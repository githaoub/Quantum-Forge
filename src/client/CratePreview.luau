--!strict
-- Crate models and the drop/rattle/open playback.
--
-- The models are built from a small primitive vocabulary (planks, iron straps,
-- rivets, neon seams) instead of one box with a label. Each pool is a different
-- silhouette, so the rail and the ceremony can both be read at a glance.
--
-- The handle can mount one crate or a whole pull: `count = 3` lays out three
-- crates, `count = 10` lays out a five-by-two rack. One click opens one crate.
-- The drop and the rattle move the group; the camera orbit stays independent.

local Theme = require(script.Parent.Theme)
local OrbitController = require(script.Parent.ViewportOrbitController)

local CratePreview = {}

export type Playback = {
	onLanded: (() -> ())?,
	onBeat: ((number) -> ())?,
	onReady: (() -> ())?,
}

export type MountOptions = {
	surface: GuiObject?,
	spin: number?,
	count: number?,
	onOrbit: ((OrbitController.Handle) -> ())?,
}

export type Handle = {
	viewport: ViewportFrame,
	models: { Model },
	count: number,
	play: (tint: Color3, playback: Playback?, manual: boolean?) -> (),
	knock: (beat: number, tint: Color3) -> (),
	hover: (tint: Color3) -> (),
	open: (index: number, tint: Color3) -> boolean,
	stop: () -> (),
	destroy: () -> (),
}

local IRON = Color3.fromRGB(44, 43, 51)
local IRON_LIGHT = Color3.fromRGB(74, 76, 88)
local DARK = Color3.fromRGB(24, 22, 28)

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material
): Part
	local piece = Instance.new("Part")
	piece.Name = name
	piece.Anchored = true
	piece.CanCollide = false
	piece.CastShadow = false
	piece.Size = size
	piece.CFrame = cf
	piece.Color = color
	piece.Material = material
	piece.TopSurface = Enum.SurfaceType.Smooth
	piece.BottomSurface = Enum.SurfaceType.Smooth
	piece.Parent = parent
	return piece
end

local function cylinder(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material
): Part
	local piece = part(parent, name, size, cf, color, material)
	piece.Shape = Enum.PartType.Cylinder
	return piece
end

local function rivet(parent: Instance, position: Vector3, color: Color3)
	local piece = part(parent, "Rivet", Vector3.new(0.2, 0.2, 0.2), CFrame.new(position), color, Enum.Material.Metal)
	piece.Shape = Enum.PartType.Ball
end

--- A wooden crate with an iron frame, a lifted lid, corner posts, diagonal
--- braces and a keyhole that is actually lit. The lid sits proud of the body so
--- the silhouette has a lip instead of reading as one extruded cube.
local function buildCrate(model: Model): { Part }
	local wood = Color3.fromRGB(96, 60, 35)
	local woodDark = Color3.fromRGB(55, 34, 21)
	local glow = Theme.Color.starMatter

	part(model, "Body", Vector3.new(4.4, 3.2, 4.4), CFrame.new(0, 0, 0), wood, Enum.Material.WoodPlanks)
	part(model, "Lid", Vector3.new(4.78, 0.5, 4.78), CFrame.new(0, 1.83, 0), woodDark, Enum.Material.WoodPlanks)
	part(model, "LidInset", Vector3.new(3.75, 0.12, 3.75), CFrame.new(0, 2.1, 0), wood, Enum.Material.WoodPlanks)
	part(model, "Base", Vector3.new(4.78, 0.34, 4.78), CFrame.new(0, -1.77, 0), woodDark, Enum.Material.WoodPlanks)

	for _, x in { -2.02, 2.02 } do
		for _, z in { -2.02, 2.02 } do
			part(model, "Post", Vector3.new(0.38, 3.4, 0.38), CFrame.new(x, 0, z), IRON, Enum.Material.Metal)
			rivet(model, Vector3.new(x, 1.5, z), IRON_LIGHT)
			rivet(model, Vector3.new(x, -1.5, z), IRON_LIGHT)
		end
	end

	for _, y in { -1.02, 1.02 } do
		part(model, "Band", Vector3.new(4.56, 0.17, 4.56), CFrame.new(0, y, 0), IRON, Enum.Material.Metal)
	end

	-- Front lock: a dark plate, a lighter inset and a lit keyhole. The keyhole
	-- is a hole and a slot, not a disc, so the front reads as a lock rather than
	-- as a button.
	part(model, "LockPlate", Vector3.new(1.38, 1.55, 0.18), CFrame.new(0, -0.08, 2.29), IRON, Enum.Material.Metal)
	part(model, "LockInset", Vector3.new(1.0, 1.16, 0.1), CFrame.new(0, -0.08, 2.4), IRON_LIGHT, Enum.Material.Metal)
	local keyhole = part(model, "Keyhole", Vector3.new(0.26, 0.26, 0.08), CFrame.new(0, 0.16, 2.47), glow, Enum.Material.Neon)
	keyhole.Shape = Enum.PartType.Ball
	local keySlot = part(model, "KeySlot", Vector3.new(0.13, 0.44, 0.08), CFrame.new(0, -0.16, 2.47), glow, Enum.Material.Neon)

	for _, z in { 2.27, -2.27 } do
		for _, sign in { -1, 1 } do
			part(
				model,
				"Brace",
				Vector3.new(0.19, 2.9, 0.1),
				CFrame.new(0, 0, z) * CFrame.Angles(0, 0, sign * math.rad(38)),
				IRON,
				Enum.Material.Metal
			)
		end
	end

	for _, x in { -2.25, 2.25 } do
		part(model, "Handle", Vector3.new(0.12, 0.48, 1.15), CFrame.new(x, 0.22, 0), DARK, Enum.Material.Metal)
	end

	for _, x in { -1.73, 1.73 } do
		for _, z in { -1.73, 1.73 } do
			part(model, "Foot", Vector3.new(0.55, 0.28, 0.55), CFrame.new(x, -2.04, z), woodDark, Enum.Material.WoodPlanks)
		end
	end

	local seams: { Part } = {}
	for _, x in { -1.45, 1.45 } do
		seams[#seams + 1] = part(
			model,
			"Seam",
			Vector3.new(0.09, 2.55, 0.09),
			CFrame.new(x, 0, 2.31),
			glow,
			Enum.Material.Neon
		)
	end
	seams[#seams + 1] = keyhole
	seams[#seams + 1] = keySlot
	return seams
end

--- A sealed fuel capsule: a standing cylinder, heavy end caps, two iron belts,
--- a lit viewport and a pair of feed pipes. Nothing about it says "wooden box".
local function buildCapsule(model: Model): { Part }
	local shell = Color3.fromRGB(52, 48, 62)
	local trim = Color3.fromRGB(31, 28, 38)
	local glow = Theme.Color.quantum

	local body = cylinder(
		model,
		"Body",
		Vector3.new(4.4, 3.15, 3.15),
		CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.rad(90)),
		shell,
		Enum.Material.Metal
	)
	body.Shape = Enum.PartType.Cylinder

	for _, y in { -2.2, 2.2 } do
		local cap = cylinder(
			model,
			"Cap",
			Vector3.new(0.55, 3.55, 3.55),
			CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)),
			trim,
			Enum.Material.Metal
		)
		cap.Shape = Enum.PartType.Cylinder
		local port = cylinder(
			model,
			"Port",
			Vector3.new(0.24, 1.1, 1.1),
			CFrame.new(0, y + (if y > 0 then 0.36 else -0.36), 0) * CFrame.Angles(0, 0, math.rad(90)),
			glow,
			Enum.Material.Neon
		)
		port.Shape = Enum.PartType.Cylinder
	end

	for _, y in { -1.25, 1.25 } do
		local belt = cylinder(
			model,
			"Belt",
			Vector3.new(0.2, 3.4, 3.4),
			CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)),
			IRON,
			Enum.Material.Metal
		)
		belt.Shape = Enum.PartType.Cylinder
	end

	-- The window sits proud of the shell so the belt does not swallow it.
	part(model, "WindowFrame", Vector3.new(1.08, 2.7, 0.16), CFrame.new(0, 0, 1.66), trim, Enum.Material.Metal)
	local window = part(model, "Window", Vector3.new(0.62, 2.3, 0.08), CFrame.new(0, 0, 1.77), glow, Enum.Material.Neon)

	for _, side in { -1, 1 } do
		cylinder(
			model,
			"Pipe",
			Vector3.new(2.6, 0.18, 0.18),
			CFrame.new(side * 1.52, 0, 0.92) * CFrame.Angles(0, 0, math.rad(90)),
			IRON_LIGHT,
			Enum.Material.Metal
		)
	end

	for _, x in { -1.25, 1.25 } do
		for _, z in { -1.25, 1.25 } do
			part(model, "Leg", Vector3.new(0.34, 0.5, 0.34), CFrame.new(x, -2.55, z), trim, Enum.Material.Metal)
		end
	end

	return { window }
end

--- A recovered obelisk: a stepped plinth, three tapering stone blocks, an iron
--- cage and four floating shards. The taper is what separates it from a pillar.
local function buildRelic(model: Model): { Part }
	local stone = Color3.fromRGB(34, 62, 88)
	local edge = Color3.fromRGB(19, 34, 50)
	local glow = Theme.Color.quantum

	part(model, "Plinth", Vector3.new(3.9, 0.45, 3.9), CFrame.new(0, -2.5, 0), edge, Enum.Material.Slate)
	part(model, "PlinthTop", Vector3.new(3.0, 0.35, 3.0), CFrame.new(0, -2.12, 0), stone, Enum.Material.Slate)
	part(model, "Shaft1", Vector3.new(2.7, 1.4, 2.7), CFrame.new(0, -1.1, 0), stone, Enum.Material.Slate)
	part(model, "Shaft2", Vector3.new(2.1, 1.5, 2.1), CFrame.new(0, 0.4, 0), stone, Enum.Material.Slate)
	part(model, "Shaft3", Vector3.new(1.5, 1.3, 1.5), CFrame.new(0, 1.8, 0), stone, Enum.Material.Slate)

	for _, x in { -1.55, 1.55 } do
		for _, z in { -1.55, 1.55 } do
			part(model, "Cage", Vector3.new(0.24, 3.2, 0.24), CFrame.new(x, -0.5, z), IRON, Enum.Material.Metal)
		end
	end

	local crown = part(
		model,
		"Crown",
		Vector3.new(1.0, 1.0, 1.0),
		CFrame.new(0, 2.72, 0) * CFrame.Angles(math.rad(45), math.rad(45), 0),
		glow,
		Enum.Material.Neon
	)
	crown.Shape = Enum.PartType.Block

	local seams: { Part } = { crown }
	for _, x in { -0.62, 0.62 } do
		seams[#seams + 1] = part(
			model,
			"Seam",
			Vector3.new(0.1, 2.5, 0.1),
			CFrame.new(x, 0.1, 1.36),
			glow,
			Enum.Material.Neon
		)
	end
	for _, x in { -0.45, 0.45 } do
		seams[#seams + 1] = part(
			model,
			"Seam",
			Vector3.new(0.1, 1.8, 0.1),
			CFrame.new(x, 1.5, 0.76),
			glow,
			Enum.Material.Neon
		)
	end

	for index = 1, 4 do
		local angle = (index - 1) * math.pi / 2 + math.pi / 4
		local shard = part(
			model,
			"Shard",
			Vector3.new(0.32, 1.1, 0.32),
			CFrame.new(math.cos(angle) * 2.3, 0.1 + index * 0.45, math.sin(angle) * 2.3)
				* CFrame.Angles(math.rad(18), angle, math.rad(26)),
			glow,
			Enum.Material.Neon
		)
		shard.Transparency = 0.15
		seams[#seams + 1] = shard
	end
	return seams
end

--- A celestial core: a dark sphere, a lit heart and three segmented orbital
--- rings. The rings are built from twelve tangent bars each because Roblox has
--- no torus primitive and a cylinder reads as a disc.
local function buildCore(model: Model): { Part }
	local shell = Color3.fromRGB(54, 35, 68)
	local glow = Theme.Color.magenta

	local body = part(model, "Body", Vector3.new(3.5, 3.5, 3.5), CFrame.new(0, 0, 0), shell, Enum.Material.SmoothPlastic)
	body.Shape = Enum.PartType.Ball
	local heart = part(model, "Heart", Vector3.new(1.25, 1.25, 1.25), CFrame.new(0, 0, 0), glow, Enum.Material.Neon)
	heart.Shape = Enum.PartType.Ball

	local radius = 2.55
	local segments = 12
	local segmentLength = 2 * math.pi * radius / segments + 0.08
	for ring = 1, 3 do
		local tilt = CFrame.Angles(math.rad(72), math.rad((ring - 1) * 60), 0)
		for index = 1, segments do
			local angle = (index - 1) * 2 * math.pi / segments
			local localPoint = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			local localTangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
			local point = tilt:VectorToWorldSpace(localPoint)
			local tangent = tilt:VectorToWorldSpace(localTangent)
			part(
				model,
				"Ring",
				Vector3.new(0.13, 0.13, segmentLength),
				CFrame.lookAt(point, point + tangent),
				IRON_LIGHT,
				Enum.Material.Metal
			)
		end
	end

	local seams: { Part } = { heart }
	for index = 1, 3 do
		local angle = index * 2 * math.pi / 3
		local mote = part(
			model,
			"Mote",
			Vector3.new(0.36, 0.36, 0.36),
			CFrame.new(math.cos(angle) * 1.95, 1.35 + index * 0.3, math.sin(angle) * 1.95),
			glow,
			Enum.Material.Neon
		)
		mote.Shape = Enum.PartType.Ball
		seams[#seams + 1] = mote
	end
	return seams
end

--- A singularity vault: a heavy plate cube, a recessed circular door, a gold
--- wheel and a rim of bolts. The last crate should look like the heaviest one.
local function buildVault(model: Model): { Part }
	local plate = Color3.fromRGB(50, 49, 58)
	local trim = Color3.fromRGB(28, 27, 34)
	local glow = Theme.Color.starMatter

	part(model, "Body", Vector3.new(5.0, 4.9, 4.5), CFrame.new(0, 0, -0.1), plate, Enum.Material.Metal)
	part(model, "Lid", Vector3.new(5.24, 0.42, 4.72), CFrame.new(0, 2.6, -0.1), trim, Enum.Material.Metal)
	part(model, "Base", Vector3.new(5.24, 0.42, 4.72), CFrame.new(0, -2.6, -0.1), trim, Enum.Material.Metal)

	for _, x in { -2.2, 2.2 } do
		for _, z in { -1.95, 1.75 } do
			part(model, "Corner", Vector3.new(0.5, 5.1, 0.5), CFrame.new(x, 0, z), trim, Enum.Material.Metal)
		end
	end
	for _, y in { -1.55, 1.55 } do
		part(model, "Band", Vector3.new(5.1, 0.28, 4.62), CFrame.new(0, y, -0.1), trim, Enum.Material.Metal)
	end

	local rim = cylinder(
		model,
		"DoorRim",
		Vector3.new(0.28, 3.9, 3.9),
		CFrame.new(0, 0, 2.18) * CFrame.Angles(0, math.rad(90), 0),
		IRON_LIGHT,
		Enum.Material.Metal
	)
	rim.Shape = Enum.PartType.Cylinder
	local door = cylinder(
		model,
		"Door",
		Vector3.new(0.42, 3.3, 3.3),
		CFrame.new(0, 0, 2.36) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(62, 61, 72),
		Enum.Material.Metal
	)
	door.Shape = Enum.PartType.Cylinder

	-- The wheel is a rim of twelve bars and four spokes, not a disc: a single
	-- cylinder with a cross in front of it reads as a sticker. Roblox has no
	-- torus primitive, so the ring is segmented like the core's orbitals.
	local wheelZ = 2.62
	local ringRadius = 0.72
	local segments = 12
	local segmentLength = 2 * math.pi * ringRadius / segments + 0.06
	for index = 1, segments do
		local angle = (index - 1) * 2 * math.pi / segments
		local point = Vector3.new(math.cos(angle) * ringRadius, math.sin(angle) * ringRadius, wheelZ)
		local tangent = Vector3.new(-math.sin(angle), math.cos(angle), 0)
		part(
			model,
			"WheelRim",
			Vector3.new(0.13, 0.13, segmentLength),
			CFrame.lookAt(point, point + tangent),
			glow,
			Enum.Material.Neon
		)
	end
	for index = 1, 4 do
		local angle = (index - 1) * math.pi / 2
		part(
			model,
			"Spoke",
			Vector3.new(0.14, ringRadius, 0.14),
			CFrame.new(math.cos(angle) * ringRadius * 0.5, math.sin(angle) * ringRadius * 0.5, wheelZ - 0.02)
				* CFrame.Angles(0, 0, angle),
			glow,
			Enum.Material.Neon
		)
	end
	local hub = part(model, "Hub", Vector3.new(0.28, 0.28, 0.28), CFrame.new(0, 0, wheelZ - 0.06), glow, Enum.Material.Neon)
	hub.Shape = Enum.PartType.Ball

	for index = 1, 8 do
		local angle = index * math.pi / 4
		rivet(model, Vector3.new(math.cos(angle) * 1.86, math.sin(angle) * 1.86, 2.44), IRON_LIGHT)
	end

	local seams: { Part } = {}
	for _, x in { -2.35, 2.35 } do
		seams[#seams + 1] = part(
			model,
			"Seam",
			Vector3.new(0.1, 3.4, 0.1),
			CFrame.new(x, 0, 2.24),
			glow,
			Enum.Material.Neon
		)
	end
	return seams
end

local BUILDERS: { [string]: (Model) -> { Part } } = {
	crate = buildCrate,
	capsule = buildCapsule,
	relic = buildRelic,
	core = buildCore,
	vault = buildVault,
}

local function buildModel(style: string): (Model, { Part })
	local model = Instance.new("Model")
	model.Name = style
	local builder = BUILDERS[style] or BUILDERS.crate
	local seams = builder(model)
	for _, seam in seams do
		seam.Transparency = 0.55
	end
	return model, seams
end

--- Positions for a pull. Three crates sit in one row, ten in a five-by-two
--- rack, and anything in between fills the same grid from the top left.
local function layout(count: number): ({ Vector3 }, number)
	local positions: { Vector3 } = {}
	local columns = if count <= 1 then 1 elseif count <= 3 then count elseif count == 4 then 2 else 5
	local rows = math.ceil(count / columns)
	local gapX = if count <= 1 then 0 elseif count <= 3 then 8.8 elseif count == 4 then 7.4 else 6.6
	local gapY = if count == 4 then 5.2 else 5.6
	for index = 1, count do
		local column = (index - 1) % columns
		local row = math.floor((index - 1) / columns)
		local x = (column - (columns - 1) / 2) * gapX
		local y = ((rows - 1) / 2 - row) * gapY
		table.insert(positions, Vector3.new(x, y, 0))
	end

	local distance = if count <= 1
		then 13.9
		elseif count <= 3 then 19.8
		elseif count <= 4 then 22.9
		else 25.8
	return positions, distance
end

--- Degrees. Narrow on purpose: the old 40 degree lens turned the outer crates
--- of a three-pull outward, so a straight row read as a fan. 30 keeps the flanks
--- honest and lets the neon do the depth work.
local FOV = 30

local function frameCamera(viewport: ViewportFrame, camera: Camera, distance: number)
	camera.FieldOfView = FOV
	camera.CFrame = CFrame.lookAt(Vector3.new(0.4, 1.6, distance), Vector3.new(0, 0.1, 0))
	viewport.CurrentCamera = camera
end

function CratePreview.mount(viewport: ViewportFrame, style: string?, opts: MountOptions?): Handle
	local shape = if style and BUILDERS[style] then style else "crate"
	local count = math.clamp(math.floor(if opts then opts.count or 1 else 1), 1, 10)

	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(178, 176, 190)
	viewport.LightColor = Color3.fromRGB(255, 224, 190)
	viewport.LightDirection = Vector3.new(-0.5, -0.8, -0.4)

	local world = Instance.new("WorldModel")
	world.Name = "CrateWorld"
	world.Parent = viewport

	local positions, distance = layout(count)
	local entries: { { model: Model, base: CFrame, seams: { Part }, opened: boolean } } = {}
	local models: { Model } = {}
	for index = 1, count do
		local model, seams = buildModel(shape)
		local base = CFrame.new(positions[index])
		model:PivotTo(base)
		model.Parent = world
		table.insert(entries, { model = model, base = base, seams = seams, opened = false })
		table.insert(models, model)
	end

	-- Invisible pivot for the orbit controller. The group is moved by
	-- `offsetValue`, not by the controller's model pivot, so the controller gets
	-- a dummy it can rotate without touching the crates.
	local anchorModel = Instance.new("Model")
	anchorModel.Name = "OrbitAnchor"
	local anchorPart = part(anchorModel, "Anchor", Vector3.new(0.2, 0.2, 0.2), CFrame.new(), Color3.new(), Enum.Material.SmoothPlastic)
	anchorPart.Transparency = 1
	anchorPart.Parent = anchorModel
	anchorModel.Parent = world

	local camera = Instance.new("Camera")
	camera.Name = "CrateCamera"
	camera.Parent = viewport
	frameCamera(viewport, camera, distance)

	local offsetValue = Instance.new("CFrameValue")
	offsetValue.Name = "CrateOffset"
	offsetValue.Value = CFrame.new()
	offsetValue.Parent = viewport

	local runId = 0
	local activeTween: Tween? = nil
	local orbit: OrbitController.Handle? = nil

	local function applyOffset(offset: CFrame)
		for _, entry in entries do
			if entry.model.Parent then
				entry.model:PivotTo(offset * entry.base)
			end
		end
	end

	local connection = offsetValue:GetPropertyChangedSignal("Value"):Connect(function()
		applyOffset(offsetValue.Value)
	end)

	local function moveTo(goal: CFrame, duration: number, easing: Enum.EasingStyle?, direction: Enum.EasingDirection?)
		if activeTween then
			activeTween:Cancel()
			activeTween = nil
		end
		activeTween = Theme.tween(offsetValue, duration, { Value = goal }, easing, direction)
	end

	if opts and opts.surface then
		orbit = OrbitController.attach(viewport, anchorModel, {
			camera = camera,
			centre = Vector3.new(0, 0, 0),
			distance = distance,
			origin = CFrame.new(),
			modelSpinSpeed = opts.spin or 0,
			cameraPitch = math.rad(-8),
			surface = opts.surface,
			offset = function()
				return offsetValue.Value
			end,
		})
		if opts.onOrbit then
			opts.onOrbit(orbit)
		end
	end

	local function setSeams(tint: Color3, transparency: number)
		for _, entry in entries do
			if not entry.opened then
				for _, seam in entry.seams do
					seam.Color = tint
					seam.Transparency = transparency
				end
			end
		end
	end

	local function play(tint: Color3, playback: Playback?, manual: boolean?)
		runId += 1
		local stamp = runId
		local cues = playback or {}

		setSeams(tint, 0.5)
		frameCamera(viewport, camera, distance)

		if Theme.reducedMotion() then
			applyOffset(CFrame.new())
			if cues.onLanded then
				cues.onLanded()
			end
			if cues.onReady and not manual then
				cues.onReady()
			end
			return
		end

		applyOffset(CFrame.new(0, 7.5, 0) * CFrame.Angles(math.rad(-8), math.rad(7), math.rad(4)))
		camera.FieldOfView = FOV + 6
		Theme.tween(camera, 0.12, { FieldOfView = FOV + 4 }, Enum.EasingStyle.Quad)
		applyOffset(CFrame.new(0, 7.5, 0) * CFrame.Angles(math.rad(-8), math.rad(7), math.rad(4)))

		local drop = Instance.new("CFrameValue")
		drop.Value = CFrame.new(0, 7.5, 0) * CFrame.Angles(math.rad(-8), math.rad(7), math.rad(4))
		local dropTween = Theme.tween(drop, 0.34, { Value = CFrame.new() }, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
		local dropConnection = drop:GetPropertyChangedSignal("Value"):Connect(function()
			if stamp ~= runId then
				return
			end
			applyOffset(drop.Value)
		end)
		dropTween.Completed:Once(function()
			dropConnection:Disconnect()
			drop:Destroy()
			if stamp ~= runId then
				return
			end
			camera.FieldOfView = FOV - 6
			Theme.tween(camera, 0.22, { FieldOfView = FOV }, Enum.EasingStyle.Back)
			moveTo(CFrame.new(), 0.16, Enum.EasingStyle.Back)
			if cues.onLanded then
				cues.onLanded()
			end
		end)

		if manual then
			return
		end

		task.spawn(function()
			task.wait(0.4)
			for beat = 1, 6 do
				if stamp ~= runId then
					return
				end
				local strength = 0.05 + beat * 0.035
				local yaw = (if beat % 2 == 0 then 1 else -1) * strength * 1.7
				local roll = (if beat % 2 == 0 then -1 else 1) * strength
				local lift = 0.12 + beat * 0.035
				moveTo(
					CFrame.new(0, lift, 0) * CFrame.Angles(math.rad(roll * 16), math.rad(yaw * 26), math.rad(roll * 9)),
					0.07,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.InOut
				)
				Theme.tween(camera, 0.14, { FieldOfView = math.max(FOV - 7, FOV + 2 - beat * 1.1) }, Enum.EasingStyle.Quad)
				setSeams(tint, math.max(0, 0.5 - beat * 0.09))
				if cues.onBeat then
					cues.onBeat(beat)
				end
				task.wait(0.15 - beat * 0.012)
			end
			if stamp ~= runId then
				return
			end
			moveTo(CFrame.new(0, 0.5, 0), 0.16, Enum.EasingStyle.Quad)
			if cues.onReady then
				cues.onReady()
			end
		end)
	end

	local function knock(beat: number, tint: Color3)
		local step = math.clamp(beat, 1, 6)
		local strength = 0.05 + step * 0.035
		local yaw = (if step % 2 == 0 then 1 else -1) * strength * 1.7
		local roll = (if step % 2 == 0 then -1 else 1) * strength
		local lift = 0.1 + step * 0.03
		moveTo(
			CFrame.new(0, lift, 0) * CFrame.Angles(math.rad(roll * 14), math.rad(yaw * 18), math.rad(roll * 7)),
			0.07,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.InOut
		)
		Theme.tween(camera, 0.14, { FieldOfView = math.max(FOV - 7, FOV + 1 - step * 0.8) }, Enum.EasingStyle.Quad)
		setSeams(tint, math.max(0, 0.5 - step * 0.08))
	end

	local function hover(tint: Color3)
		setSeams(tint, 0)
		Theme.tween(camera, 0.16, { FieldOfView = FOV - 6 }, Enum.EasingStyle.Quad)
		moveTo(CFrame.new(0, 0.35, 0), 0.16, Enum.EasingStyle.Quad)
	end

	--- Removes one crate from the rack. The crate takes the hit before it goes:
	--- it jumps, turns and fades. A lid that only fades reads as a delete.
	local function openCrate(index: number, _tint: Color3): boolean
		local entry = entries[index]
		if entry == nil or entry.opened then
			return false
		end
		entry.opened = true
		local model = entry.model
		for _, piece in model:GetDescendants() do
			if piece:IsA("BasePart") then
				Theme.tween(piece, 0.26, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end
		end

		if not Theme.reducedMotion() then
			local start = model:GetPivot()
			local burst = Instance.new("CFrameValue")
			burst.Value = CFrame.new()
			local spin = (if index % 2 == 0 then 1 else -1)
			local burstConnection = burst:GetPropertyChangedSignal("Value"):Connect(function()
				if model.Parent then
					model:PivotTo(start * burst.Value)
				end
			end)
			Theme.tween(
				burst,
				0.26,
				{ Value = CFrame.new(0, 1.15, 0) * CFrame.Angles(math.rad(16), math.rad(20) * spin, math.rad(-10)) },
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			)
			task.delay(0.3, function()
				burstConnection:Disconnect()
				burst:Destroy()
			end)
		end

		task.delay(0.28, function()
			if model.Parent then
				model:Destroy()
			end
		end)
		return true
	end

	local function stop()
		runId += 1
		if activeTween then
			activeTween:Cancel()
			activeTween = nil
		end
		camera.FieldOfView = FOV
		applyOffset(CFrame.new(0, -40, 0))
	end

	local function destroy()
		runId += 1
		if orbit then
			orbit.destroy()
			orbit = nil
		end
		connection:Disconnect()
		offsetValue:Destroy()
		viewport:ClearAllChildren()
	end

	return {
		viewport = viewport,
		models = models,
		count = count,
		play = play,
		knock = knock,
		hover = hover,
		open = openCrate,
		stop = stop,
		destroy = destroy,
	}
end

--- A camera framing that matches the solo crate: slightly above the lid,
--- looking down the seam, so the crate does not sit on a horizon line.
function CratePreview.framing(): (Vector3, Vector3)
	return Vector3.new(0.4, 1.6, 9.8), Vector3.new(0, 0.1, 0)
end

--- Every style the rail can ask for. Exposed so the UI iterates the catalogue
--- instead of hard-coding a list that drifts from the builders above.
function CratePreview.styles(): { string }
	return { "crate", "capsule", "relic", "core", "vault" }
end

return CratePreview
