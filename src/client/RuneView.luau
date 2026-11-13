--!strict
-- Runes page: blade mastery, the socket rack, and the rune shelf.
--
-- Three things happen here and they happen in order: strike with a blade to
-- raise its mastery, mastery unlocks sockets, sockets hold runes, and runes are
-- bought with Void Shards that only drop from a hot gauge.
--
-- The page is built as that chain:
--
--   bay     the blade in hand, its rank, its sockets and the live bonus
--   shelf   four rune cards in a two-by-two grid, each one a card with art
--   chain   the four steps above, printed once so the loop needs no tutorial
--
-- Everything on this screen is derived from the payload. The client never
-- decides what a rune is worth, which slot is legal, or whether a craft can be
-- afforded; it renders the server's answer and sends intents.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BladeRegistry = require(Shared:WaitForChild("BladeRegistry"))
local NumberUtil = require(Shared:WaitForChild("NumberUtil"))
local RuneConfig = require(Shared:WaitForChild("RuneConfig"))
local Types = require(Shared:WaitForChild("Types"))
local AssetManifest = require(Shared:WaitForChild("AssetManifest"))

local Theme = require(script.Parent.Theme)
local UiKit = require(script.Parent.UiKit)
local Layout = require(script.Parent.Layout)
local StateStore = require(script.Parent.StateStore)
local Sfx = require(script.Parent.Sfx)

local RuneView = {}

local HEADER_H = 58
local CHAIN_H = 112
local RANK_H = 120
local GAP = 12
local PAGE_PAD = 16
local TOP_MIN = 380
local TOP_MAX = 520

local root: Frame? = nil
local scroll: ScrollingFrame? = nil
local bay: Frame? = nil
local shelf: Frame? = nil
local chain: Frame? = nil
local rankStrip: Frame? = nil
local headerDetail: TextLabel? = nil
local relayout: (() -> ())? = nil
local rankCells: { { root: Frame, rank: TextLabel, detail: TextLabel, stroke: UIStroke } } = {}

local rankChip: TextLabel? = nil
local bladeName: TextLabel? = nil
local masteryBar: UiKit.BarParts? = nil
local masteryText: TextLabel? = nil
local socketNote: TextLabel? = nil
local socketButtons: { TextButton } = {}
local socketLabels: { TextLabel } = {}
local shardLabel: TextLabel? = nil
local bonusLabels: { [string]: TextLabel } = {}
local runeCards: { [string]: { root: Frame, count: TextLabel, handle: UiKit.ActionHandle } } = {}
local unsubscribe: (() -> ())? = nil

local function hasFreeSocket(state: Types.SyncPayload): boolean
	for index = 1, state.socketSlots do
		if (state.equippedSockets[index] or "") == "" then
			return true
		end
	end
	return false
end

--- What the button on a rune card should do right now.
local function decisionFor(state: Types.SyncPayload, runeId: string, cost: number): (string, string, Color3)
	local owned = state.runes[runeId] or 0
	if owned > 0 and hasFreeSocket(state) then
		return "socket", "SOCKET", Theme.Color.quantum
	end
	if state.shards >= cost then
		return "craft", "CRAFT", Theme.Color.aether
	end
	return "locked", "CRAFT", Theme.Color.aether
end

-- ---------------------------------------------------------------------------
-- Page shell
-- ---------------------------------------------------------------------------

local function buildPage(canvas: Frame, x: number, y: number, width: number, height: number)
	local card = UiKit.panel(canvas, {
		tier = "shell",
		radius = Theme.Radius.xl,
	})
	card.Name = "Runes"
	card.Size = UDim2.fromOffset(width, height)
	card.Position = UDim2.fromOffset(x, y)
	card.Visible = false
	card.ClipsDescendants = true
	root = card

	local body = UiKit.create("Frame", {
		Name = "Inner",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(PAGE_PAD, PAGE_PAD),
		Size = UDim2.new(1, -PAGE_PAD * 2, 1, -PAGE_PAD * 2),
	}) :: Frame
	body.Parent = card

	local header = UiKit.header(body, {
		eyebrow = "BLADE WORK  /  SOCKETS",
		title = "RUNE FORGE",
		detail = "0 SHARDS",
		height = HEADER_H,
	})
	header.Name = "RuneHeader"
	local detail = header:FindFirstChild("Detail")
	if detail and detail:IsA("TextLabel") then
		headerDetail = detail
	end

	local box = UiKit.scroll(body, { thickness = 6, transparency = 0.2 })
	box.Name = "RuneBody"
	box.Position = UDim2.fromOffset(0, HEADER_H + 2)
	box.Size = UDim2.new(1, 0, 1, -(HEADER_H + 2))
	box.AutomaticCanvasSize = Enum.AutomaticSize.None
	box.CanvasSize = UDim2.fromOffset(0, 0)
	box.ScrollingDirection = Enum.ScrollingDirection.Y
	box.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	scroll = box
end

-- ---------------------------------------------------------------------------
-- Blade bay
-- ---------------------------------------------------------------------------

local function buildBay(parent: Frame)
	local card = UiKit.panel(parent, {
		tier = "raised",
		radius = Theme.Radius.card,
	})
	card.Name = "MasteryCard"
	bay = card

	local eye = UiKit.eyebrow(card, "EQUIPPED BLADE")
	eye.Position = UDim2.fromOffset(14, 10)

	bladeName = UiKit.label(card, {
		text = "BLADE",
		size = Theme.Text.Title - 6,
		font = Theme.Font.Black,
		color = Theme.Color.starMatter,
	})
	bladeName.Position = UDim2.fromOffset(14, 28)
	bladeName.Size = UDim2.new(1, -150, 0, 30)

	rankChip = UiKit.label(card, {
		text = "RANK 0",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.gold,
		align = Enum.TextXAlignment.Right,
	})
	rankChip.Position = UDim2.new(1, -150, 0, 32)
	rankChip.Size = UDim2.fromOffset(136, 20)

	masteryBar = UiKit.bar(card, {
		height = 10,
		radius = 5,
		gradient = { Theme.Color.starMatterDeep, Theme.Color.starMatter },
	})
	masteryBar.track.Position = UDim2.fromOffset(14, 62)
	masteryBar.track.Size = UDim2.new(1, -28, 0, 10)

	masteryText = UiKit.label(card, {
		text = "",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.textSecondary,
	})
	masteryText.Position = UDim2.fromOffset(14, 78)
	masteryText.Size = UDim2.new(1, -28, 0, 18)

	local ruleA = UiKit.rule(card, { position = UDim2.fromOffset(14, 100) })
	ruleA.Size = UDim2.new(1, -28, 0, 1)

	socketNote = UiKit.eyebrow(card, "SOCKETS")
	socketNote.Position = UDim2.fromOffset(14, 106)
	socketNote.Size = UDim2.new(1, -28, 0, 14)

	local rack = UiKit.create("Frame", {
		Name = "SocketRack",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -28, 0, 70),
		Position = UDim2.fromOffset(14, 122),
	}) :: Frame
	rack.Parent = card

	for index = 1, RuneConfig.MaxSockets do
		local button = UiKit.create("TextButton", {
			Name = string.format("Socket%d", index),
			BackgroundColor3 = Theme.Color.panelSunken,
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			Size = UDim2.new(1 / 3, -8, 1, 0),
			Position = UDim2.new((index - 1) / 3, 4, 0, 0),
		}) :: TextButton
		UiKit.corner(button, Theme.Radius.sm)
		UiKit.stroke(button, Theme.Color.stroke, Theme.Stroke.thin, 0.2)
		button.Parent = rack

		local label = UiKit.label(button, {
			text = "RANK " .. tostring(index),
			size = Theme.Text.Tiny,
			font = Theme.Font.Black,
			color = Theme.Color.textSecondary,
			align = Enum.TextXAlignment.Center,
			wrap = true,
		})
		label.Size = UDim2.fromScale(1, 1)
		label.Position = UDim2.fromOffset(0, 0)

		button.Activated:Connect(function()
			StateStore.send("unsocket", { slot = index })
		end)

		socketButtons[index] = button
		socketLabels[index] = label
	end

	local ruleB = UiKit.rule(card, { position = UDim2.fromOffset(14, 198) })
	ruleB.Size = UDim2.new(1, -28, 0, 1)

	local bonusEye = UiKit.eyebrow(card, "SOCKETED BONUS")
	bonusEye.Position = UDim2.fromOffset(14, 206)
	bonusEye.Size = UDim2.new(1, -28, 0, 14)

	local cells = {
		{ key = "click", label = "STRIKE YIELD", color = Theme.Color.starMatter },
		{ key = "cool", label = "HEAT COOLING", color = Theme.Color.cyan },
		{ key = "crit", label = "CRIT CHANCE", color = Theme.Color.gold },
		{ key = "vent", label = "VENT AETHER", color = Theme.Color.aether },
	}
	for index, cell in cells do
		local column = (index - 1) % 2
		local row = (index - 1) // 2
		local cap = UiKit.eyebrow(card, cell.label, { color = Theme.Color.textFaint })
		cap.Position = UDim2.new(column * 0.5, if column == 0 then 14 else 8, 0, 224 + row * 42)
		cap.Size = UDim2.new(0.5, -22, 0, 14)
		local value = UiKit.label(card, {
			text = "+0%",
			size = Theme.Text.Subheading,
			font = Theme.Font.Numeric,
			color = cell.color,
		})
		value.Position = UDim2.new(column * 0.5, if column == 0 then 14 else 8, 0, 240 + row * 42)
		value.Size = UDim2.new(0.5, -22, 0, 22)
		bonusLabels[cell.key] = value
	end

	-- The lower bay states the rule the shelf does not: mastery is per blade.
	-- Anchored to the bottom so a tall tablet spends the air in the middle of the
	-- card, never between this note and the edge.
	local ruleC = UiKit.rule(card, { position = UDim2.new(0, 14, 1, -72) })
	ruleC.Size = UDim2.new(1, -28, 0, 1)

	local recordEye = UiKit.eyebrow(card, "BLADE RECORD")
	recordEye.Position = UDim2.new(0, 14, 1, -64)
	recordEye.Size = UDim2.new(1, -28, 0, 14)

	local recordCopy = UiKit.label(card, {
		text = "Mastery is kept per blade. Switching to another blade does not erase a rank you have already earned.",
		size = Theme.Text.Tiny,
		color = Theme.Color.textFaint,
		wrap = true,
	})
	recordCopy.Position = UDim2.new(0, 14, 1, -48)
	recordCopy.Size = UDim2.new(1, -28, 0, 38)
end

-- ---------------------------------------------------------------------------
-- Rune shelf
-- ---------------------------------------------------------------------------

local function buildRuneCard(parent: Frame, rune: RuneConfig.Rune, order: number)
	local card = UiKit.panel(parent, {
		tier = "item",
		radius = Theme.Radius.md,
	})
	card.Name = string.format("Rune_%s", rune.id)
	card.LayoutOrder = order

	local well = UiKit.badgeWell(card, {
		image = AssetManifest.uiArt(rune.icon),
		size = 64,
		accent = Theme.Color.quantum,
	})
	if well ~= nil then
		well.Position = UDim2.fromOffset(10, 10)
	end

	local name = UiKit.label(card, {
		text = rune.name,
		size = 17,
		font = Theme.Font.Black,
		color = Theme.Color.text,
	})
	name.Position = UDim2.fromOffset(86, 10)
	name.Size = UDim2.new(1, -98, 0, 24)

	local effect = UiKit.label(card, {
		text = rune.description,
		size = Theme.Text.Tiny,
		color = Theme.Color.textSecondary,
		wrap = true,
	})
	effect.Position = UDim2.fromOffset(86, 34)
	effect.Size = UDim2.new(1, -98, 0, 42)

	local count = UiKit.label(card, {
		text = "0 OWNED",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.quantum,
	})
	count.Position = UDim2.fromOffset(10, 82)
	count.Size = UDim2.new(1, -20, 0, 18)

	local handle = UiKit.actionButton(card, {
		accent = Theme.Color.quantum,
		height = 34,
		radius = Theme.Radius.sm,
		size = 13,
		label = "CRAFT",
		handler = function()
			local state = StateStore.current
			if state == nil then
				return
			end
			local action = decisionFor(state, rune.id, rune.cost)
			if action == "socket" then
				StateStore.send("socket", { rune = rune.id })
				Sfx.rune()
			elseif action == "craft" then
				StateStore.send("craftRune", { id = rune.id })
				Sfx.rune()
			end
		end,
	})
	handle.button.Name = string.format("RuneAction_%s", rune.id)
	handle.button.AnchorPoint = Vector2.new(0, 1)
	handle.button.Position = UDim2.new(0, 10, 1, -10)
	handle.button.Size = UDim2.new(1, -20, 0, 34)

	runeCards[rune.id] = { root = card, count = count, handle = handle }
end

local function buildShelf(parent: Frame)
	local card = UiKit.panel(parent, {
		tier = "item",
		radius = Theme.Radius.card,
	})
	card.Name = "RuneShelf"
	shelf = card

	local head = UiKit.label(card, {
		text = "RUNE SHELF",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.textSecondary,
	})
	head.Position = UDim2.fromOffset(14, 8)
	head.Size = UDim2.new(1, -180, 0, 16)

	shardLabel = UiKit.label(card, {
		text = "0 SHARDS",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.quantum,
		align = Enum.TextXAlignment.Right,
	})
	shardLabel.Position = UDim2.new(1, -174, 0, 8)
	shardLabel.Size = UDim2.fromOffset(160, 16)

	local grid = UiKit.create("Frame", {
		Name = "RuneGrid",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 32),
		Size = UDim2.new(1, -20, 1, -42),
	}) :: Frame
	grid.Parent = card
	UiKit.grid(grid, UDim2.new(0.5, -6, 0.5, -6), 12)

	local order = 1
	for _, rune in RuneConfig.list() do
		buildRuneCard(grid, rune, order)
		order += 1
	end
end

-- ---------------------------------------------------------------------------
-- Chain strip
-- ---------------------------------------------------------------------------

local function buildChain(parent: Frame)
	local card = UiKit.panel(parent, {
		tier = "well",
		radius = Theme.Radius.card,
		stroke = Theme.Color.quantum,
		strokeTransparency = 0.7,
	})
	card.Name = "RuneChain"
	chain = card

	local steps = {
		{ "01", "STRIKE", "Every strike with this blade adds one mastery point." },
		{ "02", "RANK UP", "Ranks unlock sockets. Rank 1 opens the first." },
		{ "03", "SOCKET", "Click an empty socket to seat a rune you already own." },
		{ "04", "CRAFT", "Hot vents drop Void Shards. Spend them on the shelf." },
	}

	for index, step in steps do
		local cell = UiKit.create("Frame", {
			Name = string.format("Step%d", index),
			BackgroundTransparency = 1,
			Position = UDim2.fromScale((index - 1) / 4, 0),
			Size = UDim2.fromScale(1 / 4, 1),
		}) :: Frame
		cell.Parent = card

		if index > 1 then
			local divider = UiKit.create("Frame", {
				BackgroundColor3 = Theme.Color.stroke,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(-1, 14),
				Size = UDim2.new(0, 1, 1, -28),
			}) :: Frame
			divider.Parent = cell
		end

		local number = UiKit.label(cell, {
			text = step[1],
			size = Theme.Text.Tiny,
			font = Theme.Font.Numeric,
			color = Theme.Color.quantum,
		})
		number.Position = UDim2.fromOffset(16, 10)
		number.Size = UDim2.fromOffset(24, 16)

		local title = UiKit.label(cell, {
			text = step[2],
			size = Theme.Text.Tiny,
			font = Theme.Font.Black,
			color = Theme.Color.text,
		})
		title.Position = UDim2.fromOffset(46, 10)
		title.Size = UDim2.new(1, -56, 0, 16)

		local copy = UiKit.label(cell, {
			text = step[3],
			size = Theme.Text.Tiny,
			color = Theme.Color.textFaint,
			wrap = true,
		})
		copy.Position = UDim2.fromOffset(16, 34)
		copy.Size = UDim2.new(1, -30, 0, 56)
	end
end

-- ---------------------------------------------------------------------------
-- Rank ladder
-- ---------------------------------------------------------------------------

--- Five ranks, the strikes each one takes, and what it opens. The bay shows the
--- current bar; this strip shows the whole road, so a player can see rank 3 is a
--- second socket rather than another number.
local function buildRankStrip(parent: Frame)
	local card = UiKit.panel(parent, {
		tier = "item",
		radius = Theme.Radius.card,
	})
	card.Name = "RankLadder"
	rankStrip = card

	local head = UiKit.label(card, {
		text = "MASTERY LADDER",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.textSecondary,
	})
	head.Position = UDim2.fromOffset(14, 8)
	head.Size = UDim2.new(1, -200, 0, 16)

	local rule = UiKit.label(card, {
		text = "EACH RANK KEEPS PER BLADE",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Right,
	})
	rule.Position = UDim2.new(1, -210, 0, 8)
	rule.Size = UDim2.fromOffset(196, 16)

	for index, threshold in RuneConfig.Thresholds do
		local cell = UiKit.create("Frame", {
			Name = string.format("RankCell%d", index),
			BackgroundColor3 = Theme.Color.panelSunken,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Position = UDim2.new((index - 1) / 5, 8, 0, 32),
			Size = UDim2.new(1 / 5, -10, 0, 76),
		}) :: Frame
		UiKit.corner(cell, Theme.Radius.sm)
		local stroke = UiKit.stroke(cell, Theme.Color.stroke, 1, 0.4)
		cell.Parent = card

		local rank = UiKit.label(cell, {
			text = string.format("RANK %d", index),
			size = Theme.Text.Tiny,
			font = Theme.Font.Black,
			color = Theme.Color.textFaint,
		})
		rank.Position = UDim2.fromOffset(10, 8)
		rank.Size = UDim2.new(1, -20, 0, 16)

		local detail = UiKit.label(cell, {
			text = string.format("%s STRIKES", NumberUtil.abbreviate(threshold)),
			size = Theme.Text.Tiny,
			font = Theme.Font.Numeric,
			color = Theme.Color.textSecondary,
		})
		detail.Position = UDim2.fromOffset(10, 26)
		detail.Size = UDim2.new(1, -20, 0, 16)

		local before = RuneConfig.socketsFor(index - 1)
		local after = RuneConfig.socketsFor(index)
		local opens = if after > before
			then string.format("SOCKET %d OPENS", after)
			else "NO NEW SOCKET"
		local note = UiKit.label(cell, {
			text = opens,
			size = Theme.Text.Tiny,
			font = Theme.Font.Black,
			color = if after > before then Theme.Color.quantum else Theme.Color.textFaint,
		})
		note.Position = UDim2.fromOffset(10, 46)
		note.Size = UDim2.new(1, -20, 0, 16)

		table.insert(rankCells, { root = cell, rank = rank, detail = detail, stroke = stroke })
	end
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

relayout = function()
	if root == nil or scroll == nil or bay == nil or shelf == nil then
		return
	end

	local bodyW = Layout.CONTENT_W - PAGE_PAD * 2 - 8
	local viewH = Layout.CONTENT_H - PAGE_PAD * 2 - HEADER_H - 2
	local topH = math.clamp(
		Layout.CONTENT_H - PAGE_PAD * 2 - HEADER_H - CHAIN_H - RANK_H - GAP * 3,
		TOP_MIN,
		TOP_MAX
	)
	local wide = bodyW >= 900

	if wide then
		local bayW = math.floor(bodyW * 0.42)
		bay.Size = UDim2.fromOffset(bayW, topH)
		bay.Position = UDim2.fromOffset(0, 0)
		shelf.Size = UDim2.fromOffset(bodyW - bayW - GAP, topH)
		shelf.Position = UDim2.fromOffset(bayW + GAP, 0)
	else
		bay.Size = UDim2.fromOffset(bodyW, topH)
		bay.Position = UDim2.fromOffset(0, 0)
		shelf.Size = UDim2.fromOffset(bodyW, topH)
		shelf.Position = UDim2.fromOffset(0, topH + GAP)
	end

	local chainY = if wide then topH + GAP else topH * 2 + GAP * 2
	if chain then
		chain.Size = UDim2.fromOffset(bodyW, CHAIN_H)
		chain.Position = UDim2.fromOffset(0, chainY)
	end

	local rankY = chainY + CHAIN_H + GAP
	if rankStrip then
		rankStrip.Size = UDim2.fromOffset(bodyW, RANK_H)
		rankStrip.Position = UDim2.fromOffset(0, rankY)
	end

	local contentH = math.max(viewH, rankY + RANK_H)
	scroll.CanvasSize = UDim2.fromOffset(0, contentH)
end

function RuneView.layout()
	if root == nil then
		return
	end
	root.Size = UDim2.fromOffset(Layout.CONTENT_W, Layout.CONTENT_H)
	root.Position = UDim2.fromOffset(Layout.CONTENT_X, Layout.CONTENT_Y)
	if relayout then
		relayout()
	end
end

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------

function RuneView.init(canvas: Frame, x: number, y: number, width: number, height: number)
	buildPage(canvas, x, y, width, height)
	local body = scroll
	if body == nil then
		return
	end

	buildBay(body)
	buildShelf(body)
	buildChain(body)
	buildRankStrip(body)

	if relayout then
		relayout()
	end

	unsubscribe = StateStore.onSync(function(payload: Types.SyncPayload)
		RuneView.render(payload)
	end)

	local current = StateStore.current
	if current then
		RuneView.render(current)
	end
end

function RuneView.card(): Frame?
	return root
end

-- ---------------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------------

function RuneView.render(payload: Types.SyncPayload)
	local blade = BladeRegistry.get(payload.equipped)

	if headerDetail then
		headerDetail.Text = string.format("%d SHARDS", payload.shards)
	end

	if bladeName then
		bladeName.Text = if blade then string.upper(blade.name) else "UNKNOWN BLADE"
		bladeName.TextColor3 = Theme.rarityColor(if blade then blade.tier else 1)
	end

	if rankChip then
		rankChip.Text = string.format("RANK %d / %d", payload.mastery, #RuneConfig.Thresholds)
		rankChip.TextColor3 = if payload.mastery > 0 then Theme.Color.gold else Theme.Color.textFaint
	end

	for index, cell in rankCells do
		local earned = payload.mastery >= index
		local nextRank = payload.mastery + 1 == index and payload.masteryNext ~= nil
		cell.root.BackgroundColor3 = if earned
			then Theme.Color.quantumDeep
			elseif nextRank then Theme.Color.panelRaised
			else Theme.Color.panelSunken
		cell.root.BackgroundTransparency = if earned then 0.72 elseif nextRank then 0 else 0.35
		cell.rank.TextColor3 = if earned
			then Theme.Color.quantum
			elseif nextRank then Theme.Color.text
			else Theme.Color.textFaint
		cell.detail.TextColor3 = if earned or nextRank then Theme.Color.textSecondary else Theme.Color.textFaint
		cell.stroke.Color = if earned
			then Theme.Color.quantum
			elseif nextRank then Theme.Color.quantum
			else Theme.Color.stroke
		cell.stroke.Transparency = if earned then 0.55 elseif nextRank then 0 else 0.4
	end

	if masteryBar and masteryText then
		local rank = payload.mastery
		local floorValue = if rank > 0 then RuneConfig.Thresholds[rank] else 0
		local ceiling = payload.masteryNext
		if ceiling == nil then
			masteryBar.set(1)
			masteryText.Text = string.format("%s STRIKES  ·  MASTERED", NumberUtil.abbreviate(payload.masteryXp))
		else
			local span = math.max(1, ceiling - floorValue)
			masteryBar.set(math.clamp((payload.masteryXp - floorValue) / span, 0, 1))
			masteryText.Text = string.format(
				"%s / %s STRIKES TO RANK %d",
				NumberUtil.abbreviate(payload.masteryXp),
				NumberUtil.abbreviate(ceiling),
				rank + 1
			)
		end
	end

	if socketNote then
		socketNote.Text = string.format("SOCKETS  %d OF %d UNLOCKED", payload.socketSlots, RuneConfig.MaxSockets)
	end

	for index, button in socketButtons do
		local label = socketLabels[index]
		local runeId = payload.equippedSockets[index] or ""
		local unlocked = index <= payload.socketSlots
		local rune = if unlocked and runeId ~= "" then RuneConfig.get(runeId) else nil

		if label then
			if rune then
				label.Text = string.upper(rune.name)
				label.TextColor3 = Theme.Color.white
			elseif unlocked then
				label.Text = "EMPTY\nADD RUNE"
				label.TextColor3 = Theme.Color.textSecondary
			else
				local needed = 0
				for rank = 1, #RuneConfig.Thresholds do
					if RuneConfig.socketsFor(rank) >= index and needed == 0 then
						needed = rank
					end
				end
				label.Text = string.format("RANK %d", needed)
				label.TextColor3 = Theme.Color.locked
			end
		end

		button.BackgroundColor3 = if rune then Theme.Color.quantumDeep else Theme.Color.panelSunken
		button.BackgroundTransparency = if rune then 0.05 else 0.35
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if rune then Theme.Color.quantum else Theme.Color.stroke
			stroke.Transparency = if rune then 0 else 0.4
		end
	end

	if shardLabel then
		shardLabel.Text = string.format("%d VOID SHARDS", payload.shards)
		shardLabel.TextColor3 = if payload.shards > 0 then Theme.Color.quantum else Theme.Color.textFaint
	end


	-- The sum of every socketed rune, which is the number the shelf is selling.
	-- `NONE` rather than `+0%`: a live meter reading zero is a broken meter.
	local bonus = RuneConfig.sum(payload.equippedSockets)
	local function bonusText(mult: number): string
		local points = math.floor((mult - 1) * 100 + 0.5)
		return if points > 0 then string.format("+%d%%", points) else "NONE"
	end
	for key, label in bonusLabels do
		if key == "crit" then
			local points = math.floor(bonus.critChance * 100 + 0.5)
			label.Text = if points > 0 then string.format("+%d%%", points) else "NONE"
		elseif key == "click" then
			label.Text = bonusText(bonus.clickMult)
		elseif key == "cool" then
			label.Text = bonusText(bonus.coolMult)
		elseif key == "vent" then
			label.Text = bonusText(bonus.ventMult)
		end
		label.TextTransparency = if label.Text == "NONE" then 0.55 else 0
	end

	for _, rune in RuneConfig.list() do
		local card = runeCards[rune.id]
		if card then
			local owned = payload.runes[rune.id] or 0
			card.count.Text = string.format("%d OWNED  ·  %d SHARDS", owned, rune.cost)
			card.count.TextColor3 = if owned > 0 then Theme.Color.quantum else Theme.Color.textFaint

			local action, text, accent = decisionFor(payload, rune.id, rune.cost)
			card.handle.set(
				if action == "locked" then "locked" else "ready",
				text,
				accent
			)
		end
	end
end

function RuneView.destroy()
	if unsubscribe then
		unsubscribe()
		unsubscribe = nil
	end
	if root then
		root:Destroy()
		root = nil
	end
	scroll = nil
	bay = nil
	shelf = nil
	chain = nil
	rankStrip = nil
	table.clear(rankCells)
	headerDetail = nil
	rankChip = nil
	bladeName = nil
	masteryBar = nil
	masteryText = nil
	socketNote = nil
	shardLabel = nil
	table.clear(bonusLabels)
	table.clear(socketButtons)
	table.clear(socketLabels)
	table.clear(runeCards)
	relayout = nil
end

return RuneView
