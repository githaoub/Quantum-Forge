---
type: build-log
status: shipped in Studio, not yet published
updated: 2026-11-12
aliases:
  - forge-27
tags:
  - build-log
  - crates
  - audio
  - game-feel
---

# Forge 27 - The crate gets its own instrument

The crate section was the one paying surface in the game that borrowed its
whole voice from the forge. The landing was an `ANVIL` body with a click and two
pings, the per-press crack was the same stack quieter, and the reveal added one
more `ANVIL` under it. On the visual side the landing had no shake at all, the
clicks moved the stage by 1.3 to 4.5px, and the reveal shook the stage by
`6 + rank * 1.2` and never touched the screen. The forge, by comparison, lands
with a 16px viewport shake and an 8px screen shake, clicks at `6 * amount` on
the viewport plus `3.5 + 3.5 * amount` on the screen, and reveals at
`7 + rank` plus `5 + rank * 1.2`.

This pass makes the crate a first-class event: eight purpose-built samples, the
forge's shake numbers at every beat, a stronger white pop, and a clean stage with
no guide card over it.

## The sound family

| Cue | Roblox id | Length | Built from | Plays on |
| --- | --- | --- | --- | --- |
| `CRATE_LAND` | 71087127981046 | 0.88s | 125 to 38 Hz saturated sub, 78 Hz cavity, 136 Hz plank, iron bands at 470 / 1160 / 2350 Hz, ten rivet grains | the crate touching the stage |
| `CRATE_HITS` A | 112903040076273 | 0.20s | 176 Hz body, 92 Hz cavity, iron at 860 Hz | a press with no open |
| `CRATE_HITS` B | 101485910396327 | 0.20s | 224 Hz body, 118 Hz cavity, iron at 1180 Hz | a press with no open |
| `CRATE_HITS` C | 125593282218554 | 0.20s | 146 Hz body, 76 Hz cavity, iron at 640 Hz | a press with no open |
| `CRATE_CRACK` | 124020777399189 | 0.50s | 104 Hz snap, 9 kHz to 900 Hz air sweep, 18 splinter grains | one crate giving way |
| `CRATE_SEAL` | 130549066084047 | 0.42s | bolt slide, 330 / 880 Hz iron, 72 Hz thud | the last press of the pull |
| `CRATE_RISE` | 75379241961315 | 0.60s | swept noise 180 Hz to 7 kHz, 42 to 96 Hz pressure, nine high ticks | the sealed hold |
| `CRATE_SHATTER` | 125700571754654 | 1.35s | 11 kHz to 620 Hz air sweep, 26 plank grains, 22 iron shards, 40 splinters, 0.85s sub | the reveal |

The synthesis is in `%TEMP%\opencode\audio-lab\build_crate_kit.py`. Three rules
matter for the next pass:

1. **Wood is a cavity plus planks, not a low sine.** The body modes are
   `1.00 / 1.92 / 3.14 / 4.70 / 6.30` at 20 to 32 dB down with decays of 1 to
   3.4x. Every layer is tapered for its last 4ms after mixing. A component that
   ends on a nonzero sample is a broadband click, and the spectrogram shows it
   as a bright vertical line through the whole hit.
2. **The breach is air before it is wood.** `CRATE_SHATTER` starts with a
   one-pole lowpass whose cutoff falls from 11 kHz to 620 Hz in 0.20s. That is
   the "kssh" that makes the reveal read as a breach instead of a louder
   landing. The planks and shards arrive on top.
3. **Sub is a shape, not a volume.** The landing and the shatter run a sine
   sweep through `tanh` so a phone speaker hears the pitch drop as harmonics.
   The shatter sub is 0.85s; the debris tail is what carries the rest.

The sounds are mono 48 kHz PCM, peak normalised to 0.89, with the crack and the
shatter lowpassed at 12 and 13 kHz. Without that trim a sharp transient spreads
to Nyquist and a phone reads the top as hiss instead of wood. All eight assets
report `Active / Approved`.

## What the mix does

- `crateLand` is `CRATE_LAND` at 0.55 x gain, one knuckle at 0.15 x gain and one
  low `ANVIL` at 0.12 x gain. The knuckle is the second knock of the crate
  touching down; the `ANVIL` is the chest.
- `crateBreak(opens, last)` is a knuckle on every press at 0.28, a
  `CRATE_CRACK` at 0.34 plus a knuckle at 0.18 when a crate gives way, and a
  `CRATE_SEAL` at 0.40 only on the last press. `last` exists because a ten-pull
  opens on all ten presses; tying the seal to `opens` would bite the lock ten
  times.
- `crateTick` keeps the do-re-mi ladder on `PING` and puts a knuckle under it at
  `weight + 0.03`. The knuckle tightens `1.8%` per scale step, so the box is the
  same object from click one to click ten.
- `crateShatter` is the whole breach at 0.55 x gain, one low `ANVIL` at 0.16 and
  one `PING` at 0.08 to glue it to the forge chord that follows.
- `riser` adds `CRATE_RISE` at 0.30 under the top of the ladder. The old hold
  had a quiet third act; the swell makes the wait pressure instead of silence.

The 69-slot boot-time pool is 36 old slots plus 33 crate slots. The three
knuckles are the point: one sample under pitch jitter is a machine gun at ten
presses in two seconds.

## The shake budget

| Beat | Forge | Crate before | Crate now |
| --- | --- | --- | --- |
| Landing | 16 viewport, 8 screen | none | 16 viewport, 8 screen |
| Press | 6 * amount viewport, 3.5 + 3.5 * amount screen | 1.3 to 4.5 stage | 1.6 + 0.55 * beat stage, 2.4 + 0.6 * beat (+1.2 open) screen |
| Seal | n/a | 4.5 stage | 7 stage, 8 screen |
| Reveal | 7 + rank card, 5 + rank * 1.2 screen | 6 + rank * 1.2 stage | 7 + rank stage, 5 + rank * 1.2 screen |
| Claim | n/a | 1.5 stage | 3.2 stage, 2.6 screen |
| Exit | n/a | 7 stage | 7 stage, 7 screen |

The reveal white pop moved from `0.18 + rank * 0.02` to
`0.32 + rank * 0.045` over 0.24s, on top of the existing 0.86 rarity wash. The
exit keeps its 0.6 `Vfx.flash`, which is what hides the cut back to the page.

The scrim grew 28 design px on every edge. `fitScreen` used to size the black
`TextButton` to the viewport plus the GUI inset exactly, so a screen shake moved
the scrim off the edge and exposed the page for a few frames. The bleed is
invisible at rest; at 0.72 canvas scale it is 20 screen px, against a maximum
shake of 11 design px.

## The guide card

The first capture of the reveal had the guide card over the blade and its ring
pointing at the anvil behind the scrim. The guide layer is at ZIndex 80 so it
can float over the vault and the codex; that also put it over the ceremony. A
one-shot hide was not enough, because the guide starts when the welcome card is
dismissed and can land mid-ceremony. `hideGuide` now subscribes to the layer's
`Visible` property and holds it down while the phase is not `closed`;
`restoreGuide` puts the previous value back after `root.Visible = false`. A guide
that was already dismissed stays dismissed.

## Studio evidence

- A full three-crate pull logged, in order: `CRATE_LAND` at 0.59, knuckle A at
  0.22, knuckle C at 0.14, `CRATE_CRACK` at 0.27, knuckle B at 0.15,
  `CRATE_SEAL` at 0.32, `CRATE_RISE` at 0.24, `CRATE_SHATTER` at 0.62, the low
  `ANVIL` at 0.27, then the forge chord. Volumes include the 0.8 SFX setting.
- The canvas moved on the landing (`max 4` at 15fps), on every press and on the
  reveal (`max 6` at 15fps). A `shakeTest 30` reached 26px on the canvas and a
  `shakeTest` with a 1s duration ran for 14 frames. The Studio session renders
  at 15fps, so a 0.26s shake only gets four samples; the property values are
  correct and the frame count matches the duration.
- The guide layer read `false` during the reveal and `true` after
  `crateDismiss`.
- The page preview seam (`cratePreview event_horizon`) now paints the same
  reveal as the forge: a `VfxScreen` wash peaked at 0.45 and the canvas moved
  during the 0.34s screen shake.
- The reveal capture at the flash peak is a full-screen purple wash with the
  blade, rings, rays and name; no guide card, no dark scrim edge.
- `selene src` is 0/0/0 and `rojo build default.project.json` succeeds.

## What is not verified

- **The mix by ear.** No tool in this environment can hear it. The samples were
  designed, measured, and classifier checked (knuckles at 0.78 to 0.88 for "a
  person knocking on a wooden crate", landing at 0.68 for "a heavy wooden crate
  crashing onto a floor", rise at 0.60 for "a cinematic riser"). The montage is
  `%TEMP%\opencode\audio-lab\crate_kit\audition.wav`. Whether the shatter is the
  right kind of exciting is still a human judgement.
- **Touch and gamepad.** The shake and the new sounds were only exercised with a
  mouse on a desktop viewport.
- **A real ten-pull.** The full walk was a three-crate preview with a forced
  answer. The ten-press ladder is the same code path and was not played with a
  ten-pull's timing.
- **A published place.** The eight assets are approved on the creator account;
  moderation in a published place has not been exercised.
