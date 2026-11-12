---
title: Video 07 - game feel, the three audio layers, and the UI that carries them
source: Tap - "Apply this and your Roblox Game will Feel 100x Better" (link not recorded)
author: Tap
transcribed: Gemini
analysed: 2026-11-11
status: shipped in part - see ADR-066 and ADR-067
tags:
  - roblox
  - game-feel
  - audio
  - ui
---

**What this note is for.** A checklist of the polish levers one video names,
mapped onto this game, with an honest ledger of what was already in the build
when the note arrived. The original paste was written by a model that had not
seen the repository, so half of it prescribes work that shipped weeks ago and
two sections contradict decisions this project already made on purpose.

**Read the ledger before the prescriptions.** Anything marked SHIPPED is a
description of the current build, not an order. Anything marked SUPERSEDED was
replaced by a better answer and must not be reintroduced.

**The one-line takeaway.** A deep progression tree cannot save a loop whose
basic action feels flat. The strike, the vent and the roll are the only three
things a player does ten thousand times, and each of them has to be built out of
more than one clip, more than one colour, and more than one frame.

---

## 1. The three pillars

**Tactile input and immediate feedback.** Every action answers within a frame.
Where the server owns the number, the client predicts it and the server corrects
it. This is already the contract in `ForgeView.strike`: `StateStore.predictClick`
mirrors the server's maths before the click leaves the machine, and a wrong
prediction is corrected by the next payload rather than by a spinner.

**Layered sound.** A single clip per action reads as a UI blip no matter how it
is pitched. The shape is transient (0 to 50ms, the attack), body (50 to 300ms,
the weight) and tail (300ms onward, the room). Add pitch jitter so a thousand
strikes are never one strike. ADR-066 is this pillar, executed.

**Anticipation and scale dynamics.** Rewards need wind-up and a physical punch
on arrival, not a static pop-up. The roll sequence is this pillar; the heat
gauge and the streak rail are its smaller siblings.

## 2. Layout rules, and where this build stands

The video's reference layout, redrawn for this game:

```
+---------------------------------------------------------------------------+
| [QUANTUM FORGE] [* SM] [<> AETHER] [@ CORES] [ASCEND] [DAILY] |            |
|                                    [? GUIDE] [FEEDBACK] [CODEX] [BOARDS]  |
+---------------------------------------------------------------------------+
| [Rate strip: NO DRONES ......................................... 0/s]      |
+----------------------------------------------+----------------------------+
|                                              | [FLEET] [RUNES] [TECH] [STORE]
|           3D FORGE AND ANVIL VIEWPORT        |----------------------------+
|                                              |  [ 3D drone / item stage ] |
|      the whole render is the strike target   |  [ BUILD 1 ]  [ BUILD 10 ] |
|                                              |----------------------------+
|                                              |  [ICON] Row        [BUY]   |
|                                              |         description        |
|----------------------------------------------|----------------------------|
| CORE HEAT [============ 84% ==] [PURGE HEAT] |                            |
+----------------------------------------------+----------------------------+
```

| Rule from the video | Status |
| --- | --- |
| Remove the black plate under the blade, let the viewport fill the height | SHIPPED. `ForgeView.buildViewport` has no plate; the gauge, streak rail and prompt are painted onto the render. |
| The whole render is the strike target | SHIPPED. `StrikeButton` is full-bleed over the stage and transparent. |
| Utility keys become one icon strip | SHIPPED. `Icons.luau` draws the guide, feedback, codex, boards, gear and backpack marks. |
| No text buttons for the vault and settings | SHIPPED. Backpack and gear keys in the forge header. |
| Uniform list rows with a badge well on the left | SHIPPED for RUNES (104px, 88px badge), STORE (104px, 72px badge) and FLEET (72px ladder rows). TECH stays at 132px on purpose; see section 7. |
| Vault: full-width header, scrap pill, 4 column 3D grid, permanent inspector, reduced dock | SHIPPED. `InventoryModal`, measured in `build-log-forge-12`. The inspector drawer is now two columns and the missing REROLL verb has a button (ADR-067). |
| Rarity-tinted multi-stop stage gradients | SHIPPED. `StageBackdrop.paint` takes warm, cool and accent, and every stage and card well uses it. |
| Drag to orbit on the forge, vault and drone stages | SHIPPED. Forge and vault via `Options.surface` (ADR-055), drone via the global path. |

## 3. The audio architecture

**The shape.** Three clips per action, every one of them pitch-jittered. The
video's argument is that a single clip repeated is mechanical because the ear
finds the identical waveform; the fix is not more clips but more layers.

**Status: partly applied, then narrowed (ADR-066, ADR-113).** The layer stack was
tried on the strike first, because that is the action the player repeats ten
thousand times. It was played once and rejected: `hit.wav` is a body blow, so the
click lost its metal edge and gained a wooden thump, and the sustained tail of
`impact_explosion_03` smeared the transient that gives the strike its snap. The
strike went back to two clips, then to one: the click is a single pitched
`impact_explosion_03`, and the band answer is the same sample higher still.

The kit now ships three samples only. `hit.wav`, `snap.mp3`, `metal.ogg` and
`impact_water.mp3` were removed entirely in ADR-113:

| Layer | Asset | Where |
| --- | --- | --- |
| metal tick | `sounds/electronicpingshort.wav` | chimes, ladders, UI |
| click | `sounds/clickfast.wav` | UI tick, hover, tab, transient |
| body | `sounds/impact_explosion_03.mp3` | strike, crit, crates, ascent |

`rollTick` climbs a major pentatonic ladder in semitones instead of the old
`1.15 + 0.09 * n` ramp, so the wind-up and the band climb share a key.


**The rule that came out of it.** Layering is for events the player has not
heard before. A sound with an established identity is a remix target, and a
remix only ships after a listen, not after a rationale. This environment cannot
hear, so the strike, the roll and the fanfare keep the mix that was tuned
against actual play.

Coverage is complete for hover, tab, modal, roll, vent, overheat, burnout, crit,
crate land, crate shatter, result, equip, melt, reroll, rune, tech, cache crack,
cache claim, dispatch, return, ascend and purchase.

## 4. The roll sequence

The video's four phases, with this build's timings:

| Phase | Video | This build |
| --- | --- | --- |
| 1. Slam | 0.0 to 0.3s, heavy clunk, frame punch | The crate falls for 0.34s on Quart-In with a Back-Out settle, the camera kicks wide, `Sfx.crateLand`, `Vfx.shake` at 16. |
| 2. Wind-up | 0.3 to 1.2s, rattle, seams emit, ticks rise | Six rattle beats from 0.4s, each with a shorter gap and a brighter seam, `Sfx.rollTick` climbing the scale. |
| 3. Shatter | 1.2s, shockwave and flash | `Sfx.crateShatter`, shockwave on the stage, sparks, white flash. |
| 4. Result | 1.2s+, turntable, toast | The blade mounts on the live turntable with its variant glow, the result card and `Sfx.result(rank)`. |

The build runs about 0.2s longer than the video's clock because the rattle needs
six beats to read as pressure rather than as a wobble. A roll is not a thing a
player watches once; it is a thing they watch four hundred times, and the
sequence is the only part of the loop where anticipation is free.

## 5. Prescriptions this project replaced

These two sections of the original paste are wrong for this build. They are kept
only so nobody re-derives them.

**SUPERSEDED: post-ascension roll price starts at 50 SM and scales as
`Base * 1.15 ^ rolls`.** A flat base ignores income, so the price is either
invisible to a late profile or a wall to an early one. `ForgeConfig.rollCost`
floors the banner price at eighteen strikes of the player's own income and ramps
the banner price by rolls taken at that banner (ADR-056). A post-ascension run
has low income by definition, so its first rolls are cheap for the same reason
the video wanted them cheap. The numbers do not need a second rule.

**SUPERSEDED: a Quality Codex tab with six tiers and its own cash and yield
multipliers.** A second multiplier on top of grade, element, prefix and suffix
double-counts every copy already in the save (ADR-060). The quality ladder ships
as twenty-four derived bands whose printed multiplier is the copy's true
product. The tab exists; the extra axis does not.

**Already done before the note arrived:** the roll deducts Star-Matter
server-side, and the heat lockout gates only strikes, so a purged player can
still roll (ADR-058).

## 6. Why the original paste was rewritten

The file arrived as one block of pasted markdown with three problems:

- It ended with an imperative block pointing at `GAME_FEEL_AND_UI_SPEC.md`, a
  file that does not exist in this repository. A future session would have gone
  looking for it, or worse, treated the block as a live order.
- Roughly half of it describes surfaces that shipped in forge-10 through
  forge-12, which turns a reference note into a duplicate work order.
- Two sections contradict ADRs this project wrote after testing the alternative.

The reference material (pillars, layout, layers, roll timeline) survived intact.

## 7. Deliberately not copied

**Uniform 104px rows including TECH.** The tech node carries a name, a
description, an effect line and a progress bar; 104px clips it. Matching the
number would mean deleting a datum to satisfy a measurement, which is the wrong
trade. The panel reads as one system because the badges, gutters and type sizes
are shared, not because three of four shelves are the same height.

**The video's black-box removal applied to the instrument row.** The gauge and
the streak rail sit on the render, but they still occupy the bottom 148px of the
card. Removing them entirely would take away the heat readout, which is the one
number a player watches while striking.

**A second currency for the sake of the layout.** The top bar has room for a
fourth pill. It does not have a fourth thing worth counting.

## 8. Still open

- The strike was the first thing judged by ear and it failed, which is the most
  useful result of the pass. The new verbs (`crit`, `crateLand`, `crateShatter`)
  have not been listened to yet: they are additive on events that were silent,
  which is the safe direction, but a roll and a crit are the two moments to hear
  next.
- The band ladder is still a ratio (`1.5 * (1 + 0.045 * streak)`) on the strike,
  because that is the part players know. Only `rollTick` uses the semitone
  ladder. If the two ever need to agree, that is a listen, not a refactor.
- `screen_capture` returns null on some Studio builds; the verification for this
  note is `selene` and `rojo` plus what the seam can measure and what the eye
  reads off the frames that do arrive.
