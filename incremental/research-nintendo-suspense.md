---
type: research
status: shipped
updated: 2026-11-11
aliases:
  - nintendo-suspense
tags:
  - research
  - crates
  - ceremony
  - game-feel
  - audio
---

# The Nintendo beat: suspense, edges and sound

The crate ceremony was already a sequence, but it read as a sequence of states:
drop, click, click, reveal. Nintendo's reward moments read as a sequence of
**tensions**: something is about to happen, the game knows it, and the player is
given just enough time to feel it before the answer lands.

This note records the pattern we studied and the parts of it that shipped in
`CrateReveal`, `Sfx`, `Haptics` and `Vfx`.

## The five-beat reveal

1. **Tell.** The player must know a reward is coming before the animation starts.
   In a Zelda chest it is the chest itself; in Mario Kart it is the item box
   spinning on the HUD. Our tell is the sealed rack: the last crate is gone and
   the prompt changes to `SEALED`.
2. **Wind-up.** A short, readable build. Nintendo rarely cuts straight from
   "opened" to "got it"; the wind-up is the game promising that the next beat
   matters. Ours is the light column, the closing vignette, the riser and two
   heartbeats.
3. **Hold.** A beat of near-stillness before the payoff. This is the "edge" the
   user meant: the screen stops, the sound drops out, and the player leans in.
   Ours is `SEALED_HOLD = 0.62 s`, longer than the six-beat rattle that precedes
   it. The hold is the most important 300 ms in the whole ceremony.
4. **Payoff.** The answer arrives with every channel at once: a flash, a ring,
   sparks, a fanfare, controller rumble and the blade. The payoff should be
   louder and brighter than anything before it, and it should be *short*.
5. **Afterglow.** The player gets to look at what they won. Ours is the copy
   rail: every sword from a x3 or x10, the best one gold, then one `COLLECT`
   key. Without the afterglow a ten-pull is one sword and nine invisible ones.

The mistake the old reveal made was spending its whole budget on the payoff. The
payoff is the cheapest beat; the wind-up and the afterglow are what make it feel
earned.

## Sound design

The sources below converge on one rule: an impact is not one sound. It is a
stack of roles that arrive in order.

| Role | What it does | Our layer |
| --- | --- | --- |
| Contact transient | The first 0-30 ms. Tells the ear something touched something. | `hit.wav` / `clickfast.wav` |
| Body / weight | 30-150 ms. Gives the object mass. | `impact_explosion_03.mp3` pitched down |
| Texture | The material: wood, steel, glass. | `metal.ogg`, `snap.mp3` |
| Tail / space | The room after the event. | `impact_water.mp3`, long pings |

Three more rules we used:

- **Pitch is a ladder, not a smear.** The rattle and the strike climb a
  pentatonic ladder (`Sfx.note`), so the tenth beat is a note rather than a
  pitch drift.
- **Silence is a layer.** The two heartbeats in the sealed hold are deliberately
  quiet and spaced 200 ms apart. The gap between them is doing more work than a
  third sound would.
- **The claim is its own verb.** The reveal says "look at this"; the claim says
  "it is yours". `Sfx.claim` is a rising pair over a swish, not a second fanfare.

Sources: `jammyfu/open-game-skills` — `juice-vfx`, `audio-feel`, `haptic-rumble`
(GitHub, MIT). Background: Vlambeer's "The Art of Screenshake", Steve Swink's
*Game Feel*, and the public Nintendo item-get / chest-opening grammar.

## Haptics

Controller rumble is the one channel that still works when the screen is full.
The rules from `haptic-rumble` that mattered:

- Query `HapticService:IsMotorSupported` before every request, and never let an
  unsupported device throw inside a UI callback.
- Rumble never carries critical information alone. Every pulse has a visual and
  audio partner.
- Stop the motor on the same slot that started it, and stop everything on close
  or disconnect.

`Haptics.luau` implements one pulse path, a three-step build for the sealed
hold, and a rate limit so a click flood cannot turn the pad into a buzz.

## What shipped

| Beat | Before | After |
| --- | --- | --- |
| Wind-up | 0.3 s hold, no light | 0.62 s hold, light column, vignette closes, riser, two heartbeats, rumble build |
| Payoff | One flash, one ring | Rarity flash + white flash on high ranks, ray fan behind the blade, ring, sparks, shake, rumble |
| Afterglow | Best copy only, `COLLECT n` | Copy rail with every sword, best marked in gold, staggered in left to right |
| Claim | Hard `Visible = false` | White wash, shake, claim stinger, rumble, cut hidden behind the VFX flash |
| Ambience | Flat stage | Dust motes in the stage light, beam from above |

## Honesty

- The ray fan is twelve 2 px frames on a zero-size pivot. It is cheap, but it is
  still a full-screen overlay when all twelve are visible on a phone. The
  reduce-motion path hides it.
- `SEALED_HOLD` is 0.62 s. A player who opens ten crates one at a time pays that
  hold once, not ten times, because it only runs after the last crate.
- The research is a synthesis of public design writing and observable Nintendo
  grammar. No Nintendo source code or proprietary data was used.
