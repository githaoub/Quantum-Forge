--!strict
-- The collection index: every blade, variant, element, grade and affix the
-- account has ever seen, and a silhouette for the ones it has not.
--
-- Why this exists as its own panel: the vault answers "what do I own right
-- now", which is a much smaller question than "what is there to own". A forge
-- with a million legal copies needs a screen that shows the ladder, or the hunt
-- has no visible top rung.
--
-- The index is a set keyed `namespace:id` on the server. Discoveries are
-- permanent and survive ascension and melting, because the codex records the
-- account rather than the current vault.
--
-- Painting rule: unknown cells are the same silhouette the forge uses for an
-- unrevealed roll, not a blank plate. A locked cell that renders as nothing
-- reads as a bug.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BladeRegistry = require(Shared:WaitForChild("BladeRegistry"))
local ForgeConfig = require(Shared:WaitForChild("ForgeConfig"))
local ModifierConfig = require(Shared:WaitForChild("ModifierConfig"))
local NumberUtil = require(Shared:WaitForChild("NumberUtil"))

local Theme = require(script.Parent.Theme)
local UiKit = require(script.Parent.UiKit)
local BladePreview = require(script.Parent.BladePreview)
local ModalShell = require(script.Parent.ModalShell)
local StateStore = require(script.Parent.StateStore)
local Sfx = require(script.Parent.Sfx)

local CodexView = {}

local CELL_W = 178
local CELL_H = 172

local shell: ModalShell.Handle? = nil
local tabBar: Frame? = nil
local grid: ScrollingFrame? = nil
local summary: TextLabel? = nil
local progress: TextLabel? = nil
local activeTab = "blades"
local unsubscribe: (() -> ())? = nil

local TABS = {
	{ id = "blades", label = "BLADES", accent = Theme.Color.gold },
	{ id = "quality", label = "QUALITY", accent = Theme.Color.starMatter },
	{ id = "variants", label = "VARIANTS", accent = Theme.Color.cyan },
	{ id = "elements", label = "ELEMENTS", accent = Theme.Color.emerald },
	{ id = "grades", label = "GRADES", accent = Theme.Color.quantum },
	{ id = "affixes", label = "AFFIXES", accent = Theme.Color.red },
}

--- Every key the codex can hold, in the order the tabs show them. Built once:
--- the total is what the footer counts against.
local ALL_KEYS: { { namespace: string, id: string } } = {}
for _, blade in BladeRegistry.list() do
	table.insert(ALL_KEYS, { namespace = "blade", id = blade.id })
end
for _, id in ForgeConfig.VariantOrder do
	table.insert(ALL_KEYS, { namespace = "variant", id = id })
end
for _, id in ModifierConfig.ElementOrder do
	table.insert(ALL_KEYS, { namespace = "element", id = id })
end
for _, id in ModifierConfig.GradeOrder do
	table.insert(ALL_KEYS, { namespace = "grade", id = id })
end
for _, id in ModifierConfig.PrefixOrder do
	table.insert(ALL_KEYS, { namespace = "prefix", id = id })
end
for _, id in ModifierConfig.SuffixOrder do
	table.insert(ALL_KEYS, { namespace = "suffix", id = id })
end
for _, quality in ModifierConfig.qualityLadder() do
	table.insert(ALL_KEYS, { namespace = "quality", id = quality.id })
end

local function found(namespace: string, id: string): boolean
	return StateStore.codex[namespace .. ":" .. id] == true
end

local function countFound(): number
	local total = 0
	for _, entry in ALL_KEYS do
		if found(entry.namespace, entry.id) then
			total += 1
		end
	end
	return total
end

--- One cell. `render` decides whether the cell shows art or a silhouette; the
--- four text-only tabs pass nil and get a coloured plate with a glyph instead.
local function cell(
	order: number,
	name: string,
	sub: string,
	color: Color3,
	known: boolean,
	blade: BladeRegistry.Blade?,
	variantTint: Color3?
)
	local card = UiKit.panel(grid :: ScrollingFrame, {
		tier = "well",
		radius = Theme.Radius.card,
		stroke = if known then Theme.Color.stroke else Theme.Color.strokeFaint,
		bevel = false,
		lip = false,
	})
	card.Name = string.format("CodexCell_%d", order)
	card.Size = UDim2.fromOffset(CELL_W, CELL_H)
	card.LayoutOrder = order

	local bar = UiKit.create("Frame", {
		BackgroundColor3 = if known then color else Theme.Color.strokeFaint,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 4),
		ZIndex = 2,
	}) :: Frame
	UiKit.corner(bar, 2)
	bar.Parent = card

	if blade then
		local stage = UiKit.create("ViewportFrame", {
			Name = "CodexThumb",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(41, 14),
			Size = UDim2.fromOffset(96, 96),
			ZIndex = 2,
		}) :: ViewportFrame
		stage.Parent = card
		-- Silhouette for an undiscovered blade: the shape is the tease, the
		-- colour and name are the reward.
		BladePreview.thumbnail(stage, blade, not known, variantTint or color)
	end

	local title = UiKit.label(card, {
		text = if known then name else "???",
		size = Theme.Text.Tiny,
		font = Theme.Font.Heading,
		color = if known then Theme.Color.text else Theme.Color.locked,
		align = Enum.TextXAlignment.Center,
		stroke = true,
	})
	title.Position = UDim2.fromOffset(6, 116)
	title.Size = UDim2.new(1, -12, 0, 18)
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.ZIndex = 3

	local caption = UiKit.label(card, {
		text = if known then sub else "UNDISCOVERED",
		size = Theme.Text.Tiny,
		font = Theme.Font.Label,
		color = if known then color else Theme.Color.textFaint,
		align = Enum.TextXAlignment.Center,
		stroke = true,
	})
	caption.Position = UDim2.fromOffset(6, 136)
	caption.Size = UDim2.new(1, -12, 0, 16)
	caption.TextTruncate = Enum.TextTruncate.AtEnd
	caption.ZIndex = 3
end

local function paintBlades()
	for index, blade in BladeRegistry.list() do
		local known = found("blade", blade.id)
		cell(
			index,
			blade.name,
			string.format("%s  TIER %d", string.upper(blade.rarity), blade.tier),
			Theme.rarityColor(blade.tier),
			known,
			blade,
			nil
		)
	end
end

local function paintVariants()
	for index, id in ForgeConfig.VariantOrder do
		local variant = ForgeConfig.variant(id)
		local known = found("variant", id)
		cell(index, variant.name, string.format("x%.2f POWER", variant.mult), variant.color, known, nil, nil)
	end
end

local function paintElements()
	for index, id in ModifierConfig.ElementOrder do
		local element = ModifierConfig.element(id)
		local known = found("element", id)
		cell(
			index,
			element.name,
			string.format("x%.2f  +%.0f%% CRIT", element.mult, element.critChance * 100),
			element.color,
			known,
			nil,
			nil
		)
	end
end

local function paintGrades()
	for index, id in ModifierConfig.GradeOrder do
		local grade = ModifierConfig.grade(id)
		local known = found("grade", id)
		cell(index, grade.name, string.format("x%.2f POWER", grade.mult), grade.color, known, nil, nil)
	end
end

local function paintAffixes()
	local order = 1
	for _, id in ModifierConfig.PrefixOrder do
		local affix = ModifierConfig.prefix(id)
		if affix then
			cell(order, affix.name, string.format("PREFIX  x%.2f", affix.mult), Theme.Color.cyan, found("prefix", id), nil, nil)
			order += 1
		end
	end
	for _, id in ModifierConfig.SuffixOrder do
		local affix = ModifierConfig.suffix(id)
		if affix then
			cell(order, affix.name, string.format("SUFFIX  x%.2f", affix.mult), Theme.Color.quantum, found("suffix", id), nil, nil)
			order += 1
		end
	end
end

--- The quality ladder. Thirty-two named bands, `Chipped-` through
--- `Primordial++`, each printing the multiplier a copy in that band carries,
--- with four pips showing where the band sits inside its grade family.
---
--- No art: the point is the ladder, and a ladder of text reads faster than a
--- ladder of icons, which is the whole reason this tab exists.
local function paintQuality()
	local CARD_H = 132
	for index, quality in ModifierConfig.qualityLadder() do
		local known = found("quality", quality.id)
		local card = UiKit.panel(grid :: ScrollingFrame, {
			tier = "well",
			radius = Theme.Radius.sm,
			stroke = if known then quality.color else Theme.Color.strokeFaint,
			bevel = false,
			lip = false,
		})
		card.Name = string.format("CodexCell_%d", index)
		card.Size = UDim2.fromOffset(CELL_W, CARD_H)
		card.LayoutOrder = index

		local bar = UiKit.create("Frame", {
			BackgroundColor3 = if known then quality.color else Theme.Color.strokeFaint,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 4),
			ZIndex = 2,
		}) :: Frame
		UiKit.corner(bar, 2)
		bar.Parent = card

		local name = UiKit.label(card, {
			text = if known then quality.name else "???",
			size = Theme.Text.Small,
			font = Theme.Font.Black,
			color = if known then Theme.Color.text else Theme.Color.locked,
			align = Enum.TextXAlignment.Center,
			stroke = true,
		})
		name.Position = UDim2.fromOffset(6, 28)
		name.Size = UDim2.new(1, -12, 0, 24)
		name.ZIndex = 3

		local mult = UiKit.label(card, {
			text = if known then string.format("x%.2f", quality.mult) else "UNDISCOVERED",
			size = Theme.Text.Tiny,
			font = Theme.Font.Numeric,
			color = if known then quality.color else Theme.Color.textFaint,
			align = Enum.TextXAlignment.Center,
			stroke = true,
		})
		mult.Position = UDim2.fromOffset(6, 58)
		mult.Size = UDim2.new(1, -12, 0, 20)
		mult.ZIndex = 3

		local step = UiKit.label(card, {
			text = string.format("STEP %d OF 4", quality.step),
			size = Theme.Text.Tiny,
			font = Theme.Font.Label,
			color = Theme.Color.textFaint,
			align = Enum.TextXAlignment.Center,
		})
		step.Position = UDim2.fromOffset(6, 88)
		step.Size = UDim2.new(1, -12, 0, 18)
		step.ZIndex = 3

		-- Four pips, filled up to this band. A single number in a wall of
		-- twenty-four cells is hard to place; the pips make the ladder visible
		-- without adding another text row.
		for pip = 1, 4 do
			local lit = pip <= quality.step
			local dot = UiKit.create("Frame", {
				BackgroundColor3 = if lit and known then quality.color else Theme.Color.strokeFaint,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(29 + (pip - 1) * 32, 112),
				Size = UDim2.fromOffset(24, 8),
				ZIndex = 3,
			}) :: Frame
			UiKit.corner(dot, 4)
			if lit and known then
				UiKit.stroke(dot, quality.color, 1, 0.45)
			end
			dot.Parent = card
		end
	end
end

local PAINTERS: { [string]: () -> () } = {
	blades = paintBlades,
	quality = paintQuality,
	variants = paintVariants,
	elements = paintElements,
	grades = paintGrades,
	affixes = paintAffixes,
}

local function refreshHeader()
	local total = #ALL_KEYS
	local seen = countFound()
	local combos = ModifierConfig.combinations(#BladeRegistry.list(), #ForgeConfig.VariantOrder)
	if summary then
		summary.Text = string.format("%d / %d DISCOVERED", seen, total)
	end
	if progress then
		progress.Text = string.format("%s COMBINATIONS", NumberUtil.abbreviate(combos))
	end
end

local function paintTabs()
	local bar = tabBar
	if bar == nil then
		return
	end
	ModalShell.clear(bar)

	for index, spec in TABS do
		local active = activeTab == spec.id
		local pill = UiKit.button(bar, {
			text = spec.label,
			fill = if active then spec.accent else Theme.Color.slate,
			stroke = if active then Theme.Color.outline else Theme.Color.stroke,
			height = 34,
			radius = Theme.Radius.sm,
			size = Theme.Text.Tiny,
			font = Theme.Font.Black,
			textColor = if active then Theme.Color.text else Theme.Color.textDim,
			handler = function()
				if activeTab == spec.id then
					return
				end
				activeTab = spec.id
				Sfx.tab()
				paintTabs()
				CodexView.refresh()
			end,
		})
		pill.Name = "CodexTab_" .. spec.id
		pill.Position = UDim2.fromOffset((index - 1) * 132, 0)
		pill.Size = UDim2.fromOffset(124, 34)
	end
end

--- Repaints the grid for the active tab. Public because Main calls it when the
--- discovery set moves while the panel is open.
function CodexView.refresh()
	refreshHeader()
	local area = grid
	if area == nil then
		return
	end
	ModalShell.clear(area)
	local painter = PAINTERS[activeTab]
	if painter then
		painter()
	end
end

function CodexView.open()
	local handle = shell
	if handle == nil then
		return
	end
	if handle.isOpen() then
		return
	end
	handle.open()
	refreshHeader()
	paintTabs()
	CodexView.refresh()
end

function CodexView.close()
	if shell then
		shell.close()
	end
end

function CodexView.isOpen(): boolean
	return shell ~= nil and shell.isOpen()
end

--- Switches tab by id. Exposed for the Studio seam: a tab is a button whose
--- handler is a closure, and `TextButton:Activate` does not exist on this build,
--- so verification drives the same state change directly.
function CodexView.setTab(id: string): boolean
	for _, spec in TABS do
		if spec.id == id then
			if activeTab == id then
				return true
			end
			activeTab = id
			Sfx.tab()
			paintTabs()
			CodexView.refresh()
			return true
		end
	end
	return false
end

function CodexView.init(canvas: Frame)
	if shell then
		return
	end

	local handle = ModalShell.build(canvas, {
		name = "CodexOverlay",
		title = "CODEX",
		subtitle = "THE FORGE REMEMBERS EVERY EDGE",
		accent = Theme.Color.quantum,
		width = 1120,
		height = 690,
	}, 44)
	shell = handle

	summary = UiKit.label(handle.body, {
		text = "0 / 0 DISCOVERED",
		size = Theme.Text.Small,
		font = Theme.Font.Black,
		color = Theme.Color.quantum,
		align = Enum.TextXAlignment.Left,
	})
	summary.Name = "CodexSummary"
	summary.Position = UDim2.fromOffset(18, 12)
	summary.Size = UDim2.fromOffset(340, 22)
	summary.ZIndex = 46

	progress = UiKit.label(handle.body, {
		text = "0 COMBINATIONS",
		size = Theme.Text.Tiny,
		font = Theme.Font.Label,
		color = Theme.Color.textDim,
		align = Enum.TextXAlignment.Right,
	})
	progress.Name = "CodexProgress"
	progress.AnchorPoint = Vector2.new(1, 0)
	progress.Position = UDim2.new(1, -18, 0, 14)
	progress.Size = UDim2.fromOffset(340, 20)
	progress.ZIndex = 46

	local bar = UiKit.create("Frame", {
		Name = "CodexTabs",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(18, 44),
		Size = UDim2.new(1, -36, 0, 34),
		ZIndex = 46,
	}) :: Frame
	bar.Parent = handle.body
	tabBar = bar

	local area = UiKit.scroll(handle.body)
	area.Name = "CodexGrid"
	area.Position = UDim2.fromOffset(18, 90)
	area.Size = UDim2.new(1, -36, 1, -104)
	area.ZIndex = 46
	UiKit.grid(area, UDim2.fromOffset(CELL_W, CELL_H), 10)
	grid = area

	unsubscribe = StateStore.onCodex(function()
		if CodexView.isOpen() then
			CodexView.refresh()
		end
	end)
	paintTabs()
	refreshHeader()
end

function CodexView.destroy()
	if unsubscribe then
		unsubscribe()
		unsubscribe = nil
	end
	if shell then
		shell.destroy()
		shell = nil
	end
	tabBar = nil
	grid = nil
	summary = nil
	progress = nil
end

return CodexView
