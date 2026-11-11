--!strict
-- Controller rumble, kept in one place.
--
-- Haptics are the one feedback channel that works when the screen is already
-- full. A crate that only shakes pixels is a video; a crate that kicks the pad
-- on the last hit is an object in the player's hands.
--
-- `SetMotor` is best-effort by design: not every platform exposes every motor,
-- and a device that cannot rumble must never throw inside a UI callback. Every
-- call is guarded twice (supported check plus pcall) and the stop is scheduled
-- on the same slot so two pulses cannot stack into a stuck motor.

local HapticService = game:GetService("HapticService")

local Haptics = {}

local enabled = true
local lastPulse = 0

type Motor = {
	input: Enum.UserInputType,
	motor: Enum.VibrationMotor,
}

local MOTORS: { Motor } = {
	{ input = Enum.UserInputType.Gamepad1, motor = Enum.VibrationMotor.Large },
	{ input = Enum.UserInputType.Gamepad1, motor = Enum.VibrationMotor.Small },
	{ input = Enum.UserInputType.Gamepad2, motor = Enum.VibrationMotor.Large },
	{ input = Enum.UserInputType.Gamepad2, motor = Enum.VibrationMotor.Small },
	{ input = Enum.UserInputType.Gamepad3, motor = Enum.VibrationMotor.Large },
	{ input = Enum.UserInputType.Gamepad3, motor = Enum.VibrationMotor.Small },
	{ input = Enum.UserInputType.Gamepad4, motor = Enum.VibrationMotor.Large },
	{ input = Enum.UserInputType.Gamepad4, motor = Enum.VibrationMotor.Small },
}

function Haptics.setEnabled(value: boolean)
	enabled = value
	if not value then
		Haptics.stop()
	end
end

local function supported(): { Motor }
	local usable = {}
	for _, entry in MOTORS do
		local ok, result = pcall(function()
			return HapticService:IsMotorSupported(entry.input, entry.motor)
		end)
		if ok and result then
			table.insert(usable, entry)
		end
	end
	return usable
end

--- One pulse on every supported motor. `strength` is 0-1; `duration` is seconds.
--- Rate-limited to one pulse per 40 ms so a click flood cannot turn the pad into
--- a continuous buzz.
function Haptics.pulse(strength: number, duration: number?)
	if not enabled then
		return
	end
	local now = os.clock()
	if now - lastPulse < 0.04 then
		return
	end
	lastPulse = now

	local amount = math.clamp(strength, 0, 1)
	local span = math.clamp(duration or 0.1, 0.02, 0.6)
	local usable = supported()
	if #usable == 0 then
		return
	end

	for _, entry in usable do
		pcall(function()
			HapticService:SetMotor(entry.input, entry.motor, amount)
		end)
	end

	task.delay(span, function()
		for _, entry in usable do
			pcall(function()
				HapticService:SetMotor(entry.input, entry.motor, 0)
			end)
		end
	end)
end

--- A rising rumble used by the sealed hold: three short pulses that get stronger.
function Haptics.build(steps: number?)
	if not enabled then
		return
	end
	local count = math.clamp(steps or 3, 1, 6)
	for index = 1, count do
		task.delay((index - 1) * 0.09, function()
			Haptics.pulse(0.18 + index * 0.12, 0.08)
		end)
	end
end

function Haptics.stop()
	for _, entry in MOTORS do
		pcall(function()
			HapticService:SetMotor(entry.input, entry.motor, 0)
		end)
	end
end

return Haptics
