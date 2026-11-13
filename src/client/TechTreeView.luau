--!strict
-- Prestige tech tree. The permanent layer: everything bought here survives
-- ascension, which is what makes spending cores feel like investment rather
-- than upkeep.
--
-- The page is a tree, not three lanes:
--
--   root -------- momentum ---- critical ---- phantom
--                      |------------- thermal ---- vent
--                      |------------- lattice ---- offline ---- head start
--
-- Every node is a compact tile with its badge, name, level pips and, when it is
-- gated, a lock. Clicking a tile selects it; the inspector on the right owns
-- the long copy, the exact price and the buy key. That keeps the tree readable
-- without printing a paragraph on every node.
--
-- Connectors are neutral ink. A coloured spine behind each branch was the
-- strongest "generated layout" signal on the old page, so there are no lane
-- spines, no branch stripes and no coloured rules here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local TechTreeConfig = require(Shared:WaitForChild("TechTreeConfig"))
local FeatConfig = require(Shared:WaitForChild("FeatConfig"))
local NumberUtil = require(Shared:WaitForChild("NumberUtil"))
local Types = require(Shared:WaitForChild("Types"))
local AssetManifest = require(Shared:WaitForChild("AssetManifest"))

local Theme = require(script.Parent.Theme)
local UiKit = require(script.Parent.UiKit)
local Layout = require(script.Parent.Layout)
local StateStore = require(script.Parent.StateStore)
local Sfx = require(script.Parent.Sfx)
local Icons = require(script.Parent.Icons)

local TechTreeView = {}

local HEADER_H = 58
local PAGE_PAD = 16
local GAP = 16
local SIDEBAR_W = 300
local NODE_W = 140
local NODE_H = 92
local ROOT_SIZE = 88
local DETAIL_H = 352
local SUMMARY_Y = 368
local SUMMARY_H = 146

type NodeGrid = { col: number, row: number }

--- Columns 1 to 4, rows 1 to 3. The root sits at column 0, middle row.
local NODE_GRID: { [string]: NodeGrid } = {
	start_might = { col = 1, row = 2 },
	crit_forge = { col = 2, row = 1 },
	auto_click = { col = 3, row = 1 },
	thermal_calibration = { col = 2, row = 2 },
	vent_efficiency = { col = 3, row = 2 },
	drone_lattice = { col = 2, row = 3 },
	offline_core = { col = 3, row = 3 },
	head_start = { col = 4, row = 3 },
}

local LINKS = {
	{ from = "", to = "start_might" },
	{ from = "start_might", to = "crit_forge" },
	{ from = "crit_forge", to = "auto_click" },
	{ from = "start_might", to = "thermal_calibration" },
	{ from = "thermal_calibration", to = "vent_efficiency" },
	{ from = "start_might", to = "drone_lattice" },
	{ from = "drone_lattice", to = "offline_core" },
	{ from = "offline_core", to = "head_start" },
}

type NodeCard = {
	node: TechTreeConfig.Node,
	root: TextButton,
	stroke: UIStroke,
	name: TextLabel,
	art: ImageLabel,
	pips: { Frame },
	lock: Frame,
	maxTag: TextLabel,
}

type Link = {
	frame: Frame,
	from: string,
	to: string,
}

type Inspector = {
	card: Frame,
	artWell: Frame,
	art: ImageLabel,
	fallback: Frame,
	name: TextLabel,
	level: TextLabel,
	pips: { Frame },
	desc: TextLabel,
	nowLine: TextLabel,
	nextLine: TextLabel,
	costCaption: TextLabel,
	costRow: UiKit.CurrencyRow,
	buy: UiKit.ActionHandle,
	hint: TextLabel,
	treeCount: TextLabel,
	treeBar: UiKit.BarParts,
	featCount: TextLabel,
	featBonus: TextLabel,
	featBar: UiKit.BarParts,
}

local root: Frame? = nil
local body: Frame? = nil
local treePanel: Frame? = nil
local lineLayer: Frame? = nil
local rootTile: Frame? = nil
local inspector: Inspector? = nil
local headerDetailRow: UiKit.CurrencyRow? = nil
local cards: { [string]: NodeCard } = {}
local cardOrder: { NodeCard } = {}
local links: { Link } = {}
local selectedId = "start_might"
local latest: Types.SyncPayload? = nil
local unsubscribe: (() -> ())? = nil

-- ---------------------------------------------------------------------------
-- Small copy helpers
-- ---------------------------------------------------------------------------

--- A node's effect at a given level, in the unit the effect actually uses.
--- The old page printed every `perLevel` as a percentage, so Phantom Hammer
--- said +50% and Head Start said +100%.
local function effectText(node: TechTreeConfig.Node, level: number): string
	if level <= 0 then
		return "NONE"
	end
	if node.effect == "autoClicks" then
		return string.format("+%.1f strikes/s", node.perLevel * level)
	elseif node.effect == "startBlades" then
		local total = math.floor(node.perLevel * level + 0.5)
		return if total == 1 then "+1 starting blade" else string.format("+%d starting blades", total)
	end

	local percent = math.floor(node.perLevel * level * 100 + 0.5)
	if node.effect == "critChance" then
		return string.format("+%d%% crit", percent)
	elseif node.effect == "sweetSpotMult" then
		return string.format("+%d%% payout · +%d° band", percent, 2 * level)
	elseif node.effect == "droneYield" then
		return string.format("+%d%% fleet yield", percent)
	elseif node.effect == "offlineYield" then
		return string.format("+%d%% offline yield", percent)
	elseif node.effect == "ventYield" then
		return string.format("+%d%% vent payout", percent)
	else
		return string.format("+%d%% strike yield", percent)
	end
end

local function pipsFor(host: Frame, count: number, width: number, height: number, gap: number): { Frame }
	local pips: { Frame } = {}
	for index = 1, count do
		local pip = UiKit.create("Frame", {
			Name = string.format("Pip%d", index),
			BackgroundColor3 = Theme.Color.stroke,
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset((index - 1) * (width + gap), 0),
			Size = UDim2.fromOffset(width, height),
			ZIndex = 4,
		}) :: Frame
		UiKit.corner(pip, 1)
		pip.Parent = host
		table.insert(pips, pip)
	end
	return pips
end

local function paintPips(pips: { Frame }, level: number, maxLevel: number, color: Color3)
	for index, pip in pips do
		pip.Visible = index <= maxLevel
		if index <= level then
			pip.BackgroundColor3 = color
			pip.BackgroundTransparency = 0
		else
			pip.BackgroundColor3 = Theme.Color.stroke
			pip.BackgroundTransparency = 0.55
		end
	end
end

-- ---------------------------------------------------------------------------
-- Page shell
-- ---------------------------------------------------------------------------

local function buildPage(canvas: Frame, x: number, y: number, width: number, height: number)
	local card = UiKit.panel(canvas, {
		tier = "shell",
		radius = Theme.Radius.xl,
	})
	card.Name = "Tech"
	card.Size = UDim2.fromOffset(width, height)
	card.Position = UDim2.fromOffset(x, y)
	card.Visible = false
	card.ClipsDescendants = true
	root = card

	local inner = UiKit.create("Frame", {
		Name = "Inner",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(PAGE_PAD, PAGE_PAD),
		Size = UDim2.new(1, -PAGE_PAD * 2, 1, -PAGE_PAD * 2),
	}) :: Frame
	inner.Parent = card
	body = inner

	local header = UiKit.header(inner, {
		eyebrow = "PERMANENT  /  THE ASCENT",
		title = "TECH TREE",
		height = HEADER_H,
	})
	header.Name = "TechHeader"
	headerDetailRow = UiKit.currencyRow(header, {
		kind = "cores",
		text = "0",
		iconSize = 16,
		textSize = Theme.Text.Small,
		color = Theme.Color.textSecondary,
		height = 18,
	})
	headerDetailRow.root.AnchorPoint = Vector2.new(1, 0)
	headerDetailRow.root.Position = UDim2.new(1, -2, 0, 18)
end

-- ---------------------------------------------------------------------------
-- Tree
-- ---------------------------------------------------------------------------

local function buildNode(parent: Frame, node: TechTreeConfig.Node): NodeCard
	local button = UiKit.create("TextButton", {
		Name = string.format("TechNode_%s", node.id),
		BackgroundColor3 = Theme.Color.card,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromOffset(NODE_W, NODE_H),
		ZIndex = 3,
	}) :: TextButton
	UiKit.corner(button, Theme.Radius.md)
	local stroke = UiKit.stroke(button, Theme.Color.stroke, 1, 0)
	UiKit.focus(button, stroke, Theme.Color.stroke, 0)
	button.Parent = parent

	local well = UiKit.create("Frame", {
		Name = "Badge",
		BackgroundColor3 = Theme.Color.panelSunken,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(10, 9),
		Size = UDim2.fromOffset(36, 36),
		ZIndex = 4,
	}) :: Frame
	UiKit.corner(well, 18)
	UiKit.stroke(well, Theme.Color.outline, 2, 0)
	well.Parent = button

	local art = UiKit.create("ImageLabel", {
		Name = "Art",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Image = AssetManifest.uiArt(node.icon),
		ScaleType = Enum.ScaleType.Crop,
		ZIndex = 5,
	}) :: ImageLabel
	UiKit.corner(art, 18)
	art.Parent = well

	local name = UiKit.label(button, {
		text = node.name,
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.text,
		wrap = true,
		alignY = Enum.TextYAlignment.Top,
	})
	name.Name = "Name"
	name.Position = UDim2.fromOffset(52, 7)
	name.Size = UDim2.new(1, -60, 0, 34)
	name.ZIndex = 4

	local status = UiKit.create("Frame", {
		Name = "Status",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 50),
		Size = UDim2.fromOffset(36, 18),
		ZIndex = 4,
	}) :: Frame
	status.Parent = button

	local lock = Icons.build(status, "lock", 16, Theme.Color.textFaint)
	lock.Name = "Lock"
	lock.Position = UDim2.fromOffset(10, 1)
	lock.Visible = false

	local maxTag = UiKit.label(status, {
		text = "MAX",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Center,
	})
	maxTag.Name = "Max"
	maxTag.Position = UDim2.fromOffset(0, 0)
	maxTag.Size = UDim2.fromOffset(36, 18)
	maxTag.Visible = false

	local pipHost = UiKit.create("Frame", {
		Name = "Pips",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 76),
		Size = UDim2.fromOffset(NODE_W - 20, 5),
		ZIndex = 4,
	}) :: Frame
	pipHost.Parent = button

	local gap = 2
	local pipW = math.max(4, math.floor(((NODE_W - 20) - gap * (node.maxLevel - 1)) / node.maxLevel))
	local pips = pipsFor(pipHost, node.maxLevel, pipW, 5, gap)

	UiKit.track(button, button.MouseEnter:Connect(function()
		if selectedId ~= node.id then
			button.BackgroundColor3 = Theme.Color.panelRaised
		end
	end))
	UiKit.track(button, button.MouseLeave:Connect(function()
		button.BackgroundColor3 = Theme.Color.card
	end))
	UiKit.track(button, button.Activated:Connect(function()
		selectedId = node.id
		Sfx.ui()
		if latest then
			TechTreeView.render(latest)
		end
	end))

	return {
		node = node,
		root = button,
		stroke = stroke,
		name = name,
		art = art,
		pips = pips,
		lock = lock,
		maxTag = maxTag,
	}
end

local function buildRootTile(parent: Frame): Frame
	local tile = UiKit.create("Frame", {
		Name = "PrestigeRoot",
		BackgroundColor3 = Theme.Color.card,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(ROOT_SIZE, ROOT_SIZE),
		ZIndex = 3,
	}) :: Frame
	UiKit.corner(tile, math.floor(ROOT_SIZE / 2))
	UiKit.stroke(tile, Theme.Color.stroke, 1, 0.1)
	tile.Parent = parent

	local markHost = UiKit.create("Frame", {
		Name = "Mark",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(22, 19),
		Size = UDim2.fromOffset(44, 44),
		ZIndex = 4,
	}) :: Frame
	markHost.Parent = tile
	local mark = Icons.build(markHost, "core", 40, Theme.Color.quantum)
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.Position = UDim2.fromScale(0.5, 0.5)

	local label = UiKit.label(tile, {
		text = "THE ASCENT",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Center,
	})
	label.Position = UDim2.fromOffset(0, 64)
	label.Size = UDim2.fromOffset(ROOT_SIZE, 14)
	label.ZIndex = 4

	return tile
end

local function buildTree(parent: Frame)
	local panel = UiKit.panel(parent, {
		tier = "well",
		radius = Theme.Radius.card,
	})
	panel.Name = "TechCanvas"
	panel.ClipsDescendants = true
	treePanel = panel

	local lines = UiKit.create("Frame", {
		Name = "Links",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
	}) :: Frame
	lines.Parent = panel
	lineLayer = lines

	for _, spec in LINKS do
		local frame = UiKit.create("Frame", {
			Name = string.format("Link_%s_%s", if spec.from == "" then "root" else spec.from, spec.to),
			BackgroundColor3 = Theme.Color.stroke,
			BackgroundTransparency = 0.72,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(1, 2),
			ZIndex = 1,
		}) :: Frame
		frame.Parent = lines
		table.insert(links, { frame = frame, from = spec.from, to = spec.to })
	end

	rootTile = buildRootTile(panel)
	for _, node in TechTreeConfig.list() do
		local card = buildNode(panel, node)
		cards[node.id] = card
		table.insert(cardOrder, card)
	end
end

local function columns(width: number): { number }
	local usable = math.max(0, width - 160)
	return {
		80,
		80 + usable * 0.25,
		80 + usable * 0.50,
		80 + usable * 0.75,
		80 + usable,
	}
end

local function rows(height: number): { number }
	return { height * 0.23, height * 0.50, height * 0.77 }
end

local function nodeCenter(id: string, xs: { number }, ys: { number }): Vector2
	if id == "" then
		return Vector2.new(xs[1], ys[2])
	end
	local grid = NODE_GRID[id]
	if grid == nil then
		return Vector2.new(xs[1], ys[2])
	end
	return Vector2.new(xs[grid.col + 1], ys[grid.row])
end

local function layoutTree(width: number, height: number)
	if treePanel == nil or lineLayer == nil or rootTile == nil then
		return
	end

	local xs = columns(width)
	local ys = rows(height)

	if rootTile then
		rootTile.Position = UDim2.fromOffset(xs[1] - ROOT_SIZE / 2, ys[2] - ROOT_SIZE / 2)
	end
	for id, card in cards do
		local grid = NODE_GRID[id]
		if grid ~= nil then
			card.root.Position = UDim2.fromOffset(
				xs[grid.col + 1] - NODE_W / 2,
				ys[grid.row] - NODE_H / 2
			)
		end
	end

	for _, link in links do
		local a = nodeCenter(link.from, xs, ys)
		local b = nodeCenter(link.to, xs, ys)
		local delta = b - a
		local length = math.max(1, delta.Magnitude)
		link.frame.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
		link.frame.Size = UDim2.fromOffset(length, 2)
		link.frame.Rotation = math.deg(math.atan2(delta.Y, delta.X))
	end
end

-- ---------------------------------------------------------------------------
-- Inspector
-- ---------------------------------------------------------------------------

local function buildInspector(parent: Frame): Inspector
	local card = UiKit.panel(parent, {
		tier = "raised",
		radius = Theme.Radius.card,
	})
	card.Name = "TechInspector"

	local detail = UiKit.panel(card, {
		tier = "item",
		radius = Theme.Radius.md,
	})
	detail.Name = "Detail"
	detail.Position = UDim2.fromOffset(0, 0)
	detail.Size = UDim2.new(1, 0, 0, DETAIL_H)

	local artWell = UiKit.create("Frame", {
		Name = "SelectedBadge",
		BackgroundColor3 = Theme.Color.panelSunken,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(14, 28),
		Size = UDim2.fromOffset(56, 56),
	}) :: Frame
	UiKit.corner(artWell, 28)
	UiKit.stroke(artWell, Theme.Color.outline, 2, 0)
	artWell.Parent = detail

	local art = UiKit.create("ImageLabel", {
		Name = "Art",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ScaleType = Enum.ScaleType.Crop,
	}) :: ImageLabel
	UiKit.corner(art, 28)
	art.Parent = artWell

	local fallback = UiKit.create("Frame", {
		Name = "Fallback",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 14),
		Size = UDim2.fromOffset(28, 28),
	}) :: Frame
	fallback.Parent = artWell
	local fallbackIcon = Icons.build(fallback, "tech", 28, Theme.Color.textFaint)
	fallbackIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	fallbackIcon.Position = UDim2.fromScale(0.5, 0.5)
	fallback.Visible = false

	local name = UiKit.label(detail, {
		text = "FORGED MOMENTUM",
		size = Theme.Text.Subheading,
		font = Theme.Font.Heading,
		color = Theme.Color.text,
	})
	name.Position = UDim2.fromOffset(82, 26)
	name.Size = UDim2.new(1, -96, 0, 26)

	local level = UiKit.label(detail, {
		text = "LEVEL 0 / 10",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.textFaint,
	})
	level.Position = UDim2.fromOffset(82, 54)
	level.Size = UDim2.new(1, -96, 0, 16)

	local pipHost = UiKit.create("Frame", {
		Name = "Pips",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(82, 76),
		Size = UDim2.new(1, -96, 0, 8),
	}) :: Frame
	pipHost.Parent = detail
	local pips = pipsFor(pipHost, 10, 8, 8, 3)

	local rule = UiKit.rule(detail, { position = UDim2.fromOffset(14, 104) })
	rule.Size = UDim2.new(1, -28, 0, 1)

	local desc = UiKit.label(detail, {
		text = "",
		size = Theme.Text.Tiny,
		color = Theme.Color.textSecondary,
		wrap = true,
		alignY = Enum.TextYAlignment.Top,
	})
	desc.Position = UDim2.fromOffset(14, 114)
	desc.Size = UDim2.new(1, -28, 0, 38)

	local nowLine = UiKit.label(detail, {
		text = "NOW   0%",
		size = Theme.Text.Small,
		font = Theme.Font.Numeric,
		color = Theme.Color.textDim,
	})
	nowLine.Position = UDim2.fromOffset(14, 158)
	nowLine.Size = UDim2.new(1, -28, 0, 20)

	local nextLine = UiKit.label(detail, {
		text = "NEXT  +25%",
		size = Theme.Text.Small,
		font = Theme.Font.Numeric,
		color = Theme.Color.textFaint,
	})
	nextLine.Position = UDim2.fromOffset(14, 180)
	nextLine.Size = UDim2.new(1, -28, 0, 20)

	local costCaption = UiKit.label(detail, {
		text = "NEXT LEVEL",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.textFaint,
	})
	costCaption.Position = UDim2.fromOffset(14, 210)
	costCaption.Size = UDim2.new(1, -28, 0, 16)

	local costRow = UiKit.currencyRow(detail, {
		kind = "cores",
		text = "0",
		iconSize = 16,
		textSize = Theme.Text.Body,
		color = Theme.Color.text,
		height = 20,
	})
	costRow.root.Position = UDim2.fromOffset(14, 228)

	local buy = UiKit.actionButton(detail, {
		accent = Theme.Color.quantum,
		height = 44,
		radius = Theme.Radius.sm,
		size = 15,
		label = "BUY LEVEL",
		handler = function()
			local node = TechTreeConfig.get(selectedId)
			if node ~= nil then
				StateStore.send("buyTech", node.id)
				Sfx.tech()
			end
		end,
	})
	buy.button.Name = "BuyTech"
	buy.button.Position = UDim2.fromOffset(14, 258)
	buy.button.Size = UDim2.new(1, -28, 0, 44)

	local hint = UiKit.label(detail, {
		text = "",
		size = Theme.Text.Tiny,
		color = Theme.Color.textFaint,
		wrap = true,
		alignY = Enum.TextYAlignment.Top,
	})
	hint.Position = UDim2.fromOffset(14, 310)
	hint.Size = UDim2.new(1, -28, 0, 32)

	local summary = UiKit.panel(card, {
		tier = "item",
		radius = Theme.Radius.md,
	})
	summary.Name = "Progress"
	summary.Position = UDim2.fromOffset(0, SUMMARY_Y)
	summary.Size = UDim2.new(1, 0, 0, SUMMARY_H)

	local treeLabel = UiKit.eyebrow(summary, "TREE PROGRESS")
	treeLabel.Position = UDim2.fromOffset(14, 10)

	local treeCount = UiKit.label(summary, {
		text = "0 / 0",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Right,
	})
	treeCount.Position = UDim2.new(1, -120, 0, 9)
	treeCount.Size = UDim2.fromOffset(106, 16)

	local treeBar = UiKit.bar(summary, {
		height = 4,
		radius = 2,
		fill = Theme.Color.quantum,
	})
	treeBar.track.Position = UDim2.fromOffset(14, 34)
	treeBar.track.Size = UDim2.new(1, -28, 0, 4)

	local featLabel = UiKit.eyebrow(summary, "FORGE FEATS")
	featLabel.Position = UDim2.fromOffset(14, 62)

	local featCount = UiKit.label(summary, {
		text = "0 / 0",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Right,
	})
	featCount.Position = UDim2.new(1, -120, 0, 61)
	featCount.Size = UDim2.fromOffset(106, 16)

	local featBonus = UiKit.label(summary, {
		text = "+0% ALL YIELD",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.gold,
	})
	featBonus.Position = UDim2.fromOffset(14, 80)
	featBonus.Size = UDim2.new(1, -28, 0, 16)

	local featBar = UiKit.bar(summary, {
		height = 3,
		radius = 2,
		fill = Theme.Color.gold,
	})
	featBar.track.Position = UDim2.fromOffset(14, 106)
	featBar.track.Size = UDim2.new(1, -28, 0, 3)

	card.Size = UDim2.fromOffset(SIDEBAR_W, DETAIL_H + SUMMARY_Y + SUMMARY_H)
	card.Parent = parent

	return {
		card = card,
		artWell = artWell,
		art = art,
		fallback = fallback,
		name = name,
		level = level,
		pips = pips,
		desc = desc,
		nowLine = nowLine,
		nextLine = nextLine,
		costCaption = costCaption,
		costRow = costRow,
		buy = buy,
		hint = hint,
		treeCount = treeCount,
		treeBar = treeBar,
		featCount = featCount,
		featBonus = featBonus,
		featBar = featBar,
	}
end

-- ---------------------------------------------------------------------------
-- Paint
-- ---------------------------------------------------------------------------

local function paintInspector(payload: Types.SyncPayload)
	local view = inspector
	if view == nil then
		return
	end

	local node = TechTreeConfig.get(selectedId)
	if node == nil then
		return
	end

	local level = math.clamp(payload.tech[node.id] or 0, 0, node.maxLevel)
	local maxed = level >= node.maxLevel
	local available = TechTreeConfig.available(node, payload.tech)
	local parent, needed = TechTreeConfig.requirement(node, payload.tech)
	local cost = TechTreeConfig.cost(node, level)
	local affordable = not maxed and available and payload.qc >= cost

	view.name.Text = string.upper(node.name)
	view.level.Text = string.format("LEVEL %d / %d", level, node.maxLevel)
	view.desc.Text = node.description
	view.nowLine.Text = "NOW   " .. effectText(node, level)
	view.nextLine.Text = if maxed then "NEXT  MASTERED" else "NEXT  " .. effectText(node, level + 1)
	view.nextLine.TextColor3 = if maxed then Theme.Color.textFaint else Theme.Color.text
	paintPips(view.pips, level, node.maxLevel, Theme.Color.quantum)

	local artId = AssetManifest.uiArt(node.icon)
	view.art.Image = artId
	view.art.Visible = artId ~= ""
	view.fallback.Visible = artId == ""

	if maxed then
		view.costCaption.Visible = false
		view.costRow.root.Visible = false
		view.buy.set("equipped", "MASTERED", Theme.Color.emerald)
		view.hint.Text = "MASTERED. The bonus stays through every ascent."
	else
		view.costCaption.Visible = true
		view.costRow.root.Visible = true
		view.costRow.set(NumberUtil.abbreviate(cost), if affordable then Theme.Color.text else Theme.Color.textFaint)

		if not available then
			view.buy.set("locked", "LOCKED", Theme.Color.textFaint)
			local parentName = if parent then parent.name else "the parent node"
			view.hint.Text = string.format("REQUIRES %s LV %d", string.upper(parentName), needed or 1)
		elseif affordable then
			view.buy.set("ready", "BUY LEVEL", Theme.Color.quantum)
			view.hint.Text = "PERMANENT. NEVER RESETS."
		else
			view.buy.set("locked", "NOT ENOUGH", Theme.Color.textFaint)
			view.hint.Text = "EARN MORE IN THE FORGE, THEN COME BACK."
		end
	end

end

local function paintTree(payload: Types.SyncPayload)
	for _, card in cardOrder do
		local node = card.node
		local level = math.clamp(payload.tech[node.id] or 0, 0, node.maxLevel)
		local maxed = level >= node.maxLevel
		local available = TechTreeConfig.available(node, payload.tech)
		local selected = selectedId == node.id

		paintPips(card.pips, level, node.maxLevel, Theme.Color.quantum)
		card.art.ImageColor3 = if available or level > 0 then Theme.Color.white else Theme.Color.locked
		card.art.ImageTransparency = if available or level > 0 then 0 else 0.58
		card.name.TextColor3 = if available or level > 0 then Theme.Color.text else Theme.Color.textFaint
		card.maxTag.Visible = maxed
		card.lock.Visible = not available and not maxed

		if selected then
			card.stroke.Color = Theme.Color.text
			card.stroke.Thickness = 2
			card.stroke.Transparency = 0
		elseif level > 0 then
			card.stroke.Color = Theme.Color.textFaint
			card.stroke.Thickness = 1
			card.stroke.Transparency = 0.15
		else
			card.stroke.Color = Theme.Color.stroke
			card.stroke.Thickness = 1
			card.stroke.Transparency = 0
		end
	end

	for _, link in links do
		local fromLevel = if link.from == "" then 1 else (payload.tech[link.from] or 0)
		local toLevel = payload.tech[link.to] or 0
		local target = TechTreeConfig.get(link.to)
		-- A link is lit when the path is open: either the child is bought, or
		-- its gate is already met and the next level is on sale. Links past a
		-- closed gate stay dim, so the tree shows the frontier instead of a
		-- uniform web.
		local open = fromLevel > 0
			and (toLevel > 0 or (target ~= nil and TechTreeConfig.available(target, payload.tech)))
		link.frame.BackgroundColor3 = if open then Theme.Color.textFaint else Theme.Color.stroke
		link.frame.BackgroundTransparency = if open then 0.55 else 0.8
	end
end

local function paintProgress(payload: Types.SyncPayload)
	local view = inspector
	if view == nil then
		return
	end

	local levels = 0
	local maxLevels = 0
	for _, node in TechTreeConfig.list() do
		levels += math.clamp(payload.tech[node.id] or 0, 0, node.maxLevel)
		maxLevels += node.maxLevel
	end
	view.treeCount.Text = string.format("%d / %d", levels, maxLevels)
	view.treeBar.set(if maxLevels > 0 then levels / maxLevels else 0)

	local input = FeatConfig.fromSync(payload)
	local done = FeatConfig.completed(input)
	local total = FeatConfig.total()
	local bonus = math.floor(FeatConfig.PerFeatBonus * done * 100 + 0.5)
	view.featCount.Text = string.format("%d / %d", done, total)
	view.featBonus.Text = string.format("+%d%% ALL YIELD", bonus)
	view.featBar.set(if total > 0 then done / total else 0)
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------

function TechTreeView.layout()
	if root == nil or body == nil or treePanel == nil or inspector == nil then
		return
	end

	root.Size = UDim2.fromOffset(Layout.CONTENT_W, Layout.CONTENT_H)
	root.Position = UDim2.fromOffset(Layout.CONTENT_X, Layout.CONTENT_Y)

	local bodyW = Layout.CONTENT_W - PAGE_PAD * 2
	local bodyH = Layout.CONTENT_H - PAGE_PAD * 2
	local treeH = bodyH - HEADER_H - 2
	local treeW = bodyW - SIDEBAR_W - GAP

	treePanel.Position = UDim2.fromOffset(0, HEADER_H + 2)
	treePanel.Size = UDim2.fromOffset(treeW, treeH)
	inspector.card.Position = UDim2.fromOffset(treeW + GAP, HEADER_H + 2)
	inspector.card.Size = UDim2.fromOffset(SIDEBAR_W, treeH)
	layoutTree(treeW, treeH)
end

function TechTreeView.init(canvas: Frame, x: number, y: number, width: number, height: number)
	buildPage(canvas, x, y, width, height)

	local inner = body
	if inner == nil then
		return
	end

	buildTree(inner)
	inspector = buildInspector(inner)
	TechTreeView.layout()

	unsubscribe = StateStore.onSync(function(payload: Types.SyncPayload)
		TechTreeView.render(payload)
	end)

	local current = StateStore.current
	if current then
		TechTreeView.render(current)
	end
end

function TechTreeView.card(): Frame?
	return root
end

--- Dev seam: select a node without a pointer press so the inspector's locked
--- and affordable states can be photographed on one profile.
function TechTreeView.select(id: string): boolean
	if TechTreeConfig.get(id) == nil then
		return false
	end
	selectedId = id
	if latest then
		TechTreeView.render(latest)
	end
	return true
end

--- Paints every region from one payload. `render` stores the payload; the
--- preview seam paints a copy and leaves the stored state alone.
local function paint(payload: Types.SyncPayload)
	if headerDetailRow then
		headerDetailRow.set(NumberUtil.abbreviate(payload.qc))
	end
	paintTree(payload)
	paintInspector(payload)
	paintProgress(payload)
end

--- Dev seam: render a temporary level table so the locked and affordable
--- inspector states can be photographed on a maxed profile. The next real sync
--- or a selection still reads the player's true state.
function TechTreeView.preview(levels: { [string]: number }, qc: number?): boolean
	local base = latest
	if base == nil then
		return false
	end
	local copy = table.clone(base)
	copy.tech = table.clone(levels)
	if qc ~= nil then
		copy.qc = qc
	end
	paint(copy)
	return true
end

function TechTreeView.render(payload: Types.SyncPayload)
	latest = payload
	paint(payload)
end

function TechTreeView.destroy()
	if unsubscribe then
		unsubscribe()
		unsubscribe = nil
	end
	if root then
		root:Destroy()
		root = nil
	end
	body = nil
	treePanel = nil
	lineLayer = nil
	rootTile = nil
	inspector = nil
	headerDetailRow = nil
	cards = {}
	cardOrder = {}
	links = {}
	latest = nil
	selectedId = "start_might"
end

return TechTreeView
