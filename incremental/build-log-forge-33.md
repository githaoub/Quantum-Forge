# Forge 33: feedback where the player is looking

Date: 2026-11-13

## The complaint

The ASCEND and DAILY keys already moved a little when they became actionable, but
the owner read the motion as a trick of the eye. The cues were a 2px stroke
changing transparency and a 3% scale, which at the edge of vision is below the
threshold of "something happened". The payout number and the crit also appeared
on the anvil plate while the player was watching their cursor or the blade.

## What changed

### Verb keys

`HudController` now gives each ready verb four cues on one beat:

1. A `ReadyGlow` frame inside the plate, filled with the verb's own accent (gold
   for ASCEND, emerald for DAILY), fading between 0.68 and 0.82 transparency.
2. The ring goes from 2px to 5px and from 0.37 to 0.02 transparency, in the
   accent colour instead of the outline colour.
3. The whole plate scales 1.00 to 1.05 around its centre.
4. The mark scales 6% on the icon's own `UIScale`.

The mark pulse deliberately reuses the UIScale that `Icons.build` already put on
the 24px canvas. A second UIScale on the same object is undefined, and it would
also break the icon fit the bar was laid out for. The base fit is captured once
and every pulse multiplies it.

Both verbs keep their own frequency, so they do not beat together and read as
one animation instead of two alerts.

### Floating numbers

`Vfx` gained `FloatOpts.at` and `Vfx.screenPoint`. `ForgeView.strike` now takes
the input point and puts the payout under the pointer, with a 12px jitter
instead of the 38px jitter that was tuned for an anvil-sized target. Space and
gamepad fall back to `Vfx.pointer`, then to the stage.

The payout is set at `Theme.Text.Heading` (22px), up from `Subheading` (18px).

The crit in `Main` is anchored on the blade stage, not on the anvil. The stage
is what the player is watching, so the flourish arrives where their eyes are.

`Vfx.float` now measures the string with `TextService:GetTextSize` and grows the
label box. The crit uses `Theme.Text.Hero` (46px), which never fit the old
260x40 box: it lost its cap height and its last digit. The box is 277x55 for
`CRIT  +1.23M` and `TextFits` is true.

Two correctness fixes came out of the same pass:

- `toLocal` reads the live UIScale instead of a cached fit. A play window that
  resized after boot left the cached number stale, which put effects tens of
  pixels off their anchor.
- The edge clamp converts the layer's physical size back into design units
  before clamping, so a number near the right or bottom edge is not pulled
  inward by the scale factor.

## Evidence

Studio, real Quantum Forge place, Play mode, 1212x576 game area, canvas
1686x720 at 0.719.

Verb keys, sampled three times over 0.5s:

| key | ring | transparency | glow | plate | mark |
| --- | --- | --- | --- | --- | --- |
| ASCEND | 2.01 .. 3.16px | 0.36 .. 0.23 | 0.81 .. 0.76 | 1.000 .. 1.019 | 0.833 .. 0.852 |
| DAILY | 4.56 .. 4.98px | 0.07 .. 0.02 | 0.74 .. 0.68 | 1.028 .. 1.049 | 0.861 .. 0.883 |

The ASCEND samples landed off the peak of its faster wave; both keys reach the
same 5px / 0.02 / 0.68 / 1.05 envelope. The ring colour reports gold
`1, 0.757, 0.239` and emerald `0.357, 0.890, 0.604`, not the outline colour the
old pass used.

Payout: a strike at GUI (497, 372) captured the label at creation at design
(685, 512) against a cursor at design (691, 517). The 6px / 5px difference is the
jitter. Label 22px, box 260x40, `TextFits` true.

Crit: the server fired `{ kind = "crit", amount = 1234567 }`. The client
captured `CRIT  +1.23M` at 46px, box 277x55, `TextFits` true, at design
(658, 434) against a blade stage centre of design (691, 437). The 33px
horizontal difference is the jitter, the vertical difference is 3px.

`selene src`: 0 errors, 0 warnings, 0 parse errors.

## Files

- `src/client/HudController.luau`: `ReadyGlow`, mark pulse, stronger ring and
  plate scale.
- `src/client/Vfx.luau`: `at`, `screenPoint`, measured boxes, live UIScale.
- `src/client/ForgeView.luau`: strike point, payout placement, `swordAnchor`.
- `src/client/Main.client.luau`: crit anchored on the blade stage.

## Still open

- A human look at the pulse on a real screen. The numbers say it is five times
  the old amplitude, but only an eye can say it is not too much.
- DataStore writes still return HTTP 401, so sessions run MOCK and the first-join
  cards repeat.
- Purchase prompt, blade meshes, 22 VFX sheets and the no-dev-pass path are
  unchanged from Forge 32.
