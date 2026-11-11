--!strict
-- The rolled crate, as a real model in a viewport.
--
-- Five shapes now, not one. The crate rail sells a *pool*, and a rail of five
-- identical wooden boxes with different labels is a menu, not a gacha. Each
-- style is built from the same primitive vocabulary — body, bands, seams, a glow
-- that leaks out — so the five read as one family and still read apart at 56px.
--
-- Contract: `mount` returns a handle whose `play(tint)` drives the drop, the
-- rattle and the hold. The seams are the light leak and the tint carrier: whatever
-- colour the caller passes is what the crate bleeds, which is how the same model
-- serves a Void capsule and a Celestial core.

local Theme = require(script.Parent.Theme)

local CratePreview = {}

export type Playback = {
	--- Fires once the crate has landed and the squash has been started.
	onLanded: (() -> ())?,
	--- Fires once per rattle beat, 1..6. The beat count is the cue for the tick
	--- sound and the screen shake, so callers do not need a second timer.
	onBeat: ((number) -> ())?,
	--- Fires when the rattle has peaked and the crate is holding. This is where a
	--- caller starts waiting on its own answer.
	onReady: (() -> ())?,
}

export type Handle = {
	viewport: ViewportFrame,
	model: Model,
	--- Drops the crate and starts the rattle.
	play: (tint: Color3, playback: Playback?) -> (),
	--- Stops any running sequence and hides the crate instantly.
	stop: () -> (),
	destroy: () -> (),
}

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

local IRON = Color3.fromRGB(34, 30, 28)

--- Wooden yard crate. The original, kept byte for byte in shape.
local function buildCrate(model: Model): { Part }
	local wood = Color3.fromRGB(96, 62, 38)
	local woodDark = Color3.fromRGB(58, 38, 24)

	part(model, "Body", Vector3.new(4, 3.2, 4), CFrame.new(0, 0, 0), wood, Enum.Material.WoodPlanks)
	part(model, "Lid", Vector3.new(4.3, 0.7, 4.3), CFrame.new(0, 1.95, 0), woodDark, Enum.Material.WoodPlanks)
	part(model, "Foot", Vector3.new(4.3, 0.4, 4.3), CFrame.new(0, -1.8, 0), woodDark, Enum.Material.WoodPlanks)

	-- Bands run around the body. Slightly larger than the body so they read as
	-- strapping rather than as painted lines.
	for _, y in { -1.05, 0.95 } do
		part(model, "Band", Vector3.new(4.16, 0.32, 4.16), CFrame.new(0, y, 0), IRON, Enum.Material.Metal)
	end

	for _, x in { -1.85, 1.85 } do
		for _, z in { -1.85, 1.85 } do
			part(model, "Bracket", Vector3.new(0.45, 3.4, 0.45), CFrame.new(x, 0, z), IRON, Enum.Material.Metal)
		end
	end

	-- Lock plate on the front face, with a keyhole that is actually a hole: two
	-- dark plates on either side of a neon core.
	part(model, "Lock", Vector3.new(1.1, 1.1, 0.22), CFrame.new(0, -0.1, 2.06), IRON, Enum.Material.Metal)
	local core = part(model, "Core", Vector3.new(0.62, 0.62, 0.62), CFrame.new(0, -0.1, 2.2), Theme.Color.starMatter, Enum.Material.Neon)
	core.Shape = Enum.PartType.Cylinder
	core.CFrame = CFrame.new(0, -0.1, 2.2) * CFrame.Angles(0, 0, math.rad(90))

	local seams: { Part } = {}
	seams[1] = part(model, "Seam", Vector3.new(0.14, 3.0, 0.14), CFrame.new(-0.9, 0, 2.02), Theme.Color.starMatter, Enum.Material.Neon)
	seams[2] = part(model, "Seam", Vector3.new(0.14, 3.0, 0.14), CFrame.new(0.9, 0, 2.02), Theme.Color.starMatter, Enum.Material.Neon)
	seams[3] = part(model, "Seam", Vector3.new(3.6, 0.12, 0.12), CFrame.new(0, 2.32, 0), Theme.Color.starMatter, Enum.Material.Neon)
	seams[4] = part(model, "Seam", Vector3.new(0.12, 0.12, 3.6), CFrame.new(0, 2.32, 0), Theme.Color.starMatter, Enum.Material.Neon)
	seams[5] = part(model, "Seam", Vector3.new(0.14, 3.0, 0.14), CFrame.new(0, 0, -2.02), Theme.Color.starMatter, Enum.Material.Neon)
	return seams
end

--- Void Capsule: a standing cylinder with two end caps and a seam that runs the
--- whole length. Reads as sealed rather than as packed.
local function buildCapsule(model: Model): { Part }
	local shell = Color3.fromRGB(46, 40, 58)
	local trim = Color3.fromRGB(28, 24, 36)

	local body = part(model, "Body", Vector3.new(4.6, 3.1, 3.1), CFrame.new(0, 0, 0), shell, Enum.Material.Metal)
	body.Shape = Enum.PartType.Cylinder
	body.CFrame = CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.rad(90))

	for _, y in { -2.5, 2.5 } do
		local cap = part(model, "Cap", Vector3.new(0.6, 3.5, 3.5), CFrame.new(0, y, 0), trim, Enum.Material.Metal)
		cap.Shape = Enum.PartType.Cylinder
		cap.CFrame = CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90))
	end

	for _, y in { -1.4, 1.4 } do
		local ring = part(model, "Ring", Vector3.new(0.34, 3.4, 3.4), CFrame.new(0, y, 0), IRON, Enum.Material.Metal)
		ring.Shape = Enum.PartType.Cylinder
		ring.CFrame = CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90))
	end

	-- The window: a tall slot cut through the front of the shell, glowing.
	local seams: { Part } = {}
	seams[1] = part(model, "Seam", Vector3.new(0.2, 3.6, 0.2), CFrame.new(0, 0, 1.5), Theme.Color.quantum, Enum.Material.Neon)
	seams[2] = part(model, "Seam", Vector3.new(0.2, 0.2, 2.0), CFrame.new(0, 2.2, 0), Theme.Color.quantum, Enum.Material.Neon)
	seams[3] = part(model, "Seam", Vector3.new(0.2, 0.2, 2.0), CFrame.new(0, -2.2, 0), Theme.Color.quantum, Enum.Material.Neon)
	return seams
end

--- Quantum Relic: an obelisk. Three tapered slabs and four floating shards, so
--- it reads as a thing that was found rather than a thing that was packed.
local function buildRelic(model: Model): { Part }
	local stone = Color3.fromRGB(30, 58, 84)
	local edge = Color3.fromRGB(16, 32, 48)

	part(model, "Base", Vector3.new(3.6, 0.5, 3.6), CFrame.new(0, -2.4, 0), edge, Enum.Material.Slate)
	part(model, "Shaft", Vector3.new(2.5, 3.4, 2.5), CFrame.new(0, -0.6, 0), stone, Enum.Material.Slate)
	part(model, "Taper", Vector3.new(1.7, 1.5, 1.7), CFrame.new(0, 1.85, 0), stone, Enum.Material.Slate)
	local crown = part(model, "Crown", Vector3.new(1.0, 1.0, 1.0), CFrame.new(0, 2.95, 0), Theme.Color.quantum, Enum.Material.Neon)
	crown.CFrame = CFrame.new(0, 2.95, 0) * CFrame.Angles(0, math.rad(45), 0)

	local seams: { Part } = {}
	seams[1] = part(model, "Seam", Vector3.new(0.16, 3.2, 0.16), CFrame.new(0, -0.6, 1.27), Theme.Color.quantum, Enum.Material.Neon)
	seams[2] = part(model, "Seam", Vector3.new(0.16, 1.4, 0.16), CFrame.new(0, 1.85, 0.87), Theme.Color.quantum, Enum.Material.Neon)

	-- Orbiting shards. They are part of the model, so the drop and rattle carry
	-- them; a separate particle system would leave them behind on the fall.
	for index = 1, 4 do
		local angle = (index - 1) * math.pi / 2 + math.pi / 4
		local shard = part(
			model,
			"Shard",
			Vector3.new(0.34, 0.9, 0.34),
			CFrame.new(math.cos(angle) * 2.5, 0.4 + index * 0.35, math.sin(angle) * 2.5)
				* CFrame.Angles(math.rad(18), angle, math.rad(26)),
			Theme.Color.quantum,
			Enum.Material.Neon
		)
		shard.Transparency = 0.25
		table.insert(seams, shard)
	end
	return seams
end

--- Celestial Core: a sphere inside three rings. The most expensive shape, and the
--- only one with no box in it at all.
local function buildCore(model: Model): { Part }
	local shell = Color3.fromRGB(58, 34, 66)

	local ball = part(model, "Body", Vector3.new(3.6, 3.6, 3.6), CFrame.new(0, 0, 0), shell, Enum.Material.SmoothPlastic)
	ball.Shape = Enum.PartType.Ball

	for index = 1, 3 do
		local tilt = (index - 1) * math.pi / 3
		local ring = part(model, "Ring", Vector3.new(0.22, 5.4, 5.4), CFrame.new(0, 0, 0), IRON, Enum.Material.Metal)
		ring.Shape = Enum.PartType.Cylinder
		ring.CFrame = CFrame.new(0, 0, 0) * CFrame.Angles(math.rad(72), tilt, 0) * CFrame.Angles(0, 0, math.rad(90))
	end

	local seams: { Part } = {}
	seams[1] = part(model, "Seam", Vector3.new(3.0, 0.16, 0.16), CFrame.new(0, 0, 1.7), Theme.Color.magenta, Enum.Material.Neon)
	seams[2] = part(model, "Seam", Vector3.new(0.16, 3.0, 0.16), CFrame.new(0, 0, 1.7), Theme.Color.magenta, Enum.Material.Neon)
	for index = 1, 3 do
		local angle = index * math.pi * 2 / 3
		local mote = part(
			model,
			"Mote",
			Vector3.new(0.42, 0.42, 0.42),
			CFrame.new(math.cos(angle) * 2.6, 1.1, math.sin(angle) * 2.6),
			Theme.Color.magenta,
			Enum.Material.Neon
		)
		mote.Shape = Enum.PartType.Ball
		table.insert(seams, mote)
	end
	return seams
end

--- Singularity Vault: a heavy cube with a circular door. The last crate in the
--- game should look like the heaviest one in the game.
local function buildVault(model: Model): { Part }
	local plate = Color3.fromRGB(44, 42, 52)
	local trim = Color3.fromRGB(26, 24, 30)

	part(model, "Body", Vector3.new(5.0, 5.0, 4.2), CFrame.new(0, 0, -0.2), plate, Enum.Material.Metal)
	part(model, "Lid", Vector3.new(5.2, 0.4, 4.4), CFrame.new(0, 2.7, -0.2), trim, Enum.Material.Metal)
	part(model, "Foot", Vector3.new(5.2, 0.4, 4.4), CFrame.new(0, -2.7, -0.2), trim, Enum.Material.Metal)

	for _, y in { -1.75, 1.75 } do
		part(model, "Band", Vector3.new(5.2, 0.36, 4.4), CFrame.new(0, y, -0.2), trim, Enum.Material.Metal)
	end

	local door = part(model, "Door", Vector3.new(0.7, 3.2, 3.2), CFrame.new(0, 0, 2.0), trim, Enum.Material.Metal)
	door.Shape = Enum.PartType.Cylinder
	door.CFrame = CFrame.new(0, 0, 2.0) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, math.rad(90))

	local wheel = part(model, "Wheel", Vector3.new(0.5, 1.1, 1.1), CFrame.new(0, 0, 2.4), Theme.Color.gold, Enum.Material.Neon)
	wheel.Shape = Enum.PartType.Cylinder
	wheel.CFrame = CFrame.new(0, 0, 2.4) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, math.rad(90))

	local seams: { Part } = {}
	seams[1] = part(model, "Seam", Vector3.new(0.14, 3.0, 0.14), CFrame.new(-1.1, 0, 2.1), Theme.Color.starMatter, Enum.Material.Neon)
	seams[2] = part(model, "Seam", Vector3.new(0.14, 3.0, 0.14), CFrame.new(1.1, 0, 2.1), Theme.Color.starMatter, Enum.Material.Neon)
	seams[3] = part(model, "Seam", Vector3.new(4.4, 0.12, 0.12), CFrame.new(0, 2.55, 0), Theme.Color.starMatter, Enum.Material.Neon)
	return seams
end

local BUILDERS: { [string]: (Model) -> { Part } } = {
	crate = buildCrate,
	capsule = buildCapsule,
	relic = buildRelic,
	core = buildCore,
	vault = buildVault,
}

--- How far the camera has to sit back for each shape to fit the same square.
--- The relic is tall and the vault is wide, and a single distance cropped both.
local DISTANCE: { [string]: number } = {
	crate = 9.4,
	capsule = 10.2,
	relic = 10.6,
	core = 10.0,
	vault = 11.0,
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

local function frameCamera(viewport: ViewportFrame, camera: Camera, style: string)
	camera.FieldOfView = 40
	local distance = DISTANCE[style] or DISTANCE.crate
	camera.CFrame = CFrame.lookAt(Vector3.new(0.4, 1.6, distance), Vector3.new(0, 0.1, 0))
	viewport.CurrentCamera = camera
end

function CratePreview.mount(viewport: ViewportFrame, style: string?): Handle
	local shape = if style and BUILDERS[style] then style else "crate"

	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(156, 148, 164)
	viewport.LightColor = Color3.fromRGB(255, 214, 170)
	viewport.LightDirection = Vector3.new(-0.5, -0.8, -0.4)

	local world = Instance.new("WorldModel")
	world.Name = "CrateWorld"
	world.Parent = viewport

	local model, seams = buildModel(shape)
	model.Parent = world

	local camera = Instance.new("Camera")
	camera.Name = "CrateCamera"
	camera.Parent = viewport
	frameCamera(viewport, camera, shape)

	local basePivot = model:GetPivot()
	local runId = 0
	local offsetValue = Instance.new("CFrameValue")
	offsetValue.Name = "CrateOffset"
	offsetValue.Parent = viewport

	local connections: { RBXScriptConnection } = {}
	local activeTween: Tween? = nil

	local function applyOffset(offset: CFrame)
		model:PivotTo(offset * basePivot)
	end

	table.insert(connections, offsetValue:GetPropertyChangedSignal("Value"):Connect(function()
		applyOffset(offsetValue.Value)
	end))

	--- One mover for the crate. Cancelling the previous tween matters: a stop mid
	--- rattle would otherwise be overwritten by the tween still in flight and the
	--- crate would hover over the next blade.
	local function moveTo(goal: CFrame, duration: number, easing: Enum.EasingStyle?, direction: Enum.EasingDirection?)
		if activeTween then
			activeTween:Cancel()
			activeTween = nil
		end
		activeTween = Theme.tween(offsetValue, duration, { Value = goal }, easing, direction)
	end

	local function stop()
		runId += 1
		if activeTween then
			activeTween:Cancel()
			activeTween = nil
		end
		camera.FieldOfView = 40
		applyOffset(CFrame.new(0, -40, 0))
	end

	local function play(tint: Color3, playback: Playback?)
		runId += 1
		local token = runId
		local cues = playback or {}

		for _, seam in seams do
			seam.Color = tint
			seam.Transparency = 0.5
		end
		frameCamera(viewport, camera, shape)

		-- Reduced motion: the crate is simply on the dais, lit, and the caller's
		-- shatter is the whole beat. No fall, no rattle.
		if Theme.reducedMotion() then
			applyOffset(CFrame.new(0, 0, 0))
			camera.FieldOfView = 40
			if cues.onLanded then
				cues.onLanded()
			end
			if cues.onReady then
				cues.onReady()
			end
			return
		end

		-- Drop from above the frame. Quart-In accelerates like a real fall; the
		-- last 20% is a Back-Out settle so the landing has weight.
		applyOffset(CFrame.new(0, 7.5, 0) * CFrame.Angles(math.rad(-8), math.rad(14), math.rad(6)))
		camera.FieldOfView = 46
		Theme.tween(camera, 0.12, { FieldOfView = 44 }, Enum.EasingStyle.Quad)
		local drop = Instance.new("CFrameValue")
		drop.Value = CFrame.new(0, 7.5, 0) * CFrame.Angles(math.rad(-8), math.rad(14), math.rad(6))
		local dropTween = Theme.tween(drop, 0.34, { Value = CFrame.new(0, 0, 0) }, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
		local dropConnection = drop:GetPropertyChangedSignal("Value"):Connect(function()
			if token ~= runId then
				return
			end
			applyOffset(drop.Value)
		end)
		dropTween.Completed:Once(function()
			dropConnection:Disconnect()
			drop:Destroy()
			if token ~= runId then
				return
			end
			-- The squash: camera kicks wide for two frames, then settles back.
			camera.FieldOfView = 34
			Theme.tween(camera, 0.22, { FieldOfView = 40 }, Enum.EasingStyle.Back)
			moveTo(CFrame.new(0, 0, 0), 0.16, Enum.EasingStyle.Back)
			if cues.onLanded then
				cues.onLanded()
			end
		end)

		-- Rattle. Six beats, each a short tilt with a seam flare; the beats get
		-- faster while the glow gets brighter, so the crate reads as pressurising
		-- rather than as a decoration with a shake on it.
		task.spawn(function()
			task.wait(0.4)
			for beat = 1, 6 do
				if token ~= runId then
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
				-- The camera steps in half a degree per beat. The crate's own tilt
				-- says "it is moving"; the push-in says "we are getting closer",
				-- which is the difference between a rattle and a wind-up.
				Theme.tween(camera, 0.14, { FieldOfView = math.max(33, 42 - beat * 1.3) }, Enum.EasingStyle.Quad)
				for _, seam in seams do
					Theme.tween(seam, 0.07, { Transparency = math.max(0, 0.5 - beat * 0.09) }, Enum.EasingStyle.Quad)
				end
				if cues.onBeat then
					cues.onBeat(beat)
				end
				task.wait(0.15 - beat * 0.012)
			end
			if token ~= runId then
				return
			end
			-- Hold at the peak. The crate floats a little, seams at full, and the
			-- caller's answer window opens here.
			moveTo(CFrame.new(0, 0.5, 0), 0.16, Enum.EasingStyle.Quad)
			if cues.onReady then
				cues.onReady()
			end
		end)
	end

	local function destroy()
		runId += 1
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		offsetValue:Destroy()
		viewport:ClearAllChildren()
	end

	return {
		viewport = viewport,
		model = model,
		play = play,
		stop = stop,
		destroy = destroy,
	}
end

--- A camera framing that matches the shipped page: slightly above the lid,
--- looking down the seam, so the crate does not sit on a horizon line.
function CratePreview.framing(): (Vector3, Vector3)
	return Vector3.new(0.4, 1.6, 9.4), Vector3.new(0, 0.1, 0)
end

--- Every style the rail can ask for. Exposed so the UI iterates the catalogue
--- instead of hard-coding a list that drifts from the builders above.
function CratePreview.styles(): { string }
	return { "crate", "capsule", "relic", "core", "vault" }
end

return CratePreview
