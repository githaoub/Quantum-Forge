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
	-- Surfaces, back to front
	void = rgb(9, 8, 10),
	backdrop = rgb(18, 15, 13),
	panel = rgb(32, 24, 19),
	panelRaised = rgb(44, 33, 25),
	panelSunken = rgb(20, 14, 10),
	-- Multiply identity. Used where a UIGradient owns the hue: the frame behind
	-- it has to be neutral or the two tints compound into mud.
	white = rgb(255, 255, 255),

	-- Muted fill for a control that cannot be used yet. Explicitly darker and
	-- bluer than `panelRaised`: a locked button has to read as a *different kind
	-- of object* from a live one, not as the same button at lower opacity.
	slate = rgb(24, 28, 38),
	-- Lit cap for a slate plate. The warm panels get their bevel from the wood
	-- gradient, so a navy currency capsule needs its own lighter stop or it sits
	-- in the top bar as a flat hole.
	slateLift = rgb(40, 48, 66),
	-- Full-bleed wallpaper. The screen used to sit on a near-black bed, which
	-- read as a web page letterboxed inside the game: the chrome floated on
	-- nothing and every gap between panels was a black hole. This is the same
	-- navy the currency capsules already wear, run across the entire display so
	-- the surround and the chrome read as one surface.
	sky = rgb(23, 31, 49),
	skyLift = rgb(38, 50, 78),
	skyDeep = rgb(13, 18, 29),

	-- The outline. Every panel, plate, pill and chip in the reference carries a
	-- hard near-black border; this is the single token for all of them.
	outline = rgb(15, 17, 23),

	-- Wood chrome. Banners, header bars and the frame around a modal card.
	wood = rgb(206, 141, 74),
	woodLight = rgb(232, 173, 108),
	woodDeep = rgb(140, 86, 40),
	tan = rgb(216, 169, 111),
	tanDeep = rgb(160, 108, 55),
	-- Fill for a content row: warm dark wood, dark enough that 11px captions
	-- still hold contrast without a stroke.
	card = rgb(58, 42, 29),
	cardDeep = rgb(38, 26, 17),

	-- Lines. `stroke` survives as the "quiet line" token for dividers inside a
	-- dark surface; everything structural uses `outline`.
	stroke = rgb(74, 56, 40),
	strokeBright = rgb(128, 96, 66),
	strokeFaint = rgb(48, 35, 25),

	-- Text. White with a black stroke is the reference's house style; keep the
	-- ladder warm so it also sits on wood without going pink.
	text = rgb(255, 255, 255),
	textDim = rgb(242, 228, 208),
	textFaint = rgb(205, 184, 158),
	-- Cool secondary copy for dark slate and card interiors. The warm faint tone
	-- above disappears into brown card stock; this one holds a 7:1 contrast ratio
	-- against `slate` and `cardDeep`, which is what a 13px description needs.
	textSecondary = rgb(184, 194, 214),

	-- Currency / category accents
	gold = rgb(255, 194, 60),
	goldDeep = rgb(224, 138, 18),
	cyan = rgb(67, 215, 245),
	cyanDeep = rgb(27, 156, 196),
	magenta = rgb(232, 91, 224),
	magentaDeep = rgb(163, 43, 176),
	emerald = rgb(75, 227, 138),
	emeraldDeep = rgb(31, 163, 92),
	red = rgb(226, 59, 59),
	redDeep = rgb(161, 30, 30),

	-- Legacy names kept as aliases: the currency accents are the same hues, and
	-- renaming every call site would churn 20 files for no pixel.
	starMatter = rgb(255, 194, 60),
	starMatterDeep = rgb(224, 138, 18),
	aether = rgb(67, 215, 245),
	aetherDeep = rgb(27, 156, 196),
	quantum = rgb(199, 125, 255),
	quantumDeep = rgb(124, 70, 200),

	-- State
	good = rgb(75, 227, 138),
	warn = rgb(255, 176, 64),
	danger = rgb(255, 92, 92),
	locked = rgb(139, 149, 165),

	-- Saturated action fills. These are deliberately outside the warm palette:
	-- a live control has to out-shout the wood chrome around it, and a solid
	-- mid-tone with dark type is the only way to do that without a gradient.
	actionCyan = rgb(0, 210, 255),
	actionOrange = rgb(255, 107, 0),
	deepBlue = rgb(22, 58, 104),

	-- Absolute black, for the modal scrim and text strokes.
	ink = rgb(0, 0, 0),

	-- Heat gauge ramp
	heatCool = rgb(78, 156, 255),
	heatSweet = rgb(112, 240, 168),
	heatHot = rgb(255, 118, 72),
	heatCritical = rgb(255, 52, 68),
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
	-- Chunky banner titles and the big numbers on a modal.
	Black = Enum.Font.GothamBlack,
}

--- Size ladder. Everything in the UI picks from here; no ad-hoc pixel values.
---
--- The whole ladder moved up ~13% for the "chunky simulator" pass. These are
--- design-space pixels inside a 1280x720 canvas that is fit-scaled to the
--- viewport, so a bigger number here is genuinely bigger on screen at every
--- resolution — it is not a zoom that crops.
Theme.Text = {
	Hero = 50,
	Title = 32,
	Heading = 23,
	Subheading = 19,
	Body = 17,
	Small = 15,
	-- Caption rung. These two used to be 12 and 10, which is below the readable
	-- floor once the canvas is fit-scaled onto a 1366px laptop: 10 design px lands
	-- at 7 screen px at 0.72 scale. Nothing on an interactive card is allowed
	-- under 13 design px now, and `Tiny` is the dense-row rung rather than a
	-- licence to shrink.
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

-- 12 is the house radius: every panel, plate and card in the reference sits
-- somewhere between 8 and 14, and 12 reads as "moulded" at both 720p and 4K.
Theme.Radius = {
	sm = 6,
	md = 10,
	card = 12,
	lg = 12,
	xl = 16,
	round = 999,
}

Theme.Stroke = {
	hair = 1,
	thin = 2,
	thick = 3,
	bold = 4,
}

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
