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
-- The page owns the whole reveal. Press ROLL, the crate drops and rattles, the
-- pool's answer lands from the server, the crate shatters, and the copy the roll
-- produced is mounted in the same viewport as a static blade. The anvil still
-- owns the three-second celebration for a blade that beats the equipped one; this
-- page is the terminal where you buy, and it should answer on the spot.

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

local CratesView = {}

-- ---------------------------------------------------------------------------
-- Geometry
-- ---------------------------------------------------------------------------

local PAD = 18
local HEADER_H = 64
local RAIL_W = 300
local ROW_H = 82
local ROW_GAP = 6
local HERO_H = 288
local VIEW = 268
local ODDS_Y = 300
local ODDS_H = 96
local KEYS_Y = 408
local KEY_H = 62
local NOTE_Y = 478
local DECK_X = RAIL_W + 18

--- Same five hues the blade cards use, so "VOID 26%" here and a purple card in
--- the vault are the same fact.
local RARITY_COLOR: { [string]: Color3 } = {
	Scrap = Theme.Color.locked,
	Forged = Theme.Color.cyan,
	Astral = Theme.Color.quantum,
	Void = Theme.Color.magenta,
	Quantum = Theme.Color.gold,
}

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local root: Frame? = nil
local deck: Frame? = nil
local railPlate: Frame? = nil

local railRows: { [string]: TextButton } = {}
local selected = "standard"

--- Set by `Main`. The roll page does not require `ForgeView`: the anvil card and
--- the pool page are siblings, and the seam between them is this callback.
CratesView.onSelect = nil :: ((id: string) -> ())?

local viewport: ViewportFrame? = nil
local crateHandle: CratePreview.Handle? = nil
local mountedShape: string? = nil

local shortLabel: TextLabel? = nil
local nameLabel: TextLabel? = nil
local blurbLabel: TextLabel? = nil
local stateLabel: TextLabel? = nil
local costValue: TextLabel? = nil
local pityValue: TextLabel? = nil
local gateValue: TextLabel? = nil
local oddsHost: Frame? = nil

local rollOne: TextButton? = nil
local rollOneFace: TextLabel? = nil
local rollOneCost: TextLabel? = nil
local rollTen: TextButton? = nil
local rollTenFace: TextLabel? = nil
local rollTenCost: TextLabel? = nil
local noteLabel: TextLabel? = nil

--- Result plate, hidden until a roll lands.
local resultPlate: Frame? = nil
local resultShort: TextLabel? = nil
local resultName: TextLabel? = nil
local resultLine: TextLabel? = nil
local resultPower: TextLabel? = nil

local rolling = false
local rollToken = 0
local awaitingReveal = false
--- True once the crate's rattle has finished and the reveal may fire.
local crateOpen = false
local pendingResult: Types.FeedEvent? = nil

local unsubscribeEvent: (() -> ())? = nil

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

--- Picks the crate the page should start on: the server's, then standard.
local function adoptSelection()
	local state = StateStore.current
	if state and ForgeConfig.crate(state.forgeCrate) then
		selected = state.forgeCrate
	end
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
	view.Ambient = Color3.fromRGB(120, 112, 132)
	view.LightColor = Color3.fromRGB(255, 208, 158)
	view.LightDirection = Vector3.new(-0.5, -0.8, -0.4)
	crateHandle = CratePreview.mount(view, shape)
	mountedShape = shape
end

-- ---------------------------------------------------------------------------
-- Paint
-- ---------------------------------------------------------------------------

local function paintRail()
	local state = StateStore.current
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
			local chip = row:FindFirstChild("State")
			if chip and chip:IsA("TextLabel") then
				if not unlocked then
					chip.Text = if state
						then string.format("AT %s LIFETIME", NumberUtil.abbreviate(crate.unlock))
						else "LINKING"
					chip.TextColor3 = Theme.Color.locked
				elseif isSelected then
					chip.Text = "SELECTED"
					chip.TextColor3 = crate.accent
				else
					chip.Text = "OPEN"
					chip.TextColor3 = Theme.Color.textSecondary
				end
			end
			row.BackgroundTransparency = if unlocked then 0 else 0.35
		end
	end
end

--- Puts the crate's own card back in the info column: name, blurb, facts.
local function paintCrateInfo()
	if resultPlate then
		resultPlate.Visible = false
	end
	for _, label in { shortLabel, nameLabel, blurbLabel, stateLabel } do
		if label then
			label.Visible = true
		end
	end
end

local function paintOdds(crate: ForgeConfig.Tier)
	local host = oddsHost
	if host == nil then
		return
	end
	for _, child in host:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local width = deckWidth()
	local entries = ForgeConfig.odds(crate)

	local eye = UiKit.label(host, {
		text = "DROP ODDS",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.textFaint,
	})
	eye.Size = UDim2.fromOffset(200, 14)

	local pity = UiKit.label(host, {
		text = string.format("PITY %d ROLLS", crate.pity),
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Right,
	})
	pity.Position = UDim2.new(1, -220, 0, 0)
	pity.Size = UDim2.fromOffset(220, 14)

	-- One stacked bar, not five cards. Five equal cards said every outcome was
	-- equally likely; a single bar makes the 0.35% sliver look like what it is.
	-- Drawn common to rare, so the legend under it reads in the same order.
	local barY = 22
	local barH = 22
	local cursor = 0
	for index = #entries, 1, -1 do
		local entry = entries[index]
		local color = RARITY_COLOR[entry.rarity] or Theme.Color.text
		local px = math.max(math.floor(width * entry.chance), 2)
		local seg = plate(host, color, 1)
		seg.Name = "Seg_" .. entry.rarity
		seg.Position = UDim2.fromOffset(math.floor(cursor), barY)
		seg.Size = UDim2.fromOffset(px, barH)
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

	-- Legend: colour, name, chance. Five even columns under the bar.
	local columns = #entries
	local gap = 10
	local colW = math.floor((width - gap * (columns - 1)) / columns)
	for slot = 1, columns do
		local entry = entries[columns - slot + 1]
		local color = RARITY_COLOR[entry.rarity] or Theme.Color.text
		local x = (slot - 1) * (colW + gap)

		local dot = plate(host, color, 1)
		dot.Position = UDim2.fromOffset(x, 56)
		dot.Size = UDim2.fromOffset(8, 8)
		dot.ZIndex = 3

		local name = UiKit.label(host, {
			text = string.upper(entry.rarity),
			size = Theme.Text.Tiny,
			font = Theme.Font.Black,
			color = Theme.Color.textDim,
		})
		name.Position = UDim2.fromOffset(x + 14, 50)
		name.Size = UDim2.fromOffset(colW - 14, 14)

		local chance = UiKit.label(host, {
			text = string.format("%.2f%%", entry.chance * 100),
			size = Theme.Text.Tiny,
			font = Theme.Font.Numeric,
			color = Theme.Color.text,
		})
		chance.Position = UDim2.fromOffset(x + 14, 66)
		chance.Size = UDim2.fromOffset(colW - 14, 14)
	end
end

local function paintDeck()
	local crate = selectedCrate()
	local q = quote(crate.id)
	local state = StateStore.current

	if shortLabel then
		shortLabel.Text = crate.short
		shortLabel.TextColor3 = crate.accent
	end
	if nameLabel then
		nameLabel.Text = string.upper(crate.name)
	end
	if blurbLabel then
		blurbLabel.Text = crate.blurb
	end
	if stateLabel then
		stateLabel.Text = if q ~= nil
			then "OPEN"
			else string.format("NEEDS %s LIFETIME", NumberUtil.abbreviate(crate.unlock))
		stateLabel.TextColor3 = if q ~= nil then Theme.Color.emerald else Theme.Color.locked
	end
	if costValue then
		costValue.Text = if q then string.format("%s SM", NumberUtil.abbreviate(q.one)) else "--"
	end
	if pityValue then
		pityValue.Text = string.format("%d ROLLS", crate.pity)
	end

	if rollOne then
		local ready = q ~= nil and state ~= nil and state.sm >= q.one
		rollOne.BackgroundColor3 = if ready then Theme.Color.panelRaised else Theme.Color.slate
		local stroke = rollOne:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if ready then Theme.Color.strokeBright else Theme.Color.stroke
		end
		if rollOneFace then
			rollOneFace.Text = if q then "ROLL" else "LOCKED"
			rollOneFace.TextColor3 = if ready then Theme.Color.text else Theme.Color.locked
			rollOneFace.TextTransparency = if ready then 0 else 0.35
		end
		if rollOneCost then
			rollOneCost.Text = if q then string.format("%s SM", NumberUtil.abbreviate(q.one)) else "--"
			rollOneCost.TextColor3 = if ready then Theme.Color.textFaint else Theme.Color.locked
			rollOneCost.TextTransparency = if ready then 0 else 0.45
		end
	end

	if rollTen then
		local ready = q ~= nil and state ~= nil and state.sm >= q.ten
		local tint = crate.accent
		rollTen.BackgroundColor3 = if ready then tint else Theme.Color.slate
		local stroke = rollTen:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if ready then Theme.Color.outline else Theme.Color.stroke
		end
		if rollTenFace then
			rollTenFace.Text = if q then "ROLL x10" else "LOCKED"
			rollTenFace.TextColor3 = if ready then Theme.onColor(tint) else Theme.Color.locked
			rollTenFace.TextTransparency = if ready then 0 else 0.35
		end
		if rollTenCost then
			rollTenCost.Text = if q then string.format("%s SM", NumberUtil.abbreviate(q.ten)) else "--"
			rollTenCost.TextColor3 = if ready then Theme.onColor(tint) else Theme.Color.locked
			rollTenCost.TextTransparency = if ready then 0 else 0.45
		end
	end

	if noteLabel and not rolling then
		if q == nil then
			noteLabel.Text = string.format("This pool opens at %s lifetime Star-Matter.", NumberUtil.abbreviate(crate.unlock))
			noteLabel.TextColor3 = Theme.Color.locked
		elseif state then
			noteLabel.Text = string.format(
				"You hold %s Star-Matter. Pity forces Void or better every %d rolls on this pool.",
				NumberUtil.abbreviate(state.sm),
				crate.pity
			)
			noteLabel.TextColor3 = Theme.Color.textSecondary
		end
	end

	paintOdds(crate)
	paintRail()
end

local function pick(id: string)
	if ForgeConfig.crate(id) == nil or id == selected then
		return
	end
	selected = id
	Sfx.tab()
	rolling = false
	awaitingReveal = false
	crateOpen = false
	pendingResult = nil
	mountCrate(selectedCrate().shape)
	paintCrateInfo()
	paintDeck()
	-- The crate is profile state, not a per-roll argument: the server bills the
	-- ramp of whatever crate the profile is on, so the pick has to land before
	-- the press. Skipping this made the next sync paint the old pool back over
	-- the one the player had just chosen.
	StateStore.send("crate", id)
	local callback = CratesView.onSelect
	if callback then
		callback(selected)
	end
end

-- ---------------------------------------------------------------------------
-- Roll
-- ---------------------------------------------------------------------------

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
	local variant = if result and result.variant then ForgeConfig.variant(result.variant) else nil
	local tint = if variant then variant.color else crate.accent
	local batch = if result then math.max(1, math.floor(result.batch or 1)) else 1

	if viewport then
		Vfx.burst(viewport, tint, 1.35)
		Vfx.sparks(viewport, tint, 22, 1.7)
		Vfx.shockwave(viewport, tint, { size = 120, spread = 2.6, duration = 0.38, thickness = 4 })
	end
	Sfx.crateShatter()

	if result == nil or result.blade == nil then
		mountCrate(crate.shape)
		paintCrateInfo()
		paintDeck()
		return
	end

	local blade = BladeRegistry.get(result.blade)
	if blade and viewport then
		unmountCrate()
		BladePreview.thumbnail(viewport, blade, nil, tint)
	end

	if resultPlate then
		resultPlate.Visible = true
	end
	for _, label in { shortLabel, nameLabel, blurbLabel, stateLabel } do
		if label then
			label.Visible = false
		end
	end

	if resultName then
		local prefix = result.prefix or ""
		local suffix = result.suffix or ""
		local display = if blade then ModifierConfig.displayName(blade.name, prefix, suffix) else "A COPY"
		resultName.Text = string.upper(display)
	end
	if resultShort then
		local grade = if result.grade and result.grade ~= "" then ModifierConfig.grade(result.grade) else nil
		resultShort.Text = if batch > 1
			then string.format("%s COPIES  ·  BEST OF THE PULL", batch)
			else "JUST FORGED"
		resultShort.TextColor3 = if grade then grade.color else tint
	end
	if resultLine and blade then
		resultLine.Text = string.format(
			"%s  ·  %s",
			ForgeConfig.variant(result.variant or ForgeConfig.StandardVariant).name,
			blade.rarity
		)
	end
	if resultPower and blade and StateStore.current and StateStore.current.forgeCosts[crate.id] then
		resultPower.Text = string.format("PITY %d/%d  ·  NEXT %s SM", StateStore.current.forgePity, crate.pity, NumberUtil.abbreviate(StateStore.current.forgeCosts[crate.id].one))
		resultPower.TextColor3 = Theme.Color.textSecondary
	end

	paintDeck()
end

--- Presses the pool for `count` copies. One transaction: the server charges the
--- ramp price for the whole batch and reports the best copy back as one event.
function CratesView.roll(count: number?)
	local batch = math.clamp(math.floor(count or 1), 1, 10)
	if rolling then
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
	local price = if batch > 1 then q.ten else q.one
	if state.sm < price then
		Sfx.error()
		noteLabel.Text = string.format("Needs %s Star-Matter.", NumberUtil.abbreviate(price))
		noteLabel.TextColor3 = Theme.Color.red
		return false
	end

	rolling = true
	rollToken += 1
	local token = rollToken
	awaitingReveal = true
	crateOpen = false
	pendingResult = nil

	mountCrate(crate.shape)
	paintCrateInfo()

	if noteLabel then
		noteLabel.Text = if batch > 1
			then string.format("Rolling %d copies from %s.", batch, crate.name)
			else string.format("Rolling %s.", crate.name)
		noteLabel.TextColor3 = Theme.Color.textSecondary
	end

	if crateHandle then
		crateHandle.play(crate.accent, {
			onLanded = function()
				if token == rollToken then
					Sfx.crateLand()
				end
			end,
			onBeat = function(beat: number)
				if token == rollToken then
					Sfx.rollTick(beat)
				end
			end,
			onReady = function()
				if token ~= rollToken then
					return
				end
				-- The rattle is the wind-up. The answer may already be sitting in
				-- `pendingResult`; if it is not, the event handler fires the reveal
				-- the moment it lands.
				crateOpen = true
				if pendingResult ~= nil then
					revealNow()
				end
			end,
		})
	end

	StateStore.send("forge", { crate = crate.id, count = batch })
	paintDeck()
	return true
end

-- ---------------------------------------------------------------------------
-- Mount
-- ---------------------------------------------------------------------------

local function header(parent: Frame)
	local banner = UiKit.banner(parent, {
		text = "CRATE VAULT",
		subtitle = "FIVE POOLS  ·  ONE ROLL  ·  ODDS ON THE TABLE",
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

		local accent = plate(row, crate.accent, 2)
		accent.Size = UDim2.fromOffset(4, ROW_H)
		accent.ZIndex = 3

		local art = UiKit.create("Frame", {
			Name = "Art",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(14, (ROW_H - 40) / 2),
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
		name.Position = UDim2.fromOffset(66, 10)
		name.Size = UDim2.fromOffset(RAIL_W - 96, 20)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.ZIndex = 3

		local price = UiKit.label(row, {
			text = string.format("%s SM  ·  PITY %d", NumberUtil.abbreviate(crate.cost), crate.pity),
			size = Theme.Text.Tiny,
			font = Theme.Font.Numeric,
			color = Theme.Color.textSecondary,
		})
		price.Position = UDim2.fromOffset(66, 34)
		price.Size = UDim2.fromOffset(RAIL_W - 96, 16)
		price.ZIndex = 3

		local chip = UiKit.label(row, {
			text = "OPEN",
			size = Theme.Text.Tiny,
			font = Theme.Font.Label,
			color = Theme.Color.textSecondary,
		})
		chip.Name = "State"
		chip.Position = UDim2.fromOffset(66, 56)
		chip.Size = UDim2.fromOffset(RAIL_W - 96, 16)
		chip.ZIndex = 3

		UiKit.track(row, row.Activated:Connect(function()
			pick(crate.id)
		end))
		UiKit.track(row, row.MouseEnter:Connect(function()
			Sfx.hover()
		end))

		railRows[crate.id] = row
	end
end

--- A labelled fact row inside the hero's info column.
local function fact(parent: Frame, y: number, caption: string): TextLabel
	local key = UiKit.label(parent, {
		text = caption,
		size = Theme.Text.Tiny,
		font = Theme.Font.Label,
		color = Theme.Color.textFaint,
	})
	key.Position = UDim2.fromOffset(0, y)
	key.Size = UDim2.fromOffset(110, 22)

	local value = UiKit.label(parent, {
		text = "--",
		size = Theme.Text.Small,
		font = Theme.Font.Numeric,
		color = Theme.Color.text,
	})
	value.Position = UDim2.fromOffset(110, y)
	value.Size = UDim2.new(1, -110, 0, 22)
	return value
end

local function buildHero(parent: Frame)
	local hero = plate(parent, Theme.Color.panelSunken, Theme.Radius.md)
	hero.Name = "Hero"
	hero.Size = UDim2.new(1, 0, 0, HERO_H)
	UiKit.stroke(hero, Theme.Color.strokeFaint, Theme.Stroke.hair, 0.25)

	local view = UiKit.create("ViewportFrame", {
		Name = "Preview",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(10, (HERO_H - VIEW) / 2),
		Size = UDim2.fromOffset(VIEW, VIEW),
		ZIndex = 2,
	}) :: ViewportFrame
	view.ClipsDescendants = true
	view.Parent = hero
	viewport = view

	local infoX = VIEW + 22
	local info = UiKit.create("Frame", {
		Name = "Info",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(infoX, 16),
		Size = UDim2.fromOffset(620, HERO_H - 32),
	}) :: Frame
	info.Parent = hero

	local short = UiKit.label(info, {
		text = "STD",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.gold,
	})
	short.Position = UDim2.fromOffset(0, 0)
	short.Size = UDim2.fromOffset(300, 16)
	shortLabel = short

	local name = UiKit.label(info, {
		text = "STANDARD FORGE CRATE",
		size = Theme.Text.Heading,
		font = Theme.Font.Display,
		color = Theme.Color.text,
	})
	name.Position = UDim2.fromOffset(0, 18)
	name.Size = UDim2.new(1, -8, 0, 30)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel = name

	local blurb = UiKit.label(info, {
		text = "",
		size = Theme.Text.Small,
		font = Theme.Font.Body,
		color = Theme.Color.textSecondary,
	})
	blurb.Position = UDim2.fromOffset(0, 54)
	blurb.Size = UDim2.new(1, -12, 0, 40)
	blurb.TextWrapped = true
	blurb.TextYAlignment = Enum.TextYAlignment.Top
	blurbLabel = blurb

	costValue = fact(info, 104, "COST")
	pityValue = fact(info, 132, "PITY")
	gateValue = fact(info, 160, "STATE")
	stateLabel = gateValue

	-- Result plate. Sits in the same column as the crate's own facts, so the
	-- answer to a roll replaces the promise of one instead of stacking on it.
	local result = plate(info, Theme.Color.panelRaised, Theme.Radius.sm)
	result.Name = "Result"
	result.Size = UDim2.new(1, -8, 0, 196)
	result.Visible = false
	UiKit.stroke(result, Theme.Color.stroke, Theme.Stroke.hair, 0.1)
	resultPlate = result

	local rShort = UiKit.label(result, {
		text = "JUST FORGED",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.emerald,
	})
	rShort.Position = UDim2.fromOffset(14, 10)
	rShort.Size = UDim2.new(1, -28, 0, 16)
	resultShort = rShort

	local rName = UiKit.label(result, {
		text = "",
		size = Theme.Text.Subheading,
		font = Theme.Font.Display,
		color = Theme.Color.text,
	})
	rName.Position = UDim2.fromOffset(14, 30)
	rName.Size = UDim2.new(1, -28, 0, 52)
	rName.TextWrapped = true
	rName.TextYAlignment = Enum.TextYAlignment.Top
	resultName = rName

	local rLine = UiKit.label(result, {
		text = "",
		size = Theme.Text.Small,
		font = Theme.Font.Body,
		color = Theme.Color.textSecondary,
	})
	rLine.Position = UDim2.fromOffset(14, 88)
	rLine.Size = UDim2.new(1, -28, 0, 20)
	resultLine = rLine

	local rPower = UiKit.label(result, {
		text = "",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.textSecondary,
	})
	rPower.Position = UDim2.fromOffset(14, 112)
	rPower.Size = UDim2.new(1, -28, 0, 16)
	resultPower = rPower

	-- Scan line: a two-pixel band under the name that reads as the crate's pulse
	-- while it is sealed and as the copy's rarity once it is open.
	local pulse = plate(result, Theme.Color.emerald, 2)
	pulse.Position = UDim2.fromOffset(14, 150)
	pulse.Size = UDim2.new(1, -28, 0, 3)
	pulse.BackgroundTransparency = 0.4
	pulse.ZIndex = 3
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
	face.Position = UDim2.fromOffset(0, 9)
	face.Size = UDim2.new(1, 0, 0, 22)
	face.ZIndex = 2

	local cost = UiKit.label(button, {
		text = "--",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = if primary then Theme.onColor(fill) else Theme.Color.textFaint,
		align = Enum.TextXAlignment.Center,
	})
	cost.Position = UDim2.fromOffset(0, 34)
	cost.Size = UDim2.new(1, 0, 0, 16)
	cost.ZIndex = 2

	UiKit.track(button, button.MouseEnter:Connect(function()
		Sfx.hover()
		UiKit.tween(button, Theme.Duration.fast, { BackgroundColor3 = fill:Lerp(Theme.Color.white, 0.08) })
	end))
	UiKit.track(button, button.MouseLeave:Connect(function()
		UiKit.tween(button, Theme.Duration.normal, { BackgroundColor3 = fill })
	end))
	return button, face, cost
end

local function buildKeys(parent: Frame)
	local gap = 10
	-- 40 / 60 split. The ten-pull is the real purchase on this page; the single
	-- key exists for players who cannot afford ten yet, and it should look like it.
	local oneW = math.floor((deckWidth() - gap) * 0.4)
	local tenW = deckWidth() - gap - oneW

	rollOne, rollOneFace, rollOneCost = buildKey(parent, "RollOne", 0, oneW, Theme.Color.starMatter, false)
	UiKit.track(rollOne, rollOne.Activated:Connect(function()
		CratesView.roll(1)
	end))

	rollTen, rollTenFace, rollTenCost = buildKey(parent, "RollTen", oneW + gap, tenW, Theme.Color.starMatter, true)
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
	paintCrateInfo()
	paintDeck()

	unsubscribeEvent = StateStore.onEvent(function(event: Types.FeedEvent)
		if event.kind ~= "forged" then
			return
		end
		-- A roll on the anvil is not this page's business. Only the pull this page
		-- started owns the reveal.
		if not awaitingReveal then
			return
		end
		pendingResult = event
		if crateOpen then
			revealNow()
		end
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
		-- The chips are rebuilt from the new width rather than scaled, so the
		-- percentage text keeps its own size.
		paintOdds(selectedCrate())
	end
	if rollOne and rollTen and deck then
		local gap = 10
		local oneW = math.floor((deckWidth() - gap) * 0.4)
		local tenW = deckWidth() - gap - oneW
		rollOne.Size = UDim2.fromOffset(oneW, KEY_H)
		rollTen.Position = UDim2.fromOffset(oneW + gap, KEYS_Y)
		rollTen.Size = UDim2.fromOffset(tenW, KEY_H)
	end
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
			if viewport then
				mountCrate(selectedCrate().shape)
			end
		end
	end
	if not root.Visible then
		return
	end
	-- The server is authoritative about which pool the ramp belongs to. Once the
	-- page is idle, follow it: a stale local pick after a rejected roll would leave
	-- the page pricing a crate the server is not on.
	if not rolling and ForgeConfig.crate(payload.forgeCrate) and payload.forgeCrate ~= selected then
		selected = payload.forgeCrate
		mountCrate(selectedCrate().shape)
		paintCrateInfo()
	end
	-- While the crate is in the air the page is showing its own note, and
	-- repainting the deck underneath would overwrite the roll's status line.
	if rolling then
		return
	end
	local note = noteLabel
	if note and payload.forgeCosts[selected] == nil then
		note.Text = string.format("This pool opens at %s lifetime Star-Matter.", NumberUtil.abbreviate(selectedCrate().unlock))
		note.TextColor3 = Theme.Color.locked
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
	unmountCrate()
	if root then
		root:Destroy()
		root = nil
	end
	table.clear(railRows)
	deck = nil
	railPlate = nil
	viewport = nil
	shortLabel = nil
	nameLabel = nil
	blurbLabel = nil
	stateLabel = nil
	costValue = nil
	pityValue = nil
	gateValue = nil
	oddsHost = nil
	rollOne = nil
	rollOneFace = nil
	rollOneCost = nil
	rollTen = nil
	rollTenFace = nil
	rollTenCost = nil
	noteLabel = nil
	resultPlate = nil
	resultShort = nil
	resultName = nil
	resultLine = nil
	resultPower = nil
	adoptSelection()
	rolling = false
	awaitingReveal = false
	pendingResult = nil
end

adoptSelection()

return CratesView
