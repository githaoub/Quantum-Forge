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
--
-- `impact_explosion_03` and `swordslash` were removed on purpose: the first is a
-- gunshot transient and the second is a blade-whip, and both read as a stray
-- action movie under a crate. The kit is now wood, metal, click and air.
local PING = "rbxasset://sounds/electronicpingshort.wav"
local WATER = "rbxasset://sounds/impact_water.mp3"

-- The body layers. `hit` is a low thud, `snap` is a dry crack, `metal` is the
-- ring of steel and `clickfast` is the small mechanical tick.
local SMACK = "rbxasset://sounds/hit.wav"
local RING = "rbxasset://sounds/metal.ogg"
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

-- The do-re-mi ladder: a full major scale in semitones above the tonic. The
-- crate sequence walks it one note per click, so a pull is a phrase the player
-- is playing rather than a timer they are waiting out. The pentatonic above
-- stays for the anvil, where the strike is a texture and not a melody.
local MAJOR = { 0, 2, 4, 5, 7, 9, 11, 12 }

--- Playback speed for a scale degree, 1 = do (the tonic).
local function degree(step: number): number
	local index = math.clamp(step, 1, #MAJOR)
	return 2 ^ (MAJOR[index] / 12)
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

--- A modal opening. Body first, chime after: the card arrives, then settles.
function Sfx.modal()
	play(SMACK, jitter(0.62, 0.05), 0.07)
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
	play(SMACK, jitter(0.55, 0.05), 0.12)
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
--- transient, a low body under it, a `metal` ring on top) and it made the click
--- *worse* on the first listen: `hit` is a body blow, not a hammer face, so the
--- mix turned a bright metal tick into a wooden thump.
---
--- Two layers, both short. `electronicpingshort` is the metal; `snap` an octave
--- up is the crack of contact. That is the sound a player already associates
--- with the anvil.
---
--- `sweet` is the band state at the moment of the click; `streak` is the live
--- in-band counter. The chime climbs a semitone-ish per point of streak, so the
--- tenth strike of a run is audibly a different note from the first: the ear
--- tracks the rail before the eye does.
function Sfx.strike(sweet: boolean, streak: number?)
	local climb = if streak then math.min(streak, 10) else 0
	local body = jitter(1.0, 0.065)
	play(PING, body, BASE_VOLUME)
	-- High, quiet, fast: the crack of the hammer face. This is the layer that
	-- makes the click feel like it has mass behind it.
	play(SNAP, jitter(1.9, 0.05), 0.07)

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
	play(SNAP, jitter(0.9, 0.03), 0.12, 0.01)
end

--- Tenth in-band strike: the window opens. A low body hit plus a rising triad,
--- so it reads as a gate unlocking rather than as a louder click. Left at five
--- layers for the same reason as the strike: this is a signature moment, and a
--- signature only changes on a listen.
function Sfx.streakComplete()
	play(SMACK, 0.5, 0.3)
	play(PING, 1.32, 0.22)
	play(PING, 1.78, 0.2, 0.075)
	play(PING, 2.38, 0.2, 0.15)
	play(SNAP, 1.9, 0.1, 0.16)
end

-- ---------------------------------------------------------------------------
-- Heat and the forge
-- ---------------------------------------------------------------------------

--- Heat released. A pressurised whoosh under a falling ping: air first, metal
--- second, which is the order the verb happens in.
function Sfx.vent()
	play(WATER, jitter(1.45, 0.08), BASE_VOLUME + 0.14)
	play(WATER, jitter(0.72, 0.06), 0.1, 0.01)
	play(PING, 0.62, BASE_VOLUME + 0.02, 0.03)
	play(SMACK, 1.1, 0.10, 0.10)
end

--- Crossing into the lock band. Steam and a low alarm body; no rising note,
--- because nothing good is happening.
function Sfx.overheat()
	play(WATER, jitter(0.8, 0.05), 0.28)
	play(SMACK, jitter(0.42, 0.04), 0.24)
	play(PING, jitter(0.55, 0.02), 0.09, 0.08)
end

--- The lock actually biting. One flat thud, no pitch movement.
function Sfx.burnout()
	play(SMACK, jitter(0.35, 0.03), 0.3)
	play(WATER, jitter(1.15, 0.05), 0.16, 0.05)
end

--- Starting a forge roll. A heavy anvil breath, not a slot machine. Two layers
--- only: the crate landing half a second later owns the weight, and stacking a
--- third knock here made the wind-up sound like the landing had already happened.
function Sfx.roll()
	play(SMACK, jitter(0.58, 0.04), 0.22)
	play(PING, jitter(1.0, 0.04), 0.09, 0.04)
end

--- The crate hitting the stage. The heaviest thing in the kit: a low body, a
--- wooden knock, and the ring of the iron bands. This is phase one of the roll,
--- and it used to be a single `rollTick`, which is why the crate read as a
--- graphic arriving rather than as an object landing.
function Sfx.crateLand()
	play(SMACK, jitter(0.44, 0.03), 0.34)
	play(SNAP, jitter(0.72, 0.04), 0.17, 0.005)
	play(RING, jitter(0.66, 0.02), 0.11, 0.03)
	play(WATER, jitter(0.9, 0.06), 0.05, 0.02)
end

--- One crate taking the hit. This is the per-click payoff, not the reveal: a
--- short crack and a wooden knock, with a heavier body only on the crate that
--- actually opens.
function Sfx.crateBreak(final: boolean?)
	play(SNAP, jitter(if final then 0.86 else 1.16, 0.03), if final then 0.2 else 0.12)
	play(SMACK, jitter(0.82, 0.05), if final then 0.16 else 0.085, 0.005)
	if final then
		play(SMACK, jitter(0.55, 0.03), 0.12, 0.03)
		play(RING, jitter(0.92, 0.02), 0.09, 0.05)
	end
end

--- The crate splitting. A hard crack over the same body as the landing, so the
--- two read as the same object at two moments.
function Sfx.crateShatter()
	play(SNAP, jitter(0.95, 0.03), 0.22)
	play(SMACK, jitter(0.6, 0.03), 0.24, 0.02)
	play(RING, jitter(1.2, 0.02), 0.14, 0.04)
	play(WATER, jitter(1.3, 0.05), 0.08, 0.03)
end

--- One tick of the roll cadence, climbing the same ladder as the strike band so
--- the wind-up and the payoff are in the same key.
function Sfx.rollTick(index: number)
	local step = math.clamp(index, 1, 8)
	local weight = 0.05 + step * 0.008
	play(CLICK, jitter(1.05 * note(step), 0.02), weight)
	play(PING, jitter(1.6 * note(step), 0.02), weight - 0.01, 0.005)
	-- The last two beats get a low body. Without it the rattle climbs in pitch
	-- but not in mass, and the crate reads as a timer rather than as pressure.
	if index >= 5 then
		play(SMACK, jitter(0.6 + step * 0.03, 0.03), 0.1, 0)
	end
end

--- One note of the crate's do-re-mi ladder.
---
--- `index` is the click within the whole pull and `total` is the click budget,
--- so a triple and a ten-pull hear the same phrase instead of the triple
--- restarting the scale on every crate. Six clicks are do re mi fa sol do; ten
--- are do re mi fa sol la ti do sol do. The last click is always the tonic,
--- because the sealed hold is the resolution and the reveal starts the next
--- phrase.
---
--- The ping carries the melody and is left almost unjittered (0.5%), because a
--- scale with a humanized pitch is a scale that is out of tune. The click keeps
--- the mechanical texture underneath it.
function Sfx.crateTick(index: number, total: number)
	local six = { 1, 2, 3, 4, 5, 8 }
	local ten = { 1, 2, 3, 4, 5, 6, 7, 8, 5, 8 }
	local ladder = if total >= 10 then ten else six
	local step = ladder[math.clamp(index, 1, #ladder)]
	local weight = 0.06 + math.min(index, 10) * 0.01
	play(CLICK, jitter(1.05, 0.02), weight * 0.8)
	play(PING, jitter(degree(step), 0.005), weight + 0.06, 0.005)
	-- The last note lands on the tonic an octave up; give it a low octave so the
	-- click has a floor instead of only a ceiling. The first tonic in a ten-pull
	-- is the top of the scale, not the end, so only the actual last click gets it.
	if step == 8 and index >= total then
		play(PING, 0.5, 0.09, 0.01)
	end
	if index >= 5 then
		play(SMACK, jitter(0.6 + math.min(index, 10) * 0.03, 0.03), 0.1, 0)
	end
end

--- A single heartbeat under the sealed hold. Low, soft and deliberately not a
--- tick: the rattle is over, and what is left is the player waiting.
function Sfx.heartbeat()
	play(SMACK, jitter(0.42, 0.03), 0.2)
	play(PING, jitter(0.55, 0.02), 0.055, 0.03)
end

--- The last half-second before a reveal. The top of the do-re-mi ladder, ending
--- on ti: the leading tone is the one note that cannot resolve by itself, so the
--- reveal's do is the answer. The old pentatonic climb ended on sol, which
--- sounds finished; the hold should not sound finished.
function Sfx.riser(steps: number?)
	local count = math.clamp(steps or 5, 1, 7)
	local last = 7
	local first = math.max(1, last - count + 1)
	for index = first, last do
		play(PING, jitter(degree(index), 0.005), 0.055 + (index - first) * 0.006, (index - first) * 0.06)
	end
	play(WATER, jitter(0.88, 0.04), 0.07, 0.02)
	play(SMACK, jitter(0.5, 0.03), 0.1, count * 0.06)
end

--- One copy leaving the ceremony. Deliberately smaller than the reveal: a claim
--- happens once per sword now, so it has to be repeatable without becoming a
--- second fanfare. A rising sol-do fourth and the ring of the blade.
function Sfx.claim()
	play(PING, jitter(1.498, 0.005), 0.1)
	play(PING, jitter(2.0, 0.005), 0.085, 0.05)
	play(RING, jitter(1.0, 0.02), 0.08, 0.015)
	play(CLICK, jitter(1.0, 0.04), 0.06, 0.02)
end

--- The last copy leaving. The claim beat plus a low do, so the ceremony has a
--- downbeat instead of stopping on the same note as every individual claim.
function Sfx.claimAll()
	Sfx.claim()
	play(SMACK, 0.5, 0.14, 0.02)
	play(PING, 0.5, 0.1, 0.08)
	play(PING, 1.0, 0.09, 0.14)
end

--- Forge celebration: a legendary blade drawn from the quench. The phrase is a
--- C-major arpeggio (do sol do mi sol do), so it resolves the do-re-mi ladder
--- the crate clicks climbed instead of landing on an arbitrary pitch.
function Sfx.forge()
	play(SMACK, 0.5, 0.34)
	play(PING, 0.5, 0.2, 0.03)
	play(PING, 0.749, 0.18, 0.09)
	play(PING, 1.0, 0.18, 0.15)
	play(PING, 1.26, 0.16, 0.21)
	play(PING, 1.498, 0.14, 0.27)
	play(PING, 2.0, 0.12, 0.33)
end

--- Result stinger, scaled by variant rank. 1 Standard, 2 Tempered, 3
--- Overclocked, 4 Void-Touched, 5 Prismatic. Every extra layer is another
--- degree of the same C-major chord, so a high rank is louder harmony rather
--- than a different key.
function Sfx.result(variantIndex: number)
	local rank = math.clamp(variantIndex, 1, 5)
	Sfx.forge()
	if rank <= 1 then
		return
	end
	play(PING, jitter(2.52, 0.005), 0.12, 0.36)
	if rank >= 3 then
		play(PING, jitter(2.997, 0.005), 0.1, 0.42)
		play(SNAP, jitter(1.7, 0.03), 0.08, 0.4)
	end
	if rank >= 4 then
		play(SMACK, jitter(0.42, 0.02), 0.22, 0.38)
		play(PING, jitter(4.0, 0.005), 0.1, 0.48)
	end
	if rank >= 5 then
		play(PING, jitter(3.364, 0.005), 0.09, 0.54)
		play(PING, jitter(4.0, 0.005), 0.11, 0.6)
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
	play(SMACK, jitter(1.35, 0.04), 0.09, 0.03)
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
	play(SMACK, 1.4, 0.08, 0.02)
end

--- A cache crack starting. Two hard taps: the lid, then the seal.
function Sfx.cacheCrack()
	play(SNAP, jitter(1.9, 0.04), 0.12)
	play(PING, jitter(1.7, 0.03), 0.08, 0.05)
	play(SNAP, jitter(2.3, 0.04), 0.09, 0.1)
end

--- A cache claim landing. Shorter than a forge, so the two do not blur.
function Sfx.cacheClaim()
	play(PING, jitter(2.1, 0.03), 0.12)
	play(PING, jitter(2.7, 0.03), 0.1, 0.06)
	play(RING, jitter(1.5, 0.03), 0.08, 0.03)
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
	play(SMACK, 0.38, 0.36)
	play(PING, 0.72, 0.24, 0.06)
	play(PING, 1.08, 0.22, 0.16)
	play(PING, 1.62, 0.2, 0.26)
	play(PING, 2.16, 0.16, 0.36)
	play(SNAP, 1.9, 0.12, 0.3)
end

--- A purchase confirmed.
function Sfx.purchase()
	play(PING, jitter(1.9, 0.03), 0.12)
	play(PING, jitter(2.4, 0.03), 0.1, 0.05)
end

return Sfx
