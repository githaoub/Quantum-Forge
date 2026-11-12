--!strict
-- Feedback layer: floating numbers, impact bursts, panel shake, screen flash.
--
-- Everything here is transient and self-recycling. The effect layer is a single
-- un-clipped frame above the HUD; the screen wash lives on its own ScreenGui so it
-- can cover the top bar. Nothing persists past ~1.2 seconds.
--
-- Coordinate note: the layer lives inside the UIScaled canvas, so a screen-space
-- position from `AbsolutePosition` has to be divided back by the scale factor.
-- Everything funnels through `toLocal`.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")

local Theme = require(script.Parent.Theme)
local UiKit = require(script.Parent.UiKit)

local Vfx = {}

local layer: Frame? = nil
--- The flash lives on the ScreenGui, not the canvas. The canvas is measured to
--- the game area, so a wash inside it stops at the letterbox on a narrow window
--- and sits under the crate ceremony. The ScreenGui is the real screen.
local flashLayer: Frame? = nil
local scaleFactor = 1

-- Player preferences. Effects are the first thing a low-end device turns off,
-- so every decorative path checks these before allocating a frame. Floating
-- numbers are information and stay on; particles, rings and flashes are not.
local enabled = true
local shakeEnabled = true

function Vfx.setEnabled(value: boolean)
	enabled = value
end

function Vfx.isEnabled(): boolean
	return enabled
end

function Vfx.setShakeEnabled(value: boolean)
	shakeEnabled = value
end

--- One running shake per target, plus the position that target rests at.
---
--- `Vfx.shake` used to read `target.Position` at the start of every call. Under
--- rapid clicking that value is whatever the previous shake left behind, because
--- a new shake begins while the old one is still mid-offset. Each call then
--- adopted a displaced position as home and restored it, so the anvil walked a
--- few pixels per click. Measured over a minute of clicking, "STRIKE THE ANVIL"
--- crossed the Core Heat bar and hung past the card's right border.
---
--- The registry is weak-keyed, so a destroyed button is not held alive by it.
type ShakeState = {
	rest: UDim2,
	connection: RBXScriptConnection?,
}

local shakes = setmetatable({}, { __mode = "k" }) :: { [GuiObject]: ShakeState }

local function stateOf(target: GuiObject): ShakeState
	local state = shakes[target]
	if state == nil then
		state = { rest = target.Position, connection = nil }
		shakes[target] = state
	elseif state.connection == nil then
		-- Nothing is animating it right now, so wherever it sits is home. This is
		-- what lets a control be re-laid-out between shakes without the shake
		-- dragging it back to a stale position.
		state.rest = target.Position
	end
	return state
end

--- Forgets a target's recorded rest position and stops any shake on it. Call
--- this from a teardown path, or after deliberately moving a control that has
--- been shaken.
function Vfx.forgetRest(target: GuiObject)
	local state = shakes[target]
	if state and state.connection then
		state.connection:Disconnect()
	end
	shakes[target] = nil
end

--- Builds (or adopts) the wash layer. Called from `init` and lazily from
--- `flash`, because a flash that silently no-ops when init ran before the
--- PlayerGui existed is the worst possible failure for a feedback effect: the
--- player sees nothing and has no way to tell why.
---
--- Idempotent on purpose. A second init reuses the existing ScreenGui instead of
--- leaving a duplicate one at the same DisplayOrder behind it.
local function ensureFlashLayer(): Frame?
	local playerGui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return nil
	end

	local screen = playerGui:FindFirstChild("VfxScreen")
	if screen and not screen:IsA("ScreenGui") then
		screen:Destroy()
		screen = nil
	end
	if screen == nil then
		screen = UiKit.create("ScreenGui", {
			Name = "VfxScreen",
			DisplayOrder = 500,
			IgnoreGuiInset = true,
			ResetOnSpawn = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		}) :: ScreenGui
		screen.Parent = playerGui
	end

	local existing = (screen :: ScreenGui):FindFirstChild("VfxFlash")
	if existing and existing:IsA("Frame") then
		flashLayer = existing
		return existing
	end

	local created = UiKit.create("Frame", {
		Name = "VfxFlash",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
	}) :: Frame
	created.Parent = screen
	flashLayer = created
	return created
end

function Vfx.init(canvas: Frame, uiScale: UIScale)
	layer = UiKit.create("Frame", {
		Name = "Vfx",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 40,
		ClipsDescendants = false,
	}) :: Frame
	layer.Parent = canvas
	scaleFactor = uiScale.Scale

	-- The wash layer. It gets its own ScreenGui rather than a frame on the game
	-- screen, for two reasons that both showed up in playtest:
	--
	-- 1. `UiKit.screen` sets `IgnoreGuiInset = false`, so the game ScreenGui
	--    starts below the Roblox top bar. A wash inside it leaves a strip of
	--    untouched screen along the top, which is exactly what "not full screen"
	--    looks like.
	-- 2. The crate ceremony and the guide layer are siblings with their own
	--    ZIndex. A wash has to land on top of all of them.
	--
	-- A dedicated ScreenGui with `IgnoreGuiInset = true` and a DisplayOrder above
	-- every other UI covers the raw viewport and the top bar at once. It has no
	-- input surface: nothing here is clickable.
	ensureFlashLayer()

	-- The canvas scale changes when the window resizes; keep the conversion
	-- honest rather than baking a stale value.
	uiScale:GetPropertyChangedSignal("Scale"):Connect(function()
		scaleFactor = uiScale.Scale
	end)
end

local function toLocal(screen: Vector2): Vector2
	if layer == nil then
		return screen
	end
	return (screen - layer.AbsolutePosition) / scaleFactor
end

--- Where a GUI object's centre sits, in the VFX layer's coordinate space.
local function anchorCentre(anchor: GuiObject): Vector2
	return toLocal(anchor.AbsolutePosition + anchor.AbsoluteSize * 0.5)
end

--- The cursor, in the VFX layer's coordinate space.
---
--- `within` is the rect the pointer has to actually be over. The forge passes its
--- own card, so a player striking with Space while their mouse is parked over the
--- top bar gets the ring on the anvil rather than a shockwave inside a currency
--- pill. Returns nil when the pointer is outside, and every caller falls back to
--- the anchor's centre.
---
--- `GetMouseLocation` is viewport space, measured from the top of the window.
--- `AbsolutePosition` is GUI space, measured from the inset edge. On this build
--- the canvas sits at GUI (0, 0) while the inset is 36px, so the two conventions
--- disagree by exactly the inset: measured live, a ring fired at a click on
--- y = 300 landed at y = 336. The inset is subtracted here once.
function Vfx.pointer(within: GuiObject?): Vector2?
	if layer == nil then
		return nil
	end
	local point = UserInputService:GetMouseLocation()
	local inset = GuiService:GetGuiInset()
	point = point - Vector2.new(inset.X, inset.Y)
	if within then
		local min = within.AbsolutePosition
		local max = min + within.AbsoluteSize
		if point.X < min.X or point.Y < min.Y or point.X > max.X or point.Y > max.Y then
			return nil
		end
	end
	return toLocal(point)
end

-- ---------------------------------------------------------------------------
-- Floating numbers
-- ---------------------------------------------------------------------------

export type FloatOpts = {
	color: Color3?,
	size: number?,
	crit: boolean?,
	drift: number?,
}

type Spark = {
	frame: Frame,
	pos: Vector2,
	vel: Vector2,
	size: number,
	spin: number,
	angle: number,
}

--- Rises and fades a number from the anchor's centre. Called on every accepted
--- click, so it stays deliberately cheap: one label, one tween pair.
function Vfx.float(anchor: GuiObject, text: string, opts: FloatOpts?)
	if layer == nil then
		return
	end

	local o = opts or {}
	local origin = anchorCentre(anchor)
	local jitterX = math.random(-38, 38)
	local jitterY = math.random(-14, 8)

	local label = UiKit.create("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = o.color or Theme.Color.starMatter,
		TextSize = o.size or (if o.crit then Theme.Text.Title else Theme.Text.Subheading),
		Font = if o.crit then Theme.Font.Display else Theme.Font.Numeric,
		TextStrokeTransparency = 0.4,
		TextStrokeColor3 = if o.crit then Theme.Color.aetherDeep else Theme.Color.ink,
		TextTransparency = 0.15,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(origin.X + jitterX, origin.Y + jitterY),
		Size = UDim2.fromOffset(260, 40),
	}) :: TextLabel
	label.Parent = layer

	local rise = o.drift or 74
	local duration = if o.crit then 1.0 else 0.78

	if Theme.reducedMotion() then
		-- The number still appears and still fades — that is the feedback that the
		-- click landed. It just does not travel or punch.
		Theme.fade(label, duration, { TextTransparency = 1, TextStrokeTransparency = 1 })
	else
		UiKit.tween(label, duration, {
			Position = UDim2.fromOffset(origin.X + jitterX * 1.4, origin.Y + jitterY - rise),
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})

		if o.crit then
			-- Crits get a scale pop on top of the rise. UIScale rather than Size so
			-- the pop is a transform, not a layout change: the label is anchored by
			-- its centre, so scaling it cannot reflow anything.
			local pop = UiKit.create("UIScale", { Scale = 0.82 }) :: UIScale
			pop.Parent = label
			UiKit.tween(pop, 0.12, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end

	task.delay(duration + 0.05, function()
		if label.Parent then
			label:Destroy()
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Bursts
-- ---------------------------------------------------------------------------

--- Radial spark burst at a screen position. `power` scales speed and count.
function Vfx.burst(anchor: GuiObject, color: Color3, power: number?)
	if layer == nil or not enabled then
		return
	end

	-- Radial travel is pure decoration; under reduce motion it is simply omitted.
	if Theme.reducedMotion() then
		return
	end

	local p = power or 1
	local origin = anchorCentre(anchor)
	local count = math.floor(8 * p)
	local distance = 70 * p

	for index = 1, count do
		local angle = (index / count) * math.pi * 2 + math.random() * 0.5
		local speed = distance * (0.55 + math.random() * 0.65)

		local spark = UiKit.create("Frame", {
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(origin.X, origin.Y),
			Size = UDim2.fromOffset(6, 6),
			BackgroundTransparency = 0.1,
			ZIndex = 41,
		}) :: Frame
		UiKit.corner(spark, 3)
		spark.Parent = layer

		UiKit.tween(spark, 0.42, {
			Position = UDim2.fromOffset(
				origin.X + math.cos(angle) * speed,
				origin.Y + math.sin(angle) * speed
			),
			Size = UDim2.fromOffset(2, 2),
			BackgroundTransparency = 1,
		}, Enum.EasingStyle.Quart)

		task.delay(0.48, function()
			if spark.Parent then
				spark:Destroy()
			end
		end)
	end
end

-- ---------------------------------------------------------------------------
-- Shockwave ring
-- ---------------------------------------------------------------------------

export type ShockOpts = {
	--- Diameter the ring starts at, in design pixels.
	size: number?,
	--- Growth multiplier over the life of the ring. 2.6 is a tight strike
	--- ripple; a forge or a streak burst wants 4+.
	spread: number?,
	duration: number?,
	--- Stroke weight of the crisp inner ring.
	thickness: number?,
	--- Explicit centre, in the VFX layer's coordinate space. Set from
	--- `Vfx.pointer` to put a strike ripple under the cursor instead of under the
	--- middle of the stage. When nil the ring centres on the anchor.
	at: Vector2?,
}

--- Expanding ring ripple centred on the anchor. The outline is the whole
--- effect: a transparent frame carrying a `UIStroke`, scaled outward while the
--- stroke fades. Two rings, one crisp and one soft, so the ripple has a bright
--- leading edge and a halo behind it instead of reading as a flat circle.
---
--- Under reduce-motion the ripple is omitted entirely rather than drawn at rest,
--- which is the same rule the bursts follow: a still ring is a decoration, and a
--- decoration that appears and never moves is worse than none.
function Vfx.shockwave(anchor: GuiObject, color: Color3, opts: ShockOpts?)
	if layer == nil or Theme.reducedMotion() or not enabled then
		return
	end

	local host = layer
	if host == nil then
		return
	end

	local o = opts or {}
	local origin = o.at or anchorCentre(anchor)
	local start = o.size or 46
	local finish = start * (o.spread or 2.6)
	local duration = o.duration or 0.34

	local ring = UiKit.create("Frame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(origin.X, origin.Y),
		Size = UDim2.fromOffset(start, start),
		ZIndex = 42,
	}) :: Frame
	UiKit.corner(ring, Theme.Radius.round)
	ring.Parent = host

	local edge = UiKit.create("UIStroke", {
		Color = color,
		Thickness = o.thickness or 3,
		Transparency = 0.05,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}) :: UIStroke
	edge.Parent = ring

	local halo = UiKit.create("UIStroke", {
		Color = color,
		Thickness = (o.thickness or 3) * 2.6,
		Transparency = 0.55,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}) :: UIStroke
	halo.Parent = ring

	UiKit.tween(ring, duration, {
		Size = UDim2.fromOffset(finish, finish),
	}, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	UiKit.tween(edge, duration, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	UiKit.tween(halo, duration, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	task.delay(duration + 0.04, function()
		if ring.Parent then
			ring:Destroy()
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Ballistic sparks
-- ---------------------------------------------------------------------------

--- Sparks thrown up out of the anchor and pulled back down by gravity.
---
--- `burst` radiates evenly and shrinks on a straight line, which reads as a
--- flash. This is the physical version: a cone, real acceleration, and a spin
--- per spark. One RenderStepped connection drives the whole batch — a
--- connection per spark would be 15 listeners competing with the UI's own.
function Vfx.sparks(anchor: GuiObject, color: Color3, count: number?, power: number?)
	if layer == nil or Theme.reducedMotion() or not enabled then
		return
	end

	local host = layer
	if host == nil then
		return
	end

	local origin = anchorCentre(anchor)
	local n = math.clamp(count or 10, 1, 40)
	local p = power or 1

	local sparks: { Spark } = {}
	for _ = 1, n do
		local size = math.random(3, 7)
		local frame = UiKit.create("Frame", {
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(origin.X, origin.Y),
			Size = UDim2.fromOffset(size, size),
			BackgroundTransparency = math.random(0, 20) / 100,
			ZIndex = 41,
		}) :: Frame
		UiKit.corner(frame, 1)
		frame.Parent = host

		-- Upward cone, not a ring: a strike throws material up and it falls back.
		local spread = (math.random() - 0.5) * math.rad(120)
		local speed = (150 + math.random() * 230) * p
		table.insert(sparks, {
			frame = frame,
			pos = origin,
			vel = Vector2.new(math.sin(spread), -math.cos(spread)) * speed,
			size = size,
			spin = (math.random() - 0.5) * 420,
			angle = math.random() * 360,
		})
	end

	local LIFE = 0.75
	local remaining = LIFE
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt: number)
		remaining -= dt
		if remaining <= 0 or host.Parent == nil then
			for _, spark in sparks do
				if spark.frame.Parent then
					spark.frame:Destroy()
				end
			end
			connection:Disconnect()
			return
		end

		local age = 1 - remaining / LIFE
		for _, spark in sparks do
			spark.vel += Vector2.new(0, 1450 * dt)
			spark.pos += spark.vel * dt
			spark.angle += spark.spin * dt

			local shrink = 1 - age * 0.55
			spark.frame.Position = UDim2.fromOffset(spark.pos.X, spark.pos.Y)
			spark.frame.Rotation = spark.angle
			spark.frame.Size = UDim2.fromOffset(spark.size * shrink, spark.size * shrink)
			spark.frame.BackgroundTransparency = math.clamp(age * 1.25, 0, 1)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Shake
-- ---------------------------------------------------------------------------
--- Shakes a GUI object in place. Overlapping calls supersede each other rather
--- than stacking, so a rapid click flood cannot tear the layout: the second call
--- restores the recorded rest position, drops the first connection, and starts a
--- fresh offset from there.
function Vfx.shake(target: GuiObject, magnitude: number?, duration: number?)
	-- Shake is one of the first things a motion-sensitive player turns off.
	if Theme.reducedMotion() or not shakeEnabled or not enabled then
		return
	end

	local state = stateOf(target)
	if state.connection then
		state.connection:Disconnect()
	end

	local mag = magnitude or 6
	local span = duration or 0.24
	local remaining = span

	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt)
		local finished = not target.Parent
		if not finished then
			remaining -= dt
			finished = remaining <= 0
		end
		if finished then
			target.Position = state.rest
			connection:Disconnect()
			if state.connection == connection then
				state.connection = nil
			end
			return
		end

		-- Decay the amplitude so the shake settles instead of stopping dead.
		local falloff = remaining / span
		target.Position = state.rest
			+ UDim2.fromOffset(
				(math.random() * 2 - 1) * mag * falloff,
				(math.random() * 2 - 1) * mag * falloff
			)
	end)
	state.connection = connection
end

--- Shakes the whole HUD, not one control.
---
--- The canvas holds every panel, so a few pixels here is the screen taking the
--- hit while the wash layer stays still. It supersedes rather than stacks for the
--- same reason `Vfx.shake` does: ten clicks a second must not walk the layout.
function Vfx.shakeScreen(magnitude: number?, duration: number?)
	local canvas = layer and layer.Parent
	if canvas and canvas:IsA("GuiObject") then
		Vfx.shake(canvas, magnitude, duration)
	end
end

-- ---------------------------------------------------------------------------
-- Lightning
-- ---------------------------------------------------------------------------

--- Jagged bolts thrown up out of a control. Segments are rotated rectangles,
--- not images, so there is no upload dependency and the shape re-rolls every
--- time. Used on crits and on Void/Prismatic forge results.
function Vfx.lightning(anchor: GuiObject, color: Color3, power: number?)
	if layer == nil or Theme.reducedMotion() or not enabled then
		return
	end

	local host = layer
	if host == nil then
		return
	end

	local origin = anchorCentre(anchor)
	local p = power or 1
	local bolts = 4
	local segments = 5

	for bolt = 1, bolts do
		local angle = -math.pi / 2 + (bolt - (bolts + 1) * 0.5) * 0.3 + (math.random() - 0.5) * 0.18
		local x, y = origin.X, origin.Y
		local step = (18 + math.random() * 10) * p

		for segment = 1, segments do
			local nx = x + math.cos(angle) * step + (math.random() - 0.5) * 12
			local ny = y + math.sin(angle) * step + (math.random() - 0.5) * 12
			local dx, dy = nx - x, ny - y
			local length = math.sqrt(dx * dx + dy * dy)
			local thickness = math.max(1, 3 - segment * 0.35)

			local shard = UiKit.create("Frame", {
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset((x + nx) * 0.5, (y + ny) * 0.5),
				Size = UDim2.fromOffset(length, thickness),
				Rotation = math.deg(math.atan2(dy, dx)),
				BackgroundTransparency = 0.1,
				ZIndex = 43,
			}) :: Frame
			shard.Parent = host

			UiKit.tween(shard, 0.18 + segment * 0.02, {
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(length * 0.55, 1),
			}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

			task.delay(0.26, function()
				if shard.Parent then
					shard:Destroy()
				end
			end)

			x, y = nx, ny
			angle += (math.random() - 0.5) * 0.48
			step *= 0.86
		end
	end
end

-- ---------------------------------------------------------------------------
-- Composite beats
-- ---------------------------------------------------------------------------

--- One anvil hit, all four layers in the right order: ballistic sparks, a tight
--- ground ring, and on a crit a bolt plus a shallow flash. Callers pass the
--- anchor they already have; the composite owns the layering so no two views
--- invent their own version of "a strike".
function Vfx.strikeBurst(anchor: GuiObject, color: Color3, power: number?, crit: boolean?)
	if not enabled then
		return
	end
	local p = power or 1
	Vfx.sparks(anchor, color, math.floor(10 * p), p)
	Vfx.shockwave(anchor, color, {
		size = 32,
		spread = 2.1 + p * 0.5,
		duration = 0.28,
		thickness = 2,
	})
	if crit then
		Vfx.lightning(anchor, color, 1.1)
		Vfx.flash(color, 0.07)
		-- The crit ring is the shape the player learns to look for. The 32px
		-- ripple above is too close to the hit to read as a signature, and the
		-- sprite sheet that used to carry the 420px disc is still unuploaded, so
		-- the procedural fallback has to own the scale.
		Vfx.shockwave(anchor, color, {
			size = 180,
			spread = 3.2,
			duration = 0.55,
			thickness = 6,
		})
	end
end

--- The tiny scuff under a button press. Deliberately four sparks, not a burst:
--- every tap in the game goes through here, so it has to cost almost nothing.
function Vfx.uiSpark(anchor: GuiObject, color: Color3)
	if not enabled or Theme.reducedMotion() then
		return
	end
	Vfx.sparks(anchor, color, 4, 0.55)
end

--- Forge result wash. Rank is 1-5: Standard through Prismatic. The top two
--- ranks get lightning and a wider ring, so the variant is readable from the
--- other side of the screen without reading the toast.
function Vfx.resultWash(anchor: GuiObject, color: Color3, rank: number)
	if not enabled then
		return
	end
	local r = math.clamp(rank, 1, 5)
	Vfx.sparks(anchor, color, 14 + r * 5, 1.1 + r * 0.18)
	Vfx.shockwave(anchor, color, {
		size = 90,
		spread = 3.2 + r * 0.35,
		duration = 0.5 + r * 0.04,
		thickness = 3 + r * 0.4,
	})
	Vfx.flash(color, 0.06 + r * 0.025)
	if r >= 4 then
		Vfx.lightning(anchor, color, 1.3)
	end
end

-- ---------------------------------------------------------------------------
-- Ambient embers
-- ---------------------------------------------------------------------------

export type EmberOpts = {
	count: number?,
	color: Color3?,
	--- Fraction of the anchor's height where embers are allowed to spawn.
	floor: number?,
}

--- Slow embers drifting up the face of a card. One pool, one RenderStepped
--- connection, recycled frames: a fireplace made of tweens would allocate a
--- frame every second and leave it to the GC mid-scroll.
---
--- Returns a cleanup function. The caller owns it and must call it from the
--- view's destroy path; the loop also self-terminates if the anchor is destroyed.
function Vfx.ambientEmbers(anchor: GuiObject, opts: EmberOpts?): () -> ()
	if layer == nil or Theme.reducedMotion() or not enabled then
		return function() end
	end

	local host = layer
	if host == nil then
		return function() end
	end

	local o = opts or {}
	local color = o.color or Theme.Color.starMatter
	local count = math.clamp(o.count or 14, 1, 40)
	local floor = math.clamp(o.floor or 0.35, 0, 1)

	local frames: { Frame } = {}
	local seeds: { { x: number, y: number, speed: number, drift: number, phase: number, size: number } } = {}

	local function rect(): (number, number, number, number)
		local left = (anchor.AbsolutePosition.X - host.AbsolutePosition.X) / scaleFactor
		local top = (anchor.AbsolutePosition.Y - host.AbsolutePosition.Y) / scaleFactor
		local width = anchor.AbsoluteSize.X / scaleFactor
		local height = anchor.AbsoluteSize.Y / scaleFactor
		return left, top, width, height
	end

	local spawnedLeft, spawnedTop, spawnedWidth, spawnedHeight = rect()

	for index = 1, count do
		local size = math.random(20, 44) / 10
		local frame = UiKit.create("Frame", {
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(size, size),
			BackgroundTransparency = math.random(55, 88) / 100,
			ZIndex = 40,
		}) :: Frame
		UiKit.corner(frame, 2)
		frame.Parent = host
		frames[index] = frame
		seeds[index] = {
			x = spawnedLeft + math.random() * spawnedWidth,
			y = spawnedTop + spawnedHeight * (floor + math.random() * (1 - floor)),
			speed = 14 + math.random() * 26,
			drift = 4 + math.random() * 10,
			phase = math.random() * math.pi * 2,
			size = size,
		}
	end

	local clock = 0
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt: number)
		local alive = anchor.Parent ~= nil and host.Parent ~= nil and enabled
		if not alive then
			for _, frame in frames do
				if frame.Parent then
					frame:Destroy()
				end
			end
			connection:Disconnect()
			return
		end

		local step = math.min(dt, 0.1)
		clock += step
		for index, seed in seeds do
			seed.y -= seed.speed * step
			local x = seed.x + math.sin(clock * 0.9 + seed.phase) * seed.drift
			if seed.y < spawnedTop - 12 then
				-- Re-read the rect on respawn so a resized canvas does not
				-- leave the whole column spawning off the panel.
				spawnedLeft, spawnedTop, spawnedWidth, spawnedHeight = rect()
				seed.x = spawnedLeft + math.random() * spawnedWidth
				seed.y = spawnedTop + spawnedHeight * (0.92 + math.random() * 0.08)
				seed.speed = 14 + math.random() * 26
				seed.phase = math.random() * math.pi * 2
			end
			local frame = frames[index]
			frame.Position = UDim2.fromOffset(x, seed.y)
			frame.Size = UDim2.fromOffset(seed.size, seed.size)
			frame.BackgroundTransparency = math.clamp(0.55 + (seed.y - spawnedTop) / math.max(1, spawnedHeight) * 0.3, 0.55, 0.92)
		end
	end)

	return function()
		if connection.Connected then
			connection:Disconnect()
		end
		for _, frame in frames do
			if frame.Parent then
				frame:Destroy()
			end
		end
		table.clear(frames)
		table.clear(seeds)
	end
end

-- ---------------------------------------------------------------------------
-- Screen flash
-- ---------------------------------------------------------------------------

--- Full-screen colour wash that fades immediately. Used for ascension, crits,
--- overheat and the crate's white pop. Deliberately subtle by default, because a
--- flash that lingers is a headache.
---
--- `duration` overrides the fade when the caller needs the wash to match a
--- shorter stage beat. The frame is parented to `flashLayer` on its own ScreenGui
--- so the wash reaches the letterbox and the top bar, not just the canvas.
---
--- Three frames recycled round-robin rather than one frame per call: the strike
--- fires this on every click, and at ten clicks a second a fresh instance plus a
--- fresh tween twice a second is exactly the kind of churn that shows up as a
--- hitch on a phone. Round-robin also means a second flash mid-fade takes its own
--- frame instead of cancelling the first one and popping.
local WASH_FRAMES = 3
local washPool: { Frame } = {}
local washTweens: { [Frame]: Tween } = {}
local washIndex = 1

function Vfx.flash(color: Color3, peak: number?, duration: number?)
	if not enabled then
		return
	end
	local host = flashLayer
	if host == nil or host.Parent == nil then
		host = ensureFlashLayer()
	end
	if host == nil then
		return
	end

	local fade = duration or 0.5
	local wash = washPool[washIndex]
	if wash == nil then
		wash = UiKit.create("Frame", {
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 1,
		}) :: Frame
		wash.Parent = host
		washPool[washIndex] = wash
	else
		local running = washTweens[wash]
		if running then
			running:Cancel()
		end
		if wash.Parent ~= host then
			wash.Parent = host
		end
	end
	washIndex = washIndex % WASH_FRAMES + 1

	wash.BackgroundColor3 = color
	wash.BackgroundTransparency = 1 - math.clamp(peak or 0.35, 0, 1)

	-- A wash is a colour change, not travel, so it survives reduce motion; it is
	-- just shortened.
	washTweens[wash] = UiKit.tween(
		wash,
		if Theme.reducedMotion() then math.min(0.12, fade) else fade,
		{ BackgroundTransparency = 1 }
	)
end

return Vfx
