--!strict
-- Fleet page: the drone ladder, the live hull preview, and the fleet services.
--
-- Drones are the idle half of the economy. The ladder is hard-coded: five rungs,
-- each with its own hull, yield and price curve, and no ceiling. A player buys
-- the rung they can afford, the rung above opens on fleet size, and the numbers
-- climb into the millions. That staircase is the point of the tab.
--
-- This is a page, not a panel of rows. The hangar reads as one composition:
--
--   masthead   the fleet name and the live drone count
--   top row    the 3D hull on the left, the hull rack and buy keys on the right
--   deck       expedition, salvage and the sigil codex as three service cards
--   notes      three rules of the idle loop, in the order they matter
--
-- Everything under the masthead scrolls as one body. Fixed card heights mean a
-- number changing never moves a card under the pointer.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local NumberUtil = require(Shared:WaitForChild("NumberUtil"))
local DroneRegistry = require(Shared:WaitForChild("DroneRegistry"))
local AssetManifest = require(Shared:WaitForChild("AssetManifest"))
local SalvageConfig = require(Shared:WaitForChild("SalvageConfig"))
local ExpeditionConfig = require(Shared:WaitForChild("ExpeditionConfig"))
local MonetizationConfig = require(Shared:WaitForChild("MonetizationConfig"))
local Types = require(Shared:WaitForChild("Types"))

local Theme = require(script.Parent.Theme)
local UiKit = require(script.Parent.UiKit)
local Layout = require(script.Parent.Layout)
local StageBackdrop = require(script.Parent.StageBackdrop)
local StateStore = require(script.Parent.StateStore)
local DroneModelBuilder = require(script.Parent.DroneModelBuilder)
local Sfx = require(script.Parent.Sfx)

local DroneView = {}

local HEADER_H = 58
local HERO_H = 300
local RACK_H = 300
local SERVICE_H = 300
local NOTES_H = 102
local PAGE_PAD = 16
local GAP = 12

local root: Frame? = nil
local scroll: ScrollingFrame? = nil
local hero: Frame? = nil
local rack: Frame? = nil
local notes: Frame? = nil
local expeditionCard: Frame? = nil
local salvageCard: Frame? = nil
local codexCard: Frame? = nil
local headerDetail: TextLabel? = nil

local viewport: ViewportFrame? = nil
local tierNameLabel: TextLabel? = nil
local tierOwnedLabel: TextLabel? = nil
local fleetLabel: TextLabel? = nil
local outputLabel: TextLabel? = nil
local perDroneLabel: TextLabel? = nil
local flavorLabel: TextLabel? = nil
local gateLabel: TextLabel? = nil
local gatePercent: TextLabel? = nil
local gateBar: UiKit.BarParts? = nil
local buyOneHandle: UiKit.ActionHandle? = nil
local buyTenHandle: UiKit.ActionHandle? = nil
local buyOneCost: UiKit.CurrencyRow? = nil
local buyOneNeed: TextLabel? = nil
local buyTenCost: UiKit.CurrencyRow? = nil
local buyTenNeed: TextLabel? = nil
local unsubscribe: (() -> ())? = nil
local cleanupModel: (() -> ())? = nil
local relayout: (() -> ())? = nil

--- The rung the hero is showing. `nil` until the first payload, then the best
--- unlocked rung. Clicking a rack row pins it, including a locked rung, which is
--- how the next hull gets advertised before it is affordable.
local selectedTier: string? = nil
local mountedTier: string? = nil
local latest: Types.SyncPayload? = nil

type RackRow = {
	root: TextButton,
	name: TextLabel,
	count: TextLabel,
	bar: Frame,
	stroke: UIStroke,
}

local rackRows: { [string]: RackRow } = {}
local rackOrder: { string } = {}
--- One live orbit per rack row. They spin unconditionally, so the cleanup has
--- to run before the card is destroyed or five RenderStepped loops keep writing
--- into dead viewports.
local rackPreviewCleanups: { () -> () } = {}

-- Expedition band. Two halves that never coexist: the mission shelf while the
-- fleet is home, and a single flight line while it is out.
local expShelf: Frame? = nil
local expLive: Frame? = nil
local expShardLabel: TextLabel? = nil
local expTitle: TextLabel? = nil
local expTimer: TextLabel? = nil
local expReward: Frame? = nil
local expAether: UiKit.CurrencyRow? = nil
local expCores: UiKit.CurrencyRow? = nil
local expShards: TextLabel? = nil
local expBar: UiKit.BarParts? = nil
local expButtons: { [string]: UiKit.ActionHandle } = {}
local expDurations: { [string]: TextLabel } = {}

-- Salvage rack and codex.
type CacheSlot = {
	root: TextButton,
	name: TextLabel,
	state: TextLabel,
	hint: TextLabel,
	aether: UiKit.CurrencyRow,
	cores: UiKit.CurrencyRow,
	bar: UiKit.BarParts,
	stroke: UIStroke,
}

local cacheSlots: { CacheSlot } = {}
local cacheMeterBar: UiKit.BarParts? = nil
local cacheMeterText: TextLabel? = nil
local codexRows: { [string]: { root: Frame, pips: { Frame }, bonus: TextLabel } } = {}
local codexCount: TextLabel? = nil

local function buy(count: number)
	if selectedTier == nil then
		return
	end
	Sfx.purchase()
	StateStore.send("buyDrones", { id = selectedTier, count = count })
end

--- The fleet entry for a rung, from the tick payload.
local function entryFor(payload: Types.SyncPayload, id: string): Types.FleetEntry?
	for _, entry in payload.fleet do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

--- The next hull the fleet has not opened yet. The hero advertises this when the
--- selected hull is already buyable, so the rack always has a next step.
local function nextLocked(payload: Types.SyncPayload): (string?, Types.FleetEntry?)
	for _, id in rackOrder do
		local entry = entryFor(payload, id)
		if entry and not entry.unlocked then
			return id, entry
		end
	end
	return nil, nil
end

-- ---------------------------------------------------------------------------
-- Page shell
-- ---------------------------------------------------------------------------

local function buildPage(canvas: Frame, x: number, y: number, width: number, height: number)
	local card = UiKit.panel(canvas, {
		tier = "shell",
		radius = Theme.Radius.xl,
	})
	card.Name = "Fleet"
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
		eyebrow = "HANGAR  /  FLEET",
		title = "DRONE FLEET",
		detail = "0 DRONES ONLINE",
		height = HEADER_H,
	})
	header.Name = "FleetHeader"
	local detail = header:FindFirstChild("Detail")
	if detail and detail:IsA("TextLabel") then
		headerDetail = detail
	end

	local box = UiKit.scroll(body, { thickness = 6, transparency = 0.2 })
	box.Name = "FleetBody"
	box.Position = UDim2.fromOffset(0, HEADER_H + 2)
	box.Size = UDim2.new(1, 0, 1, -(HEADER_H + 2))
	box.AutomaticCanvasSize = Enum.AutomaticSize.None
	box.CanvasSize = UDim2.fromOffset(0, 0)
	box.ScrollingDirection = Enum.ScrollingDirection.Y
	box.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	scroll = box
end

-- ---------------------------------------------------------------------------
-- Hero
-- ---------------------------------------------------------------------------

--- The stage behind the drone: a gradient wash, a faint grid for depth, then
--- the viewport. The wash itself lives in `StageBackdrop`, shared with the forge
--- and the vault.
local function buildStage(parent: Frame)
	local stage = UiKit.create("Frame", {
		Name = "DroneStage",
		BackgroundColor3 = Theme.Color.void,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.fromScale(1, 1),
	}) :: Frame
	UiKit.corner(stage, Theme.Radius.md)
	UiKit.stroke(stage, Theme.Color.outline, Theme.Stroke.thick, 0)
	UiKit.gradient(stage, { Theme.Color.void, Theme.Color.panelSunken }, 90)
	stage.Parent = parent

	StageBackdrop.paint(stage, {
		warm = Theme.Color.aether,
		cool = Theme.Color.quantum,
		radius = Theme.Radius.md,
		zIndex = 1,
	})

	local grid = UiKit.create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
	}) :: Frame
	grid.Parent = stage
	for index = 1, 6 do
		local line = UiKit.create("Frame", {
			BackgroundColor3 = Theme.Color.aether,
			BackgroundTransparency = 0.92,
			BorderSizePixel = 0,
			Size = UDim2.new(0, 1, 1, 0),
			Position = UDim2.fromScale(index / 7, 0),
			ZIndex = 1,
		}) :: Frame
		line.Parent = grid
	end
	for index = 1, 4 do
		local line = UiKit.create("Frame", {
			BackgroundColor3 = Theme.Color.aether,
			BackgroundTransparency = 0.93,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 1),
			Position = UDim2.fromScale(0, index / 5),
			ZIndex = 1,
		}) :: Frame
		line.Parent = grid
	end

	local frame = UiKit.create("ViewportFrame", {
		Name = "DroneViewport",
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(152, 168, 200),
		LightColor = Color3.fromRGB(228, 242, 255),
		LightDirection = Vector3.new(-0.5, -0.7, -0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
	}) :: ViewportFrame
	frame.Parent = stage
	viewport = frame

	return stage
end

--- One cell of the three-column stat strip. Scale widths, because the hero is
--- 58% of the page on a tablet and 100% on a phone, and three fixed cells left a
--- third of the panel empty at the wide size.
local function buildStat(
	parent: Frame,
	xScale: number,
	wScale: number,
	caption: string,
	color: Color3,
	y: number
): TextLabel
	local head = UiKit.label(parent, {
		text = caption,
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.textFaint,
	})
	head.Position = UDim2.new(xScale, 0, 0, y)
	head.Size = UDim2.new(wScale, 0, 0, 16)

	local value = UiKit.label(parent, {
		text = "0",
		size = Theme.Text.Subheading,
		font = Theme.Font.Numeric,
		color = color,
	})
	value.Position = UDim2.new(xScale, 0, 0, y + 18)
	value.Size = UDim2.new(wScale, 0, 0, 26)
	return value
end

local function buildHero(parent: Frame)
	local card = UiKit.panel(parent, {
		tier = "raised",
		radius = Theme.Radius.card,
	})
	card.Name = "FleetHero"
	hero = card

	local stage = buildStage(card)
	stage.Position = UDim2.fromOffset(8, 8)
	stage.Size = UDim2.new(0.46, -12, 1, -16)

	local info = UiKit.create("Frame", {
		Name = "FleetInfo",
		BackgroundTransparency = 1,
		Position = UDim2.new(0.46, 4, 0, 10),
		Size = UDim2.new(0.54, -18, 1, -20),
		ZIndex = 3,
	}) :: Frame
	info.Parent = card

	local eyebrow = UiKit.eyebrow(info, "SELECTED HULL")
	eyebrow.Position = UDim2.fromOffset(0, 0)

	tierNameLabel = UiKit.label(info, {
		text = "SCRAP DRONE",
		size = Theme.Text.Title - 8,
		font = Theme.Font.Black,
		color = Theme.Color.aether,
	})
	tierNameLabel.Name = "TierName"
	tierNameLabel.Position = UDim2.fromOffset(0, 14)
	tierNameLabel.Size = UDim2.new(1, -120, 0, 28)

	tierOwnedLabel = UiKit.label(info, {
		text = "0 OWNED",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.textSecondary,
		align = Enum.TextXAlignment.Right,
	})
	tierOwnedLabel.Name = "TierOwned"
	tierOwnedLabel.Position = UDim2.new(1, -118, 0, 20)
	tierOwnedLabel.Size = UDim2.fromOffset(118, 18)

	local rule = UiKit.rule(info, { position = UDim2.fromOffset(0, 48) })
	rule.Size = UDim2.new(1, 0, 0, 1)

	fleetLabel = buildStat(info, 0, 1 / 3, "FLEET", Theme.Color.text, 56)
	outputLabel = buildStat(info, 1 / 3, 1 / 3, "OUTPUT", Theme.Color.starMatter, 56)
	perDroneLabel = buildStat(info, 2 / 3, 1 / 3, "PER COPY", Theme.Color.cyan, 56)

	for _, x in { 1 / 3, 2 / 3 } do
		local divider = UiKit.create("Frame", {
			BackgroundColor3 = Theme.Color.stroke,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(1, 36),
			Position = UDim2.new(x, 0, 0, 58),
			ZIndex = 3,
		}) :: Frame
		divider.Parent = info
	end

	gateLabel = UiKit.label(info, {
		text = "",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.cyan,
	})
	gateLabel.Position = UDim2.fromOffset(0, 114)
	gateLabel.Size = UDim2.new(1, -100, 0, 16)

	gatePercent = UiKit.label(info, {
		text = "",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Right,
	})
	gatePercent.Position = UDim2.new(1, -100, 0, 114)
	gatePercent.Size = UDim2.fromOffset(100, 16)

	gateBar = UiKit.bar(info, {
		height = 6,
		radius = 3,
		gradient = { Theme.Color.cyanDeep, Theme.Color.cyan },
	})
	gateBar.track.Position = UDim2.fromOffset(0, 134)
	gateBar.track.Size = UDim2.new(1, 0, 0, 6)

	flavorLabel = UiKit.label(info, {
		text = "",
		size = Theme.Text.Tiny,
		color = Theme.Color.textSecondary,
		wrap = true,
	})
	flavorLabel.Position = UDim2.fromOffset(0, 150)
	flavorLabel.Size = UDim2.new(1, 0, 0, 32)

	local dock = UiKit.create("Frame", {
		Name = "FleetDock",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 1, -46),
		Size = UDim2.new(1, 0, 0, 46),
		ZIndex = 4,
	}) :: Frame
	dock.Parent = info
	UiKit.hlist(dock, 8, Enum.VerticalAlignment.Center)

	local oneHandle = UiKit.actionButton(dock, {
		accent = Theme.Color.actionCyan,
		height = 46,
		radius = Theme.Radius.md,
		size = 14,
		solid = true,
		labelColor = Theme.Color.ink,
		labelStroke = false,
		label = "BUILD 1",
		handler = function()
			buy(1)
		end,
	})
	oneHandle.button.Name = "BuyDrone"
	oneHandle.button.Size = UDim2.new(0.46, -4, 0, 46)
	oneHandle.button.ZIndex = 5
	buyOneHandle = oneHandle

	local tenHandle = UiKit.actionButton(dock, {
		accent = Theme.Color.aether,
		height = 46,
		radius = Theme.Radius.md,
		size = 14,
		label = "BUILD 10",
		handler = function()
			buy(10)
		end,
	})
	tenHandle.button.Name = "BuyDroneTen"
	tenHandle.button.Size = UDim2.new(0.54, -4, 0, 46)
	tenHandle.button.ZIndex = 5
	buyTenHandle = tenHandle

	-- The buy keys show their currency. A bare "5.37M" beside a "150.26M" was
	-- the only price in the game with no unit, and the crystal is the same mark
	-- the top bar and every payout row use. Two lines: verb on top, price or
	-- the unlock requirement underneath, so a locked hull never has to fit
	-- "LOCKED · 110 DRONES REQUIRED" on one line.
	local function buildCost(handle: UiKit.ActionHandle, ink: Color3): (UiKit.CurrencyRow, TextLabel)
		local face = handle.button:FindFirstChild("Face")
		if face and face:IsA("TextLabel") then
			face.Position = UDim2.fromOffset(6, 3)
			face.Size = UDim2.new(1, -12, 0, 18)
		end
		local need = UiKit.label(handle.button, {
			text = "",
			size = Theme.Text.Tiny,
			font = Theme.Font.Numeric,
			color = Theme.Color.textSecondary,
			align = Enum.TextXAlignment.Center,
		})
		need.Name = "Need"
		need.Position = UDim2.fromOffset(6, 24)
		need.Size = UDim2.new(1, -12, 0, 16)
		need.Visible = false
		local cost = UiKit.currencyRow(handle.button, {
			kind = "aether",
			text = "",
			iconSize = 16,
			textSize = Theme.Text.Tiny,
			color = ink,
			iconColor = Theme.Color.white,
			height = 16,
			gap = 3,
		})
		cost.root.Name = "Cost"
		cost.root.AnchorPoint = Vector2.new(0.5, 0)
		cost.root.Position = UDim2.new(0.5, 0, 0, 24)
		cost.root.Visible = false
		return cost, need
	end

	buyOneCost, buyOneNeed = buildCost(oneHandle, Theme.Color.ink)
	buyTenCost, buyTenNeed = buildCost(tenHandle, Theme.Color.white)
end

-- ---------------------------------------------------------------------------
-- Hull rack
-- ---------------------------------------------------------------------------

--- Five rows stacked, not five keys across a strip. A row carries the hull name,
--- the owned count and the unlock meter in one line, and the column reads as a
--- ladder instead of a tab bar.
local function buildRack(parent: Frame)
	local card = UiKit.panel(parent, {
		tier = "item",
		radius = Theme.Radius.card,
	})
	card.Name = "HullRack"
	rack = card

	local head = UiKit.label(card, {
		text = "HULL RACK",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.textSecondary,
	})
	head.Position = UDim2.fromOffset(12, 7)
	head.Size = UDim2.new(1, -120, 0, 16)

	local hint = UiKit.label(card, {
		text = "PICK A HULL TO PREVIEW",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Right,
	})
	hint.Position = UDim2.new(1, -180, 0, 7)
	hint.Size = UDim2.fromOffset(168, 16)

	for index, tier in DroneRegistry.tiers do
		local row = UiKit.create("TextButton", {
			Name = string.format("Rung_%s", tier.id),
			BackgroundColor3 = Theme.Color.panelSunken,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			Size = UDim2.new(1, -20, 0, 48),
			Position = UDim2.fromOffset(10, 30 + (index - 1) * 52),
		}) :: TextButton
		UiKit.corner(row, Theme.Radius.sm)
		local stroke = UiKit.stroke(row, Theme.Color.stroke, 1, 0)
		row.Parent = card

		-- The row has to look like a hull you can pick, not a label with a meter.
		-- A spinning 38px model is the cheapest way to say "this is a drone" and
		-- it makes the locked rungs read as a ladder you climb instead of five
		-- grey rows. The model is the same one the hero stage uses.
		local preview = UiKit.create("ViewportFrame", {
			Name = "RungPreview",
			BackgroundColor3 = Theme.Color.void,
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			Ambient = Color3.fromRGB(152, 168, 200),
			LightColor = Color3.fromRGB(228, 242, 255),
			LightDirection = Vector3.new(-0.5, -0.7, -0.5),
			Size = UDim2.fromOffset(38, 38),
			Position = UDim2.fromOffset(6, 5),
			ZIndex = 2,
		}) :: ViewportFrame
		UiKit.corner(preview, 6)
		UiKit.stroke(preview, tier.glow, 1, 0.55)
		preview.Parent = row
		rackPreviewCleanups[#rackPreviewCleanups + 1] = DroneModelBuilder.mount(preview, tier.id)

		local name = UiKit.label(row, {
			text = string.upper(tier.name),
			size = Theme.Text.Tiny,
			font = Theme.Font.Black,
			color = Theme.Color.locked,
		})
		name.Position = UDim2.fromOffset(52, 4)
		name.Size = UDim2.new(1, -118, 0, 18)

		local count = UiKit.label(row, {
			text = "0",
			size = Theme.Text.Small,
			font = Theme.Font.Numeric,
			color = Theme.Color.textDim,
			align = Enum.TextXAlignment.Right,
		})
		count.Position = UDim2.new(1, -62, 0, 3)
		count.Size = UDim2.fromOffset(52, 20)

		local track = UiKit.create("Frame", {
			BackgroundColor3 = Theme.Color.void,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -122, 0, 4),
			Position = UDim2.new(0, 52, 1, -9),
		}) :: Frame
		UiKit.corner(track, 2)
		track.Parent = row

		local bar = UiKit.create("Frame", {
			BackgroundColor3 = Theme.Color.stroke,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(0, 1),
		}) :: Frame
		UiKit.corner(bar, 2)
		bar.Parent = track

		rackRows[tier.id] = { root = row, name = name, count = count, bar = bar, stroke = stroke }
		rackOrder[#rackOrder + 1] = tier.id

		row.Activated:Connect(function()
			selectedTier = tier.id
			if latest then
				DroneView.render(latest)
			end
		end)
	end
end

-- ---------------------------------------------------------------------------
-- Expedition
-- ---------------------------------------------------------------------------

--- The clock the server actually commits. Express Salvage is permanent, so a
--- mission card must quote the shortened time before the player sends a squad.
local function missionSeconds(payload: Types.SyncPayload, mission: ExpeditionConfig.Mission): number
	if payload.ownedPasses.expressSalvage then
		return math.max(60, math.floor(mission.seconds * MonetizationConfig.ExpeditionTimeScale))
	end
	return mission.seconds
end

local function durationText(seconds: number): string
	if seconds >= 3600 then
		return string.format("%dH", math.ceil(seconds / 3600))
	end
	return string.format("%dM", math.ceil(seconds / 60))
end

local function buildExpedition(parent: Frame)
	local card = UiKit.panel(parent, {
		tier = "item",
		radius = Theme.Radius.card,
	})
	card.Name = "ExpeditionCard"
	expeditionCard = card

	local head = UiKit.label(card, {
		text = "EXPEDITION",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.textSecondary,
	})
	head.Position = UDim2.fromOffset(12, 7)
	head.Size = UDim2.fromOffset(150, 16)

	expShardLabel = UiKit.label(card, {
		text = "0 SHARDS",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.quantum,
		align = Enum.TextXAlignment.Right,
	})
	expShardLabel.Position = UDim2.new(1, -160, 0, 7)
	expShardLabel.Size = UDim2.fromOffset(148, 16)

	local shelf = UiKit.create("Frame", {
		Name = "ExpeditionShelf",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 258),
		Position = UDim2.fromOffset(0, 28),
	}) :: Frame
	shelf.Parent = card
	expShelf = shelf

	for index, mission in ExpeditionConfig.list() do
		local row = UiKit.create("Frame", {
			Name = string.format("Mission_%s", mission.id),
			BackgroundColor3 = Theme.Color.panelSunken,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -20, 0, 76),
			Position = UDim2.fromOffset(10, (index - 1) * 84),
		}) :: Frame
		UiKit.corner(row, Theme.Radius.sm)
		row.Parent = shelf

		local well = UiKit.badgeWell(row, {
			image = AssetManifest.uiArt(mission.icon),
			size = 56,
			accent = Theme.Color.aether,
		})
		if well ~= nil then
			well.Position = UDim2.fromOffset(8, 10)
		end

		local name = UiKit.label(row, {
			text = mission.name,
			size = Theme.Text.Small,
			font = Theme.Font.Black,
			color = Theme.Color.text,
		})
		name.Position = UDim2.fromOffset(76, 12)
		name.Size = UDim2.new(1, -200, 0, 22)

		local detail = UiKit.label(row, {
			text = string.format("%d DRONES  ·  %s", mission.squad, durationText(mission.seconds)),
			size = Theme.Text.Tiny,
			font = Theme.Font.Numeric,
			color = Theme.Color.textSecondary,
		})
		detail.Position = UDim2.fromOffset(76, 34)
		detail.Size = UDim2.new(1, -200, 0, 16)
		expDurations[mission.id] = detail

		-- The reward gets its own line instead of riding the end of the squad
		-- line. On the tablet the card is a third of the deck, and the joined
		-- string did not fit at the 13px floor.
		local reward = UiKit.currencyRow(row, {
			kind = "aether",
			text = string.format("+%s", NumberUtil.compact(mission.aether)),
			iconSize = 16,
			textSize = Theme.Text.Tiny,
			color = Theme.Color.aether,
			height = 16,
		})
		reward.root.Position = UDim2.fromOffset(76, 52)

		local handle = UiKit.actionButton(row, {
			accent = Theme.Color.quantum,
			height = 32,
			radius = Theme.Radius.sm,
			size = 13,
			label = "SEND",
			handler = function()
				Sfx.dispatch()
				StateStore.send("dispatch", { id = mission.id })
			end,
		})
		handle.button.Name = string.format("Dispatch_%s", mission.id)
		handle.button.Position = UDim2.new(1, -98, 0.5, -16)
		handle.button.Size = UDim2.fromOffset(86, 32)
		handle.set("ready", "SEND", Theme.Color.quantum)
		expButtons[mission.id] = handle
	end

	local live = UiKit.create("Frame", {
		Name = "ExpeditionLive",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -20, 0, 258),
		Position = UDim2.fromOffset(10, 28),
		Visible = false,
	}) :: Frame
	live.Parent = card
	expLive = live

	expTitle = UiKit.label(live, {
		text = "",
		size = Theme.Text.Subheading,
		font = Theme.Font.Black,
		color = Theme.Color.quantum,
	})
	expTitle.Position = UDim2.fromOffset(2, 12)
	expTitle.Size = UDim2.new(1, -140, 0, 24)

	expTimer = UiKit.label(live, {
		text = "00:00",
		size = Theme.Text.Subheading,
		font = Theme.Font.Numeric,
		color = Theme.Color.starMatter,
		align = Enum.TextXAlignment.Right,
	})
	expTimer.Position = UDim2.new(1, -150, 0, 10)
	expTimer.Size = UDim2.fromOffset(148, 26)

	expBar = UiKit.bar(live, {
		height = 8,
		radius = 4,
		gradient = { Theme.Color.quantumDeep, Theme.Color.quantum },
	})
	expBar.track.Position = UDim2.fromOffset(2, 50)
	expBar.track.Size = UDim2.new(1, -4, 0, 8)

	expReward = UiKit.create("Frame", {
		Name = "ExpeditionReward",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -4, 0, 20),
		Position = UDim2.fromOffset(2, 70),
	}) :: Frame
	expReward.Parent = live
	local rewardList = UiKit.hlist(expReward, 12, Enum.VerticalAlignment.Center)
	rewardList.HorizontalAlignment = Enum.HorizontalAlignment.Center

	expAether = UiKit.currencyRow(expReward, {
		kind = "aether",
		text = "+0",
		iconSize = 16,
		textSize = Theme.Text.Tiny,
		color = Theme.Color.aether,
		height = 20,
	})
	expCores = UiKit.currencyRow(expReward, {
		kind = "cores",
		text = "+0",
		iconSize = 16,
		textSize = Theme.Text.Tiny,
		color = Theme.Color.quantum,
		height = 20,
	})
	expShards = UiKit.label(expReward, {
		text = "",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.textSecondary,
	})
	expShards.AutomaticSize = Enum.AutomaticSize.X
	expShards.Size = UDim2.fromOffset(0, 20)
end

-- ---------------------------------------------------------------------------
-- Salvage
-- ---------------------------------------------------------------------------

local function buildSalvage(parent: Frame)
	local card = UiKit.panel(parent, {
		tier = "item",
		radius = Theme.Radius.card,
	})
	card.Name = "SalvageCard"
	salvageCard = card

	local head = UiKit.label(card, {
		text = "SALVAGE RACK",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.textSecondary,
	})
	head.Position = UDim2.fromOffset(12, 7)
	head.Size = UDim2.fromOffset(180, 16)

	cacheMeterBar = UiKit.bar(card, {
		height = 5,
		radius = 3,
		gradient = { Theme.Color.quantumDeep, Theme.Color.quantum },
	})
	cacheMeterBar.track.Position = UDim2.fromOffset(12, 28)
	cacheMeterBar.track.Size = UDim2.new(1, -24, 0, 5)

	cacheMeterText = UiKit.label(card, {
		text = "NEXT CACHE  0 / 40 STRIKES",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.textSecondary,
	})
	cacheMeterText.Position = UDim2.fromOffset(12, 37)
	cacheMeterText.Size = UDim2.new(1, -24, 0, 16)

	for index = 1, SalvageConfig.MaxCaches do
		local slotW = 1 / SalvageConfig.MaxCaches
		local rootSlot = UiKit.create("TextButton", {
			Name = string.format("CacheSlot%d", index),
			BackgroundColor3 = Theme.Color.panelSunken,
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			Size = UDim2.new(slotW, -8, 0, 142),
			Position = UDim2.new((index - 1) * slotW, 6, 0, 62),
		}) :: TextButton
		UiKit.corner(rootSlot, Theme.Radius.sm)
		local stroke = UiKit.stroke(rootSlot, Theme.Color.stroke, 2, 0.25)
		rootSlot.Parent = card

		local nameLabel = UiKit.label(rootSlot, {
			text = "EMPTY",
			size = Theme.Text.Tiny,
			font = Theme.Font.Black,
			color = Theme.Color.textFaint,
			align = Enum.TextXAlignment.Center,
		})
		nameLabel.Position = UDim2.fromOffset(6, 8)
		nameLabel.Size = UDim2.new(1, -12, 0, 16)

		local stateLabel = UiKit.label(rootSlot, {
			text = "",
			size = Theme.Text.Subheading,
			font = Theme.Font.Black,
			color = Theme.Color.text,
			align = Enum.TextXAlignment.Center,
		})
		stateLabel.Position = UDim2.fromOffset(6, 36)
		stateLabel.Size = UDim2.new(1, -12, 0, 28)

		local aetherRow = UiKit.currencyRow(rootSlot, {
			kind = "aether",
			text = "+0",
			iconSize = 16,
			textSize = Theme.Text.Tiny,
			color = Theme.Color.aether,
			height = 16,
			gap = 3,
		})
		aetherRow.root.AnchorPoint = Vector2.new(0.5, 0)
		aetherRow.root.Position = UDim2.new(0.5, 0, 0, 66)
		aetherRow.root.Visible = false

		local coresRow = UiKit.currencyRow(rootSlot, {
			kind = "cores",
			text = "+0",
			iconSize = 16,
			textSize = Theme.Text.Tiny,
			color = Theme.Color.quantum,
			height = 16,
			gap = 3,
		})
		coresRow.root.AnchorPoint = Vector2.new(0.5, 0)
		coresRow.root.Position = UDim2.new(0.5, 0, 0, 82)
		coresRow.root.Visible = false

		local hint = UiKit.label(rootSlot, {
			text = "",
			size = Theme.Text.Tiny,
			font = Theme.Font.Numeric,
			color = Theme.Color.textSecondary,
			align = Enum.TextXAlignment.Center,
			wrap = true,
		})
		hint.Position = UDim2.fromOffset(6, 98)
		hint.Size = UDim2.new(1, -12, 0, 18)

		local bar = UiKit.bar(rootSlot, {
			height = 4,
			radius = 2,
			gradient = { Theme.Color.quantumDeep, Theme.Color.quantum },
		})
		bar.track.Position = UDim2.new(0, 8, 1, -16)
		bar.track.Size = UDim2.new(1, -16, 0, 4)
		bar.set(0)

		rootSlot.Activated:Connect(function()
			local state = StateStore.current
			if state == nil then
				return
			end
			local cache = state.caches[index]
			if cache == nil then
				return
			end
			if cache.readyAt <= 0 then
				Sfx.cacheCrack()
				StateStore.send("crackCache", { slot = index })
			elseif cache.secondsLeft <= 0 then
				Sfx.cacheClaim()
				StateStore.send("claimCache", { slot = index })
			end
		end)

		cacheSlots[index] = {
			root = rootSlot,
			name = nameLabel,
			state = stateLabel,
			hint = hint,
			aether = aetherRow,
			cores = coresRow,
			bar = bar,
			stroke = stroke,
		}
	end

	local footnote = UiKit.label(card, {
		text = "Caches crack on the server clock. One rack per account.",
		size = Theme.Text.Tiny,
		color = Theme.Color.textFaint,
		wrap = true,
	})
	footnote.Position = UDim2.new(0, 12, 1, -46)
	footnote.Size = UDim2.new(1, -24, 0, 34)
end

-- ---------------------------------------------------------------------------
-- Codex
-- ---------------------------------------------------------------------------

local STAT_LABEL: { [string]: string } = {
	click = "STRIKE",
	cool = "COOLING",
	crit = "CRIT",
	vent = "VENT",
}

local function buildCodex(parent: Frame)
	local card = UiKit.panel(parent, {
		tier = "item",
		radius = Theme.Radius.card,
	})
	card.Name = "CodexCard"
	codexCard = card

	local head = UiKit.label(card, {
		text = "SIGIL CODEX",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.textSecondary,
	})
	head.Position = UDim2.fromOffset(12, 7)
	head.Size = UDim2.fromOffset(180, 16)

	codexCount = UiKit.label(card, {
		text = "0 / 4 SETS",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.quantum,
		align = Enum.TextXAlignment.Right,
	})
	codexCount.Position = UDim2.new(1, -172, 0, 7)
	codexCount.Size = UDim2.fromOffset(160, 16)

	for index, setId in SalvageConfig.SetOrder do
		local set = SalvageConfig.SigilSets[setId]
		local row = UiKit.create("Frame", {
			Name = string.format("Codex_%s", setId),
			BackgroundColor3 = Theme.Color.panelSunken,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -24, 0, 48),
			Position = UDim2.fromOffset(12, 30 + (index - 1) * 56),
		}) :: Frame
		UiKit.corner(row, 6)
		row.Parent = card

		local name = UiKit.label(row, {
			text = set.name,
			size = Theme.Text.Tiny,
			font = Theme.Font.Black,
			color = Theme.Color.textSecondary,
		})
		name.Position = UDim2.fromOffset(10, 4)
		name.Size = UDim2.new(1, -32, 0, 18)

		local pips: { Frame } = {}
		for pip = 1, #set.sigils do
			local dot = UiKit.create("Frame", {
				BackgroundColor3 = Theme.Color.panelSunken,
				BorderSizePixel = 0,
				Size = UDim2.fromOffset(10, 10),
				Position = UDim2.fromOffset(10 + (pip - 1) * 16, 28),
			}) :: Frame
			UiKit.corner(dot, 5)
			UiKit.stroke(dot, Theme.Color.stroke, 1, 0.15)
			dot.Parent = row
			pips[pip] = dot
		end

		local bonus = UiKit.label(row, {
			text = string.format(
				"+%d%% %s",
				math.floor(set.amount * 100 + 0.5),
				STAT_LABEL[set.stat] or set.stat
			),
			size = Theme.Text.Tiny,
			font = Theme.Font.Numeric,
			color = Theme.Color.textFaint,
			align = Enum.TextXAlignment.Right,
		})
		bonus.Position = UDim2.new(1, -160, 0, 24)
		bonus.Size = UDim2.fromOffset(150, 18)

		codexRows[setId] = { root = row, pips = pips, bonus = bonus }
	end
end

-- ---------------------------------------------------------------------------
-- Field notes
-- ---------------------------------------------------------------------------

local function buildNotes(parent: Frame)
	local card = UiKit.panel(parent, {
		tier = "well",
		radius = Theme.Radius.card,
		stroke = Theme.Color.cyan,
		strokeTransparency = 0.7,
	})
	card.Name = "FleetNotes"
	notes = card

	local head = UiKit.label(card, {
		text = "FIELD NOTES",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.cyan,
	})
	head.Position = UDim2.fromOffset(14, 8)
	head.Size = UDim2.new(1, -28, 0, 16)

	local lines = {
		"A hull opens when the whole fleet reaches its gate, not when you can afford it.",
		"An expedition keeps earning while you are away. Send the squad first.",
		"Caches crack on the server clock. A closed tab still finishes the job.",
	}
	for index, line in lines do
		local marker = UiKit.label(card, {
			text = string.format("%02d", index),
			size = Theme.Text.Tiny,
			font = Theme.Font.Numeric,
			color = Theme.Color.cyan,
		})
		marker.Position = UDim2.fromOffset(14, 30 + (index - 1) * 26)
		marker.Size = UDim2.fromOffset(24, 18)

		local copy = UiKit.label(card, {
			text = line,
			size = Theme.Text.Tiny,
			color = Theme.Color.textSecondary,
			wrap = true,
		})
		copy.Position = UDim2.fromOffset(42, 30 + (index - 1) * 26)
		copy.Size = UDim2.new(1, -56, 0, 18)
	end
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

--- Places the body cards for the current canvas. The top row is a stage and a
--- rack side by side; the service deck is three cards on a wide canvas and one
--- column on a phone. The scroll canvas is measured from the last card, so the
--- page never reports a canvas shorter than its content.
relayout = function()
	if root == nil or scroll == nil or hero == nil or rack == nil then
		return
	end

	local bodyW = Layout.CONTENT_W - PAGE_PAD * 2 - 8
	local bodyH = Layout.CONTENT_H - PAGE_PAD * 2 - HEADER_H - 2
	local wide = bodyW >= 980

	if wide then
		local rackW = math.clamp(math.floor(bodyW * 0.34), 320, 430)
		hero.Size = UDim2.fromOffset(bodyW - rackW - GAP, HERO_H)
		hero.Position = UDim2.fromOffset(0, 0)
		rack.Size = UDim2.fromOffset(rackW, HERO_H)
		rack.Position = UDim2.fromOffset(bodyW - rackW, 0)
	else
		hero.Size = UDim2.fromOffset(bodyW, HERO_H)
		hero.Position = UDim2.fromOffset(0, 0)
		rack.Size = UDim2.fromOffset(bodyW, RACK_H)
		rack.Position = UDim2.fromOffset(0, HERO_H + GAP)
	end

	local servicesY = if wide then HERO_H + GAP else HERO_H + RACK_H + GAP * 2
	local cols = if bodyW >= 980 then 3 elseif bodyW >= 760 then 2 else 1
	local cardW = math.floor((bodyW - (cols - 1) * GAP) / cols)
	local cards = { expeditionCard, salvageCard, codexCard }
	for index, card in cards do
		if card then
			local column = (index - 1) % cols
			local row = (index - 1) // cols
			card.Size = UDim2.fromOffset(cardW, SERVICE_H)
			card.Position = UDim2.fromOffset(column * (cardW + GAP), servicesY + row * (SERVICE_H + GAP))
		end
	end

	local rows = math.ceil(#cards / cols)
	local notesY = servicesY + rows * (SERVICE_H + GAP)
	if notes then
		notes.Size = UDim2.fromOffset(bodyW, NOTES_H)
		notes.Position = UDim2.fromOffset(0, notesY)
	end

	-- The body is taller than the window on a laptop and shorter on a tablet. A
	-- canvas at least the window height keeps the scrollbar honest and lets the
	-- last card sit above the fold instead of under a dead band.
	local contentH = math.max(bodyH, notesY + NOTES_H)
	scroll.CanvasSize = UDim2.fromOffset(0, contentH)
end

function DroneView.layout()
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
-- Model mount
-- ---------------------------------------------------------------------------

local function mountTier(id: string)
	if viewport == nil then
		return
	end
	if cleanupModel then
		cleanupModel()
		cleanupModel = nil
	end
	cleanupModel = DroneModelBuilder.mount(viewport, id, {
		distance = 5.8,
		centre = Vector3.new(0, -0.15, 0),
	})
	mountedTier = id
end

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------

function DroneView.init(canvas: Frame, x: number, y: number, width: number, height: number)
	buildPage(canvas, x, y, width, height)
	local body = scroll
	if body == nil then
		return
	end

	buildHero(body)
	buildRack(body)
	buildExpedition(body)
	buildSalvage(body)
	buildCodex(body)
	buildNotes(body)

	if relayout then
		relayout()
	end

	unsubscribe = StateStore.onSync(function(payload: Types.SyncPayload)
		DroneView.render(payload)
	end)

	local current = StateStore.current
	if current then
		DroneView.render(current)
	end
end

function DroneView.card(): Frame?
	return root
end

-- ---------------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------------

local function formatClock(seconds: number): string
	local total = math.max(0, math.ceil(seconds))
	if total >= 3600 then
		return string.format("%d:%02d:%02d", total // 3600, (total % 3600) // 60, total % 60)
	end
	return string.format("%d:%02d", total // 60, total % 60)
end

local expActiveShown: boolean? = nil

local function paintExpedition(payload: Types.SyncPayload)
	if expShelf == nil or expLive == nil then
		return
	end

	if expShardLabel then
		expShardLabel.Text = string.format("%d SHARDS", payload.shards)
	end

	local active = payload.expId ~= ""
	if active ~= expActiveShown then
		expActiveShown = active
		expShelf.Visible = not active
		expLive.Visible = active
	end

	local home = payload.drones
	for _, mission in ExpeditionConfig.list() do
		local clock = missionSeconds(payload, mission)
		local detail = expDurations[mission.id]
		if detail then
			detail.Text = string.format("%d DRONES  ·  %s", mission.squad, durationText(clock))
		end
		local handle = expButtons[mission.id]
		if handle then
			if active then
				handle.set("locked", "AWAY", Theme.Color.quantum)
			elseif home >= mission.squad then
				handle.set("ready", "SEND", Theme.Color.quantum)
			else
				handle.set("locked", string.format("NEED %d", mission.squad), Theme.Color.quantum)
			end
		end
	end

	if not active then
		return
	end

	local mission = ExpeditionConfig.get(payload.expId)
	if mission == nil then
		return
	end
	if expTitle then
		expTitle.Text = string.upper(mission.name)
	end
	if expTimer then
		expTimer.Text = formatClock(payload.expRemaining)
	end
	if expBar then
		-- Use the clock the mission was dispatched with, not today's Express
		-- discount. Buying the charter mid-flight must not make the bar jump.
		local clock = if payload.expTotal > 0 then payload.expTotal else missionSeconds(payload, mission)
		local elapsed = clock - payload.expRemaining
		expBar.set(math.clamp(elapsed / math.max(1, clock), 0, 1))
	end
	if expReward then
		if expAether then
			expAether.set(string.format("+%s", NumberUtil.compact(payload.expAether)))
		end
		if expCores then
			expCores.root.Visible = payload.expCores > 0
			expCores.set(string.format("+%d", payload.expCores))
		end
		if expShards then
			expShards.Visible = payload.expShards > 0
			expShards.Text = string.format("%d SHARDS", payload.expShards)
		end
	end
end

local function formatShort(seconds: number): string
	local total = math.max(0, math.ceil(seconds))
	if total >= 60 then
		return string.format("%d:%02d", total // 60, total % 60)
	end
	return string.format("0:%02d", total)
end

local function paintSalvage(payload: Types.SyncPayload)
	for index, slot in cacheSlots do
		local cache = payload.caches[index]
		local rarity = if cache then SalvageConfig.getRarity(cache.rarity) else nil

		if cache == nil or rarity == nil then
			slot.root.BackgroundColor3 = Theme.Color.panelSunken
			slot.root.BackgroundTransparency = 0.35
			slot.name.Text = "EMPTY"
			slot.name.TextColor3 = Theme.Color.textFaint
			slot.state.Text = ""
			slot.hint.Text = ""
			slot.aether.root.Visible = false
			slot.cores.root.Visible = false
			slot.stroke.Color = Theme.Color.stroke
			slot.stroke.Transparency = 0.35
			slot.bar.set(0)
			slot.bar.track.Visible = false
			continue
		end

		slot.name.Text = string.upper(rarity.name)
		slot.name.TextColor3 = rarity.color
		slot.stroke.Color = rarity.color
		slot.bar.track.Visible = true

		local ready = cache.readyAt > 0 and cache.secondsLeft <= 0
		if cache.readyAt <= 0 then
			slot.root.BackgroundColor3 = Theme.Color.panelSunken
			slot.root.BackgroundTransparency = 0
			slot.stroke.Transparency = 0
			slot.state.Text = "CRACK"
			slot.state.TextColor3 = Theme.Color.text
			slot.hint.Text = ""
			slot.aether.root.Visible = false
			slot.cores.root.Visible = false
			slot.bar.set(0)
		elseif not ready then
			local total = math.max(1, rarity.crackSeconds)
			slot.root.BackgroundColor3 = Theme.Color.panelSunken
			slot.root.BackgroundTransparency = 0
			slot.stroke.Transparency = 0.25
			slot.state.Text = formatShort(cache.secondsLeft)
			slot.state.TextColor3 = Theme.Color.text
			slot.hint.Text = "CRACKING"
			slot.aether.root.Visible = false
			slot.cores.root.Visible = false
			slot.bar.set(math.clamp(1 - cache.secondsLeft / total, 0, 1))
		else
			slot.root.BackgroundColor3 = rarity.color:Lerp(Theme.Color.ink, 0.74)
			slot.root.BackgroundTransparency = 0
			slot.stroke.Transparency = 0
			slot.state.Text = "CLAIM"
			slot.state.TextColor3 = rarity.color
			slot.aether.root.Visible = rarity.aether > 0
			slot.aether.set(string.format("+%s", NumberUtil.compact(rarity.aether)))
			slot.cores.root.Visible = rarity.cores > 0
			slot.cores.set(string.format("+%d", rarity.cores))
			slot.hint.Text = if rarity.shards > 0 then string.format("%d SHARDS", rarity.shards) else ""
			slot.bar.set(1)
		end
	end

	local full = #payload.caches >= SalvageConfig.MaxCaches
	if cacheMeterBar then
		cacheMeterBar.set(math.clamp(payload.cacheMeter / math.max(1, payload.cacheGoal), 0, 1))
	end
	if cacheMeterText then
		cacheMeterText.Text = if full
			then "RACK FULL"
			else string.format("NEXT CACHE  %d / %d STRIKES", payload.cacheMeter, payload.cacheGoal)
		cacheMeterText.TextColor3 = if full then Theme.Color.warn else Theme.Color.textSecondary
	end
end

local function paintCodex(payload: Types.SyncPayload)
	for setId, row in codexRows do
		local set = SalvageConfig.getSet(setId)
		if set == nil then
			continue
		end
		local progress = SalvageConfig.setProgress(setId, payload.sigils)
		local complete = progress >= #set.sigils

		for pip, dot in row.pips do
			local filled = pip <= progress
			dot.BackgroundColor3 = if filled then Theme.Color.quantum else Theme.Color.panelSunken
			local stroke = dot:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if filled then Theme.Color.quantum else Theme.Color.stroke
			end
		end

		row.bonus.TextColor3 = if complete then Theme.Color.quantum else Theme.Color.textFaint
		row.root.BackgroundColor3 = if complete then Theme.Color.quantumDeep else Theme.Color.panelSunken
		row.root.BackgroundTransparency = if complete then 0.72 else 0.35
	end

	if codexCount then
		codexCount.Text = string.format("%d / %d SETS", payload.codexSets, #SalvageConfig.SetOrder)
		codexCount.TextColor3 = if payload.codexSets > 0 then Theme.Color.quantum else Theme.Color.textFaint
	end
end

function DroneView.render(payload: Types.SyncPayload)
	if viewport == nil then
		return
	end
	latest = payload

	-- First payload picks the best rung the fleet has opened. After that the
	-- player's choice sticks, including a locked rung they are previewing.
	if selectedTier == nil or entryFor(payload, selectedTier :: string) == nil then
		selectedTier = DroneRegistry.bestUnlocked(payload.drones).id
	end
	local id = selectedTier :: string
	local entry = entryFor(payload, id)
	local tier = DroneRegistry.get(id)
	if entry == nil or tier == nil then
		return
	end

	if mountedTier ~= id then
		mountTier(id)
	end

	if headerDetail then
		headerDetail.Text = string.format("%s DRONES ONLINE", NumberUtil.abbreviate(payload.drones))
	end

	if tierNameLabel then
		tierNameLabel.Text = string.upper(tier.name)
		tierNameLabel.TextColor3 = tier.glow
	end
	if tierOwnedLabel then
		tierOwnedLabel.Text = string.format("%s OWNED", NumberUtil.abbreviate(entry.owned))
	end

	if fleetLabel then
		fleetLabel.Text = NumberUtil.abbreviate(payload.drones)
	end
	if outputLabel then
		outputLabel.Text = NumberUtil.abbreviateRate(payload.passiveYield)
	end
	if perDroneLabel then
		perDroneLabel.Text = NumberUtil.abbreviateRate(tier.yield)
	end
	if flavorLabel then
		flavorLabel.Text = tier.flavor
	end

	-- The gate line answers "what opens next". A selected locked hull states its
	-- own gate; an open hull advertises the next one. When every hull is open the
	-- bar is full and the caption says so instead of printing a fake percentage.
	local gateTier: DroneRegistry.DroneTier? = nil
	local gateEntry: Types.FleetEntry? = nil
	if not entry.unlocked then
		gateTier = tier
		gateEntry = entry
	else
		local nextId, nextEntry = nextLocked(payload)
		if nextId then
			gateTier = DroneRegistry.get(nextId)
			gateEntry = nextEntry
		end
	end

	if gateLabel and gatePercent and gateBar then
		if gateTier and gateEntry then
			local progress = math.clamp(payload.drones / math.max(1, gateEntry.unlockAt), 0, 1)
			gateLabel.Text = string.format("NEXT HULL  ·  %s", string.upper(gateTier.name))
			gateLabel.TextColor3 = if entry.unlocked then Theme.Color.cyan else Theme.Color.warn
			gatePercent.Text = string.format(
				"%s / %s DRONES",
				NumberUtil.abbreviate(payload.drones),
				NumberUtil.abbreviate(gateEntry.unlockAt)
			)
			gateBar.set(progress)
		else
			gateLabel.Text = "EVERY HULL OPEN"
			gateLabel.TextColor3 = Theme.Color.cyan
			gatePercent.Text = "FULL LADDER"
			gateBar.set(1)
		end
	end

	-- Buy keys price the selected rung, not the best unlocked one.
	local oneReady = entry.unlocked and payload.as >= entry.cost
	local tenReady = entry.unlocked and payload.as >= entry.bulk
	if buyOneHandle then
		buyOneHandle.set(
			if oneReady then "ready" else "locked",
			if entry.unlocked then "BUILD 1" else "LOCKED",
			Theme.Color.actionCyan
		)
	end
	if buyTenHandle then
		buyTenHandle.set(
			if tenReady then "ready" else "locked",
			if entry.unlocked then "BUILD 10" else "LOCKED",
			Theme.Color.aether
		)
	end
	if buyOneCost and buyOneNeed then
		buyOneCost.root.Visible = entry.unlocked
		buyOneNeed.Visible = not entry.unlocked
		if entry.unlocked then
			buyOneCost.set(
				NumberUtil.compact(entry.cost),
				if oneReady then Theme.Color.ink else Theme.Color.textSecondary
			)
		else
			buyOneNeed.Text = string.format("%s DRONES REQUIRED", NumberUtil.compact(entry.unlockAt))
		end
	end
	if buyTenCost and buyTenNeed then
		buyTenCost.root.Visible = entry.unlocked
		buyTenNeed.Visible = not entry.unlocked
		if entry.unlocked then
			buyTenCost.set(
				NumberUtil.compact(entry.bulk),
				if tenReady then Theme.Color.white else Theme.Color.textSecondary
			)
		else
			buyTenNeed.Text = string.format("%s DRONES REQUIRED", NumberUtil.compact(entry.unlockAt))
		end
	end

	-- Rack. Every row repaints from the tick payload: owned count, unlock
	-- meter, and the selected border.
	for _, rungId in rackOrder do
		local key = rackRows[rungId]
		local rungTier = DroneRegistry.get(rungId)
		local rung = entryFor(payload, rungId)
		if key ~= nil and rungTier ~= nil and rung ~= nil then
			key.name.Text = string.upper(rungTier.name)
			key.name.TextColor3 = if rung.unlocked then rungTier.glow else Theme.Color.locked
			key.count.Text = NumberUtil.abbreviate(rung.owned)
			key.count.TextColor3 = if rung.owned > 0 then Theme.Color.text else Theme.Color.textDim
			local progress = if rung.unlocked
				then 1
				else math.clamp(payload.drones / math.max(1, rung.unlockAt), 0, 1)
			key.bar.Size = UDim2.fromScale(progress, 1)
			key.bar.BackgroundColor3 = if rung.unlocked then rungTier.glow else Theme.Color.strokeBright
			local chosen = rungId == id
			key.root.BackgroundColor3 = if chosen then Theme.Color.panelRaised else Theme.Color.panelSunken
			key.stroke.Color = if chosen then rungTier.glow else Theme.Color.stroke
			key.stroke.Thickness = if chosen then 2 else 1
		end
	end

	paintExpedition(payload)
	paintSalvage(payload)
	paintCodex(payload)
end

--- Selects a rung and repaints. Public for the Studio seam.
function DroneView.select(id: string): boolean
	if DroneRegistry.get(id) == nil then
		return false
	end
	selectedTier = id
	if latest then
		DroneView.render(latest)
	end
	return true
end

function DroneView.selected(): string?
	return selectedTier
end

function DroneView.destroy()
	if unsubscribe then
		unsubscribe()
		unsubscribe = nil
	end
	if cleanupModel then
		cleanupModel()
		cleanupModel = nil
	end
	for _, cleanup in rackPreviewCleanups do
		cleanup()
	end
	table.clear(rackPreviewCleanups)
	if root then
		root:Destroy()
		root = nil
	end
	scroll = nil
	hero = nil
	rack = nil
	notes = nil
	expeditionCard = nil
	salvageCard = nil
	codexCard = nil
	headerDetail = nil
	viewport = nil
	tierNameLabel = nil
	tierOwnedLabel = nil
	fleetLabel = nil
	outputLabel = nil
	perDroneLabel = nil
	flavorLabel = nil
	gateLabel = nil
	gatePercent = nil
	gateBar = nil
	buyOneHandle = nil
	buyTenHandle = nil
	buyOneCost = nil
	buyOneNeed = nil
	buyTenCost = nil
	buyTenNeed = nil
	selectedTier = nil
	mountedTier = nil
	latest = nil
	table.clear(rackRows)
	table.clear(rackOrder)
	expShelf = nil
	expLive = nil
	expShardLabel = nil
	expTitle = nil
	expTimer = nil
	expReward = nil
	expAether = nil
	expCores = nil
	expShards = nil
	expBar = nil
	table.clear(expButtons)
	table.clear(expDurations)
	expActiveShown = nil
	table.clear(cacheSlots)
	cacheMeterBar = nil
	cacheMeterText = nil
	table.clear(codexRows)
	codexCount = nil
	relayout = nil
end

return DroneView
