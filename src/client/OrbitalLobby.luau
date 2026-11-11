--!strict
-- Camera framing for the Orbital Command Bridge.
--
-- The bridge itself is built server-side (LobbyService) so other players see it.
-- This only positions the viewport camera: a slow orbit, high enough to read the
-- platform as a place, low enough that the forged blades on characters are
-- visible through the gaps between panels.
--
-- Scriptable camera rather than the default one because a free-look camera
-- fights a full-screen HUD: the player would spend the session looking at the
-- underside of the platform through a menu.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local OrbitalLobby = {}

local connection: RBXScriptConnection? = nil
local angle = math.rad(28)

local RADIUS = 52
local HEIGHT = 26
local FOCUS = Vector3.new(0, 6, 0)
local ORBIT_SPEED = 0.035 -- radians per second; a full turn takes ~3 minutes

--- Eases the camera from wherever it currently is to the orbit so the transition
--- out of the default spawn view is not a snap.
local function frameCamera(camera: Camera)
	local target = CFrame.lookAt(
		Vector3.new(math.cos(angle) * RADIUS, HEIGHT, math.sin(angle) * RADIUS),
		FOCUS
	)

	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 58
	TweenService:Create(camera, TweenInfo.new(1.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		CFrame = target,
	}):Play()
end

function OrbitalLobby.init()
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end

	-- Wait for the bridge to exist so the camera does not frame an empty void
	-- for the first half second.
	task.spawn(function()
		local deadline = os.clock() + 10
		while workspace:FindFirstChild("OrbitalBridge") == nil and os.clock() < deadline do
			task.wait(0.1)
		end

		camera = workspace.CurrentCamera
		if camera == nil then
			return
		end

		frameCamera(camera)

		local tweened = true
		local timer = 0

		connection = RunService.RenderStepped:Connect(function(dt)
			local current = workspace.CurrentCamera
			if current == nil then
				return
			end

			-- Camera can be stolen back by the engine on respawn; reclaim it.
			if current.CameraType ~= Enum.CameraType.Scriptable then
				current.CameraType = Enum.CameraType.Scriptable
			end

			angle += dt * ORBIT_SPEED
			local target = CFrame.lookAt(
				Vector3.new(math.cos(angle) * RADIUS, HEIGHT, math.sin(angle) * RADIUS),
				FOCUS
			)

			-- Blend the opening tween into the live orbit rather than fighting
			-- it: for the first 1.6s we let the tween own the CFrame.
			timer += dt
			if tweened and timer > 1.6 then
				tweened = false
			end
			if not tweened then
				current.CFrame = target
			end
		end)
	end)
end

function OrbitalLobby.destroy()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
	end
end

return OrbitalLobby
