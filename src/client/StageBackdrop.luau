--!strict
-- The gradient wash behind a 3D viewport.
--
-- A `UIGradient` interpolates along a single axis, so there is no such thing as
-- a radial fill in Roblox's UI renderer. A radial *look* is composited here
-- from one opaque base ramp plus four crossed luminance bands: every band is
-- transparent at both ends, so where they overlap the colours add up and the
-- centre reads as a bloom, while the corners stay dark. That is the difference
-- between this and the stack of solid circles it replaces: circles have a hard
-- edge at every step, bands have none.
--
-- Three callers, one module:
--
--   forge     two tier lights, full-bleed, seven layers
--   drone     aether against quantum, same stack
--   vault     one wash per card and one behind the inspect stage
--
-- `tile` drops the diagonal bands and the rim shaft. A 221px card does not show
-- them, and twenty-five cards do not need twenty-five times the frame count.

local Theme = require(script.Parent.Theme)
local UiKit = require(script.Parent.UiKit)

local StageBackdrop = {}

export type Spec = {
	--- Key light: sits low, under the subject.
	warm: Color3,
	--- Rim light: sits high, behind the subject.
	cool: Color3,
	--- Third light, used by the diagonal bands and the shaft only. Vault cards
	--- pass the variant colour here so the rarity hue stays dominant and the
	--- variant reads as a rim rather than mixing into mud.
	accent: Color3?,
	--- Base ramp rotation in degrees. 90 runs top to bottom.
	rotation: number?,
	--- How far the base ramp is pushed toward the void, 0..1. The full stages
	--- use the module default; a 136px card well needs a lighter floor or the
	--- art reads as a black box with a tint on top.
	depth: number?,
	radius: number?,
	zIndex: number?,
	--- Offset height instead of filling the parent. Card art wells stop above
	--- the name row, so the wash is given the height of the art only.
	height: number?,
	--- Base ramp, two bands, vignette. No diagonals, no shaft.
	tile: boolean?,
	--- Fade the bottom of the wash into this colour. Cards pass the plate they
	--- sit on so the art dissolves into the name row instead of ending on a
	--- visible line.
	settle: Color3?,
	settleHeight: number?,
}

export type Handle = {
	--- Re-tints the wash in place. Cheap enough to call on every sync. `accent`
	--- is the third light (diagonals and shaft); omit it to reuse `warm`.
	setColors: (warm: Color3, cool: Color3, accent: Color3?) -> (),
	layers: { Frame },
}

--- Pushes a colour toward the void without losing its hue. The ramp still has
--- to read as the rarity colour while staying dark enough for white type and a
--- lit blade to sit on top of it; `DEEP` is the full stage and a card passes its
--- own, lighter value through `spec.depth`.
local function deep(color: Color3, amount: number): Color3
	return color:Lerp(Theme.Color.void, amount)
end

local DEEP = 0.68

--- `stops` are `{ offset, transparency }` pairs, offset first.
type Stop = { number }

local function ramp(gradient: UIGradient, stops: { Stop })
	local keypoints = {}
	for _, stop in stops do
		table.insert(keypoints, NumberSequenceKeypoint.new(stop[1], stop[2]))
	end
	gradient.Transparency = NumberSequence.new(keypoints)
end

local function layer(parent: GuiObject, zIndex: number, height: number?): Frame
	local frame = UiKit.create("Frame", {
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Size = if height then UDim2.new(1, 0, 0, height) else UDim2.fromScale(1, 1),
		ZIndex = zIndex,
	}) :: Frame
	frame.Parent = parent
	return frame
end

--- Paints a wash onto `parent`. Layers are added as children, bottom first, so
--- the caller's viewport has to sit at a higher `ZIndex` than `spec.zIndex`.
function StageBackdrop.paint(parent: GuiObject, spec: Spec): Handle
	local zIndex = spec.zIndex or 1
	local tile = spec.tile == true
	local radius = spec.radius or Theme.Radius.md
	local height = spec.height
	local depthAmount = spec.depth or DEEP

	local layers: { Frame } = {}

	local function add(color: Color3, rotation: number, stops: { Stop }): Frame
		local frame = layer(parent, zIndex, height)
		UiKit.corner(frame, radius)
		frame.BackgroundColor3 = color
		local gradient = UiKit.gradient(frame, { color, color }, rotation)
		ramp(gradient, stops)
		table.insert(layers, frame)
		return frame
	end

	-- 1. Base ramp. Opaque: it is the floor of the wash, and it is what makes
	-- the stage read as a lit room instead of as a black rectangle.
	local depth = layer(parent, zIndex, height)
	UiKit.corner(depth, radius)
	local depthGradient = UiKit.gradient(depth, {
		deep(spec.cool, depthAmount),
		deep(spec.warm, depthAmount),
	}, spec.rotation or 90)
	table.insert(layers, depth)

	-- 2. Crossed bands. Two is the minimum that reads as light rather than as a
	-- stripe; four is where the union stops looking like a plus. On a full stage
	-- the band is narrowed around the middle so it reads as a glow; on a 136px
	-- card the same narrowing would read as a stripe, so tiles keep the wide ramp.
	local function bloomStops(alpha: number): { Stop }
		if tile then
			return { { 0, 1 }, { 0.5, alpha }, { 1, 1 } }
		end
		return { { 0, 1 }, { 0.32, 1 }, { 0.5, alpha }, { 0.68, 1 }, { 1, 1 } }
	end

	local warmBloom = add(spec.warm, 90, bloomStops(if tile then 0.74 else 0.78))
	local coolBloom = add(spec.cool, 0, bloomStops(if tile then 0.76 else 0.81))

	local accent = spec.accent or spec.warm
	local diagonalWarm: Frame? = nil
	local diagonalCool: Frame? = nil
	if not tile then
		diagonalWarm = add(accent, 42, {
			{ 0, 1 },
			{ 0.5, 0.9 },
			{ 1, 1 },
		})
		diagonalCool = add(accent, 138, {
			{ 0, 1 },
			{ 0.5, 0.91 },
			{ 1, 1 },
		})
	end

	-- 3. Rim shaft. A narrow band of the accent light, raked across the stage at
	-- the same angle the key light strikes the blade. The offset is what keeps
	-- it off centre: a beam through the middle would read as a seam.
	local shaft: Frame? = nil
	if not tile then
		shaft = add(accent, 118, {
			{ 0, 1 },
			{ 0.34, 0.9 },
			{ 0.58, 1 },
			{ 1, 1 },
		})
		shaft.BackgroundTransparency = 0.12
	end

	-- 4. Vignette. Rotation 270 puts offset 0 at the bottom, so the floor goes
	-- dark and the wash lifts toward the top of the frame. A card well is 136px
	-- tall and carries its own settle plate, so its floor stays much lighter.
	local vignette = add(Theme.Color.void, 270, if tile
		then { { 0, 0.18 }, { 0.62, 0.78 }, { 1, 1 } }
		else { { 0, 0.04 }, { 0.62, 0.68 }, { 1, 1 } })
	vignette.BackgroundColor3 = Theme.Color.void

	-- 5. Settle. One plate of the parent surface colour, opaque at the bottom
	-- edge and transparent at the top, so the art dissolves into the card.
	if spec.settle then
		local settleHeight = spec.settleHeight or 40
		local settle = UiKit.create("Frame", {
			BackgroundColor3 = spec.settle,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, settleHeight),
			Position = UDim2.new(0, 0, 1, -settleHeight),
			ZIndex = zIndex,
		}) :: Frame
		UiKit.corner(settle, radius)
		local gradient = UiKit.gradient(settle, { spec.settle, spec.settle }, 90)
		ramp(gradient, {
			{ 0, 1 },
			{ 0.55, 0.18 },
			{ 1, 0 },
		})
		settle.Parent = parent
		table.insert(layers, settle)
	end

	local handle: Handle = {
		layers = layers,
		setColors = function(warm: Color3, cool: Color3, accentColor: Color3?)
			local rim = accentColor or warm
			depthGradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, deep(cool, depthAmount)),
				ColorSequenceKeypoint.new(1, deep(warm, depthAmount)),
			})
			warmBloom.BackgroundColor3 = warm
			local warmGradient = warmBloom:FindFirstChildOfClass("UIGradient")
			if warmGradient then
				warmGradient.Color = ColorSequence.new(warm, warm)
			end
			coolBloom.BackgroundColor3 = cool
			local coolGradient = coolBloom:FindFirstChildOfClass("UIGradient")
			if coolGradient then
				coolGradient.Color = ColorSequence.new(cool, cool)
			end
			if diagonalWarm then
				diagonalWarm.BackgroundColor3 = rim
				local gradient = diagonalWarm:FindFirstChildOfClass("UIGradient")
				if gradient then
					gradient.Color = ColorSequence.new(rim, rim)
				end
			end
			if diagonalCool then
				diagonalCool.BackgroundColor3 = rim
				local gradient = diagonalCool:FindFirstChildOfClass("UIGradient")
				if gradient then
					gradient.Color = ColorSequence.new(rim, rim)
				end
			end
			if shaft then
				shaft.BackgroundColor3 = rim
				local gradient = shaft:FindFirstChildOfClass("UIGradient")
				if gradient then
					gradient.Color = ColorSequence.new(rim, rim)
				end
			end
		end,
	}

	return handle
end

return StageBackdrop
