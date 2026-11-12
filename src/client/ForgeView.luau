--!strict
-- The forge: the one screen the player actually looks at.
--
-- Layout is authored against the 1280x720 design canvas (see Theme). Everything
-- below the viewport is anchored from the top in pixels and the panel itself is
-- anchored to the bottom edge, so it stretches correctly on any aspect ratio
-- without a single constraint object.
--
-- The strike button is deliberately enormous. In a clicker, the primary input
-- should be impossible to miss with a thumb on a phone.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local NumberUtil = require(Shared:WaitForChild("NumberUtil"))
local BladeRegistry = require(Shared:WaitForChild("BladeRegistry"))
local ForgeConfig = require(Shared:WaitForChild("ForgeConfig"))
local ModifierConfig = require(Shared:WaitForChild("ModifierConfig"))
local Types = require(Shared:WaitForChild("Types"))

local Theme = require(script.Parent.Theme)
local Layout = require(script.Parent.Layout)
local UiKit = require(script.Parent.UiKit)
local StageBackdrop = require(script.Parent.StageBackdrop)
local StateStore = require(script.Parent.StateStore)
local BladePreview = require(script.Parent.BladePreview)
local CratePreview = require(script.Parent.CratePreview)
local Vfx = require(script.Parent.Vfx)
local SpriteFx = require(script.Parent.SpriteFx)
local Notifications = require(script.Parent.Notifications)
local Sfx = require(script.Parent.Sfx)

local ForgeView = {}

--- Set by whoever wants to observe real, accepted strikes (the onboarding guide
--- does). Fires after the local guards pass, so a rejected tap never counts as
--- progress. Kept as a field rather than a listener registry because there is
--- exactly one consumer.
ForgeView.onStrike = nil :: (() -> ())?

local root: Frame? = nil
local viewport: ViewportFrame? = nil
local bladeName: TextLabel? = nil
local bladeFlavor: TextLabel? = nil
local multChip: TextLabel? = nil

local heatBlock: Frame? = nil
local heatLabel: TextLabel? = nil
local heatStatus: TextLabel? = nil
local heatTrackStroke: UIStroke? = nil
local heatBand: Frame? = nil
local heatPenalty: Frame? = nil
local heatFill: Frame? = nil
local heatFillGradient: UIGradient? = nil
local heatVentTick: Frame? = nil
local heatLeanTick: Frame? = nil
local heatNeedle: Frame? = nil
local heatBandLabel: TextLabel? = nil
--- True while the coach notes hold the gauge for the purge lesson. The server
--- is the authority; this stops the local prediction from racing past 85 while
--- the player reads.
local heatHold = false

local strikeButton: TextButton? = nil
local strikeFlash: Frame? = nil
local strikeHint: TextLabel? = nil

-- Roll column. `rolling` is the in-flight flag that keeps a second press from
-- stacking a second sequence, and `pendingRoll` is where the server's answer
-- waits until the crate has finished its wind-up.
local rollButton: TextButton? = nil
local rollCostLabel: TextLabel? = nil
local pityFill: Frame? = nil
--- The `SCRAP n · PITY n/m` footer under the roll column.
local rollFooter: TextLabel? = nil
--- Batch key and crate key, stacked to the right of ROLL. The batch key buys ten
--- at the ramp price; the crate key opens the browser. Both are small because the
--- card's job is the strike, and the gacha page is where the decision lives.
local batchButton: TextButton? = nil
local batchLabel: TextLabel? = nil
local crateChip: TextButton? = nil
local crateChipLabel: TextLabel? = nil
--- Which pool the next quick roll buys. The payload is authoritative; this is the
--- local selection so a crate picked in the browser survives until the sync
--- confirms it, and so the Studio seam can drive it without a server round trip.
local selectedCrate = ""
local crateViewport: ViewportFrame? = nil
local crateHandle: CratePreview.Handle? = nil
local crateStage: Frame? = nil
local rolling = false
local rollToken = 0
local pendingRoll: { blade: string?, variant: string?, element: string?, grade: string?, batch: number? }? = nil
--- Studio diagnostic: the reason the last `roll` call did not start, or the
--- phase it reached. A silent no-op is indistinguishable from a dropped remote
--- without it.
local lastRollNote = "none"
local comboChip: TextLabel? = nil
local comboText: string? = nil
-- Streak rail: ten pips and one line, inside the anvil plate's bottom band.
local streakLabel: TextLabel? = nil
local streakPips: { Frame } = {}
local streakLit = -1
local streakText: string? = nil
-- Overdrive edge detection. The window opens on a server sync, so the client
-- sees it as a transition rather than as a click; remembering the previous
-- value is the only way to fire the burst exactly once.
local lastOverdrive = 0
-- The stage border. Warm when the gauge is near the band, gold while the rail
-- is full, danger-red on a burn-out. Held as a handle so the breathe pass in
-- `step` can pulse it without re-finding it every frame.
-- Thermal vent. It is a key on the right end of the heat rail, not a separate
-- row: the threshold, the payout and the control all live on the gauge the
-- player is already watching.
local ventPill: TextButton? = nil
local ventPillStroke: UIStroke? = nil
local ventPillFill: Frame? = nil
local ventPillLabel: TextLabel? = nil
local ventPillDetail: TextLabel? = nil
local ventReady = false
local ventLabelText: string? = nil
local ventDetailText: string? = nil

-- Stage: the viewport itself is scale-punched on a hit. The colour wash that
-- used to live on top of it is now a screen event in `Vfx`, so this frame only
-- owns the punch and the clip.
local viewportScale: UIScale? = nil

-- The strike caption on the deck. The whole stage is the hit target; this only
-- names the verb and the payout, so removing it never removes the click.

-- The stage wash behind the blade. One handle: repainting a tier is two colours
-- on the same layers, not a rebuild.
local backdrop: StageBackdrop.Handle? = nil

-- Orbit controller for the hero blade, handed back by `BladePreview.mount` so
-- the strike handler can read how far the pointer travelled.
type OrbitHandle = { dragTravel: number, dragging: boolean, cameraYaw: number, cameraPitch: number }
local previewOrbit: OrbitHandle? = nil

-- Strike cadence, and the glow level the render pass asked for. `step` only
-- breathes around that level; it never decides it.
local strikeTimes: { number } = {}
local comboTimer = 0

-- Showcase window after a forge. While it is open, `ensureBlade` refuses to swap
-- the model, which is what lets a newly forged (but weaker, therefore not
-- auto-equipped) blade stay on screen for a couple of seconds.
local showcaseToken = 0
local showcaseUntil = 0
--- What the player had equipped when the showcase opened. Used to tell "the
--- sync is just repeating itself" apart from "the player equipped something
--- else while the fireworks were still running".
local showcaseEquipped: string? = nil

-- The aura is the only looping sprite: it lives while the blade is inside the
-- heat band and is retired the moment it leaves.
local auraHandle: SpriteFx.Handle? = nil
local auraOn = false

local currentBladeId: string? = nil
local currentVariantId: string? = nil
local cleanupPreview: (() -> ())? = nil
local stopEmbers: (() -> ())? = nil
local unlocked = false

local state: Types.SyncPayload? = nil
local unsubscribe: (() -> ())? = nil

-- ---------------------------------------------------------------------------
-- Heat colour ramp
-- ---------------------------------------------------------------------------

local function lerpColor(a: Color3, b: Color3, t: number): Color3
	return Color3.new(
		a.R + (b.R - a.R) * t,
		a.G + (b.G - a.G) * t,
		a.B + (b.B - a.B) * t
	)
end

--- Maps 0..100 heat onto the gauge ramp: cold blue, green through the sweet
-- spot, orange, then red as it approaches the lockout.
local function heatColor(heat: number, bandMin: number, bandMax: number): Color3
	if heat <= bandMin then
		local t = if bandMin <= 0 then 0 else heat / bandMin
		return lerpColor(Theme.Color.heatCool, Theme.Color.heatSweet, t)
	elseif heat <= bandMax then
		return Theme.Color.heatSweet
	end

	local t = math.clamp((heat - bandMax) / math.max(1, 100 - bandMax), 0, 1)
	return lerpColor(Theme.Color.heatSweet, Theme.Color.heatCritical, t)
end

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------

local bladeSubtitle: TextLabel? = nil

local function buildHeader(parent: Frame)
	-- Title block: name over rarity, flush left on a flat plate. The roll column
	-- lives to the right of it, so the plate stops 268px short rather than
	-- running under the keys.
	local banner = UiKit.banner(parent, {
		text = "RUSTED CLEAVER",
		subtitle = "SCRAP",
		position = UDim2.fromOffset(0, 0),
		width = UDim2.new(1, 0, 0, 64),
		height = 64,
		size = Theme.Text.Title - 4,
		accent = Theme.Color.gold,
	})
	banner.Name = "BladeBanner"

	local title = banner:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		bladeName = title
	end
	local subtitle = banner:FindFirstChild("Subtitle")
	if subtitle and subtitle:IsA("TextLabel") then
		bladeSubtitle = subtitle
	end

	local chip = UiKit.badge(banner, {
		text = "x1.00",
		color = Theme.Color.starMatter,
		width = 92,
		height = 26,
		size = Theme.Text.Tiny,
	})
	chip.Name = "MultChip"
	chip.Position = UDim2.new(1, -104, 0.5, -13)
	local chipFace = chip:FindFirstChild("Face")
	if chipFace and chipFace:IsA("TextLabel") then
		chipFace.Font = Theme.Font.Numeric
		multChip = chipFace
	end
end

--- The roll stage: a single transparent viewport holding the real 3D crate.
---
--- There used to be a sunken dais with three concentric halos underneath, which
--- is what the report caught as "a 2D circle behind the crate". At Cosmic the
--- tier colour is green, so the plate read as a UI element rather than as ground,
--- and the crate was fighting a bright shape it could never occlude. The viewport
--- is transparent and the crate carries its own light, so the stage is now empty
--- until the box drops into it.
local function buildCrate(stage: Frame)
	-- 300px square so a 4-unit crate at a 40 degree field of view has margin to
	-- fall into.
	local view = UiKit.create("ViewportFrame", {
		Name = "CrateViewport",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(300, 300),
		Visible = false,
		ZIndex = 6,
	}) :: ViewportFrame
	view.Parent = stage
	crateViewport = view
	crateHandle = CratePreview.mount(view)
end

--- Shows the crate stage. Called before the crate drops, so the viewport is live
--- when the first frame of the fall renders.
local function paintCrateStage(_tierIndex: number)
	local view = crateViewport
	if view then
		view.Visible = true
	end
end

local function buildViewport(parent: Frame)
	-- The stage owns everything from under the banner to the bottom of the card.
	-- It used to stop at 230px and leave the heat rail and a 144px STRIKE plate
	-- stacked underneath, which is the "black box" the player sees between the
	-- blade and the bottom edge. The render is now the whole column; the gauge
	-- and the streak rail are painted onto it as an instrument strip.
	local frame = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.void,
		BorderSizePixel = 0,
		-- Title block 64, gap 8, stage to the bottom edge.
		Size = UDim2.new(1, 0, 1, -72),
		Position = UDim2.fromOffset(0, 72),
		ClipsDescendants = true,
	}) :: Frame
	UiKit.corner(frame, Theme.Radius.md)
	UiKit.stroke(frame, Theme.Color.stroke, Theme.Stroke.hair, 0)
	UiKit.gradient(frame, { Theme.Color.void, Theme.Color.panelSunken }, 90)
	frame.Parent = parent

	-- Forge backdrop. A flat black rectangle makes even a good blade read as a
	-- placeholder, so the stage gets a warm pool under the blade, a cool rim
	-- behind the tip, and a faint grid for depth. All procedural: no asset, no
	-- upload step, and it costs nine frames.
	local grid = UiKit.create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		ZIndex = 1,
	}) :: Frame
	grid.Parent = frame
	for index = 1, 7 do
		local line = UiKit.create("Frame", {
			BackgroundColor3 = Theme.Color.strokeBright,
			BackgroundTransparency = 0.93,
			BorderSizePixel = 0,
			Size = UDim2.new(0, 1, 1, 0),
			Position = UDim2.fromScale(index / 8, 0),
			ZIndex = 1,
		}) :: Frame
		line.Parent = grid
	end
	for index = 1, 4 do
		local line = UiKit.create("Frame", {
			BackgroundColor3 = Theme.Color.strokeBright,
			BackgroundTransparency = 0.94,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 1),
			Position = UDim2.fromScale(0, index / 5),
			ZIndex = 1,
		}) :: Frame
		line.Parent = grid
	end

	-- The wash. A `UIGradient` interpolates on one axis only, so the radial
	-- look is a base ramp plus four crossed light bands, each transparent at
	-- both ends: where they overlap the colours add up under the blade, and the
	-- corners stay dark. Replaces the stack of solid circles, which had a hard
	-- edge at every step. Colours come from the tier through `paintBackdrop`.
	local palette = Theme.tierBackdrop(1)
	backdrop = StageBackdrop.paint(frame, {
		warm = palette.warm,
		cool = palette.cool,
		radius = Theme.Radius.md,
		zIndex = 0,
	})

	viewport = UiKit.create("ViewportFrame", {
		Name = "BladeViewport",
		BackgroundTransparency = 1,
		-- Full bleed. The camera solve in `BladePreview` fills the frame height,
		-- so a taller stage makes the blade itself bigger rather than leaving a
		-- bigger empty stage around the same sword.
		Size = UDim2.fromScale(1, 1),
		-- Warm key from the upper left, cool violet fill: the two-tone split is
		-- what separates a metal edge from a metal face without a second light.
		Ambient = Color3.fromRGB(96, 108, 156),
		LightColor = Color3.fromRGB(255, 186, 118),
		LightDirection = Vector3.new(-0.55, -0.75, -0.45),
		ZIndex = 2,
	}) :: ViewportFrame
	viewport.Parent = frame

	-- Punch scale lives on the viewport, inside the clipped stage frame: at 1.04
	-- it grows into the clip instead of over the heat gauge.
	local punch = UiKit.create("UIScale", { Scale = 1 }) :: UIScale
	punch.Parent = viewport
	viewportScale = punch

	-- No stage-local wash. Every beat that used to draw here now calls
	-- `Vfx.flash`, which paints on its own full-screen layer. A wash clipped to
	-- the viewport was the reason the forge white and the crit gold stopped at
	-- the canvas edge instead of reading as a screen event.

	bladeFlavor = UiKit.label(frame, {
		text = "",
		size = Theme.Text.Micro,
		color = Theme.Color.textSecondary,
		align = Enum.TextXAlignment.Left,
		wrap = true,
	})
	bladeFlavor.Size = UDim2.new(1, -360, 0, 18)
	bladeFlavor.Position = UDim2.fromOffset(18, 14)
	bladeFlavor.ZIndex = 6

	-- Roll stage. Sits above the blade viewport and below the flash, so the crate
	-- covers the blade while it is winding up and the reveal wash still lands on
	-- top of both. Clipped like the rest of the stage.
	local crateLayer = UiKit.create("Frame", {
		Name = "CrateStage",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		ZIndex = 5,
	}) :: Frame
	crateLayer.Parent = frame
	crateStage = crateLayer
	buildCrate(crateLayer)

	return frame
end

local function buildHeat(parent: Frame)
	-- Heat dial. A number, a slim ruled bar and one caption, floating over the
	-- render between the two keys. The bar is 12px: it shows the band and the
	-- penalty edge, and it does not turn the stage into a form.
	local block = UiKit.create("Frame", {
		Name = "HeatBlock",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, -92),
		Size = UDim2.fromOffset(380, 78),
		ZIndex = 7,
	}) :: Frame
	block.Parent = parent
	heatBlock = block

	heatLabel = UiKit.label(block, {
		text = "CORE HEAT",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Center,
	})
	heatLabel.Size = UDim2.new(1, 0, 0, 14)

	heatStatus = UiKit.label(block, {
		text = "0%",
		size = Theme.Text.Title,
		font = Theme.Font.Numeric,
		color = Theme.Color.textDim,
		align = Enum.TextXAlignment.Center,
	})
	heatStatus.Size = UDim2.new(1, 0, 0, Theme.Text.Title + 4)
	heatStatus.Position = UDim2.fromOffset(0, 12)

	heatBandLabel = UiKit.label(block, {
		text = "",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Center,
	})
	heatBandLabel.Size = UDim2.new(1, 0, 0, 14)
	heatBandLabel.Position = UDim2.fromOffset(0, 64)

	local track = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.panelSunken,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.fromOffset(380, 12),
		Position = UDim2.fromOffset(0, 50),
	}) :: Frame
	UiKit.corner(track, Theme.Radius.sm)
	heatTrackStroke = UiKit.stroke(track, Theme.Color.stroke, Theme.Stroke.hair, 0)
	track.Parent = block
	track.Name = "HeatGauge"

	-- Sweet-spot band, drawn under the fill so it shows wherever heat has not
	-- reached yet. Green is the one place on this screen where a colour means a
	-- rule rather than a style.
	heatBand = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.heatSweet,
		BackgroundTransparency = 0.8,
		BorderSizePixel = 0,
		Size = UDim2.fromScale((Config.SweetSpotMax - Config.SweetSpotMin) / 100, 1),
		Position = UDim2.fromScale(Config.SweetSpotMin / 100, 0),
	}) :: Frame
	heatBand.Parent = track

	-- Penalty edge. Past this the core runs lean and every strike pays half, so
	-- the last tenth of the bar is a red zone the player has to leave. It is a
	-- rule they can see, not a lockout they have to wait out.
	heatPenalty = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.danger,
		BackgroundTransparency = 0.72,
		BorderSizePixel = 0,
		Size = UDim2.fromScale((100 - Config.PenaltyFrom) / 100, 1),
		Position = UDim2.fromScale(Config.PenaltyFrom / 100, 0),
	}) :: Frame
	heatPenalty.Parent = track

	-- The lean point gets its own full-height tick. The decade ticks and the
	-- filled red zone tell the player where they are; this tells them where the
	-- rule changes, before they cross it. The gauge caption names the multiplier
	-- once they are past it.
	local leanTick = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.danger,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 2, 1, 0),
		Position = UDim2.fromScale(Config.PenaltyFrom / 100, 0),
		ZIndex = 3,
	}) :: Frame
	leanTick.Parent = track
	heatLeanTick = leanTick

	heatFill = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.white,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
	}) :: Frame
	heatFillGradient = UiKit.gradient(heatFill, { Theme.Color.heatCool, Theme.Color.heatSweet }, 0)
	heatFill.Parent = track

	-- Decade ticks. Unmarked bars read as "fill up"; a ruled bar reads as an
	-- instrument, and 65/85/90 become positions instead of guesses.
	for step = 1, 9 do
		local tick = UiKit.create("Frame", {
			BackgroundColor3 = Theme.Color.strokeBright,
			BackgroundTransparency = if step % 5 == 0 then 0.5 else 0.8,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(1, if step % 5 == 0 then 7 else 4),
			Position = UDim2.fromScale(step / 10, 1),
			AnchorPoint = Vector2.new(0, 1),
			ZIndex = 2,
		}) :: Frame
		tick.Parent = track
	end

	-- Vent threshold tick: the line the player is aiming for.
	heatVentTick = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.warn,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 2, 1, 0),
		Position = UDim2.fromScale(Config.VentThreshold / 100, 0),
		ZIndex = 4,
	}) :: Frame
	heatVentTick.Parent = track

	-- Where the heat actually is this instant.
	heatNeedle = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.text,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 2, 1, 4),
		Position = UDim2.fromOffset(0, -2),
		ZIndex = 6,
	}) :: Frame
	UiKit.corner(heatNeedle, 1)
	heatNeedle.Parent = track

	-- Thermal vent key, bolted to the right end of the strip.
	--
	-- It has two jobs and they must not look alike. Below the threshold it is a
	-- flat slate key that names the threshold; at 85% it turns into a solid
	-- cyan plate carrying the payout. Same footprint, so the deck never shifts
	-- and the player never has to hunt for it in a new place.
	local vent = UiKit.create("TextButton", {
		Name = "VentStrip",
		BackgroundColor3 = Theme.Color.slate,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromOffset(136, 64),
		Position = UDim2.new(1, -152, 1, -84),
		ZIndex = 8,
	}) :: TextButton
	UiKit.corner(vent, Theme.Radius.md)
	ventPillStroke = UiKit.stroke(vent, Theme.Color.stroke, Theme.Stroke.thin, 0)
	vent.Parent = parent
	ventPill = vent

	ventPillFill = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.actionCyan,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 1,
	}) :: Frame
	UiKit.corner(ventPillFill, Theme.Radius.md)
	ventPillFill.Parent = vent

	ventPillLabel = UiKit.label(vent, {
		text = "VENT",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.locked,
		align = Enum.TextXAlignment.Center,
	})
	ventPillLabel.Position = UDim2.fromOffset(0, 12)
	ventPillLabel.Size = UDim2.new(1, 0, 0, 16)
	ventPillLabel.ZIndex = 3

	ventPillDetail = UiKit.label(vent, {
		text = string.format("%d%% TO UNLOCK", Config.VentThreshold),
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.locked,
		align = Enum.TextXAlignment.Center,
		wrap = true,
	})
	ventPillDetail.Position = UDim2.fromOffset(4, 30)
	ventPillDetail.Size = UDim2.new(1, -8, 0, 32)
	ventPillDetail.ZIndex = 3

	vent.Activated:Connect(function()
		local current = state
		if current == nil then
			return
		end
		local canVent = current.heat >= Config.VentThreshold
		if not canVent then
			-- A tap on the locked key explains itself instead of doing nothing.
			Notifications.push(
				string.format("Vent unlocks at %d%% core heat", Config.VentThreshold),
				"warn"
			)
			return
		end
		Sfx.vent()
		-- The plume rises out of the key into the viewport, which is where the
		-- heat it is dumping came from.
		if not SpriteFx.play(vent, "vent", Theme.Color.aether, { size = 320 }) then
			Vfx.burst(vent, Theme.Color.aether, 1.4)
		end
		StateStore.send("vent")
	end)
end

--- Paints the instrument strip onto the 3D stage and turns the whole render into
--- the strike target.
---
--- Nothing sits on a plate: the render runs to the bottom edge, and the strike
--- caption, the heat dial and the purge key float over it. A solid deck across
--- the bottom covered a fifth of the blade, which is the one thing on this
--- screen worth looking at.
local function buildHud(parent: Frame)
	-- No strike plate. There was a 240x64 orange key in this corner, and it was
	-- the only saturated rectangle on a screen whose subject is a blade: the eye
	-- went to the button, not the sword, and a key that duplicates the whole
	-- stage behind it says the render is not clickable when it is.
	--
	-- The stage itself is the button (see the StrikeButton below). What is left
	-- here is the caption: the verb, and what the next press pays.
	strikeHint = UiKit.label(parent, {
		text = "",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Left,
	})
	strikeHint.Name = "StrikeHint"
	strikeHint.Position = UDim2.new(0, 18, 1, -42)
	strikeHint.Size = UDim2.fromOffset(300, 18)
	strikeHint.ZIndex = 7

	-- Top-right readout stack: cadence, then the streak. Both are live numbers
	-- and both are secondary to the blade, so they sit in the stage's empty
	-- upper corner instead of on plates.
	comboChip = UiKit.label(parent, {
		text = "",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Right,
	})
	comboChip.Size = UDim2.fromOffset(320, 16)
	comboChip.Position = UDim2.new(1, -338, 0, 16)
	comboChip.ZIndex = 7

	-- Streak rail: ten pips and one line. A row of pips rather than a bar because
	-- the question the player is asking is "how many more", and a bar answers
	-- "how much" instead.
	local rail = UiKit.create("Frame", {
		Name = "StreakRail",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(320, 20),
		Position = UDim2.new(1, -338, 0, 40),
		ZIndex = 7,
	}) :: Frame
	rail.Parent = parent

	streakLabel = UiKit.label(rail, {
		text = string.format("STREAK 0/%d", Config.StreakForOverdrive),
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Left,
	})
	streakLabel.Size = UDim2.fromOffset(150, 20)
	streakLabel.ZIndex = 8

	-- Right-aligned pip block: 10 * 14 + 9 * 4 = 176 wide.
	local pipW, pipGap = 14, 4
	local totalW = Config.StreakForOverdrive * pipW + (Config.StreakForOverdrive - 1) * pipGap
	for index = 1, Config.StreakForOverdrive do
		local pip = UiKit.create("Frame", {
			Name = string.format("Pip%d", index),
			BackgroundColor3 = Theme.Color.stroke,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(pipW, 7),
			Position = UDim2.new(1, -(totalW - (index - 1) * (pipW + pipGap)), 0.5, -3),
			ZIndex = 8,
		}) :: Frame
		UiKit.corner(pip, 3)
		pip.Parent = rail
		streakPips[index] = pip
	end

	-- Press flash: a white wash that fires and immediately fades. Full bleed and
	-- rounded to the stage, so it reads as the render reacting rather than as a
	-- square appearing.
	strikeFlash = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.text,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
	}) :: Frame
	UiKit.corner(strikeFlash, Theme.Radius.md)
	strikeFlash.Parent = parent

	-- The hit layer. Transparent, full bleed, above the render and below every
	-- HUD element, so the vent key still wins its own clicks.
	local button = UiKit.create("TextButton", {
		Name = "StrikeButton",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
	}) :: TextButton
	button.Parent = parent
	strikeButton = button

	-- InputBegan rather than Activated: Activated fires on release, which adds
	-- up to a full click of latency on every strike. This feels instant.
	button.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			ForgeView.strike()
		end
	end)
end


-- ---------------------------------------------------------------------------
-- Stage feedback
-- ---------------------------------------------------------------------------

--- Scale-punch on the blade. The stage frame clips it, so this never disturbs
--- the heat gauge below.
local function punchViewport(strength: number)
	if viewportScale == nil or Theme.reducedMotion() then
		return
	end
	viewportScale.Scale = 1 + 0.04 * strength
	UiKit.tween(viewportScale, 0.2, { Scale = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
end

--- The hit gesture on the anvil itself. The plate is a full-width child of the
--- forge card, so it never moves: the jitter runs on the inset content layer and
--- the card's own outline stays put. `strength` scales travel and settle, which
--- is how a crit reads as heavier than a click without a second animation path.
---
--- The viewport shake is now mirrored by a smaller whole-HUD shake. The stage is
--- clipped, so a few pixels there read as the blade rattling inside its window;
--- the canvas shake is what makes the hit felt across the screen.
function ForgeView.punch(strength: number?)
	if Theme.reducedMotion() then
		return
	end
	local amount = math.clamp(strength or 1, 0.5, 2.5)
	if viewport then
		-- Kept moderate on purpose: the viewport is full-bleed inside a clipped
		-- frame, so a large offset exposes the frame edge behind the blade.
		Vfx.shake(viewport, 6 * amount, 0.15 + 0.05 * amount)
	end
	Vfx.shakeScreen(3.5 + 3.5 * amount, 0.16 + 0.05 * amount)
end

--- Wash over the screen. `hold` is the fade length; a strike wants a short
--- pulse, a forge wants a longer bloom. This is `Vfx.flash`, not a frame on the
--- stage: the stage is clipped to the viewport, so a wash there stops at the
--- canvas edge and reads as a rectangle instead of a flash.
local function screenFlash(color: Color3, peak: number, hold: number)
	Vfx.flash(color, peak, hold)
end

--- Records a strike for the cadence readout and drops the stale end of the
--- window. Two seconds is long enough to bridge a human click rate and short
--- enough that stopping is noticed within a beat.
local function recordStrike()
	local now = os.clock()
	strikeTimes[#strikeTimes + 1] = now
	local cutoff = now - 2
	while #strikeTimes > 0 and strikeTimes[1] < cutoff do
		table.remove(strikeTimes, 1)
	end
end

-- ---------------------------------------------------------------------------
-- Strike
-- ---------------------------------------------------------------------------

function ForgeView.strike()
	if not unlocked then
		return
	end

	local current = state
	if current == nil then
		return
	end

	if ForgeView.onStrike then
		ForgeView.onStrike()
	end

	local blade = BladeRegistry.get(current.equipped)
	local rarityIndex = if blade then blade.tier else 1
	local tint = Theme.rarityColor(rarityIndex)
	local crit = false

	-- Prediction: mirror the server's strike maths exactly. If we predicted the
	-- base yield while the player was standing in the sweet spot, every click
	-- would visibly snap upward ~100ms later, which reads as lag.
	local predicted = current.clickYield
	if current.inSweetSpot then
		predicted *= current.bandMult
	end
	StateStore.predictClick(predicted, crit)

	if strikeFlash then
		strikeFlash.BackgroundTransparency = 0.72
		UiKit.tween(strikeFlash, 0.22, { BackgroundTransparency = 1 })
	end

	if viewport then
		ForgeView.punch(if current.inSweetSpot then 1.7 else 1)
		Vfx.float(viewport, "+" .. NumberUtil.abbreviate(predicted), {
			color = if current.inSweetSpot then Theme.Color.heatSweet else Theme.Color.starMatter,
			crit = false,
		})
		-- Second marker in the band: "+12.5" alone does not say *why* it was
		-- bigger, and the player is looking at the render, not the gauge.
		if current.inSweetSpot then
			Vfx.float(viewport, string.format("x%.2g", current.bandMult), {
				color = Theme.Color.aether,
				size = Theme.Text.Body,
				drift = 118,
			})
		end
		-- The blade leaves a trail in its own rarity colour. The flipbook is the
		-- real effect; `Vfx.burst` is the always-available fallback for builds
		-- whose sheets have not been uploaded yet.
		if not SpriteFx.play(viewport, "slash", tint) then
			Vfx.burst(viewport, tint, 0.9)
		end
	end

	Sfx.strike(current.inSweetSpot, current.streak)

	-- The stage answers: the blade slams forward, the container punches, the
	-- frame washes, and sparks come out of the anvil. In the band everything is
	-- louder and gold. This is the difference between a number going up and an
	-- anvil being hit.
	recordStrike()
	BladePreview.react(if current.inSweetSpot then 5.2 else 3.4)
	punchViewport(if current.inSweetSpot then 1.3 else 1)
	screenFlash(
		if current.inSweetSpot then Theme.Color.starMatter else Theme.Color.white,
		-- Every click washes the whole screen now, so the peak is lower than
		-- the stage-local version was. At ten clicks a second a 0.28 white is a
		-- strobe; 0.15 is a pulse you can still see the HUD through.
		if current.inSweetSpot then 0.22 else 0.15,
		0.1
	)
	if viewport then
		Vfx.sparks(
			viewport,
			if current.inSweetSpot then Theme.Color.heatSweet else tint,
			if current.inSweetSpot then 15 else 9,
			if current.inSweetSpot then 1.5 else 1
		)
		-- A ring ripple under the sparks. The band gets a wide warm wave, an
		-- ordinary hit a tight one, so the two are separable at a glance without
		-- reading the multiplier.
		--
		-- It is centred on the cursor, not on the stage. The stage is a viewport
		-- with a blade in the middle of it; a ring that always blooms from the same
		-- pixel reads as an animation playing, while a ring that blooms where the
		-- player just hit reads as the anvil answering. `Vfx.pointer` returns nil
		-- when the cursor is off the forge card (Space presses, touch, gamepad), and
		-- the ring falls back to the stage centre for those input methods.
		Vfx.shockwave(viewport, if current.inSweetSpot then Theme.Color.heatSweet else tint, {
			size = if current.inSweetSpot then 130 else 88,
			spread = if current.inSweetSpot then 2.5 else 2.1,
			duration = if current.inSweetSpot then 0.4 else 0.3,
			thickness = if current.inSweetSpot then 4 else 2.5,
			at = Vfx.pointer(root),
		})
	end

	StateStore.send("click")

	-- Heat is server-authoritative but a local nudge keeps the gauge moving
	-- between packets instead of stepping at 10Hz. A held gauge stops at the
	-- vent line so the purge note cannot be contradicted by the bar.
	if state then
		local ceiling = if heatHold then math.max(Config.VentThreshold, state.heat) else 100
		state.heat = math.min(state.heat + Config.HeatPerClick, ceiling)
		ForgeView.render(state)
	end
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

--- Header labels for a blade. Shared by `ensureBlade` and the forge showcase so
--- a showcased blade never shows the previous blade's name above it.
local function paintHeader(blade: BladeRegistry.Blade, variantId: string?)
	if bladeName then
		bladeName.Text = blade.name
		bladeName.TextColor3 = Theme.rarityColor(blade.tier)
	end
	local variant = if variantId then ForgeConfig.variant(variantId) else nil
	local variantName = if variant and variant.id ~= ForgeConfig.StandardVariant then variant.name else nil
	if bladeSubtitle then
		bladeSubtitle.Text = string.upper(blade.rarity)
		bladeSubtitle.TextColor3 = Theme.rarityColor(blade.tier)
		if variantName then
			bladeSubtitle.Text = string.format("%s  ·  %s", string.upper(blade.rarity), string.upper(variantName))
		end
	end
	if bladeFlavor then
		if variantName then
			bladeFlavor.Text = string.format("%s  ·  %s", variantName, variant.text)
		else
			bladeFlavor.Text = blade.flavor
		end
	end
end

--- Repaints the stage wash to the blade's tier.
---
--- Two colour pairs, one per pool, resolved through `Theme.tierBackdrop` so the
--- backdrop, the header tint and the rarity stripe on the inventory card all
--- come off the same ladder. Called from the same place as `paintHeader`, which
--- is what keeps the backdrop from lagging a mount by a sync.
local function paintBackdrop(tier: number)
	local palette = Theme.tierBackdrop(tier)
	if backdrop then
		backdrop.setColors(palette.warm, palette.cool)
	end
end

--- Mounts one blade and repaints the header from the same table, so the name
--- above the viewport and the model inside it cannot be written from different
--- sources. The attribute records what was actually built; anything that swaps
--- geometry afterwards (a late mesh upgrade, a second mount) can be checked
--- against it instead of against a variable in this file.
local function mountBlade(bladeId: string, variantId: string?)
	if viewport == nil then
		return
	end
	local blade = BladeRegistry.get(bladeId)
	if blade == nil then
		return
	end
	local variant = if variantId then ForgeConfig.variant(variantId) else nil

	if cleanupPreview then
		cleanupPreview()
		cleanupPreview = nil
	end
	previewOrbit = nil

	cleanupPreview = BladePreview.mount(viewport, blade, if variant then variant.color else nil, {
		-- The stage is 486 tall and carries a 148px instrument strip at the
		-- bottom. 0.64 of the height frames a blade 311px tall (old stage: 184),
		-- and the upward bias keeps the hilt clear of the heat rail.
		frameFill = 0.64,
		aimBias = 0.13,
		-- The anvil is the drag surface. It is the only control over the render,
		-- so it is what sees the press; the strike still fires on that same
		-- press, and a held drag orbits the camera from there.
		surface = strikeButton,
		onOrbit = function(handle)
			previewOrbit = handle
		end,
	})
	paintHeader(blade, variantId)
	paintBackdrop(blade.tier)
	currentBladeId = blade.id
	currentVariantId = variantId

	local mounted = viewport:GetAttribute("BladeId")
	if mounted ~= blade.id then
		warn(string.format("[forge] viewport built %s, header expects %s", tostring(mounted), blade.id))
	end
end

local function ensureBlade(bladeId: string, variantId: string?)
	-- A forge showcase owns the viewport for a couple of seconds. Without this
	-- guard the next 10Hz sync would swap the freshly forged blade straight back
	-- to the equipped one before the player saw it.
	--
	-- The guard is not absolute: it only holds while the equipped blade is the
	-- showcased one or the one that was equipped when the showcase started. An
	-- explicit equip to a third blade during the window wins, because the player
	-- asked for it and a celebration is not worth showing the wrong weapon.
	if os.clock() < showcaseUntil then
		if (bladeId == currentBladeId and variantId == currentVariantId) or bladeId == showcaseEquipped then
			return
		end
		showcaseToken += 1
		showcaseUntil = 0
	end

	if currentBladeId == bladeId and currentVariantId == variantId then
		return
	end

	mountBlade(bladeId, variantId)
end

--- The crate the next quick roll buys.
---
--- Payload first, local selection second: the server is authoritative, but a
--- crate picked in the browser has to survive the frames before the next sync, and
--- the Studio seam sets it without a round trip. Falls back to whatever lifetime
--- has opened, which is what a pre-crate save means.
local function crateFor(payload: Types.SyncPayload): ForgeConfig.Tier
	local localPick = ForgeConfig.crate(selectedCrate)
	if localPick and payload.forgeCosts[localPick.id] then
		return localPick
	end
	local serverPick = ForgeConfig.crate(payload.forgeCrate)
	if serverPick then
		return serverPick
	end
	return ForgeConfig.tierFor(payload.runSm)
end

function ForgeView.render(payload: Types.SyncPayload)
	state = payload

	ensureBlade(payload.equipped, payload.equippedVariant)

	-- Aura. Unlike every other effect this one has no procedural equivalent, so
	-- there is nothing to fall back to: if the sheets are absent the anvil simply
	-- looks the same as it always did. Retrying every payload is free because
	-- `attach` bails on a cached availability check.
	if payload.inSweetSpot ~= auraOn then
		auraOn = payload.inSweetSpot
		if auraOn then
			if auraHandle == nil and viewport ~= nil then
				auraHandle = SpriteFx.attach(viewport, "aura", Theme.Color.heatSweet, { size = 640 })
			end
		elseif auraHandle ~= nil then
			auraHandle.stop()
			auraHandle = nil
		end
	end

	if multChip then
		multChip.Text = NumberUtil.abbreviateMultiplier(payload.mult)
	end

	-- Roll column. The price is the server's number, never a local guess, and the
	-- plate greys out exactly when the server would refuse.
	local pityGoal = math.max(payload.forgePityGoal, 1)
	if rollFooter then
		rollFooter.Text = string.format("SCRAP %s  ·  PITY %d/%d", NumberUtil.abbreviate(payload.scrap), payload.forgePity, pityGoal)
		rollFooter.TextColor3 = if payload.forgePity + 1 >= pityGoal
			then Theme.Color.quantum
			else Theme.Color.textSecondary
	end
	if pityFill then
		local ratio = math.clamp(payload.forgePity / pityGoal, 0, 1)
		pityFill.Size = UDim2.fromScale(ratio, 1)
		pityFill.BackgroundColor3 = if payload.forgePity + 1 >= pityGoal
			then Theme.Color.quantum
			else Theme.Color.cyanDeep
	end

	-- Crate and batch. The chip names the pool the ROLL key buys; the batch key
	-- quotes the ten-pull price on the same line, because a ten-pull that costs
	-- eleven singles is a fact the player should not have to derive.
	local crate = crateFor(payload)
	local quote = payload.forgeCosts[crate.id]
	local unit = if quote then quote.one else payload.forgeCost
	if crateChipLabel then
		crateChipLabel.Text = string.format("%s  ▾", crate.short)
		crateChipLabel.TextColor3 = crate.accent
	end
	if crateChip then
		local stroke = crateChip:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = crate.accent:Lerp(Theme.Color.outline, 0.45)
		end
	end
	if batchLabel then
		batchLabel.Text = if quote then string.format("x10  %s", NumberUtil.abbreviate(quote.ten)) else "x10"
		batchLabel.TextColor3 = if quote and payload.sm >= quote.ten
			then Theme.Color.text
			else Theme.Color.textFaint
	end
	if batchButton then
		local live = quote ~= nil and payload.sm >= quote.ten
		local stroke = batchButton:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if live then Theme.Color.stroke else Theme.Color.strokeFaint
		end
	end
	if rollCostLabel then
		rollCostLabel.Text = string.format("%s SM", NumberUtil.abbreviate(unit))
	end
	if rollButton then
		-- Rolling a crate is not a strike: it spends Star-Matter and touches no
		-- heat, so the overheat lockout must not gate it. The lock belongs to the
		-- anvil, which already prints OVERHEATED on the gauge and on the strike
		-- key. Leaving the lock in this line was the "cannot roll while purging"
		-- bug: a burned-out player had a dead roll button for five seconds with
		-- no explanation on it.
		local affordable = payload.sm >= unit
		rollButton.BackgroundColor3 = if affordable then Theme.Color.starMatterDeep else Theme.Color.slate
		local stroke = rollButton:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if affordable then Theme.Color.outline else Theme.Color.stroke
		end
		if rollCostLabel then
			rollCostLabel.TextColor3 = if affordable then Theme.Color.gold else Theme.Color.textDim
		end
	end

	-- Heat readout
	local heat = math.clamp(payload.heat, 0, 100)
	local bandMin = payload.bandMin
	local bandMax = payload.bandMax
	local overhot = heat >= Config.PenaltyFrom

	if heatFill then
		heatFill.Size = UDim2.fromScale(heat / 100, 1)
		local fillColor = if overhot then Theme.Color.danger else heatColor(heat, bandMin, bandMax)
		heatFill.BackgroundColor3 = fillColor
		if heatFillGradient then
			-- One state, one colour. The old blue-to-state ramp printed a rainbow
			-- inside the bar, which is a gauge from a different game: this one
			-- reads its state from the number above it.
			heatFillGradient.Color = ColorSequence.new(fillColor, fillColor)
		end
	end
	if heatBand then
		-- The band is a server fact (Thermal Calibration widens it), not the
		-- build-time default. Before this line the gauge drew 65-85 forever
		-- while the strike paid the wider band, so the screen disagreed with
		-- the economy.
		local lo = math.clamp(bandMin / 100, 0, 1)
		local hi = math.clamp(bandMax / 100, 0, 1)
		heatBand.Position = UDim2.fromScale(lo, 0)
		heatBand.Size = UDim2.fromScale(math.max(0, hi - lo), 1)
	end
	if heatLeanTick then
		heatLeanTick.BackgroundTransparency = if overhot then 0 else 0.3
	end
	if heatNeedle then
		heatNeedle.Position = UDim2.new(heat / 100, -1, 0, -2)
		heatNeedle.BackgroundColor3 = if overhot then Theme.Color.danger else Theme.Color.text
	end
	if heatTrackStroke then
		heatTrackStroke.Color = heatColor(heat, bandMin, bandMax)
		heatTrackStroke.Thickness = if payload.inSweetSpot then Theme.Stroke.thin else Theme.Stroke.hair
		heatTrackStroke.Transparency = 0
	end
	if heatStatus then
		heatStatus.Text = string.format("%d%%", math.floor(heat))
		heatStatus.TextColor3 = if overhot then Theme.Color.danger else heatColor(heat, bandMin, bandMax)
	end
	if heatBandLabel then
		-- One caption, and it changes with the state the player is in. A
		-- permanent "x2.5 legend" is a rulebook; this is a machine face.
		if overhot then
			heatBandLabel.Text = string.format("OVERHOT  YIELD x%.2g", Config.PenaltyMult)
			heatBandLabel.TextColor3 = Theme.Color.danger
		elseif payload.inSweetSpot then
			heatBandLabel.Text = string.format("SWEET SPOT  x%.2g", payload.bandMult)
			heatBandLabel.TextColor3 = Theme.Color.heatSweet
		elseif heat >= Config.VentThreshold then
			heatBandLabel.Text = "PURGE TO COOL"
			heatBandLabel.TextColor3 = Theme.Color.cyan
		else
			heatBandLabel.Text = string.format("BAND %d-%d", math.ceil(bandMin), math.floor(bandMax))
			heatBandLabel.TextColor3 = Theme.Color.textFaint
		end
	end
	-- Strike affordance
	if strikeButton then
		strikeButton.Active = true
	end
	if strikeHint then
		-- The caption is the live payout: what the next press pays, in
		-- Star-Matter, not a rate. `/s` belongs on the auto-click readout, which
		-- already has its own line in the top right of the stage.
		strikeHint.Text = string.format("STRIKE   +%s SM", NumberUtil.abbreviate(payload.clickYield))
		strikeHint.TextColor3 = if payload.inSweetSpot then Theme.Color.heatSweet else Theme.Color.textFaint
	end
	-- Thermal vent key, on the right end of the heat rail. Two states, never
	-- ambiguous: a flat slate key that names the gap while locked, and a solid
	-- saturated plate carrying the payout once the threshold is crossed.
	local canVent = heat >= Config.VentThreshold
	-- Cyan means "dump heat now"; molten orange means "you burned out, purge".
	-- Solid fills only: at 132x34 a multi-stop gradient reads as mud, and the
	-- old cyan-to-gold ramp turned the payout line brown at the midpoint.
	local ventAccent = Theme.Color.actionCyan
	local ventInk = Color3.fromRGB(11, 14, 20)

	if ventReady ~= canVent then
		ventReady = canVent
		if ventPillFill then
			ventPillFill.Visible = canVent
		end
	end

	if ventPill then
		ventPill.BackgroundColor3 = if canVent then ventAccent else Theme.Color.slate
		ventPill.BackgroundTransparency = 0
	end
	if ventPillFill and canVent then
		ventPillFill.BackgroundColor3 = ventAccent
	end
	if ventPillStroke then
		ventPillStroke.Color = if canVent then ventInk else Theme.Color.outline
		-- Thick enough to hold the plate off the dark panel behind it, thin
		-- enough that the fill stays the loudest thing on the row.
		ventPillStroke.Thickness = if canVent then 2.5 else Theme.Stroke.thick
		ventPillStroke.Transparency = 0
	end

	local labelText: string
	local detailText: string
	if canVent then
		-- Lower bound: tech multipliers are applied server-side, so the payout is
		-- never less than this.
		local payout = math.floor(heat * Config.AetherPerHeat)
		-- No emoji. A bolt glyph renders as a grey tofu box wherever the emoji
		-- font is missing, and it ate a fifth of the key.
		labelText = "PURGE HEAT"
		detailText = string.format("+%s AETHER", NumberUtil.abbreviate(payout))
	else
		labelText = "PURGE"
		detailText = string.format("REACH %d%%", Config.VentThreshold)
	end

	if ventPillLabel and labelText ~= ventLabelText then
		ventLabelText = labelText
		ventPillLabel.Text = labelText
	end
	if ventPillDetail and detailText ~= ventDetailText then
		ventDetailText = detailText
		ventPillDetail.Text = detailText
	end
	-- Pure white on the plate, with a near-black outline so the type survives
	-- both the cyan and the orange without changing colour between states.
	if ventPillLabel then
		ventPillLabel.TextColor3 = if canVent then Theme.Color.white else Theme.Color.locked
		ventPillLabel.TextStrokeColor3 = ventInk
		ventPillLabel.TextStrokeTransparency = if canVent then 0 else 1
	end
	if ventPillDetail then
		ventPillDetail.TextColor3 = if canVent then Theme.Color.white else Theme.Color.locked
		ventPillDetail.TextStrokeColor3 = ventInk
		ventPillDetail.TextStrokeTransparency = if canVent then 0.15 else 1
		ventPillDetail.TextTransparency = if canVent then 0 else 0.35
	end

	-- Streak rail. Ten clean strikes open a fifteen-second window where every hit
	-- pays double, so the rail answers two questions at once: how close the
	-- window is, and whether it is open right now.
	local goal = math.max(1, payload.streakGoal)
	local overdrive = payload.overdriveRemaining

	-- Overdrive opened. Fired on the transition, never on every sync inside the
	-- window, or a 15-second buff would flash fifteen times.
	if overdrive > 0 and lastOverdrive <= 0 then
		screenFlash(Theme.Color.gold, 0.45, 0.5)
		if viewport then
			Vfx.shockwave(viewport, Theme.Color.starMatter, {
				size = 220,
				spread = 3.4,
				duration = 0.62,
				thickness = 5,
			})
		end
		if root then
			Vfx.shake(root, 6, 0.28)
		end
		Sfx.streakComplete()
	end
	lastOverdrive = overdrive
	local lit = if overdrive > 0 then goal else math.clamp(payload.streak, 0, goal)
	local text = if overdrive > 0
		then string.format("OVERDRIVE x%d   %.0fs", Config.OverdriveMultiplier, math.ceil(overdrive))
		else string.format("STREAK %d/%d", lit, goal)

	if lit ~= streakLit or overdrive > 0 then
		streakLit = lit
		for index, pip in streakPips do
			local on = index <= lit
			pip.BackgroundColor3 = if on then Theme.Color.starMatter else Theme.Color.stroke
			pip.BackgroundTransparency = if on then 0 else 0.35
		end
	end

	if streakLabel and text ~= streakText then
		streakText = text
		streakLabel.Text = text
		streakLabel.TextColor3 = if overdrive > 0 then Theme.Color.starMatter else Theme.Color.textFaint
	end
end

-- ---------------------------------------------------------------------------
-- Forge celebration
-- ---------------------------------------------------------------------------

--- Shows the newly forged blade for a beat, then hands the viewport back to
--- whatever the profile has equipped.
---
--- Needed because `forgeBlade` only auto-equips a blade that is *stronger* than
--- the current one. Without the showcase, forging a sidegrade would pay out and
--- then show nothing at all. While the window is open `ensureBlade` is blocked,
--- so the 10Hz sync cannot yank the model back mid-spin.
function ForgeView.celebrate(bladeId: string?, variantId: string?, batch: number?)
	-- A roll in flight owns the reveal: park the answer so the crate sequence
	-- fires it at the shatter instead of popping a blade mid-wind-up.
	if rolling then
		pendingRoll = { blade = bladeId, variant = variantId, batch = batch }
		return
	end

	local blade = if bladeId then BladeRegistry.get(bladeId) else nil
	local variant = if variantId then ForgeConfig.variant(variantId) else nil
	local tint = if variant then variant.color else Theme.Color.starMatter
	local rank = 1
	if variant then
		for index, id in ForgeConfig.VariantOrder do
			if id == variant.id then
				rank = index
				break
			end
		end
	end

	if blade and viewport then
		showcaseToken += 1
		local token = showcaseToken
		showcaseUntil = os.clock() + 2.6
		showcaseEquipped = if state then state.equipped else nil

		if cleanupPreview then
			cleanupPreview()
			cleanupPreview = nil
		end
		previewOrbit = nil
		cleanupPreview = BladePreview.mount(viewport, blade, tint, {
			frameFill = 0.64,
			aimBias = 0.13,
			surface = strikeButton,
			onOrbit = function(handle)
				previewOrbit = handle
			end,
		})
		paintHeader(blade, variantId)
		paintBackdrop(blade.tier)
		currentBladeId = blade.id
		currentVariantId = variantId

		task.delay(2.6, function()
			if token ~= showcaseToken then
				return
			end
			showcaseUntil = 0
			currentBladeId = nil
			currentVariantId = nil
			local current = state
			ensureBlade(
				if current then current.equipped else BladeRegistry.StarterBlade,
				if current then current.equippedVariant else nil
			)
		end)
	end

	-- Five beats: punch, variant wash, shake, sparks, and the stinger (played
	-- by the caller at the same moment so audio and image are one event).
	punchViewport(1.6)
	screenFlash(tint, 0.5, 0.45)
	if viewport then
		Vfx.resultWash(viewport, tint, rank)
	end
	if root then
		Vfx.shake(root, 7 + rank, 0.3 + rank * 0.02)
	end
	Vfx.shakeScreen(5 + rank * 1.2, 0.3 + rank * 0.02)
	if viewport then
		Vfx.sparks(viewport, tint, 18 + rank * 4, 1.6 + rank * 0.12)
	end

	-- A ten-pull is one reveal, so the count has to be stated once. Without it
	-- the player sees a single blade and has to open the vault to believe the
	-- other nine landed.
	if batch and batch > 1 and root then
		Vfx.float(root, string.format("x%d FORGED", batch), {
			color = tint,
			size = Theme.Text.Heading,
			drift = 104,
		})
	end
end

--- Rank of a variant on the rarity ladder, 1 = Standard. Drives the stinger and
--- the shake magnitude.
local function variantRankOf(variantId: string?): number
	if variantId == nil then
		return 1
	end
	for index, id in ForgeConfig.VariantOrder do
		if id == variantId then
			return index
		end
	end
	return 1
end

--- Hides the roll stage. Idempotent: the sequence, the reveal and `destroy` all
--- call it, and a half-hidden crate would sit over the next blade.
local function hideCrate()
	local handle = crateHandle
	if handle then
		handle.stop()
	end
	local view = crateViewport
	if view then
		view.Visible = false
	end
end

--- The burst. Called with the roll already resolved, so it never invents a
--- result: an empty `pendingRoll` means the server refused and the crate fizzles
--- instead of pretending.
local function revealRoll()
	local token = rollToken
	local result = pendingRoll
	pendingRoll = nil
	rolling = false

	hideCrate()

	if result == nil then
		-- Rejected roll: the toast has already explained why. A small red shake
		-- is the visual half of "that did not work", and the old blade comes back
		-- because it never actually left the player's hands.
		Sfx.error()
		if viewport then
			viewport.Visible = true
			Vfx.shake(viewport, 6, 0.16)
		end
		return
	end

	if viewport then
		viewport.Visible = true
	end

	local variantId = result.variant
	local variant = if variantId then ForgeConfig.variant(variantId) else nil
	local tint = if variant then variant.color else Theme.Color.starMatter
	local rank = variantRankOf(variantId)
	local elementId = result.element
	local elementTint = if elementId and elementId ~= ""
		then ModifierConfig.element(elementId).color
		else tint

	-- The crate breaks before the blade arrives: the shockwave is anchored to the
	-- stage (the viewport is already hidden), so the player sees the box come
	-- apart at the spot the sword is about to occupy.
	local stage = crateStage
	if stage then
		Vfx.shockwave(stage, tint, { size = 58, spread = 4.6 + rank * 0.4, thickness = 6 })
		Vfx.sparks(stage, elementTint, 14, 1.5)
	end

	if viewport then
		viewport.Visible = true
		Vfx.shockwave(viewport, tint, { size = 70, spread = 4.2 + rank * 0.4, thickness = 5 })
		Vfx.burst(viewport, tint, 1.4 + rank * 0.2)
	end
	screenFlash(Theme.Color.white, 0.85, 0.22)
	Vfx.shakeScreen(7, 0.26)
	Sfx.crateShatter()
	Sfx.forge()
	if token == rollToken then
		ForgeView.celebrate(result.blade, variantId, result.batch)
		Sfx.result(rank)
	end
end

--- One roll: slam, wind-up, shatter, reveal.
---
--- The server answers somewhere inside the wind-up; `celebrate` parks the result
--- in `pendingRoll` and returns, so the reveal is always driven by the animation
--- clock rather than by packet timing. If the answer misses the deadline the
--- sequence still ends, and a late event simply showcases the blade.
function ForgeView.roll(count: number?)
	local batch = math.clamp(math.floor(count or 1), 1, 10)
	if rolling then
		lastRollNote = string.format("busy token=%d", rollToken)
		return
	end
	local live = StateStore.current
	if live == nil then
		lastRollNote = "no state"
		return
	end
	if not unlocked then
		lastRollNote = "locked out"
		return
	end

	local crate = crateFor(live)
	local quote = live.forgeCosts[crate.id]
	local price = if quote
		then (if batch > 1 then quote.ten else quote.one)
		else live.forgeCost
	if live.sm < price then
		lastRollNote = string.format("poor sm=%.1f cost=%.1f", live.sm, price)
		Sfx.error()
		Notifications.push(string.format("Need %s Star-Matter", NumberUtil.abbreviate(price)), "bad")
		return
	end

	rolling = true
	rollToken += 1
	pendingRoll = nil
	local token = rollToken
	local startedAt = os.clock()
	lastRollNote = string.format("started token=%d crate=%s x%d", token, crate.id, batch)

	-- The old sword leaves the moment the roll starts. Leaving it mounted under
	-- the crate is the ghost the report named: the crate is 180px, the blade is
	-- 400px, and the hilt pokes out of the box for the whole wind-up.
	if viewport then
		viewport.Visible = false
	end
	paintCrateStage(crate.tier)

	StateStore.send("forge", { crate = crate.id, count = batch })

	if Theme.reducedMotion() then
		-- No crate at all: the reveal is the whole interaction.
		task.delay(0.2, function()
			if token ~= rollToken then
				return
			end
			revealRoll()
		end)
		return
	end

	local handle = crateHandle
	if handle == nil or crateStage == nil then
		task.delay(0.25, function()
			if token == rollToken then
				revealRoll()
			end
		end)
		return
	end

	Sfx.roll()

	-- The crate owns its own clock: drop, land, rattle, hold. This sequence only
	-- subscribes to it, so the tick sounds and the screen shake land on the frames
	-- the model actually moves instead of on a second hand-rolled timer that
	-- drifts against the animation.
	handle.play(crate.accent, {
		onLanded = function()
			if token ~= rollToken then
				return
			end
			-- Slam. The crate is the heaviest object in the loop, so this is the
			-- one beat that shakes the whole HUD as well as the stage.
			if viewport then
				Vfx.shake(viewport, 16, 0.2)
			end
			Vfx.shakeScreen(8, 0.26)
			Sfx.crateLand()
		end,
		onBeat = function(beat: number)
			if token ~= rollToken then
				return
			end
			Sfx.rollTick(1 + beat)
			if beat % 2 == 0 and viewport then
				Vfx.shake(viewport, 3 + beat, 0.09)
			end
		end,
		onReady = function()
			-- The answer usually lands inside the wind-up. A refused roll never
			-- produces one, so the wait is bounded and the crate fizzles.
			task.spawn(function()
				local deadline = startedAt + 4.2
				while pendingRoll == nil and os.clock() < deadline do
					task.wait(0.04)
				end
				if token ~= rollToken then
					return
				end
				revealRoll()
			end)
		end,
	})
end

--- Anchor for the onboarding ring.
function ForgeView.rollAnchor(): TextButton?
	return rollButton
end

--- Studio diagnostics: why a roll did or did not start. `roll` returns early on
--- five different guards, and a silent no-op is indistinguishable from a dropped
--- remote without these three flags.
function ForgeView.isRolling(): boolean
	return rolling
end

function ForgeView.isUnlocked(): boolean
	return unlocked
end

--- Studio diagnostic: what the last `roll` call decided, in words.
function ForgeView.rollNote(): string
	return lastRollNote
end

--- Per-frame decay for the cadence readout and the glow breathe. Called from the
--- same RenderStepped loop that drives the HUD.
function ForgeView.step(dt: number)
	comboTimer += dt

	-- The live purge key pulses so it reads as "press me" from the corner of an
	-- eye that is watching the blade, not the gauge. The stroke only breathes a
	-- little: it is the contrast anchor for white type, so fading it out would
	-- undo the readability the plate exists for.
	if ventReady and ventPillStroke then
		local breathe = 0.5 + 0.5 * math.sin(comboTimer * 5.4)
		ventPillStroke.Transparency = breathe * 0.12
		if ventPillFill then
			ventPillFill.BackgroundTransparency = breathe * 0.03
		end
	end

	if comboChip == nil then
		return
	end

	local now = os.clock()
	local cutoff = now - 2
	while #strikeTimes > 0 and strikeTimes[1] < cutoff do
		table.remove(strikeTimes, 1)
	end

	local rate = #strikeTimes * 0.5
	local tier = ""
	local color = Theme.Color.textFaint
	if rate >= 6 then
		tier = "MAX OVERDRIVE"
		color = Theme.Color.starMatter
	elseif rate >= 4 then
		tier = "OVERDRIVE"
		color = Theme.Color.aether
	elseif rate >= 2.5 then
		tier = "HOT"
		color = Theme.Color.heatSweet
	end

	local text = if tier == ""
		then string.format("STRIKE SPEED   %.1f/s", rate)
		else string.format("%s   %.1f/s", tier, rate)

	-- Text assignment invalidates layout even when the string is identical, and
	-- this runs every frame.
	if text ~= comboText then
		comboText = text
		comboChip.Text = text
		comboChip.TextColor3 = color
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

--- The anvil button itself, for effects that need to anchor on it from outside
--- this module (crit flourishes, overheat flashes). Returns nil before init.
function ForgeView.strikeAnchor(): TextButton?
	return strikeButton
end

--- Freezes the local heat prediction at the vent line while the coach notes
--- explain the purge. The server does the real hold. Nothing is clamped here:
--- a replay may begin with the gauge already above the line, and dropping the
--- bar under the player's eyes would be a lie.
function ForgeView.setHeatHold(value: boolean)
	heatHold = value
end

--- The heat dial, for the coach notes. The whole block is the target: the
--- gauge, the number and the band caption are one control in the player's head.
function ForgeView.heatAnchor(): Frame?
	return heatBlock
end

--- The purge key, for the coach notes. Same button the player presses, not a
--- stand-in that would point at the wrong place after a reflow.
function ForgeView.ventAnchor(): TextButton?
	return ventPill
end

--- The hero orbit, for the Studio seam. The camera is normally driven by
--- holding a drag on the anvil; `VirtualInputManager` is capability-locked, so
--- the seam reads the handle and nudges its angles directly.
function ForgeView.orbitHandle(): OrbitHandle?
	return previewOrbit
end

--- The forge card itself. The section host hides it while a management screen is
--- up; it is passed in once at boot rather than looked up by name, so the host
--- cannot grab the wrong frame if the hierarchy is ever nested differently.
function ForgeView.card(): Frame?
	return root
end

--- Names the crate the next roll buys. Called by the browser before it hands the
--- pull back, and by the Studio seam.
function ForgeView.setCrate(id: string)
	selectedCrate = id
	local live = StateStore.current
	if live then
		ForgeView.render(live)
	end
end

function ForgeView.crateId(): string
	-- Resolved, not raw: before the browser has ever been opened the selection is
	-- empty and the card is quoting whatever the server says it is on. Reporting
	-- the raw field here is how the Studio seam read `standard` while the footer
	-- underneath was printing the Void crate's pity.
	local live = StateStore.current
	if live then
		return crateFor(live).id
	end
	return selectedCrate
end

--- Re-places the card after a window resize.
---
--- The card's interior is elastic — the banner gives up a fixed right column,
--- the stage fills whatever is left — so a reflow is two property writes and no
--- rebuild. The viewport texture is untouched, which is the point: resizing the
--- window should not re-render the hero blade.
function ForgeView.layout()
	if root == nil then
		return
	end
	root.Size = UDim2.fromOffset(Layout.CONTENT_W, Layout.CONTENT_H)
	root.Position = UDim2.fromOffset(Layout.CONTENT_X, Layout.CONTENT_Y)
end

--- `width` and `height` are the content rect from `Layout`, in design pixels.
function ForgeView.init(canvas: Frame, x: number, y: number, width: number, height: number)
	local panel = UiKit.panel(canvas, {
		tier = "shell",
		radius = Theme.Radius.xl,
	})
	panel.Name = "Forge"
	panel.Size = UDim2.fromOffset(width, height)
	panel.Position = UDim2.fromOffset(x, y)
	root = panel

	local inner = UiKit.create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	}) :: Frame
	inner.Parent = panel
	UiKit.padding(inner, 18)
	-- Children are positioned in the inner frame's *own* space, so shrink it to
	-- the padded area and let absolute offsets inside stay simple.
	inner.Size = UDim2.new(1, -36, 1, -36)
	inner.Position = UDim2.fromOffset(18, 18)

	buildHeader(inner)
	-- No roll column on this screen. Rolling lives on the CRATES page, where the
	-- pools, odds and both keys already are; a second copy here put two gacha
	-- verbs two inches apart and made the anvil look like a form footer.
	local stageFrame = buildViewport(inner)
	buildHeat(stageFrame)
	buildHud(stageFrame)

	-- Reset per-session state. `init` can run twice in one process (Play Again
	-- rebuilds the ScreenGui), and stale timestamps would leave the cadence chip
	-- reading a rate from the previous session.
	table.clear(strikeTimes)
	comboText = nil
	comboTimer = 0
	showcaseToken = 0
	showcaseUntil = 0
	showcaseEquipped = nil
	currentBladeId = nil
	unlocked = false
	ventReady = false
	ventLabelText = nil
	ventDetailText = nil
	rolling = false
	rollToken += 1
	pendingRoll = nil

	-- Mount the starter blade before any state arrives. `render` drives this too,
	-- but only once a payload lands — so pre-connection the viewport was a black
	-- rectangle with a blade name beside it, which reads as broken rather than
	-- empty. On a new save the first payload equips this same blade, and
	-- `ensureBlade` early-returns without touching it.
	ensureBlade(BladeRegistry.StarterBlade, ForgeConfig.StandardVariant)

	-- The viewport is the one always-visible dark surface in the game, so it is
	-- where ambient embers earn their frame cost. Delayed one beat: the panel has
	-- not been laid out on the frame `init` runs, so an immediate spawn would
	-- anchor every ember at 0,0.
	if stopEmbers then
		stopEmbers()
		stopEmbers = nil
	end
	task.delay(0.25, function()
		if root == nil or viewport == nil then
			return
		end
		if stopEmbers then
			stopEmbers()
			stopEmbers = nil
		end
		stopEmbers = Vfx.ambientEmbers(viewport, { count = 12, floor = 0.35 })
	end)

	unsubscribe = StateStore.onSync(function(payload: Types.SyncPayload)
		ForgeView.render(payload)
	end)

	-- Unlock after the first real payload so a pre-connection tap cannot fire a
	-- remote before the session is live.
	task.delay(0.4, function()
		unlocked = true
	end)
end

function ForgeView.destroy()
	if unsubscribe then
		unsubscribe()
		unsubscribe = nil
	end
	if auraHandle ~= nil then
		auraHandle.stop()
		auraHandle = nil
	end
	auraOn = false
	if cleanupPreview then
		cleanupPreview()
		cleanupPreview = nil
	end
	previewOrbit = nil
	if stopEmbers then
		stopEmbers()
		stopEmbers = nil
	end
	if root then
		root:Destroy()
		root = nil
	end
	lastOverdrive = 0
	comboChip = nil
	viewportScale = nil
	ventPillStroke = nil
	ventPill = nil
	ventPillFill = nil
	ventPillLabel = nil
	ventPillDetail = nil
	rollButton = nil
	rollCostLabel = nil
	rollFooter = nil
	pityFill = nil
	batchButton = nil
	batchLabel = nil
	crateChip = nil
	crateChipLabel = nil
	crateStage = nil
	crateViewport = nil
	if crateHandle then
		crateHandle.destroy()
		crateHandle = nil
	end
	rolling = false
	rollToken += 1
	pendingRoll = nil
	table.clear(strikeTimes)
end

return ForgeView
