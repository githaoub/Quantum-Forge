--!strict
-- Drag-to-orbit and idle spin for a ViewportFrame.
--
-- The two motions are independent on purpose:
--
--   model   spins about its own Y axis every frame, always, at `modelSpinSpeed`
--   camera  orbits the model at the user's chosen yaw/pitch, and stays there
--
-- Dragging moves the camera. The model never pauses, because a turntable that
-- stops when you touch it reads as broken: the sword should keep turning while
-- you walk around it, the way a display piece does.
--
-- Camera placement follows the standard turntable formula:
--
--   cam.CFrame = CFrame.new(centre)
--       * CFrame.Angles(0, cameraYaw, 0)
--       * CFrame.Angles(cameraPitch, 0, 0)
--       * CFrame.new(0, 0, distance)
--
-- `centre` and `distance` come from the caller's framing solve, so the orbit
-- radius is whatever the blade or drone was already framed at. A late mesh
-- upgrade re-solves the framing and pushes it in through `setFraming`.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local OrbitController = {}

export type Handle = {
	--- Camera angles, radians. Writable: the ease settles on whatever is here.
	cameraYaw: number,
	cameraPitch: number,
	--- Model tilt added on top of the spin, radians. The strike slam.
	extraPitch: number,
	--- Model spin velocity added to the idle spin, rad/s. The strike kick.
	extraYawSpeed: number,
	dragging: boolean,
	--- Pixels the cursor travelled during the current (or last) drag. Callers
	--- that share their surface with a click action use this to tell a tap from
	--- an orbit: under ~6px is a tap.
	dragTravel: number,
	--- Re-frames the orbit after geometry changes (mesh lands, blade swaps).
	setFraming: (centre: Vector3, distance: number) -> (),
	destroy: () -> (),
}

export type Options = {
	--- Camera that renders the viewport. Required: the controller owns its CFrame.
	camera: Camera,
	--- Point the camera orbits, in the viewport's world space.
	centre: Vector3,
	--- Orbit radius, from the caller's framing solve.
	distance: number,
	--- Pivot the model rotates about. Defaults to the model's pivot at attach.
	origin: CFrame?,
	--- Idle spin starting angle.
	modelYaw: number?,
	--- Constant model tilt on X, e.g. the blade's -5 degree lean.
	modelPitch: number?,
	--- Constant model roll on Z, e.g. the blade's hero lean or the drone's bank.
	modelRoll: number?,
	--- Idle spin rate, rad/s. 0.9 in this game: a full turn every seven seconds.
	modelSpinSpeed: number?,
	--- Extra local transform painted on the model each frame. The blade's bob.
	offset: (() -> CFrame)?,
	cameraYaw: number?,
	cameraPitch: number?,
	--- Radians per pixel of cursor travel.
	sensitivity: number?,
	--- Camera pitch limits, radians. Symmetric.
	cameraPitchLimit: number?,
	--- Control that receives the press. A `ViewportFrame` never sees a mouse
	--- button, and a viewport under a modal is covered by the scrim's hit layer,
	--- so the caller passes the button that sits over the render. When omitted
	--- the press is resolved globally against the viewport rectangle.
	surface: GuiObject?,
}

local DEFAULT_SPIN = 0.9
local DEFAULT_SENSITIVITY = 0.008
local DEFAULT_PITCH_LIMIT = math.rad(40)
-- Easing rate for the camera angles. 16/s settles in about 180ms: attached to
-- the cursor, but a flick does not whip the frame.
local EASE = 16

--- Attaches orbit control to `viewport` and starts the render loop.
--- Returns a handle; call `handle.destroy()` when the viewport is torn down.
function OrbitController.attach(viewport: ViewportFrame, model: Model, options: Options): Handle
	local camera = options.camera
	local centre = options.centre
	local distance = math.max(options.distance, 0.1)
	local origin = options.origin or model:GetPivot()
	local modelPitch = options.modelPitch or 0
	local modelRoll = options.modelRoll or 0
	local spinSpeed = options.modelSpinSpeed or DEFAULT_SPIN
	local sensitivity = options.sensitivity or DEFAULT_SENSITIVITY
	local pitchLimit = options.cameraPitchLimit or DEFAULT_PITCH_LIMIT
	local offset = options.offset
	--- Press events arrive here when the caller has a control over the render.
	--- The rect used for hit-testing is the same object.
	local surface: GuiObject = options.surface or viewport

	local handle: Handle = {
		cameraYaw = options.cameraYaw or 0,
		cameraPitch = math.clamp(options.cameraPitch or 0, -pitchLimit, pitchLimit),
		extraPitch = 0,
		extraYawSpeed = 0,
		dragging = false,
		dragTravel = 0,
		setFraming = function(nextCentre: Vector3, nextDistance: number)
			centre = nextCentre
			distance = math.max(nextDistance, 0.1)
		end,
		destroy = function() end,
	}

	-- Deliberately NOT `Active`. An Active GuiObject marks every click on it as
	-- game-processed, which stops `UserInputService.InputBegan` from seeing the
	-- press at all - measured live: a click inside the frame reported
	-- `processed=true` while the frame itself never fired `InputBegan`. Input is
	-- resolved globally against the frame rectangle instead.
	viewport.Active = false

	local alive = true
	local dragging = false
	local dragType: Enum.UserInputType? = nil
	local activeTouch: InputObject? = nil
	local modelSpin = options.modelYaw or 0
	local easedYaw = handle.cameraYaw
	local easedPitch = handle.cameraPitch

	--- True when a pointer position sits inside the drag surface.
	---
	--- `InputObject.Position` and `GuiObject.AbsolutePosition` are both in
	--- screen pixels, so they compare directly. `GetMouseLocation()` does not:
	--- it reports from the top of the screen while a non-inset ScreenGui starts
	--- its coordinates below the top bar, and the two disagree by the inset
	--- height. Measured live on this build: a click at 445,200 read back as
	--- `Position = 445,200` and `GetMouseLocation() = 445,258`.
	local function insideSurface(point: Vector3): boolean
		local corner = surface.AbsolutePosition
		local size = surface.AbsoluteSize
		return point.X >= corner.X
			and point.X <= corner.X + size.X
			and point.Y >= corner.Y
			and point.Y <= corner.Y + size.Y
	end

	-- Last pointer position, in screen pixels. Deltas are computed from this
	-- rather than read from `InputObject.Delta`: a warped or synthetic cursor
	-- reports a position without a matching delta, and the drag would silently
	-- apply zero.
	local lastPointer: Vector3? = nil

	local function applyDrag(dx: number, dy: number)
		-- The model follows the cursor: drag right, the camera swings right with
		-- it; drag down, the camera rises so the model is seen from above. This
		-- is the "grab the object" direction, not the inverted "grab the world"
		-- direction the first pass shipped.
		handle.dragTravel += math.abs(dx) + math.abs(dy)
		handle.cameraYaw += dx * sensitivity
		handle.cameraPitch = math.clamp(handle.cameraPitch - dy * sensitivity, -pitchLimit, pitchLimit)
	end

	local function endDrag()
		dragging = false
		handle.dragging = false
		dragType = nil
		activeTouch = nil
	end

	local function beginDrag(kind: Enum.UserInputType, touch: InputObject?)
		if dragging then
			return
		end
		dragging = true
		handle.dragging = true
		handle.dragTravel = 0
		dragType = kind
		activeTouch = touch
		lastPointer = if touch then touch.Position else nil
	end

	--- Touch still arrives on the frame itself, which is the one path a mobile
	--- tap has.
	local began = viewport.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch then
			beginDrag(input.UserInputType, input)
		end
	end)

	--- When the caller hands in a control that sits over the render, the press
	--- comes from that control and not from the viewport. A `GuiButton` is the
	--- only object in this stack that ever sees a mouse button: a `ViewportFrame`
	--- does not fire `InputBegan` for the mouse on this build (measured, not
	--- assumed), and a viewport inside a modal is covered by the scrim's hit
	--- layer, which eats the press first.
	local beganSurface: RBXScriptConnection? = nil
	if options.surface then
		beganSurface = surface.InputBegan:Connect(function(input: InputObject)
			if dragging then
				return
			end
			local kind = input.UserInputType
			if kind == Enum.UserInputType.MouseButton1
				or kind == Enum.UserInputType.MouseButton2
				or kind == Enum.UserInputType.Touch
			then
				beginDrag(kind, if kind == Enum.UserInputType.Touch then input else nil)
				lastPointer = input.Position
			end
		end)
	end

	--- Without a surface control, mouse drags are handled globally, gated on the
	--- press landing inside the viewport rectangle.
	---
	--- Left and right both work: LMB is the obvious one, RMB is the habit every
	--- other 3D viewer trains. Once the drag starts it keeps going outside the
	--- frame, because a gesture should not die when the cursor crosses an edge.
	local beganGlobal = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or dragging or options.surface ~= nil then
			return
		end
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.MouseButton2 then
			if insideSurface(input.Position) then
				beginDrag(kind)
				lastPointer = input.Position
			end
		elseif kind == Enum.UserInputType.Touch then
			-- Touch has to arrive on the frame itself; the global event reports a
			-- position in the same space, so it is accepted here too.
			if insideSurface(input.Position) then
				beginDrag(kind, input)
			end
		end
	end)

	-- Global rather than viewport-local: a drag that leaves the frame has to
	-- keep orbiting, or the motion stops the moment the cursor crosses the edge
	-- of the box the player is already looking at.
	local changed = UserInputService.InputChanged:Connect(function(input: InputObject)
		if not dragging then
			return
		end
		if dragType == Enum.UserInputType.MouseButton1 or dragType == Enum.UserInputType.MouseButton2 then
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				local previous = lastPointer
				local current = input.Position
				if previous ~= nil then
					applyDrag(current.X - previous.X, current.Y - previous.Y)
				end
				lastPointer = current
			end
		elseif dragType == Enum.UserInputType.Touch then
			if input == activeTouch then
				applyDrag(input.Delta.X, input.Delta.Y)
			end
		end
	end)

	local ended = UserInputService.InputEnded:Connect(function(input: InputObject)
		if not dragging then
			return
		end
		if dragType == Enum.UserInputType.MouseButton1 or dragType == Enum.UserInputType.MouseButton2 then
			if input.UserInputType == dragType then
				endDrag()
				lastPointer = nil
			end
		elseif dragType == Enum.UserInputType.Touch then
			if input == activeTouch then
				endDrag()
			end
		end
	end)

	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt: number)
		if not alive or not model.Parent then
			return
		end
		local step = math.min(dt, 0.1)

		-- The model spin never consults `dragging`. That is the whole contract:
		-- the camera moves, the model keeps turning.
		modelSpin += step * (spinSpeed + handle.extraYawSpeed)
		local base = origin
		if offset then
			base = base * offset()
		end
		model:PivotTo(
			base
				* CFrame.Angles(modelPitch + handle.extraPitch, modelSpin, 0)
				* CFrame.Angles(0, 0, modelRoll)
		)

		local ease = math.min(1, step * EASE)
		-- Clamped at the point of use, not only at the point of input: the angles
		-- are public fields, and a direct write should not be able to put the
		-- camera under the floor.
		handle.cameraPitch = math.clamp(handle.cameraPitch, -pitchLimit, pitchLimit)
		easedYaw += (handle.cameraYaw - easedYaw) * ease
		easedPitch += (handle.cameraPitch - easedPitch) * ease

		camera.CFrame = CFrame.new(centre)
			* CFrame.Angles(0, easedYaw, 0)
			* CFrame.Angles(easedPitch, 0, 0)
			* CFrame.new(0, 0, distance)
	end)

	handle.destroy = function()
		if not alive then
			return
		end
		alive = false
		began:Disconnect()
		if beganSurface then
			beganSurface:Disconnect()
		end
		beganGlobal:Disconnect()
		changed:Disconnect()
		ended:Disconnect()
		connection:Disconnect()
	end

	return handle
end

return OrbitController
