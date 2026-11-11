--!strict
-- Every blade in the registry, built from primitives.
--
-- The catalogue is 25 named swords and each one has its own line in `RECIPES`.
-- A recipe is not a colour swap: it names a grip, a pommel shape, a guard
-- silhouette, a blade profile, how the fuller runs, and which signature details
-- are welded on. Rusted Cleaver gets notches and a heat pipe; Forgebrand gets
-- horns and a crystal pommel; Nova Reaver gets a split blade with a suspended
-- core. Nothing here reads an uploaded asset, so there is no state in which a
-- blade has no model.
--
-- All geometry is built on +Y, hilt at y = 0, pommel below zero. That is the
-- contract `BladePreview` frames against: the pivot is the hilt, so the
-- turntable rotates the weapon the way a hand would.
--
-- Parts are anchored, non-colliding, non-queryable, and cast no shadows. A
-- ViewportFrame ignores physics anyway, and these get cloned into 25 thumbnails.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BladeRegistry = require(Shared:WaitForChild("BladeRegistry"))
local AssetManifest = require(Shared:WaitForChild("AssetManifest"))
local Config = require(Shared:WaitForChild("Config"))

local BladeModelBuilder = {}

--- Registry `material` is a string so it survives serialisation to the generated
--- manifest. Only the four the catalogue actually uses are mapped; anything else
--- falls back to Metal rather than erroring on an unknown key.
local MATERIALS: { [string]: Enum.Material } = {
	Metal = Enum.Material.Metal,
	Neon = Enum.Material.Neon,
	Glass = Enum.Material.Glass,
	DiamondPlate = Enum.Material.DiamondPlate,
}

--- Set while auditing recipes. Off by default: the derived fallback already
--- produces a full sword, so a missing line is a coverage gap, not a broken
--- blade.
local DEBUG_RECIPES = false

-- ---------------------------------------------------------------------------
-- Recipes
-- ---------------------------------------------------------------------------

export type GuardKind = "bar" | "chevron" | "vguard" | "horns" | "clamp" | "ring"
export type PommelKind = "cap" | "spike" | "crystal" | "ring"
export type BladeKind = "cleaver" | "fang" | "straight" | "sabre" | "glaive" | "scythe" | "greatsword" | "split"
export type FullerKind = "none" | "single" | "double"

export type Recipe = {
	blade: BladeKind,
	guard: GuardKind,
	pommel: PommelKind,
	fuller: FullerKind,
	--- Blade length in studs from the guard to the tip.
	length: number,
	--- Width at the ricasso, before the taper.
	width: number,
	--- Sideways sweep at the tip, in studs.
	curve: number,
	--- Number of chassis segments. 5 reads as a taper, 7 as a curve.
	segments: number,
	--- Notch the edge every other segment (scrap) rather than a smooth line.
	notched: boolean,
	--- Neon channels along the flat of the blade.
	runes: number,
	--- Neon heat pipes running from the guard up the blade.
	vapours: number,
	--- Suspended cores inside a cutout (celestial and above).
	crystals: number,
	--- Bolts on the guard and ricasso.
	rivets: number,
}

--- One line per blade id. Ordered like the registry so a diff between the two
--- files is a scan, not a search.
local RECIPES: { [string]: Recipe } = {
	-- Tier 1 — scrap: short, brutal, repaired rather than made.
	rusted_cleaver = {
		blade = "cleaver",
		guard = "bar",
		pommel = "cap",
		fuller = "single",
		length = 3.05,
		width = 0.92,
		curve = 0.10,
		segments = 5,
		notched = true,
		runes = 0,
		vapours = 1,
		crystals = 0,
		rivets = 2,
	},
	scrap_fang = {
		blade = "fang",
		guard = "chevron",
		pommel = "spike",
		fuller = "none",
		length = 3.25,
		width = 0.72,
		curve = 0.85,
		segments = 6,
		notched = true,
		runes = 0,
		vapours = 1,
		crystals = 0,
		rivets = 1,
	},
	rivet_edge = {
		blade = "straight",
		guard = "bar",
		pommel = "cap",
		fuller = "single",
		length = 3.40,
		width = 0.66,
		curve = 0.0,
		segments = 5,
		notched = false,
		runes = 0,
		vapours = 0,
		crystals = 0,
		rivets = 3,
	},
	coil_shard = {
		blade = "sabre",
		guard = "vguard",
		pommel = "ring",
		fuller = "double",
		length = 3.50,
		width = 0.74,
		curve = 1.15,
		segments = 6,
		notched = false,
		runes = 1,
		vapours = 1,
		crystals = 0,
		rivets = 0,
	},
	cinder_spike = {
		blade = "straight",
		guard = "horns",
		pommel = "spike",
		fuller = "single",
		length = 3.55,
		width = 0.52,
		curve = 0.0,
		segments = 6,
		notched = false,
		runes = 0,
		vapours = 2,
		crystals = 0,
		rivets = 0,
	},

	-- Tier 2 — forged: industrial, heavy, visibly assembled.
	iron_vigil = {
		blade = "straight",
		guard = "clamp",
		pommel = "ring",
		fuller = "double",
		length = 3.70,
		width = 0.88,
		curve = 0.0,
		segments = 6,
		notched = false,
		runes = 1,
		vapours = 1,
		crystals = 0,
		rivets = 2,
	},
	forgebrand = {
		blade = "greatsword",
		guard = "horns",
		pommel = "crystal",
		fuller = "double",
		length = 3.85,
		width = 1.10,
		curve = 0.0,
		segments = 6,
		notched = false,
		runes = 2,
		vapours = 2,
		crystals = 0,
		rivets = 0,
	},
	temperline = {
		blade = "sabre",
		guard = "vguard",
		pommel = "cap",
		fuller = "single",
		length = 3.90,
		width = 0.78,
		curve = 1.05,
		segments = 7,
		notched = false,
		runes = 2,
		vapours = 1,
		crystals = 0,
		rivets = 0,
	},
	anvils_oath = {
		blade = "greatsword",
		guard = "clamp",
		pommel = "spike",
		fuller = "single",
		length = 4.00,
		width = 1.18,
		curve = 0.0,
		segments = 6,
		notched = false,
		runes = 2,
		vapours = 2,
		crystals = 0,
		rivets = 2,
	},
	slagspite = {
		blade = "fang",
		guard = "horns",
		pommel = "crystal",
		fuller = "none",
		length = 4.05,
		width = 1.02,
		curve = 1.25,
		segments = 7,
		notched = true,
		runes = 1,
		vapours = 2,
		crystals = 0,
		rivets = 0,
	},

	-- Tier 3 — astral: long, slim, energy running through the steel.
	nova_reaver = {
		blade = "split",
		guard = "vguard",
		pommel = "crystal",
		fuller = "double",
		length = 4.25,
		width = 0.98,
		curve = 1.30,
		segments = 7,
		notched = false,
		runes = 2,
		vapours = 1,
		crystals = 2,
		rivets = 0,
	},
	starlight_falchion = {
		blade = "sabre",
		guard = "vguard",
		pommel = "ring",
		fuller = "double",
		length = 4.30,
		width = 0.82,
		curve = 1.40,
		segments = 7,
		notched = false,
		runes = 3,
		vapours = 1,
		crystals = 1,
		rivets = 0,
	},
	comets_wake = {
		blade = "split",
		guard = "horns",
		pommel = "spike",
		fuller = "single",
		length = 4.35,
		width = 0.86,
		curve = 0.25,
		segments = 7,
		notched = false,
		runes = 2,
		vapours = 2,
		crystals = 2,
		rivets = 0,
	},
	gravwell_sabre = {
		blade = "split",
		guard = "clamp",
		pommel = "crystal",
		fuller = "double",
		length = 4.30,
		width = 1.02,
		curve = 1.15,
		segments = 7,
		notched = false,
		runes = 3,
		vapours = 1,
		crystals = 2,
		rivets = 0,
	},
	astral_cutter = {
		blade = "split",
		guard = "ring",
		pommel = "crystal",
		fuller = "double",
		length = 4.40,
		width = 0.90,
		curve = 1.55,
		segments = 8,
		notched = false,
		runes = 3,
		vapours = 1,
		crystals = 3,
		rivets = 0,
	},

	-- Tier 4 — void: mass and absence. Wider chassis, colder cores.
	nullbreaker = {
		blade = "split",
		guard = "clamp",
		pommel = "spike",
		fuller = "double",
		length = 4.55,
		width = 1.22,
		curve = 0.0,
		segments = 7,
		notched = false,
		runes = 3,
		vapours = 2,
		crystals = 3,
		rivets = 0,
	},
	voidfang = {
		blade = "fang",
		guard = "horns",
		pommel = "crystal",
		fuller = "none",
		length = 4.50,
		width = 1.10,
		curve = 1.65,
		segments = 8,
		notched = true,
		runes = 3,
		vapours = 1,
		crystals = 2,
		rivets = 0,
	},
	entropy_edge = {
		blade = "split",
		guard = "clamp",
		pommel = "ring",
		fuller = "single",
		length = 4.60,
		width = 0.96,
		curve = 0.30,
		segments = 7,
		notched = false,
		runes = 3,
		vapours = 2,
		crystals = 2,
		rivets = 0,
	},
	event_horizon = {
		blade = "split",
		guard = "ring",
		pommel = "crystal",
		fuller = "double",
		length = 4.65,
		width = 1.04,
		curve = 1.70,
		segments = 8,
		notched = false,
		runes = 3,
		vapours = 1,
		crystals = 3,
		rivets = 0,
	},
	blackstar_glaive = {
		blade = "split",
		guard = "vguard",
		pommel = "spike",
		fuller = "double",
		length = 4.70,
		width = 0.92,
		curve = 1.85,
		segments = 8,
		notched = false,
		runes = 3,
		vapours = 2,
		crystals = 2,
		rivets = 0,
	},

	-- Tier 5 — quantum: the endgame silhouettes, all split frames and cores.
	hadron_splitter = {
		blade = "split",
		guard = "clamp",
		pommel = "crystal",
		fuller = "double",
		length = 4.90,
		width = 1.26,
		curve = 0.0,
		segments = 8,
		notched = false,
		runes = 4,
		vapours = 2,
		crystals = 3,
		rivets = 0,
	},
	quanta_verge = {
		blade = "split",
		guard = "ring",
		pommel = "crystal",
		fuller = "single",
		length = 4.95,
		width = 0.90,
		curve = 0.35,
		segments = 8,
		notched = false,
		runes = 4,
		vapours = 1,
		crystals = 3,
		rivets = 0,
	},
	singularity_blade = {
		blade = "split",
		guard = "vguard",
		pommel = "crystal",
		fuller = "double",
		length = 5.00,
		width = 1.00,
		curve = 1.30,
		segments = 8,
		notched = false,
		runes = 4,
		vapours = 2,
		crystals = 3,
		rivets = 0,
	},
	entangle_scythe = {
		blade = "scythe",
		guard = "horns",
		pommel = "spike",
		fuller = "none",
		length = 5.05,
		width = 1.12,
		curve = 2.30,
		segments = 9,
		notched = false,
		runes = 4,
		vapours = 1,
		crystals = 2,
		rivets = 0,
	},
	forge_eternal = {
		blade = "greatsword",
		guard = "clamp",
		pommel = "crystal",
		fuller = "double",
		length = 5.10,
		width = 1.34,
		curve = 0.0,
		segments = 8,
		notched = false,
		runes = 5,
		vapours = 3,
		crystals = 3,
		rivets = 0,
	},
}

--- Coverage is a build invariant, not a hope: every registry id must have a
--- recipe. If one is ever added without a line here, the derived fallback below
--- still produces a full sword (never a stick), but the warning names the id so
--- the gap gets closed before it ships.
local function recipeFor(blade: BladeRegistry.Blade): Recipe
	local recipe = RECIPES[blade.id]
	if recipe ~= nil then
		return recipe
	end

	if DEBUG_RECIPES then
		warn(string.format("[blade] no recipe for %s; using the derived fallback", blade.id))
	end

	local width = if blade.shape == "greatsword" then 1.2 else 0.9
	return {
		blade = if blade.shape == "scythe" then "scythe" elseif blade.shape == "glaive" then "split" else blade.shape,
		guard = if blade.tier >= 3 then "vguard" else "bar",
		pommel = if blade.tier >= 3 then "crystal" else "cap",
		fuller = if blade.tier >= 2 then "double" else "single",
		length = 2.9 + blade.tier * 0.35,
		width = width,
		curve = if blade.shape == "curved" then 1.2 else 0.0,
		segments = 6,
		notched = blade.tier == 1,
		runes = math.max(0, blade.tier - 1),
		vapours = if blade.tier >= 2 then 1 else 0,
		crystals = if blade.tier >= 3 then 2 else 0,
		rivets = if blade.tier == 1 then 2 else 0,
	}
end

-- ---------------------------------------------------------------------------
-- Primitives
-- ---------------------------------------------------------------------------

local function color(triple: { number }): Color3
	return Color3.fromRGB(triple[1], triple[2], triple[3])
end

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

--- Cylinder aligned to +Y. Roblox cylinders are authored along X, so every one
--- of these carries the same 90° roll rather than each call site remembering it.
local function rod(props: { [string]: any }): Part
	local cframe: CFrame = props.CFrame or CFrame.new()
	props.CFrame = cframe * CFrame.Angles(0, 0, math.rad(90))
	props.Shape = Enum.PartType.Cylinder
	return part(props)
end

local function paint(instance: BasePart, color3: Color3, material: Enum.Material, transparency: number?)
	instance.Color = color3
	instance.Material = material
	if transparency then
		instance.Transparency = transparency
	end
end

-- ---------------------------------------------------------------------------
-- Hilt
-- ---------------------------------------------------------------------------

local function buildGrip(model: Model, blade: BladeRegistry.Blade, recipe: Recipe, silhouette: boolean)
	local gripColor = if silhouette then Color3.new(0, 0, 0) else color(blade.gripColor)
	local glowColor = if silhouette then Color3.new(0, 0, 0) else color(blade.glowColor)
	-- SmoothPlastic in both modes: the grip read is silhouette, not surface. A
	-- metal grip at thumbnail size is a grey blob under any lighting.
	local material = Enum.Material.SmoothPlastic
	local length = 1.05
	local radius = 0.19

	local grip = rod({
		Name = "Grip",
		Size = Vector3.new(length, radius * 2, radius * 2),
		CFrame = CFrame.new(0, -length * 0.5 - 0.12, 0),
	})
	paint(grip, gripColor, material)
	grip.Parent = model

	-- Three binding rings. On a silhouette they stay geometry, just black: the
	-- wrap ridges are part of the read.
	for index = 1, 3 do
		local y = -0.18 - (length - 0.28) * (index / 4)
		local ring = rod({
			Name = "GripRing",
			Size = Vector3.new(0.07, radius * 2.25, radius * 2.25),
			CFrame = CFrame.new(0, y, 0),
		})
		paint(ring, if index == 2 then glowColor else gripColor, material)
		ring.Parent = model
	end

	-- Collar between grip and guard.
	local collar = part({
		Name = "Collar",
		Size = Vector3.new(0.42, 0.14, 0.34),
		CFrame = CFrame.new(0, -0.06, 0),
	})
	paint(collar, if silhouette then Color3.new(0, 0, 0) else color(blade.bladeColor), material)
	collar.Parent = model

	local pommelColor = if silhouette then Color3.new(0, 0, 0) else color(blade.bladeColor)
	local coreColor = if silhouette then Color3.new(0, 0, 0) else glowColor
	local base = -length - 0.12

	if recipe.pommel == "cap" then
		local cap = part({
			Name = "Pommel",
			Size = Vector3.new(0.5, 0.30, 0.5),
			CFrame = CFrame.new(0, base - 0.12, 0) * CFrame.Angles(0, math.rad(45), 0),
		})
		paint(cap, pommelColor, material)
		cap.Parent = model

		local band = rod({
			Name = "PommelBand",
			Size = Vector3.new(0.10, 0.56, 0.56),
			CFrame = CFrame.new(0, base - 0.02, 0),
		})
		paint(band, coreColor, if silhouette then Enum.Material.SmoothPlastic else Enum.Material.Neon)
		band.Parent = model
	elseif recipe.pommel == "spike" then
		for index = 1, 2 do
			local spike = part({
				Name = "PommelSpike",
				Size = Vector3.new(0.26 - (index - 1) * 0.1, 0.26, 0.26 - (index - 1) * 0.1),
				CFrame = CFrame.new(0, base - 0.10 - (index - 1) * 0.22, 0) * CFrame.Angles(0, math.rad(45), 0),
			})
			paint(spike, if index == 1 then pommelColor else coreColor, material)
			spike.Parent = model
		end
	elseif recipe.pommel == "crystal" then
		local socket = part({
			Name = "PommelSocket",
			Size = Vector3.new(0.46, 0.26, 0.46),
			CFrame = CFrame.new(0, base - 0.10, 0) * CFrame.Angles(0, math.rad(45), 0),
		})
		paint(socket, pommelColor, material)
		socket.Parent = model

		local crystal = part({
			Name = "PommelCrystal",
			Size = Vector3.new(0.30, 0.44, 0.30),
			CFrame = CFrame.new(0, base - 0.34, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
		})
		paint(crystal, coreColor, if silhouette then Enum.Material.SmoothPlastic else Enum.Material.Neon)
		crystal.Parent = model
	else
		-- pommel == "ring": an open loop, eight segments, which reads as a hole
		-- at thumbnail size where a solid disc would not.
		for index = 1, 8 do
			local angle = (index - 1) / 8 * math.pi * 2
			local segment = part({
				Name = "PommelRing",
				Size = Vector3.new(0.11, 0.11, 0.30),
				CFrame = CFrame.new(0, base - 0.16 + math.cos(angle) * 0.16, math.sin(angle) * 0.16)
					* CFrame.Angles(angle, 0, 0),
			})
			paint(segment, pommelColor, material)
			segment.Parent = model
		end
	end
end

-- ---------------------------------------------------------------------------
-- Guard
-- ---------------------------------------------------------------------------

local function buildGuard(model: Model, blade: BladeRegistry.Blade, recipe: Recipe, silhouette: boolean)
	local metal = if silhouette then Color3.new(0, 0, 0) else color(blade.bladeColor)
	local glow = if silhouette then Color3.new(0, 0, 0) else color(blade.glowColor)
	local material = MATERIALS[blade.material] or Enum.Material.Metal
	if silhouette then
		material = Enum.Material.SmoothPlastic
	end

	local stance = recipe.width * 2.35
	local y = 0.10

	-- Centre block, shared by every guard. It is what the blade grows out of.
	local block = part({
		Name = "GuardBlock",
		Size = Vector3.new(0.46, 0.34, 0.36),
		CFrame = CFrame.new(0, y, 0),
	})
	paint(block, metal, material)
	block.Parent = model

	if recipe.guard == "bar" then
		local bar = part({
			Name = "GuardBar",
			Size = Vector3.new(stance, 0.18, 0.30),
			CFrame = CFrame.new(0, y, 0),
		})
		paint(bar, metal, material)
		bar.Parent = model
	elseif recipe.guard == "chevron" then
		for _, side in { -1, 1 } do
			local wing = part({
				Name = "GuardWing",
				Size = Vector3.new(stance * 0.52, 0.16, 0.28),
				CFrame = CFrame.new(side * stance * 0.26, y + 0.05, 0)
					* CFrame.Angles(0, 0, math.rad(side * 18)),
			})
			paint(wing, metal, material)
			wing.Parent = model
		end
	elseif recipe.guard == "vguard" then
		-- Swept forward: the wings rise toward the blade, which is the shape
		-- that reads as a duelist's guard rather than a cross.
		for _, side in { -1, 1 } do
			local wing = part({
				Name = "GuardSweep",
				Size = Vector3.new(stance * 0.58, 0.15, 0.26),
				CFrame = CFrame.new(side * stance * 0.27, y + 0.12, 0)
					* CFrame.Angles(0, 0, math.rad(side * 34)),
			})
			paint(wing, metal, material)
			wing.Parent = model

			local tip = part({
				Name = "GuardTip",
				Size = Vector3.new(0.13, 0.26, 0.18),
				CFrame = CFrame.new(side * stance * 0.52, y + 0.26, 0)
					* CFrame.Angles(0, 0, math.rad(side * 34)),
			})
			paint(tip, glow, if silhouette then Enum.Material.SmoothPlastic else Enum.Material.Neon)
			tip.Parent = model
		end
	elseif recipe.guard == "horns" then
		-- Two-stage horns: a thick root that turns up, then a thinner point.
		for _, side in { -1, 1 } do
			local root = part({
				Name = "GuardHorn",
				Size = Vector3.new(stance * 0.34, 0.20, 0.30),
				CFrame = CFrame.new(side * stance * 0.17, y + 0.02, 0)
					* CFrame.Angles(0, 0, math.rad(side * 12)),
			})
			paint(root, metal, material)
			root.Parent = model

			local point = part({
				Name = "GuardHornTip",
				Size = Vector3.new(0.15, 0.46, 0.22),
				CFrame = CFrame.new(side * stance * 0.34, y + 0.20, 0)
					* CFrame.Angles(0, 0, math.rad(side * 30)),
			})
			paint(point, if silhouette then Color3.new(0, 0, 0) else color(blade.gripColor), material)
			point.Parent = model
		end
	elseif recipe.guard == "clamp" then
		-- Mechanical clamp: two heavy jaws with a neon seam between them.
		for _, side in { -1, 1 } do
			local jaw = part({
				Name = "GuardJaw",
				Size = Vector3.new(stance * 0.30, 0.30, 0.36),
				CFrame = CFrame.new(side * stance * 0.22, y, 0) * CFrame.Angles(0, math.rad(side * 8), 0),
			})
			paint(jaw, metal, material)
			jaw.Parent = model
		end
		local seam = part({
			Name = "GuardSeam",
			Size = Vector3.new(stance * 0.52, 0.06, 0.10),
			CFrame = CFrame.new(0, y + 0.14, 0),
		})
		paint(seam, glow, if silhouette then Enum.Material.SmoothPlastic else Enum.Material.Neon)
		seam.Parent = model
	else
		-- ring guard: a circular cage around the ricasso.
		for index = 1, 10 do
			local angle = (index - 1) / 10 * math.pi * 2
			local radius = stance * 0.42
			local segment = part({
				Name = "GuardRing",
				Size = Vector3.new(0.09, 0.09, 0.26),
				CFrame = CFrame.new(0, y + math.cos(angle) * radius, math.sin(angle) * radius)
					* CFrame.Angles(angle, 0, 0),
			})
			paint(segment, if index % 3 == 0 then glow else metal, material)
			segment.Parent = model
		end
	end

	-- Bolts. Scrap-tier only, and they sit on the block so they read at any size.
	for index = 1, recipe.rivets do
		local side = if index % 2 == 0 then 1 else -1
		local bolt = part({
			Name = "Rivet",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.11, 0.11, 0.11),
			CFrame = CFrame.new(side * (0.16 + index * 0.05), y + 0.06, 0.16),
		})
		paint(bolt, if silhouette then Color3.new(0, 0, 0) else color(blade.glowColor), material)
		bolt.Parent = model
	end
end

-- ---------------------------------------------------------------------------
-- Blade
-- ---------------------------------------------------------------------------

local function bladeProfile(recipe: Recipe): { base: number, tip: number, sweep: number }
	if recipe.blade == "cleaver" then
		return { base = 1.0, tip = 0.78, sweep = 0.10 }
	elseif recipe.blade == "fang" then
		return { base = 0.92, tip = 0.16, sweep = recipe.curve }
	elseif recipe.blade == "greatsword" then
		return { base = 1.0, tip = 0.24, sweep = 0.0 }
	elseif recipe.blade == "scythe" then
		return { base = 1.05, tip = 0.10, sweep = recipe.curve }
	elseif recipe.blade == "glaive" then
		return { base = 0.94, tip = 0.14, sweep = recipe.curve }
	elseif recipe.blade == "sabre" then
		return { base = 0.90, tip = 0.18, sweep = recipe.curve }
	elseif recipe.blade == "split" then
		return { base = 0.98, tip = 0.22, sweep = recipe.curve }
	end
	return { base = 0.92, tip = 0.30, sweep = 0.0 }
end

--- The blade chassis.
---
--- Each segment is a box on the parametric curve, rotated to sit flush with its
--- neighbour. Two smaller boxes ride the outer edges of every other segment to
--- give the flat a V cross-section; a split blade shifts the halves apart and
--- runs a neon channel between them.
local function buildBlade(model: Model, blade: BladeRegistry.Blade, recipe: Recipe, silhouette: boolean)
	local profile = bladeProfile(recipe)
	local metal = if silhouette then Color3.new(0, 0, 0) else color(blade.bladeColor)
	local glow = if silhouette then Color3.new(0, 0, 0) else color(blade.glowColor)
	local dark = if silhouette then Color3.new(0, 0, 0) else color(blade.gripColor)
	local material = if silhouette then Enum.Material.SmoothPlastic else (MATERIALS[blade.material] or Enum.Material.Metal)
	local neonMaterial = if silhouette then Enum.Material.SmoothPlastic else Enum.Material.Neon

	local baseY = 0.30
	local segments = recipe.segments
	local split = recipe.blade == "split"
	local halfGap = if split then 0.10 else 0.0

	local function point(t: number): Vector2
		return Vector2.new(profile.sweep * t * t, recipe.length * t)
	end

	for index = 1, segments do
		local t0 = (index - 1) / segments
		local t1 = index / segments
		local tm = (t0 + t1) * 0.5

		local a = point(t0)
		local b = point(t1)
		local mid = point(tm)
		local span = (b - a).Magnitude
		local angle = math.atan2(b.X - a.X, b.Y - a.Y)
		local taper = 1 - (1 - profile.tip * profile.base) * tm
		local width = recipe.width * profile.base * taper
		local thickness = 0.16 - 0.055 * tm

		local cf = CFrame.new(mid.X, baseY + mid.Y, 0) * CFrame.Angles(0, 0, -angle)
		local halves = if split then { -1, 1 } else { 0 } 
		for _, side in halves do
			local offset = if split then side * (halfGap + width * 0.17) else 0
			local halfWidth = if split then width * 0.30 else width

			local spine = part({
				Name = string.format("Blade%02d", index),
				Size = Vector3.new(halfWidth, span * 1.08, thickness),
				CFrame = cf * CFrame.new(offset, 0, 0),
			})
			paint(spine, metal, material)
			spine.Parent = model

			-- Outer bevel. A shallow wedge on each cutting edge: the silhouette
			-- gains a real taper instead of a flat card. A split blade cuts on one
			-- side per half, so it gets a single bevel; a solid blade gets two.
			local edges: { number } = if split then { side } else { -1, 1 }
			for _, edgeSign in edges do
				local offsetX = if split then offset + side * halfWidth * 0.42 else edgeSign * width * 0.46
				local bevel = part({
					Name = "Bevel",
					Size = Vector3.new(0.05, span * 1.02, thickness * 0.72),
					CFrame = cf * CFrame.new(offsetX, 0, 0) * CFrame.Angles(0, 0, math.rad(edgeSign * 7)),
				})
				paint(bevel, glow, neonMaterial, 0.25)
				bevel.Parent = model
			end
		end

		-- Notches: scrap blades have chunks bitten out of the edge. Two short
		-- stubs proud of the line read as damage at thumbnail size.
		if recipe.notched and index % 2 == 1 and index < segments then
			for _, side in { -1, 1 } do
				local notch = part({
					Name = "Notch",
					Size = Vector3.new(0.14, span * 0.34, thickness * 1.15),
					CFrame = cf * CFrame.new(side * width * 0.45, -span * 0.10, 0)
						* CFrame.Angles(0, 0, math.rad(side * 22)),
				})
				paint(notch, dark, material)
				notch.Parent = model
			end
		end
	end

	-- Fuller: one or two neon channels running up the ricasso. How far they go
	-- is the tier read — deeper blades carry the light closer to the point.
	local fullerSegments = if recipe.fuller == "none" then 0
		elseif recipe.fuller == "single" then math.ceil(segments * 0.45)
		else math.ceil(segments * 0.62)

	for index = 1, fullerSegments do
		local tm = (index - 0.5) / segments
		local mid = point(tm)
		local width = recipe.width * profile.base * (1 - (1 - profile.tip * profile.base) * tm)
		local span = recipe.length / segments
		local channel = part({
			Name = "Fuller",
			Size = Vector3.new(if split then width * 0.10 else width * 0.16, span * 0.92, 0.19),
			CFrame = CFrame.new(mid.X, baseY + mid.Y, 0) * CFrame.Angles(0, 0, -math.atan2(profile.sweep * 2 * tm, recipe.length)),
		})
		paint(channel, glow, neonMaterial, 0.05)
		channel.Parent = model

		if recipe.fuller == "double" then
			for _, side in { -1, 1 } do
				local twin = part({
					Name = "FullerTwin",
					Size = Vector3.new(width * 0.055, span * 0.86, 0.205),
					CFrame = CFrame.new(mid.X + side * width * 0.26, baseY + mid.Y, 0)
						* CFrame.Angles(0, 0, -math.atan2(profile.sweep * 2 * tm, recipe.length)),
				})
				paint(twin, glow, neonMaterial, 0.35)
				twin.Parent = model
			end
		end
	end

	-- Tip cap: a short tapered stack, so the point never ends on a blunt box.
	local tip = point(1)
	local tipWidth = recipe.width * profile.base * profile.tip * profile.base
	for index = 1, 2 do
		local cap = part({
			Name = "Tip",
			Size = Vector3.new(tipWidth * (1 - index * 0.32), 0.20 - index * 0.04, 0.10),
			CFrame = CFrame.new(tip.X, baseY + tip.Y + index * 0.11, 0),
		})
		paint(cap, if index == 1 then metal else glow, if index == 1 then material else neonMaterial)
		cap.Parent = model
	end

	-- Suspended cores in a cutout frame. The frame is four thin rails; the core
	-- floats inside them without touching, which is the celestial signature.
	if recipe.crystals > 0 then
		for index = 1, recipe.crystals do
			local t = 0.26 + (index - 1) * 0.20
			local centre = point(t)
			local radius = 0.20 + 0.03 * index
			local y = baseY + centre.Y

			for _, axis in { Vector3.new(1, 0, 0), Vector3.new(0, 1, 0) } do
				local horizontal = axis.X ~= 0
				local rail = part({
					Name = "CoreFrame",
					Size = if horizontal
						then Vector3.new(radius * 2.2, 0.05, 0.12)
						else Vector3.new(0.05, radius * 2.2, 0.12),
					CFrame = CFrame.new(centre.X, y, 0),
				})
				paint(rail, metal, material)
				rail.Parent = model
			end

			local core = part({
				Name = "Core",
				Size = Vector3.new(radius, radius, radius * 0.72),
				CFrame = CFrame.new(centre.X, y, 0) * CFrame.Angles(math.rad(45), math.rad(45), math.rad(index * 36)),
			})
			paint(core, glow, neonMaterial, 0.05)
			core.Parent = model
		end
	end

	-- Heat pipes: thin neon rods from the guard up the blade. On the scrap and
	-- forge tiers they are the main source of colour.
	for index = 1, recipe.vapours do
		local side = if index % 2 == 0 then 1 else -1
		local pipe = part({
			Name = "HeatPipe",
			Size = Vector3.new(0.07, recipe.length * 0.36, 0.10),
			CFrame = CFrame.new(side * recipe.width * 0.34, baseY + recipe.length * 0.20, 0.11)
				* CFrame.Angles(0, 0, math.rad(side * 4)),
		})
		paint(pipe, glow, neonMaterial, 0.2)
		pipe.Parent = model
	end

	-- Runes: short horizontal ticks along the flat, one per tier step.
	for index = 1, recipe.runes do
		local t = 0.16 + (index - 1) * 0.14
		if t < 0.92 then
			local centre = point(t)
			local rune = part({
				Name = "Rune",
				Size = Vector3.new(recipe.width * 0.34, 0.055, 0.21),
				CFrame = CFrame.new(centre.X, baseY + centre.Y, 0),
			})
			paint(rune, glow, neonMaterial, 0.1)
			rune.Parent = model
		end
	end
end

-- ---------------------------------------------------------------------------
-- Uploaded meshes
-- ---------------------------------------------------------------------------

--- Centre and size of the axis-aligned box around every part under `root`.
---
--- Walked from `CFrame` and `Size` rather than taken from `Model:GetBoundingBox()`
--- or `GetExtentsSize()`. Both are unreliable once an imported mesh is in the
--- model: a MeshPart keeps its native `MeshSize` (640 studs for these imports)
--- while `Size` carries the scaled value (5.4), and measured on the old build a
--- correctly scaled 6.4-stud blade claimed to be 320.7 studs tall. Framing a
--- camera from that number puts the blade a third of the way across an empty
--- frame. Walking the parts is exact, and it is what the renderer shows.
function BladeModelBuilder.bounds(root: Instance): (Vector3, Vector3)
	local min = Vector3.new(math.huge, math.huge, math.huge)
	local max = Vector3.new(-math.huge, -math.huge, -math.huge)

	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			local half = descendant.Size * 0.5
			local cf = descendant.CFrame
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local corner = (cf * CFrame.new(half.X * sx, half.Y * sy, half.Z * sz)).Position
						min = Vector3.new(math.min(min.X, corner.X), math.min(min.Y, corner.Y), math.min(min.Z, corner.Z))
						max = Vector3.new(math.max(max.X, corner.X), math.max(max.Y, corner.Y), math.max(max.Z, corner.Z))
					end
				end
			end
		end
	end

	if min.X == math.huge then
		return Vector3.zero, Vector3.zero
	end

	return (min + max) * 0.5, max - min
end

--- The loaded mesh Model for an asset id, if `MeshService` has replicated it.
--- Returns nil while the asset is still loading, which is the normal state for
--- the first few seconds after a server starts.
local function meshSource(assetId: string): Model?
	local folder = ReplicatedStorage:FindFirstChild(Config.MeshFolder)
	if folder == nil then
		return nil
	end
	local found = folder:FindFirstChild(assetId)
	if found ~= nil and found:IsA("Model") then
		return found
	end
	return nil
end

--- Does a body part name mark the emissive half of an export?
---
--- `scripts/build_models.py` writes exactly two objects per asset: `<id>` for the
--- metal and `<id>_glow` for the core, runes and vents. Roblox imports them as
--- separate MeshParts, so the only signal that survives is the name. Matching on
--- a substring rather than the full suffix keeps this working if the importer
--- prefixes the part with the model name.
local function isGlowPart(instance: BasePart): boolean
	return string.find(string.lower(instance.Name), "glow", 1, true) ~= nil
end

--- Body surfaces that survive the move to a sculpted mesh.
---
--- The registry's `Neon` and `Glass` described the primitive build: an emissive
--- slab, or a transparent shell with light inside it. On a sculpted mesh both
--- work against the read. An emissive body flattens the shading that makes the
--- bevels legible, and a glass body is literally see-through — measured live,
--- Comet's Wake rendered as a transparent shell around its core, which is exactly
--- the "hollow sword" it looked like. The mesh carries its own detail, so the
--- body is always an opaque metal and all of the energy stays in `_glow`.
local BODY_MATERIALS: { [string]: Enum.Material } = {
	Metal = Enum.Material.Metal,
	DiamondPlate = Enum.Material.DiamondPlate,
}

--- Rebuilds `model` from an uploaded asset. Returns false when the source has no
--- parts, so the caller can fall back to primitives rather than show nothing.
local function applyMesh(
	model: Model,
	blade: BladeRegistry.Blade,
	source: Model,
	entry: AssetManifest.MeshEntry,
	silhouette: boolean
): boolean
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

	-- The exporter writes real stud-sized geometry, but nothing guarantees the
	-- importer preserves the unit scale: the old .fbx round trip came back at
	-- 100x. Measure what arrived and rescale to the height the build recorded.
	local _, measured = BladeModelBuilder.bounds(clone)
	clone:ScaleTo(entry.height / math.max(measured.Y, 0.001))

	-- Seat on the origin plane: the bottom of the pommel at y = 0, centred in X
	-- and Z. The model is authored with the hilt base at z = 0 and the pommel
	-- hanging below it, so this pins the same axis the primitive build uses.
	-- Done per part rather than with PivotTo because the importer picks its own
	-- model pivot and cannot be trusted to have kept the authored one.
	local lo, extent = BladeModelBuilder.bounds(clone)
	local shift = Vector3.new(-lo.X - extent.X * 0.5, -lo.Y, -lo.Z - extent.Z * 0.5)

	local bodyColor = color(blade.bladeColor)
	local glowColor = color(blade.glowColor)
	local bodyMaterial = BODY_MATERIALS[blade.material] or Enum.Material.Metal

	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CFrame += shift
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CastShadow = false
			if silhouette then
				descendant.Color = Color3.new(0, 0, 0)
				descendant.Material = Enum.Material.SmoothPlastic
			elseif isGlowPart(descendant) then
				descendant.Color = glowColor
				descendant.Material = Enum.Material.Neon
			else
				descendant.Color = bodyColor
				descendant.Material = bodyMaterial
			end
		end
	end

	for _, child in model:GetChildren() do
		child:Destroy()
	end

	-- Flatten: `LoadAsset` hands back a Model wrapping a Model wrapping the
	-- MeshParts, and `FindFirstChildOfClass("MeshPart")` finds nothing through
	-- two levels of wrapper. Move the parts up, throw the wrappers away.
	for _, descendant in parts do
		descendant.Parent = model
	end
	clone:Destroy()

	model.Name = blade.id
	return true
end

--- True when the uploaded asset for `bladeId` is already replicated.
function BladeModelBuilder.hasMesh(bladeId: string): boolean
	return meshSource(bladeId) ~= nil
end

--- Calls `onArrive` when the mesh for `assetId` replicates. Returns a cancel
--- function. Needed because the server loads the assets in the background: the
--- viewport is usually built before they land, and without this the first player
--- on a server keeps the placeholder until they re-open the tab.
function BladeModelBuilder.watch(assetId: string, onArrive: () -> ()): () -> ()
	local connections: { RBXScriptConnection } = {}
	local finished = false

	local function stop()
		finished = true
		for _, connection in connections do
			if connection.Connected then
				connection:Disconnect()
			end
		end
		table.clear(connections)
	end

	local function bindFolder(folder: Instance)
		if finished or not folder:IsA("Folder") then
			return
		end
		if folder:FindFirstChild(assetId) ~= nil then
			-- The asset beat us here: the caller checked `hasMesh` before the
			-- load finished. Without this branch the viewport would keep its
			-- placeholder forever, because there is no later ChildAdded to hear.
			stop()
			onArrive()
			return
		end
		table.insert(
			connections,
			folder.ChildAdded:Connect(function(child: Instance)
				if finished then
					return
				end
				if child.Name == assetId and child:IsA("Model") then
					stop()
					onArrive()
				end
			end)
		)
	end

	local existing = ReplicatedStorage:FindFirstChild(Config.MeshFolder)
	if existing ~= nil then
		bindFolder(existing)
	else
		-- A client can boot before the server has created the folder.
		table.insert(
			connections,
			ReplicatedStorage.ChildAdded:Connect(function(child: Instance)
				if child.Name == Config.MeshFolder then
					bindFolder(child)
				end
			end)
		)
	end

	return stop
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------

--- Assembles a full blade into `model`: the uploaded mesh when it has replicated,
--- the procedural recipe otherwise. `silhouette` renders the same geometry in
--- matte black with no emissive material, for the fog-of-war cards — the shape is
--- the tease, the colour would be the reveal.
---
--- The primitive path is not legacy. It is what a fresh clone with no uploads
--- sees, what a player sees for the first few seconds of a server, and what keeps
--- a missing or failed asset from showing an empty viewport.
function BladeModelBuilder.build(model: Model, blade: BladeRegistry.Blade, silhouette: boolean?): Model
	for _, child in model:GetChildren() do
		child:Destroy()
	end

	local opaque = silhouette == true

	local entry = AssetManifest.mesh(blade.id)
	if entry ~= nil then
		local source = meshSource(blade.id)
		if source ~= nil and applyMesh(model, blade, source, entry, opaque) then
			return model
		end
	end

	local recipe = recipeFor(blade)
	buildGrip(model, blade, recipe, opaque)
	buildGuard(model, blade, recipe, opaque)
	buildBlade(model, blade, recipe, opaque)

	model.Name = blade.id
	return model
end

--- True when this id has a hand-written recipe. Used by the verification pass
--- so coverage is a checked fact rather than a comment.
function BladeModelBuilder.hasRecipe(bladeId: string): boolean
	return RECIPES[bladeId] ~= nil
end

function BladeModelBuilder.recipeIds(): { string }
	local ids = {}
	for id in RECIPES do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

return BladeModelBuilder
