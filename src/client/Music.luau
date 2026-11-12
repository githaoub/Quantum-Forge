--!strict
-- Background loop. The game was silent between anvil hits, which read as dead
-- rather than as quiet: a forge needs a room tone to sit under the work.
--
-- The track is Creator Store audio by APMOfficial ("Dark Pulsing Synth", 2:24),
-- which is licensed for use in Roblox experiences and costs nothing. It is a
-- slow, sinister synth pulse, which is the same temperature as the forge: not a
-- melody to listen to, a bed the anvil and the crate can land on top of.
--
-- Music has its own persisted level, separate from `Sfx`. A player may want the
-- anvil and the crate without a bed under them, or the reverse; folding both into
-- one slider makes the settings sheet lie about what it controls. `Main` applies
-- the saved `settings.musicVolume` on the first payload and `Sections` calls this
-- while the MUSIC slider moves.
local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")

local Theme = require(script.Parent.Theme)

local Music = {}

local TRACK = "rbxassetid://9042781325"
--- Under the quietest body layer. The track is mastered hot; 0.16 sits under the
--- anvil without disappearing on a laptop speaker. This is the 100% level; the
--- player's saved slider scales it.
local TARGET_VOLUME = 0.16
local FADE_IN = 2.4
-- Shorter than the intro fade: the slider has to answer while the hand is still
-- on it, and a 2.4s lag reads as a broken control.
local FADE_OUT = 0.35

local sound: Sound? = nil
--- 0..1 slider level. Defaults to the same 55% the save migration writes, so a
--- client that boots before the first payload is not briefly full volume.
local volumeScale = 0.55
--- Invalidates a pending pause when the level comes back up inside the fade.
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
		if sound ~= current or volumeScale <= 0 then
			return
		end
		current:Play()
		fadeTo(TARGET_VOLUME * volumeScale, FADE_IN)
	end)
end

--- Sets the player's music level. Zero fades out and pauses; any level above
--- zero resumes the same loop where it stopped, so a slider nudge never restarts
--- the track.
function Music.setVolume(value: number)
	local nextVolume = math.clamp(if value == value then value else 0.55, 0, 1)
	if nextVolume == volumeScale then
		return
	end
	local wasSilent = volumeScale <= 0
	volumeScale = nextVolume
	fadeToken += 1

	local current = sound
	if current == nil then
		return
	end
	if volumeScale > 0 then
		if not current.IsPlaying then
			if current.IsPaused then
				current:Resume()
			else
				current:Play()
			end
		end
		fadeTo(TARGET_VOLUME * volumeScale, if wasSilent then FADE_IN else FADE_OUT)
		return
	end

	local token = fadeToken
	fadeTo(0, FADE_OUT)
	task.delay(FADE_OUT + 0.05, function()
		if token == fadeToken and sound == current and volumeScale <= 0 then
			current:Pause()
		end
	end)
end

function Music.getVolume(): number
	return volumeScale
end

function Music.isEnabled(): boolean
	return volumeScale > 0
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
