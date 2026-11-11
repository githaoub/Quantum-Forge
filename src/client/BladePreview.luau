--!strict
-- Hosts a blade inside a ViewportFrame: build, pivot, camera, orbit.
--
-- Geometry comes from `BladeModelBuilder`, which has a hand-written recipe for
-- every id in the registry plus the uploaded mesh path. That module owns *what a
-- sword looks like*; this one owns *how it is framed and moved*, so the
-- inventory thumbnail and the forge hero shot share one camera solve and one
-- pose.
--
-- Motion is delegated to `ViewportOrbitController`: idle turn, drag-to-orbit and
-- a smooth resume on release. A strike still feeds the controller a yaw impulse
-- and a pitch slam, so the blade answers the anvil without fighting the player's
-- hand.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BladeRegistry = require(Shared:WaitForChild("BladeRegistry"))

local Theme = require(script.Parent.Theme)
local BladeModelBuilder = require(script.Parent.BladeModelBuilder)
local OrbitController = require(script.Parent.ViewportOrbitController)

local BladePreview = {}

-- Angular velocity injected by a strike. Module-level because there is exactly
-- one full-size preview on screen; `react()` has to reach whichever model the
-- render loop is currently moving.
local kick = 0

-- Forward pitch from a slam, in radians. Separate from `kick` because it decays
-- an order of magnitude faster: the spin is the recovery, the slam is the impact.
local slam = 0

-- Emissive flash. The neon parts of whichever model is mounted are cached with
-- their base colours, so a strike can drive every glow surface white for a beat
-- without a `GetDescendants` walk on the click path.
local flash = 0
local glowParts: { [BasePart]: Color3 } = {}
local glowApplied = false

local FLASH_WHITE = Color3.new(1, 1, 1)

local function applyGlow(level: number)
	if level <= 0.004 then
		if not glowApplied then
			return
		end
		glowApplied = false
		for part, base in glowParts do
			if part.Parent ~= nil then
				part.Color = base
			end
		end
		return
	end
	glowApplied = true
	local blend = math.min(level, 1) * 0.8
	for part, base in glowParts do
		if part.Parent ~= nil then
			part.Color = base:Lerp(FLASH_WHITE, blend)
		end
	end
end

--- Re-reads the live model's emissive surfaces. Called on mount and on every
--- mesh hot-swap, because `applyMesh` replaces the parts underneath us.
local function collectGlow(model: Model, tint: Color3?)
	table.clear(glowParts)
	for _, child in model:GetDescendants() do
		if child:IsA("BasePart") and child.Material == Enum.Material.Neon then
			-- The variant lives on the emissive surfaces. Tinting the steel as
			-- well turns a blade into a coloured toy; tinting only the glow
			-- keeps the silhouette and lets the forge palette read in the dark.
			local base = if tint then child.Color:Lerp(tint, 0.62) else child.Color
			glowParts[child] = base
			child.Color = base
		end
	end
end

--- Nudges the turntable and pitches the blade forward. Fired on every anvil
--- strike so the blade answers the hit instead of sitting still while the
--- button shakes.
---
--- `slam` is capped at ~1 rad rather than accumulating without bound: two rapid
--- clicks should read as two hits, not as the blade spinning out of frame.
function BladePreview.react(strength: number?)
	local s = strength or 3.4
	kick = math.min(kick + s, 9)
	flash = math.min(flash + 0.62, 1)
	if not Theme.reducedMotion() then
		slam = math.min(slam + 0.34 + s * 0.06, 1.05)
	end
end

--- Centre and size of the axis-aligned box around every part under `root`.
--- Owned by `BladeModelBuilder` because the mesh path needs it too; re-exported
--- here so the two never disagree about what a model's extents are.
local boundsOf = BladeModelBuilder.bounds

--- Ensures the model has an explicit pivot part and returns it.
---
--- Without a PrimaryPart the model pivot is whatever the engine last computed,
--- and `PivotTo` is measured against that. Live: the camera framed a blade whose
--- measured centre was 2.00, and the blade then sat at 1.78 — a 0.22-stud drift
--- that pushed the hilt out of frame. An invisible part at the hilt base pins
--- the pivot, and gives the turntable a sensible axis: the haft, not the middle
--- of the blade.
local function ensurePivot(model: Model): BasePart
	local existing = model:FindFirstChild("Pivot")
	if existing ~= nil and existing:IsA("BasePart") then
		model.PrimaryPart = existing
		return existing
	end

	local pivot = Instance.new("Part")
	pivot.Name = "Pivot"
	pivot.Size = Vector3.new(0.01, 0.01, 0.01)
	pivot.Transparency = 1
	pivot.Anchored = true
	pivot.CanCollide = false
	pivot.CanTouch = false
	pivot.CanQuery = false
	pivot.CastShadow = false
	pivot.CFrame = CFrame.new(0, 0, 0)
	pivot.Parent = model
	model.PrimaryPart = pivot
	return pivot
end

-- Hero pose. 25 degrees of yaw and 20 of roll: the reference the brief asked
-- for, and the reason a flat slab reads as a sword instead of a scratch down the
-- middle of an empty box. Yaw is the turntable on the hero shot, so only the
-- static thumbnails bake it in.
local HERO_YAW = math.rad(25)
local HERO_ROLL = math.rad(-20)
local HERO_PITCH = math.rad(-5)

-- Fraction of the frame height the blade should occupy. 0.80 is the brief;
-- LEAN_PAD covers the projection of the lean, which taller-than-wide geometry
-- loses a few percent of after the roll. Net fill lands around 78%.
local FRAME_FILL = 0.80
local LEAN_PAD = 1.04
local AZIMUTH = math.rad(26)
local ELEVATION = math.rad(12)

-- Yaw for the static thumbnails. The blade mesh is built with its flat facing
-- local +X and its width on local Z (a 5.4-stud blade is 1.83 wide and 0.56
-- thick), and the thumbnail camera sits 26 degrees off -Z. Baking the hero yaw
-- of 25 there leaves the flat almost edge-on, so a 69px card renders a hairline
-- instead of a sword. Facing the camera means putting the flat normal on the
-- camera direction, which is 90 - AZIMUTH; the extra 18 degrees is the same
-- three-quarter turn the hero pose uses, kept so the copy has a lit side and a
-- shadowed side instead of reading flat.
local THUMB_YAW = math.pi * 0.5 - AZIMUTH - math.rad(18)

--- Places a camera so the model fills `FRAME_FILL` of the frame height, three
--- quarters from the front-left with a slight downward bias. Shared by the hero
--- viewport and the thumbnails so the two never disagree about scale.
---
--- `fill` and `bias` let the forge ask for a smaller blade inside a taller
--- stage: the full-height render has 148px of instrument strip at the bottom,
--- and at the thumbnail's 80% fill the hilt would sit behind the heat rail.
local function framingOf(camera: Camera, model: Model, fill: number?, bias: number?): (Vector3, number, Vector3)
	local centre, extent = boundsOf(model)
	local distance = (extent.Y * 0.5 * LEAN_PAD) / (math.tan(math.rad(camera.FieldOfView * 0.5)) * (fill or FRAME_FILL))
	-- Aim a hair below the measured centre. The pose rotates about the hilt, so
	-- the tip leans away from the camera and projects upward; without the bias
	-- the blade sits low with an empty band under the pommel.
	local aim = centre - Vector3.new(0, extent.Y * (bias or 0.018), 0)
	return aim, distance, extent
end

--- Static camera for the inventory thumbnails: same framing, no orbit.
local function solveCamera(camera: Camera, model: Model)
	local aim, distance, extent = framingOf(camera, model)
	local horizontal = math.cos(ELEVATION) * distance
	camera.CFrame = CFrame.lookAt(
		aim
			+ Vector3.new(
				math.sin(AZIMUTH) * horizontal,
				math.sin(ELEVATION) * distance,
				-math.cos(AZIMUTH) * horizontal
			),
		aim
	)
	return extent
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Assembles a blade into `model`. Returns the model for chaining.
---
--- `silhouette` builds the same geometry matte black with no emissive parts, for
--- the fog-of-war cards: the shape is the tease, the colour would be the reveal.
function BladePreview.build(model: Model, blade: BladeRegistry.Blade, silhouette: boolean?): Model
	BladeModelBuilder.build(model, blade, silhouette)
	ensurePivot(model)
	return model
end

--- Builds a blade inside a ViewportFrame and starts a slow turntable spin.
--- Returns a cleanup function; call it when the viewport is destroyed.
---
--- `opts.frameFill` and `opts.aimBias` are the framing knobs; both default to
--- the hero pose so existing callers are unchanged.
function BladePreview.mount(
	viewport: ViewportFrame,
	blade: BladeRegistry.Blade,
	tint: Color3?,
	opts: {
		frameFill: number?,
		aimBias: number?,
		--- Idle turntable rate in rad/s. Nil keeps the hero spin (0.9); 0 holds
		--- the pose so a reward still cannot catch the blade edge-on.
		spin: number?,
		--- Control that receives the drag press. Passed straight through to the
		--- orbit controller; see `ViewportOrbitController.Options.surface`.
		surface: GuiObject?,
		--- Fired once the controller exists, so the caller can read `dragTravel`
		--- (the forge uses it to tell a tap from an orbit).
		onOrbit: ((OrbitController.Handle) -> ())?,
	}?
): () -> ()
	for _, child in viewport:GetChildren() do
		child:Destroy()
	end

	local fill = if opts then opts.frameFill else nil
	local bias = if opts then opts.aimBias else nil

	local world = Instance.new("WorldModel")
	world.Parent = viewport

	local model = Instance.new("Model")
	model.Name = blade.id
	model.Parent = world

	-- The viewport states which blade it is actually showing. The forge header
	-- reads this after a mount instead of trusting its own variable, so a
	-- double mount or a stale callback is visible immediately rather than as a
	-- wrong model under the right name.
	viewport:SetAttribute("BladeId", blade.id)

	BladePreview.build(model, blade)
	collectGlow(model, tint)

	local camera = Instance.new("Camera")
	camera.FieldOfView = 42
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local bobAmplitude = 0.10
	local clock = 0
	local aim, distance = Vector3.zero, 10

	local function frame()
		local nextAim, nextDistance, extent = framingOf(camera, model, fill, bias)
		aim, distance = nextAim, nextDistance
		-- Bob is proportional to the blade. A fixed 0.22 studs reads as a drift
		-- on a greatsword and as a bounce on a dagger.
		bobAmplitude = extent.Y * 0.023
	end

	frame()

	-- The model spins continuously at 0.9 rad/s. Dragging orbits the camera
	-- around it; the spin never pauses, so the blade keeps turning while the
	-- player looks from the side or from below.
	local orbit = OrbitController.attach(viewport, model, {
		camera = camera,
		centre = aim,
		distance = distance,
		origin = CFrame.new(),
		modelYaw = HERO_YAW,
		modelPitch = HERO_PITCH,
		modelRoll = HERO_ROLL,
		cameraYaw = math.pi - AZIMUTH,
		cameraPitch = -ELEVATION,
		surface = if opts then opts.surface else nil,
		modelSpinSpeed = if opts then opts.spin else nil,
		offset = function()
			return CFrame.new(0, math.sin(clock * 1.15) * bobAmplitude, 0)
		end,
	})
	if opts and opts.onOrbit then
		opts.onOrbit(orbit)
	end

	-- Strike energy decays here and is handed to the controller as an impulse.
	local energy: RBXScriptConnection
	energy = game:GetService("RunService").RenderStepped:Connect(function(dt: number)
		if not model.Parent then
			energy:Disconnect()
			return
		end
		local step = math.min(dt, 0.1)
		clock += step
		kick *= math.exp(-step * 3.6)
		slam *= math.exp(-step * 8.5)
		flash *= math.exp(-step * 9.5)
		applyGlow(flash)
		orbit.extraYawSpeed = kick
		orbit.extraPitch = slam
	end)

	-- The mesh usually lands after the viewport exists. Rebuild in place and
	-- re-solve the framing when it does: `applyMesh` reseats every part, so an
	-- orbit fitted to the placeholder circles geometry that has moved.
	local cancelWatch: (() -> ())? = nil
	if not BladeModelBuilder.hasMesh(blade.id) then
		cancelWatch = BladeModelBuilder.watch(blade.id, function()
			if not model.Parent then
				return
			end
			BladePreview.build(model, blade)
			collectGlow(model)
			frame()
			orbit.setFraming(aim, distance)
		end)
	end

	return function()
		if energy.Connected then
			energy:Disconnect()
		end
		orbit.destroy()
		if cancelWatch ~= nil then
			cancelWatch()
		end
		kick = 0
		slam = 0
		flash = 0
		glowApplied = false
		table.clear(glowParts)
		viewport:SetAttribute("BladeId", nil)
		viewport:ClearAllChildren()
	end
end

--- Static thumbnail used by inventory cards. No spin: a grid of twenty-five
--- turntables is a framerate crime.
---
--- `silhouette` renders the locked-wave card: same geometry, matte black, no
--- neon. The caller is expected to switch the frame background to something
--- lighter than the model or the whole card reads as an empty box.
function BladePreview.thumbnail(viewport: ViewportFrame, blade: BladeRegistry.Blade, silhouette: boolean?, tint: Color3?)
	for _, child in viewport:GetChildren() do
		child:Destroy()
	end

	-- Thumbnails are read at 28 to 69 pixels, and the steel is a dark, low
	-- albedo material. At the old ambient of 180 the copy rendered as a hairline
	-- of specular on a near-black plate: present, and invisible. Full ambient
	-- keeps the coloured glow and the bevel readable at that size, and the view
	-- lights still shade the two sides of the blade apart.
	viewport.Ambient = if silhouette then Color3.fromRGB(0, 0, 0) else Color3.fromRGB(255, 255, 255)
	viewport.LightColor = if silhouette then Color3.fromRGB(8, 10, 16) else Color3.fromRGB(255, 255, 255)
	viewport.LightDirection = Vector3.new(-0.55, -0.72, -0.42)
	viewport.BackgroundColor3 = if silhouette then Theme.Color.slate else Theme.Color.void

	local world = Instance.new("WorldModel")
	world.Parent = viewport

	local model = Instance.new("Model")
	model.Name = blade.id
	model.Parent = world

	BladePreview.build(model, blade, silhouette)
	if tint and not silhouette then
		collectGlow(model, tint)
	end
	model:PivotTo(CFrame.Angles(0, THUMB_YAW, HERO_ROLL))

	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	solveCamera(camera, model)
end

return BladePreview
