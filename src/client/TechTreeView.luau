--!strict
-- Prestige tech tree. The permanent layer: everything bought here survives
-- ascension, which is what makes spending Quantum Cores feel like investment
-- rather than upkeep.
--
-- Costs come from TechTreeConfig on both sides, so the button label and the
-- server's charge can never disagree.
--
-- The page is a tree, not a list:
--
--   sidebar   core reserve, forge feats and the branch totals
--   strike    clicking: momentum, critical forge, phantom hammer
--   fleet     idle: drone lattice, offline core, head start
--   heat      the sweet spot and vent lane, plus a live stats card
--
-- Each branch is a lane with a header, a spine and three cards. Every card keeps
-- its level pips and its next-level effect on its face, so the page can be read
-- without hovering anything.

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

local TechTreeView = {}

local HEADER_H = 58
local PAGE_PAD = 16
local GAP = 14
local SIDEBAR_W = 300
local BRANCH_HEADER_H = 38
local NODE_H = 170
local NODE_GAP = 10
local NOTES_H = 110

type NodeCard = {
	node: TechTreeConfig.Node,
	root: Frame,
	level: TextLabel,
	effect: TextLabel,
	next: TextLabel,
	handle: UiKit.ActionHandle,
	bar: UiKit.BarParts,
	lastKind: UiKit.ActionKind?,
	lastLabel: string?,
}

type FeatRow = {
	name: TextLabel,
	progress: TextLabel,
	bar: UiKit.BarParts,
}

type FeatPanel = {
	count: TextLabel,
	bonus: TextLabel,
	bar: UiKit.BarParts,
	rows: { FeatRow },
}

type Branch = {
	id: string,
	name: string,
	accent: Color3,
	root: Frame,
	count: TextLabel,
	cards: { NodeCard },
}

local root: Frame? = nil
local scroll: ScrollingFrame? = nil
local headerDetail: TextLabel? = nil
local balance: TextLabel? = nil
local balanceNext: TextLabel? = nil
local featPanel: FeatPanel? = nil
local branches: { Branch } = {}
local branchTotals: { [string]: TextLabel } = {}
local heatMult: TextLabel? = nil
local heatBand: TextLabel? = nil
local heatVent: TextLabel? = nil
local unsubscribe: (() -> ())? = nil
local relayout: (() -> ())? = nil

local BRANCH_ORDER = { "strike", "fleet", "heat" }

local BRANCHES = {
	strike = {
		name = "STRIKE",
		accent = Theme.Color.gold,
		nodes = { "start_might", "crit_forge", "auto_click" },
	},
	fleet = {
		name = "FLEET",
		accent = Theme.Color.cyan,
		nodes = { "drone_lattice", "offline_core", "head_start" },
	},
	heat = {
		name = "HEAT",
		accent = Theme.Color.magenta,
		nodes = { "thermal_calibration", "vent_efficiency" },
	},
}

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

	local body = UiKit.create("Frame", {
		Name = "Inner",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(PAGE_PAD, PAGE_PAD),
		Size = UDim2.new(1, -PAGE_PAD * 2, 1, -PAGE_PAD * 2),
	}) :: Frame
	body.Parent = card

	local header = UiKit.header(body, {
		eyebrow = "PERMANENT  /  PRESTIGE",
		title = "TECH TREE",
		detail = "0 CORES",
		height = HEADER_H,
	})
	header.Name = "TechHeader"
	local detail = header:FindFirstChild("Detail")
	if detail and detail:IsA("TextLabel") then
		headerDetail = detail
	end

	local box = UiKit.scroll(body, { thickness = 6, transparency = 0.2 })
	box.Name = "TechBody"
	box.Position = UDim2.fromOffset(0, HEADER_H + 2)
	box.Size = UDim2.new(1, 0, 1, -(HEADER_H + 2))
	box.AutomaticCanvasSize = Enum.AutomaticSize.None
	box.CanvasSize = UDim2.fromOffset(0, 0)
	box.ScrollingDirection = Enum.ScrollingDirection.Y
	box.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	scroll = box
end

-- ---------------------------------------------------------------------------
-- Sidebar
-- ---------------------------------------------------------------------------

local function buildBalance(parent: Frame, y: number)
	local card = UiKit.panel(parent, {
		tier = "raised",
		radius = Theme.Radius.card,
		stroke = Theme.Color.quantum,
		strokeTransparency = 0.55,
	})
	card.Name = "CoreReserve"
	card.Position = UDim2.fromOffset(0, y)
	card.Size = UDim2.new(1, 0, 0, 150)

	local cap = UiKit.eyebrow(card, "CORE RESERVE")
	cap.Position = UDim2.fromOffset(14, 10)

	balance = UiKit.label(card, {
		text = "0",
		size = Theme.Text.Title,
		font = Theme.Font.Numeric,
		color = Theme.Color.quantum,
	})
	balance.Position = UDim2.fromOffset(14, 28)
	balance.Size = UDim2.new(1, -28, 0, 36)

	local rule = UiKit.rule(card, { position = UDim2.fromOffset(14, 72) })
	rule.Size = UDim2.new(1, -28, 0, 1)

	local note = UiKit.label(card, {
		text = "Cores come from THE ASCENT only. Every level below is permanent.",
		size = Theme.Text.Tiny,
		color = Theme.Color.textSecondary,
		wrap = true,
	})
	note.Position = UDim2.fromOffset(14, 82)
	note.Size = UDim2.new(1, -28, 0, 32)

	balanceNext = UiKit.label(card, {
		text = "",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.textFaint,
	})
	balanceNext.Position = UDim2.fromOffset(14, 120)
	balanceNext.Size = UDim2.new(1, -28, 0, 16)
end

local function buildFeatPanel(parent: Frame, y: number): FeatPanel
	local card = UiKit.panel(parent, {
		tier = "item",
		radius = Theme.Radius.card,
		stroke = Theme.Color.gold,
		strokeTransparency = 0.7,
	})
	card.Name = "FeatPanel"
	card.Position = UDim2.fromOffset(0, y)
	card.Size = UDim2.new(1, 0, 0, 300)

	local title = UiKit.label(card, {
		text = "FORGE FEATS",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.gold,
	})
	title.Position = UDim2.fromOffset(14, 8)
	title.Size = UDim2.new(1, -160, 0, 16)

	local count = UiKit.label(card, {
		text = "0 / 0",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Right,
	})
	count.Position = UDim2.new(1, -132, 0, 8)
	count.Size = UDim2.fromOffset(118, 16)

	local bonus = UiKit.label(card, {
		text = "PERMANENT +0% ALL YIELD",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.gold,
	})
	bonus.Position = UDim2.fromOffset(14, 26)
	bonus.Size = UDim2.new(1, -28, 0, 16)

	local bar = UiKit.bar(card, {
		height = 4,
		radius = 2,
		gradient = { Theme.Color.goldDeep, Theme.Color.gold },
	})
	bar.track.Position = UDim2.fromOffset(14, 48)
	bar.track.Size = UDim2.new(1, -28, 0, 4)

	local rows: { FeatRow } = {}
	for index = 1, 4 do
		local rowY = 62 + (index - 1) * 56
		local name = UiKit.label(card, {
			text = "",
			size = Theme.Text.Tiny,
			font = Theme.Font.Black,
			color = Theme.Color.text,
		})
		name.Position = UDim2.fromOffset(14, rowY)
		name.Size = UDim2.new(1, -150, 0, 18)

		local progress = UiKit.label(card, {
			text = "",
			size = Theme.Text.Tiny,
			font = Theme.Font.Numeric,
			color = Theme.Color.textFaint,
			align = Enum.TextXAlignment.Right,
		})
		progress.Position = UDim2.new(1, -142, 0, rowY + 1)
		progress.Size = UDim2.fromOffset(128, 16)

		local rowBar = UiKit.bar(card, {
			height = 3,
			radius = 2,
			gradient = { Theme.Color.goldDeep, Theme.Color.gold },
		})
		rowBar.track.Position = UDim2.fromOffset(14, rowY + 22)
		rowBar.track.Size = UDim2.new(1, -28, 0, 3)

		table.insert(rows, { name = name, progress = progress, bar = rowBar })
	end

	return { count = count, bonus = bonus, bar = bar, rows = rows }
end

local function buildBranchTotals(parent: Frame, y: number)
	local card = UiKit.panel(parent, {
		tier = "item",
		radius = Theme.Radius.card,
	})
	card.Name = "BranchTotals"
	card.Position = UDim2.fromOffset(0, y)
	card.Size = UDim2.new(1, 0, 0, 150)

	local head = UiKit.label(card, {
		text = "BRANCH TOTALS",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.textSecondary,
	})
	head.Position = UDim2.fromOffset(14, 8)
	head.Size = UDim2.new(1, -28, 0, 16)

	for index, id in BRANCH_ORDER do
		local branch = BRANCHES[id]
		local row = UiKit.create("Frame", {
			Name = string.format("Total_%s", id),
			BackgroundColor3 = Theme.Color.panelSunken,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(12, 30 + (index - 1) * 34),
			Size = UDim2.new(1, -24, 0, 28),
		}) :: Frame
		UiKit.corner(row, 4)
		row.Parent = card

		local mark = UiKit.create("Frame", {
			BackgroundColor3 = branch.accent,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.fromOffset(12, 12),
		}) :: Frame
		UiKit.corner(mark, 3)
		mark.Parent = row

		local name = UiKit.label(row, {
			text = branch.name,
			size = Theme.Text.Tiny,
			font = Theme.Font.Black,
			color = Theme.Color.text,
		})
		name.Position = UDim2.fromOffset(28, 5)
		name.Size = UDim2.new(1, -100, 0, 18)

		local value = UiKit.label(row, {
			text = "0 LEVELS",
			size = Theme.Text.Tiny,
			font = Theme.Font.Numeric,
			color = Theme.Color.textFaint,
			align = Enum.TextXAlignment.Right,
		})
		value.Position = UDim2.new(1, -104, 0, 5)
		value.Size = UDim2.fromOffset(94, 18)
		branchTotals[id] = value
	end
end

local function buildSidebar(parent: Frame)
	local side = UiKit.create("Frame", {
		Name = "TechSidebar",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(SIDEBAR_W, 624),
	}) :: Frame
	side.Parent = parent

	buildBalance(side, 0)
	featPanel = buildFeatPanel(side, 162)
	buildBranchTotals(side, 474)
end

-- ---------------------------------------------------------------------------
-- Nodes
-- ---------------------------------------------------------------------------

local function buildNodeCard(parent: Frame, node: TechTreeConfig.Node, accent: Color3, order: number): NodeCard
	local card = UiKit.panel(parent, {
		tier = "item",
		radius = Theme.Radius.md,
		stroke = accent,
		strokeTransparency = 0.8,
	})
	card.Name = string.format("TechNode_%s", node.id)
	card.Size = UDim2.new(1, 0, 0, NODE_H)
	card.Position = UDim2.fromOffset(0, BRANCH_HEADER_H + NODE_GAP + (order - 1) * (NODE_H + NODE_GAP))
	card.ZIndex = 2

	local stripe = UiKit.create("Frame", {
		BackgroundColor3 = accent,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 10),
		Size = UDim2.new(0, 3, 1, -20),
		ZIndex = 3,
	}) :: Frame
	UiKit.corner(stripe, 2)
	stripe.Parent = card

	local well = UiKit.badgeWell(card, {
		image = AssetManifest.uiArt(node.icon),
		size = 56,
		accent = accent,
	})
	if well ~= nil then
		well.Position = UDim2.fromOffset(10, 10)
	end

	local name = UiKit.label(card, {
		text = node.name,
		size = Theme.Text.Small,
		font = Theme.Font.Black,
		color = Theme.Color.text,
	})
	name.Position = UDim2.fromOffset(76, 9)
	name.Size = UDim2.new(1, -86, 0, 20)

	local level = UiKit.label(card, {
		text = "0 / 0",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = accent,
	})
	level.Position = UDim2.fromOffset(76, 29)
	level.Size = UDim2.new(1, -86, 0, 16)

	local desc = UiKit.label(card, {
		text = node.description,
		size = Theme.Text.Tiny,
		color = Theme.Color.textSecondary,
		wrap = true,
	})
	desc.Position = UDim2.fromOffset(76, 47)
	desc.Size = UDim2.new(1, -86, 0, 30)

	local effect = UiKit.label(card, {
		text = "",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = accent,
	})
	effect.Position = UDim2.fromOffset(10, 78)
	effect.Size = UDim2.new(1, -20, 0, 16)

	local bar = UiKit.bar(card, {
		height = 4,
		radius = 2,
		gradient = { Theme.Color.panelSunken, accent },
	})
	bar.track.Position = UDim2.fromOffset(10, 98)
	bar.track.Size = UDim2.new(1, -20, 0, 4)

	local nextLabel = UiKit.label(card, {
		text = "",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.textFaint,
	})
	nextLabel.Position = UDim2.fromOffset(10, 108)
	nextLabel.Size = UDim2.new(1, -20, 0, 16)

	local handle = UiKit.actionButton(card, {
		accent = accent,
		height = 32,
		radius = Theme.Radius.sm,
		size = 13,
		label = "BUY",
		handler = function()
			StateStore.send("buyTech", node.id)
			Sfx.tech()
		end,
	})
	local action = handle.button
	action.Name = string.format("TechBuy_%s", node.id)
	action.AnchorPoint = Vector2.new(0, 1)
	action.Position = UDim2.new(0, 10, 1, -10)
	action.Size = UDim2.new(1, -20, 0, 32)

	return {
		node = node,
		root = card,
		level = level,
		effect = effect,
		next = nextLabel,
		handle = handle,
		bar = bar,
		lastKind = nil,
		lastLabel = nil,
	}
end

local function buildHeatCard(parent: Frame, accent: Color3, order: number)
	local card = UiKit.panel(parent, {
		tier = "well",
		radius = Theme.Radius.md,
		stroke = accent,
		strokeTransparency = 0.75,
	})
	card.Name = "HeatSummary"
	card.Size = UDim2.new(1, 0, 0, NODE_H)
	card.Position = UDim2.fromOffset(0, BRANCH_HEADER_H + NODE_GAP + (order - 1) * (NODE_H + NODE_GAP))
	card.ZIndex = 2

	local head = UiKit.label(card, {
		text = "HEAT READOUT",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = accent,
	})
	head.Position = UDim2.fromOffset(12, 10)
	head.Size = UDim2.new(1, -24, 0, 16)

	local rows = {
		{ key = "mult", caption = "SWEET SPOT", color = Theme.Color.gold },
		{ key = "band", caption = "BAND", color = Theme.Color.starMatter },
		{ key = "vent", caption = "VENT BONUS", color = Theme.Color.aether },
	}
	for index, row in rows do
		local y = 28 + (index - 1) * 36
		local cap = UiKit.label(card, {
			text = row.caption,
			size = Theme.Text.Tiny,
			font = Theme.Font.Numeric,
			color = Theme.Color.textFaint,
		})
		cap.Position = UDim2.fromOffset(12, y)
		cap.Size = UDim2.new(1, -24, 0, 14)

		local value = UiKit.label(card, {
			text = "",
			size = Theme.Text.Subheading,
			font = Theme.Font.Numeric,
			color = row.color,
		})
		value.Position = UDim2.fromOffset(12, y + 14)
		value.Size = UDim2.new(1, -24, 0, 22)

		if row.key == "mult" then
			heatMult = value
		elseif row.key == "band" then
			heatBand = value
		else
			heatVent = value
		end
	end

	local note = UiKit.label(card, {
		text = "Read from the levels you own. Not another purchase.",
		size = Theme.Text.Tiny,
		color = Theme.Color.textFaint,
		wrap = true,
	})
	note.Position = UDim2.fromOffset(12, NODE_H - 32)
	note.Size = UDim2.new(1, -24, 0, 26)
end

local function buildBranch(parent: Frame, id: string, order: number): Branch
	local def = BRANCHES[id]
	local accent = def.accent

	local lane = UiKit.create("Frame", {
		Name = string.format("Branch_%s", id),
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(300, 588),
	}) :: Frame
	lane.Parent = parent

	-- The spine runs behind the cards, in the gaps. It is what makes three
	-- stacked cards read as one lane instead of three tiles.
	local spine = UiKit.create("Frame", {
		Name = "Spine",
		BackgroundColor3 = accent,
		BackgroundTransparency = 0.7,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, BRANCH_HEADER_H),
		Size = UDim2.new(0, 2, 1, -(BRANCH_HEADER_H + 12)),
		ZIndex = 1,
	}) :: Frame
	spine.Parent = lane

	local header = UiKit.create("Frame", {
		Name = "BranchHeader",
		BackgroundColor3 = Theme.Color.card,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, BRANCH_HEADER_H),
		ZIndex = 2,
	}) :: Frame
	UiKit.corner(header, Theme.Radius.sm)
	UiKit.stroke(header, accent, 1, 0.55)
	header.Parent = lane

	local plaque = UiKit.create("Frame", {
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(8, 6),
		Size = UDim2.fromOffset(26, 26),
	}) :: Frame
	UiKit.corner(plaque, 3)
	plaque.Parent = header

	local number = UiKit.label(plaque, {
		text = string.format("%02d", order),
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.onColor(accent),
		align = Enum.TextXAlignment.Center,
	})
	number.Size = UDim2.fromScale(1, 1)

	local title = UiKit.label(header, {
		text = def.name,
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.text,
	})
	title.Position = UDim2.fromOffset(44, 10)
	title.Size = UDim2.new(1, -110, 0, 18)

	local count = UiKit.label(header, {
		text = "0 / 0",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Right,
	})
	count.Position = UDim2.new(1, -80, 0, 10)
	count.Size = UDim2.fromOffset(70, 18)

	local cards: { NodeCard } = {}
	for index, nodeId in def.nodes do
		local node = TechTreeConfig.get(nodeId)
		if node then
			table.insert(cards, buildNodeCard(lane, node, accent, index))
		end
	end

	if id == "heat" then
		buildHeatCard(lane, accent, #cards + 1)
	end

	return { id = id, name = def.name, accent = accent, root = lane, count = count, cards = cards }
end

-- ---------------------------------------------------------------------------
-- Notes
-- ---------------------------------------------------------------------------

local function buildNotes(parent: Frame)
	local card = UiKit.panel(parent, {
		tier = "well",
		radius = Theme.Radius.card,
		stroke = Theme.Color.quantum,
		strokeTransparency = 0.75,
	})
	card.Name = "TechNotes"
	card.Size = UDim2.new(1, 0, 0, NOTES_H)

	local head = UiKit.label(card, {
		text = "HOW CORES WORK",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.quantum,
	})
	head.Position = UDim2.fromOffset(14, 8)
	head.Size = UDim2.new(1, -28, 0, 16)

	local facts = {
		"Every level on this page survives THE ASCENT. Nothing here resets.",
		"Cores come from an ascent, not from Aether. Spend them before the next run.",
		"A maxed node keeps its bonus and its pips, so a full lane is a finished promise.",
	}
	for index, fact in facts do
		local marker = UiKit.label(card, {
			text = string.format("%02d", index),
			size = Theme.Text.Tiny,
			font = Theme.Font.Numeric,
			color = Theme.Color.quantum,
		})
		marker.Position = UDim2.fromOffset(14, 32 + (index - 1) * 24)
		marker.Size = UDim2.fromOffset(24, 16)

		local copy = UiKit.label(card, {
			text = fact,
			size = Theme.Text.Tiny,
			color = Theme.Color.textSecondary,
		})
		copy.Position = UDim2.fromOffset(42, 32 + (index - 1) * 24)
		copy.Size = UDim2.new(1, -56, 0, 16)
	end
end

-- ---------------------------------------------------------------------------
-- Feats
-- ---------------------------------------------------------------------------

local function renderFeats(payload: Types.SyncPayload)
	local panel = featPanel
	if panel == nil then
		return
	end
	local input = FeatConfig.fromSync(payload)
	local done = FeatConfig.completed(input)
	local total = FeatConfig.total()
	panel.count.Text = string.format("%d / %d", done, total)
	panel.bonus.Text = string.format(
		"PERMANENT +%d%% ALL YIELD",
		math.floor(FeatConfig.PerFeatBonus * done * 100 + 0.5)
	)
	panel.bar.set(if total > 0 then done / total else 1)

	local nextFeats = FeatConfig.next(input, #panel.rows)
	for index, row in panel.rows do
		local entry = nextFeats[index]
		if entry ~= nil then
			row.name.Visible = true
			row.name.Text = entry.feat.name
			row.progress.Visible = true
			row.progress.Text = string.format(
				"%s / %s",
				NumberUtil.abbreviate(entry.value),
				NumberUtil.abbreviate(entry.feat.target)
			)
			row.bar.track.Visible = true
			row.bar.set(entry.progress)
		elseif index == 1 then
			row.name.Visible = true
			row.name.Text = "ALL FEATS COMPLETE"
			row.progress.Visible = true
			row.progress.Text = "EVERY LADDER FINISHED"
			row.bar.track.Visible = true
			row.bar.set(1)
		else
			row.name.Visible = false
			row.progress.Visible = false
			row.bar.track.Visible = false
		end
	end
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

relayout = function()
	if root == nil or scroll == nil then
		return
	end

	local bodyW = Layout.CONTENT_W - PAGE_PAD * 2 - 8
	local treeX = SIDEBAR_W + 24
	local branchW = math.floor((bodyW - treeX - GAP * 2) / 3)
	for _, branch in branches do
		branch.root.Size = UDim2.fromOffset(branchW, 588)
	end

	local lane1 = branches[1]
	local lane2 = branches[2]
	local lane3 = branches[3]
	if lane1 and lane2 and lane3 then
		lane1.root.Position = UDim2.fromOffset(treeX, 0)
		lane2.root.Position = UDim2.fromOffset(treeX + branchW + GAP, 0)
		lane3.root.Position = UDim2.fromOffset(treeX + (branchW + GAP) * 2, 0)
	end

	local notes = scroll:FindFirstChild("TechNotes")
	if notes and notes:IsA("GuiObject") then
		notes.Size = UDim2.fromOffset(bodyW - treeX, NOTES_H)
		notes.Position = UDim2.fromOffset(treeX, 600)
	end

	local viewH = Layout.CONTENT_H - PAGE_PAD * 2 - HEADER_H - 2
	scroll.CanvasSize = UDim2.fromOffset(0, math.max(viewH, 724))
end

function TechTreeView.layout()
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

function TechTreeView.init(canvas: Frame, x: number, y: number, width: number, height: number)
	buildPage(canvas, x, y, width, height)
	local body = scroll
	if body == nil then
		return
	end

	buildSidebar(body)
	for index, id in BRANCH_ORDER do
		table.insert(branches, buildBranch(body, id, index))
	end
	buildNotes(body)

	if relayout then
		relayout()
	end

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

-- ---------------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------------

function TechTreeView.render(payload: Types.SyncPayload)
	if headerDetail then
		headerDetail.Text = string.format("%s CORES", NumberUtil.abbreviate(payload.qc))
	end
	if balance then
		balance.Text = NumberUtil.abbreviate(payload.qc)
	end
	renderFeats(payload)

	-- The cheapest node the player can buy right now. It is a nudge, not a
	-- promise: a maxed node is skipped.
	local cheapest: number? = nil
	for _, branch in branches do
		for _, card in branch.cards do
			local level = payload.tech[card.node.id] or 0
			if level < card.node.maxLevel then
				local cost = TechTreeConfig.cost(card.node, level)
				if cheapest == nil or cost < cheapest then
					cheapest = cost
				end
			end
		end
	end
	if balanceNext then
		balanceNext.Text = if cheapest
			then string.format("CHEAPEST NEXT LEVEL  %s QC", NumberUtil.abbreviate(cheapest))
			else "EVERY NODE MAXED"
		balanceNext.TextColor3 = if cheapest and payload.qc >= cheapest
			then Theme.Color.emerald
			else Theme.Color.textFaint
	end

	for _, branch in branches do
		local levels = 0
		local maxLevels = 0
		for _, card in branch.cards do
			local level = payload.tech[card.node.id] or 0
			local maxed = level >= card.node.maxLevel
			local cost = TechTreeConfig.cost(card.node, level)
			local affordable = payload.qc >= cost and not maxed

			levels += level
			maxLevels += card.node.maxLevel

			card.level.Text = string.format("Lv %d / %d", level, card.node.maxLevel)
			card.bar.set(level / math.max(1, card.node.maxLevel))

			if level > 0 then
				card.effect.Text = string.format("Now +%d%%", math.floor(card.node.perLevel * level * 100 + 0.5))
				card.effect.TextColor3 = branch.accent
			else
				card.effect.Text = string.format("Per level +%d%%", math.floor(card.node.perLevel * 100 + 0.5))
				card.effect.TextColor3 = Theme.Color.textFaint
			end

			local kind: UiKit.ActionKind
			local text: string
			if maxed then
				kind = "equipped"
				text = "MAXED"
			elseif affordable then
				kind = "ready"
				text = string.format("BUY  ·  %s QC", NumberUtil.abbreviate(cost))
				card.next.Text = string.format(
					"NEXT +%d%%",
					math.floor(card.node.perLevel * 100 + 0.5)
				)
			else
				kind = "locked"
				text = string.format("%s QC", NumberUtil.abbreviate(cost))
				card.next.Text = string.format("NEED %s MORE", NumberUtil.abbreviate(math.max(0, cost - payload.qc)))
			end
			if maxed then
				card.next.Text = "BONUS IS BANKED"
			end

			if kind ~= card.lastKind or text ~= card.lastLabel then
				card.lastKind = kind
				card.lastLabel = text
				card.handle.set(kind, text, branch.accent)
			end

			card.root.BackgroundTransparency = if level > 0 then 0.02 else 0.06
		end

		if branch.count then
			branch.count.Text = string.format("%d / %d", levels, maxLevels)
			branch.count.TextColor3 = if levels > 0 then branch.accent else Theme.Color.textFaint
		end

		local total = branchTotals[branch.id]
		if total then
			total.Text = string.format("%d LEVELS", levels)
			total.TextColor3 = if levels > 0 then branch.accent else Theme.Color.textFaint
		end
	end

	local stats = TechTreeConfig.compute(payload.tech)
	if heatMult then
		heatMult.Text = string.format("x%.2f", stats.sweetSpotMult)
	end
	if heatBand then
		heatBand.Text = string.format("%d - %d", math.floor(stats.sweetSpotMin), math.floor(stats.sweetSpotMax))
	end
	if heatVent then
		heatVent.Text = string.format("+%d%%", math.floor((stats.ventMult - 1) * 100 + 0.5))
	end
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
	scroll = nil
	headerDetail = nil
	balance = nil
	balanceNext = nil
	featPanel = nil
	branches = {}
	heatMult = nil
	heatBand = nil
	heatVent = nil
	table.clear(branchTotals)
	relayout = nil
end

return TechTreeView
