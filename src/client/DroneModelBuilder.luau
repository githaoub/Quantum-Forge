--!strict
-- Procedural drone model for the Fleet viewport.
--
-- Everything here is primitives: no mesh asset, no upload, no Blender export in
-- the runtime path. A drone is a small enough object that a low-poly read is the
-- whole job, and primitives keep the fleet tab playable on a fresh clone where
-- the uploaded blade meshes have not landed yet.
--
-- Shape language: one dark core sphere with a neon inner sphere (the reactor),
-- two thin hoops at right angles (the thruster rings), four swept fins on the
-- diagonals (the stabilisers), and a single lens at the nose. Every piece is
-- anchored and non-interactive; the whole model spins about its own centre.
--
-- The render loop is owned by the caller through the returned cleanup function.
-- A ViewportFrame rebuild (tab switch, ascension) destroys the model anyway, but
-- the RenderStepped connection would survive it and keep writing to a dead
-- model, which is the leak this contract prevents.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetManifest = require(Shared:WaitForChild("AssetManifest"))
local Config = require(Shared:WaitForChild("Config"))
local DroneRegistry = require(Shared:WaitForChild("DroneRegistry"))

local Theme = require(script.Parent.Theme)
local BladeModelBuilder = require(script.Parent.BladeModelBuilder)
local OrbitController = require(script.Parent.ViewportOrbitController)

local DroneModelBuilder = {}

--- Asset id of the sculpted drone in `scripts/build_models.py` / the manifest.
local DRONE_ID = "fleet_drone"

local CORE_RADIUS = 1.05
local HOOP_SEGMENTS = 14
local FIN_COUNT = 4

--- Per-rung size. The staircase is deliberately shallow: the viewport camera is
--- fixed, so a 1.45x Cosmic hull would clip its own fins. Grandeur comes from
--- silhouette and glow, not from zooming the model out of frame.
local TIER_SCALE = { 1.0, 1.08, 1.02, 1.1, 1.18 }

--- Creates one anchored, non-colliding part.
local function part(props: { [string]: any }): Part
	local instance = Instance.new("Part")
	instance.Anchored = true
	instance.CanCollide = false
	instance.CanTouch = false
	instance.CanQuery = false
	instance.CastShadow = false
	instance.TopSurface = Enum.SurfaceType.Smooth
	instance.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(instance :: any)[key] = value
	end
	return instance
end

--- One hoop made of short blocks. A torus would be one mesh; fourteen segments
--- cost 14 parts and read as a ring from any angle the camera can reach, which
--- is the only thing that matters inside a small viewport.
local function buildHoop(
	parent: Model,
	radius: number,
	thickness: number,
	color: Color3,
	tilt: CFrame,
	segments: number?
)
	local count = segments or HOOP_SEGMENTS
	for index = 1, count do
		local angle = (index - 1) / count * math.pi * 2
		local position = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local segment = part({
			Name = string.format("Hoop%02d", index),
			Size = Vector3.new(thickness, thickness, radius * 2 * math.sin(math.pi / count) * 1.25),
			CFrame = tilt * CFrame.new(position) * CFrame.Angles(0, -angle, 0),
			Color = color,
			Material = Enum.Material.Neon,
			Transparency = 0.08,
		})
		segment.Parent = parent
	end
end

--- One swept fin. A flat wedge angled up and out, placed on a diagonal so the
--- silhouette never lines up with a hoop.
local function buildFin(
	parent: Model,
	index: number,
	count: number,
	radius: number,
	color: Color3,
	accent: Color3
)
	local angle = (index - 1) / count * math.pi * 2 + math.pi / 4
	local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))

	local fin = part({
		Name = string.format("Fin%d", index),
		Size = Vector3.new(0.10, 0.52, 0.74),
		CFrame = CFrame.new(outward * radius + Vector3.new(0, 0.16, 0))
			* CFrame.Angles(math.rad(28), -angle, 0),
		Color = color,
		Material = Enum.Material.Metal,
	})
	fin.Parent = parent

	local tip = part({
		Name = string.format("FinTip%d", index),
		Size = Vector3.new(0.12, 0.10, 0.20),
		CFrame = fin.CFrame * CFrame.new(0, 0.28, 0.30),
		Color = accent,
		Material = Enum.Material.Neon,
	})
	tip.Parent = parent
end

--- Orbiting hardware. A small sphere on a stub reads as a companion craft and
--- costs two parts; the stub is what keeps it from looking like a floating coin.
local function buildSatellite(parent: Model, index: number, radius: number, size: number, hull: Color3, glow: Color3)
	local angle = (index - 1) / 3 * math.pi * 2
	local position = Vector3.new(math.cos(angle) * radius, math.sin(angle * 1.7) * 0.35, math.sin(angle) * radius)

	local body = part({
		Name = string.format("Satellite%d", index),
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(size, size, size),
		CFrame = CFrame.new(position),
		Color = hull,
		Material = Enum.Material.Metal,
	})
	body.Parent = parent

	local eye = part({
		Name = string.format("SatelliteLens%d", index),
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(size * 0.55, size * 0.55, size * 0.55),
		CFrame = CFrame.new(position + position.Unit * size * 0.4),
		Color = glow,
		Material = Enum.Material.Neon,
	})
	eye.Parent = parent

	local strut = part({
		Name = string.format("SatelliteStrut%d", index),
		Size = Vector3.new(0.05, 0.05, position.Magnitude - size * 0.5),
		CFrame = CFrame.lookAt(position * 0.5, Vector3.zero),
		Color = hull:Lerp(Color3.new(0, 0, 0), 0.3),
		Material = Enum.Material.SmoothPlastic,
	})
	strut.Parent = parent
end

--- The placeholder drone: primitives only, no asset. Used until the sculpted
--- mesh replicates, and on a clone with no uploads at all.
---
--- The rung changes the silhouette: Scrap is the bare core, Molten grows exhaust
--- bells, Quantum carries photon cubes, Celestial escorts itself with a swarm,
--- and Cosmic is a spine with outrigger pods. A player can tell what they own
--- from across the room without reading a label.
local function buildPrimitive(model: Model, tier: DroneRegistry.DroneTier): Model
	for _, child in model:GetChildren() do
		child:Destroy()
	end

	local rank = tier.tier
	local scale = TIER_SCALE[rank] or 1
	local radius = CORE_RADIUS * scale
	local hull = tier.hull
	local neon = tier.glow
	local hot = tier.glow:Lerp(Theme.Color.white, 0.35)
	local plate = hull:Lerp(Theme.Color.ink, 0.35)

	-- Spine. Only the two capital ships carry one; on the small rungs it would
	-- read as a tail rather than as a hull.
	if rank >= 4 then
		local spine = part({
			Name = "Spine",
			Size = Vector3.new(radius * 0.34, radius * 0.34, radius * (if rank >= 5 then 3.4 else 2.2)),
			Color = plate,
			Material = Enum.Material.Metal,
		})
		spine.Parent = model
	end

	-- Core: dark shell, neon reactor inside, a brighter band across the equator.
	local shell = part({
		Name = "Core",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(radius * 2, radius * 2, radius * 2),
		Color = hull,
		Material = Enum.Material.Metal,
	})
	shell.Parent = model

	local reactor = part({
		Name = "Reactor",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(radius * 1.55, radius * 1.55, radius * 1.55),
		Color = neon,
		Material = Enum.Material.Neon,
	})
	reactor.Parent = model

	local belt = part({
		Name = "Belt",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.16, radius * 2.12, radius * 2.12),
		CFrame = CFrame.Angles(0, 0, math.rad(90)),
		Color = plate,
		Material = Enum.Material.SmoothPlastic,
	})
	belt.Parent = model

	-- Thruster rings: one horizontal, then a canted one per rung above Molten.
	-- The cant is what stops the drone from reading as a flat wheel from the
	-- camera's hero angle.
	buildHoop(model, radius * 1.22, 0.10, neon, CFrame.Angles(0, 0, 0))
	if rank >= 2 then
		buildHoop(model, radius * 1.04, 0.07, hot, CFrame.Angles(math.rad(72), math.rad(18), 0))
	end
	if rank >= 4 then
		buildHoop(model, radius * 1.34, 0.06, neon, CFrame.Angles(math.rad(34), 0, math.rad(18)))
	end
	if rank >= 5 then
		buildHoop(model, radius * 1.48, 0.05, hot, CFrame.Angles(math.rad(-22), math.rad(40), 0))
	end

	-- Stabilisers. The capital ships get a doubled fin set.
	local fins = if rank >= 5 then 8 else if rank >= 3 then 6 else FIN_COUNT
	for index = 1, fins do
		buildFin(model, index, fins, radius * 1.18, plate, neon)
	end

	-- Rung-specific hardware.
	if rank >= 2 then
		-- Exhaust bells. Two cones at the back, which is where a thruster read
		-- comes from at this size.
		for index = 1, 2 do
			local bell = part({
				Name = string.format("Exhaust%d", index),
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.34, radius * 0.62, radius * 0.62),
				CFrame = CFrame.new((index - 1.5) * radius * 0.7, -radius * 0.30, radius * 0.92)
					* CFrame.Angles(0, math.rad(90), 0),
				Color = plate,
				Material = Enum.Material.Metal,
			})
			bell.Parent = model

			local flare = part({
				Name = string.format("ExhaustGlow%d", index),
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.08, radius * 0.44, radius * 0.44),
				CFrame = CFrame.new((index - 1.5) * radius * 0.7, -radius * 0.30, radius * 1.12)
					* CFrame.Angles(0, math.rad(90), 0),
				Color = hot,
				Material = Enum.Material.Neon,
			})
			flare.Parent = model
		end
	end

	if rank >= 3 then
		-- Photon cubes on a light orbit. Only four parts, and they are the tell
		-- that this rung bends space rather than burning fuel.
		for index = 1, 4 do
			local angle = (index - 1) / 4 * math.pi * 2
			local cube = part({
				Name = string.format("Photon%d", index),
				Size = Vector3.new(0.22, 0.22, 0.22),
				CFrame = CFrame.new(math.cos(angle) * radius * 1.55, 0.24, math.sin(angle) * radius * 1.55)
					* CFrame.Angles(angle, angle * 1.4, 0),
				Color = neon,
				Material = Enum.Material.Neon,
			})
			cube.Parent = model
		end
	end

	if rank >= 4 then
		-- Escorts. The Celestial Swarm is a fleet, not a bigger ball.
		for index = 1, 3 do
			buildSatellite(model, index, radius * 1.9, radius * 0.34, hull, hot)
		end
	end

	if rank >= 5 then
		-- Outrigger pods on the spine: the Dreadnought silhouette.
		for _, sign in { -1, 1 } do
			local pod = part({
				Name = "Pod",
				Size = Vector3.new(radius * 0.30, radius * 0.30, radius * 1.8),
				CFrame = CFrame.new(sign * radius * 0.82, -radius * 0.18, radius * 0.2),
				Color = plate,
				Material = Enum.Material.Metal,
			})
			pod.Parent = model

			local lamp = part({
				Name = "PodLamp",
				Size = Vector3.new(radius * 0.12, radius * 0.12, radius * 1.2),
				CFrame = pod.CFrame * CFrame.new(0, radius * 0.22, 0),
				Color = neon,
				Material = Enum.Material.Neon,
			})
			lamp.Parent = model
		end
	end

	-- Nose lens. The one asymmetric piece, which is what gives the spin a front.
	local lens = part({
		Name = "Lens",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.34 * scale, 0.34 * scale, 0.34 * scale),
		CFrame = CFrame.new(0, 0, -radius * 1.02),
		Color = hot,
		Material = Enum.Material.Neon,
	})
	lens.Parent = model

	return model
end

-- ---------------------------------------------------------------------------
-- Uploaded mesh
-- ---------------------------------------------------------------------------

local function meshSource(): Model?
	local folder = ReplicatedStorage:FindFirstChild(Config.MeshFolder)
	if folder == nil then
		return nil
	end
	local found = folder:FindFirstChild(DRONE_ID)
	if found ~= nil and found:IsA("Model") then
		return found
	end
	return nil
end

--- Rebuilds `model` from the sculpted drone asset. Returns false when the source
--- has no parts.
---
--- Normalisation differs from the blades on purpose: a blade is anchored at its
--- hilt, a drone is centred on the origin, because the viewport spins it about
--- its own middle. Anchoring the drone to its base would make it orbit the
--- camera instead of turning on the spot.
local function applyDroneMesh(model: Model, source: Model, entry: AssetManifest.MeshEntry, tier: DroneRegistry.DroneTier): boolean
	local clone = source:Clone()

	local parts: { BasePart } = {}
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	if #parts == 0 then
		clone:Destroy()
		return false
	end

	local _, measured = BladeModelBuilder.bounds(clone)
	clone:ScaleTo(entry.height / math.max(measured.Y, 0.001))

	local centre = BladeModelBuilder.bounds(clone)
	local shift = -centre

	local hull = tier.hull
	local neon = tier.glow

	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CFrame += shift
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CastShadow = false
			if string.find(string.lower(descendant.Name), "glow", 1, true) ~= nil then
				descendant.Color = neon
				descendant.Material = Enum.Material.Neon
			else
				descendant.Color = hull
				descendant.Material = Enum.Material.Metal
			end
		end
	end

	for _, child in model:GetChildren() do
		child:Destroy()
	end
	for _, descendant in parts do
		descendant.Parent = model
	end
	clone:Destroy()

	model.Name = "Drone"
	return true
end

--- Pins a pivot at the model origin. `PivotTo` rotates about the primary part, so
--- without this the spin axis is wherever the importer happened to leave the
--- pivot — which for a wrapped asset is the bounding-box centre of a wrapper.
local function pinPivot(model: Model): BasePart
	local pivot = Instance.new("Part")
	pivot.Name = "Pivot"
	pivot.Size = Vector3.new(0.01, 0.01, 0.01)
	pivot.Transparency = 1
	pivot.Anchored = true
	pivot.CanCollide = false
	pivot.CanTouch = false
	pivot.CanQuery = false
	pivot.CastShadow = false
	pivot.CFrame = CFrame.new()
	pivot.Parent = model
	model.PrimaryPart = pivot
	return pivot
end

--- Builds the drone into `model`: the uploaded mesh when it has replicated and
--- the rung is Scrap, primitives otherwise.
---
--- The sculpted asset is one generic hull. It dresses the first rung exactly;
--- every rung above it is procedural, because a ladder whose five tiers all
--- render the same mesh is a price list, not a fleet.
function DroneModelBuilder.build(model: Model, tierId: string?): Model
	local tier = DroneRegistry.get(tierId) or DroneRegistry.tiers[1]
	if tier.tier == 1 then
		local entry = AssetManifest.mesh(DRONE_ID)
		if entry ~= nil then
			local source = meshSource()
			if source ~= nil and applyDroneMesh(model, source, entry, tier) then
				pinPivot(model)
				return model
			end
		end
	end

	buildPrimitive(model, tier)
	pinPivot(model)
	return model
end

--- True when the sculpted drone has replicated.
function DroneModelBuilder.hasMesh(): boolean
	return meshSource() ~= nil
end

--- Mounts a spinning drone inside `viewport`. Returns a cleanup function.
---
--- `opts.distance` and `opts.centre` let the caller reframe: the Fleet hero is a
--- wide, short stage with a buy row across its bottom, so the drone needs a
--- longer lens and a low aim to sit above the keys.
function DroneModelBuilder.mount(
	viewport: ViewportFrame,
	tierId: string?,
	opts: { distance: number?, centre: Vector3? }?
): () -> ()
	for _, child in viewport:GetChildren() do
		child:Destroy()
	end

	local world = Instance.new("WorldModel")
	world.Parent = viewport

	local model = Instance.new("Model")
	model.Name = "Drone"
	model.Parent = world

	local tier = DroneRegistry.get(tierId) or DroneRegistry.tiers[1]
	DroneModelBuilder.build(model, tier.id)

	-- Upgrade in place when the sculpted asset lands. Only the Scrap rung uses
	-- it; the higher rungs stay procedural on purpose.
	local cancelWatch: (() -> ())? = nil
	if tier.tier == 1 and not DroneModelBuilder.hasMesh() then
		cancelWatch = BladeModelBuilder.watch(DRONE_ID, function()
			if not model.Parent then
				return
			end
			DroneModelBuilder.build(model, tier.id)
		end)
	end

	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	-- Spin and drag-to-orbit. Both live in `ViewportOrbitController`: the model
	-- keeps turning at 0.9 rad/s unconditionally, and dragging orbits the camera
	-- around it. The orbit radius and starting angles reproduce the old fixed
	-- three-quarter shot exactly: camera at (3.1, 2.15, -4.15) looking at
	-- (0, 0.05, 0) is distance 5.589, yaw 2.500, pitch -0.385.
	--
	-- The 15-degree roll is the drone's hero cant: a level craft reads as a
	-- diagram, a banked one reads as flying.
	local orbit = OrbitController.attach(viewport, model, {
		camera = camera,
		centre = if opts and opts.centre then opts.centre else Vector3.new(0, 0.05, 0),
		distance = if opts and opts.distance then opts.distance else 5.589,
		origin = CFrame.new(),
		modelRoll = math.rad(15),
		cameraYaw = 2.500,
		cameraPitch = -0.385,
	})

	return function()
		orbit.destroy()
		if cancelWatch ~= nil then
			cancelWatch()
		end
		viewport:ClearAllChildren()
	end
end

return DroneModelBuilder
