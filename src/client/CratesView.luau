--!strict
-- The roll page: a full-width section, not a modal.
--
-- Why a page. The forge tab is the anvil: a blade in a viewport, a heat gauge, a
-- strike key. A crate roll is a different decision and it was buried in the same
-- card, which meant the only thing a player could do with a pool was press the
-- one button under it. Five crates and a ten-pull need a page where the odds and
-- the price sit side by side and the pool is a choice.
--
-- Why it is a section and not an overlay: rolling is a loop the player returns to
-- every few minutes, and a modal that has to be opened and closed around every
-- pull is a tax on the loop. It lives at `Sections` key "crates", the same way
-- the fleet and the tech tree do, and it keeps its own crate model on screen.
--
-- The page owns the whole reveal. The crate drops, rattles, cracks and hands its
-- answer to a lit stage; the copy lands as a blade on that same stage. The forge
-- still owns the three-second celebration for a blade equipped there. This one
-- is a purchase, so it gets its own ceremony.
--
-- The ceremony is a ladder, not a single flash:
--
--   1. the crate falls and the stage charge bar starts
--   2. six beats, each one faster, brighter and a half-step heavier
--   3. a held beat at full charge, where the answer is already known
--   4. the crack, the screen wash, the fanfare, the rays
--   5. the copy, its rarity, its condition and its power on the stage
--
-- A ten-pull adds a ribbon of every copy under the result. The server returns
-- all ten in `results`; the reveal names the best and lets the ribbon prove the
-- other nine happened. That is the difference between "x10" as a caption and
-- ten pulls as an event.
--
-- Pity is drawn as progress toward the guarantee, not as its threshold. The
-- profile counter carries across pools, so the honest read is `PITY 3 / 11`,
-- and the label switches to `GUARANTEE NEXT ROLL` when the next pull is forced.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local NumberUtil = require(Shared:WaitForChild("NumberUtil"))
local ForgeConfig = require(Shared:WaitForChild("ForgeConfig"))
local ModifierConfig = require(Shared:WaitForChild("ModifierConfig"))
local BladeRegistry = require(Shared:WaitForChild("BladeRegistry"))
local Types = require(Shared:WaitForChild("Types"))

local Theme = require(script.Parent.Theme)
local Layout = require(script.Parent.Layout)
local UiKit = require(script.Parent.UiKit)
local StateStore = require(script.Parent.StateStore)
local Sfx = require(script.Parent.Sfx)
local Vfx = require(script.Parent.Vfx)
local CratePreview = require(script.Parent.CratePreview)
local BladePreview = require(script.Parent.BladePreview)
local StageBackdrop = require(script.Parent.StageBackdrop)
local CrateReveal = require(script.Parent.CrateReveal)

local CratesView = {}

-- ---------------------------------------------------------------------------
-- Geometry
-- ---------------------------------------------------------------------------

local PAD = 18
local HEADER_H = 64
local RAIL_W = 300
local ROW_H = 76
local ROW_GAP = 6

--- The stage. The crate zone is fixed so the 3D framing never depends on the
--- window; the info column beside it is the elastic half.
local HERO_H = 300
local OBJECT_W = 400
local INFO_X = 412
local VIEW = 300

local ODDS_Y = HERO_H + 10
local ODDS_H = 96
local KEYS_Y = ODDS_Y + ODDS_H + 12
local KEY_H = 64
local NOTE_Y = KEYS_Y + KEY_H + 7
local DECK_X = RAIL_W + 18

--- Rarity colours, mirroring `BladeRegistry.RARITY_INFO`. Kept here because the
--- page draws the odds legend before it has a blade to ask. Quantum is mint, not
--- gold: the star-matter currency is gold, and using it for a blade rarity made
--- the same word mean two colours on two screens.
local RARITY_COLOR: { [string]: Color3 } = {
	Scrap = Color3.fromRGB(168, 130, 96),
	Forged = Color3.fromRGB(176, 188, 202),
	Astral = Color3.fromRGB(122, 226, 255),
	Void = Color3.fromRGB(198, 132, 255),
	Quantum = Color3.fromRGB(132, 255, 208),
}

local RARITY_RANK: { [string]: number } = {
	Scrap = 1,
	Forged = 2,
	Astral = 3,
	Void = 4,
	Quantum = 5,
}

local VARIANT_RANK: { [string]: number } = {
	standard = 1,
	tempered = 2,
	overclocked = 3,
	void = 4,
	prismatic = 5,
}

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local root: Frame? = nil
local deck: Frame? = nil
local railPlate: Frame? = nil
local hero: Frame? = nil

local railRows: { [string]: TextButton } = {}
local railPrices: { [string]: TextLabel } = {}
local railTracks: { [string]: Frame } = {}
local railFills: { [string]: Frame } = {}
local selected = "standard"
--- True while the player is inspecting a pool the run has not opened. The pick
--- is local only, so the sync loop must not follow the server back.
local browsingLocked = false

--- Set by `Main`. The roll page does not require `ForgeView`: the anvil card and
--- the pool page are siblings, and the seam between them is this callback.
CratesView.onSelect = nil :: ((id: string) -> ())?

local viewport: ViewportFrame? = nil
local viewportScale: UIScale? = nil
local crateHandle: CratePreview.Handle? = nil
local mountedShape: string? = nil
local stageTint: StageBackdrop.Handle? = nil

-- Stage furniture
local stageFlash: Frame? = nil
local rarityTag: TextLabel? = nil
local rayHost: Frame? = nil
local rays: { Frame } = {}
local beam: Frame? = nil
local daisGlow: Frame? = nil
local daisLine: Frame? = nil
local chargeBar: Frame? = nil
local chargeCaption: TextLabel? = nil

-- Rest column
local restGroup: Frame? = nil
local restEyebrow: TextLabel? = nil
local restTitle: TextLabel? = nil
local restBlurb: TextLabel? = nil
local restPityValue: TextLabel? = nil
local restPityHint: TextLabel? = nil
local pityHost: Frame? = nil
local pityTicks: { Frame } = {}
local unlockBar: Frame? = nil
local unlockFill: Frame? = nil
local restRareValue: TextLabel? = nil
local restMark: TextLabel? = nil

-- Result column
local resultGroup: Frame? = nil
local resultKicker: TextLabel? = nil
local resultNew: TextLabel? = nil
local resultVariant: TextLabel? = nil
local resultName: TextLabel? = nil
local resultCondition: TextLabel? = nil
local resultPowerKey: TextLabel? = nil
local resultPowerValue: TextLabel? = nil
local resultEquipped: TextLabel? = nil
local resultAffix: TextLabel? = nil
local resultPity: TextLabel? = nil
local resultBackLabel: TextLabel? = nil

-- Batch ribbon
local ribbon: Frame? = nil
local ribbonCells: { Frame } = {}

-- Odds strip
local oddsHost: Frame? = nil
local oddsCrateId: string? = nil
local oddsWidth = 0

-- Keys
local rollOne: TextButton? = nil
local rollOneFace: TextLabel? = nil
local rollOneCost: TextLabel? = nil
local rollThree: TextButton? = nil
local rollThreeFace: TextLabel? = nil
local rollThreeCost: TextLabel? = nil
local rollTen: TextButton? = nil
local rollTenFace: TextLabel? = nil
local rollTenCost: TextLabel? = nil
local noteLabel: TextLabel? = nil

local rolling = false
local rollToken = 0
local awaitingReveal = false
--- True once the rattle has finished and the reveal may fire.
local crateOpen = false
local revealReadyAt = 0
local pendingResult: Types.FeedEvent? = nil
local showingResult = false

local unsubscribeEvent: (() -> ())? = nil

-- ---------------------------------------------------------------------------
-- Data
-- ---------------------------------------------------------------------------

local function selectedCrate(): ForgeConfig.Tier
	return ForgeConfig.crate(selected) or ForgeConfig.Tiers[1]
end

local function quote(id: string): Types.CrateQuote?
	local state = StateStore.current
	if state == nil then
		return nil
	end
	return state.forgeCosts[id]
end

--- The profile counter is shared by every pool. A crate with a smaller goal can
--- be entered with the counter already past it, so the display clamps.
local function pityProgress(crate: ForgeConfig.Tier): (number, number, number)
	local state = StateStore.current
	local goal = math.max(1, crate.pity)
	local filled = if state then math.clamp(state.forgePity, 0, goal) else 0
	return filled, goal, math.max(0, goal - filled)
end

--- Odds of the two rarities the guarantee can pay, from the crate's own weights.
--- This is the number the player is actually buying when pity is close.
local function pityChance(crate: ForgeConfig.Tier): number
	local total = 0
	for _, entry in ForgeConfig.odds(crate) do
		if entry.rarity == "Void" or entry.rarity == "Quantum" then
			total += entry.chance
		end
	end
	return total
end

local function variantOf(id: string?): ForgeConfig.Variant
	return ForgeConfig.variant(if id and id ~= "" then id else ForgeConfig.StandardVariant)
end

local function bladeOf(id: string?): BladeRegistry.Blade?
	if id == nil then
		return nil
	end
	return BladeRegistry.get(id)
end

-- ---------------------------------------------------------------------------
-- Small drawing helpers
-- ---------------------------------------------------------------------------

local function plate(parent: Instance, color: Color3, radius: number): Frame
	local frame = UiKit.create("Frame", {
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}) :: Frame
	UiKit.corner(frame, radius)
	frame.Parent = parent
	return frame
end

--- Width of the deck (the right-hand column) in design pixels.
---
--- Computed from `Layout` rather than read back from the frame: at build time the
--- card has never been laid out, so `AbsoluteSize` is zero and the keys would be
--- born at their fallback width until the first resize.
local function deckWidth(): number
	return Layout.CONTENT_W - 36 - DECK_X
end

local function infoWidth(): number
	return math.max(300, deckWidth() - INFO_X - 20)
end

local function ribbonWidth(): number
	return math.max(320, deckWidth() - 24)
end

--- A 2D silhouette per crate family for the rail. The hero is a real 3D model;
--- five more viewports in the rail would be five worlds on a page that already
--- runs one, and the rail only has to be legible at 40px.
local function glyph(parent: Instance, style: string, accent: Color3, size: number)
	local host = UiKit.create("Frame", {
		Name = "Glyph",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
	}) :: Frame
	host.Parent = parent

	local body = plate(host, Theme.Color.panelSunken, math.floor(size * 0.22))
	body.Size = UDim2.fromScale(1, 1)

	local function piece(color: Color3, x: number, y: number, w: number, h: number, radius: number)
		local frame = plate(host, color, radius)
		frame.Position = UDim2.fromScale(x, y)
		frame.Size = UDim2.fromScale(w, h)
		frame.ZIndex = 3
		return frame
	end

	if style == "capsule" then
		piece(Theme.Color.slate, 0.34, 0.08, 0.32, 0.84, 999)
		piece(accent, 0.44, 0.16, 0.12, 0.68, 999)
	elseif style == "relic" then
		piece(Theme.Color.slate, 0.36, 0.62, 0.28, 0.26, 3)
		piece(Theme.Color.slate, 0.41, 0.3, 0.18, 0.34, 3)
		piece(accent, 0.455, 0.16, 0.09, 0.14, 2)
	elseif style == "core" then
		piece(Theme.Color.slate, 0.2, 0.2, 0.6, 0.6, 999)
		piece(accent, 0.34, 0.46, 0.32, 0.08, 999)
	elseif style == "vault" then
		piece(Theme.Color.slate, 0.14, 0.16, 0.72, 0.68, 4)
		piece(Theme.Color.void, 0.34, 0.32, 0.32, 0.34, 999)
		piece(accent, 0.44, 0.42, 0.12, 0.14, 999)
	else
		piece(Theme.Color.slate, 0.16, 0.22, 0.68, 0.56, 4)
		piece(accent, 0.16, 0.38, 0.68, 0.07, 2)
		piece(accent, 0.16, 0.56, 0.68, 0.07, 2)
	end
end

--- A horizontal rule that does not need its own stroke object.
local function rule(parent: Instance, y: number, width: number, color: Color3, transparency: number): Frame
	local line = UiKit.create("Frame", {
		BackgroundColor3 = color,
		BackgroundTransparency = transparency,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.fromOffset(width, 1),
	}) :: Frame
	line.Parent = parent
	return line
end

--- Gradient transparency on a plain frame. `UiKit.gradient` only sets colour;
--- light shafts and floor lines need the alpha ramp.
local function fadeGradient(frame: Frame, stops: { NumberSequenceKeypoint }): UIGradient
	local gradient = UiKit.create("UIGradient", {
		Transparency = NumberSequence.new(stops),
	}) :: UIGradient
	gradient.Parent = frame
	return gradient
end

-- ---------------------------------------------------------------------------
-- Crate model
-- ---------------------------------------------------------------------------

local function unmountCrate()
	if crateHandle then
		crateHandle.destroy()
		crateHandle = nil
	end
	mountedShape = nil
	if viewport then
		viewport:ClearAllChildren()
	end
end

local function mountCrate(shape: string)
	local view = viewport
	if view == nil then
		return
	end
	if mountedShape == shape and crateHandle then
		return
	end
	unmountCrate()
	-- A crate viewport wants a lit stage; a blade thumbnail sets its own lighting
	-- inside `BladePreview.thumbnail`, so both can share one frame.
	view.Ambient = Color3.fromRGB(156, 148, 164)
	view.LightColor = Color3.fromRGB(255, 208, 158)
	view.LightDirection = Vector3.new(-0.5, -0.8, -0.4)
	crateHandle = CratePreview.mount(view, shape, {
		surface = hero,
		spin = 0.12,
	})
	mountedShape = shape
end

-- ---------------------------------------------------------------------------
-- Stage
-- ---------------------------------------------------------------------------

local function restPalette(crate: ForgeConfig.Tier): (Color3, Color3, Color3)
	local theme = Theme.tierBackdrop(crate.tier)
	return crate.accent, theme.cool, crate.accent
end

local function paintDais(color: Color3)
	if daisGlow then
		daisGlow.BackgroundColor3 = color
		daisGlow.BackgroundTransparency = 0.9
	end
	if daisLine then
		daisLine.BackgroundColor3 = color
	end
end

local function paintRestTint(crate: ForgeConfig.Tier)
	if stageTint == nil then
		return
	end
	local warm, cool, accent = restPalette(crate)
	stageTint.setColors(warm, cool, accent)
	paintDais(accent)
	if beam then
		beam.BackgroundColor3 = accent
	end
end

local function paintRays(visible: boolean, tint: Color3, rank: number)
	local host = rayHost
	if host == nil then
		return
	end
	host.Visible = visible
	if not visible then
		return
	end
	local alpha = math.clamp(0.78 - rank * 0.07, 0.34, 0.72)
	for _, ray in rays do
		ray.BackgroundColor3 = tint
		ray.BackgroundTransparency = 1
		UiKit.tween(ray, Theme.Duration.slow, { BackgroundTransparency = alpha }, Enum.EasingStyle.Quad)
	end
	host.Rotation = 0
	-- A slow quarter-degree drift keeps the rays from reading as a decal. It is
	-- a reveal-only element, so a looping rotation here does not compete with a
	-- number the player is trying to read.
	if not Theme.reducedMotion() then
		UiKit.tween(host, 7, { Rotation = 5 }, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	end
end

local function paintBeam(visible: boolean, tint: Color3, rank: number)
	local frame = beam
	if frame == nil then
		return
	end
	frame.Visible = visible
	if not visible then
		return
	end
	frame.BackgroundColor3 = tint
	frame.BackgroundTransparency = math.clamp(0.94 - rank * 0.025, 0.76, 0.94)
end

local function paintTag(text: string, tint: Color3, visible: boolean)
	local tag = rarityTag
	if tag == nil then
		return
	end
	tag.Visible = visible
	tag.Text = text
	tag.TextColor3 = tint
	local stroke = tag:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = tint
		stroke.Transparency = 0.35
	end
	tag.BackgroundTransparency = 0.35
	tag.TextTransparency = 1
	if visible then
		UiKit.tween(tag, Theme.Duration.normal, { TextTransparency = 0, BackgroundTransparency = 0.2 })
	end
end

local function resetStage(crate: ForgeConfig.Tier)
	showingResult = false
	if restGroup then
		restGroup.Visible = true
	end
	if resultGroup then
		resultGroup.Visible = false
	end
	if ribbon then
		ribbon.Visible = false
	end
	if rarityTag then
		rarityTag.Visible = false
	end
	if rayHost then
		rayHost.Visible = false
	end
	if beam then
		beam.Visible = false
	end
	if chargeBar then
		chargeBar.Visible = false
	end
	if chargeCaption then
		chargeCaption.Visible = false
	end
	if stageFlash then
		stageFlash.BackgroundTransparency = 1
	end
	paintRestTint(crate)
end

-- ---------------------------------------------------------------------------
-- Paint
-- ---------------------------------------------------------------------------

local function paintRail()
	local state = StateStore.current
	local runSm = if state then state.runSm else 0
	for _, crate in ForgeConfig.Tiers do
		local row = railRows[crate.id]
		if row then
			local unlocked = quote(crate.id) ~= nil
			local isSelected = crate.id == selected
			local stroke = row:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if isSelected then crate.accent else Theme.Color.strokeFaint
				stroke.Transparency = if isSelected then 0 else 0.35
				stroke.Thickness = if isSelected then 2 else 1
			end

			local name = row:FindFirstChild("Name")
			if name and name:IsA("TextLabel") then
				name.TextColor3 = if unlocked then Theme.Color.text else Theme.Color.locked
			end

			local price = railPrices[crate.id]
			if price then
				if unlocked then
					local q = quote(crate.id)
					price.Text = string.format("%s SM", if q then NumberUtil.abbreviate(q.one) else "--")
					price.TextColor3 = Theme.Color.textSecondary
				else
					local pct = if crate.unlock <= 0 then 1 else math.clamp(runSm / crate.unlock, 0, 1)
					price.Text = string.format("%d%% TO OPEN", math.floor(pct * 100))
					price.TextColor3 = Theme.Color.locked
				end
			end

			local track = railTracks[crate.id]
			local fill = railFills[crate.id]
			if track and fill then
				track.Visible = not unlocked
				if not unlocked and crate.unlock > 0 then
					fill.Size = UDim2.fromScale(math.clamp(runSm / crate.unlock, 0, 1), 1)
					fill.BackgroundColor3 = crate.accent
				end
			end

			row.BackgroundTransparency = if unlocked then 0 else 0.3
		end
	end
end

local function paintPity(crate: ForgeConfig.Tier)
	local host = pityHost
	local bar = unlockBar
	local state = StateStore.current
	local locked = quote(crate.id) == nil
	local filled, goal, remaining = pityProgress(crate)

	if host then
		host.Visible = not locked
	end
	if bar then
		bar.Visible = locked
	end

	if locked then
		local pct = if crate.unlock <= 0 then 1 else math.clamp((if state then state.runSm else 0) / crate.unlock, 0, 1)
		if unlockFill then
			unlockFill.Size = UDim2.fromScale(pct, 1)
			unlockFill.BackgroundColor3 = crate.accent
		end
		if restPityValue then
			restPityValue.Text = string.format("OPEN AT %s", NumberUtil.abbreviate(crate.unlock))
			restPityValue.TextColor3 = Theme.Color.textFaint
		end
		if restPityHint then
			restPityHint.Text = string.format("%d%% THIS RUN", math.floor(pct * 100))
			restPityHint.TextColor3 = Theme.Color.textFaint
		end
		return
	end

	if restPityValue then
		restPityValue.Text = string.format("PITY  %d / %d", filled, goal)
		restPityValue.TextColor3 = if remaining <= 1 then Theme.Color.gold else Theme.Color.textFaint
	end
	if restPityHint then
		restPityHint.Text = if remaining <= 1
			then "GUARANTEE NEXT ROLL"
			else string.format("GUARANTEE IN %d", remaining)
		restPityHint.TextColor3 = if remaining <= 1 then Theme.Color.gold else Theme.Color.textSecondary
	end

	local width = infoWidth()
	if host then
		host.Size = UDim2.fromOffset(width, 14)
	end
	if bar then
		bar.Size = UDim2.fromOffset(width, 8)
	end
	local gap = 3
	local tickW = math.max(4, math.floor((width - gap * (goal - 1)) / goal))
	for index = 1, #pityTicks do
		local tick = pityTicks[index]
		tick.Visible = index <= goal
		if index <= goal then
			local last = index == goal
			tick.Position = UDim2.fromOffset((index - 1) * (tickW + gap), if last then 0 else 6)
			tick.Size = UDim2.fromOffset(tickW, if last then 14 else 8)
			if index <= filled then
				tick.BackgroundColor3 = if last then Theme.Color.gold else crate.accent
				tick.BackgroundTransparency = 0
			elseif index == filled + 1 then
				tick.BackgroundColor3 = if remaining <= 1 then Theme.Color.gold else Theme.Color.text
				tick.BackgroundTransparency = 0.25
			elseif last then
				tick.BackgroundColor3 = Theme.Color.gold
				tick.BackgroundTransparency = 0.55
			else
				tick.BackgroundColor3 = Theme.Color.strokeBright
				tick.BackgroundTransparency = 0.55
			end
		end
	end
end

local function paintRest(crate: ForgeConfig.Tier)
	local state = StateStore.current
	if restEyebrow then
		restEyebrow.Text = string.format("POOL %02d / %02d", crate.tier, #ForgeConfig.Tiers)
		restEyebrow.TextColor3 = crate.accent
	end
	if restTitle then
		restTitle.Text = string.upper(crate.name)
	end
	if restBlurb then
		restBlurb.Text = crate.blurb
	end
	if restRareValue then
		restRareValue.Text = string.format("%.2f%%", pityChance(crate) * 100)
	end
	if restMark then
		restMark.Text = string.format("%02d", crate.tier)
		restMark.TextColor3 = crate.accent
	end
	if state == nil and restBlurb then
		-- Pre-sync the page still shows the pool; the note line carries the wait.
		restBlurb.Text = "Linking the vault."
	end
end

local function paintOdds(crate: ForgeConfig.Tier)
	local host = oddsHost
	if host == nil then
		return
	end

	local width = deckWidth()
	if oddsCrateId == crate.id and oddsWidth == width then
		return
	end
	oddsCrateId = crate.id
	oddsWidth = width

	for _, child in host:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local entries = ForgeConfig.odds(crate)

	local eye = UiKit.label(host, {
		text = "DROP ODDS",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.textFaint,
	})
	eye.Size = UDim2.fromOffset(200, 14)

	-- One stacked bar, not five cards. Five equal cards said every outcome was
	-- equally likely; a single bar makes the 0.35% sliver look like what it is.
	-- Drawn common to rare, so the legend under it reads in the same order.
	local barY = 20
	local barH = 22
	local cursor = 0
	local voidX: number? = nil
	for index = #entries, 1, -1 do
		local entry = entries[index]
		local color = RARITY_COLOR[entry.rarity] or Theme.Color.text
		local px = math.max(2, math.floor(width * entry.chance))
		if entry.rarity == "Void" then
			voidX = cursor
		end
		local seg = plate(host, color, 1)
		seg.Name = "Seg_" .. entry.rarity
		seg.Position = UDim2.fromOffset(cursor, barY)
		seg.Size = UDim2.fromOffset(math.max(1, px - 1), barH)
		seg.ZIndex = 2
		cursor += px
	end

	local frame = UiKit.create("Frame", {
		Name = "OddsFrame",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, barY),
		Size = UDim2.fromOffset(width, barH),
	}) :: Frame
	frame.ZIndex = 3
	UiKit.stroke(frame, Theme.Color.stroke, Theme.Stroke.hair, 0.2)
	frame.Parent = host

	-- The guarantee is the only bracket on the odds bar. It spans the two
	-- rarities pity can pay, so the player can see what a forced roll excludes.
	if voidX then
		local bracket = UiKit.create("Frame", {
			BackgroundColor3 = RARITY_COLOR.Void,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(voidX, barY + barH + 3),
			Size = UDim2.fromOffset(math.max(2, width - voidX), 1),
			ZIndex = 3,
		}) :: Frame
		bracket.Parent = host
	end

	-- Legend: colour, name, chance. Five even columns under the bar.
	local columns = #entries
	local gap = 10
	local colW = math.floor((width - gap * (columns - 1)) / columns)
	for slot = 1, columns do
		local entry = entries[columns - slot + 1]
		local color = RARITY_COLOR[entry.rarity] or Theme.Color.text
		local x = (slot - 1) * (colW + gap)

		local dot = plate(host, color, 1)
		dot.Position = UDim2.fromOffset(x, 53)
		dot.Size = UDim2.fromOffset(8, 8)
		dot.ZIndex = 3

		local name = UiKit.label(host, {
			text = string.upper(entry.rarity),
			size = Theme.Text.Tiny,
			font = Theme.Font.Black,
			color = if entry.rarity == "Void" or entry.rarity == "Quantum" then color else Theme.Color.textDim,
		})
		name.Position = UDim2.fromOffset(x + 14, 47)
		name.Size = UDim2.fromOffset(colW - 14, 14)

		local chance = UiKit.label(host, {
			text = string.format("%.2f%%", entry.chance * 100),
			size = Theme.Text.Tiny,
			font = Theme.Font.Numeric,
			color = Theme.Color.text,
		})
		chance.Position = UDim2.fromOffset(x + 14, 63)
		chance.Size = UDim2.fromOffset(colW - 14, 14)
	end
end

local function paintKey(
	button: TextButton?,
	face: TextLabel?,
	cost: TextLabel?,
	ready: boolean,
	locked: boolean,
	label: string,
	price: number?,
	fill: Color3,
	ink: Color3
)
	if button == nil then
		return
	end
	local activeFill = if ready then fill else Theme.Color.slate
	button.BackgroundColor3 = activeFill
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = if ready then Theme.Color.outline else Theme.Color.stroke
	end
	if face then
		face.Text = if locked then "LOCKED" else label
		face.TextColor3 = if ready then ink else Theme.Color.locked
		face.TextTransparency = if ready then 0 else 0.25
	end
	if cost then
		cost.Text = if price then string.format("%s SM", NumberUtil.abbreviate(price)) else "--"
		cost.TextColor3 = if ready then ink else Theme.Color.locked
		cost.TextTransparency = if ready then 0 else 0.3
	end
end

local function paintNote(q: Types.CrateQuote?)
	local label = noteLabel
	if label == nil or rolling then
		return
	end
	local state = StateStore.current
	if q == nil then
		-- The rail carries the percentage and the stage carries the open price.
		label.Text = ""
		return
	end
	if state == nil then
		label.Text = "Linking the vault."
		label.TextColor3 = Theme.Color.textFaint
		return
	end
	if state.invCount >= state.invMax then
		label.Text = string.format("Vault full: %d / %d. Melt a copy to make room.", state.invCount, state.invMax)
		label.TextColor3 = Theme.Color.warn
		return
	end
	if state.sm < q.one then
		label.Text = string.format("Needs %s more Star-Matter for a single roll.", NumberUtil.abbreviate(q.one - state.sm))
		label.TextColor3 = Theme.Color.warn
		return
	end
	-- Nothing important to say. The stage already prints pity, guarantee and
	-- odds; repeating them here was the third copy of the same rule.
	label.Text = ""
end

local function paintResultPity(crate: ForgeConfig.Tier)
	if resultPity == nil then
		return
	end
	local filled, goal, remaining = pityProgress(crate)
	resultPity.Text = if remaining <= 1
		then string.format("PITY %d / %d  ·  GUARANTEE NEXT ROLL", filled, goal)
		else string.format("PITY %d / %d  ·  GUARANTEE IN %d", filled, goal, remaining)
	resultPity.TextColor3 = if remaining <= 1 then Theme.Color.gold else Theme.Color.textFaint
end

local function paintDeck()
	local crate = selectedCrate()
	local q = quote(crate.id)
	local state = StateStore.current

	if not showingResult then
		paintRest(crate)
	else
		paintResultPity(crate)
	end
	paintPity(crate)
	paintRail()
	paintOdds(crate)

	local locked = q == nil
	local canOne = q ~= nil and state ~= nil and state.sm >= q.one
	local canThree = q ~= nil and state ~= nil and state.sm >= q.three
	local canTen = q ~= nil and state ~= nil and state.sm >= q.ten

	if rollOne and rollOneFace and rollOneCost then
		paintKey(rollOne, rollOneFace, rollOneCost, canOne, locked, "ROLL", if q then q.one else nil, Theme.Color.panelRaised, Theme.Color.text)
	end
	if rollThree and rollThreeFace and rollThreeCost then
		paintKey(rollThree, rollThreeFace, rollThreeCost, canThree, locked, "ROLL x3", if q then q.three else nil, Theme.Color.panelRaised, Theme.Color.text)
	end
	if rollTen and rollTenFace and rollTenCost then
		paintKey(rollTen, rollTenFace, rollTenCost, canTen, locked, "ROLL x10", if q then q.ten else nil, crate.accent, Theme.onColor(crate.accent))
	end

	paintNote(q)
end

-- ---------------------------------------------------------------------------
-- Roll
-- ---------------------------------------------------------------------------

local function showRest(crate: ForgeConfig.Tier)
	showingResult = false
	if restGroup then
		restGroup.Visible = true
	end
	if resultGroup then
		resultGroup.Visible = false
	end
	if ribbon then
		ribbon.Visible = false
	end
	paintRest(crate)
end

local function showResult(result: Types.FeedEvent, blade: BladeRegistry.Blade?, variant: ForgeConfig.Variant, rank: number)
	showingResult = true
	if restGroup then
		restGroup.Visible = false
	end
	if resultGroup then
		resultGroup.Visible = true
	end

	local batch = math.max(1, math.floor(result.batch or 1))
	local rarityColor = RARITY_COLOR[blade and blade.rarity or "Scrap"] or variant.color

	if resultKicker then
		resultKicker.Text = if batch > 1 then string.format("BEST OF %d", batch) else "JUST FORGED"
		resultKicker.TextColor3 = if batch > 1 then Theme.Color.gold else Theme.Color.textFaint
	end
	if resultNew then
		local text = if result.newBlade == true
			then "NEW BLADE"
			elseif result.newVariant == true then "NEW VARIANT" else ""
		resultNew.Text = text
		resultNew.Visible = text ~= ""
		resultNew.TextColor3 = Theme.Color.gold
	end
	if resultVariant then
		resultVariant.Text = string.format(
			'<font color="#%s">%s</font>   ·   <font color="#%s">%s</font>',
			variant.color:ToHex(),
			string.upper(variant.name),
			rarityColor:ToHex(),
			string.upper(blade and blade.rarity or "Scrap")
		)
	end
	local nameSize = Theme.Text.Title
	if resultName then
		local display = if blade
			then ModifierConfig.displayName(blade.name, result.prefix or "", result.suffix or "")
			else "A COPY"
		resultName.Text = string.upper(display)
		resultName.TextColor3 = Theme.Color.text
		-- A 30px title fits one line; a modifier-heavy name does not. Drop the
		-- long ones to the heading rung so two lines still clear the condition.
		nameSize = if #display > 24 then Theme.Text.Heading else Theme.Text.Title
	end
	if resultCondition then
		resultCondition.Text = ModifierConfig.condition(result.grade or "", result.element or "")
	end
	if resultPowerValue then
		if result.power then
			resultPowerValue.Text = NumberUtil.abbreviate(result.power)
			resultPowerValue.Visible = true
			if resultPowerKey then
				resultPowerKey.Visible = true
			end
		else
			resultPowerValue.Visible = false
			if resultPowerKey then
				resultPowerKey.Visible = false
			end
		end
	end
	if resultEquipped then
		resultEquipped.Visible = result.equipped == true
	end
	if resultAffix then
		local parts = {}
		local prefix = ModifierConfig.prefix(result.prefix or "")
		local suffix = ModifierConfig.suffix(result.suffix or "")
		if prefix then
			table.insert(parts, prefix.name)
		end
		if suffix then
			table.insert(parts, suffix.name)
		end
		resultAffix.Text = table.concat(parts, "  ·  ")
	end
	if resultPity then
		paintResultPity(selectedCrate())
	end

	-- Entrance. Text fades in order, and the name gets one size punch. No sliding
	-- frames: the stage flash is already the motion, and moving type on a lit
	-- backdrop reads as a layout bug rather than as a reveal.
	local order: { TextLabel } = {}
	for _, label in { resultKicker, resultNew, resultVariant, resultName, resultCondition, resultPowerKey, resultPowerValue, resultEquipped, resultAffix, resultPity, resultBackLabel } do
		if label then
			table.insert(order, label)
		end
	end
	for _, label in order do
		label.TextTransparency = 1
	end
	if resultName then
		resultName.TextSize = nameSize - 4
		local token = rollToken
		task.delay(if rank >= 4 then 0.34 else 0, function()
			if token == rollToken then
				UiKit.tween(resultName, Theme.Duration.slow, { TextSize = nameSize }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			end
		end)
	end
	local token = rollToken
	local baseDelay = if rank >= 4 then 0.34 else 0
	for index, label in order do
		task.delay(baseDelay + (index - 1) * 0.055, function()
			if token == rollToken then
				UiKit.tween(label, Theme.Duration.normal, { TextTransparency = 0 }, Enum.EasingStyle.Quad)
			end
		end)
	end
end

--- The ten-pull ribbon. One cell per copy, rarity on the bottom edge, variant on
--- the left edge, so two collection axes are visible without a second legend.
local function paintRibbon(result: Types.FeedEvent)
	local strip = ribbon
	if strip == nil then
		return
	end
	for _, child in strip:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(ribbonCells)

	local copies = result.results
	if copies == nil or #copies < 2 then
		strip.Visible = false
		return
	end
	strip.Visible = true

	local gap = 4
	local count = #copies
	local width = ribbonWidth()
	local cellW = math.max(36, math.floor((width - gap * (count - 1)) / count))
	local bestId = result.blade
	local bestMarked = false

	for index, copy in copies do
		local blade = bladeOf(copy.blade)
		local variant = variantOf(copy.variant)
		local rarityColor = RARITY_COLOR[blade and blade.rarity or "Scrap"] or Theme.Color.text
		local isBest = not bestMarked and copy.blade == bestId and (result.power == nil or copy.power == result.power)
		if isBest then
			bestMarked = true
		end
		local cell = plate(strip, variant.color:Lerp(Theme.Color.void, 0.8), Theme.Radius.sm)
		cell.Name = "Copy" .. index
		cell.Position = UDim2.fromOffset((index - 1) * (cellW + gap), 0)
		cell.Size = UDim2.fromOffset(cellW, 34)
		cell.ZIndex = 4
		local stroke = UiKit.stroke(cell, if isBest then Theme.Color.text else rarityColor, if isBest then 2 else 1, if isBest then 0.15 else 0.5)

		local edge = UiKit.create("Frame", {
			BackgroundColor3 = variant.color,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(3, 34),
			ZIndex = 5,
		}) :: Frame
		edge.Parent = cell
		local name = UiKit.label(cell, {
			text = if blade then string.upper(blade.name) else string.upper(copy.blade),
			size = Theme.Text.Tiny,
			font = if isBest then Theme.Font.Heading else Theme.Font.Label,
			color = if isBest then Theme.Color.text else Theme.Color.textDim,
		})
		name.Position = UDim2.fromOffset(8, 2)
		name.Size = UDim2.new(1, -10, 0, 18)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.ZIndex = 5

		local bar = UiKit.create("Frame", {
			BackgroundColor3 = rarityColor,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 8, 1, -7),
			Size = UDim2.fromOffset(0, 3),
			ZIndex = 5,
		}) :: Frame
		bar.Parent = cell

		local tag = UiKit.label(cell, {
			text = if isBest then "BEST" else string.upper(blade and blade.rarity or "COPY"),
			size = Theme.Text.Tiny,
			font = Theme.Font.Numeric,
			color = if isBest then Theme.Color.gold else rarityColor,
		})
		tag.Position = UDim2.fromOffset(8, 19)
		tag.Size = UDim2.new(1, -10, 0, 12)
		tag.ZIndex = 5

		table.insert(ribbonCells, cell)

		-- The stagger is the point: ten cells landing together is a table, ten
		-- cells landing one after another is a run of pulls.
		local token = rollToken
		cell.BackgroundTransparency = 1
		edge.BackgroundTransparency = 1
		stroke.Transparency = 1
		name.TextTransparency = 1
		tag.TextTransparency = 1
		bar.BackgroundTransparency = 1
		task.delay((index - 1) * 0.06, function()
			if token ~= rollToken then
				return
			end
			UiKit.tween(cell, Theme.Duration.fast, { BackgroundTransparency = 0 })
			UiKit.tween(edge, Theme.Duration.fast, { BackgroundTransparency = 0 })
			UiKit.tween(stroke, Theme.Duration.fast, { Transparency = if isBest then 0.15 else 0.5 })
			UiKit.tween(name, Theme.Duration.fast, { TextTransparency = 0 })
			UiKit.tween(tag, Theme.Duration.fast, { TextTransparency = 0 })
			UiKit.tween(bar, Theme.Duration.normal, { Size = UDim2.new(1, -16, 0, 3), BackgroundTransparency = 0.15 }, Enum.EasingStyle.Quad)
		end)
	end
end

local function revealNow()
	if not awaitingReveal then
		return
	end
	awaitingReveal = false
	crateOpen = false
	local result = pendingResult
	pendingResult = nil
	rolling = false

	local crate = selectedCrate()
	local blade = bladeOf(result and result.blade)
	local variant = variantOf(result and result.variant)
	local rarity = if blade then blade.rarity else "Scrap"
	local tint = variant.color
	local rarityColor = RARITY_COLOR[rarity] or tint
	local rank = math.max(VARIANT_RANK[variant.id] or 1, RARITY_RANK[rarity] or 1)

	if chargeBar then
		chargeBar.Visible = false
	end
	if chargeCaption then
		chargeCaption.Visible = false
	end

	Sfx.crateShatter()
	task.delay(0.07, function()
		Sfx.result(rank)
	end)

	if viewport then
		Vfx.resultWash(viewport, tint, rank)
		if rank >= 4 then
			local token = rollToken
			task.delay(0.16, function()
				if token == rollToken then
					Vfx.shockwave(viewport, rarityColor, {
						size = 150,
						spread = 3.2,
						duration = 0.5,
						thickness = 5,
					})
				end
			end)
		end
	end
	if hero then
		Vfx.shake(hero, 2 + rank * 1.6, 0.32)
	end
	if stageFlash then
		stageFlash.BackgroundColor3 = rarityColor
		stageFlash.BackgroundTransparency = 0.18
		UiKit.tween(stageFlash, 0.5, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end

	if stageTint then
		local theme = Theme.tierBackdrop(crate.tier)
		stageTint.setColors(tint, theme.cool, rarityColor)
	end
	paintDais(tint)
	paintRays(rank >= 3, tint, rank)
	paintBeam(true, tint, rank)
	paintTag(
		string.format(
			'<font color="#%s">%s</font>   ·   <font color="#%s">%s</font>',
			tint:ToHex(),
			string.upper(variant.name),
			rarityColor:ToHex(),
			string.upper(rarity)
		),
		tint,
		true
	)

	if result == nil or blade == nil then
		unmountCrate()
		mountCrate(crate.shape)
		showRest(crate)
		paintDeck()
		if noteLabel then
			noteLabel.Text = "The forge returned an empty crate. No copy was lost."
			noteLabel.TextColor3 = Theme.Color.warn
		end
		return
	end

	unmountCrate()
	-- The blade lands a little too big and settles. The crate is gone in the
	-- same frame, so the punch reads as the copy coming through the crack.
	if viewportScale then
		viewportScale.Scale = 1.1
		UiKit.tween(viewportScale, Theme.Duration.slow, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end
	if viewport then
		BladePreview.thumbnail(viewport, blade, nil, tint)
	end
	showResult(result, blade, variant, rank)
	paintRibbon(result)
	paintDeck()
end

local function tryReveal()
	if not awaitingReveal or not crateOpen then
		return
	end
	local wait = math.max(0, revealReadyAt - os.clock())
	if wait > 0 then
		local token = rollToken
		task.delay(wait, function()
			if token == rollToken and awaitingReveal and crateOpen and pendingResult ~= nil then
				revealNow()
			end
		end)
		return
	end
	revealNow()
end

--- Presses the pool for `count` copies. One transaction: the server charges the
--- ramp price for the whole batch and reports every copy back as one event.
---
--- The page no longer performs the reveal. It opens `CrateReveal`, a canvas-wide
--- scrim with the chosen crate in it, and the player breaks the seal with six
--- clicks. The answer is requested now and held until the sixth.
function CratesView.roll(count: number?)
	local batch = if count == 10 then 10 elseif count == 3 then 3 else 1
	if rolling or CrateReveal.isOpen() then
		return false
	end
	local state = StateStore.current
	if state == nil then
		return false
	end
	local crate = selectedCrate()
	local q = state.forgeCosts[crate.id]
	if q == nil then
		Sfx.error()
		return false
	end
	local free = math.max(0, state.invMax - state.invCount)
	if free <= 0 then
		Sfx.error()
		if noteLabel then
			noteLabel.Text = string.format("Vault full: %d / %d. Melt a copy to make room.", state.invCount, state.invMax)
			noteLabel.TextColor3 = Theme.Color.warn
		end
		return false
	end
	-- The server caps a pull at the free slots. Spawn and charge the same number
	-- here, or a ten-pull with three slots shows ten crates and pays for three.
	-- The price tier follows `actual`, not `batch`: a x10 key with three free
	-- slots is a x3 purchase and must quote the x3 price.
	local actual = math.min(batch, free)
	local price = if actual >= 10 then q.ten elseif actual >= 3 then q.three else q.one
	if state.sm < price then
		Sfx.error()
		if noteLabel then
			noteLabel.Text = string.format("Needs %s Star-Matter.", NumberUtil.abbreviate(price))
			noteLabel.TextColor3 = Theme.Color.red
		end
		return false
	end
	if actual < batch and noteLabel then
		noteLabel.Text = string.format("Vault space: rolling %d of %d.", actual, batch)
		noteLabel.TextColor3 = Theme.Color.warn
	end

	local _, _, remaining = pityProgress(crate)
	rolling = true
	local opened = CrateReveal.open({
		crate = crate,
		batch = actual,
		armed = remaining <= 1,
		onExit = function()
			rolling = false
			paintDeck()
		end,
	})
	if not opened then
		rolling = false
		Sfx.error()
		return false
	end

	StateStore.send("forge", { crate = crate.id, count = actual })
	paintDeck()
	return true
end

local function pick(id: string)
	if ForgeConfig.crate(id) == nil or id == selected then
		return
	end
	-- A locked pool is a window, not a purchase. Selecting it is a local browse:
	-- the server refuses to switch the profile's crate to a pool the run has not
	-- opened, and the next sync would snap the page back to the old one. So the
	-- pick is only sent when the pool can actually be rolled.
	local unlocked = quote(id) ~= nil
	browsingLocked = not unlocked
	selected = id
	Sfx.tab()
	rolling = false
	awaitingReveal = false
	crateOpen = false
	pendingResult = nil
	rollToken += 1
	local crate = selectedCrate()
	resetStage(crate)
	unmountCrate()
	mountCrate(crate.shape)
	paintDeck()
	-- The crate is profile state, not a per-roll argument: the server bills the
	-- ramp of whatever crate the profile is on, so the pick has to land before
	-- the press. Skipping this made the next sync paint the old pool back over
	-- the one the player had just chosen.
	if unlocked then
		StateStore.send("crate", id)
	end
	local callback = CratesView.onSelect
	if callback then
		callback(selected)
	end
end

-- ---------------------------------------------------------------------------
-- Mount
-- ---------------------------------------------------------------------------

local function header(parent: Frame)
	local banner = UiKit.banner(parent, {
		text = "CRATE VAULT",
		subtitle = "FIVE POOLS  ·  ODDS PRINTED",
		width = UDim2.new(1, 0, 0, HEADER_H),
		height = HEADER_H,
		size = Theme.Text.Title - 4,
		accent = Theme.Color.quantum,
		icon = "★",
	})
	banner.Name = "Header"
end

local function buildRail(parent: Frame)
	local rail = plate(parent, Theme.Color.panelSunken, Theme.Radius.md)
	rail.Name = "Rail"
	rail.Size = UDim2.new(0, RAIL_W, 1, 0)
	UiKit.stroke(rail, Theme.Color.strokeFaint, Theme.Stroke.hair, 0.25)
	railPlate = rail

	local head = UiKit.label(rail, {
		text = "POOLS",
		size = Theme.Text.Tiny,
		font = Theme.Font.Heading,
		color = Theme.Color.textFaint,
	})
	head.Position = UDim2.fromOffset(14, 12)
	head.Size = UDim2.fromOffset(RAIL_W - 28, 16)

	for index, crate in ForgeConfig.Tiers do
		local row = UiKit.create("TextButton", {
			Name = "Crate_" .. crate.id,
			BackgroundColor3 = Theme.Color.panelRaised,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			Position = UDim2.fromOffset(12, 34 + (index - 1) * (ROW_H + ROW_GAP)),
			Size = UDim2.fromOffset(RAIL_W - 24, ROW_H),
		}) :: TextButton
		UiKit.corner(row, Theme.Radius.sm)
		UiKit.stroke(row, Theme.Color.strokeFaint, Theme.Stroke.hair, 0.35)
		row.Parent = rail
		if index == 1 then
			row.BackgroundColor3 = Theme.Color.card
		end

		local accent = plate(row, crate.accent, 2)
		accent.Size = UDim2.fromOffset(4, ROW_H)
		accent.ZIndex = 3

		local art = UiKit.create("Frame", {
			Name = "Art",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(14, (ROW_H - 40) / 2 - 2),
			Size = UDim2.fromOffset(40, 40),
		}) :: Frame
		art.Parent = row
		glyph(art, crate.shape, crate.accent, 40)

		local name = UiKit.label(row, {
			text = string.upper(crate.name),
			size = Theme.Text.Small,
			font = Theme.Font.Heading,
			color = Theme.Color.text,
		})
		name.Name = "Name"
		name.Position = UDim2.fromOffset(66, 18)
		name.Size = UDim2.fromOffset(RAIL_W - 96, 20)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.ZIndex = 3

		local price = UiKit.label(row, {
			text = "--",
			size = Theme.Text.Tiny,
			font = Theme.Font.Numeric,
			color = Theme.Color.textSecondary,
		})
		price.Position = UDim2.fromOffset(66, 40)
		price.Size = UDim2.fromOffset(RAIL_W - 92, 16)
		price.ZIndex = 3
		railPrices[crate.id] = price

		local track = UiKit.create("Frame", {
			BackgroundColor3 = Theme.Color.strokeFaint,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(12, ROW_H - 5),
			Size = UDim2.new(1, -24, 0, 2),
			ZIndex = 4,
			Visible = false,
		}) :: Frame
		track.Parent = row
		railTracks[crate.id] = track

		local fill = UiKit.create("Frame", {
			BackgroundColor3 = crate.accent,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(0, 1),
			ZIndex = 5,
		}) :: Frame
		fill.Parent = track
		railFills[crate.id] = fill

		UiKit.track(row, row.Activated:Connect(function()
			pick(crate.id)
		end))
		UiKit.track(row, row.MouseEnter:Connect(function()
			Sfx.hover()
			UiKit.tween(row, Theme.Duration.fast, { BackgroundColor3 = Theme.Color.card })
		end))
		UiKit.track(row, row.MouseLeave:Connect(function()
			if crate.id ~= selected then
				UiKit.tween(row, Theme.Duration.normal, { BackgroundColor3 = Theme.Color.panelRaised })
			else
				UiKit.tween(row, Theme.Duration.normal, { BackgroundColor3 = Theme.Color.card })
			end
		end))

		railRows[crate.id] = row
	end
end

--- Builds the objects hanging over the hero, independent of the info column.
local function buildStage()
	if hero == nil then
		return
	end

	-- Rays sit behind the subject. Twelve thin blades of light, anchored at the
	-- object's centre, each fading at both ends so the wheel has no hard rim.
	local host = UiKit.create("Frame", {
		Name = "Rays",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(OBJECT_W / 2, 0),
		Size = UDim2.fromOffset(OBJECT_W, HERO_H),
		ZIndex = 1,
		Visible = false,
	}) :: Frame
	host.Parent = hero
	rayHost = host
	for index = 1, 12 do
		local ray = UiKit.create("Frame", {
			BackgroundColor3 = Theme.Color.white,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(3, 360),
			Rotation = (index - 1) * 15,
			ZIndex = 1,
		}) :: Frame
		fadeGradient(ray, {
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.45, 0.1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(0.55, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		ray.Parent = host
		table.insert(rays, ray)
	end

	local shaft = UiKit.create("Frame", {
		Name = "Beam",
		BackgroundColor3 = Theme.Color.white,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(110, 0),
		Size = UDim2.fromOffset(180, HERO_H),
		ZIndex = 1,
		Visible = false,
	}) :: Frame
	fadeGradient(shaft, {
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	shaft.Parent = hero
	beam = shaft

	-- Dais. A soft pool under the subject plus a 2px rule at the floor line. The
	-- 3D crate has no ground plane of its own, so without this it floats.
	local glow = UiKit.create("Frame", {
		Name = "DaisGlow",
		BackgroundColor3 = Theme.Color.white,
		BackgroundTransparency = 0.88,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(86, 216),
		Size = UDim2.fromOffset(228, 54),
		ZIndex = 1,
	}) :: Frame
	UiKit.corner(glow, 999)
	glow.Parent = hero
	daisGlow = glow

	local line = UiKit.create("Frame", {
		Name = "DaisLine",
		BackgroundColor3 = Theme.Color.white,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(100, 268),
		Size = UDim2.fromOffset(200, 2),
		ZIndex = 3,
	}) :: Frame
	fadeGradient(line, {
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	line.Parent = hero
	daisLine = line

	local view = UiKit.create("ViewportFrame", {
		Name = "Preview",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset((OBJECT_W - VIEW) / 2, 0),
		Size = UDim2.fromOffset(VIEW, VIEW),
		ZIndex = 2,
	}) :: ViewportFrame
	view.ClipsDescendants = true
	view.Parent = hero
	viewport = view
	local scale = UiKit.create("UIScale", { Scale = 1 }) :: UIScale
	scale.Parent = view
	viewportScale = scale

	local tag = UiKit.label(hero, {
		text = "",
		size = Theme.Text.Small,
		font = Theme.Font.Black,
		color = Theme.Color.text,
		align = Enum.TextXAlignment.Center,
		rich = true,
	})
	tag.Name = "RarityTag"
	tag.AnchorPoint = Vector2.new(0.5, 0)
	tag.Position = UDim2.fromOffset(OBJECT_W / 2, 14)
	tag.Size = UDim2.fromOffset(300, 26)
	tag.BackgroundColor3 = Theme.Color.void
	tag.BackgroundTransparency = 1
	tag.ZIndex = 5
	tag.Visible = false
	UiKit.corner(tag, Theme.Radius.sm)
	UiKit.stroke(tag, Theme.Color.stroke, Theme.Stroke.hair, 0.2)
	rarityTag = tag

	local caption = UiKit.label(hero, {
		text = "BREACHING",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.textSecondary,
		align = Enum.TextXAlignment.Center,
	})
	caption.Name = "ChargeCaption"
	caption.Position = UDim2.fromOffset(0, 242)
	caption.Size = UDim2.fromOffset(OBJECT_W, 16)
	caption.ZIndex = 5
	caption.Visible = false
	chargeCaption = caption

	local bar = UiKit.create("Frame", {
		Name = "ChargeBar",
		BackgroundColor3 = Theme.Color.strokeFaint,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(40, 264),
		Size = UDim2.fromOffset(OBJECT_W - 80, 4),
		ZIndex = 5,
		Visible = false,
	}) :: Frame
	UiKit.corner(bar, 2)
	bar.Parent = hero
	chargeBar = bar

	local fill = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.starMatter,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		ZIndex = 6,
	}) :: Frame
	UiKit.corner(fill, 2)
	fill.Parent = bar

	local flash = UiKit.create("Frame", {
		Name = "StageFlash",
		BackgroundColor3 = Theme.Color.white,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 7,
	}) :: Frame
	UiKit.corner(flash, Theme.Radius.md)
	flash.Parent = hero
	stageFlash = flash
end

local function buildRest(parent: Frame)
	local group = UiKit.create("Frame", {
		Name = "Rest",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
	}) :: Frame
	group.Parent = parent
	restGroup = group

	local width = infoWidth()

	local eyebrow = UiKit.label(group, {
		text = "POOL 01 / 05",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.gold,
	})
	eyebrow.Position = UDim2.fromOffset(0, 0)
	eyebrow.Size = UDim2.fromOffset(260, 16)
	restEyebrow = eyebrow

	local title = UiKit.label(group, {
		text = "STANDARD FORGE CRATE",
		size = Theme.Text.Title,
		font = Theme.Font.Black,
		color = Theme.Color.text,
	})
	title.Position = UDim2.fromOffset(0, 19)
	title.Size = UDim2.new(1, -8, 0, 38)
	title.TextTruncate = Enum.TextTruncate.AtEnd
	restTitle = title

	local blurb = UiKit.label(group, {
		text = "",
		size = Theme.Text.Small,
		font = Theme.Font.Body,
		color = Theme.Color.textSecondary,
		wrap = true,
	})
	blurb.Position = UDim2.fromOffset(0, 60)
	blurb.Size = UDim2.new(1, -12, 0, 38)
	blurb.TextYAlignment = Enum.TextYAlignment.Top
	restBlurb = blurb

	local pityLabel = UiKit.label(group, {
		text = "PITY",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.textFaint,
	})
	pityLabel.Position = UDim2.fromOffset(0, 106)
	pityLabel.Size = UDim2.fromOffset(200, 14)
	restPityValue = pityLabel

	local hint = UiKit.label(group, {
		text = "",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.textSecondary,
		align = Enum.TextXAlignment.Right,
	})
	hint.Position = UDim2.fromOffset(0, 106)
	hint.Size = UDim2.new(1, 0, 0, 14)
	restPityHint = hint

	local ticks = UiKit.create("Frame", {
		Name = "PityTicks",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 124),
		Size = UDim2.fromOffset(width, 14),
		ZIndex = 4,
	}) :: Frame
	ticks.Parent = group
	pityHost = ticks
	for _ = 1, 12 do
		local tick = UiKit.create("Frame", {
			BackgroundColor3 = Theme.Color.strokeBright,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(8, 8),
		}) :: Frame
		UiKit.corner(tick, 1)
		tick.Parent = ticks
		table.insert(pityTicks, tick)
	end

	local unlock = UiKit.create("Frame", {
		Name = "UnlockBar",
		BackgroundColor3 = Theme.Color.strokeFaint,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 124),
		Size = UDim2.fromOffset(width, 8),
		ZIndex = 4,
		Visible = false,
	}) :: Frame
	UiKit.corner(unlock, 2)
	unlock.Parent = group
	unlockBar = unlock

	local unlockFillFrame = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.gold,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		ZIndex = 5,
	}) :: Frame
	UiKit.corner(unlockFillFrame, 2)
	unlockFillFrame.Parent = unlock
	unlockFill = unlockFillFrame

	local divider = rule(group, 150, width, Theme.Color.strokeFaint, 0.2)
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.ZIndex = 4

	local function stat(index: number, caption: string): TextLabel
		local x = (index - 1) / 3
		local key = UiKit.label(group, {
			text = caption,
			size = Theme.Text.Tiny,
			font = Theme.Font.Label,
			color = Theme.Color.textFaint,
		})
		key.Position = UDim2.new(x, 0, 0, 160)
		key.Size = UDim2.new(1 / 3, -8, 0, 14)
		local value = UiKit.label(group, {
			text = "--",
			size = Theme.Text.Subheading,
			font = Theme.Font.Numeric,
			color = Theme.Color.text,
		})
		value.Position = UDim2.new(x, 0, 0, 176)
		value.Size = UDim2.new(1 / 3, -8, 0, 22)
		return value
	end
	restRareValue = stat(1, "VOID OR BETTER")
	if restRareValue then
		restRareValue.TextColor3 = RARITY_COLOR.Void
	end

	-- A large, very faint pool number. It gives the empty right half a subject
	-- without adding another object to read.
	local mark = UiKit.label(group, {
		text = "01",
		size = Theme.Text.Hero * 2,
		font = Theme.Font.Black,
		color = Theme.Color.gold,
		align = Enum.TextXAlignment.Right,
	})
	mark.Name = "PoolMark"
	mark.Position = UDim2.new(1, -160, 0, 156)
	mark.Size = UDim2.fromOffset(160, 112)
	mark.TextTransparency = 0.9
	mark.ZIndex = 2
	restMark = mark
end

local function buildResult(parent: Frame)
	local group = UiKit.create("Frame", {
		Name = "Result",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Visible = false,
	}) :: Frame
	group.Parent = parent
	resultGroup = group

	local kicker = UiKit.label(group, {
		text = "JUST FORGED",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.cyan,
	})
	kicker.Position = UDim2.fromOffset(0, 0)
	kicker.Size = UDim2.fromOffset(320, 16)
	resultKicker = kicker

	local new = UiKit.label(group, {
		text = "",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.gold,
		align = Enum.TextXAlignment.Right,
	})
	new.Position = UDim2.new(1, -200, 0, 0)
	new.Size = UDim2.fromOffset(200, 16)
	new.Visible = false
	resultNew = new

	local variant = UiKit.label(group, {
		text = "",
		size = Theme.Text.Subheading,
		font = Theme.Font.Black,
		color = Theme.Color.text,
		rich = true,
	})
	variant.Position = UDim2.fromOffset(0, 20)
	variant.Size = UDim2.new(1, -8, 0, 22)
	resultVariant = variant

	local name = UiKit.label(group, {
		text = "",
		size = Theme.Text.Title,
		font = Theme.Font.Black,
		color = Theme.Color.text,
		wrap = true,
	})
	name.Position = UDim2.fromOffset(0, 45)
	name.Size = UDim2.new(1, -8, 0, 64)
	name.TextYAlignment = Enum.TextYAlignment.Top
	resultName = name

	local condition = UiKit.label(group, {
		text = "",
		size = Theme.Text.Small,
		font = Theme.Font.Body,
		color = Theme.Color.textDim,
	})
	condition.Position = UDim2.fromOffset(0, 111)
	condition.Size = UDim2.new(1, -8, 0, 18)
	resultCondition = condition

	local powerKey = UiKit.label(group, {
		text = "POWER",
		size = Theme.Text.Tiny,
		font = Theme.Font.Label,
		color = Theme.Color.textFaint,
	})
	powerKey.Position = UDim2.fromOffset(0, 136)
	powerKey.Size = UDim2.fromOffset(52, 22)
	resultPowerKey = powerKey

	local power = UiKit.label(group, {
		text = "--",
		size = Theme.Text.Heading,
		font = Theme.Font.Numeric,
		color = Theme.Color.text,
	})
	power.Position = UDim2.fromOffset(54, 133)
	power.Size = UDim2.fromOffset(180, 24)
	resultPowerValue = power

	local equipped = UiKit.label(group, {
		text = "AUTO-EQUIPPED",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.emerald,
		align = Enum.TextXAlignment.Right,
	})
	equipped.Position = UDim2.new(1, -200, 0, 136)
	equipped.Size = UDim2.fromOffset(200, 18)
	equipped.Visible = false
	resultEquipped = equipped

	local affix = UiKit.label(group, {
		text = "",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.textSecondary,
	})
	affix.Position = UDim2.fromOffset(0, 160)
	affix.Size = UDim2.new(1, -8, 0, 16)
	resultAffix = affix

	local pity = UiKit.label(group, {
		text = "",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.textFaint,
	})
	pity.Position = UDim2.fromOffset(0, 181)
	pity.Size = UDim2.new(1, -8, 0, 16)
	resultPity = pity

	-- The result is a room the player can leave without buying another pull.
	-- Without this the only exits were rolling again or switching pools, which
	-- made a good reveal feel like a modal with no close.
	local back = UiKit.create("TextButton", {
		Name = "BackToPool",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Position = UDim2.fromOffset(0, 208),
		Size = UDim2.fromOffset(150, 20),
		ZIndex = 5,
	}) :: TextButton
	back.Parent = group
	local backLabel = UiKit.label(back, {
		text = "BACK TO POOL",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.textFaint,
	})
	backLabel.Size = UDim2.fromScale(1, 1)
	backLabel.ZIndex = 6
	resultBackLabel = backLabel

	UiKit.track(back, back.MouseEnter:Connect(function()
		UiKit.tween(backLabel, Theme.Duration.fast, { TextColor3 = Theme.Color.text })
	end))
	UiKit.track(back, back.MouseLeave:Connect(function()
		UiKit.tween(backLabel, Theme.Duration.normal, { TextColor3 = Theme.Color.textFaint })
	end))
	UiKit.track(back, back.Activated:Connect(function()
		CratesView.dismiss()
	end))
end

local function buildRibbon()
	local heroFrame = hero
	if heroFrame == nil then
		return
	end
	local strip = UiKit.create("Frame", {
		Name = "PullRibbon",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, HERO_H - 44),
		Size = UDim2.new(1, -24, 0, 34),
		ZIndex = 4,
		Visible = false,
	}) :: Frame
	strip.Parent = heroFrame
	ribbon = strip
end

local function buildHero(parent: Frame)
	local frame = plate(parent, Theme.Color.panelSunken, Theme.Radius.md)
	frame.Name = "Hero"
	frame.Size = UDim2.new(1, 0, 0, HERO_H)
	frame.ClipsDescendants = true
	hero = frame

	local crate = selectedCrate()
	local theme = Theme.tierBackdrop(crate.tier)
	stageTint = StageBackdrop.paint(frame, {
		warm = crate.accent,
		cool = theme.cool,
		accent = crate.accent,
		radius = Theme.Radius.md,
		zIndex = 0,
		depth = 0.8,
	})
	UiKit.stroke(frame, Theme.Color.strokeFaint, Theme.Stroke.hair, 0.15)

	buildStage()

	-- The reveal's rays and the rest stage's wash both run to the right edge.
	-- A soft vertical scrim under the info column keeps the type off the light
	-- without putting it back inside a card.
	local scrim = UiKit.create("Frame", {
		Name = "InfoScrim",
		BackgroundColor3 = Theme.Color.void,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(INFO_X - 24, 0),
		Size = UDim2.new(1, -(INFO_X - 24), 1, 0),
		ZIndex = 3,
	}) :: Frame
	fadeGradient(scrim, {
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.18, 0.86),
		NumberSequenceKeypoint.new(1, 0.3),
	})
	scrim.Parent = frame

	local info = UiKit.create("Frame", {
		Name = "Info",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(INFO_X, 14),
		Size = UDim2.new(1, -INFO_X - 20, 1, -28),
		ZIndex = 4,
	}) :: Frame
	info.Parent = frame

	buildRest(info)
	buildResult(info)
	buildRibbon()
end

local function buildOdds(parent: Frame)
	local band = UiKit.create("Frame", {
		Name = "Odds",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, ODDS_Y),
		Size = UDim2.new(1, 0, 0, ODDS_H),
	}) :: Frame
	band.Parent = parent
	oddsHost = band
end

--- One roll key. `primary` gets the saturated fill and the heavy outline; the
--- secondary key is a quiet plate beside it. Two equally loud keys made the page
--- ask "which one is the real button" on every visit.
local function buildKey(parent: Frame, name: string, x: number, w: number, accent: Color3, primary: boolean): (TextButton, TextLabel, TextLabel)
	local fill = if primary then accent else Theme.Color.panelRaised
	local button = UiKit.create("TextButton", {
		Name = name,
		BackgroundColor3 = fill,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Position = UDim2.fromOffset(x, KEYS_Y),
		Size = UDim2.fromOffset(w, KEY_H),
	}) :: TextButton
	UiKit.corner(button, Theme.Radius.md)
	UiKit.stroke(button, if primary then Theme.Color.outline else Theme.Color.strokeBright, if primary then Theme.Stroke.bold else Theme.Stroke.thin, 0)
	button.Parent = parent

	local face = UiKit.label(button, {
		text = "ROLL",
		size = Theme.Text.Subheading,
		font = Theme.Font.Black,
		color = if primary then Theme.onColor(fill) else Theme.Color.text,
		align = Enum.TextXAlignment.Center,
	})
	face.Position = UDim2.fromOffset(0, 10)
	face.Size = UDim2.new(1, 0, 0, 22)
	face.ZIndex = 2

	local cost = UiKit.label(button, {
		text = "--",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = if primary then Theme.onColor(fill) else Theme.Color.textFaint,
		align = Enum.TextXAlignment.Center,
	})
	cost.Position = UDim2.fromOffset(0, 36)
	cost.Size = UDim2.new(1, 0, 0, 16)
	cost.ZIndex = 2

	local hoverBase: Color3? = nil
	UiKit.track(button, button.MouseEnter:Connect(function()
		Sfx.hover()
		hoverBase = button.BackgroundColor3
		UiKit.tween(button, Theme.Duration.fast, { BackgroundColor3 = button.BackgroundColor3:Lerp(Theme.Color.white, 0.08) })
	end))
	UiKit.track(button, button.MouseLeave:Connect(function()
		local base = hoverBase or fill
		hoverBase = nil
		UiKit.tween(button, Theme.Duration.normal, { BackgroundColor3 = base })
	end))
	UiKit.track(button, button.Activated:Connect(function()
		local base = button.BackgroundColor3
		UiKit.tween(button, Theme.Duration.instant, { BackgroundColor3 = base:Lerp(Theme.Color.ink, 0.16) })
		task.delay(0.07, function()
			if button.Parent then
				UiKit.tween(button, Theme.Duration.fast, { BackgroundColor3 = base })
			end
		end)
	end))
	return button, face, cost
end

local function buildKeys(parent: Frame)
	local gap = 10
	-- 26 / 30 / 44. The ten-pull is still the real purchase on this page; the
	-- single is the try-it key and the three is the bridge a player reaches for
	-- when they can almost afford ten.
	local available = deckWidth() - gap * 2
	local oneW = math.floor(available * 0.26)
	local threeW = math.floor(available * 0.30)
	local tenW = available - oneW - threeW

	rollOne, rollOneFace, rollOneCost = buildKey(parent, "RollOne", 0, oneW, Theme.Color.panelRaised, false)
	UiKit.track(rollOne, rollOne.Activated:Connect(function()
		CratesView.roll(1)
	end))

	rollThree, rollThreeFace, rollThreeCost = buildKey(parent, "RollThree", oneW + gap, threeW, Theme.Color.panelRaised, false)
	UiKit.track(rollThree, rollThree.Activated:Connect(function()
		CratesView.roll(3)
	end))

	rollTen, rollTenFace, rollTenCost = buildKey(parent, "RollTen", oneW + threeW + gap * 2, tenW, Theme.Color.starMatter, true)
	UiKit.track(rollTen, rollTen.Activated:Connect(function()
		CratesView.roll(10)
	end))

	noteLabel = UiKit.label(parent, {
		text = "",
		size = Theme.Text.Tiny,
		font = Theme.Font.Body,
		color = Theme.Color.textSecondary,
	})
	noteLabel.Name = "Note"
	noteLabel.Position = UDim2.fromOffset(0, NOTE_Y)
	noteLabel.Size = UDim2.new(1, 0, 0, 18)
	noteLabel.TextTruncate = Enum.TextTruncate.AtEnd
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

--- `x, y, w, h` are the content rect from `Layout`, in design pixels.
function CratesView.init(canvas: Frame, x: number, y: number, width: number, height: number)
	if root then
		return
	end

	local card = UiKit.panel(canvas, {
		tier = "shell",
		radius = Theme.Radius.xl,
	})
	card.Name = "Crates"
	card.Size = UDim2.fromOffset(width, height)
	card.Position = UDim2.fromOffset(x, y)
	card.Visible = false
	root = card

	local body = UiKit.create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -36, 1, -(HEADER_H + PAD * 2)),
		Position = UDim2.fromOffset(18, HEADER_H + 18),
	}) :: Frame
	body.Parent = card

	header(card)

	buildRail(body)

	local deckFrame = UiKit.create("Frame", {
		Name = "Deck",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(DECK_X, 0),
		Size = UDim2.new(1, -DECK_X, 1, 0),
	}) :: Frame
	deckFrame.Parent = body
	deck = deckFrame

	buildHero(deckFrame)
	buildOdds(deckFrame)
	buildKeys(deckFrame)

	-- The page owns the crate model for its whole life; mounts happen on select
	-- and on roll, never on tab switch, so coming back to the page is instant.
	mountCrate(selectedCrate().shape)
	paintDeck()

	-- The ceremony is a canvas-level overlay: a black scrim over the rail, the
	-- HUD and this page, with the chosen crate inside it. It is built once and
	-- reused for every pool.
	CrateReveal.init(canvas)

	unsubscribeEvent = StateStore.onEvent(function(event: Types.FeedEvent)
		if event.kind ~= "forged" then
			return
		end
		-- A roll on the anvil is not this page's business. Only the pull this page
		-- started owns the reveal, and only for the pool it started on.
		if not awaitingReveal then
			return
		end
		if event.crate ~= nil and event.crate ~= selected then
			return
		end
		pendingResult = event
		tryReveal()
	end)
end

--- Re-places the page after a resize. The rail is a fixed 300 and the deck is
--- elastic, so only the two roots and the odds strip need moving.
function CratesView.layout()
	local card = root
	if card == nil then
		return
	end
	card.Size = UDim2.fromOffset(Layout.CONTENT_W, Layout.CONTENT_H)
	card.Position = UDim2.fromOffset(Layout.CONTENT_X, Layout.CONTENT_Y)
	if deck then
		deck.Size = UDim2.new(1, -DECK_X, 1, 0)
	end
	if railPlate then
		railPlate.Size = UDim2.new(0, RAIL_W, 1, 0)
	end
	if oddsHost then
		paintOdds(selectedCrate())
	end
	if rollOne and rollThree and rollTen then
		local gap = 10
		local available = deckWidth() - gap * 2
		local oneW = math.floor(available * 0.26)
		local threeW = math.floor(available * 0.30)
		local tenW = available - oneW - threeW
		rollOne.Size = UDim2.fromOffset(oneW, KEY_H)
		rollThree.Position = UDim2.fromOffset(oneW + gap, KEYS_Y)
		rollThree.Size = UDim2.fromOffset(threeW, KEY_H)
		rollTen.Position = UDim2.fromOffset(oneW + threeW + gap * 2, KEYS_Y)
		rollTen.Size = UDim2.fromOffset(tenW, KEY_H)
	end
	paintPity(selectedCrate())
end

function CratesView.card(): Frame?
	return root
end

--- Set once the page has adopted the server's crate. Before the first payload the
--- page has nothing to mirror, so it starts on Standard and corrects itself here.
local adopted = false

function CratesView.render(payload: Types.SyncPayload)
	if root == nil then
		return
	end
	-- Adoption runs even while the tab is hidden: the page is born on Standard
	-- and the first payload may land long before the player opens it, so waiting
	-- for a visible frame would show the wrong pool for one sync.
	if not adopted then
		adopted = true
		if ForgeConfig.crate(payload.forgeCrate) then
			selected = payload.forgeCrate
		end
		if viewport then
			mountCrate(selectedCrate().shape)
			paintRestTint(selectedCrate())
		end
	end
	if not root.Visible then
		return
	end
	-- The server is authoritative about which pool the ramp belongs to. Once the
	-- page is idle, follow it: a stale local pick after a rejected roll would leave
	-- the page pricing a crate the server is not on.
	--
	-- Except while the player is browsing a locked pool. That pick never reached
	-- the server on purpose, so following `forgeCrate` here would undo the browse
	-- on the very next tick.
	local browsingLockedPool = browsingLocked and quote(selected) == nil
	if not browsingLockedPool then
		browsingLocked = false
		if not rolling and ForgeConfig.crate(payload.forgeCrate) and payload.forgeCrate ~= selected then
			selected = payload.forgeCrate
			if not showingResult then
				unmountCrate()
				mountCrate(selectedCrate().shape)
				paintRestTint(selectedCrate())
			end
		end
	end
	-- While the crate is in the air the page is showing its own note, and
	-- repainting the deck underneath would overwrite the roll's status line.
	if rolling then
		return
	end
	paintDeck()
end

--- Studio seam and `ForgeView` chip: selects a pool without a pointer.
function CratesView.select(id: string): boolean
	if ForgeConfig.crate(id) == nil then
		return false
	end
	pick(id)
	return true
end

--- Studio seam: paints a reveal without charging or rolling. Used by `QF_Dev`
--- to check the top-rarity treatment without waiting for a 0.35% pull.
function CratesView.preview(bladeId: string, variantId: string?): boolean
	local blade = BladeRegistry.get(bladeId)
	if blade == nil then
		return false
	end
	rollToken += 1
	awaitingReveal = true
	crateOpen = true
	revealReadyAt = 0
	pendingResult = {
		kind = "forged",
		blade = bladeId,
		variant = variantId or "prismatic",
		batch = 1,
		crate = selected,
		newBlade = true,
	}
	revealNow()
	return true
end

--- Studio seam: paints the overlay reveal without charging or rolling.
function CratesView.revealPreview(bladeId: string, variantId: string?): boolean
	local blade = BladeRegistry.get(bladeId)
	if blade == nil then
		return false
	end
	local crate = selectedCrate()
	return CrateReveal.preview(crate, {
		kind = "forged",
		blade = bladeId,
		variant = variantId or "prismatic",
		batch = 1,
		crate = crate.id,
		newBlade = true,
	})
end

--- Studio seam: opens the ceremony with `batch` crates and answers as the
--- server would, so the drop, the click ladder and the reveal can be walked
--- without spending a pull or a vault slot.
function CratesView.stagePreview(batch: number?): boolean
	local crate = selectedCrate()
	local count = math.clamp(math.floor(batch or 1), 1, 10)
	local opened = CrateReveal.open({ crate = crate, batch = count, armed = false })
	if not opened then
		return false
	end
	local copies: { Types.ForgedCopy } = {}
	local best: Types.ForgedCopy? = nil
	local bestScore = -1
	for index = 1, count do
		local rarity = ForgeConfig.rollRarity(false, crate)
		local blade = ForgeConfig.pickBlade(crate.tier, rarity)
		if blade then
			local variant = if index == count then "prismatic" elseif index % 3 == 0 then "void" else "standard"
			local copy: Types.ForgedCopy = {
				blade = blade.id,
				variant = variant,
				power = index * 1000 + (RARITY_RANK[blade.rarity] or 1),
				newBlade = false,
				newVariant = false,
			}
			copies[#copies + 1] = copy
			local score = (RARITY_RANK[blade.rarity] or 1) * 10 + (VARIANT_RANK[variant] or 1)
			if score >= bestScore then
				bestScore = score
				best = copy
			end
		end
	end
	if best == nil then
		return false
	end
	CrateReveal.deliver({
		kind = "forged",
		blade = best.blade,
		variant = best.variant,
		power = best.power,
		batch = #copies,
		crate = crate.id,
		newBlade = true,
		results = copies,
	})
	return true
end

--- Leaves the result without buying another pull. The crate comes back, so the
--- page is a pool browser again rather than a reveal with no exit.
function CratesView.dismiss()
	if CrateReveal.isOpen() then
		CrateReveal.close()
		return
	end
	if rolling then
		return
	end
	local crate = selectedCrate()
	resetStage(crate)
	unmountCrate()
	mountCrate(crate.shape)
	paintRestTint(crate)
	paintDeck()
end

function CratesView.selection(): string
	return selected
end

function CratesView.isRolling(): boolean
	return rolling
end

function CratesView.destroy()
	if unsubscribeEvent then
		unsubscribeEvent()
		unsubscribeEvent = nil
	end
	CrateReveal.destroy()
	unmountCrate()
	if root then
		root:Destroy()
		root = nil
	end
	table.clear(railRows)
	table.clear(railPrices)
	table.clear(railTracks)
	table.clear(railFills)
	table.clear(pityTicks)
	table.clear(ribbonCells)
	table.clear(rays)
	deck = nil
	railPlate = nil
	hero = nil
	viewport = nil
	stageTint = nil
	stageFlash = nil
	rarityTag = nil
	rayHost = nil
	beam = nil
	daisGlow = nil
	daisLine = nil
	chargeBar = nil
	chargeCaption = nil
	restGroup = nil
	restEyebrow = nil
	restTitle = nil
	restBlurb = nil
	restPityValue = nil
	restPityHint = nil
	pityHost = nil
	unlockBar = nil
	unlockFill = nil
	restRareValue = nil
	restMark = nil
	resultGroup = nil	resultKicker = nil
	resultNew = nil
	resultVariant = nil
	resultName = nil
	resultCondition = nil
	resultPowerKey = nil
	resultPowerValue = nil
	resultEquipped = nil
	resultAffix = nil
	resultPity = nil
	resultBackLabel = nil
	ribbon = nil
	oddsHost = nil
	rollOne = nil
	rollOneFace = nil
	rollOneCost = nil
	rollThree = nil
	rollThreeFace = nil
	rollThreeCost = nil
	rollTen = nil
	rollTenFace = nil
	rollTenCost = nil
	noteLabel = nil
	rolling = false
	awaitingReveal = false
	crateOpen = false
	pendingResult = nil
	showingResult = false
end

return CratesView
