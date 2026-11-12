--!strict
-- The server roster: every player in this server, ranked by lifetime
-- Star-Matter, with a card for the selected one.
--
-- This is the flex surface. The global boards answer "who is the best in the
-- world"; this panel answers "who is here right now" and shows the blade those
-- players actually forged. The server builds the public slice, so the client
-- never sees settings, purchases or trade state.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BladeRegistry = require(Shared:WaitForChild("BladeRegistry"))
local ForgeConfig = require(Shared:WaitForChild("ForgeConfig"))
local NumberUtil = require(Shared:WaitForChild("NumberUtil"))

local Theme = require(script.Parent.Theme)
local UiKit = require(script.Parent.UiKit)
local ModalShell = require(script.Parent.ModalShell)
local BladePreview = require(script.Parent.BladePreview)
local StateStore = require(script.Parent.StateStore)
local Sfx = require(script.Parent.Sfx)

local PlayersView = {}

local REFRESH_SECONDS = 10
local ROW_H = 64
local LIST_W = 292
local DETAIL_X = 324
local STAGE_W = 260

local shell: ModalShell.Handle? = nil
local listHost: ScrollingFrame? = nil
local detailHost: Frame? = nil
local selectedUserId = 0
local lastData: any = nil
local lastSignature = ""
local refreshClock = 0
local loading = false
local bladeCleanup: (() -> ())? = nil
local cheerUserId = 0
local cheerUntil = 0

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function clearDetail()
	if bladeCleanup then
		bladeCleanup()
		bladeCleanup = nil
	end
	if detailHost then
		ModalShell.clear(detailHost)
	end
end

local function selectedEntry(): any?
	if type(lastData) ~= "table" or type(lastData.players) ~= "table" then
		return nil
	end
	for _, entry in lastData.players do
		if entry.userId == selectedUserId then
			return entry
		end
	end
	return nil
end

local function rankOf(userId: number): (number, number)
	if type(lastData) ~= "table" or type(lastData.players) ~= "table" then
		return 0, 0
	end
	for index, entry in lastData.players do
		if entry.userId == userId then
			return index, #lastData.players
		end
	end
	return 0, #lastData.players
end

--- A head shot when the thumbnail service answers, a coloured initial when it
--- does not. The fallback is already painted, so a failed request costs a pixel
--- and never a hole.
local function avatar(parent: GuiObject, x: number, y: number, size: number, userId: number, name: string)
	local plate = UiKit.create("Frame", {
		Name = "Avatar",
		BackgroundColor3 = Theme.Color.slate,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(size, size),
		ZIndex = 2,
	}) :: Frame
	UiKit.corner(plate, size / 2)
	UiKit.stroke(plate, Theme.Color.stroke, Theme.Stroke.thin, 0.2)
	plate.Parent = parent

	local initial = string.upper(string.sub(name, 1, 1))
	local fallback = UiKit.label(plate, {
		text = if initial ~= "" then initial else "?",
		size = math.max(Theme.Text.Small, math.floor(size * 0.4)),
		font = Theme.Font.Black,
		color = Theme.Color.textSecondary,
		align = Enum.TextXAlignment.Center,
	})
	fallback.Size = UDim2.fromScale(1, 1)
	fallback.ZIndex = 3

	task.spawn(function()
		local ok, url = pcall(function()
			return Players:GetUserThumbnailAsync(
				userId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size100x100
			)
		end)
		if not ok or type(url) ~= "string" or url == "" or not plate.Parent then
			return
		end
		local image = UiKit.create("ImageLabel", {
			Name = "Head",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			Image = url,
			ScaleType = Enum.ScaleType.Crop,
			ZIndex = 4,
		}) :: ImageLabel
		UiKit.corner(image, size / 2)
		image.Parent = plate
	end)
end

-- ---------------------------------------------------------------------------
-- List
-- ---------------------------------------------------------------------------

local function paintEmpty(message: string)
	local host = listHost
	if host == nil then
		return
	end
	ModalShell.clear(host)
	if detailHost then
		clearDetail()
		local empty = UiKit.label(detailHost, {
			text = message,
			size = Theme.Text.Small,
			font = Theme.Font.Black,
			color = Theme.Color.textFaint,
			align = Enum.TextXAlignment.Center,
		})
		empty.Position = UDim2.fromOffset(0, 120)
		empty.Size = UDim2.new(1, 0, 0, 40)
	end
end

local function paintRow(entry: any, order: number)
	local host = listHost
	if host == nil then
		return
	end
	local selected = entry.userId == selectedUserId
	local you = lastData ~= nil and entry.userId == lastData.you
	local row = UiKit.create("TextButton", {
		Name = string.format("PlayerRow_%d", entry.userId),
		BackgroundColor3 = if selected then Theme.Color.panelRaised else Theme.Color.panel,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.new(1, -8, 0, ROW_H),
		LayoutOrder = order,
		ZIndex = 2,
	}) :: TextButton
	UiKit.corner(row, Theme.Radius.sm)
	UiKit.stroke(
		row,
		if selected then Theme.Color.cyan else Theme.Color.strokeFaint,
		if selected then Theme.Stroke.thin else Theme.Stroke.thin,
		if selected then 0 else 0.45
	)
	row.Parent = host

	avatar(row, 8, 12, 40, entry.userId, tostring(entry.name or "?"))

	local name = UiKit.label(row, {
		text = tostring(entry.name or "?"),
		size = Theme.Text.Small,
		font = Theme.Font.Heading,
		color = if selected then Theme.Color.text else Theme.Color.textSecondary,
		align = Enum.TextXAlignment.Left,
	})
	name.Position = UDim2.fromOffset(56, 10)
	name.Size = UDim2.new(1, -112, 0, 20)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.ZIndex = 3

	local score = UiKit.label(row, {
		text = string.format("%s SM", NumberUtil.compact(tonumber(entry.lifetimeSm) or 0)),
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = if selected then Theme.Color.cyan else Theme.Color.textFaint,
		align = Enum.TextXAlignment.Left,
	})
	score.Position = UDim2.fromOffset(56, 32)
	score.Size = UDim2.new(1, -112, 0, 18)
	score.ZIndex = 3

	if you then
		local tag = UiKit.badge(row, {
			text = "YOU",
			color = Theme.Color.cyan,
			width = 40,
			height = 18,
			size = Theme.Text.Tiny,
			textColor = Theme.Color.ink,
		})
		tag.Name = "YouTag"
		tag.AnchorPoint = Vector2.new(1, 0)
		tag.Position = UDim2.new(1, -8, 0, 8)
		tag.ZIndex = 3
	end

	local place = UiKit.label(row, {
		text = tostring(order),
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = if order <= 3 then Theme.Color.gold else Theme.Color.textDim,
		align = Enum.TextXAlignment.Right,
	})
	place.AnchorPoint = Vector2.new(1, 1)
	place.Position = UDim2.new(1, -8, 1, -6)
	place.Size = UDim2.fromOffset(26, 18)
	place.ZIndex = 3

	row.Activated:Connect(function()
		if selectedUserId == entry.userId then
			return
		end
		selectedUserId = entry.userId
		Sfx.tab()
		lastSignature = ""
		PlayersView.refresh()
	end)
	row.MouseEnter:Connect(function()
		Sfx.hover()
	end)
end

-- ---------------------------------------------------------------------------
-- Detail
-- ---------------------------------------------------------------------------

local function statCell(parent: Frame, x: number, y: number, label: string, value: string, accent: Color3)
	local caption = UiKit.label(parent, {
		text = label,
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Left,
	})
	caption.Position = UDim2.fromOffset(x, y)
	caption.Size = UDim2.fromOffset(140, 16)
	caption.ZIndex = 3

	local figure = UiKit.label(parent, {
		text = value,
		size = Theme.Text.Subheading,
		font = Theme.Font.Numeric,
		color = accent,
		align = Enum.TextXAlignment.Left,
	})
	figure.Position = UDim2.fromOffset(x, y + 18)
	figure.Size = UDim2.fromOffset(150, 24)
	figure.ZIndex = 3
end

local function paintDetail(entry: any)
	local host = detailHost
	if host == nil then
		return
	end
	clearDetail()

	local rank, total = rankOf(entry.userId)
	local you = lastData ~= nil and entry.userId == lastData.you
	local top = if type(entry.top) == "table" then entry.top else {}
	local best = top[1]
	local blade = if best ~= nil then BladeRegistry.get(best.id) else nil
	local variant = if best ~= nil then ForgeConfig.variant(best.variant) else nil
	local accent = if variant ~= nil then variant.color else Theme.Color.gold

	-- The blade stage. The same preview the forge, vault and crate use, so the
	-- thing being flexed is the thing the other player actually swings.
	local stage = UiKit.create("ViewportFrame", {
		Name = "PlayerStage",
		BackgroundColor3 = Theme.Color.panelSunken,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(18, 16),
		Size = UDim2.fromOffset(STAGE_W, 310),
		ZIndex = 1,
	}) :: ViewportFrame
	stage.ClipsDescendants = true
	UiKit.corner(stage, Theme.Radius.md)
	UiKit.stroke(stage, accent, Theme.Stroke.thin, 0.35)
	stage.Parent = host

	-- A soft disc behind the model so the stage reads as a lit room rather than
	-- a black rectangle.
	local glow = UiKit.create("Frame", {
		Name = "Glow",
		BackgroundColor3 = accent,
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.56),
		Size = UDim2.fromOffset(190, 190),
		ZIndex = 1,
	}) :: Frame
	UiKit.corner(glow, 95)
	glow.Parent = stage

	if blade ~= nil then
		bladeCleanup = BladePreview.mount(stage, blade, accent, {
			frameFill = 0.78,
			aimBias = 0,
			spin = 0.8,
			surface = host,
		})
	end

	local plate = UiKit.label(host, {
		text = if blade ~= nil then string.upper(blade.name) else "NO BLADE YET",
		size = Theme.Text.Small,
		font = Theme.Font.Black,
		color = if blade ~= nil then Theme.Color.text else Theme.Color.textFaint,
		align = Enum.TextXAlignment.Center,
	})
	plate.Name = "StageName"
	plate.AnchorPoint = Vector2.new(0.5, 1)
	plate.Position = UDim2.fromOffset(18 + STAGE_W / 2, 316)
	plate.Size = UDim2.fromOffset(STAGE_W - 16, 18)
	plate.ZIndex = 3

	local name = UiKit.label(host, {
		text = tostring(entry.name or "?"),
		size = 30,
		font = Theme.Font.Black,
		color = Theme.Color.text,
		align = Enum.TextXAlignment.Left,
	})
	name.Position = UDim2.fromOffset(300, 16)
	name.Size = UDim2.new(1, -318, 0, 38)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.ZIndex = 3

	local handle = UiKit.label(host, {
		text = "@" .. tostring(entry.handle or ""),
		size = Theme.Text.Tiny,
		font = Theme.Font.Label,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Left,
	})
	handle.Position = UDim2.fromOffset(300, 52)
	handle.Size = UDim2.fromOffset(240, 16)
	handle.ZIndex = 3

	local rankChip = UiKit.badge(host, {
		text = string.format("#%d OF %d", rank, math.max(1, total)),
		color = if you then Theme.Color.cyan else Theme.Color.gold,
		width = 104,
		height = 20,
		size = Theme.Text.Tiny,
		textColor = Theme.Color.ink,
	})
	rankChip.Position = UDim2.fromOffset(300, 76)
	rankChip.ZIndex = 3

	local playtime = UiKit.label(host, {
		text = string.format("PLAYED %s", NumberUtil.abbreviateTime(tonumber(entry.playtime) or 0)),
		size = Theme.Text.Tiny,
		font = Theme.Font.Label,
		color = Theme.Color.textDim,
		align = Enum.TextXAlignment.Right,
	})
	playtime.AnchorPoint = Vector2.new(1, 0)
	playtime.Position = UDim2.new(1, -18, 0, 82)
	playtime.Size = UDim2.fromOffset(220, 16)
	playtime.ZIndex = 3

	local rule = UiKit.create("Frame", {
		Name = "Rule",
		BackgroundColor3 = Theme.Color.strokeFaint,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(300, 104),
		Size = UDim2.new(1, -318, 0, 1),
		ZIndex = 2,
	}) :: Frame
	rule.Parent = host

	statCell(host, 300, 118, "STAR-MATTER", NumberUtil.compact(tonumber(entry.sm) or 0), Theme.Color.starMatter)
	statCell(host, 460, 118, "LIFETIME", NumberUtil.compact(tonumber(entry.lifetimeSm) or 0), Theme.Color.gold)
	statCell(host, 300, 174, "AETHER", NumberUtil.compact(tonumber(entry.aether) or 0), Theme.Color.aether)
	statCell(host, 460, 174, "DRONES", NumberUtil.compact(tonumber(entry.drones) or 0), Theme.Color.cyan)
	statCell(host, 300, 230, "ASCENSIONS", NumberUtil.compact(tonumber(entry.ascensions) or 0), Theme.Color.quantum)
	statCell(host, 460, 230, "COPIES", NumberUtil.compact(tonumber(entry.invCount) or 0), Theme.Color.textSecondary)

	-- The top three blades. This is the row that makes the panel a flex rather
	-- than a stat sheet: names and multipliers, in the same shorthand the vault
	-- uses.
	local shelf = UiKit.create("Frame", {
		Name = "TopBlades",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(18, 350),
		Size = UDim2.new(1, -36, 0, 86),
		ZIndex = 2,
	}) :: Frame
	shelf.Parent = host

	for index = 1, 3 do
		local pick = top[index]
		if pick ~= nil then
			local pickBlade = BladeRegistry.get(pick.id)
			local pickVariant = ForgeConfig.variant(pick.variant)
			local pickAccent = if pickVariant ~= nil then pickVariant.color else Theme.Color.gold
			local card = UiKit.panel(shelf, {
				tier = "well",
				radius = Theme.Radius.sm,
				stroke = Theme.Color.strokeFaint,
				bevel = false,
				lip = false,
			})
			card.Name = string.format("TopBlade_%d", index)
			card.Position = UDim2.fromOffset((index - 1) * 202, 0)
			card.Size = UDim2.fromOffset(194, 84)
			card.ZIndex = 2

			local edge = UiKit.create("Frame", {
				Name = "Edge",
				BackgroundColor3 = pickAccent,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(1, 10),
				Size = UDim2.fromOffset(3, 64),
				ZIndex = 3,
			}) :: Frame
			UiKit.corner(edge, 1)
			edge.Parent = card

			local title = UiKit.label(card, {
				text = if pickBlade ~= nil then string.upper(pickBlade.name) else "UNKNOWN",
				size = Theme.Text.Tiny,
				font = Theme.Font.Black,
				color = Theme.Color.textSecondary,
				align = Enum.TextXAlignment.Left,
			})
			title.Position = UDim2.fromOffset(14, 10)
			title.Size = UDim2.new(1, -24, 0, 18)
			title.TextTruncate = Enum.TextTruncate.AtEnd
			title.ZIndex = 3

			local power = UiKit.label(card, {
				text = NumberUtil.abbreviateMultiplier(tonumber(pick.power) or 1),
				size = Theme.Text.Subheading,
				font = Theme.Font.Numeric,
				color = pickAccent,
				align = Enum.TextXAlignment.Left,
			})
			power.Position = UDim2.fromOffset(14, 36)
			power.Size = UDim2.new(1, -24, 0, 26)
			power.ZIndex = 3

			local variantLabel = UiKit.label(card, {
				text = if pickVariant ~= nil then string.upper(pickVariant.name) else "",
				size = Theme.Text.Tiny,
				font = Theme.Font.Label,
				color = Theme.Color.textFaint,
				align = Enum.TextXAlignment.Left,
			})
			variantLabel.Position = UDim2.fromOffset(14, 62)
			variantLabel.Size = UDim2.new(1, -24, 0, 14)
			variantLabel.ZIndex = 3
		end
	end

	if you then
		local tag = UiKit.label(host, {
			text = "THIS IS YOU",
			size = Theme.Text.Tiny,
			font = Theme.Font.Black,
			color = Theme.Color.textFaint,
			align = Enum.TextXAlignment.Left,
		})
		tag.Position = UDim2.fromOffset(300, 314)
		tag.Size = UDim2.fromOffset(160, 18)
		tag.ZIndex = 3
	else
		local cheer = UiKit.button(host, {
			text = if cheerUserId == entry.userId and os.clock() < cheerUntil then "CHEERED" else "CHEER",
			height = 40,
			radius = Theme.Radius.sm,
			size = Theme.Text.Small,
			font = Theme.Font.Black,
			textColor = Theme.Color.ink,
			fill = Theme.Color.cyan,
			stroke = Theme.Color.outline,
			handler = function()
				if cheerUserId == entry.userId and os.clock() < cheerUntil then
					return
				end
				cheerUserId = entry.userId
				cheerUntil = os.clock() + 3
				StateStore.send("cheer", entry.userId)
				Sfx.ui()
				lastSignature = ""
				PlayersView.refresh()
			end,
		})
		cheer.Name = "CheerButton"
		cheer.Position = UDim2.fromOffset(300, 310)
		cheer.Size = UDim2.fromOffset(160, 40)
		cheer.ZIndex = 3
	end

	local hint = UiKit.label(host, {
		text = "TAP A PLAYER TO SEE THEIR BEST BLADE",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Left,
	})
	hint.Position = UDim2.fromOffset(18, 448)
	hint.Size = UDim2.new(1, -36, 0, 16)
	hint.ZIndex = 3
end

-- ---------------------------------------------------------------------------
-- Paint
-- ---------------------------------------------------------------------------

function PlayersView.refresh()
	if shell == nil or not shell.isOpen() or loading then
		return
	end
	loading = true
	local host = listHost
	if host ~= nil and #host:GetChildren() == 0 then
		local waitLabel = UiKit.label(host, {
			text = "READING THE ROOM…",
			size = Theme.Text.Tiny,
			font = Theme.Font.Black,
			color = Theme.Color.textFaint,
			align = Enum.TextXAlignment.Center,
		})
		waitLabel.Size = UDim2.new(1, 0, 0, 40)
	end

	task.spawn(function()
		local data = StateStore.request("roster")
		loading = false
		if shell == nil or not shell.isOpen() then
			return
		end
		if type(data) ~= "table" or type(data.players) ~= "table" or #data.players == 0 then
			if lastData == nil then
				lastSignature = ""
				paintEmpty("SERVER LIST UNAVAILABLE")
			end
			return
		end
		lastData = data
		local found = false
		for _, entry in data.players do
			if entry.userId == selectedUserId then
				found = true
				break
			end
		end
		if not found then
			selectedUserId = tonumber(data.you) or data.players[1].userId
		end

		local signature = tostring(selectedUserId)
		for _, entry in data.players do
			local top = entry.top
			local mark = if type(top) == "table" and top[1] ~= nil
				then string.format("%s/%s", tostring(top[1].id), tostring(top[1].variant))
				else "-"
			signature ..= string.format(
				"|%d:%s:%s:%s:%s:%s:%s:%s:%s",
				entry.userId,
				tostring(entry.name),
				tostring(entry.lifetimeSm),
				tostring(entry.sm),
				tostring(entry.aether),
				tostring(entry.drones),
				tostring(entry.ascensions),
				tostring(entry.invCount),
				mark
			)
		end
		if signature == lastSignature then
			return
		end
		lastSignature = signature

		local hostNow = listHost
		if hostNow == nil then
			return
		end
		local scrollY = hostNow.CanvasPosition.Y
		ModalShell.clear(hostNow)
		for order, entry in data.players do
			paintRow(entry, order)
		end
		hostNow.CanvasPosition = Vector2.new(0, scrollY)

		local entry = selectedEntry()
		if entry ~= nil then
			paintDetail(entry)
		end
		if #data.players == 1 then
			local only = UiKit.label(hostNow, {
				text = "NO ONE ELSE HERE YET",
				size = Theme.Text.Tiny,
				font = Theme.Font.Black,
				color = Theme.Color.textFaint,
				align = Enum.TextXAlignment.Center,
			})
			only.Size = UDim2.new(1, 0, 0, 34)
			only.Position = UDim2.fromOffset(0, ROW_H + 18)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function PlayersView.open()
	local handle = shell
	if handle == nil or handle.isOpen() then
		return
	end
	selectedUserId = 0
	lastSignature = ""
	handle.open()
	PlayersView.refresh()
	refreshClock = 0
end

function PlayersView.close()
	if shell then
		shell.close()
	end
end

function PlayersView.isOpen(): boolean
	return shell ~= nil and shell.isOpen()
end

function PlayersView.select(userId: number): boolean
	if type(lastData) ~= "table" or type(lastData.players) ~= "table" then
		return false
	end
	for _, entry in lastData.players do
		if entry.userId == userId then
			selectedUserId = userId
			lastSignature = ""
			PlayersView.refresh()
			return true
		end
	end
	return false
end

function PlayersView.step(dt: number)
	if shell == nil or not shell.isOpen() then
		return
	end
	refreshClock += dt
	if refreshClock < REFRESH_SECONDS then
		return
	end
	refreshClock = 0
	PlayersView.refresh()
end

function PlayersView.init(canvas: Frame)
	if shell then
		return
	end

	local handle = ModalShell.build(canvas, {
		name = "PlayersOverlay",
		title = "IN THIS SERVER",
		subtitle = "",
		accent = Theme.Color.cyan,
		width = 980,
		height = 640,
		onClose = function()
			clearDetail()
			lastData = nil
			lastSignature = ""
		end,
	}, 50)
	shell = handle

	local list = UiKit.scroll(handle.body)
	list.Name = "PlayerList"
	list.Position = UDim2.fromOffset(16, 14)
	list.Size = UDim2.fromOffset(LIST_W, 558)
	list.ZIndex = 2
	UiKit.vlist(list, { gap = 6, padTop = 4, padBottom = 4 })
	listHost = list

	local detail = UiKit.create("Frame", {
		Name = "PlayerDetail",
		BackgroundColor3 = Theme.Color.panel,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(DETAIL_X, 14),
		Size = UDim2.new(1, -DETAIL_X - 16, 0, 558),
		ZIndex = 1,
	}) :: Frame
	UiKit.corner(detail, Theme.Radius.md)
	UiKit.stroke(detail, Theme.Color.strokeFaint, Theme.Stroke.thin, 0.2)
	detail.Parent = handle.body
	detailHost = detail
end

function PlayersView.destroy()
	clearDetail()
	if shell then
		shell.destroy()
		shell = nil
	end
	listHost = nil
	detailHost = nil
	lastData = nil
	lastSignature = ""
end

return PlayersView
