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
local ContentProvider = game:GetService("ContentProvider")

local Sfx = {}

-- The kit, in two families.
--
-- `PING` and `CLICK` are client assets, so they resolve offline in Studio and in
-- a published place with no upload step. They carry melody and interface.
--
-- `STRIKE`, `SWEET`, `CRIT` and `ANVIL` are purpose-built metal pings, uploaded
-- to the account that owns the place: inharmonic plate modes with a 10ms hammer
-- transient, tuned so the click reads as struck steel instead of a body blow.
-- `STRIKE` is one voice, `SWEET` is a fifth-stacked chord with a low thump for
-- the green bar, and `CRIT` is the long ring an octave up. They share a key, so a
-- run of clicks is one instrument rather than three unrelated samples.
--
-- `impact_explosion_03`, `snap`, `hit`, `metal` and `impact_water` are gone for
-- good. The explosion was the last one standing and it was the wrong texture
-- under a hammer: a broadband blast over a click reads as a thud, and it buried
-- the ping the click is supposed to be.
local PING = "rbxasset://sounds/electronicpingshort.wav"
local CLICK = "rbxasset://sounds/clickfast.wav"
local STRIKE = "rbxassetid://71886932584271"
local SWEET = "rbxassetid://97522852807133"
local CRIT = "rbxassetid://121142281920008"
local ANVIL = "rbxassetid://95191181057410"

local BASE_VOLUME = 0.2

-- One pool per asset, created once, preloaded at boot.
--
-- This used to be 24 shared slots that had their `SoundId` rewritten on every
-- cue. That is why the kit felt late: reassigning `SoundId` invalidates the
-- decoded buffer attached to that instance, so a click could wait on a decode
-- before it started. Dedicated pools mean the buffer is already resident and
-- `:Play()` starts on the same frame as the press.
--
-- Sizes are per cue, not per pool: the strike is the only thing that fires at
-- click rate, so it gets the deepest pool and everything else stays small.
local POOL_SIZES: { [string]: number } = {
	[STRIKE] = 10,
	[SWEET] = 5,
	[CRIT] = 3,
	[ANVIL] = 6,
	[PING] = 6,
	[CLICK] = 6,
}

local pools: { [string]: { Sound } } = {}
local cursors: { [string]: number } = {}
local enabled = true
--- Player-controlled gain, 0..1. The mix below is authored at 100%; this is the
--- one multiplier every layer passes through, so the settings slider cannot
--- drift from the kit.
local volumeScale = 1

local function poolFor(asset: string): { Sound }
	local existing = pools[asset]
	if existing then
		return existing
	end
	local size = POOL_SIZES[asset] or 4
	local made = table.create(size)
	for index = 1, size do
		local sound = Instance.new("Sound")
		sound.Name = "SfxSlot"
		sound.SoundId = asset
		sound.Volume = BASE_VOLUME * volumeScale
		sound.Parent = SoundService
		made[index] = sound
	end
	pools[asset] = made
	cursors[asset] = 1
	return made
end

local function take(asset: string): Sound
	local made = poolFor(asset)
	local index = cursors[asset] or 1
	cursors[asset] = index % #made + 1
	return made[index]
end

--- Builds every pool and warms the decoder before the first click. Called once
--- from boot; the player's first strike should never be the frame that loads
--- the strike.
function Sfx.preload()
	local list: { Instance } = {}
	for asset in POOL_SIZES do
		for _, sound in poolFor(asset) do
			table.insert(list, sound)
		end
	end
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
	end)
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

--- Plays one layer on that asset's own pool. `delay` staggers a chord without
--- spawning a task for the zero case.
local function play(asset: string, speed: number, volume: number, delay: number?)
	if not enabled or volumeScale <= 0 then
		return
	end
	local sound = take(asset)
	sound.PlaybackSpeed = speed
	sound.Volume = math.clamp(volume * volumeScale, 0, 1)
	if delay == nil or delay <= 0 then
		sound:Play()
		return
	end
	task.delay(delay, function()
		if enabled and volumeScale > 0 and sound.Parent ~= nil then
			sound:Play()
		end
	end)
end

local function stopAll()
	for _, made in pools do
		for _, sound in made do
			sound:Stop()
		end
	end
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
	stopAll()
end

function Sfx.isEnabled(): boolean
	return enabled and volumeScale > 0
end

--- Sets the player's SFX level. Zero is a mute: every ringing layer stops on
--- the same frame, because a slider that only takes effect on the next click
--- reads as broken while a crate is mid-ceremony.
function Sfx.setVolume(value: number)
	volumeScale = math.clamp(if value == value then value else 1, 0, 1)
	if volumeScale > 0 then
		return
	end
	stopAll()
end

function Sfx.getVolume(): number
	return volumeScale
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
	play(ANVIL, jitter(0.9, 0.05), 0.09)
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
	play(ANVIL, jitter(0.62, 0.05), 0.12)
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
--- The click is one purpose-built sample: a 10ms hammer transient into an
--- inharmonic steel ring. Nothing else is layered under it, because the whole
--- point of the pass that produced it was to hear the ping and not a thud.
---
--- `sweet` is the band state at the moment of the click. The green bar gets a
--- different hit, not a louder one: a fifth-stacked chord with a low thump and a
--- short glint, so the reward for precision is a bigger sound rather than the
--- same sound with the volume up. `streak` lifts the whole chord a whole tone per
--- in-band hit, which is what makes a run of green-bar clicks build instead of
--- repeating.
function Sfx.strike(sweet: boolean, streak: number?)
	local climb = if streak then math.min(streak, 10) else 0

	if sweet then
		local lift = 2 ^ (math.min(climb, 5) * 2 / 12)
		play(SWEET, jitter(lift, 0.015), 0.22)
		play(PING, 2 * lift, 0.06, 0.03)
		return
	end

	play(STRIKE, jitter(1.0, 0.05), 0.15)
end

--- A critical strike, fired from the server event so it lands on the frame the
--- real number arrives. The longest ring in the kit, an octave above the strike,
--- with one low body under it: the ear should be able to tell a crit from a sweet
--- spot with the screen covered.
function Sfx.crit()
	play(CRIT, jitter(1.0, 0.02), 0.3)
	play(ANVIL, jitter(0.5, 0.02), 0.12, 0.01)
end

--- Tenth in-band strike: the window opens. A low body hit plus a rising triad,
--- so it reads as a gate unlocking rather than as a louder click. Left at five
--- layers for the same reason as the strike: this is a signature moment, and a
--- signature only changes on a listen.
function Sfx.streakComplete()
	play(ANVIL, 0.5, 0.3)
	play(PING, 1.32, 0.22)
	play(PING, 1.78, 0.2, 0.075)
	play(PING, 2.38, 0.2, 0.15)
	play(ANVIL, 1.9, 0.08, 0.16)
end

-- ---------------------------------------------------------------------------
-- Heat and the forge
-- ---------------------------------------------------------------------------

--- Heat released. A falling ping with a short mechanical spit under it: the
--- gauge empties, then the metal answers.
function Sfx.vent()
	play(PING, jitter(1.45, 0.08), BASE_VOLUME + 0.14)
	play(PING, jitter(0.72, 0.06), 0.1, 0.01)
	play(CLICK, jitter(1.6, 0.05), 0.12, 0.02)
	play(ANVIL, 1.1, 0.06, 0.10)
end

--- Crossing into the lock band. A low alarm body; no rising note, because
--- nothing good is happening.
function Sfx.overheat()
	play(ANVIL, jitter(0.5, 0.04), 0.24)
	play(CLICK, jitter(0.8, 0.05), 0.11)
	play(PING, jitter(0.55, 0.02), 0.09, 0.08)
end

--- The lock actually biting. One flat thud, no pitch movement.
function Sfx.burnout()
	play(ANVIL, jitter(0.5, 0.03), 0.28)
	play(CLICK, jitter(1.15, 0.05), 0.1, 0.05)
end

--- Starting a forge roll. A heavy anvil breath, not a slot machine. Two layers
--- only: the crate landing half a second later owns the weight, and stacking a
--- third knock here made the wind-up sound like the landing had already happened.
function Sfx.roll()
	play(ANVIL, jitter(0.58, 0.04), 0.22)
	play(PING, jitter(1.0, 0.04), 0.09, 0.04)
end

--- The crate hitting the stage. The heaviest thing in the kit: a low body, a
--- wooden knock, and the ring of the iron bands. This is phase one of the roll,
--- and it used to be a single `rollTick`, which is why the crate read as a
--- graphic arriving rather than as an object landing.
function Sfx.crateLand(gain: number?)
	local g = gain or 1
	-- Four layers, not three. The second low body at 0.30 is the chest hitting
	-- the bench; without it the crate sounds like a box of cutlery being set
	-- down.
	play(ANVIL, jitter(0.44, 0.03), 0.42 * g)
	play(CLICK, jitter(0.72, 0.04), 0.18 * g, 0.005)
	play(PING, jitter(0.66, 0.02), 0.13 * g, 0.03)
	play(ANVIL, jitter(0.30, 0.02), 0.12 * g, 0.012)
end

--- One crate taking the hit. This is the per-click payoff, not the reveal: a
--- short crack and a wooden knock, with a heavier body only on the crate that
--- actually opens.
function Sfx.crateBreak(final: boolean?)
	play(CLICK, jitter(if final then 0.86 else 1.16, 0.03), if final then 0.42 else 0.26)
	play(ANVIL, jitter(0.82, 0.05), if final then 0.30 else 0.19, 0.005)
	if final then
		play(ANVIL, jitter(0.55, 0.03), 0.22, 0.03)
		play(PING, jitter(0.92, 0.02), 0.22, 0.05)
	end
end

--- The crate splitting. A hard crack over the same body as the landing, so the
--- two read as the same object at two moments. `gain` lets the ceremony be
--- louder than the anvil without changing the anvil's mix.
function Sfx.crateShatter(gain: number?)
	local g = gain or 1
	-- The reveal downbeat. The low body is what makes the tick read as wood
	-- giving way instead of a firecracker in a cupboard.
	play(CLICK, jitter(0.95, 0.03), 0.34 * g)
	play(ANVIL, jitter(0.6, 0.03), 0.28 * g, 0.02)
	play(PING, jitter(1.2, 0.02), 0.18 * g, 0.04)
	play(ANVIL, jitter(0.40, 0.02), 0.12 * g, 0.01)
end

--- One tick of the roll cadence, climbing the same ladder as the strike band so
--- the wind-up and the payoff are in the same key.
function Sfx.rollTick(index: number)
	local step = math.clamp(index, 1, 8)
	local weight = 0.06 + step * 0.010
	play(CLICK, jitter(1.05 * note(step), 0.02), weight)
	play(PING, jitter(1.6 * note(step), 0.02), weight + 0.02, 0.005)
	-- The last two beats get a low body. Without it the rattle climbs in pitch
	-- but not in mass, and the crate reads as a timer rather than as pressure.
	if index >= 5 then
		play(ANVIL, jitter(0.6 + step * 0.03, 0.03), 0.13, 0)
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
	local weight = 0.11 + math.min(index, 10) * 0.016
	play(CLICK, jitter(1.05, 0.02), weight * 0.8)
	play(PING, jitter(degree(step), 0.005), weight + 0.10, 0.005)
	-- The last note lands on the tonic an octave up; give it a low octave so the
	-- click has a floor instead of only a ceiling. The first tonic in a ten-pull
	-- is the top of the scale, not the end, so only the actual last click gets it.
	if step == 8 and index >= total then
		play(PING, 0.5, 0.18, 0.01)
	end
	if index >= 5 then
		play(ANVIL, jitter(0.6 + math.min(index, 10) * 0.03, 0.03), 0.20, 0)
	end
end

--- A single heartbeat under the sealed hold. Low, soft and deliberately not a
--- tick: the rattle is over, and what is left is the player waiting.
function Sfx.heartbeat()
	play(ANVIL, jitter(0.5, 0.03), 0.22)
	play(PING, jitter(0.55, 0.02), 0.12, 0.03)
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
		play(PING, jitter(degree(index), 0.005), 0.12 + (index - first) * 0.012, (index - first) * 0.06)
	end
	play(ANVIL, jitter(0.5, 0.03), 0.2, count * 0.06)
end

--- One copy leaving the ceremony. Deliberately smaller than the reveal: a claim
--- happens once per sword now, so it has to be repeatable without becoming a
--- second fanfare. A rising sol-do fourth and the ring of the blade.
function Sfx.claim()
	play(PING, jitter(1.498, 0.005), 0.15)
	play(PING, jitter(2.0, 0.005), 0.13, 0.05)
	play(PING, jitter(1.0, 0.02), 0.12, 0.015)
	play(CLICK, jitter(1.0, 0.04), 0.09, 0.02)
end

--- The last copy leaving. The claim beat plus a low do, so the ceremony has a
--- downbeat instead of stopping on the same note as every individual claim.
function Sfx.claimAll()
	Sfx.claim()
	play(ANVIL, 0.5, 0.22, 0.02)
	play(PING, 0.5, 0.14, 0.08)
	play(PING, 1.0, 0.13, 0.14)
end

--- Forge celebration: a legendary blade drawn from the quench. The phrase is a
--- C-major arpeggio (do sol do mi sol do), so it resolves the do-re-mi ladder
--- the crate clicks climbed instead of landing on an arbitrary pitch.
function Sfx.forge()
	play(ANVIL, 0.5, 0.34)
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
		play(CLICK, jitter(1.7, 0.03), 0.08, 0.4)
	end
	if rank >= 4 then
		play(ANVIL, jitter(0.42, 0.02), 0.22, 0.38)
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

--- A copy melted into scrap. A falling tick over a short metal knock.
function Sfx.melt()
	play(CLICK, jitter(1.7, 0.06), 0.14)
	play(ANVIL, jitter(1.35, 0.04), 0.09, 0.03)
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
	play(ANVIL, 1.4, 0.08, 0.02)
end

--- A cache crack starting. Two hard taps: the lid, then the seal.
function Sfx.cacheCrack()
	play(CLICK, jitter(1.9, 0.04), 0.12)
	play(PING, jitter(1.7, 0.03), 0.08, 0.05)
	play(CLICK, jitter(2.3, 0.04), 0.09, 0.1)
end

--- A cache claim landing. Shorter than a forge, so the two do not blur.
function Sfx.cacheClaim()
	play(PING, jitter(2.1, 0.03), 0.12)
	play(PING, jitter(2.7, 0.03), 0.1, 0.06)
	play(PING, jitter(1.5, 0.03), 0.08, 0.03)
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
	play(ANVIL, 0.38, 0.36)
	play(PING, 0.72, 0.24, 0.06)
	play(PING, 1.08, 0.22, 0.16)
	play(PING, 1.62, 0.2, 0.26)
	play(PING, 2.16, 0.16, 0.36)
	play(ANVIL, 1.9, 0.12, 0.3)
end

--- A purchase confirmed.
function Sfx.purchase()
	play(PING, jitter(1.9, 0.03), 0.12)
	play(PING, jitter(2.4, 0.03), 0.1, 0.05)
end

return Sfx
