--!strict
-- The forge handbook: ten pages, every number read from the config that owns it.
--
-- Why this replaced the old spotlight guide: the guide was a sequence of cards
-- that fired on thresholds, plus an objective strip and a ring that had to track
-- a control through tab switches. It interrupted play, and when the ring lost its
-- target it pointed at nothing. A handbook is a thing a player opens on purpose,
-- and it can be honest about the whole system on page one instead of dribbling
-- one rule per interruption.
--
-- The pages are built by `pages()` at paint time, not at require time, because
-- half of the numbers are the player's own: capacity, heat, drones, scrap, the
-- roll price at the banner they are on. A handbook that prints a stale capacity
-- is worse than no handbook.
--
-- Art is drawn, except for two live 3D stages (the equipped blade and the vault
-- card), which are the only visuals that cannot lie about what the player owns.
-- Nothing here is an uploaded screenshot, so nothing here can render as a grey
-- box on a cold join.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local AssetManifest = require(Shared:WaitForChild("AssetManifest"))
local BladeRegistry = require(Shared:WaitForChild("BladeRegistry"))
local Config = require(Shared:WaitForChild("Config"))
local ForgeConfig = require(Shared:WaitForChild("ForgeConfig"))
local ModifierConfig = require(Shared:WaitForChild("ModifierConfig"))
local NumberUtil = require(Shared:WaitForChild("NumberUtil"))
local RuneConfig = require(Shared:WaitForChild("RuneConfig"))
local TechTreeConfig = require(Shared:WaitForChild("TechTreeConfig"))
local Types = require(Shared:WaitForChild("Types"))

local Theme = require(script.Parent.Theme)
local UiKit = require(script.Parent.UiKit)
local BladePreview = require(script.Parent.BladePreview)
local ModalShell = require(script.Parent.ModalShell)
local StateStore = require(script.Parent.StateStore)
local Sfx = require(script.Parent.Sfx)

local HandbookView = {}

local PANEL_W = 1120
local PANEL_H = 700
local RAIL_W = 232
local CONTENT_X = 264
local CONTENT_W = PANEL_W - CONTENT_X - 16
local LEFT_W = 500
local ART_X = 516
local ART_W = CONTENT_W - ART_X
local PAGE_BUTTON_H = 44

type Page = {
	id: string,
	title: string,
	kicker: string,
	accent: Color3,
	lead: string,
	steps: { { head: string, body: string } },
	facts: { { label: string, value: string } },
	art: string,
	tip: string,
}

local shell: ModalShell.Handle? = nil
local rail: ScrollingFrame? = nil
local content: Frame? = nil
local activeIndex = 1
local cleanup: (() -> ())? = nil

-- ---------------------------------------------------------------------------
-- Drawing helpers
-- ---------------------------------------------------------------------------

local function block(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, radius: number?): Frame
	local frame = UiKit.create("Frame", {
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		ZIndex = 3,
	}) :: Frame
	UiKit.corner(frame, radius or 4)
	frame.Parent = parent
	return frame
end

--- The empty half of a bar. `panelSunken` sits twelve values off the panel it
--- is drawn on, so a track in it reads as nothing and every empty bar looks like
--- a stray stub floating in the dark. `void` plus a hairline outline makes the
--- slot visible, which is the whole job of a track.
local function track(parent: Instance, x: number, y: number, w: number, h: number, radius: number?): Frame
	local frame = block(parent, x, y, w, h, Theme.Color.void, radius)
	UiKit.stroke(frame, Theme.Color.strokeFaint, 1, 0)
	return frame
end

local function text(
	parent: Instance,
	value: string,
	x: number,
	y: number,
	w: number,
	h: number,
	size: number,
	color: Color3,
	font: Enum.Font?,
	align: Enum.TextXAlignment?
): TextLabel
	local label = UiKit.label(parent, {
		text = value,
		size = size,
		font = font or Theme.Font.Body,
		color = color,
		align = align or Enum.TextXAlignment.Left,
	})
	label.Position = UDim2.fromOffset(x, y)
	label.Size = UDim2.fromOffset(w, h)
	label.ZIndex = 4
	return label
end

local function percent(part: number, whole: number): number
	if whole <= 0 then
		return 0
	end
	return math.clamp(part / whole, 0, 1)
end

local function stateNow(): any
	return StateStore.current
end

--- A framed plate inside an art panel. Local because three painters build the
--- same object and the panel options are four lines each.
local function uiPanel(parent: Instance, x: number, y: number, w: number, h: number, stroke: Color3): Frame
	local frame = UiKit.panel(parent, {
		tier = "well",
		radius = Theme.Radius.sm,
		stroke = stroke,
		bevel = false,
		lip = false,
	})
	frame.Position = UDim2.fromOffset(x, y)
	frame.Size = UDim2.fromOffset(w, h)
	return frame
end

-- ---------------------------------------------------------------------------
-- Art
-- ---------------------------------------------------------------------------

local ART: { [string]: (panel: Frame, accent: Color3) -> () } = {}

--- The equipped blade, spinning. The only art that is looked up rather than
--- drawn, and the only one that can show the player something they own.
ART.blade = function(panel: Frame, accent: Color3)
	local state = stateNow()
	local bladeId = if state and type(state.equipped) == "string" and state.equipped ~= ""
		then state.equipped
		else BladeRegistry.StarterBlade
	local blade = BladeRegistry.get(bladeId)
	if blade == nil then
		return
	end

	local stage = UiKit.create("ViewportFrame", {
		Name = "BladeStage",
		BackgroundColor3 = Theme.Color.void,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(52, 26),
		Size = UDim2.fromOffset(220, 236),
		ZIndex = 3,
	}) :: ViewportFrame
	UiKit.corner(stage, 10)
	UiKit.stroke(stage, Theme.Color.strokeFaint, 1, 0)
	stage.Parent = panel

	local tint = if state and type(state.equippedElement) == "string" and state.equippedElement ~= ""
		then ModifierConfig.element(state.equippedElement).color
		else accent
	cleanup = BladePreview.mount(stage, blade, tint)

	local name = if state and type(state.equipped) == "string" and state.equipped ~= ""
		then ModifierConfig.displayName(blade.name, state.equippedPrefix or "", state.equippedSuffix or "")
		else blade.name
	text(panel, name, 18, 270, ART_W - 36, 22, Theme.Text.Small, Theme.Color.text, Theme.Font.Heading, Enum.TextXAlignment.Center)
	text(panel, "EQUIPPED COPY", 18, 294, ART_W - 36, 18, Theme.Text.Tiny, accent, Theme.Font.Black, Enum.TextXAlignment.Center)
	text(panel, "TAP AND DRAG TO TURN IT", 18, 318, ART_W - 36, 16, Theme.Text.Tiny, Theme.Color.textFaint, Theme.Font.Label, Enum.TextXAlignment.Center)
end

--- The heat gauge, drawn as the three zones the physics actually has.
ART.gauge = function(panel: Frame, _accent: Color3)
	local state = stateNow()
	local heat = math.clamp(if state then state.heat else 0, 0, 100)
	local trackX, trackY, trackW, trackH = 18, 46, ART_W - 36, 26

	text(panel, "HEAT GAUGE", 18, 16, ART_W - 36, 20, Theme.Text.Tiny, Theme.Color.textDim, Theme.Font.Black)
	track(panel, trackX, trackY, trackW, trackH, 6)

	local sweetA = percent(Config.SweetSpotMin, 100)
	local sweetB = percent(Config.SweetSpotMax, 100)
	local dangerA = percent(Config.OverheatAt, 100)

	local cool = block(panel, trackX + 3, trackY + 3, (trackW - 6) * sweetA, trackH - 6, Theme.Color.heatCool, 4)
	cool.BackgroundTransparency = 0.25
	local sweet = block(panel, trackX + 3 + (trackW - 6) * sweetA, trackY + 3, (trackW - 6) * (sweetB - sweetA), trackH - 6, Theme.Color.heatSweet, 4)
	sweet.BackgroundTransparency = 0.1
	local hot = block(panel, trackX + 3 + (trackW - 6) * sweetB, trackY + 3, (trackW - 6) * (dangerA - sweetB), trackH - 6, Theme.Color.heatHot, 4)
	hot.BackgroundTransparency = 0.2
	local burn = block(panel, trackX + 3 + (trackW - 6) * dangerA, trackY + 3, (trackW - 6) * (1 - dangerA), trackH - 6, Theme.Color.heatCritical, 4)
	burn.BackgroundTransparency = 0.1

	local needle = block(panel, trackX + (trackW - 4) * percent(heat, 100), trackY - 8, 4, trackH + 16, Theme.Color.text, 2)
	needle.ZIndex = 5

	text(panel, string.format("%d", math.floor(heat)), trackX, trackY + trackH + 4, 80, 24, Theme.Text.Subheading, Theme.Color.text, Theme.Font.Numeric)
	text(panel, "CURRENT HEAT", trackX + 72, trackY + trackH + 10, trackW - 72, 18, Theme.Text.Tiny, Theme.Color.textDim, Theme.Font.Label, Enum.TextXAlignment.Right)
	text(panel, string.format("SWEET %d-%d", Config.SweetSpotMin, Config.SweetSpotMax), 18, 112, ART_W - 36, 18, Theme.Text.Tiny, Theme.Color.heatSweet, Theme.Font.Black)
	text(panel, string.format("VENT ABOVE %d", Config.VentThreshold), 18, 134, ART_W - 36, 18, Theme.Text.Tiny, Theme.Color.heatHot, Theme.Font.Black)
	text(panel, string.format("BURNOUT AT %d", Config.OverheatAt), 18, 156, ART_W - 36, 18, Theme.Text.Tiny, Theme.Color.heatCritical, Theme.Font.Black)

	local rows = {
		{ string.format("+%.1f HEAT PER STRIKE", Config.HeatPerClick), Theme.Color.textSecondary },
		{ string.format("-%.1f HEAT PER SECOND", Config.HeatDecayPerSec), Theme.Color.textSecondary },
		{ string.format("%.2fx YIELD IN THE BAND", Config.SweetSpotMultiplier), Theme.Color.starMatter },
		{ string.format("%d STRIKES OPEN OVERDRIVE", Config.StreakForOverdrive), Theme.Color.cyan },
	}
	for index, row in rows do
		local y = 190 + (index - 1) * 34
		block(panel, 18, y + 6, 6, 10, row[2], 3)
		text(panel, row[1], 32, y, ART_W - 50, 22, Theme.Text.Tiny, row[2], Theme.Font.Label)
	end
end

--- Rarity odds, as bars. `RarityWeights` is the authority, so this cannot drift
--- from the roll.
ART.odds = function(panel: Frame, _accent: Color3)
	local total = 0
	for _, weight in ForgeConfig.RarityWeights do
		total += weight
	end
	text(panel, "RARITY WEIGHTS", 18, 16, ART_W - 36, 20, Theme.Text.Tiny, Theme.Color.textDim, Theme.Font.Black)

	for index, rarity in ForgeConfig.RarityOrder do
		local weight = ForgeConfig.RarityWeights[rarity] or 0
		local y = 52 + (index - 1) * 52
		local share = percent(weight, total)
		local color = Theme.rarityColor(index)
		text(panel, string.upper(rarity), 18, y, 120, 20, Theme.Text.Tiny, color, Theme.Font.Black)
		text(panel, string.format("%.1f%%", share * 100), ART_W - 86, y, 68, 20, Theme.Text.Tiny, Theme.Color.text, Theme.Font.Numeric, Enum.TextXAlignment.Right)
		track(panel, 18, y + 24, ART_W - 36, 12, 6)
		block(panel, 18, y + 24, math.max(2, (ART_W - 36) * share), 12, color, 6)
	end

	local state = stateNow()
	local pity = if state and type(state.forgePity) == "number" then state.forgePity else 0
	text(panel, string.format("PITY  %d / %d", pity, ForgeConfig.Tiers[#ForgeConfig.Tiers].pity), 18, 322, ART_W - 36, 20, Theme.Text.Tiny, Theme.Color.textFaint, Theme.Font.Label)
end

ART.variants = function(panel: Frame, _accent: Color3)
	local total = 0
	for _, id in ForgeConfig.VariantOrder do
		total += ForgeConfig.variant(id).weight
	end
	text(panel, "FIVE FINISHES", 18, 16, ART_W - 36, 20, Theme.Text.Tiny, Theme.Color.textDim, Theme.Font.Black)

	for index, id in ForgeConfig.VariantOrder do
		local variant = ForgeConfig.variant(id)
		local y = 48 + (index - 1) * 62
		block(panel, 18, y + 4, 14, 14, variant.color, 3)
		text(panel, string.upper(variant.name), 40, y, 180, 20, Theme.Text.Tiny, variant.color, Theme.Font.Black)
		text(panel, string.format("%.1f%%  x%.2f", percent(variant.weight, total) * 100, variant.mult), ART_W - 140, y, 122, 20, Theme.Text.Tiny, Theme.Color.text, Theme.Font.Numeric, Enum.TextXAlignment.Right)
		text(panel, variant.text, 40, y + 22, ART_W - 58, 30, Theme.Text.Tiny, Theme.Color.textSecondary, Theme.Font.Body)
	end
end

ART.quality = function(panel: Frame, accent: Color3)
	text(panel, "FOUR STEPS PER GRADE", 18, 16, ART_W - 36, 20, Theme.Text.Tiny, Theme.Color.textDim, Theme.Font.Black)
	text(panel, "GRADE x ELEMENT x PREFIX x SUFFIX", 18, 38, ART_W - 36, 18, Theme.Text.Tiny, Theme.Color.textFaint, Theme.Font.Label)

	local suffixes = { "-", "", "+", "++" }
	local thresholds = { "UNDER 1.20", "1.20 TO 1.44", "1.45 TO 1.71", "1.72 AND UP" }
	for step = 1, 4 do
		local y = 72 + (step - 1) * 64
		local sample = "MYTHIC" .. suffixes[step]
		text(panel, sample, 18, y, 160, 22, Theme.Text.Small, accent, Theme.Font.Black)
		text(panel, thresholds[step], ART_W - 158, y, 140, 20, Theme.Text.Tiny, Theme.Color.textSecondary, Theme.Font.Label, Enum.TextXAlignment.Right)
		for pip = 1, 4 do
			block(panel, 18 + (pip - 1) * 30, y + 30, 24, 8, if pip <= step then accent else Theme.Color.strokeFaint, 4)
		end
	end
	text(panel, "24 BANDS. EACH PRINTED NUMBER IS THE COPY'S TRUE MULTIPLIER.", 18, 330, ART_W - 36, 32, Theme.Text.Tiny, Theme.Color.textFaint, Theme.Font.Body)
end

ART.vault = function(panel: Frame, accent: Color3)
	local state = stateNow()
	local count = if state then state.invCount else 0
	local max = if state then state.invMax else Config.InventoryMax
	local scrap = if state then state.scrap else 0

	text(panel, "CAPACITY", 18, 16, 120, 20, Theme.Text.Tiny, Theme.Color.textDim, Theme.Font.Black)
	text(panel, string.format("%d / %d", count, max), ART_W - 138, 16, 120, 20, Theme.Text.Tiny, Theme.Color.text, Theme.Font.Numeric, Enum.TextXAlignment.Right)
	block(panel, 18, 42, ART_W - 36, 14, Theme.Color.void, 7)
	local fill = math.max(2, (ART_W - 36) * percent(count, math.max(1, max)))
	block(panel, 18, 42, fill, 14, if count >= max then Theme.Color.danger else accent, 7)

	local card = UiKit.panel(panel, {
		tier = "item",
		radius = Theme.Radius.sm,
		stroke = Theme.Color.stroke,
		bevel = false,
		lip = false,
	})
	card.Name = "VaultSample"
	card.Position = UDim2.fromOffset(18, 76)
	card.Size = UDim2.fromOffset(124, 156)

	local stage = UiKit.create("ViewportFrame", {
		Name = "SampleStage",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(22, 8),
		Size = UDim2.fromOffset(80, 88),
		ZIndex = 4,
	}) :: ViewportFrame
	stage.Parent = card
	local stateBlade = if state and type(state.equipped) == "string" and state.equipped ~= "" then state.equipped else BladeRegistry.StarterBlade
	local blade = BladeRegistry.get(stateBlade)
	if blade then
		local tint = if state and type(state.equippedVariant) == "string"
			then ForgeConfig.variant(state.equippedVariant).color
			else Theme.Color.gold
		BladePreview.thumbnail(stage, blade, false, tint)
	end
	text(card, "SAMPLE COPY", 6, 100, 112, 18, Theme.Text.Tiny, Theme.Color.text, Theme.Font.Black, Enum.TextXAlignment.Center)
	text(card, "MELTS FOR", 6, 118, 112, 16, Theme.Text.Tiny, Theme.Color.textSecondary, Theme.Font.Label, Enum.TextXAlignment.Center)

	-- The real salvage of the equipped copy, from the same function the melt
	-- button calls. An invented "+N" next to a page that promises real numbers
	-- is the one thing this book cannot do.
	local equippedUid = if state and type(state.equippedUid) == "string" then state.equippedUid else ""
	local sample: Types.InvEntry? = nil
	for _, entry in StateStore.inventory do
		if entry.uid == equippedUid then
			sample = entry
			break
		end
	end
	local melt = if sample then ForgeConfig.salvageCopy(sample) else 0
	text(card, string.format("+%d SCRAP", melt), 6, 134, 112, 18, Theme.Text.Tiny, Theme.Color.starMatter, Theme.Font.Numeric, Enum.TextXAlignment.Center)

	local rows = {
		{ "COPIES", string.format("%d", count), Theme.Color.text },
		{ "SCRAP", NumberUtil.abbreviate(scrap), Theme.Color.starMatter },
		{ "CAP", string.format("%d", max), Theme.Color.textSecondary },
		{ "REROLL", string.format("%d+ SCRAP", ForgeConfig.rerollCost(1)), Theme.Color.cyan },
	}
	for index, row in rows do
		local y = 78 + (index - 1) * 42
		text(panel, row[1], 160, y, 90, 18, Theme.Text.Tiny, Theme.Color.textFaint, Theme.Font.Label)
		text(panel, row[2], 160, y + 18, ART_W - 178, 18, Theme.Text.Tiny, row[3], Theme.Font.Numeric)
	end
end

ART.fleet = function(panel: Frame, accent: Color3)
	local state = stateNow()
	local fleet = if state then state.fleet else {}
	local total = if state then state.drones else 0

	text(panel, "DRONES", 18, 16, 120, 20, Theme.Text.Tiny, Theme.Color.textDim, Theme.Font.Black)
	text(panel, string.format("%d", total), ART_W - 138, 12, 120, 26, Theme.Text.Subheading, Theme.Color.aether, Theme.Font.Numeric, Enum.TextXAlignment.Right)

	local best = 1
	for _, entry in fleet do
		best = math.max(best, entry.owned)
	end
	for index, entry in fleet do
		local y = 48 + (index - 1) * 50
		local rung = string.upper(string.gsub(tostring(entry.id), "_", " "))
		text(panel, rung, 18, y, 150, 20, Theme.Text.Tiny, if entry.unlocked then Theme.Color.text else Theme.Color.locked, Theme.Font.Label)
		text(panel, string.format("%d", entry.owned), ART_W - 78, y, 60, 20, Theme.Text.Tiny, Theme.Color.aether, Theme.Font.Numeric, Enum.TextXAlignment.Right)
		track(panel, 18, y + 24, ART_W - 36, 10, 5)
		block(panel, 18, y + 24, (ART_W - 36) * percent(entry.owned, best), 10, if entry.unlocked then accent else Theme.Color.strokeFaint, 5)
	end
	text(panel, string.format("OFFLINE  %s AT %d%%", NumberUtil.abbreviateTime(Config.OfflineCapSeconds), math.floor(Config.OfflineEfficiency * 100)), 18, 312, ART_W - 36, 20, Theme.Text.Tiny, Theme.Color.textFaint, Theme.Font.Label)
end

ART.runes = function(panel: Frame, accent: Color3)
	local state = stateNow()
	local runes = if state then state.runes else {}
	local sockets = if state then state.socketSlots else 0

	text(panel, "SOCKETS", 18, 16, 120, 20, Theme.Text.Tiny, Theme.Color.textDim, Theme.Font.Black)
	for slot = 1, RuneConfig.MaxSockets do
		local open = slot <= (sockets or 0)
		local box = block(panel, 18 + (slot - 1) * 44, 42, 38, 38, if open then Theme.Color.panelSunken else Theme.Color.slate, 8)
		UiKit.stroke(box, if open then accent else Theme.Color.stroke, 2, if open then 0 else 0.5)
		text(box, if open then "+" else "X", 0, 0, 38, 38, Theme.Text.Small, if open then accent else Theme.Color.locked, Theme.Font.Black, Enum.TextXAlignment.Center)
	end
	text(panel, string.format("MASTERY RANK %d", if state then state.mastery else 0), 168, 42, ART_W - 186, 20, Theme.Text.Tiny, Theme.Color.textSecondary, Theme.Font.Label)
	text(panel, string.format("%d / %d STRIKES", if state then state.masteryXp else 0, if state and state.masteryNext then state.masteryNext else RuneConfig.Thresholds[1]), 168, 62, ART_W - 186, 18, Theme.Text.Tiny, Theme.Color.textFaint, Theme.Font.Numeric)

	local palette = { Theme.Color.starMatter, Theme.Color.cyan, Theme.Color.red, Theme.Color.quantum }
	for index, id in RuneConfig.Order do
		local rune = RuneConfig.get(id)
		if rune then
			local y = 100 + (index - 1) * 52
			local color = palette[index] or accent
			block(panel, 18, y + 2, 12, 12, color, 3)
			text(panel, rune.name, 38, y, 180, 20, Theme.Text.Tiny, color, Theme.Font.Label)
			text(panel, string.format("x%d", runes[id] or 0), ART_W - 78, y, 60, 20, Theme.Text.Tiny, Theme.Color.text, Theme.Font.Numeric, Enum.TextXAlignment.Right)
			text(panel, rune.description, 38, y + 20, ART_W - 58, 26, Theme.Text.Tiny, Theme.Color.textSecondary, Theme.Font.Body)
		end
	end
end

ART.ascend = function(panel: Frame, _accent: Color3)
	local state = stateNow()
	local sm = if state then state.sm else 0
	local progress = percent(sm, Config.AscendThreshold)

	text(panel, "ASCENSION THRESHOLD", 18, 16, ART_W - 36, 20, Theme.Text.Tiny, Theme.Color.textDim, Theme.Font.Black)
	text(panel, NumberUtil.abbreviate(Config.AscendThreshold) .. " SM", 18, 40, ART_W - 36, 30, Theme.Text.Heading, Theme.Color.quantum, Theme.Font.Numeric)
	track(panel, 18, 78, ART_W - 36, 16, 8)
	block(panel, 18, 78, (ART_W - 36) * progress, 16, Theme.Color.quantum, 8)
	text(panel, string.format("%.0f%% OF THE WAY", progress * 100), 18, 100, ART_W - 36, 18, Theme.Text.Tiny, Theme.Color.textFaint, Theme.Font.Label)

	local plate = UiKit.panel(panel, {
		tier = "well",
		radius = Theme.Radius.sm,
		stroke = Theme.Color.strokeFaint,
		bevel = false,
		lip = false,
	})
	plate.Position = UDim2.fromOffset(18, 134)
	plate.Size = UDim2.fromOffset(ART_W - 36, 92)
	text(plate, "CORES = SQUARE ROOT OF", 12, 8, ART_W - 60, 18, Theme.Text.Tiny, Theme.Color.textFaint, Theme.Font.Label)
	text(plate, "SM / 1B", 12, 26, ART_W - 60, 26, Theme.Text.Subheading, Theme.Color.text, Theme.Font.Numeric)

	local cores = math.floor((sm / Config.AscendThreshold) ^ Config.AscendExponent)
	text(panel, "YOU WOULD EARN", 18, 240, ART_W - 36, 18, Theme.Text.Tiny, Theme.Color.textDim, Theme.Font.Black)
	text(panel, string.format("%s CORE%s", NumberUtil.abbreviate(cores), if cores == 1 then "" else "S"), 18, 260, ART_W - 36, 30, Theme.Text.Heading, Theme.Color.quantum, Theme.Font.Numeric, Enum.TextXAlignment.Center)

	local lines = {
		{ "KEEPS", "TECH, CODEX, MASTERY, CORES", Theme.Color.emerald },
		{ "LOSES", "SM, AETHER, DRONES, BLADES", Theme.Color.danger },
	}
	for index, line in lines do
		local y = 302 + (index - 1) * 28
		text(panel, line[1], 18, y, 60, 18, Theme.Text.Tiny, line[3], Theme.Font.Black)
		text(panel, line[2], 84, y, ART_W - 102, 18, Theme.Text.Tiny, Theme.Color.textSecondary, Theme.Font.Label)
	end
end

ART.trade = function(panel: Frame, _accent: Color3)
	text(panel, "THE EXCHANGE", 18, 16, ART_W - 36, 20, Theme.Text.Tiny, Theme.Color.textDim, Theme.Font.Black)

	local function plate(x: number, label: string, color: Color3)
		local frame = uiPanel(panel, x, 46, 126, 104, color)
		text(frame, label, 6, 8, 114, 18, Theme.Text.Tiny, color, Theme.Font.Black, Enum.TextXAlignment.Center)
		for index = 1, 3 do
			-- Visible sockets, not black bars: `strokeFaint` is one step off the
			-- well, which reads as three empty slots instead of three holes.
			block(frame, 10, 32 + (index - 1) * 22, 106, 16, Theme.Color.strokeFaint, 4)
		end
	end
	plate(14, "YOUR OFFER", Theme.Color.emerald)
	plate(ART_W - 140, "THEIR OFFER", Theme.Color.cyan)
	text(panel, "⇄", ART_W / 2 - 16, 78, 32, 32, 30, Theme.Color.text, Theme.Font.Black, Enum.TextXAlignment.Center)

	local bar = UiKit.panel(panel, {
		tier = "raised",
		radius = Theme.Radius.sm,
		stroke = Theme.Color.emerald,
		bevel = false,
		lip = false,
	})
	bar.Position = UDim2.fromOffset(18, 168)
	bar.Size = UDim2.fromOffset(ART_W - 36, 38)
	text(bar, "BOTH SIDES ACCEPT", 0, 0, ART_W - 36, 38, Theme.Text.Small, Theme.Color.emerald, Theme.Font.Black, Enum.TextXAlignment.Center)

	local notes = {
		"8 BLADES PER SIDE",
		"ANY CHANGE CLEARS BOTH KEYS",
		"OFFERED COPIES CANNOT BE MELTED",
		"REQUESTS EXPIRE IN 20 SECONDS",
	}
	for index, note in notes do
		text(panel, note, 18, 218 + (index - 1) * 28, ART_W - 36, 22, Theme.Text.Tiny, Theme.Color.textSecondary, Theme.Font.Label)
	end
end

-- ---------------------------------------------------------------------------
-- Pages
-- ---------------------------------------------------------------------------

--- Tech nodes live in a config module required at the top of this file; the
--- count is all the handbook needs from it.
local TECH_NODES = #TechTreeConfig.list()

local function pages(): { Page }
	local state = stateNow()
	local tier = if state
		then (ForgeConfig.tierAt(math.max(1, math.floor(tonumber(state.forgeTier) or 1))) or ForgeConfig.Tiers[1])
		else ForgeConfig.Tiers[1]
	local tierName = if state and type(state.forgeTierName) == "string" and state.forgeTierName ~= ""
		then state.forgeTierName
		else tier.name
	local cost = if state then state.forgeCost else tier.cost
	local click = if state then state.clickYield else Config.BaseClickYield
	local mult = if state then state.mult else 1
	local passive = if state then state.passiveYield else 0
	local runeBag = if state and type(state.runes) == "table" then state.runes else {}
	local runeTotal = 0
	for _, count in runeBag do
		runeTotal += count
	end

	return {
		{
			id = "loop",
			title = "THE LOOP",
			kicker = "START HERE",
			accent = Theme.Color.starMatter,
			lead = "Strike the anvil, hold the heat band, and spend what you earn on rolls. Every blade you forge multiplies every strike after it.",
			steps = {
				{ head = "STRIKE", body = "The anvil, or the space bar. Each hit pays your multiplier and adds heat." },
				{ head = "RIDE THE BAND", body = string.format("Between %d and %d heat every strike pays %.1fx. That is the skill curve.", Config.SweetSpotMin, Config.SweetSpotMax, Config.SweetSpotMultiplier) },
				{ head = "VENT, THEN ROLL", body = "Venting above the threshold pays Aether. Star-Matter buys the crate on the right." },
			},
			facts = {
				{ label = "STAR-MATTER", value = if state then NumberUtil.abbreviate(state.sm) else "0" },
				{ label = "PER STRIKE", value = NumberUtil.abbreviate(click) },
				{ label = "MULTIPLIER", value = NumberUtil.abbreviateMultiplier(mult) },
				{ label = "PASSIVE / SEC", value = NumberUtil.abbreviate(passive) },
			},
			art = "blade",
			tip = "Every number in this book is read from the same config the game runs on. If a page says 2.5x, the anvil pays 2.5x.",
		},
		{
			id = "heat",
			title = "HEAT AND VENTS",
			kicker = "THE ONE MECHANIC THAT PUNISHES MASHING",
			accent = Theme.Color.heatHot,
			lead = string.format("Heat climbs %.1f per strike and falls %.1f per second. Holding %d to %d pays %.1fx. Past %d the gauge runs hot and venting becomes legal; at %d it caps and stays there.", Config.HeatPerClick, Config.HeatDecayPerSec, Config.SweetSpotMin, Config.SweetSpotMax, Config.SweetSpotMultiplier, Config.VentThreshold, Config.OverheatAt),
			steps = {
				{ head = "CLIMB", body = string.format("%.1f heat per strike against %.1f lost per second. The gauge only climbs past two strikes a second, and the band opens at %d.", Config.HeatPerClick, Config.HeatDecayPerSec, Config.SweetSpotMin) },
				{ head = "HOLD", body = string.format("In the band, crits and anomalies are live. %d clean strikes in a row opens Overdrive: %.0fx for %d seconds.", Config.StreakForOverdrive, Config.OverdriveMultiplier, Config.OverdriveSeconds) },
				{ head = "PURGE", body = string.format("Purge above %d for %.2f Aether per point of heat. Past %d the core runs lean: every strike pays %.1fx until you purge. Heat never locks the anvil.", Config.VentThreshold, Config.AetherPerHeat, Config.PenaltyFrom, Config.PenaltyMult) },
			},
			facts = {
				{ label = "HEAT PER STRIKE", value = string.format("%.1f", Config.HeatPerClick) },
				{ label = "DECAY PER SECOND", value = string.format("%.1f", Config.HeatDecayPerSec) },
				{ label = "BAND PAYS", value = string.format("%.1fx", Config.SweetSpotMultiplier) },
				{ label = "LEAN POINT", value = string.format("%d%% PAYS %.1fx", Config.PenaltyFrom, Config.PenaltyMult) },
			},
			art = "gauge",
			tip = "The gauge caps at 100 and keeps accepting clicks. Living in the red is a choice you pay for, not a timeout.",
		},
		{
			id = "forge",
			title = "THE CRATE",
			kicker = "SPEND STAR-MATTER, ROLL A COPY",
			accent = Theme.Color.starMatter,
			lead = string.format("The crate rolls one copy from the banner you are on. Price is the banner cost, ramped by rolls taken at that banner, and floored at %d strikes of your own income so it stays visible at every point on the curve.", ForgeConfig.RollIncomeStrikes),
			steps = {
				{ head = "PICK A BANNER", body = "Five banners unlock on lifetime Star-Matter. A higher banner costs more and rolls a stronger pool." },
				{ head = "ROLL", body = string.format("This roll costs %s SM. The next one costs more until the ramp caps at %.0fx the banner price.", NumberUtil.abbreviate(cost), ForgeConfig.RollCostCap) },
				{ head = "PITY", body = "A void or quantum drop is forced within the banner's pity window, so a dry streak cannot run forever." },
			},
			facts = {
				{ label = "BANNER", value = string.upper(tierName) },
				{ label = "ROLL COST", value = string.format("%s SM", NumberUtil.abbreviate(cost)) },
				{ label = "ROLLS TAKEN", value = if state then tostring(state.forgeRolls) else "0" },
				{ label = "INCOME FLOOR", value = string.format("%d STRIKES", ForgeConfig.RollIncomeStrikes) },
			},
			art = "odds",
			tip = "The crate is a roll, not a shop. The blade you get is the blade you get; the vault is where duplicates become value.",
		},
		{
			id = "variants",
			title = "VARIANTS",
			kicker = "THE SAME BLADE, FIVE WAYS",
			accent = Theme.Color.cyan,
			lead = "Every copy rolls a variant. Standard is the baseline, and the four rare finishes multiply the blade and change how it behaves in a run.",
			steps = {
				{ head = "STANDARD", body = "74 of 100 rolls. No bonus, no penalty. The blade as it left the anvil." },
				{ head = "TEMPERED AND OVERCLOCKED", body = "Tempered cools faster; overclocked adds crit chance. Both are common enough to plan around." },
				{ head = "VOID AND PRISMATIC", body = "Four in a hundred rolls. Void doubles shards; prismatic adds a quarter more Aether on every vent." },
			},
			facts = {
				{ label = "VARIANTS", value = tostring(#ForgeConfig.VariantOrder) },
				{ label = "STANDARD ODDS", value = string.format("%.0f%%", ForgeConfig.variant("standard").weight) },
				{ label = "BEST MULT", value = string.format("x%.2f", ForgeConfig.variant("prismatic").mult) },
				{ label = "REROLL", value = string.format("%d+ SCRAP", ForgeConfig.rerollCost(1)) },
			},
			art = "variants",
			tip = "Variants are the second axis of the hunt. Two copies of the same blade are not the same copy.",
		},
		{
			id = "quality",
			title = "QUALITY",
			kicker = "TWENTY-FOUR BANDS, ONE MULTIPLIER",
			accent = Theme.Color.quantum,
			lead = "A copy's quality is derived, not stored. Grade, element and affixes multiply together, and the product lands in one of four steps inside its grade family: -, plain, +, or ++.",
			steps = {
				{ head = "THE AXES", body = string.format("%d elements, %d grades, %d prefixes at %.0f%%, %d suffixes at %.0f%%. Each rolls independently.", #ModifierConfig.ElementOrder, #ModifierConfig.GradeOrder, #ModifierConfig.PrefixOrder, ModifierConfig.PrefixChance * 100, #ModifierConfig.SuffixOrder, ModifierConfig.SuffixChance * 100) },
				{ head = "THE STEP", body = "The step is the within-family score against four thresholds. It names the band; it does not add a second multiplier." },
				{ head = "THE CODEX", body = "Every band you have seen is recorded. Twenty-four cells, from Chipped minus to Transcendent plus plus." },
			},
			facts = {
				{ label = "BANDS", value = tostring(#ModifierConfig.qualityLadder()) },
				{ label = "ELEMENTS", value = tostring(#ModifierConfig.ElementOrder) },
				{ label = "AFFIXES", value = tostring(#ModifierConfig.PrefixOrder + #ModifierConfig.SuffixOrder) },
				{ label = "TOP BAND", value = "MYTHIC++" },
			},
			art = "quality",
			tip = "A quality band cannot be bought or rerolled on its own. It is a reading of the copy, which is why it survives a variant reroll unchanged.",
		},
		{
			id = "vault",
			title = "THE VAULT",
			kicker = "SIXTY SLOTS AND A MELTING POT",
			accent = Theme.Color.gold,
			lead = string.format("The vault holds %d copies. Duplicates melt into Scrap, Scrap buys variant rerolls, and favourites protect the copies you do not want a batch melt to touch.", Config.InventoryMax),
			steps = {
				{ head = "MELT", body = "One copy at a time from the inspector, or arm MELT MULTIPLE and tick a batch. The bar prints the exact count and Scrap before you commit." },
				{ head = "SELECT DUPES", body = "Groups copies by blade, variant, grade, element and both affixes. The last copy of a pattern is never selected." },
				{ head = "EQUIP BEST", body = "Equips the strongest copy by power, not by rarity. A tempered epic can beat a standard mythic." },
			},
			facts = {
				{ label = "COPIES", value = string.format("%d / %d", if state then state.invCount else 0, if state then state.invMax else Config.InventoryMax) },
				{ label = "SCRAP", value = if state then NumberUtil.abbreviate(state.scrap) else "0" },
				{ label = "REROLL COST", value = string.format("%d SCRAP", ForgeConfig.rerollCost(1)) },
				{ label = "EQUIPPED", value = if state and state.equipped ~= "" and BladeRegistry.get(state.equipped) then string.upper(BladeRegistry.get(state.equipped).name) else "NONE" },
			},
			art = "vault",
			tip = "Offered copies are locked while a trade stands. That lock is why the offer then melt scam has nothing to land on.",
		},
		{
			id = "fleet",
			title = "THE FLEET",
			kicker = "INCOME THAT DOES NOT NEED THE ANVIL",
			accent = Theme.Color.aether,
			lead = string.format("Drones pay Star-Matter per second whether you are striking or not. Five rungs, each gated on the total you already own. Offline income is capped at %s and pays at %d%%.", NumberUtil.abbreviateTime(Config.OfflineCapSeconds), math.floor(Config.OfflineEfficiency * 100)),
			steps = {
				{ head = "BUY A RUNG", body = "Each rung has its own Aether price and its own yield. Buying in bulk is cheaper per drone." },
				{ head = "EXPEDITION", body = "Committed drones leave the passive pool and come back with Aether and cores. They do not produce while they are away." },
				{ head = "OFFLINE", body = "The welcome back card pays the fleet's output for the time you were gone, inside the cap." },
			},
			facts = {
				{ label = "DRONES", value = if state then tostring(state.drones) else "0" },
				{ label = "PASSIVE / SEC", value = if state then NumberUtil.abbreviate(state.passiveYield) else "0" },
				{ label = "AETHER", value = if state then NumberUtil.abbreviate(state.as) else "0" },
				{ label = "OFFLINE CAP", value = NumberUtil.abbreviateTime(Config.OfflineCapSeconds) },
			},
			art = "fleet",
			tip = "The fleet is the reason a session can end. Log out with drones running and the next join opens with a payout card.",
		},
		{
			id = "runes",
			title = "RUNES AND TECH",
			kicker = "SMALL BONUSES THAT COMPOUND",
			accent = Theme.Color.emerald,
			lead = "Mastery is earned per blade pattern, not per copy. Ranks unlock sockets; runes drop from hot anomalies and add flat bonuses while socketed.",
			steps = {
				{ head = "MASTERY", body = string.format("%d strikes to rank 1, then %d, %d, %d and %d. The rank survives ascension because it belongs to the pattern.", RuneConfig.Thresholds[1], RuneConfig.Thresholds[2], RuneConfig.Thresholds[3], RuneConfig.Thresholds[4], RuneConfig.Thresholds[5]) },
				{ head = "SOCKETS", body = "Rank 1 opens one socket, rank 3 opens a second, rank 5 opens the third. Each rune is consumed when it goes in." },
				{ head = "TECH", body = "Cores buy permanent nodes. Tech is never wiped by an ascension, so it is the long ladder under the short one." },
			},
			facts = {
				{ label = "RANK", value = if state then tostring(state.mastery) else "0" },
				{ label = "SOCKETS", value = string.format("%d / %d", if state then state.socketSlots else 0, RuneConfig.MaxSockets) },
				{ label = "RUNES", value = tostring(runeTotal) },
				{ label = "TECH NODES", value = tostring(TECH_NODES) },
			},
			art = "runes",
			tip = "Anomalies only drop while the gauge is genuinely hot. Runes are paid for living at the top of the band, not for bouncing off it.",
		},
		{
			id = "ascend",
			title = "ASCENSION",
			kicker = "TRADE THE RUN FOR PERMANENT POWER",
			accent = Theme.Color.quantum,
			lead = string.format("At %s Star-Matter you can ascend. Cores are the square root of your Star-Matter over the threshold, and they buy tech that never resets.", NumberUtil.abbreviate(Config.AscendThreshold)),
			steps = {
				{ head = "BANK", body = "Ascend when the next run will be faster than this one. Cores scale with the square root, so waiting past the threshold still pays." },
				{ head = "RESET", body = "Star-Matter, Aether, drones and forged blades are wiped. Blades are the run; the codex remembers them." },
				{ head = "KEEP", body = "Tech, codex, mastery, cores and every discovery survive. The next run starts with the same anvil and a better ladder." },
			},
			facts = {
				{ label = "THRESHOLD", value = NumberUtil.abbreviate(Config.AscendThreshold) },
				{ label = "CORES NOW", value = if state then NumberUtil.abbreviate(math.floor((state.sm / Config.AscendThreshold) ^ Config.AscendExponent)) else "0" },
				{ label = "ASCENSIONS", value = if state then tostring(state.ascensions) else "0" },
				{ label = "CORES", value = if state then NumberUtil.abbreviate(state.qc) else "0" },
			},
			art = "ascend",
			tip = "The first ascension is the largest relative jump. Later ones are about tech breadth, not about the number going up.",
		},
		{
			id = "trade",
			title = "TRADING",
			kicker = "TWO PLAYERS, ONE ATOMIC SWAP",
			accent = Theme.Color.emerald,
			lead = "Trading is a request, an offer and two accepts. Nothing moves until both keys are pressed, and any change to either side clears both.",
			steps = {
				{ head = "ASK", body = "Pick a forger on the trade desk and press ASK. They get a popup; the session opens only if they accept." },
				{ head = "OFFER", body = "Tick up to eight copies and set a shard amount. Their screen updates as you build. Offered copies are locked from melting." },
				{ head = "ACCEPT", body = "Both sides press ACCEPT. The swap is one server tick: remove both sides, mint both sides, transfer shards." },
			},
			facts = {
				{ label = "BLADES PER SIDE", value = "8" },
				{ label = "REQUEST EXPIRY", value = "20 SECONDS" },
				{ label = "SESSION EXPIRY", value = "240 SECONDS" },
				{ label = "PRIVACY", value = "SETTINGS > ALLOW TRADE REQUESTS" },
			},
			art = "trade",
			tip = "The equipped copy and favourites are never offerable. If a copy is missing from the picker, that is why.",
		},
	}
end

-- ---------------------------------------------------------------------------
-- Paint
-- ---------------------------------------------------------------------------

local function paintRail()
	local area = rail
	if area == nil then
		return
	end
	ModalShell.clear(area)
	for index, entry in pages() do
		local active = index == activeIndex
		local button = UiKit.button(area, {
			text = "",
			fill = if active then entry.accent else Theme.Color.panelSunken,
			stroke = if active then Theme.Color.outline else Theme.Color.strokeFaint,
			height = PAGE_BUTTON_H,
			radius = Theme.Radius.sm,
			handler = function()
				if activeIndex == index then
					return
				end
				activeIndex = index
				Sfx.tab()
				HandbookView.refresh()
			end,
		})
		button.Name = string.format("HandbookPage_%s", entry.id)
		button.Size = UDim2.new(1, 0, 0, PAGE_BUTTON_H)
		button.LayoutOrder = index

		local number = UiKit.label(button, {
			text = string.format("%02d", index),
			size = Theme.Text.Tiny,
			font = Theme.Font.Numeric,
			color = if active then Theme.Color.ink else entry.accent,
		})
		number.Position = UDim2.fromOffset(10, 0)
		number.Size = UDim2.fromOffset(28, PAGE_BUTTON_H)
		number.ZIndex = 3

		local title = UiKit.label(button, {
			text = entry.title,
			size = Theme.Text.Tiny,
			font = Theme.Font.Black,
			color = if active then Theme.Color.ink else Theme.Color.textDim,
			align = Enum.TextXAlignment.Left,
		})
		title.Position = UDim2.fromOffset(40, 0)
		title.Size = UDim2.new(1, -48, 0, PAGE_BUTTON_H)
		title.TextTruncate = Enum.TextTruncate.AtEnd
		title.ZIndex = 3
	end
end

local function paintHero(panel: Frame, page: Page, index: number, total: number)
	local band = UiKit.create("Frame", {
		Name = "Hero",
		BackgroundColor3 = Theme.Color.panelSunken,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(CONTENT_W, 108),
		ZIndex = 2,
	}) :: Frame
	UiKit.corner(band, Theme.Radius.card)
	UiKit.stroke(band, Theme.Color.outline, Theme.Stroke.thick, 0)
	UiKit.gradient(band, { Theme.Color.panelRaised, Theme.Color.panel }, 90)
	band.Parent = panel

	local art = AssetManifest.lihfolkArt("band")
	if art ~= "" then
		local tile = UiKit.create("ImageLabel", {
			Name = "BandArt",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = art,
			ImageTransparency = 0.5,
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromOffset(180, 180),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 3,
		}) :: ImageLabel
		UiKit.corner(tile, Theme.Radius.card)
		tile.Parent = band
	end

	-- Left-to-right darkening so the title always reads, whatever the texture
	-- underneath is doing at that pixel.
	local scrim = UiKit.create("Frame", {
		Name = "Scrim",
		BackgroundColor3 = Theme.Color.ink,
		BorderSizePixel = 0,
		BackgroundTransparency = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
	}) :: Frame
	UiKit.corner(scrim, Theme.Radius.card)
	local gradient = UiKit.create("UIGradient", {
		Rotation = 0,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.22),
			NumberSequenceKeypoint.new(0.62, 0.5),
			NumberSequenceKeypoint.new(1, 0.85),
		}),
	}) :: UIGradient
	gradient.Parent = scrim
	scrim.Parent = band

	local kicker = text(band, page.kicker, 22, 16, CONTENT_W - 200, 18, Theme.Text.Tiny, page.accent, Theme.Font.Black)
	kicker.ZIndex = 6
	local title = text(band, page.title, 20, 34, CONTENT_W - 200, 44, 32, Theme.Color.text, Theme.Font.Black)
	title.ZIndex = 6
	title.TextStrokeTransparency = 0
	local pageNumber = text(band, string.format("PAGE %02d OF %02d", index, total), CONTENT_W - 190, 66, 168, 22, Theme.Text.Tiny, Theme.Color.textDim, Theme.Font.Numeric, Enum.TextXAlignment.Right)
	pageNumber.ZIndex = 6

	local rule = block(band, 22, 88, 86, 4, page.accent, 2)
	rule.ZIndex = 6
end

local function paintContent(panel: Frame, page: Page)
	local left = UiKit.create("Frame", {
		Name = "PageText",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 122),
		Size = UDim2.fromOffset(LEFT_W, 446),
		ZIndex = 3,
	}) :: Frame
	left.Parent = panel

	local lead = UiKit.label(left, {
		text = page.lead,
		size = Theme.Text.Small,
		font = Theme.Font.Body,
		color = Theme.Color.textSecondary,
		wrap = true,
	})
	lead.Name = "Lead"
	lead.Position = UDim2.fromOffset(0, 0)
	lead.Size = UDim2.fromOffset(LEFT_W, 76)
	lead.ZIndex = 4

	text(left, "HOW IT WORKS", 0, 88, LEFT_W, 18, Theme.Text.Tiny, page.accent, Theme.Font.Black)

	for index, step in page.steps do
		local y = 110 + (index - 1) * 72
		local dot = block(left, 0, y + 2, 24, 24, Theme.Color.panelSunken, 12)
		UiKit.stroke(dot, page.accent, 2, 0)
		text(dot, tostring(index), 0, 0, 24, 24, Theme.Text.Tiny, page.accent, Theme.Font.Black, Enum.TextXAlignment.Center)
		text(left, step.head, 34, y, LEFT_W - 34, 20, Theme.Text.Tiny, Theme.Color.text, Theme.Font.Black)
		local body = text(left, step.body, 34, y + 20, LEFT_W - 34, 46, Theme.Text.Tiny, Theme.Color.textSecondary, Theme.Font.Body)
		body.TextWrapped = true
	end

	text(left, "NUMBERS", 0, 334, LEFT_W, 18, Theme.Text.Tiny, page.accent, Theme.Font.Black)
	for index, fact in page.facts do
		local column = (index - 1) % 2
		local row = math.floor((index - 1) / 2)
		local card = UiKit.panel(left, {
			tier = "well",
			radius = Theme.Radius.sm,
			stroke = Theme.Color.strokeFaint,
			bevel = false,
			lip = false,
		})
		card.Name = string.format("Fact_%d", index)
		card.Position = UDim2.fromOffset(column * 254, 356 + row * 46)
		card.Size = UDim2.fromOffset(242, 40)

		text(card, fact.label, 10, 2, 222, 16, Theme.Text.Tiny, Theme.Color.textFaint, Theme.Font.Label)
		local value = text(card, fact.value, 10, 17, 222, 20, Theme.Text.Tiny, Theme.Color.text, Theme.Font.Numeric)
		value.TextTruncate = Enum.TextTruncate.AtEnd
	end

	local artPanel = UiKit.panel(panel, {
		tier = "well",
		radius = Theme.Radius.card,
		stroke = Theme.Color.strokeFaint,
		bevel = false,
		lip = false,
	})
	artPanel.Name = "PageArt"
	artPanel.Position = UDim2.fromOffset(ART_X, 122)
	artPanel.Size = UDim2.fromOffset(ART_W, 372)
	UiKit.gradient(artPanel, { Theme.Color.panelSunken, Theme.Color.panel }, 90)

	cleanup = nil
	local painter = ART[page.art]
	if painter then
		painter(artPanel, page.accent)
	end

	local tip = UiKit.panel(panel, {
		tier = "item",
		radius = Theme.Radius.sm,
		stroke = Theme.Color.strokeFaint,
		bevel = false,
		lip = false,
	})
	tip.Name = "PageTip"
	tip.Position = UDim2.fromOffset(ART_X, 508)
	tip.Size = UDim2.fromOffset(ART_W, 60)

	local bar = block(tip, 0, 0, 5, 60, page.accent, 2)
	bar.ZIndex = 3
	local tipText = text(tip, page.tip, 18, 6, ART_W - 30, 48, Theme.Text.Tiny, Theme.Color.textSecondary, Theme.Font.Body)
	tipText.TextWrapped = true
end

local function paintNav(panel: Frame, index: number, total: number, page: Page)
	local nav = UiKit.create("Frame", {
		Name = "PageNav",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 588),
		Size = UDim2.fromOffset(CONTENT_W, 46),
		ZIndex = 3,
	}) :: Frame
	nav.Parent = panel

	local previous = UiKit.button(nav, {
		text = "< PREV",
		fill = Theme.Color.slate,
		stroke = Theme.Color.stroke,
		height = 40,
		radius = Theme.Radius.sm,
		size = Theme.Text.Small,
		font = Theme.Font.Black,
		textColor = if index > 1 then Theme.Color.text else Theme.Color.locked,
		handler = function()
			if index <= 1 then
				return
			end
			activeIndex = index - 1
			Sfx.tab()
			HandbookView.refresh()
		end,
	})
	previous.Name = "HandbookPrev"
	previous.Position = UDim2.fromOffset(0, 3)
	previous.Size = UDim2.fromOffset(130, 40)

	local next = UiKit.button(nav, {
		text = "NEXT >",
		fill = if index < total then page.accent else Theme.Color.slate,
		stroke = if index < total then Theme.Color.outline else Theme.Color.stroke,
		height = 40,
		radius = Theme.Radius.sm,
		size = Theme.Text.Small,
		font = Theme.Font.Black,
		-- White face on the accent plate. Dark type on a bright fill was tried
		-- on the reference and it goes to mud at small scale: the label carries
		-- a hard near-black stroke, and a near-black glyph inside it is a bar.
		textColor = if index < total then Theme.Color.text else Theme.Color.locked,
		handler = function()
			if index >= total then
				return
			end
			activeIndex = index + 1
			Sfx.tab()
			HandbookView.refresh()
		end,
	})
	next.Name = "HandbookNext"
	next.AnchorPoint = Vector2.new(1, 0)
	next.Position = UDim2.new(1, 0, 0, 3)
	next.Size = UDim2.fromOffset(130, 40)

	local label = UiKit.label(nav, {
		text = string.format("%s   %d / %d", string.upper(page.title), index, total),
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = page.accent,
		align = Enum.TextXAlignment.Center,
	})
	label.Name = "HandbookPageLabel"
	label.Position = UDim2.fromOffset(140, 3)
	label.Size = UDim2.fromOffset(CONTENT_W - 280, 40)
	label.ZIndex = 4
end

function HandbookView.refresh()
	local handle = shell
	if handle == nil then
		return
	end
	if cleanup then
		cleanup()
		cleanup = nil
	end

	local list = pages()
	activeIndex = math.clamp(activeIndex, 1, #list)
	local page = list[activeIndex]
	local area = content
	if area == nil then
		return
	end
	ModalShell.clear(area)
	paintHero(area, page, activeIndex, #list)
	paintContent(area, page)
	paintNav(area, activeIndex, #list, page)
	local bar = rail
	if bar then
		paintRail()
	end
	if handle.setSubtitle then
		handle.setSubtitle(string.format("PAGE %d OF %d", activeIndex, #list))
	end
end

function HandbookView.open()
	local handle = shell
	if handle == nil then
		return
	end
	if handle.isOpen() then
		return
	end
	handle.open()
	HandbookView.refresh()
end

function HandbookView.openAt(id: string): boolean
	for index, page in pages() do
		if page.id == id then
			activeIndex = index
			HandbookView.open()
			return true
		end
	end
	return false
end

function HandbookView.close()
	if shell then
		shell.close()
	end
end

function HandbookView.isOpen(): boolean
	return shell ~= nil and shell.isOpen()
end

function HandbookView.page(): string
	local page = pages()[activeIndex]
	return if page then page.id else ""
end

function HandbookView.setPage(id: string): boolean
	for index, page in pages() do
		if page.id == id then
			activeIndex = index
			if shell and shell.isOpen() then
				HandbookView.refresh()
			end
			return true
		end
	end
	return false
end

function HandbookView.init(canvas: Frame)
	if shell then
		return
	end

	local handle = ModalShell.build(canvas, {
		name = "HandbookOverlay",
		title = "FORGE HANDBOOK",
		subtitle = "EVERY RULE, EVERY NUMBER",
		accent = Theme.Color.gold,
		width = PANEL_W,
		height = PANEL_H,
	}, 32)
	shell = handle

	local railArea = UiKit.scroll(handle.body)
	railArea.Name = "HandbookRail"
	railArea.Position = UDim2.fromOffset(16, 12)
	railArea.Size = UDim2.fromOffset(RAIL_W, 600)
	UiKit.vlist(railArea, { gap = 6 })
	rail = railArea

	local credit = UiKit.label(handle.body, {
		text = "SKY + METAL: LIHFOLK",
		size = Theme.Text.Tiny,
		font = Theme.Font.Label,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Left,
	})
	credit.Name = "HandbookCredit"
	credit.Position = UDim2.fromOffset(18, 616)
	credit.Size = UDim2.fromOffset(RAIL_W, 16)

	local divider = UiKit.create("Frame", {
		Name = "Divider",
		BackgroundColor3 = Theme.Color.stroke,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(256, 12),
		Size = UDim2.fromOffset(2, 618),
	}) :: Frame
	divider.Parent = handle.body

	local area = UiKit.create("Frame", {
		Name = "HandbookContent",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(CONTENT_X, 12),
		Size = UDim2.fromOffset(CONTENT_W, 634),
	}) :: Frame
	area.Parent = handle.body
	content = area
end

function HandbookView.destroy()
	if cleanup then
		cleanup()
		cleanup = nil
	end
	if shell then
		shell.destroy()
		shell = nil
	end
	rail = nil
	content = nil
end

return HandbookView
