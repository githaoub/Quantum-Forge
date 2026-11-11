--!strict
-- The single source of visual truth. Every colour, size and font in the UI comes
-- from here so a restyle is one file, not forty.
--
-- Palette: chunky Roblox simulator. Warm wood chrome, near-black 3px outlines,
-- solid saturated plates, white type with a hard black stroke. Nothing here is
-- translucent: the reference UI is opaque, and thin translucent panels were what
-- made the old build read as a wireframe.

local Theme = {}

-- ---------------------------------------------------------------------------
-- Colour
-- ---------------------------------------------------------------------------

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

Theme.Color = {
	-- Surfaces, back to front. Depth is value, not bevel: four values are enough
	-- to read a stack, and a fifth turns into mud on a dark display.
	void = rgb(6, 7, 10),
	backdrop = rgb(10, 12, 16),
	panel = rgb(19, 23, 29),
	panelRaised = rgb(29, 35, 44),
	panelSunken = rgb(11, 14, 19),
	-- Multiply identity. Used where a UIGradient owns the hue: the frame behind
	-- it has to be neutral or the two tints compound into mud.
	white = rgb(255, 255, 255),

	-- Muted fill for a control that cannot be used yet. A locked control is a
	-- different object, not the same object at lower opacity: it drops the accent
	-- and keeps a flat, cold fill.
	slate = rgb(18, 22, 29),
	-- Lit cap for a slate plate, kept so a currency capsule can carry one step of
	-- lift without a gradient.
	slateLift = rgb(34, 41, 53),
	-- Full-bleed wallpaper. The screen sits on a near-black bed, and the chrome
	-- carries the only two values above it.
	sky = rgb(10, 13, 18),
	skyLift = rgb(26, 32, 41),
	skyDeep = rgb(5, 7, 10),

	-- The outline. Reserved for the one primary key per screen and for glyph
	-- lockups; every container uses `stroke` at 1px.
	outline = rgb(5, 7, 11),

	-- Chrome plate. Banners, the top bar and the rail wear this, flat.
	wood = rgb(35, 42, 53),
	woodLight = rgb(46, 54, 68),
	woodDeep = rgb(23, 28, 36),
	tan = rgb(38, 46, 58),
	tanDeep = rgb(26, 32, 40),
	-- Fill for a content row: one step above the shell, flat.
	card = rgb(26, 31, 39),
	cardDeep = rgb(18, 22, 29),

	-- Lines. `stroke` is the 1px container border; `strokeBright` is the same line
	-- under the pointer. `strokeFaint` is a divider inside a dark surface.
	stroke = rgb(38, 46, 58),
	strokeBright = rgb(58, 68, 84),
	strokeFaint = rgb(30, 36, 46),

	-- Text. One warm-free ladder: white, then two greys that both hold contrast
	-- on `shell`, so a 13px caption never needs a stroke to survive.
	text = rgb(244, 247, 251),
	textDim = rgb(200, 208, 220),
	textFaint = rgb(142, 153, 169),
	textSecondary = rgb(174, 184, 199),

	-- Currency / category accents
	gold = rgb(255, 193, 61),
	goldDeep = rgb(184, 128, 26),
	cyan = rgb(123, 228, 255),
	cyanDeep = rgb(31, 148, 174),
	magenta = rgb(199, 125, 255),
	magentaDeep = rgb(122, 70, 196),
	emerald = rgb(91, 227, 154),
	emeraldDeep = rgb(28, 154, 99),
	red = rgb(255, 107, 107),
	redDeep = rgb(176, 52, 52),

	-- Legacy names kept as aliases: the currency accents are the same hues, and
	-- renaming every call site would churn 20 files for no pixel.
	starMatter = rgb(255, 193, 61),
	starMatterDeep = rgb(184, 128, 26),
	aether = rgb(123, 228, 255),
	aetherDeep = rgb(31, 148, 174),
	quantum = rgb(167, 139, 250),
	quantumDeep = rgb(94, 66, 178),

	-- State
	good = rgb(91, 227, 154),
	warn = rgb(255, 180, 84),
	danger = rgb(255, 107, 107),
	locked = rgb(111, 122, 138),

	-- Action fills. One ember for the verb, one cool for information. Both are
	-- used flat; a gradient on a key is chrome pretending to be light.
	actionCyan = rgb(123, 228, 255),
	actionOrange = rgb(255, 122, 47),
	deepBlue = rgb(22, 35, 58),

	-- Absolute black, for the modal scrim and glyph strokes.
	ink = rgb(0, 0, 0),

	-- Heat gauge ramp
	heatCool = rgb(79, 156, 255),
	heatSweet = rgb(112, 240, 168),
	heatHot = rgb(255, 138, 76),
	heatCritical = rgb(255, 61, 77),
}

--- Rarity colours, indexed by tier. Mirrors BladeRegistry.rarityInfo so the UI
-- never has to reach into the registry for a colour it can get here.
Theme.Rarity = {
	rgb(196, 148, 96),
	rgb(188, 204, 224),
	rgb(96, 214, 246),
	rgb(206, 138, 255),
	rgb(122, 255, 196),
}

function Theme.rarityColor(tier: number): Color3
	local index = math.clamp(tier, 1, #Theme.Rarity)
	return Theme.Rarity[index]
end

--- Two-colour stage wash for the equipped-blade viewport, indexed by tier.
---
--- `warm` sits under the hilt, `cool` behind the tip, the way a key light and a
--- rim light fall on a photographed sword. Keeping the pair here means the forge
--- stage, and anything else that wants a tier-coloured backdrop, cannot drift
--- from the rarity ladder.
export type TierBackdrop = {
	warm: Color3,
	cool: Color3,
}

Theme.TierBackdrop = {
	-- 1 Scrap: rust and dim amber, the colour of a blade left in the yard.
	{ warm = rgb(168, 74, 36), cool = rgb(122, 88, 26) },
	-- 2 Forge: molten orange against steel blue, the forge and the quench.
	{ warm = rgb(255, 107, 0), cool = rgb(70, 108, 138) },
	-- 3 Quantum: electric cyan and deep violet, plasma in a bottle.
	{ warm = rgb(0, 210, 255), cool = rgb(96, 40, 190) },
	-- 4 Celestial: astral magenta and nebula indigo.
	{ warm = rgb(255, 54, 200), cool = rgb(43, 46, 143) },
	-- 5 Cosmic: gold against the same indigo, the last tier before legend.
	{ warm = rgb(255, 194, 60), cool = rgb(58, 43, 143) },
}

function Theme.tierBackdrop(tier: number): TierBackdrop
	local index = math.clamp(tier, 1, #Theme.TierBackdrop)
	return Theme.TierBackdrop[index]
end

-- ---------------------------------------------------------------------------
-- Type
-- ---------------------------------------------------------------------------

Theme.Font = {
	Display = Enum.Font.GothamBlack,
	Heading = Enum.Font.GothamBold,
	Body = Enum.Font.GothamMedium,
	Mono = Enum.Font.Code,
	-- Numerals are monospaced. Two reasons: a HUD reads better when the digits are
	-- fixed-width (it is the house style of the genre), and a proportional font
	-- makes a live counter jitter horizontally as glyph widths change — every
	-- 1 -> 0 tick nudges the pill contents.
	Numeric = Enum.Font.Code,
	-- Button faces and tab labels. Heading weights are too shouty at 13px.
	Label = Enum.Font.GothamBold,
	-- Small-caps labels and button faces. Not GothamBlack: at 13px the heaviest
	-- weight closes the counters and the face turns to mush.
	Black = Enum.Font.GothamBold,
}

--- Size ladder. Everything in the UI picks from here; no ad-hoc pixel values.
---
--- The ladder is unchanged at the top (a hero figure still has to dominate a
--- 720px canvas) and unchanged at the floor: 13 design px is the readable limit
--- once the canvas is fit-scaled onto a laptop, and nothing interactive goes
--- below it.
Theme.Text = {
	Hero = 46,
	Title = 30,
	Heading = 22,
	Subheading = 18,
	Body = 16,
	Small = 15,
	Micro = 14,
	Tiny = 13,
}

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

Theme.Space = {
	xs = 4,
	sm = 8,
	md = 12,
	lg = 18,
	xl = 26,
	xxl = 38,
}

-- 4 on controls, 6 on panels, 0 on rules. The old 10-16px corners were half of
-- the "mobile app" read: a moulded radius says toy, a near-square corner says
-- instrument.
Theme.Radius = {
	sm = 3,
	md = 4,
	card = 6,
	lg = 6,
	xl = 8,
	round = 999,
}

Theme.Stroke = {
	hair = 1,
	thin = 1,
	thick = 2,
	bold = 3,
}

--- Whether type should be ink or white on `background`.
---
--- Every accent in the palette is light enough that white type on it is a
--- contrast failure (gold, cool, emerald), which is why so much of the old UI
--- needed a black stroke to survive. Picking the face colour from the fill
--- removes the stroke rather than compensating for it.
function Theme.onColor(background: Color3): Color3
	local luma = 0.2126 * background.R + 0.7152 * background.G + 0.0722 * background.B
	return if luma > 0.55 then Theme.Color.ink else Theme.Color.text
end

-- ---------------------------------------------------------------------------
-- Elevation
-- ---------------------------------------------------------------------------

-- Read them bottom-up, which is also the order they appear in the table:
--
--   well   a readout cut *into* a panel — gauge track, passive-rate strip
--   item   one discrete row inside a list — a blade, a tech node, a shop entry
--   shell  the region background a list lives in — top bar, forge, side panel
--   raised the thing the player acts on — primary button, modal, toast
--
-- Every rung is opaque. A translucent card over a translucent panel is the
-- single biggest reason the old UI read as a wireframe.
export type Tier = "well" | "item" | "shell" | "raised"

export type ElevationSpec = {
	fill: Color3,
	transparency: number,
	strokeTransparency: number,
}

local ELEVATION: { [Tier]: ElevationSpec } = {
	well = { fill = Theme.Color.panelSunken, transparency = 0, strokeTransparency = 0 },
	item = { fill = Theme.Color.card, transparency = 0, strokeTransparency = 0 },
	shell = { fill = Theme.Color.panel, transparency = 0, strokeTransparency = 0 },
	raised = { fill = Theme.Color.panelRaised, transparency = 0, strokeTransparency = 0 },
}

Theme.Elevation = ELEVATION

--- Resolves a tier name to its surface spec, defaulting to `shell`. Going through
--- a function rather than indexing `Theme.Elevation` directly keeps the default in
--- one place and gives the type checker an explicit return type.
function Theme.elevation(tier: Tier?): ElevationSpec
	return ELEVATION[tier or "shell"]
end

-- Design resolution the UI is authored against. Height is authoritative: the
-- canvas is always 720 design px tall and the width is taken from the viewport,
-- so a 16:9 display lands near 1280 and a 21:9 near 1680. `Layout.init` receives
-- the measured width at boot and every consumer reads plain numbers from it.
--
-- 1440 remains the nominal figure — it is what a 2:1 window gets, and it is the
-- width the chrome was budgeted against (tabs, a live rate readout and seven
-- keys on one 46px strip).
Theme.DesignWidth = 1440
Theme.DesignHeight = 720

-- ---------------------------------------------------------------------------
-- Motion
-- ---------------------------------------------------------------------------

Theme.Duration = {
	instant = 0.06,
	fast = 0.14,
	normal = 0.26,
	slow = 0.45,
	lazy = 0.9,
}

--- Honours the client's "reduce motion" accessibility setting. Cached because
--- this is read from inside tween-heavy loops; probed in a pcall because the
--- property is not present on every client build.
local reducedMotion: boolean? = nil

function Theme.reducedMotion(): boolean
	if reducedMotion ~= nil then
		return reducedMotion
	end
	local ok, value = pcall(function(): boolean
		-- selene: allow(incorrect_standard_library_use)
		return game:GetService("UserGameSettings").ReducedMotionMode == Enum.ReducedMotionMode.Enabled
	end)
	reducedMotion = ok and value == true
	return reducedMotion :: boolean
end

--- Runs even when reduce-motion is on. Opacity is not motion: collapsing every
--- fade to a hard cut makes an interface read as broken rather than calm, so
--- fade-outs keep their duration while travel, scaling and shaking do not.
function Theme.fade(instance: Instance, duration: number, goal: { [string]: any }): Tween
	local tween = game:GetService("TweenService"):Create(instance, TweenInfo.new(duration, Enum.EasingStyle.Linear), goal)
	tween:Play()
	return tween
end

--- Spawns a tween and cleans the instance when it is destroyed mid-flight.
--- Collapses to an instant state change when reduce-motion is on, so the UI never
--- animates against the player's stated preference.
function Theme.tween(instance: Instance, duration: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local info = TweenInfo.new(
		if Theme.reducedMotion() then 0 else duration,
		style or Enum.EasingStyle.Quad,
		direction or Enum.EasingDirection.Out
	)
	local tween = game:GetService("TweenService"):Create(instance, info, goal)
	tween:Play()
	return tween
end

return Theme
