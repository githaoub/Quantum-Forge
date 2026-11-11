# Forge 11 - the batch mode, the stage wash, and two orbit surfaces

Shipped 2026-11-11. The design record is `ADR-053` through `ADR-055` in
`design-decisions.md`; the measured tables are below.

The ticket was a UI/UX refinement pass: tighten the vault's batch strip, make
selection a mode instead of a hidden box, replace the flat circles behind every
3D render with a real gradient, and give the forge and the inspector the same
drag-to-orbit the fleet hero already had.

Everything below was checked against a live playtest on place `102663811434617`.
This is the first pass where pointer input was synthesised (`user_mouse_input`)
rather than driven through the `QF_Dev` seam, so the click paths are measured,
not inferred.

---

## 1. The batch strip

The bar was 46px tall with `EQUIP BEST` and `MELT MULTIPLE` touching, the
selection keys pinned to the right edge, and a readout growing into the middle.
It is now four fixed slots, 40px tall, 10px apart:

| slot | x | width | face |
| --- | --- | --- | --- |
| `EQUIP BEST` | 0 | 190 | cyan plate, always |
| `MELT MULTIPLE` | 200 | 208 | house red; slate `CANCEL` while armed |
| `SELECT DUPES` | 418 | 150 | slate; text dims to `locked` when there is nothing to select |
| `CLEAR` | 578 | 88 | slate; text follows the same rule |

Measured at canvas scale 0.8: the strip is `32` tall (40 design), the melt key
`166.4 x 32` (208 x 40), the tick box `17.6` (22), and the inspector grab rect
`278.4 x 140.8` (348 x 176). At 0.62 they read `24.8`, `129.0 x 24.8`, `13.6`
and `215.8 x 109.1` - the same design numbers through the canvas `UIScale`, with
no text clipped at either size.

The melt action is not one of the four. A fifth plate appears at the right end of
the strip, 240px wide, only while something is ticked: `MELT 3  +384`. A mode
switch and a destructive confirm do not share a key.

## 2. Selection as a mode

`MELT MULTIPLE` arms the mode. While it is armed:

- every card that owns a meltable copy grows the tick box; every other card has
  none, and the box is not built at all for a group with nothing to melt;
- a click **anywhere on the card tray** toggles that copy. The tick box is still
  there, but it is a badge now, not the only hit target;
- a ticked card takes the same gold `4px` border the inspected card takes, so the
  queue is legible from across the grid;
- `CANCEL` disarms and clears the ticks, and closing the vault does the same.

The hit layer is one full-size `TextButton` (`VaultCardHit`, 221 x 184) above the
labels and below the star and the box, so the star and the box keep their own
jobs.

Live, with a real pointer:

| action | result |
| --- | --- |
| click card 2 centre, mode off | `inspected` moves `forge_eternal\|tempered` -> `forge_eternal\|standard` |
| arm the mode, click card 3 centre | `selected = 1`, confirm reads `MELT 1  +264`, `inspected` does **not** move |
| click the same card again | `selected = 0`, confirm hides, readout returns |
| `CANCEL` with two ticked | `selected = 0`, key back to `MELT MULTIPLE`, fill `161,30,30` |

`SELECT DUPES` arms the mode first, so pressing it from the idle strip opens the
mode and fills it in one gesture. In this playtest profile every group held a
single copy, so it selected nothing and its label stayed `locked`; that is the
disabled state doing its job, not a dead key.

## 3. The stage wash

The old backdrop was four nested rounded frames per pool - solid circles at
rising transparency. They step. A `UIGradient` interpolates on one axis only, so
there is no radial fill in the renderer, but there is a radial *look*:

```
base     one opaque ramp, deep(cool) -> deep(warm), rotation 90
bloom    two crossed bands, each transparent at both ends
diagonal two accent bands at 42 and 138 degrees
shaft    a narrow accent band raked at 118 degrees
vignette void at the floor, fading up
settle   cards only: the plate colour, opaque at the bottom edge
```

Where the bands overlap the colours add; where they run out, the base shows. No
step anywhere, and the corners fall off on their own.

Three callers, one module (`StageBackdrop`):

| stage | warm | cool | accent |
| --- | --- | --- | --- |
| forge | `Theme.tierBackdrop(tier).warm` | `cool` | warm |
| fleet hero | `aether` | `quantum` | warm |
| vault card | rarity colour | rarity colour | variant colour |
| vault inspector | rarity colour | rarity colour | variant colour |

Cards are `tile = true`: two bands instead of four, no shaft, a lighter floor
(`depth = 0.5` instead of the module's `0.68`) and a wider vignette, because a
136px art well reads a narrowed band as a stripe. The wash stops at 136px and
settles into the card plate over 46px, so the name and the stat row keep a flat
surface.

Re-tint is in place: `setColors(warm, cool, accent?)` rewrites four
`ColorSequence`s and three `BackgroundColor3`s. Verified by opening two cards:
the inspector's base ramp moved from `65,131,103` (tier 1 green) to
`107,73,132` (Nullbreaker's violet) without a remount.

The three viewports are now transparent (`BackgroundTransparency = 1`) where the
two smaller ones used to be opaque black boxes; the wash is what shows behind
the render.

## 4. Orbit on the anvil and in the inspector

`ViewportOrbitController` gained one option and one field:

- `Options.surface: GuiObject` - the control that receives the press. A
  `ViewportFrame` never sees a mouse button on this build, and a viewport inside
  a modal is covered by the scrim's hit layer, which eats the press first.
- `Handle.dragTravel: number` - pixels travelled this drag, so a caller can tell
  a tap from an orbit.

The fleet hero keeps the global path (no surface, pressed anywhere inside the
frame). The forge passes its `StrikeButton`; the vault inspector gets a
transparent `VaultStageGrab` button over the render, above the dimmer.

Measured with synthesised mouse input:

| gesture | camera before | camera after |
| --- | --- | --- |
| forge, LMB drag 118px right | `5.72, 2.07, -14.15` | `12.76, 3.92, -4.02` |
| inspector, LMB drag 79px right | `5.05, 2.28, -12.77` | `10.36, 1.93, -7.91` |
| inspector, RMB drag 91px left | `10.52, 1.90, -7.64` | `4.20, 2.82, -13.00` |

The strike still fires on the press that begins an orbit drag - six clicks on the
anvil drove core heat to `4%` and the cadence readout to `HOT 3.0/s`. That is the
trade: firing on press keeps the core loop instant, and a drag costs one strike.
Firing on release would gate every strike in the game behind a click.

## 5. Verification

- `selene src/` - 0 errors, 0 warnings, 0 parse errors.
- `rojo build -o verify.rbxlx` - clean.
- Client console clean after the playtest.
- Every claim above is from the live session: geometry from
  `AbsolutePosition` / `AbsoluteSize`, camera moves from `CurrentCamera.CFrame`,
  selection from `InventoryModal.batchState`, clicks from `user_mouse_input`.
- Six captures read by eye (`ScreenCapture_7` through `_14`), including the
  before/after of the wash.

## Traps worth keeping

| Trap | Symptom | Fix |
| --- | --- | --- |
| A full-screen `TextButton` dimmer behind a modal | Every click inside the panel arrives with `processed = true`, so a viewport under it can never start a drag | Press from a `GuiButton` over the render (`VaultStageGrab`), not from the global input path |
| Complementary bloom colours at equal weight | Tier green over variant orange composites to olive; every card looked the same | The base carries the tier, the accent bands carry the variant, and `warm == cool` on the cards |
| A narrowed band on a 136px card | The bloom reads as a horizontal stripe | `tile` keeps the wide ramp and drops the diagonals |
| `LayoutOrder` is not an index | `openDetailAt(card.LayoutOrder)` is correct only because `buildCard` assigns it from the view index | The seam takes a visible-list index; the card stores the same number |
