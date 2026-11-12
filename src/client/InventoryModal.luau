--!strict
-- The blade vault.
--
-- One screen for every copy a player owns: a 4-column grid of live 3D tiles on
-- the left, a permanent inspector on the right, and one batch bar along the
-- bottom. Nothing here owns state; the server is the authority for equip, melt,
-- reroll and favorite, and the whole surface repaints from `StateStore`.
--
-- Three things this file deliberately does NOT do:
--
--   * no "click a card to select" helper line. A card is clickable, the inspector
--     fills, and the picture is the instruction.
--   * no STATS button on a card. The card click is the stats button.
--   * no box-only hit target. MELT MULTIPLE is a mode: the whole card tray
--     toggles a copy while it is on, and the key turns into CANCEL so the way
--     out is the same size as the way in. Outside the mode a card inspects,
--     which is what a player does ten times more often than melting.
--
-- Thumbnails are live `ViewportFrame` renders, but only for the rows on screen.
-- A sixty-card grid would otherwise build sixty models and sixty cameras to show
-- two and a half rows; the scroll window decides who gets a model.

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BladeRegistry = require(Shared:WaitForChild("BladeRegistry"))
local ForgeConfig = require(Shared:WaitForChild("ForgeConfig"))
local ModifierConfig = require(Shared:WaitForChild("ModifierConfig"))
local NumberUtil = require(Shared:WaitForChild("NumberUtil"))
local RuneConfig = require(Shared:WaitForChild("RuneConfig"))

local Theme = require(script.Parent.Theme)
local UiKit = require(script.Parent.UiKit)
local StageBackdrop = require(script.Parent.StageBackdrop)
local StateStore = require(script.Parent.StateStore)
local InventoryModel = require(script.Parent.InventoryModel)
local BladePreview = require(script.Parent.BladePreview)
local Sfx = require(script.Parent.Sfx)
local Notifications = require(script.Parent.Notifications)
local Modals = require(script.Parent.Modals)

local InventoryModal = {}

--- Set by Main. The trade desk is its own overlay, so the vault hands off
--- rather than owning it.
InventoryModal.tradeHandler = nil :: (() -> ())?

-- ---------------------------------------------------------------------------
-- Geometry (design px on the 1440x720 canvas)
-- ---------------------------------------------------------------------------

local CARD_W = 221
local CARD_H = 184
local CARD_GAP = 10
local INSPECTOR_W = 380
local BANNER_H = 54
local TOOLBAR_H = 46
--- 40, not 46: the batch strip is a toolbar, not a second header. 15px black
--- type still has 12px of air above and below at this height.
local BATCH_H = 40
--- Air between batch keys. The 3px outlines need the gap or four plates read as
--- one long bar; 10 also matches the card gutter, so the strip lines up with the
--- grid above it.
local BATCH_GAP = 10
local PAD = 18

local SORT_ORDER = { "power", "rarity", "newest" }
local SORT_LABEL = {
	power = "MULTIPLIER  ↓",
	rarity = "RARITY  ↓",
	newest = "NEWEST",
}

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local overlay: Frame? = nil
local panel: Frame? = nil
local grid: ScrollingFrame? = nil
local inspectorStage: ViewportFrame? = nil
local inspectorSurface: TextButton? = nil
local inspectorBackdrop: StageBackdrop.Handle? = nil
local inspectorOrbit: { cameraYaw: number, cameraPitch: number, dragTravel: number }? = nil
local inspectorName: TextLabel? = nil
local inspectorSub: TextLabel? = nil
local statWell: Frame? = nil
local dock: Frame? = nil
local scrapValue: TextLabel? = nil
local ownedValue: TextLabel? = nil
local sortButton: TextButton? = nil
local batchMelt: TextButton? = nil
local batchDupes: TextButton? = nil
local batchClear: TextButton? = nil
local batchConfirm: TextButton? = nil
local selectionLabel: TextLabel? = nil

local cards: { Frame } = {}
local groups: { InventoryModel.Group } = {}
local view: { InventoryModel.Group } = {}
local selected: { [string]: boolean } = {}
local favoriteSet: { [string]: boolean } = {}
local inspectKey: string? = nil
local filterKind = "all"
local sortKind = "power"
--- True while MELT MULTIPLE is armed. The mode owns the card click and the
--- checkboxes; the batch key owns the way out.
local meltMode = false
local signature = ""
local open = false
local unsubSync: (() -> ())? = nil
local unsubInventory: (() -> ())? = nil
local inspectorCleanup: (() -> ())? = nil
local inspectorMountedKey: string? = nil
local thumbsDirty = true

-- Forward declaration: the filter and sort setters live above the grid builder
-- but have to re-run it. One indirection beats moving 200 lines of card code
-- above the public API for the sake of the parser.
local rebuild: () -> () = function() end
local refreshCounts: () -> () = function() end

--- Fired whenever the vault opens or closes. The tutorial uses it to stop
--- pointing at a card that is about to be covered by the overlay.
InventoryModal.onOpenChange = nil :: ((open: boolean) -> ())?

--- Fired after EQUIP BEST is pressed. The vault is otherwise closed to the
--- client, and the coach notes need to know the press landed even when the
--- copy it picked was already the strongest one.
InventoryModal.onEquipBest = nil :: (() -> ())?

-- ---------------------------------------------------------------------------
-- Payload helpers
-- ---------------------------------------------------------------------------

local function current(): any
	return StateStore.current
end

local function totalCopies(): number
	local state = current()
	return if state then state.invCount else #StateStore.inventory
end

local function inventoryMax(): number
	local state = current()
	return if state then (state.invMax or 0) else 0
end

local function equippedUid(): string
	local state = current()
	return if state then state.equippedUid else ""
end

local function groupFavorite(group: InventoryModel.Group): boolean
	for _, uid in group.uids do
		if favoriteSet[uid] then
			return true
		end
	end
	return false
end

local function groupEquipped(group: InventoryModel.Group): boolean
	local uid = equippedUid()
	if uid == "" then
		return false
	end
	for _, candidate in group.uids do
		if candidate == uid then
			return true
		end
	end
	return false
end

local function masteryStrikes(bladeId: string): number
	local state = current()
	local all = if state then state.masteryAll else nil
	if type(all) == "table" then
		return tonumber(all[bladeId]) or 0
	end
	return 0
end

-- ---------------------------------------------------------------------------
-- Selection and batch state
-- ---------------------------------------------------------------------------

local function selectedCount(): number
	local count = 0
	for _ in selected do
		count += 1
	end
	return count
end

--- How many copies of one group can actually melt right now. The server refuses
--- the equipped copy, favorites, and the last copy in the vault, so the tick box
--- has to know the same three rules: a tick that cannot melt is a lie on the bar.
local function groupMeltable(group: InventoryModel.Group): number
	local total = totalCopies()
	if total <= 1 then
		return 0
	end
	local uid = equippedUid()
	local count = 0
	for _, copyUid in group.uids do
		if copyUid ~= uid and not favoriteSet[copyUid] then
			count += 1
		end
	end
	return math.min(count, total - 1)
end

local function picks(): ({ string }, number)
	local uid = equippedUid()
	return InventoryModel.meltable(groups, selected, uid, totalCopies(), favoriteSet),
		InventoryModel.meltValue(groups, selected, uid, totalCopies(), favoriteSet)
end

local function refreshBatch()
	local uids, worth = picks()
	local armed = meltMode

	-- The batch key is a switch, not a trigger. Off it wears the house red and
	-- opens the mode; on it wears the old slate and is the way out. The plate
	-- that actually melts appears on the right the moment a copy is ticked, so
	-- the destructive action never shares a key with the mode switch.
	local melt = batchMelt
	if melt then
		local text = if armed then "CANCEL" else "MELT MULTIPLE"
		local face = melt:FindFirstChild("Face")
		if face and face:IsA("TextLabel") then
			face.Text = text
		else
			melt.Text = text
		end
		melt.BackgroundColor3 = if armed then Theme.Color.slate else Theme.Color.redDeep
		melt.TextColor3 = if armed then Theme.Color.textDim else Theme.Color.text
		local stroke = melt:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if armed then Theme.Color.strokeBright else Theme.Color.red
		end
	end

	local hasDupes = false
	for _, group in groups do
		if group.count > 1 and groupMeltable(group) > 0 then
			hasDupes = true
			break
		end
	end
	local dupes = batchDupes
	if dupes then
		dupes.TextColor3 = if hasDupes then Theme.Color.textDim else Theme.Color.locked
	end
	local clear = batchClear
	if clear then
		clear.TextColor3 = if selectedCount() > 0 then Theme.Color.textDim else Theme.Color.locked
	end

	local confirm = batchConfirm
	if confirm then
		confirm.Visible = armed and #uids > 0
		if #uids > 0 then
			confirm.Text = string.format("MELT %d  +%d", #uids, worth)
		end
	end
	local label = selectionLabel
	if label then
		label.Visible = armed and #uids == 0
		label.Text = string.format("%d TO MELT  ·  +%d SCRAP", #uids, worth)
		label.TextColor3 = if #uids > 0 then Theme.Color.gold else Theme.Color.textFaint
	end
end

local function paintCard(card: Frame)
	local key = card:GetAttribute("groupKey")
	if type(key) ~= "string" then
		return
	end
	local group: InventoryModel.Group? = nil
	for _, candidate in groups do
		if candidate.key == key then
			group = candidate
			break
		end
	end
	if group == nil then
		return
	end

	local inspected = key == inspectKey
	local equipped = groupEquipped(group)
	local ticked = meltMode and selected[key] == true
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then
		if ticked or inspected then
			-- A ticked card is a queued card, and the inspected card is the one
			-- the right-hand pane is showing: both get the gold edge. The tick
			-- box is what tells them apart.
			stroke.Color = Theme.Color.gold
			stroke.Thickness = Theme.Stroke.bold
		elseif equipped then
			stroke.Color = Theme.Color.emerald
			stroke.Thickness = Theme.Stroke.thick
		else
			stroke.Color = Theme.Color.outline
			stroke.Thickness = Theme.Stroke.thick
		end
	end
	local check = card:FindFirstChild("Check")
	if check and check:IsA("Frame") then
		local live = groupMeltable(group)
		local queued = selected[key] == true and live > 0
		-- The box is part of the melt mode, not decoration: outside the mode the
		-- card has one job (inspect) and a tick box on it would be a second.
		check.Visible = live > 0 and meltMode
		check.BackgroundColor3 = if queued then Theme.Color.gold else Theme.Color.void
		check.BackgroundTransparency = if queued then 0 else 0.35
		local checkStroke = check:FindFirstChildOfClass("UIStroke")
		if checkStroke then
			checkStroke.Color = if queued then Theme.Color.outline else Theme.Color.strokeBright
			checkStroke.Thickness = if queued then Theme.Stroke.thick else 2
		end
		local tick = check:FindFirstChild("Tick")
		if tick and tick:IsA("TextLabel") then
			tick.Visible = queued
		end
	end
	local box = card:FindFirstChild("VaultCheck")
	if box and box:IsA("GuiObject") then
		box.Visible = groupMeltable(group) > 0 and meltMode
	end
	local countFace = card:FindFirstChild("CountFace", true)
	if countFace and countFace:IsA("TextLabel") then
		local live = groupMeltable(group)
		countFace.Text = if live < group.count
			then string.format("%d/%d", live, group.count)
			else string.format("x%d", group.count)
		countFace.TextColor3 = if live < group.count then Theme.Color.textFaint else Theme.Color.text
	end
	local star = card:FindFirstChild("FavStar")
	if star and star:IsA("TextButton") then
		local on = favoriteSet[group.repUid] == true
		star.TextColor3 = if on then Theme.Color.gold else Theme.Color.textFaint
		star.Text = if on then "★" else "☆"
	end
end

local function repaintCards()
	for _, card in cards do
		paintCard(card)
	end
	refreshBatch()
end

local function toggleSelect(key: string)
	if selected[key] then
		selected[key] = nil
	else
		local live = 0
		for _, group in groups do
			if group.key == key then
				live = groupMeltable(group)
				break
			end
		end
		if live > 0 then
			selected[key] = true
		end
	end
	Sfx.tab()
	repaintCards()
end

--- Arms or disarms the batch mode.
---
--- Disarming clears the ticks. A tick only exists to be melted, and one that
--- survived CANCEL would melt copies the player believed they had backed out
--- of; the mode and the selection are the same decision.
local function setMeltMode(on: boolean)
	if meltMode == on then
		return
	end
	meltMode = on
	if not on then
		table.clear(selected)
	end
	repaintCards()
end

-- ---------------------------------------------------------------------------
-- Inspector
-- ---------------------------------------------------------------------------

local function statRow(parent: Frame, order: number, label: string, value: string, color: Color3?, labelScale: number?)
	local split = labelScale or 0.58
	local row = UiKit.create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = order,
	}) :: Frame
	row.Parent = parent

	-- Both halves start at y 0 and are the full height of the row, so the label
	-- and the value share one baseline by construction. The old drawer gave each
	-- a different offset and the columns drifted a line apart at some sizes.
	local name = UiKit.label(row, {
		text = label,
		size = Theme.Text.Tiny,
		font = Theme.Font.Label,
		color = Theme.Color.textSecondary,
		alignY = Enum.TextYAlignment.Center,
	})
	name.Position = UDim2.fromOffset(0, 0)
	name.Size = UDim2.fromScale(split, 1)

	local amount = UiKit.label(row, {
		text = value,
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = color or Theme.Color.text,
		align = Enum.TextXAlignment.Right,
		alignY = Enum.TextYAlignment.Center,
	})
	amount.Position = UDim2.fromScale(split, 0)
	amount.Size = UDim2.fromScale(1 - split, 1)
	amount.Name = "Value"
	return row
end

--- One of the two stat columns in the inspector drawer.
---
--- The drawer holds ten facts and used to be a single column. At 132px only six
--- of them fit, so COOLING, MASTERY and SOCKETS sat permanently below the clip
--- line: the rune lock was printed by the code and never visible. Splitting by
--- meaning keeps every row on screen without touching the type rung or the hero
--- stage: what the copy IS on the left, what it DOES on the right.
local function statColumn(parent: Frame, x: number, width: number): Frame
	local column = UiKit.create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(x, 0),
		Size = UDim2.new(0, width, 1, 0),
	}) :: Frame
	UiKit.vlist(column, { gap = 0 })
	column.Parent = parent
	return column
end

local function clearInspector()
	if inspectorCleanup then
		inspectorCleanup()
		inspectorCleanup = nil
	end
	inspectorMountedKey = nil
	inspectorOrbit = nil
end

local function paintInspector()
	local name = inspectorName
	local sub = inspectorSub
	local well = statWell
	local actions = dock
	if name == nil or sub == nil or well == nil or actions == nil then
		return
	end

	local group: InventoryModel.Group? = nil
	for _, candidate in groups do
		if candidate.key == inspectKey then
			group = candidate
			break
		end
	end

	for _, child in well:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for _, child in actions:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	if group == nil then
		name.Text = "NO BLADE SELECTED"
		name.TextColor3 = Theme.Color.locked
		sub.Text = "Pick a card to inspect it."
		clearInspector()
		if inspectorBackdrop then
			inspectorBackdrop.setColors(Theme.Color.gold, Theme.Color.gold, Theme.Color.cyan)
		end
		local stage = inspectorStage
		if stage then
			stage:ClearAllChildren()
			stage:SetAttribute("ThumbKey", nil)
		end
		local equip = UiKit.button(actions, {
			text = "EQUIP",
			fill = Theme.Color.slate,
			stroke = Theme.Color.outline,
			height = 36,
			radius = Theme.Radius.sm,
			size = Theme.Text.Small,
			font = Theme.Font.Black,
			textColor = Theme.Color.locked,
			handler = function() end,
		})
		equip.Name = "VaultEquip"
		equip.Position = UDim2.fromOffset(0, 0)
		equip.Size = UDim2.new(1, 0, 0, 36)
		return
	end

	local holdsEquipped = groupEquipped(group)
	local strikes = masteryStrikes(group.id)
	local rank = RuneConfig.masteryRank(strikes)
	local sockets = RuneConfig.socketsFor(rank)

	name.Text = group.displayName
	name.TextColor3 = Theme.rarityColor(group.blade.tier)
	sub.Text = string.format("%s  ·  %s  ·  %dx", group.condition, group.variantInfo.name, group.count)
	sub.TextColor3 = group.elementColor

	-- Modifier block. The two columns are 176 and 136 wide with a 24px gutter:
	-- the left one has to hold names like "of the Colossus" (98px at the 13px
	-- rung) and the right one only ever prints numbers. The split is by meaning,
	-- so a copy without a prefix leaves a hole in the left column rather than
	-- shuffling the right.
	local identity = statColumn(well, 0, 176)
	local performance = statColumn(well, 200, 136)
	local idOrder = 0
	local perfOrder = 0
	local function addId(label: string, value: string, color: Color3?)
		idOrder += 1
		statRow(identity, idOrder, label, value, color, 0.42)
	end
	local function addPerf(label: string, value: string, color: Color3?)
		perfOrder += 1
		statRow(performance, perfOrder, label, value, color, 0.46)
	end

	local modBonus = ModifierConfig.bonus(group.element, group.prefix, group.suffix)

	addId("MULTIPLIER", NumberUtil.abbreviateMultiplier(group.power), Theme.Color.gold)
	addId("GRADE", if group.grade ~= "" then ModifierConfig.grade(group.grade).name else "None", Theme.Color.text)
	addId("ELEMENT", if group.element ~= "" then ModifierConfig.element(group.element).name else "None", group.elementColor)
	if group.prefix ~= "" then
		local prefix = ModifierConfig.prefix(group.prefix)
		addId("PREFIX", if prefix then prefix.name else "None", Theme.Color.cyan)
	end
	if group.suffix ~= "" then
		local suffix = ModifierConfig.suffix(group.suffix)
		addId("SUFFIX", if suffix then suffix.name else "None", Theme.Color.quantum)
	end
	addPerf("VARIANT", string.format("x%.2f", group.variantInfo.mult), group.variantInfo.color)
	addPerf("CRIT", string.format("+%.0f%%", (group.variantInfo.critChance + modBonus.critChance) * 100), Theme.Color.cyan)
	addPerf("COOL", string.format("x%.2f", group.variantInfo.coolMult * modBonus.coolMult), Theme.Color.emerald)
	addPerf("MASTERY", string.format("R%d  %s", rank, NumberUtil.abbreviate(strikes)), Theme.Color.white)
	addPerf("SOCKETS", string.format("%d / %d", sockets, RuneConfig.MaxSockets), Theme.Color.white)

	-- Turntable. One live mount at a time, and only when the inspected copy
	-- actually changed: remounting on every 10Hz repaint would restart the spin
	-- several times a second.
	local stage = inspectorStage
	if stage then
		if inspectorMountedKey ~= group.key then
			clearInspector()
			inspectorCleanup = BladePreview.mount(stage, group.blade, group.variantInfo.color, {
				frameFill = 0.72,
				aimBias = 0.05,
				surface = inspectorSurface,
				onOrbit = function(handle)
					inspectorOrbit = handle
				end,
			})
			inspectorMountedKey = group.key
		end
	end
	if inspectorBackdrop then
		inspectorBackdrop.setColors(Theme.rarityColor(group.blade.tier), Theme.rarityColor(group.blade.tier), group.variantInfo.color)
	end

	-- Dock: a two-by-two grid in a 356px well. EQUIP keeps the top-left because
	-- it is the verb a player presses most, FAVORITE sits beside it, and the two
	-- Scrap actions share the bottom row.
	--
	-- REROLL is new here. `ProgressionService.rerollVariant` has existed since
	-- the Salvage rack shipped and the handbook has been quoting its price in
	-- public, but no button ever called it: the sink for duplicate blades was a
	-- server function nobody could reach. It sits on the copy the inspector is
	-- showing, which is the one the player is actually looking at.
	local equip = UiKit.button(actions, {
		text = if holdsEquipped then "EQUIPPED" else "EQUIP",
		fill = if holdsEquipped then Theme.Color.slate else Theme.Color.cyanDeep,
		stroke = if holdsEquipped then Theme.Color.outline else Theme.Color.cyan,
		height = 34,
		radius = Theme.Radius.sm,
		size = Theme.Text.Small,
		font = Theme.Font.Black,
		textColor = if holdsEquipped then Theme.Color.locked else Theme.Color.text,
		handler = function()
			if holdsEquipped then
				return
			end
			Sfx.equip()
			StateStore.send("equip", { uid = group.repUid })
		end,
	})
	equip.Name = "VaultEquip"
	equip.Position = UDim2.fromOffset(0, 0)
	equip.Size = UDim2.fromOffset(174, 34)

	local starred = favoriteSet[group.repUid] == true
	local favorite = UiKit.button(actions, {
		text = if starred then "FAVORITED" else "FAVORITE",
		fill = if starred then Theme.Color.goldDeep else Theme.Color.panelSunken,
		stroke = if starred then Theme.Color.gold else Theme.Color.stroke,
		height = 34,
		radius = Theme.Radius.sm,
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		textColor = Theme.Color.text,
		handler = function()
			InventoryModal.toggleFavorite(group.repUid)
		end,
	})
	favorite.Name = "VaultFavorite"
	favorite.Position = UDim2.fromOffset(182, 0)
	favorite.Size = UDim2.fromOffset(174, 34)

	-- Affordability is read at paint time so the key greys out the moment the
	-- melt lands, and again inside the handler so a stale paint cannot spend.
	local rerollPrice = ForgeConfig.rerollCost(group.blade.tier)
	local scrapNow = if StateStore.current then StateStore.current.scrap else 0
	local canReroll = scrapNow >= rerollPrice
	local reroll = UiKit.button(actions, {
		text = string.format("REROLL  %d SCRAP", rerollPrice),
		fill = if canReroll then Theme.Color.quantumDeep else Theme.Color.slate,
		stroke = if canReroll then Theme.Color.quantum else Theme.Color.outline,
		height = 34,
		radius = Theme.Radius.sm,
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		textColor = if canReroll then Theme.Color.text else Theme.Color.locked,
		handler = function()
			InventoryModal.rerollDetail()
		end,
	})
	reroll.Name = "VaultReroll"
	reroll.Position = UDim2.fromOffset(0, 38)
	reroll.Size = UDim2.fromOffset(174, 34)

	local value = ForgeConfig.salvageValue(group.id, group.variant, group.element, group.grade, group.prefix, group.suffix)
	local melt = UiKit.button(actions, {
		text = string.format("MELT  +%d SCRAP", value),
		fill = Theme.Color.redDeep,
		stroke = Theme.Color.red,
		height = 34,
		radius = Theme.Radius.sm,
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		textColor = Theme.Color.text,
		handler = function()
			InventoryModal.meltDetail()
		end,
	})
	melt.Name = "VaultMelt"
	melt.Position = UDim2.fromOffset(182, 38)
	melt.Size = UDim2.fromOffset(174, 34)
end

local function inspect(key: string?)
	inspectKey = key
	repaintCards()
	paintInspector()
end

--- The group the inspector is showing, or nil when it is empty or the group
--- vanished (melted from the batch bar, for instance).
local function inspectedGroup(): InventoryModel.Group?
	local key = inspectKey
	if key == nil then
		return nil
	end
	for _, candidate in groups do
		if candidate.key == key then
			return candidate
		end
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Public actions (buttons, confirm dialogs and the Studio seam all call these)
-- ---------------------------------------------------------------------------

--- Toggles the protection flag on one uid. Optimistic: the star flips now and
--- the next payload confirms it, because a favorite that waits 100ms for a
--- round-trip feels broken.
function InventoryModal.toggleFavorite(uid: string)
	local on = favoriteSet[uid] ~= true
	if on then
		favoriteSet[uid] = true
	else
		favoriteSet[uid] = nil
	end
	Sfx.tab()
	StateStore.send("favorite", { uid = uid })
	repaintCards()
	paintInspector()
end

function InventoryModal.favoriteAt(index: number): boolean
	local group = view[index]
	if group == nil then
		return false
	end
	InventoryModal.toggleFavorite(group.repUid)
	return true
end

function InventoryModal.setFilter(kind: string)
	if kind == filterKind then
		return
	end
	filterKind = kind
	Sfx.tab()
	signature = ""
	rebuild()
end

function InventoryModal.setSort(kind: string)
	if kind == sortKind then
		return
	end
	sortKind = kind
	Sfx.tab()
	signature = ""
	rebuild()
end

function InventoryModal.cycleSort()
	local index = 1
	for position, id in SORT_ORDER do
		if id == sortKind then
			index = position
			break
		end
	end
	InventoryModal.setSort(SORT_ORDER[index % #SORT_ORDER + 1])
end

--- The copy the inspector's MELT acts on: the first uid that is not equipped and
--- not favorited. A group can hold the equipped copy and still own spares, so
--- keying the action off the representative refused every duplicate of the blade
--- in hand, which in practice is the second starter blade.
function InventoryModal.detailMeltTarget(): (string?, InventoryModel.Group?)
	local group = inspectedGroup()
	if group == nil then
		return nil, nil
	end
	local uid = equippedUid()
	for _, candidate in group.uids do
		if candidate ~= uid and not favoriteSet[candidate] then
			return candidate, group
		end
	end
	return nil, group
end

--- Inspector MELT: confirm, then melt one spare copy from the open group.
function InventoryModal.meltDetail(): boolean
	local target, group = InventoryModal.detailMeltTarget()
	if group == nil then
		return false
	end
	if target == nil then
		Sfx.error()
		Notifications.push("Equip or unfavorite another copy first", "bad")
		return false
	end
	local value = ForgeConfig.salvageValue(group.id, group.variant, group.element, group.grade, group.prefix, group.suffix)
	Modals.confirm(
		"MELT A BLADE",
		string.format(
			"Melt one of %d %s of %s (%s, %s) into %d Scrap?",
			group.count,
			if group.count == 1 then "copy" else "copies",
			group.displayName,
			group.condition,
			group.variantInfo.name,
			value
		),
		"MELT",
		Theme.Color.red,
		function()
			InventoryModal.commitDetailMelt(target)
		end
	)
	return true
end

--- Sends a single melt. Kept separate from `commitMelt` because the server logs
--- one-copy melts under a different funnel event than batches.
function InventoryModal.commitDetailMelt(uid: string)
	Sfx.melt()
	StateStore.send("salvage", { uid = uid })
	table.clear(selected)
	repaintCards()
end

--- Inspector REROLL: confirm, then buy a fresh variant for the copy on the
--- turntable. The outcome is random on purpose, and the dialog says so in the
--- same breath as the price. A button that spends Scrap must never be dressed as
--- an upgrade when it is a gamble.
---
--- It targets `repUid`, which is the copy the inspector is showing. Melting is
--- the opposite: that one has to skip the equipped and favorited copies, because
--- melting the blade in hand is a mistake, while rerolling your main is the point
--- of the sink.
function InventoryModal.rerollDetail(): boolean
	local group = inspectedGroup()
	if group == nil then
		return false
	end
	local price = ForgeConfig.rerollCost(group.blade.tier)
	local scrap = if StateStore.current then StateStore.current.scrap else 0
	if scrap < price then
		Sfx.error()
		Notifications.push(string.format("Needs %d Scrap to reroll", price), "warn")
		return false
	end
	Modals.confirm(
		"REROLL THE VARIANT",
		string.format(
			"Spend %d Scrap on a random variant for this %s (%s)? The roll can come back worse than the one it replaces.",
			price,
			group.displayName,
			group.variantInfo.name
		),
		"REROLL",
		Theme.Color.quantumDeep,
		function()
			InventoryModal.commitDetailReroll(group.repUid)
		end
	)
	return true
end

--- Sends the reroll. Sound on the press: the server answers with a toast naming
--- the new variant, and the payload repaints the turntable and the rarity tint.
---
--- `uid` defaults to the copy on the turntable so the Studio seam can drive the
--- verb without knowing which card is open.
function InventoryModal.commitDetailReroll(uid: string?)
	local target = uid
	if target == nil then
		local group = inspectedGroup()
		if group == nil then
			return
		end
		target = group.repUid
	end
	Sfx.reroll()
	StateStore.send("reroll", { uid = target })
end

--- Selects every group that owns more than one meltable copy. Groups holding the
--- equipped copy are included on purpose: `meltable` drops that uid, so ticking
--- such a group melts its spares and never the blade in hand. Favorites are
--- dropped the same way, so SELECT DUPES is safe to press with protection on.
--- A group whose only copies are protected is not ticked: the bar counts copies,
--- and a tick that contributes nothing is how "3 selected, 2 to melt" happened.
---
--- Arms the mode first: this key is reachable from the idle strip, and arriving
--- in a mode the player did not ask for is exactly what the tick boxes are for.
function InventoryModal.selectDupes()
	meltMode = true
	Sfx.tab()
	for _, group in groups do
		if group.count > 1 and groupMeltable(group) > 0 then
			selected[group.key] = true
		end
	end
	repaintCards()
end

function InventoryModal.clearSelection()
	Sfx.tab()
	table.clear(selected)
	repaintCards()
end

--- Public so the Studio seam and the batch key drive one switch.
function InventoryModal.setMeltMode(on: boolean)
	setMeltMode(on)
end

function InventoryModal.isMeltMode(): boolean
	return meltMode
end

--- Studio seam: the inspect orbit. `ViewportOrbitController` is normally driven
--- by the drag surface; the seam nudges the angles to prove the camera answers.
function InventoryModal.orbitHandle(): { cameraYaw: number, cameraPitch: number, dragTravel: number }?
	return inspectorOrbit
end

--- Dev-seam readout: the strip's real geometry and faces, so a layout pass can
--- be checked without a pointer.
function InventoryModal.batchState(): { [string]: any }
	local melt = batchMelt
	local confirm = batchConfirm
	local label = selectionLabel
	return {
		mode = meltMode,
		meltText = if melt then melt.Text else "",
		meltHeight = if melt then melt.AbsoluteSize.Y else 0,
		meltFill = if melt then melt.BackgroundColor3 else Theme.Color.void,
		confirmVisible = if confirm then confirm.Visible else false,
		confirmText = if confirm then confirm.Text else "",
		labelVisible = if label then label.Visible else false,
		labelText = if label then label.Text else "",
		selected = selectedCount(),
	}
end

--- What the current selection would melt, and what it pays. The confirm copy and
--- the request body both read this, so the number in the dialog is the number
--- the server is asked for.
function InventoryModal.selectionSummary(): ({ string }, number)
	return picks()
end

function InventoryModal.equipBest()
	Sfx.equip()
	StateStore.send("equipBest")
	if InventoryModal.onEquipBest then
		InventoryModal.onEquipBest()
	end
end

--- Sends the melt. Public because the accept button on the confirm dialog and
--- the Studio dev seam call exactly this.
function InventoryModal.commitMelt(uids: { string })
	Sfx.melt()
	StateStore.send("salvageMany", { uids = uids })
	table.clear(selected)
	repaintCards()
end

--- Asks before melting. Returns false when the selection melts nothing.
function InventoryModal.meltSelected(): boolean
	local list, worth = picks()
	if #list == 0 then
		Sfx.error()
		return false
	end
	Modals.confirm(
		"MELT A SELECTION",
		string.format(
			"Melt %d %s into %d Scrap?",
			#list,
			if #list == 1 then "copy" else "copies",
			worth
		),
		"MELT ALL",
		Theme.Color.red,
		function()
			InventoryModal.commitMelt(list)
		end
	)
	return true
end

--- Opens the inspector for the highest-ranked visible card. Used by the Studio
--- seam and by anything that wants "show me the best thing I own".
function InventoryModal.openFirstDetail()
	local group = view[1]
	if group then
		inspect(group.key)
	end
end

--- Inspects the Nth card in grid order. Same entry point the cards use, addressed
--- by position instead of by key.
function InventoryModal.openDetailAt(index: number): boolean
	local group = view[index]
	if group == nil then
		return false
	end
	inspect(group.key)
	return true
end

--- Studio seam: toggles the copy at a visible-list index, exactly what the card
--- hit layer does while the melt mode is armed.
function InventoryModal.toggleAt(index: number): boolean
	local group = view[index]
	if group == nil then
		return false
	end
	toggleSelect(group.key)
	return selected[group.key] == true
end

function InventoryModal.closeDetail()
	inspectKey = nil
	clearInspector()
	repaintCards()
	paintInspector()
end

--- Diagnostics for the Studio seam: which filter, which sort, which card. Not
--- read by any player-facing code.
function InventoryModal.currentFilter(): string
	return filterKind
end

function InventoryModal.currentSort(): string
	return sortKind
end

function InventoryModal.inspectedKey(): string?
	return inspectKey
end

-- ---------------------------------------------------------------------------
-- Grid
-- ---------------------------------------------------------------------------

local function accept(group: InventoryModel.Group): boolean
	if filterKind == "equipped" then
		return groupEquipped(group)
	elseif filterKind == "favorites" then
		return groupFavorite(group)
	end
	return true
end

local function sortView(list: { InventoryModel.Group })
	table.sort(list, function(a: InventoryModel.Group, b: InventoryModel.Group): boolean
		if sortKind == "rarity" then
			if a.blade.tier ~= b.blade.tier then
				return a.blade.tier > b.blade.tier
			end
		elseif sortKind == "newest" then
			if a.forgedAt ~= b.forgedAt then
				return a.forgedAt > b.forgedAt
			end
		end
		if a.power ~= b.power then
			return a.power > b.power
		end
		if a.blade.tier ~= b.blade.tier then
			return a.blade.tier > b.blade.tier
		end
		return a.blade.name < b.blade.name
	end)
end

local function buildCard(group: InventoryModel.Group, index: number)
	local holdsEquipped = groupEquipped(group)
	local tierColor = Theme.rarityColor(group.blade.tier)

	local card = UiKit.panel(grid :: ScrollingFrame, {
		tier = "raised",
		radius = Theme.Radius.card,
		stroke = Theme.Color.outline,
		bevel = false,
		lip = false,
	})
	card.Name = string.format("VaultCard_%s_%s", group.id, group.variant)
	card.Size = UDim2.fromOffset(CARD_W, CARD_H)
	card.LayoutOrder = index
	card:SetAttribute("groupKey", group.key)
	card:SetAttribute("thumbBlade", group.id)
	card:SetAttribute("thumbVariant", group.variant)
	card:SetAttribute("thumbElement", group.element)
	table.insert(cards, card)

	-- Accent bar. Doubles as the EQUIPPED tag: a green ribbon is both the
	-- strongest possible signal and the only place on a 221px card where the word
	-- fits without stealing a row from the name or the stats.
	local bar = UiKit.create("Frame", {
		Name = "AccentBar",
		BackgroundColor3 = if holdsEquipped then Theme.Color.emerald else tierColor,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 16),
		ZIndex = 2,
	}) :: Frame
	UiKit.corner(bar, Theme.Radius.card)
	bar.Parent = card
	if holdsEquipped then
		local tag = UiKit.label(bar, {
			text = "EQUIPPED",
			size = Theme.Text.Tiny,
			font = Theme.Font.Black,
			color = Theme.Color.ink,
			align = Enum.TextXAlignment.Center,
		})
		tag.Size = UDim2.fromScale(1, 1)
		tag.ZIndex = 3
	end

	-- Art wash. The blade sits on a gradient built from the tier colour and the
	-- variant colour, not on a stack of flat circles: circles step, bands blend.
	-- It stops 136px down and settles into the card plate, so the name and the
	-- stat row keep a clean surface.
	StageBackdrop.paint(card, {
		warm = tierColor,
		cool = tierColor,
		accent = group.variantInfo.color,
		radius = Theme.Radius.card,
		height = 136,
		tile = true,
		depth = 0.5,
		settle = Theme.Color.panelRaised,
		settleHeight = 46,
	})

	local stage = UiKit.create("ViewportFrame", {
		Name = "VaultThumb",
		-- Transparent: the wash behind it is the backdrop. The old opaque frame
		-- painted a black 96px box over whatever the card had underneath.
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(62, 20),
		Size = UDim2.fromOffset(96, 96),
		ZIndex = 2,
	}) :: ViewportFrame
	stage.Parent = card

	local name = UiKit.label(card, {
		-- Prefix and suffix are part of the object's name, so they belong on the
		-- card. Truncation is set below: "Molten Rusted Cleaver of Ruin" cannot
		-- fit 205px at 15px, and a wrapped name breaks the row grid.
		text = group.displayName,
		size = Theme.Text.Small,
		font = Theme.Font.Heading,
		color = Theme.Color.text,
		align = Enum.TextXAlignment.Center,
		stroke = true,
	})
	name.Position = UDim2.fromOffset(8, 112)
	name.Size = UDim2.new(1, -16, 0, 20)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.ZIndex = 3

	-- Condition strip. Grade is the rarity of the copy itself and element is its
	-- flavour; the element supplies the colour, so the axis a player is hunting
	-- for is readable at a glance without opening the drawer.
	local condition = UiKit.label(card, {
		text = group.condition,
		size = Theme.Text.Tiny,
		font = Theme.Font.Label,
		color = group.elementColor,
		align = Enum.TextXAlignment.Center,
		stroke = true,
	})
	condition.Name = "Condition"
	condition.Position = UDim2.fromOffset(8, 132)
	condition.Size = UDim2.new(1, -16, 0, 15)
	condition.TextTruncate = Enum.TextTruncate.AtEnd
	condition.ZIndex = 3

	local chip = UiKit.badge(card, {
		text = group.variantInfo.name,
		color = group.variantInfo.color,
		width = 90,
		height = 20,
		size = Theme.Text.Tiny,
		textColor = Theme.Color.ink,
	})
	chip.Position = UDim2.fromOffset(8, 150)
	chip.ZIndex = 3

	local power = UiKit.label(card, {
		text = NumberUtil.abbreviateMultiplier(group.power),
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.gold,
		align = Enum.TextXAlignment.Center,
		stroke = true,
	})
	power.Position = UDim2.fromOffset(102, 150)
	power.Size = UDim2.fromOffset(72, 20)
	power.ZIndex = 3

	if group.count > 1 then
		local count = UiKit.create("Frame", {
			BackgroundColor3 = Theme.Color.panelSunken,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 54),
			Size = UDim2.fromOffset(40, 22),
			ZIndex = 4,
		}) :: Frame
		UiKit.corner(count, 6)
		UiKit.stroke(count, Theme.Color.outline, 2, 0)
		count.Parent = card
		local label = UiKit.label(count, {
			text = string.format("x%d", group.count),
			size = Theme.Text.Tiny,
			font = Theme.Font.Black,
			color = Theme.Color.text,
			align = Enum.TextXAlignment.Center,
		})
		label.Name = "CountFace"
		label.Size = UDim2.fromScale(1, 1)
		label.ZIndex = 5
	end

	local star = UiKit.create("TextButton", {
		Name = "FavStar",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = if favoriteSet[group.repUid] then "★" else "☆",
		TextColor3 = if favoriteSet[group.repUid] then Theme.Color.gold else Theme.Color.textFaint,
		TextSize = 22,
		Font = Theme.Font.Black,
		TextStrokeTransparency = 0,
		TextStrokeColor3 = Theme.Color.outline,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 20),
		Size = UDim2.fromOffset(30, 30),
		ZIndex = 6,
	}) :: TextButton
	star.Parent = card
	UiKit.track(star, star.Activated:Connect(function()
		InventoryModal.toggleFavorite(group.repUid)
	end))
	UiKit.track(star, star.MouseEnter:Connect(function()
		Sfx.hover()
	end))

	-- Melt checkbox. Only in the melt mode: outside it the card has one job and
	-- a tick box would be a second. A group with nothing meltable has no box at
	-- all, so a tick can only ever mean a copy the server will actually take.
	local live = groupMeltable(group)
	local ticked = selected[group.key] == true and live > 0
	local check = UiKit.create("Frame", {
		Name = "Check",
		BackgroundColor3 = Theme.Color.void,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 144),
		Size = UDim2.fromOffset(22, 22),
		Visible = live > 0 and meltMode,
		ZIndex = 6,
	}) :: Frame
	UiKit.corner(check, 6)
	UiKit.stroke(check, Theme.Color.strokeBright, 2, 0.1)
	check.Parent = card
	local tick = UiKit.label(check, {
		text = "✓",
		size = 16,
		font = Theme.Font.Black,
		color = Theme.Color.void,
		align = Enum.TextXAlignment.Center,
	})
	tick.Name = "Tick"
	tick.Visible = ticked
	tick.Size = UDim2.fromScale(1, 1)
	tick.ZIndex = 7

	if live > 0 then
		local box = UiKit.create("TextButton", {
			Name = "VaultCheck",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 144),
			Size = UDim2.fromOffset(22, 22),
			Visible = live > 0 and meltMode,
			ZIndex = 7,
		}) :: TextButton
		box.Parent = card
		UiKit.track(box, box.Activated:Connect(function()
			toggleSelect(group.key)
		end))
	end

	-- The card body is the inspect target, and the batch target while the melt
	-- mode is armed. One full-size hit layer, so the player never has to find a
	-- 22px box: the tray is the control.
	local hit = UiKit.create("TextButton", {
		Name = "VaultCardHit",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
	}) :: TextButton
	hit.Parent = card
	UiKit.track(hit, hit.Activated:Connect(function()
		if meltMode then
			toggleSelect(group.key)
			return
		end
		inspect(group.key)
		Sfx.ui()
	end))
	UiKit.track(hit, hit.MouseEnter:Connect(function()
		Sfx.hover()
	end))

	thumbsDirty = true
	paintCard(card)
	return card
end

local function rebuildGrid()
	local frame = grid
	if frame == nil then
		return
	end
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(cards)
	table.clear(view)

	local state = current()
	if state == nil then
		return
	end
	table.clear(favoriteSet)
	for uid, flag in state.favorites or {} do
		if flag then
			favoriteSet[uid] = true
		end
	end

	groups = InventoryModel.group(StateStore.inventory, state.equippedUid)

	for _, group in groups do
		if accept(group) then
			table.insert(view, group)
		end
	end
	sortView(view)

	if #view == 0 then
		local message = if #groups == 0
			then "NO BLADES YET. ROLL THE FORGE."
			else "NO BLADES MATCH THIS FILTER."
		local empty = UiKit.label(frame, {
			text = message,
			size = Theme.Text.Body,
			font = Theme.Font.Black,
			color = Theme.Color.textDim,
			align = Enum.TextXAlignment.Center,
		})
		empty.Size = UDim2.new(1, 0, 0, 60)
		empty.LayoutOrder = 1
	end

	-- Keep the inspector on a group that still exists; otherwise fall back to the
	-- top of the list so the right-hand pane is never an empty box.
	local stillVisible = false
	for _, group in view do
		if group.key == inspectKey then
			stillVisible = true
			break
		end
	end
	if not stillVisible then
		inspectKey = if view[1] then view[1].key else nil
	end

	for index, group in view do
		buildCard(group, index)
	end

	refreshBatch()
	paintInspector()
	thumbsDirty = true
end

rebuild = rebuildGrid

local function refresh()
	if not open then
		return
	end
	local state = current()
	local parts = {
		tostring(if state then state.invVersion else 0),
		if state then state.equippedUid else "",
		tostring(if state then state.scrap else 0),
		tostring(totalCopies()),
		tostring(inventoryMax()),
		filterKind,
		sortKind,
	}
	for _, entry in StateStore.inventory do
		parts[#parts + 1] = entry.uid .. ":" .. entry.variant
	end
	for uid, flag in state and state.favorites or {} do
		if flag then
			parts[#parts + 1] = "f" .. uid
		end
	end
	local sig = table.concat(parts, "|")

	if sig ~= signature then
		signature = sig
		rebuildGrid()
	end

	refreshCounts()
end

refreshCounts = function()
	local state = current()
	if state == nil then
		return
	end
	local scrap = scrapValue
	if scrap then
		scrap.Text = NumberUtil.abbreviate(state.scrap)
	end
	local owned = ownedValue
	if owned then
		owned.Text = string.format("%d / %d", state.invCount, state.invMax)
		owned.TextColor3 = if state.invCount >= state.invMax then Theme.Color.warn else Theme.Color.text
	end
	local sort = sortButton
	if sort then
		sort.Text = SORT_LABEL[sortKind] or SORT_LABEL.power
	end
end

-- ---------------------------------------------------------------------------
-- Thumbnail window
-- ---------------------------------------------------------------------------

--- Builds a thumbnail for one card, or frees the model when the card is far
--- enough off screen that it cannot come back into view before the next tick.
local function syncThumb(card: Frame, build: boolean)
	local stage = card:FindFirstChild("VaultThumb")
	if stage == nil or not stage:IsA("ViewportFrame") then
		return
	end
	local bladeId = card:GetAttribute("thumbBlade")
	local variantId = card:GetAttribute("thumbVariant")
	if type(bladeId) ~= "string" or type(variantId) ~= "string" then
		return
	end
	local key = bladeId .. "|" .. variantId

	if build then
		if stage:GetAttribute("ThumbKey") == key then
			return
		end
		local blade = BladeRegistry.get(bladeId)
		if blade == nil then
			return
		end
		BladePreview.thumbnail(stage, blade, false, ForgeConfig.variant(variantId).color)
		stage:SetAttribute("ThumbKey", key)
	else
		if stage:GetAttribute("ThumbKey") == nil then
			return
		end
		stage:ClearAllChildren()
		stage:SetAttribute("ThumbKey", nil)
	end
end

local function updateThumbs()
	local frame = grid
	if frame == nil or not open then
		return
	end
	local top = frame.AbsolutePosition.Y - 10
	local bottom = top + frame.AbsoluteSize.Y + CARD_H
	for _, card in cards do
		local y = card.AbsolutePosition.Y
		local h = card.AbsoluteSize.Y
		local inside = y + h > top and y < bottom
		syncThumb(card, inside)
	end
	thumbsDirty = false
end

-- ---------------------------------------------------------------------------
-- Chrome
-- ---------------------------------------------------------------------------

--- A compact cog for the scrap capsule. Eight teeth, a ring and a bore, drawn
--- with the same 2px outline as every other icon in the chrome.
local function scrapIcon(parent: Frame, size: number)
	local centre = size * 0.5
	local ring = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.woodLight,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size * 0.58, size * 0.58),
		ZIndex = 1,
	}) :: Frame
	UiKit.corner(ring, Theme.Radius.round)
	UiKit.stroke(ring, Theme.Color.outline, 2, 0)
	ring.Parent = parent

	for index = 0, 5 do
		local angle = math.rad(index * 60)
		local tooth = UiKit.create("Frame", {
			BackgroundColor3 = Theme.Color.woodLight,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(centre + math.cos(angle) * size * 0.36, centre + math.sin(angle) * size * 0.36),
			Size = UDim2.fromOffset(size * 0.18, size * 0.24),
			Rotation = index * 60,
			ZIndex = 1,
		}) :: Frame
		UiKit.corner(tooth, 2)
		UiKit.stroke(tooth, Theme.Color.outline, 1, 0.2)
		tooth.Parent = parent
	end

	local bore = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.void,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size * 0.2, size * 0.2),
		ZIndex = 2,
	}) :: Frame
	UiKit.corner(bore, Theme.Radius.round)
	bore.Parent = parent
end

--- The two-line currency capsule, matching the HUD pills but squatter.
local function buildCurrencyPill(parent: Frame, x: number, width: number, caption: string, icon: boolean)
	local pill = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.slate,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(x, 0),
		Size = UDim2.fromOffset(width, TOOLBAR_H),
	}) :: Frame
	UiKit.corner(pill, 12)
	UiKit.gradient(pill, { Theme.Color.slateLift, Theme.Color.slate }, 90)
	UiKit.stroke(pill, Theme.Color.outline, 2.5, 0)
	pill.Parent = parent

	if icon then
		local badge = UiKit.create("Frame", {
			BackgroundColor3 = Theme.Color.wood,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 9, 0.5, 0),
			Size = UDim2.fromOffset(28, 28),
		}) :: Frame
		UiKit.corner(badge, 8)
		UiKit.stroke(badge, Theme.Color.outline, 2, 0)
		badge.Parent = pill
		scrapIcon(badge, 22)
	end

	local left = if icon then 46 else 14
	local value = UiKit.label(pill, {
		text = "0",
		size = Theme.Text.Subheading,
		font = Theme.Font.Numeric,
		color = Theme.Color.text,
		stroke = true,
	})
	value.Position = UDim2.fromOffset(left, 4)
	value.Size = UDim2.new(1, -left - 10, 0, 22)

	local sub = UiKit.label(pill, {
		text = caption,
		size = Theme.Text.Tiny,
		font = Theme.Font.Label,
		color = Theme.Color.gold,
	})
	sub.Position = UDim2.fromOffset(left, 25)
	sub.Size = UDim2.new(1, -left - 10, 0, 16)

	if icon then
		scrapValue = value
	else
		ownedValue = value
	end
	return pill
end

local function buildFilterRow(parent: Frame)
	local row = UiKit.create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(390, 0),
		Size = UDim2.fromOffset(420, TOOLBAR_H),
	}) :: Frame
	row.Parent = parent

	local specs = {
		{ id = "all", label = "ALL" },
		{ id = "equipped", label = "EQUIPPED" },
		{ id = "favorites", label = "FAVORITES" },
	}
	for index, spec in specs do
		local active = filterKind == spec.id
		local pill = UiKit.button(row, {
			text = spec.label,
			fill = if active then Theme.Color.redDeep else Theme.Color.panelSunken,
			stroke = if active then Theme.Color.red else Theme.Color.stroke,
			height = 38,
			radius = Theme.Radius.sm,
			size = Theme.Text.Tiny,
			font = Theme.Font.Black,
			textColor = if active then Theme.Color.text else Theme.Color.textDim,
			handler = function()
				InventoryModal.setFilter(spec.id)
			end,
		})
		pill.Name = "VaultFilter_" .. spec.id
		pill.Position = UDim2.fromOffset((index - 1) * 108, 4)
		pill.Size = UDim2.fromOffset(100, 38)
	end

	sortButton = UiKit.button(parent, {
		text = SORT_LABEL[sortKind] or SORT_LABEL.power,
		fill = Theme.Color.slate,
		stroke = Theme.Color.outline,
		height = 38,
		radius = Theme.Radius.sm,
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		textColor = Theme.Color.text,
		handler = function()
			InventoryModal.cycleSort()
		end,
	})
	sortButton.Name = "VaultSort"
	sortButton.AnchorPoint = Vector2.new(1, 0)
	sortButton.Position = UDim2.new(1, 0, 0, 4)
	sortButton.Size = UDim2.fromOffset(210, 38)
end

local function buildInspector(parent: Frame)
	local frame = UiKit.panel(parent, {
		tier = "raised",
		radius = Theme.Radius.card,
		stroke = Theme.Color.outline,
	})
	frame.Name = "VaultInspector"
	frame.Size = UDim2.new(0, INSPECTOR_W, 1, -(BANNER_H + TOOLBAR_H + 20 + BATCH_H + 10))
	frame.Position = UDim2.new(1, -(INSPECTOR_W + PAD), 0, BANNER_H + TOOLBAR_H + 20)

	inspectorName = UiKit.label(frame, {
		text = "NO BLADE SELECTED",
		size = Theme.Text.Subheading,
		font = Theme.Font.Black,
		color = Theme.Color.text,
		stroke = true,
	})
	inspectorName.Position = UDim2.fromOffset(14, 10)
	inspectorName.Size = UDim2.new(1, -28, 0, 24)
	inspectorName.TextTruncate = Enum.TextTruncate.AtEnd

	inspectorSub = UiKit.label(frame, {
		text = "",
		size = Theme.Text.Micro,
		font = Theme.Font.Label,
		color = Theme.Color.textSecondary,
	})
	inspectorSub.Position = UDim2.fromOffset(14, 34)
	inspectorSub.Size = UDim2.new(1, -28, 0, 18)
	inspectorSub.TextTruncate = Enum.TextTruncate.AtEnd

	local stageWell = UiKit.panel(frame, {
		tier = "well",
		radius = Theme.Radius.md,
		bevel = false,
		lip = false,
	})
	stageWell.Name = "VaultStageWell"
	stageWell.Position = UDim2.fromOffset(12, 58)
	stageWell.Size = UDim2.new(1, -24, 0, 184)
	stageWell.ClipsDescendants = true

	-- The inspect stage gets the same wash as the cards, tinted to the selected
	-- blade. Repainted in `paintInspector` from the tier and variant colours.
	inspectorBackdrop = StageBackdrop.paint(stageWell, {
		warm = Theme.Color.gold,
		cool = Theme.Color.gold,
		accent = Theme.Color.cyan,
		radius = Theme.Radius.md,
		depth = 0.5,
		zIndex = 1,
	})

	local stage = UiKit.create("ViewportFrame", {
		Name = "VaultStage",
		-- Transparent, so the wash behind it is the backdrop. An opaque
		-- viewport here was a black rectangle inside a lit frame.
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 1, -8),
		ZIndex = 2,
	}) :: ViewportFrame
	UiKit.corner(stage, Theme.Radius.sm)
	stage.Parent = stageWell
	inspectorStage = stage

	-- Drag surface. A ViewportFrame never receives mouse presses, so the orbit
	-- needs a button over it; without this the press was eaten by the dimmer
	-- behind the modal and the inspect stage could not be turned at all.
	local grab = UiKit.create("TextButton", {
		Name = "VaultStageGrab",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 1, -8),
		ZIndex = 3,
	}) :: TextButton
	grab.Parent = stageWell
	inspectorSurface = grab

	local well = UiKit.panel(frame, {
		tier = "well",
		radius = Theme.Radius.md,
		bevel = false,
		lip = false,
	})
	well.Name = "VaultStats"
	well.Position = UDim2.fromOffset(12, 252)
	well.Size = UDim2.new(1, -24, 0, 132)
	statWell = well
	UiKit.padding(well, 10, 10, 6)
	-- No list layout on the well itself: the two columns are placed by offset
	-- and each one owns its own `vlist`. A layout here would stack the columns
	-- on top of each other and ignore their x.

	local actions = UiKit.create("Frame", {
		Name = "VaultDock",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 392),
		Size = UDim2.new(1, -24, 0, 76),
	}) :: Frame
	actions.Parent = frame
	dock = actions
end

local function build()
	local canvas = overlay
	if canvas == nil then
		return
	end

	local frame = UiKit.panel(canvas, {
		tier = "shell",
		radius = Theme.Radius.xl,
	})
	frame.Name = "VaultPanel"
	frame.Size = UDim2.fromScale(0.94, 0.92)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.ClipsDescendants = false
	panel = frame

	-- Full-bleed header. The banner goes edge to edge and the close key sits on
	-- top of it: a banner that stops 220px short leaves a bare wood-red strip on
	-- the right, which is the gap this rebuild exists to kill.
	local banner = UiKit.banner(frame, {
		text = "BLADE VAULT",
		position = UDim2.fromOffset(0, 0),
		width = UDim2.new(1, 0, 0, BANNER_H),
		size = 24,
		accent = Theme.Color.gold,
		iconKind = "vault",
		plaqueSize = 40,
		icon = "★",
	})
	local bannerCorner = banner:FindFirstChildOfClass("UICorner")
	if bannerCorner then
		bannerCorner.CornerRadius = UDim.new(0, Theme.Radius.xl)
	end

	local close = UiKit.closeButton(frame, function()
		InventoryModal.close()
	end)
	close.Name = "VaultClose"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 8)
	close.ZIndex = 5

	-- Trade doorway. It lives in the vault rather than the top bar because the
	-- vault is where a player is already looking at copies they do not have
	-- equipped, which is exactly the set that can be offered.
	local trade = UiKit.button(frame, {
		text = "TRADE",
		fill = Theme.Color.emeraldDeep,
		stroke = Theme.Color.emerald,
		height = 38,
		radius = Theme.Radius.sm,
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		textColor = Theme.Color.text,
		handler = function()
			local handler = InventoryModal.tradeHandler
			if handler then
				InventoryModal.close()
				handler()
			end
		end,
	})
	trade.Name = "VaultTrade"
	trade.AnchorPoint = Vector2.new(1, 0)
	trade.Position = UDim2.new(1, -62, 0, 8)
	trade.Size = UDim2.fromOffset(96, 38)
	trade.ZIndex = 5

	local toolbar = UiKit.create("Frame", {
		Name = "VaultToolbar",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(PAD, BANNER_H + 10),
		Size = UDim2.new(1, -PAD * 2, 0, TOOLBAR_H),
	}) :: Frame
	toolbar.Parent = frame

	buildCurrencyPill(toolbar, 0, 200, "SCRAP", true)
	buildCurrencyPill(toolbar, 208, 170, "OWNED", false)
	buildFilterRow(toolbar)

	local scroll = UiKit.scroll(frame)
	scroll.Name = "VaultGrid"
	scroll.Position = UDim2.fromOffset(PAD, BANNER_H + 10 + TOOLBAR_H + 10)
	scroll.Size = UDim2.new(1, -PAD * 2 - INSPECTOR_W - 12, 1, -(BANNER_H + 10 + TOOLBAR_H + 10) - BATCH_H - 10)
	grid = scroll
	UiKit.grid(scroll, UDim2.fromOffset(CARD_W, CARD_H), CARD_GAP)
	UiKit.padding(scroll, 4)

	buildInspector(frame)

	local batch = UiKit.create("Frame", {
		Name = "VaultBatch",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, PAD, 1, -BATCH_H - 10),
		Size = UDim2.new(1, -PAD * 2, 0, BATCH_H),
	}) :: Frame
	batch.Parent = frame

	-- Four keys, four fixed slots, left to right in the order a batch is made:
	-- equip, arm the melt, take every dupe, drop the ticks. Fixed slots mean the
	-- strip never reflows as a selection appears, and 10px of air keeps four 3px
	-- outlines from reading as one long plate.
	--
	-- The melt plate itself lives at the far right, and only while a copy is
	-- ticked. A destructive action does not share a key with the mode switch.
	local equipBest = UiKit.button(batch, {
		text = "EQUIP BEST",
		fill = Theme.Color.cyanDeep,
		stroke = Theme.Color.cyan,
		height = BATCH_H,
		radius = Theme.Radius.md,
		size = Theme.Text.Small,
		font = Theme.Font.Black,
		textColor = Theme.Color.text,
		handler = InventoryModal.equipBest,
	})
	equipBest.Name = "VaultEquipBest"
	equipBest.Position = UDim2.fromOffset(0, 0)
	equipBest.Size = UDim2.fromOffset(190, BATCH_H)

	batchMelt = UiKit.button(batch, {
		text = "MELT MULTIPLE",
		fill = Theme.Color.redDeep,
		stroke = Theme.Color.red,
		height = BATCH_H,
		radius = Theme.Radius.md,
		size = Theme.Text.Small,
		font = Theme.Font.Black,
		textColor = Theme.Color.text,
		handler = function()
			setMeltMode(not meltMode)
			Sfx.tab()
		end,
	})
	batchMelt.Name = "VaultMeltSelected"
	batchMelt.Position = UDim2.fromOffset(190 + BATCH_GAP, 0)
	batchMelt.Size = UDim2.fromOffset(208, BATCH_H)

	batchDupes = UiKit.button(batch, {
		text = "SELECT DUPES",
		fill = Theme.Color.panelSunken,
		stroke = Theme.Color.stroke,
		height = BATCH_H,
		radius = Theme.Radius.md,
		size = Theme.Text.Small,
		font = Theme.Font.Black,
		textColor = Theme.Color.textSecondary,
		handler = InventoryModal.selectDupes,
	})
	batchDupes.Name = "VaultSelectDupes"
	batchDupes.Position = UDim2.fromOffset(190 + 208 + BATCH_GAP * 2, 0)
	batchDupes.Size = UDim2.fromOffset(150, BATCH_H)

	batchClear = UiKit.button(batch, {
		text = "CLEAR",
		fill = Theme.Color.panelSunken,
		stroke = Theme.Color.stroke,
		height = BATCH_H,
		radius = Theme.Radius.md,
		size = Theme.Text.Small,
		font = Theme.Font.Black,
		textColor = Theme.Color.textDim,
		handler = InventoryModal.clearSelection,
	})
	batchClear.Name = "VaultClear"
	batchClear.Position = UDim2.fromOffset(190 + 208 + 150 + BATCH_GAP * 3, 0)
	batchClear.Size = UDim2.fromOffset(88, BATCH_H)

	batchConfirm = UiKit.button(batch, {
		text = "MELT",
		fill = Theme.Color.redDeep,
		stroke = Theme.Color.red,
		height = BATCH_H,
		radius = Theme.Radius.md,
		size = Theme.Text.Small,
		font = Theme.Font.Black,
		textColor = Theme.Color.text,
		handler = InventoryModal.meltSelected,
	})
	batchConfirm.Name = "VaultMeltConfirm"
	batchConfirm.AnchorPoint = Vector2.new(1, 0)
	batchConfirm.Position = UDim2.fromScale(1, 0)
	batchConfirm.Size = UDim2.fromOffset(240, BATCH_H)
	batchConfirm.Visible = false

	selectionLabel = UiKit.label(batch, {
		text = "0 TO MELT  ·  +0 SCRAP",
		size = Theme.Text.Micro,
		font = Theme.Font.Numeric,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Right,
		alignY = Enum.TextYAlignment.Center,
	})
	selectionLabel.Name = "VaultSelection"
	selectionLabel.AnchorPoint = Vector2.new(1, 0)
	selectionLabel.Position = UDim2.fromScale(1, 0)
	selectionLabel.Size = UDim2.fromOffset(240, BATCH_H)
	selectionLabel.Visible = false

	UiKit.track(scroll, scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		thumbsDirty = true
	end))
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function InventoryModal.isOpen(): boolean
	return open
end

function InventoryModal.open()
	if open then
		return
	end
	if overlay == nil then
		return
	end
	open = true
	overlay.Visible = true
	signature = ""
	refresh()
	refreshCounts()
	if panel then
		panel.Position = UDim2.fromScale(0.5, 0.54)
		Theme.tween(panel, Theme.Duration.normal, { Position = UDim2.fromScale(0.5, 0.5) })
	end
	Sfx.modal()
	thumbsDirty = true
	local callback = InventoryModal.onOpenChange
	if callback then
		callback(true)
	end
end

function InventoryModal.close()
	if not open then
		return
	end
	open = false
	inspectKey = nil
	-- The mode does not survive a close: a batch left armed with ticks the
	-- player cannot see is a melt waiting to happen.
	meltMode = false
	table.clear(selected)
	clearInspector()
	if overlay then
		overlay.Visible = false
	end
	Sfx.close()
	local callback = InventoryModal.onOpenChange
	if callback then
		callback(false)
	end
end

function InventoryModal.toggle()
	if open then
		InventoryModal.close()
	else
		InventoryModal.open()
	end
end

function InventoryModal.init(canvas: Frame)
	if overlay then
		return
	end

	local layer = UiKit.create("Frame", {
		Name = "VaultOverlay",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 31,
	}) :: Frame
	layer.Parent = canvas
	overlay = layer

	-- The dim lives inside the layer so show/hide is one flag, and it is one
	-- ZIndex below the panel: clicks that miss the panel land here and close.
	local dim = UiKit.create("TextButton", {
		Name = "Dim",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Color.void,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
	}) :: TextButton
	dim.Parent = layer
	UiKit.track(dim, dim.Activated:Connect(function()
		-- The vault panel is a Frame, not a button, so a click on a gap between
		-- cards or under the inspector used to pass through to this dimmer and
		-- close the vault. Ignore anything that landed inside the panel; only
		-- the gutter around the sheet is a close target.
		local panelBox = panel
		if panelBox == nil then
			return
		end
		local point = UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
		local origin = panelBox.AbsolutePosition
		local extent = origin + panelBox.AbsoluteSize
		if point.X >= origin.X and point.X <= extent.X and point.Y >= origin.Y and point.Y <= extent.Y then
			return
		end
		InventoryModal.close()
	end))

	build()

	unsubSync = StateStore.onSync(function()
		refresh()
	end)
	unsubInventory = StateStore.onInventory(function()
		signature = ""
		refresh()
	end)

	-- Thumbnails are built on demand. A 240ms tick is faster than a row of cards
	-- can be scrolled into the window and cheap enough to run while the vault is
	-- closed (the guard returns immediately).
	task.spawn(function()
		while overlay do
			task.wait(0.24)
			if open and thumbsDirty then
				updateThumbs()
			end
		end
	end)
end

function InventoryModal.destroy()
	if unsubSync then
		unsubSync()
		unsubSync = nil
	end
	if unsubInventory then
		unsubInventory()
		unsubInventory = nil
	end
	open = false
	inspectKey = nil
	signature = ""
	clearInspector()
	table.clear(selected)
	table.clear(favoriteSet)
	table.clear(cards)
	table.clear(groups)
	table.clear(view)
	if overlay then
		overlay:Destroy()
		overlay = nil
	end
	panel = nil
	grid = nil
	inspectorStage = nil
	inspectorName = nil
	inspectorSub = nil
	statWell = nil
	dock = nil
	scrapValue = nil
	ownedValue = nil
	sortButton = nil
	batchMelt = nil
	batchDupes = nil
	batchClear = nil
	selectionLabel = nil
end

return InventoryModal
