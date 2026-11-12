--!strict
-- Background loop. The game was silent between anvil hits, which read as dead
-- rather than as quiet: a forge needs a room tone to sit under the work.
--
-- The track is Creator Store audio by APMOfficial ("Dark Pulsing Synth", 2:24),
-- which is licensed for use in Roblox experiences and costs nothing. It is a
-- slow, sinister synth pulse, which is the same temperature as the forge: not a
-- melody to listen to, a bed the anvil and the crate can land on top of.
--
-- Music has its own persisted switch, separate from `Sfx`. A player may want the
-- anvil and the crate without a bed under them, or the reverse; folding both into
-- one mute makes the settings sheet lie about what it controls. `Main` applies
-- the saved `settings.music` on the first payload and `Sections` calls this when
-- the MUSIC row flips.
local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")

local Theme = require(script.Parent.Theme)

local Music = {}

local TRACK = "rbxassetid://9042781325"
--- Under the quietest body layer. The track is mastered hot; 0.16 sits under the
--- anvil without disappearing on a laptop speaker.
local TARGET_VOLUME = 0.16
local FADE_IN = 2.4
local FADE_OUT = 0.5

local sound: Sound? = nil
local enabled = true
--- Invalidates a pending pause when the switch flips back on inside the fade.
local fadeToken = 0
--- The running gain tween. Starting a second fade without cancelling the first
--- lets the mute and the intro fight over `Volume` for a frame or two.
local fadeTween: Tween? = nil

local function fadeTo(volume: number, duration: number)
	local current = sound
	if current == nil then
		return
	end
	if fadeTween then
		fadeTween:Cancel()
	end
	-- Linear and independent of reduce-motion: this is gain, not travel, and a
	-- hard cut at the start of the loop is worse than a fade for everyone.
	fadeTween = Theme.fade(current, duration, { Volume = volume })
end

--- Starts the loop. Safe to call twice; the second call is a no-op.
function Music.init()
	if sound ~= nil then
		return
	end
	local current = Instance.new("Sound")
	current.Name = "ForgeMusic"
	current.SoundId = TRACK
	current.Looped = true
	current.Volume = 0
	current.Parent = SoundService
	sound = current

	task.spawn(function()
		-- The first notes should already be decoded when the loop starts, so the
		-- intro does not arrive as a stutter over the first strike.
		pcall(function()
			ContentProvider:PreloadAsync({ current })
		end)
		if sound ~= current or not enabled then
			return
		end
		current:Play()
		fadeTo(TARGET_VOLUME, FADE_IN)
	end)
end

--- Follows the SFX preference. Disabling fades out before pausing so a mute
--- never clips a note in half.
function Music.setEnabled(value: boolean)
	enabled = value
	fadeToken += 1
	local current = sound
	if current == nil then
		return
	end
	if value then
		if not current.IsPlaying then
			if current.IsPaused then
				current:Resume()
			else
				current:Play()
			end
		end
		fadeTo(TARGET_VOLUME, FADE_OUT)
		return
	end

	local token = fadeToken
	fadeTo(0, FADE_OUT)
	task.delay(FADE_OUT + 0.05, function()
		if token == fadeToken and sound == current and not enabled then
			current:Pause()
		end
	end)
end

function Music.isEnabled(): boolean
	return enabled
end

function Music.destroy()
	fadeToken += 1
	if fadeTween then
		fadeTween:Cancel()
		fadeTween = nil
	end
	if sound then
		sound:Destroy()
		sound = nil
	end
end

return Music
