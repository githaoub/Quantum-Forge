--!strict
-- The sound kit: layered, pitch-jittered, and built only from assets that are
-- provably present.
--
-- Every id here resolves offline in Studio because the files ship inside the
-- Roblox client's own `content/sounds` directory (`rbxasset://`). That is the
-- whole reason for the restriction: a marketplace id that has not been uploaded
-- yet is a silent failure in a published place, and a guessed id is worse than
-- no sound at all. The 22 generated VFX/sound sheets are still pending upload;
-- when they land, this module is the single place they get swapped in.
--
-- Layering is the point. A single ping reads as a UI blip. A sharp high transient
-- over a low body, both pitch-jittered 0.95-1.08, reads as a hammer hitting
-- metal, and it never machine-guns, because no two hits land on the same pitch.
--
-- Mute is local and instant. `Sfx.setEnabled(false)` stops every slot already
-- playing, so a player who mutes during a streak gets silence on the next frame
-- rather than after a server round trip. `Main.client` applies the saved
-- preference on boot and the settings modal writes it back.

local SoundService = game:GetService("SoundService")

local Sfx = {}

-- Proven-present client assets.
--
-- Every id below was checked with `ContentProvider:PreloadAsync` in Edit mode
-- before it was allowed in. Two well-known names failed that check and are not
-- here: `sounds/swoosh.wav` and `sounds/bell.wav` both report
-- `Enum.AssetFetchStatus.Failure`, and a guessed id is worse than no sound.
local PING = "rbxasset://sounds/electronicpingshort.wav"
local IMPACT = "rbxasset://sounds/impact_explosion_03.mp3"
local WATER = "rbxasset://sounds/impact_water.mp3"

-- The three layers the strike was missing. `hit` is the hammer face (0-50ms),
-- `impact_explosion` pitched low is the anvil mass (50-300ms), and `metal` is
-- the ring of the steel after the hit. One short clip per action reads as a UI
-- blip no matter how it is pitched; three clips stacked read as an object.
local SMACK = "rbxasset://sounds/hit.wav"
local RING = "rbxasset://sounds/metal.ogg"
local SWISH = "rbxasset://sounds/swordslash.wav"
local CLICK = "rbxasset://sounds/clickfast.wav"
local SNAP = "rbxasset://sounds/snap.mp3"

-- 24 slots: a burst of eight clicks can each want four layers, a forge result
-- can want eight, and reusing a slot mid-playback truncates the previous hit,
-- which is audible.
local POOL_SIZE = 24
local BASE_VOLUME = 0.2

local pool: { Sound } = {}
local nextIndex = 1
local enabled = true

local function ensurePool()
	if #pool > 0 then
		return
	end
	for index = 1, POOL_SIZE do
		local sound = Instance.new("Sound")
		sound.Name = string.format("SfxSlot%d", index)
		sound.SoundId = PING
		sound.Volume = BASE_VOLUME
		sound.Parent = SoundService
		pool[index] = sound
	end
end

local function take(): Sound
	ensurePool()
	local sound = pool[nextIndex]
	nextIndex = nextIndex % POOL_SIZE + 1
	return sound
end

--- Random spread for a hammer: never the same pitch twice in a row.
local function jitter(scale: number, spread: number): number
	return scale * (1 - spread + math.random() * spread * 2)
end

-- Major pentatonic, one octave plus the octave above it, in semitones.
--
-- The old band climb multiplied the pitch by 1.045 per streak point, which
-- drifts a quarter tone every ten strikes and never lands anywhere. A ladder in
-- semitones means the tenth in-band strike is a note instead of a smear, and a
-- run of strikes becomes something you can hum.
local PENTATONIC = { 0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24 }

--- Playback speed for the nth step of the ladder, clamped at the top.
local function note(step: number): number
	local index = math.clamp(step + 1, 1, #PENTATONIC)
	return 2 ^ (PENTATONIC[index] / 12)
end

--- Plays one layer on a pooled slot. `delay` staggers a chord without spawning
--- a task for the zero case.
local function play(asset: string, speed: number, volume: number, delay: number?)
	if not enabled then
		return
	end
	local sound = take()
	sound.SoundId = asset
	sound.PlaybackSpeed = speed
	sound.Volume = volume
	if delay == nil or delay <= 0 then
		sound:Play()
		return
	end
	task.delay(delay, function()
		if enabled and sound.Parent ~= nil then
			sound:Play()
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Mute
-- ---------------------------------------------------------------------------

--- Turns every layer off and cuts whatever is still ringing. Called by the
--- settings modal and on boot from the saved profile.
function Sfx.setEnabled(value: boolean)
	enabled = value
	if value then
		return
	end
	for _, sound in pool do
		sound:Stop()
	end
end

function Sfx.isEnabled(): boolean
	return enabled
end

-- ---------------------------------------------------------------------------
-- UI
-- ---------------------------------------------------------------------------

--- The quiet tick under every button press. Deliberately the smallest sound in
--- the kit: a menu that barks on every tap is worse than a silent one.
function Sfx.ui()
	play(CLICK, jitter(1.15, 0.04), 0.05)
	play(PING, jitter(2.6, 0.04), 0.045)
end

--- Hover on a live control. Half the UI tick, high and short, so scanning a list
--- reads as texture rather than as a dozen clicks.
function Sfx.hover()
	play(CLICK, jitter(1.45, 0.05), 0.022)
end

--- Tab switch: two notes a fourth apart, the second one late enough to read as
--- a step rather than a chord.
function Sfx.tab()
	play(CLICK, jitter(1.0, 0.03), 0.05)
	play(PING, jitter(1.9, 0.03), 0.06)
	play(PING, jitter(2.55, 0.03), 0.04, 0.035)
end

--- A modal opening. Impact first, chime after: the card arrives, then settles.
function Sfx.modal()
	play(IMPACT, jitter(0.9, 0.05), 0.09)
	play(PING, jitter(1.5, 0.04), 0.06, 0.04)
end

--- A modal closing. Falling pair, no impact, so it can never be mistaken for an
--- action that succeeded.
function Sfx.close()
	play(PING, jitter(1.35, 0.03), 0.055)
	play(PING, jitter(1.0, 0.03), 0.045, 0.045)
end

--- Rejected action. Low, short, and not harsh: the player already knows.
function Sfx.error()
	play(IMPACT, jitter(0.62, 0.05), 0.12)
	play(PING, jitter(0.8, 0.03), 0.07, 0.02)
end

--- Currency or scrap landing in the purse.
function Sfx.coin()
	play(PING, jitter(2.2, 0.03), 0.08)
	play(PING, jitter(2.75, 0.03), 0.05, 0.04)
end

-- ---------------------------------------------------------------------------
-- Strike
-- ---------------------------------------------------------------------------

--- One anvil strike.
---
--- The strike is the most repeated sound in the game and it is deliberately the
--- thinnest thing in the kit. A three-layer stack was tried here (a `hit`
--- transient, an `impact` body under it, a `metal` ring on top) and it made the
--- click *worse* on the first listen: `hit` is a body blow, not a hammer face, so
--- the mix turned a bright metal tick into a wooden thump, and the sustained
--- explosion tail smeared the transient that gives the strike its snap.
---
--- Two layers, both short. `electronicpingshort` is the metal, `impact` an octave
--- and a half up is the hammer behind it. That is the sound a player already
--- associates with the anvil.
---
--- `sweet` is the band state at the moment of the click; `streak` is the live
--- in-band counter. The chime climbs a semitone-ish per point of streak, so the
--- tenth strike of a run is audibly a different note from the first: the ear
--- tracks the rail before the eye does.
function Sfx.strike(sweet: boolean, streak: number?)
	local climb = if streak then math.min(streak, 10) else 0
	local body = jitter(1.0, 0.065)
	play(PING, body, BASE_VOLUME)
	-- High, quiet, fast: the metal in the hammer. This is the layer that makes
	-- the click feel like it has mass behind it.
	play(IMPACT, jitter(2.55, 0.05), 0.10)

	if sweet then
		play(PING, 1.5 * (1 + climb * 0.045), BASE_VOLUME + 0.05)
		play(PING, 2.25 * (1 + climb * 0.045), 0.10, 0.045)
	end
end

--- A critical strike, fired from the server event so it lands on the frame the
--- real number arrives. Bright, short, and one octave above the band: the ear
--- should be able to tell a crit from a sweet spot with the screen covered.
function Sfx.crit()
	play(SMACK, jitter(1.55, 0.03), 0.19)
	play(RING, jitter(1.85, 0.01), 0.13, 0.02)
	play(PING, jitter(3.1, 0.02), 0.1, 0.03)
	play(IMPACT, jitter(0.55, 0.03), 0.2, 0.01)
end

--- Tenth in-band strike: the window opens. A low body hit plus a rising triad,
--- so it reads as a gate unlocking rather than as a louder click. Left at five
--- layers for the same reason as the strike: this is a signature moment, and a
--- signature only changes on a listen.
function Sfx.streakComplete()
	play(IMPACT, 0.55, 0.34)
	play(PING, 1.32, 0.22)
	play(PING, 1.78, 0.2, 0.075)
	play(PING, 2.38, 0.2, 0.15)
	play(IMPACT, 1.9, 0.12, 0.16)
end

-- ---------------------------------------------------------------------------
-- Heat and the forge
-- ---------------------------------------------------------------------------

--- Heat released. A pressurised whoosh under a falling ping: air first, metal
--- second, which is the order the verb happens in.
function Sfx.vent()
	play(WATER, jitter(1.45, 0.08), BASE_VOLUME + 0.14)
	play(SWISH, jitter(0.72, 0.06), 0.1, 0.01)
	play(PING, 0.62, BASE_VOLUME + 0.02, 0.03)
	play(IMPACT, 1.1, 0.10, 0.10)
end

--- Crossing into the lock band. Steam and a low alarm body; no rising note,
--- because nothing good is happening.
function Sfx.overheat()
	play(WATER, jitter(0.8, 0.05), 0.28)
	play(IMPACT, jitter(0.42, 0.04), 0.24)
	play(PING, jitter(0.55, 0.02), 0.09, 0.08)
end

--- The lock actually biting. One flat thud, no pitch movement.
function Sfx.burnout()
	play(IMPACT, jitter(0.35, 0.03), 0.3)
	play(WATER, jitter(1.15, 0.05), 0.16, 0.05)
end

--- Starting a forge roll. A heavy anvil breath, not a slot machine. Two layers
--- only: the crate landing half a second later owns the weight, and stacking a
--- third knock here made the wind-up sound like the landing had already happened.
function Sfx.roll()
	play(IMPACT, jitter(0.58, 0.04), 0.22)
	play(PING, jitter(1.0, 0.04), 0.09, 0.04)
end

--- The crate hitting the stage. The heaviest thing in the kit: a low body, a
--- wooden knock, and the ring of the iron bands. This is phase one of the roll,
--- and it used to be a single `rollTick`, which is why the crate read as a
--- graphic arriving rather than as an object landing.
function Sfx.crateLand()
	play(IMPACT, jitter(0.44, 0.03), 0.34)
	play(SMACK, jitter(0.72, 0.04), 0.17, 0.005)
	play(RING, jitter(0.66, 0.02), 0.11, 0.03)
	play(WATER, jitter(0.9, 0.06), 0.05, 0.02)
end

--- The crate splitting. A hard crack over the same body as the landing, so the
--- two read as the same object at two moments.
function Sfx.crateShatter()
	play(SNAP, jitter(0.95, 0.03), 0.22)
	play(IMPACT, jitter(0.8, 0.03), 0.24, 0.02)
	play(RING, jitter(1.2, 0.02), 0.14, 0.04)
end

--- One tick of the roll cadence, climbing the same ladder as the strike band so
--- the wind-up and the payoff are in the same key.
function Sfx.rollTick(index: number)
	local step = math.clamp(index, 1, 8)
	play(CLICK, jitter(1.05 * note(step), 0.02), 0.06)
	play(PING, jitter(1.6 * note(step), 0.02), 0.05, 0.005)
end

--- Forge celebration: a legendary blade drawn from the quench. Heavy low thud,
--- metallic clang, then a bright chime an octave up.
---
--- The fanfare is left at five layers. A `hit` knock and a second `metal` ring
--- were tried in the same pass that broke the strike, and they pushed the low
--- thud forward until the reveal read as a door closing. The result stinger below
--- adds its own layers by rank; this one stays the phrase it always was.
function Sfx.forge()
	play(IMPACT, 0.5, 0.34)
	play(PING, 0.78, 0.22, 0.05)
	play(PING, 1.56, 0.2, 0.11)
	play(IMPACT, 2.1, 0.11, 0.12)
	play(PING, 2.34, 0.14, 0.2)
end

--- Result stinger, scaled by variant rank. 1 Standard, 2 Tempered, 3
--- Overclocked, 4 Void-Touched, 5 Prismatic.
function Sfx.result(variantIndex: number)
	local rank = math.clamp(variantIndex, 1, 5)
	Sfx.forge()
	if rank <= 1 then
		return
	end
	play(PING, jitter(2.9, 0.02), 0.12, 0.18)
	if rank >= 3 then
		play(PING, jitter(3.4, 0.02), 0.12, 0.26)
		play(IMPACT, jitter(1.7, 0.03), 0.1, 0.24)
	end
	if rank >= 4 then
		play(IMPACT, jitter(0.42, 0.02), 0.24, 0.3)
		play(PING, jitter(0.62, 0.02), 0.14, 0.34)
	end
	if rank >= 5 then
		play(PING, jitter(1.16, 0.01), 0.18, 0.4)
		play(PING, jitter(1.74, 0.01), 0.16, 0.48)
		play(PING, jitter(2.6, 0.01), 0.14, 0.56)
	end
end

--- A copy equipped. Two ascending notes, no impact: this is a choice, not a
--- strike.
function Sfx.equip()
	play(PING, jitter(1.55, 0.03), 0.1)
	play(PING, jitter(2.1, 0.03), 0.08, 0.05)
end

--- A copy melted into scrap. Wet hiss under a short metal knock.
function Sfx.melt()
	play(WATER, jitter(1.7, 0.06), 0.14)
	play(IMPACT, jitter(1.35, 0.04), 0.09, 0.03)
end

--- Variant reroll: three rising ticks, then a small resolve.
function Sfx.reroll()
	play(PING, jitter(1.2, 0.02), 0.07)
	play(PING, jitter(1.5, 0.02), 0.07, 0.06)
	play(PING, jitter(1.9, 0.02), 0.07, 0.12)
	play(PING, jitter(2.4, 0.02), 0.09, 0.19)
end

-- ---------------------------------------------------------------------------
-- Other verbs
-- ---------------------------------------------------------------------------

--- Rune crafted or socketed. Purely crystalline: three tall pings, no impact
--- layer, so it can never be mistaken for a strike.
function Sfx.rune()
	play(PING, 2.0, 0.18)
	play(PING, 2.52, 0.16, 0.06)
	play(PING, 3.0, 0.13, 0.12)
end

--- A tech node bought. Lower and rounder than a rune, so the two currency
--- sinks are distinguishable with the eyes closed.
function Sfx.tech()
	play(PING, 1.18, 0.2)
	play(PING, 1.76, 0.15, 0.07)
	play(IMPACT, 1.4, 0.08, 0.02)
end

--- A cache crack starting. Two hard taps: the lid, then the seal.
function Sfx.cacheCrack()
	play(IMPACT, jitter(1.9, 0.04), 0.12)
	play(PING, jitter(1.7, 0.03), 0.08, 0.05)
	play(IMPACT, jitter(2.3, 0.04), 0.09, 0.1)
end

--- A cache claim landing. Shorter than a forge, so the two do not blur.
function Sfx.cacheClaim()
	play(PING, jitter(2.1, 0.03), 0.12)
	play(PING, jitter(2.7, 0.03), 0.1, 0.06)
	play(IMPACT, jitter(1.5, 0.03), 0.08, 0.03)
end

--- Drone dispatch. A rising two-note launch.
function Sfx.dispatch()
	play(PING, jitter(1.25, 0.03), 0.09)
	play(PING, jitter(1.85, 0.03), 0.08, 0.07)
end

--- Drone return. Falling pair, so the fleet reads as coming home.
function Sfx.returned()
	play(PING, jitter(1.7, 0.03), 0.09)
	play(PING, jitter(1.15, 0.03), 0.08, 0.07)
end

--- Ascension. The biggest stinger in the kit: low body, long rise, final chord.
function Sfx.ascend()
	play(IMPACT, 0.38, 0.36)
	play(PING, 0.72, 0.24, 0.06)
	play(PING, 1.08, 0.22, 0.16)
	play(PING, 1.62, 0.2, 0.26)
	play(PING, 2.16, 0.16, 0.36)
	play(IMPACT, 1.9, 0.12, 0.3)
end

--- A purchase confirmed.
function Sfx.purchase()
	play(PING, jitter(1.9, 0.03), 0.12)
	play(PING, jitter(2.4, 0.03), 0.1, 0.05)
end

return Sfx
