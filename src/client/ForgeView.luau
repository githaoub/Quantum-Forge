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

local heatFill: Frame? = nil
local heatFillGradient: UIGradient? = nil
local heatBand: Frame? = nil
local heatVentTick: Frame? = nil
local heatLabel: TextLabel? = nil
local heatStatus: TextLabel? = nil
local heatTrackStroke: UIStroke? = nil
local heatNeedle: Frame? = nil
local heatBandLabel: TextLabel? = nil

local strikeButton: TextButton? = nil
local strikeFlash: Frame? = nil
local strikeHint: TextLabel? = nil
local strikeGlow: UIStroke? = nil

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
--- Set by `Main`: the crate browser is UI, and `ForgeView` does not own a modal.
local openCrates: (() -> ())? = nil
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
local stageStroke: UIStroke? = nil
local stageGlow = 0.45
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

-- Stage: the viewport itself is scale-punched on a hit, and a full-bleed frame
-- on top of it flashes. Both are children of the clipped stage frame, so neither
-- can bleed onto the heat gauge.
local viewportScale: UIScale? = nil
local viewportFlash: Frame? = nil

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
local glowBase = 0.92
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

local function buildHeader(parent: Frame)
	-- The blade name lives in the same overhanging wood banner the reference uses
	-- for its section headers. Rarity tints the title; the hard black stroke keeps
	-- it legible on wood at any hue.
	--
	-- The banner gives up 236px on the right: the roll column lives there, and a
	-- banner running under it would put the blade name behind the ROLL button.
	local banner = UiKit.banner(parent, {
		text = "RUSTED CLEAVER",
		position = UDim2.fromOffset(0, 0),
		width = UDim2.new(1, -236, 0, 46),
		size = 22,
		accent = Theme.Color.gold,
		icon = "★",
	})
	banner.Name = "BladeBanner"

	local title = banner:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		bladeName = title
	end

	local chip = UiKit.badge(banner, {
		text = "x1.00",
		color = Theme.Color.gold,
		width = 88,
		height = 26,
		size = 12,
	})
	chip.Name = "MultChip"
	chip.Position = UDim2.new(1, -98, 0.5, -13)
	local chipFace = chip:FindFirstChild("Face")
	if chipFace and chipFace:IsA("TextLabel") then
		chipFace.Font = Theme.Font.Numeric
		multChip = chipFace
	end
end

--- The roll column: Scrap and pity readouts above a chunky ROLL plate.
---
--- Price and pity live next to the button rather than inside a tooltip, because
--- the whole decision is "can I afford this and how close am I to a guaranteed
--- Void". A player should not have to open a sheet to learn either.
local function buildRollBar(parent: Frame)
	-- 222 x 74. ROLL keeps the whole left half; the right half is a two-key stack:
	-- x10 on top, the crate chip under it. Both are quick paths, not the gacha
	-- page, so they stay 21px tall and read as secondary keys beside the one big
	-- verb. The bottom 24px is the scrap/pity footer and its meter.
	local column = UiKit.create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(222, 74),
		Position = UDim2.new(1, -222, 0, 0),
	}) :: Frame
	column.Parent = parent

	local roll = UiKit.create("TextButton", {
		Name = "RollButton",
		BackgroundColor3 = Theme.Color.starMatterDeep,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(128, 46),
	}) :: TextButton
	UiKit.corner(roll, Theme.Radius.md)
	UiKit.gradient(roll, { Theme.Color.starMatterDeep, Theme.Color.gold }, 90)
	UiKit.stroke(roll, Theme.Color.outline, Theme.Stroke.thick, 0)
	roll.Parent = column
	rollButton = roll

	local face = UiKit.label(roll, {
		text = "ROLL",
		size = 19,
		font = Theme.Font.Black,
		color = Theme.Color.white,
		align = Enum.TextXAlignment.Center,
		stroke = true,
	})
	face.Name = "Face"
	face.Position = UDim2.fromOffset(0, 4)
	face.Size = UDim2.new(1, 0, 0, 24)
	face.ZIndex = 2

	rollCostLabel = UiKit.label(roll, {
		text = "50 SM",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.gold,
		align = Enum.TextXAlignment.Center,
	})
	rollCostLabel.Name = "Cost"
	rollCostLabel.Position = UDim2.fromOffset(0, 26)
	rollCostLabel.Size = UDim2.new(1, 0, 0, 16)
	rollCostLabel.ZIndex = 2

	UiKit.track(roll, roll.MouseEnter:Connect(function()
		Sfx.hover()
		UiKit.tween(roll, Theme.Duration.fast, { BackgroundColor3 = Theme.Color.starMatterDeep:Lerp(Theme.Color.white, 0.12) })
	end))
	UiKit.track(roll, roll.MouseLeave:Connect(function()
		UiKit.tween(roll, Theme.Duration.normal, { BackgroundColor3 = Theme.Color.starMatterDeep })
	end))
	UiKit.track(roll, roll.Activated:Connect(function()
		ForgeView.roll(1)
	end))

	local function sideKey(name: string, y: number, handler: () -> ()): (TextButton, TextLabel)
		local button = UiKit.create("TextButton", {
			Name = name,
			BackgroundColor3 = Theme.Color.panelSunken,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			Position = UDim2.fromOffset(134, y),
			Size = UDim2.fromOffset(88, 21),
		}) :: TextButton
		UiKit.corner(button, Theme.Radius.sm)
		local stroke = UiKit.stroke(button, Theme.Color.stroke, Theme.Stroke.hair, 0.1)
		button.Parent = column

		local label = UiKit.label(button, {
			text = "",
			size = Theme.Text.Tiny,
			font = Theme.Font.Black,
			color = Theme.Color.text,
			align = Enum.TextXAlignment.Center,
		})
		label.Name = "Face"
		label.Size = UDim2.fromScale(1, 1)
		label.ZIndex = 2
		label.TextTruncate = Enum.TextTruncate.AtEnd

		UiKit.track(button, button.MouseEnter:Connect(function()
			Sfx.hover()
			stroke.Transparency = 0
		end))
		UiKit.track(button, button.MouseLeave:Connect(function()
			stroke.Transparency = 0.1
		end))
		UiKit.track(button, button.Activated:Connect(handler))
		return button, label
	end

	batchButton, batchLabel = sideKey("BatchButton", 0, function()
		ForgeView.roll(10)
	end)

	crateChip, crateChipLabel = sideKey("CrateButton", 25, function()
		if openCrates then
			openCrates()
		end
	end)

	-- Scrap and pity, as one footer line under the column and a hairline meter
	-- beneath it. They lived on the stage's top-left corner for one pass, which is
	-- where the equipped blade's condition line already prints: `Void-Touched ·
	-- The core went somewhere else` ran straight through `SCRAP 6086`. The column
	-- is the only block on this card that the render never paints on, and both
	-- facts are about the roll, so they belong here.
	rollFooter = UiKit.label(column, {
		text = "SCRAP 0  ·  PITY 0/12",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.textSecondary,
		align = Enum.TextXAlignment.Right,
	})
	rollFooter.Name = "RollFooter"
	rollFooter.Position = UDim2.fromOffset(0, 50)
	rollFooter.Size = UDim2.fromOffset(222, 16)
	rollFooter.TextTruncate = Enum.TextTruncate.AtEnd

	local track = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.void,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 68),
		Size = UDim2.fromOffset(222, 4),
	}) :: Frame
	UiKit.corner(track, 2)
	track.Parent = column

	pityFill = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.quantum,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
	}) :: Frame
	UiKit.corner(pityFill, 2)
	pityFill.Parent = track
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
		-- Inner column is 540 tall. Banner 0..46, stage 54..540.
		Size = UDim2.new(1, 0, 1, -54),
		Position = UDim2.fromOffset(0, 54),
		ClipsDescendants = true,
	}) :: Frame
	UiKit.corner(frame, Theme.Radius.md)
	stageStroke = UiKit.stroke(frame, Theme.Color.strokeFaint, Theme.Stroke.hair, 0.4)
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

	-- Full-bleed wash over the blade. A ViewportFrame cannot hold a GUI stroke or
	-- gradient inside its own render, so the flash is drawn on top of it here.
	viewportFlash = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.white,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		-- Full bleed. The stage is the 3D view; a wash that stops 22px short
		-- leaves a lit strip along the bottom edge and reads as a bug.
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
	}) :: Frame
	viewportFlash.Parent = frame

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
	heatLabel = UiKit.label(parent, {
		text = "CORE HEAT",
		size = Theme.Text.Micro,
		font = Theme.Font.Heading,
		color = Theme.Color.textSecondary,
	})
	heatLabel.Size = UDim2.new(0.5, -16, 0, 20)
	heatLabel.Position = UDim2.new(0, 16, 1, -88)
	heatLabel.ZIndex = 7

	heatStatus = UiKit.label(parent, {
		text = "0%",
		size = Theme.Text.Small,
		font = Theme.Font.Numeric,
		color = Theme.Color.textDim,
		align = Enum.TextXAlignment.Right,
	})
	heatStatus.Size = UDim2.new(1, -32, 0, 20)
	heatStatus.Position = UDim2.new(0, 0, 1, -88)
	heatStatus.ZIndex = 7

	local track = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.panelSunken,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		-- The rail stops 140px short so the vent key sits on the same row,
		-- flush right. The gauge is the instrument; the key is the one control
		-- on it, and they read as a single bar.
		Size = UDim2.new(1, -168, 0, 40),
		Position = UDim2.new(0, 14, 1, -64),
		ZIndex = 7,
	}) :: Frame
	UiKit.corner(track, Theme.Radius.sm)
	heatTrackStroke = UiKit.stroke(track, Theme.Color.strokeFaint, Theme.Stroke.hair, 0.4)
	track.Parent = parent
	track.Name = "HeatGauge"

	-- Sweet-spot band. Drawn before the fill so the fill reads on top of it and
	-- the band shows through wherever heat has not reached yet.
	heatBand = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.heatSweet,
		BackgroundTransparency = 0.78,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.2, 1),
		Position = UDim2.fromScale(0.65, 0),
	}) :: Frame
	heatBand.Parent = track

	-- The band's own edge. Without it the zone is invisible against a full bar,
	-- which is precisely the moment the player needs to see where the safe exit is.
	local bandStroke = UiKit.create("UIStroke", {
		Color = Theme.Color.heatSweet,
		Thickness = 1,
		Transparency = 0.55,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}) :: UIStroke
	bandStroke.Parent = heatBand

	-- "x2.5" printed inside the band so the reward is legible without hovering.
	heatBandLabel = UiKit.label(heatBand, {
		text = "x2.5",
		size = Theme.Text.Micro,
		font = Theme.Font.Numeric,
		color = Theme.Color.heatSweet,
		align = Enum.TextXAlignment.Center,
		transparency = 0.1,
	})
	heatBandLabel.Size = UDim2.fromScale(1, 1)

	heatFill = UiKit.create("Frame", {
		-- Neutral: the hue lives in the gradient below, so the bar can ramp from
		-- cold at its own left edge to the current state colour at the tip. A
		-- tinted fill under a fixed hue ramp goes muddy above the band.
		BackgroundColor3 = Theme.Color.white,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
	}) :: Frame
	heatFillGradient = UiKit.gradient(heatFill, { Theme.Color.heatCool, Theme.Color.heatSweet }, 0)
	heatFill.Parent = track

	-- Decade ticks. An unmarked bar reads as "fill up"; a ruled bar reads as an
	-- instrument, and 65/85 become positions instead of guesses.
	for step = 1, 9 do
		local tick = UiKit.create("Frame", {
			BackgroundColor3 = Theme.Color.strokeBright,
			BackgroundTransparency = if step % 5 == 0 then 0.55 else 0.8,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(1, if step % 5 == 0 then 10 else 6),
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
		Position = UDim2.fromScale(0.85, 0),
		ZIndex = 4,
	}) :: Frame
	heatVentTick.Parent = track

	-- Where the heat actually is this instant. The fill tells you how much; the
	-- needle tells you which way it is moving, which is the thing a player acts on.
	heatNeedle = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.text,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 2, 1, 4),
		Position = UDim2.fromOffset(0, -2),
		ZIndex = 6,
	}) :: Frame
	UiKit.corner(heatNeedle, 1)
	heatNeedle.Parent = track

	-- Thermal vent key, bolted to the right end of the rail.
	--
	-- It has two jobs and they must not look alike. Below the threshold it is a
	-- flat slate key that names the threshold; at 85% it turns into a solid
	-- cyan→gold plate carrying the payout. Same footprint, so the row never
	-- shifts and the player never has to hunt for it in a new place.
	local vent = UiKit.create("TextButton", {
		Name = "VentStrip",
		BackgroundColor3 = Theme.Color.slate,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromOffset(132, 40),
		Position = UDim2.new(1, -146, 1, -64),
		ZIndex = 8,
	}) :: TextButton
	UiKit.corner(vent, Theme.Radius.sm)
	ventPillStroke = UiKit.stroke(vent, Theme.Color.outline, Theme.Stroke.thick, 0)
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
	UiKit.corner(ventPillFill, Theme.Radius.sm)
	ventPillFill.Parent = vent

	-- Lit edge on the plate. Child of the fill so it only shows in the live
	-- state, and it never tints the label sitting above it.
	local ventBevel = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.white,
		BackgroundTransparency = 0.58,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -14, 0, 2),
		Position = UDim2.fromOffset(7, 1),
		ZIndex = 2,
	}) :: Frame
	UiKit.corner(ventBevel, 2)
	ventBevel.Parent = ventPillFill

	ventPillLabel = UiKit.label(vent, {
		text = "VENT",
		size = 15,
		font = Theme.Font.Black,
		color = Theme.Color.locked,
		align = Enum.TextXAlignment.Center,
	})
	ventPillLabel.Position = UDim2.fromOffset(0, 4)
	ventPillLabel.Size = UDim2.new(1, 0, 0, 18)
	ventPillLabel.ZIndex = 3

	ventPillDetail = UiKit.label(vent, {
		text = string.format("%d%% TO UNLOCK", Config.VentThreshold),
		size = 13,
		font = Theme.Font.Black,
		color = Theme.Color.locked,
		align = Enum.TextXAlignment.Center,
		transparency = 0.35,
	})
	ventPillDetail.Position = UDim2.fromOffset(0, 23)
	ventPillDetail.Size = UDim2.new(1, 0, 0, 15)
	ventPillDetail.ZIndex = 3

	vent.Activated:Connect(function()
		local current = state
		if current == nil then
			return
		end
		local canVent = current.locked or current.heat >= Config.VentThreshold
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
--- There is no plate under the viewport any more: the gauge, the streak rail and
--- the yield readout float on a soft scrim at the bottom of the render, and the
--- render itself is the button. A player who clicks the blade, the empty air
--- around it, or the scrim all get the same strike, which is the behaviour a
--- full-bleed viewport promises.
local function buildHud(parent: Frame)
	-- Bottom scrim. Fades from nothing at its top edge to near-opaque at the
	-- bottom, so the instrument row reads over a bright blade without drawing a
	-- hard box edge across the render.
	local scrim = UiKit.create("Frame", {
		Name = "HudScrim",
		BackgroundColor3 = Theme.Color.void,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 148),
		Position = UDim2.new(0, 0, 1, -148),
		ZIndex = 5,
	}) :: Frame
	local fade = UiKit.gradient(scrim, { Theme.Color.void, Theme.Color.void }, 90)
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.62, 0.58),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	scrim.Parent = parent

	-- Streak rail: ten pips and one line, directly above the gauge. A row of
	-- pips rather than a bar because the question the player is asking is "how
	-- many more", and a bar answers "how much" instead.
	local rail = UiKit.create("Frame", {
		Name = "StreakRail",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -32, 0, 20),
		Position = UDim2.new(0, 16, 1, -116),
		ZIndex = 7,
	}) :: Frame
	rail.Parent = parent

	streakLabel = UiKit.label(rail, {
		text = string.format("STREAK 0/%d", Config.StreakForOverdrive),
		size = Theme.Text.Micro,
		font = Theme.Font.Black,
		color = Theme.Color.textSecondary,
	})
	streakLabel.Size = UDim2.fromOffset(176, 20)
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

	-- The action prompt. It floats on the render above the instrument row rather
	-- than sitting on a plate: the whole stage is the button now, and this is the
	-- label on it.
	local prompt = UiKit.label(parent, {
		text = "STRIKE THE ANVIL",
		size = Theme.Text.Subheading,
		font = Theme.Font.Display,
		color = Theme.Color.starMatter,
		align = Enum.TextXAlignment.Center,
		stroke = true,
	})
	prompt.Size = UDim2.fromOffset(260, 24)
	prompt.Position = UDim2.new(0.5, -130, 1, -94)
	prompt.ZIndex = 7

	-- Yield readout and cadence, top right. Both are live numbers, not copy.
	strikeHint = UiKit.label(parent, {
		text = "",
		size = Theme.Text.Small,
		font = Theme.Font.Numeric,
		color = Theme.Color.textSecondary,
		align = Enum.TextXAlignment.Right,
	})
	strikeHint.Size = UDim2.fromOffset(300, 20)
	strikeHint.Position = UDim2.new(1, -318, 0, 14)
	strikeHint.ZIndex = 7

	comboChip = UiKit.label(parent, {
		text = "",
		size = Theme.Text.Micro,
		font = Theme.Font.Numeric,
		color = Theme.Color.textSecondary,
		align = Enum.TextXAlignment.Right,
	})
	comboChip.Size = UDim2.fromOffset(300, 18)
	comboChip.Position = UDim2.new(1, -318, 0, 36)
	comboChip.ZIndex = 7

	-- Press flash: a white wash that fires and immediately fades. Full bleed and
	-- rounded to the stage, so it reads as the render reacting rather than as a
	-- square appearing.
	strikeFlash = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.text,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 6,
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

	-- The stage border is the anvil's face: cold at rest, hot as the gauge nears
	-- the band, danger-red on a burn-out.
	strikeGlow = UiKit.create("UIStroke", {
		Color = Theme.Color.heatCool,
		Thickness = 2,
		Transparency = 0.92,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}) :: UIStroke
	strikeGlow.Parent = button

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
function ForgeView.punch(strength: number?)
	if Theme.reducedMotion() then
		return
	end
	local amount = math.clamp(strength or 1, 0.5, 2.5)
	if viewport then
		Vfx.shake(viewport, 4 * amount, 0.12 + 0.06 * amount)
	end
end

--- Wash over the stage. `hold` is the flash length before it fades; a strike
--- wants ~0.06s of white, a forge wants a longer gold bloom.
local function flashViewport(color: Color3, peak: number, hold: number)
	if viewportFlash == nil then
		return
	end
	viewportFlash.BackgroundColor3 = color
	viewportFlash.BackgroundTransparency = 1 - peak
	UiKit.tween(viewportFlash, hold, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
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

	if current.locked then
		-- Local echo so the player understands instantly; the server will also
		-- reject it, which is the authority.
		Notifications.push("Core locked, wait or vent.", "bad")
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
		ForgeView.punch(1)
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
	flashViewport(
		if current.inSweetSpot then Theme.Color.starMatter else Theme.Color.white,
		if current.inSweetSpot then 0.42 else 0.28,
		0.08
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
	-- between packets instead of stepping at 10Hz.
	if state then
		state.heat = math.min(state.heat + 2.5, 100)
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
	if bladeFlavor then
		local variant = if variantId then ForgeConfig.variant(variantId) else nil
		if variant and variant.id ~= ForgeConfig.StandardVariant then
			bladeFlavor.Text = string.format("%s  ·  %s", variant.name, variant.text)
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

	-- Heat gauge
	local heat = math.clamp(payload.heat, 0, 100)
	local bandMin = payload.bandMin
	local bandMax = payload.bandMax

	if heatFill then
		heatFill.Size = UDim2.fromScale(heat / 100, 1)
		if heatFillGradient then
			-- Ramp from cold to the colour heat is worth right now, measured
			-- across the filled portion only. The act of filling is what heats
			-- the colour; there is no separate animation to keep in sync.
			heatFillGradient.Color = ColorSequence.new(Theme.Color.heatCool, heatColor(heat, bandMin, bandMax))
		end
	end
	if heatBand then
		heatBand.Position = UDim2.fromScale(bandMin / 100, 0)
		heatBand.Size = UDim2.fromScale((bandMax - bandMin) / 100, 1)
	end
	if heatStatus then
		if payload.locked then
			heatStatus.Text = string.format("OVERHEATED   %.1fs", payload.lockRemaining)
			heatStatus.TextColor3 = Theme.Color.danger
		elseif payload.inSweetSpot then
			-- Name the multiplier here rather than in a legend: this is the one
			-- moment the player needs to know what the zone is worth.
			heatStatus.Text = string.format("%d%%   x%.2g BONUS", math.floor(heat), payload.bandMult)
			heatStatus.TextColor3 = Theme.Color.heatSweet
		else
			heatStatus.Text = string.format("%d%%", math.floor(heat))
			heatStatus.TextColor3 = if heat >= 85 then Theme.Color.warn else Theme.Color.textDim
		end
	end
	if heatNeedle then
		heatNeedle.Position = UDim2.new(heat / 100, -1, 0, -2)
		heatNeedle.BackgroundColor3 = if payload.locked then Theme.Color.danger else Theme.Color.text
		heatNeedle.BackgroundTransparency = if payload.locked then 0.2 else 0
	end
	if heatTrackStroke then
		-- The rail changes colour before the fill does, which gives the player a
		-- half-second of warning while they are still looking at the button.
		heatTrackStroke.Color = heatColor(heat, bandMin, bandMax)
		heatTrackStroke.Transparency = if payload.locked then 0.15 else 0.45
		heatTrackStroke.Thickness = if payload.inSweetSpot then Theme.Stroke.thin else Theme.Stroke.hair
	end
	if heatBandLabel then
		heatBandLabel.Text = string.format("x%.2g", payload.bandMult)
		heatBandLabel.TextColor3 = if payload.inSweetSpot then Theme.Color.heatSweet else Theme.Color.textDim
	end

	-- Strike affordance
	if strikeButton then
		local locked = payload.locked
		strikeButton.Active = not locked
		local stroke = strikeButton:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if locked then Theme.Color.danger else Theme.Color.starMatter
			stroke.Transparency = if locked then 0.15 else 0.45
		end
	end
	if strikeGlow then
		-- Glow intensity is distance to the band, not absolute heat: the last
		-- ten points before 65% should be the brightest part of the ramp.
		local span = math.max(1, bandMax - bandMin)
		local closeness = math.clamp((heat - bandMin) / span, 0, 1)
		glowBase = 0.92 - 0.8 * closeness
		strikeGlow.Color = heatColor(heat, bandMin, bandMax)
		strikeGlow.Thickness = 2 + 3 * closeness
		if payload.locked then
			strikeGlow.Color = Theme.Color.danger
			glowBase = 0.3
		end
	end
	if strikeHint then
		if payload.locked then
			strikeHint.Text = "cooling down"
			strikeHint.TextColor3 = Theme.Color.danger
		elseif payload.inSweetSpot then
			-- Show the *bonus* number, not the base. The player is in the band
			-- right now; tell them what that is worth.
			strikeHint.Text = string.format("%s   SWEET SPOT BONUS", NumberUtil.abbreviateRate(payload.clickYield))
			strikeHint.TextColor3 = Theme.Color.heatSweet
		else
			strikeHint.Text = NumberUtil.abbreviateRate(payload.clickYield)
			strikeHint.TextColor3 = Theme.Color.textFaint
		end
	end

	-- Thermal vent key, on the right end of the heat rail. Two states, never
	-- ambiguous: a flat slate key that names the gap while locked, and a solid
	-- saturated plate carrying the payout once the threshold is crossed.
	local canVent = payload.locked or heat >= Config.VentThreshold
	-- Cyan means "dump heat now"; molten orange means "you burned out, purge".
	-- Solid fills only: at 132x34 a multi-stop gradient reads as mud, and the
	-- old cyan-to-gold ramp turned the payout line brown at the midpoint.
	local ventAccent = if payload.locked then Theme.Color.actionOrange else Theme.Color.actionCyan
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
	if heatVentTick then
		heatVentTick.BackgroundColor3 = if canVent then ventAccent else Theme.Color.warn
		heatVentTick.BackgroundTransparency = if canVent then 0 else 0.15
	end

	local labelText: string
	local detailText: string
	if payload.locked then
		labelText = "PURGE HEAT"
		detailText = string.format("%.1fs LOCKOUT", payload.lockRemaining)
	elseif canVent then
		-- Lower bound: tech multipliers are applied server-side, so the payout is
		-- never less than this.
		local payout = math.floor(heat * Config.AetherPerHeat)
		-- No emoji. The bolt glyph ate a fifth of a 132px key and rendered as a
		-- grey tofu box wherever the emoji font was missing.
		labelText = "VENT HEAT"
		detailText = string.format("+%s AETHER", NumberUtil.abbreviate(payout))
	else
		labelText = "VENT"
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

	-- Stage border follows the gauge. This is the one piece of feedback that is
	-- always on screen while the player looks at the blade, so it carries the
	-- "you are close / you are in / you are hot" read without a label.
	if stageStroke then
		local span = math.max(1, bandMax - bandMin)
		local closeness = math.clamp((heat - bandMin) / span, 0, 1)
		if payload.locked then
			stageStroke.Color = Theme.Color.danger
			stageStroke.Thickness = 2.5
			stageStroke.Transparency = 0.1
			stageGlow = 0.1
		elseif payload.streak >= goal then
			stageStroke.Color = Theme.Color.starMatter
			stageStroke.Thickness = 3.5
			stageStroke.Transparency = 0
			stageGlow = 0
		else
			stageStroke.Color = heatColor(heat, bandMin, bandMax)
			stageStroke.Thickness = Theme.Stroke.hair + 2.4 * closeness
			stageStroke.Transparency = 0.55 - 0.42 * closeness
			stageGlow = 0.55 - 0.42 * closeness
		end
	end

	-- Overdrive opened. Fired on the transition, never on every sync inside the
	-- window, or a 15-second buff would flash fifteen times.
	if overdrive > 0 and lastOverdrive <= 0 then
		flashViewport(Theme.Color.gold, 0.72, 0.5)
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
	flashViewport(tint, 0.9, 0.45)
	if viewport then
		Vfx.resultWash(viewport, tint, rank)
	end
	if root then
		Vfx.shake(root, 7 + rank, 0.3 + rank * 0.02)
	end
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
	flashViewport(Theme.Color.white, 1, 0.18)
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
			-- Slam. The camera shake lives on the blade viewport even though it is
			-- hidden: `Vfx.shake` writes the canvas, not the frame, and the reveal
			-- turns the viewport back on inside the same beat.
			if viewport then
				Vfx.shake(viewport, 16, 0.2)
			end
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

	if strikeGlow then
		local breathe = 0.5 + 0.5 * math.sin(comboTimer * 3.4)
		strikeGlow.Transparency = math.clamp(glowBase - breathe * 0.08 * (1 - glowBase), 0, 1)
	end

	-- The stage edge breathes against its own baseline. `stageGlow` is the
	-- resting transparency the render pass chose; the breath never overrides it.
	if stageStroke then
		local breathe = 0.5 + 0.5 * math.sin(comboTimer * 2.6)
		stageStroke.Transparency = math.clamp(stageGlow - breathe * 0.12 * (1 - stageGlow), 0, 1)
	end

	-- The live vent key pulses so it reads as "press me" from the corner of an
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
	buildRollBar(inner)
	local stageFrame = buildViewport(inner)
	buildHeat(stageFrame)
	buildHud(stageFrame)

	-- Reset per-session state. `init` can run twice in one process (Play Again
	-- rebuilds the ScreenGui), and stale timestamps would leave the cadence chip
	-- reading a rate from the previous session.
	table.clear(strikeTimes)
	comboText = nil
	glowBase = 0.92
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
	strikeGlow = nil
	stageStroke = nil
	lastOverdrive = 0
	comboChip = nil
	viewportScale = nil
	viewportFlash = nil
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
