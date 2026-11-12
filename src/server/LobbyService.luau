--!strict
-- The Orbital Command Bridge: the physical spawn lobby.
--
-- Built entirely from primitives at runtime. No models, no asset IDs, no manual
-- Studio placement — which means the game builds from source and the geometry
-- can be tuned by editing numbers.
--
-- The flex hook lives here too: each character gets a Highlight, a floating
-- aura ring and a particle emitter tinted by the rarity of the equipped blade.
-- Server-side so other players actually see it.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetManifest = require(Shared:WaitForChild("AssetManifest"))
local BladeRegistry = require(Shared:WaitForChild("BladeRegistry"))
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))

local DataManager = require(script.Parent.DataManager)

local LobbyService = {}

local PLATFORM_Y = 0
local PLATFORM_RADIUS = 34

--- The VIP pass is the only purchase with a body. Gold because the HUD's VIP
--- ribbon is gold; the second ring sits outside the blade ring so the two read
--- as layers rather than as one recoloured aura.
local VIP_COLOR = Color3.fromRGB(255, 200, 78)

local auraConnections: { [Player]: { RBXScriptConnection } } = {}
local lastApplied: { [Player]: string } = {}

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

local function buildPlatform(parent: Instance)
	local disc = part({
		Name = "Platform",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, PLATFORM_RADIUS * 2, PLATFORM_RADIUS * 2),
		CFrame = CFrame.new(0, PLATFORM_Y - 1, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(16, 19, 30),
		Material = Enum.Material.Metal,
		Reflectance = 0.08,
	})
	disc.Parent = parent

	-- Rim: a slightly larger, thinner disc that reads as an illuminated edge.
	local rim = part({
		Name = "Rim",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.35, PLATFORM_RADIUS * 2 + 3, PLATFORM_RADIUS * 2 + 3),
		CFrame = CFrame.new(0, PLATFORM_Y - 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(78, 168, 255),
		Material = Enum.Material.Neon,
	})
	rim.Parent = parent

	-- Concentric inlay rings: cheap, and they give the flat disc a sense of scale.
	for index = 1, 3 do
		local radius = PLATFORM_RADIUS * (0.32 + index * 0.2)
		local ring = part({
			Name = string.format("Inlay%d", index),
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.12, radius * 2, radius * 2),
			CFrame = CFrame.new(0, PLATFORM_Y + 0.02, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = if index == 2 then Color3.fromRGB(150, 120, 255) else Color3.fromRGB(56, 78, 122),
			Material = Enum.Material.Neon,
			Transparency = if index == 2 then 0.3 else 0.55,
		})
		ring.Parent = parent
	end
end

local function buildPylons(parent: Instance)
	local count = 8
	for index = 1, count do
		local angle = (index / count) * math.pi * 2
		local x = math.cos(angle) * (PLATFORM_RADIUS - 3)
		local z = math.sin(angle) * (PLATFORM_RADIUS - 3)

		local pylon = part({
			Name = string.format("Pylon%d", index),
			Size = Vector3.new(1.1, 9, 1.1),
			CFrame = CFrame.new(x, PLATFORM_Y + 4.5, z) * CFrame.Angles(0, -angle, math.rad(9)),
			Color = Color3.fromRGB(24, 28, 42),
			Material = Enum.Material.Metal,
		})
		pylon.Parent = parent

		local cap = part({
			Name = string.format("PylonCap%d", index),
			Size = Vector3.new(1.5, 0.9, 1.5),
			CFrame = CFrame.new(x, PLATFORM_Y + 9.3, z) * CFrame.Angles(0, -angle, 0),
			Color = Color3.fromRGB(94, 214, 255),
			Material = Enum.Material.Neon,
		})
		cap.Parent = parent
	end
end

--- The forge itself: the object the player is conceptually striking.
local function buildAnvil(parent: Instance)
	local base = part({
		Name = "AnvilBase",
		Size = Vector3.new(9, 3, 6),
		CFrame = CFrame.new(0, PLATFORM_Y + 1.5, -6),
		Color = Color3.fromRGB(34, 38, 52),
		Material = Enum.Material.Metal,
	})
	base.Parent = parent

	local body = part({
		Name = "AnvilBody",
		Size = Vector3.new(6.4, 2.2, 4),
		CFrame = CFrame.new(0, PLATFORM_Y + 4.1, -6),
		Color = Color3.fromRGB(48, 52, 68),
		Material = Enum.Material.DiamondPlate,
	})
	body.Parent = parent

	local horn = part({
		Name = "AnvilHorn",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2.6, 1.4, 1.4),
		CFrame = CFrame.new(-5.2, PLATFORM_Y + 4.1, -6) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(48, 52, 68),
		Material = Enum.Material.DiamondPlate,
	})
	horn.Parent = parent

	-- Heat glow under the anvil: a slow-pulsing neon slab. It is the visual
	-- promise that this is the thing to click.
	local glow = part({
		Name = "AnvilGlow",
		Size = Vector3.new(8.4, 0.25, 5.6),
		CFrame = CFrame.new(0, PLATFORM_Y + 3.0, -6),
		Color = Color3.fromRGB(255, 168, 72),
		Material = Enum.Material.Neon,
		Transparency = 0.25,
	})
	glow.Parent = parent

	local pulse = Instance.new("PointLight")
	pulse.Brightness = 2.4
	pulse.Range = 22
	pulse.Color = Color3.fromRGB(255, 172, 84)
	pulse.Parent = glow

	task.spawn(function()
		while glow.Parent do
			local phase = (math.sin(os.clock() * 1.6) + 1) / 2
			glow.Transparency = 0.15 + phase * 0.35
			pulse.Brightness = 1.6 + phase * 1.8
			task.wait(0.08)
		end
	end)
end

local function buildDebris(parent: Instance)
	-- Floating shards above the bridge. Static positions (no server physics):
	-- anything that moves per-frame on the server is a bandwidth tax for
	-- something a client-side tween could do for free.
	local count = 26
	local random = Random.new(90210)

	for index = 1, count do
		local angle = random:NextNumber(0, math.pi * 2)
		local radius = random:NextNumber(18, 52)
		local height = random:NextNumber(6, 30)
		local size = random:NextNumber(0.5, 2.4)

		local shard = part({
			Name = string.format("Debris%d", index),
			Size = Vector3.new(size, size * random:NextNumber(1.2, 3.4), size),
			CFrame = CFrame.new(
				math.cos(angle) * radius,
				PLATFORM_Y + height,
				math.sin(angle) * radius
			) * CFrame.Angles(random:NextNumber(0, 6), random:NextNumber(0, 6), random:NextNumber(0, 6)),
			Color = if index % 3 == 0 then Color3.fromRGB(120, 92, 210) else Color3.fromRGB(38, 46, 70),
			Material = if index % 3 == 0 then Enum.Material.Neon else Enum.Material.Slate,
			Transparency = if index % 3 == 0 then 0.35 else 0,
		})
		shard.Parent = parent
	end
end

--- Forward declaration: `applyLighting` calls it, and the body lives below the
--- procedural setup it overrides.
local applySky: () -> ()

local function applyLighting()
	Lighting.Ambient = Color3.fromRGB(36, 40, 58)
	Lighting.OutdoorAmbient = Color3.fromRGB(28, 32, 50)
	Lighting.Brightness = 0.9
	Lighting.ClockTime = 0.2
	Lighting.GeographicLatitude = 0
	Lighting.EnvironmentDiffuseScale = 0.4
	Lighting.EnvironmentSpecularScale = 0.5
	Lighting.GlobalShadows = true
	Lighting.FogEnd = 900
	Lighting.FogStart = 260
	Lighting.FogColor = Color3.fromRGB(12, 14, 26)

	local existing = Lighting:FindFirstChildOfClass("Atmosphere")
	if existing == nil then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.32
		atmosphere.Offset = 0.15
		atmosphere.Color = Color3.fromRGB(118, 132, 176)
		atmosphere.Decay = Color3.fromRGB(78, 92, 140)
		atmosphere.Glare = 0.4
		atmosphere.Haze = 1.6
		atmosphere.Parent = Lighting
	end

	local bloom = Lighting:FindFirstChildOfClass("BlurEffect")
	if bloom == nil then
		local effect = Instance.new("BlurEffect")
		effect.Size = 2
		effect.Parent = Lighting
	end

	local glow = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	glow.Intensity = 0.7
	glow.Size = 32
	glow.Threshold = 1.4
	glow.Parent = Lighting

	applySky()
end

--- The LihFolk night sky, when the switch in `Config` is on and all six faces
--- have been uploaded.
---
--- The pack ships a lighting recipe per sky and this is that recipe, trimmed to
--- the keys the bridge cares about: painted stars and a painted moon on the
--- faces, so the engine's own are switched off, and an indigo atmosphere so the
--- horizon matches the seam of the cubemap.
---
--- Without the faces, the procedural lighting above stands and any stale sky is
--- removed. A fresh clone and a failed upload both look exactly like the build
--- did before the sky existed, which is the only honest fallback for six
--- textures that must all be present at once.
applySky = function()
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if not Config.UseLihFolkSky or not AssetManifest.hasSkybox() then
		if sky then
			sky:Destroy()
		end
		return
	end

	local live = sky or Instance.new("Sky")
	live.Name = "LihFolkSky"
	live.SkyboxBk = AssetManifest.skyFace("bk")
	live.SkyboxDn = AssetManifest.skyFace("dn")
	live.SkyboxFt = AssetManifest.skyFace("ft")
	live.SkyboxLf = AssetManifest.skyFace("lf")
	live.SkyboxRt = AssetManifest.skyFace("rt")
	live.SkyboxUp = AssetManifest.skyFace("up")
	live.CelestialBodiesShown = false
	live.StarCount = 0
	live.SunAngularSize = 0
	live.MoonAngularSize = 0
	live.Parent = Lighting

	Lighting.Brightness = 0.72
	Lighting.ClockTime = 0
	Lighting.Ambient = Color3.fromRGB(58, 64, 123)
	Lighting.OutdoorAmbient = Color3.fromRGB(77, 85, 160)
	Lighting.EnvironmentDiffuseScale = 0.2
	Lighting.EnvironmentSpecularScale = 0
	Lighting.ExposureCompensation = 0.2

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Density = 0.3
		atmosphere.Offset = 0
		atmosphere.Color = Color3.fromRGB(57, 42, 99)
		atmosphere.Decay = Color3.fromRGB(58, 43, 99)
		atmosphere.Glare = 0
		atmosphere.Haze = 0.5
	end

	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if bloom then
		bloom.Intensity = 0.8
		bloom.Size = 32
		bloom.Threshold = 1.1
	end
end

-- ---------------------------------------------------------------------------
-- Per-character aura
-- ---------------------------------------------------------------------------

local function clearAura(player: Player)
	local connections = auraConnections[player]
	if connections then
		for _, connection in connections do
			if connection.Connected then
				connection:Disconnect()
			end
		end
		auraConnections[player] = nil
	end
end

local function attachAura(player: Player, character: Model)
	clearAura(player)

	local root = character:WaitForChild("HumanoidRootPart", 8)
	if root == nil or not root:IsA("BasePart") then
		return
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "ForgeAura"
	highlight.FillTransparency = 0.92
	highlight.OutlineTransparency = 0.35
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = character
	highlight.Parent = character

	local ring = part({
		Name = "AuraRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.12, 7, 7),
		Color = Color3.fromRGB(120, 200, 255),
		Material = Enum.Material.Neon,
		Transparency = 0.45,
		-- Welded, so it must not be anchored: an anchored Part1 ignores the weld
		-- and the ring stays at the spawn point while the player walks away.
		Anchored = false,
	})
	ring.Parent = character

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = ring
	weld.Parent = ring
	ring.CFrame = root.CFrame * CFrame.new(0, -2.4, 0) * CFrame.Angles(0, 0, math.rad(90))

	-- VIP layer: a wider gold ring and a floating tag, both hidden until the
	-- 1Hz repaint reads the pass. Additive on purpose so a Quantum blade still
	-- reads as Quantum first and VIP second.
	local vipRing = part({
		Name = "VipRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, 10, 10),
		Color = VIP_COLOR,
		Material = Enum.Material.Neon,
		Transparency = 0.55,
		Anchored = false,
	})
	vipRing.Parent = character

	local vipWeld = Instance.new("WeldConstraint")
	vipWeld.Part0 = root
	vipWeld.Part1 = vipRing
	vipWeld.Parent = vipRing
	vipRing.CFrame = root.CFrame * CFrame.new(0, -2.7, 0) * CFrame.Angles(0, 0, math.rad(90))

	local head = character:FindFirstChild("Head")
	local tag = Instance.new("BillboardGui")
	tag.Name = "VipTag"
	tag.Adornee = if head and head:IsA("BasePart") then head else root
	tag.Size = UDim2.fromOffset(54, 22)
	tag.StudsOffset = Vector3.new(0, 2.4, 0)
	tag.AlwaysOnTop = true
	tag.MaxDistance = 80
	tag.Enabled = false
	tag.Parent = character

	local plate = Instance.new("TextLabel")
	plate.Name = "Plate"
	plate.Size = UDim2.fromScale(1, 1)
	plate.BackgroundTransparency = 1
	plate.Text = "VIP"
	plate.TextColor3 = VIP_COLOR
	plate.TextStrokeColor3 = Color3.new(0, 0, 0)
	plate.TextStrokeTransparency = 0.2
	plate.Font = Enum.Font.GothamBlack
	plate.TextSize = 18
	plate.Parent = tag

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "AuraMotes"
	emitter.Texture = ""
	emitter.Color = ColorSequence.new(Color3.fromRGB(150, 220, 255))
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.28),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.9, 1.8)
	emitter.Rate = 14
	emitter.Speed = NumberRange.new(1.2, 2.8)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, 2.4, 0)
	emitter.Parent = root

	local connections: { RBXScriptConnection } = {}
	table.insert(connections, character.Destroying:Connect(function()
		clearAura(player)
	end))
	auraConnections[player] = connections
end

--- Paints the VIP layer. Separate from the blade paint because a player can own
--- VIP with no blade equipped, and because the cache key has to invalidate on a
--- purchase as well as on a blade swap.
local function paintVip(state: Types.ProfileState, character: Model): boolean
	local vip = state.passes.vipAura == true

	local tag = character:FindFirstChild("VipTag")
	if tag and tag:IsA("BillboardGui") then
		tag.Enabled = vip
	end

	local ring = character:FindFirstChild("VipRing")
	if ring and ring:IsA("BasePart") then
		ring.Transparency = if vip then 0.55 else 1
	end

	return vip
end

--- Repaints the aura from the player's equipped blade. Cheap enough to run at
-- 1Hz for everyone; only writes when the blade actually changed.
function LobbyService.refreshAura(player: Player)
	local state = DataManager.get(player)
	local character = player.Character
	if state == nil or character == nil then
		return
	end

	local vip = paintVip(state, character)
	local key = state.equippedBlade .. if vip then "|vip" else ""
	if lastApplied[player] == key then
		return
	end
	lastApplied[player] = key

	local blade = BladeRegistry.get(state.equippedBlade)
	if blade == nil then
		return
	end

	local rarity = BladeRegistry.rarityInfo(blade.rarity)
	local color = Color3.fromRGB(rarity.color[1], rarity.color[2], rarity.color[3])
	local glowColor = Color3.fromRGB(blade.glowColor[1], blade.glowColor[2], blade.glowColor[3])

	local highlight = character:FindFirstChild("ForgeAura")
	if highlight and highlight:IsA("Highlight") then
		highlight.OutlineColor = color
		highlight.FillColor = glowColor
	end

	local ring = character:FindFirstChild("AuraRing")
	if ring and ring:IsA("BasePart") then
		ring.Color = glowColor
		ring.Transparency = if blade.aura == "none" then 1 else 0.4
		-- Higher rarities get a wider ring. Visible progression, no UI needed.
		local diameter = 5 + blade.tier * 1.6
		ring.Size = Vector3.new(0.12, diameter, diameter)
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		local emitter = root:FindFirstChild("AuraMotes")
		if emitter and emitter:IsA("ParticleEmitter") then
			emitter.Color = ColorSequence.new(glowColor)
			emitter.Rate = if blade.aura == "none" then 4 else 10 + blade.tier * 5
		end
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

-- CharacterAdded belongs to a Player, not to the Players service. Subscribing on
-- the service is not a valid member and throws at boot, which is exactly how this
-- once took the whole server down: LobbyService.init() is the fifth stage of boot,
-- so an error here left the remotes built but no player ever loaded.
local playerConnections: { [Player]: { RBXScriptConnection } } = {}
local lifecycleConnection: RBXScriptConnection? = nil
local leaveConnection: RBXScriptConnection? = nil
local repaintConnection: RBXScriptConnection? = nil

local function unsubscribePlayer(player: Player)
	local connections = playerConnections[player]
	if connections then
		for _, connection in connections do
			if connection.Connected then
				connection:Disconnect()
			end
		end
		playerConnections[player] = nil
	end
end

local function applyCharacter(player: Player, character: Model)
	-- The character is not guaranteed to have a HumanoidRootPart the instant
	-- CharacterAdded fires; attachAura waits, so this is safe to call straight off
	-- the event. It also re-checks the player is still in the game, because a
	-- player who leaves during the wait must not get an aura.
	if player.Parent == nil then
		return
	end
	attachAura(player, character)
	LobbyService.refreshAura(player)
end

local function subscribePlayer(player: Player)
	-- Idempotent: PlayerAdded can race the boot sweep over GetPlayers().
	if playerConnections[player] then
		return
	end

	local connections: { RBXScriptConnection } = {}
	playerConnections[player] = connections

	table.insert(connections, player.CharacterAdded:Connect(function(character: Model)
		applyCharacter(player, character)
	end))

	table.insert(connections, player.CharacterRemoving:Connect(function()
		clearAura(player)
		lastApplied[player] = nil
	end))

	if player.Character then
		task.spawn(applyCharacter, player, player.Character)
	end
end

function LobbyService.init()
	local existing = workspace:FindFirstChild("OrbitalBridge")
	if existing then
		existing:Destroy()
	end

	-- Re-init must not stack listeners on the previous run's set.
	if lifecycleConnection then
		lifecycleConnection:Disconnect()
		lifecycleConnection = nil
	end
	if leaveConnection then
		leaveConnection:Disconnect()
		leaveConnection = nil
	end
	if repaintConnection then
		repaintConnection:Disconnect()
		repaintConnection = nil
	end
	for player in playerConnections do
		unsubscribePlayer(player)
	end

	local folder = Instance.new("Folder")
	folder.Name = "OrbitalBridge"
	folder.Parent = workspace

	buildPlatform(folder)
	buildPylons(folder)
	buildAnvil(folder)
	buildDebris(folder)
	applyLighting()

	-- Spawns are a cylinder above the bridge centre so nobody spawns inside the
	-- anvil or falls off the edge.
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "BridgeSpawn"
	spawnLocation.Size = Vector3.new(14, 0.4, 14)
	spawnLocation.CFrame = CFrame.new(0, PLATFORM_Y + 0.2, 6)
	spawnLocation.Anchored = true
	spawnLocation.CanCollide = false
	spawnLocation.Transparency = 1
	spawnLocation.Neutral = true
	spawnLocation.Duration = 0
	spawnLocation.Parent = folder

	lifecycleConnection = Players.PlayerAdded:Connect(subscribePlayer)

	leaveConnection = Players.PlayerRemoving:Connect(function(player: Player)
		unsubscribePlayer(player)
		clearAura(player)
		lastApplied[player] = nil
	end)

	-- Players already in the game when boot finished (Studio play test, hot
	-- restart) never fire PlayerAdded, so sweep them explicitly.
	for _, player in Players:GetPlayers() do
		subscribePlayer(player)
	end

	-- One shared 1Hz repaint loop beats one loop per player.
	local accumulator = 0
	repaintConnection = RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 1 then
			return
		end
		accumulator = 0
		for _, player in Players:GetPlayers() do
			LobbyService.refreshAura(player)
		end
	end)

	if Config.Debug then
		print("[QuantumForge] Orbital Bridge constructed")
	end
end

return LobbyService
