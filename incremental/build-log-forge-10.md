# Build log: progress pricing, an honest melt count, and a clickable sheet

Shipped 2026-11-11. The design record is `ADR-049` through `ADR-052` in
`incremental/design-decisions.md`; this is the working log of what changed and
what was measured, in the order it was built.

The pass had five jobs: make every Star-Matter sink scale with the account
instead of sitting on a fixed table, make the batch melt count equal the number
of copies the player ticked, put the melt key next to `EQUIP BEST` in the house
red, make the settings rows the size of a row rather than the size of a stamp,
and rebuild the two header icons whose teeth were rotated onto the rim instead
of off it. Every number below was read out of the running place at 0.7194 canvas
scale, then divided back into design pixels.

## What shipped

| ask | shipped as |
| --- | --- |
| sinks scale with progress | `Config.progressScale(lifetime) = min((lifetime / 1e9) ^ 0.5, 1e4)` |
| forge rolls scale | `rollCost(tier, rolls, scale)`, server passes `progressScale` |
| drone prices scale | `cost` / `bulkCost` take `scale`, server passes `sqrt(progressScale)` |
| no gap under `EQUIP BEST` | `EQUIP BEST` at x 0, `MELT MULTIPLE` at x 190, both 46 tall |
| house red melt key | `redDeep` plate, `red` stroke, white face |
| a tick you can find | the checkbox is on every card that can melt, selected or not |
| the count the player counted | a ticked card contributes its own badge: `x3` or `2/3` |
| no silent drop | a group with nothing meltable has no checkbox at all |
| a readable sheet | each setting is a 402 x 54 row; the row is the switch |
| a gear that reads | six radial teeth, rotated `angle + 90`, 30px canvas |
| a backpack that reads | 28px canvas, 18 x 15 body, 2px outline on every plate |
| shorter batch bar | 56 -> 46 design px, grid gains 10px |

## Files

New:

- `incremental/build-log-forge-10.md` - this file.

Changed:

- `src/shared/Config.luau` - `ProgressReference = 1e9`,
  `ProgressExponent = 0.5`, `ProgressCap = 1e4`, `progressScale(lifetime)`.
- `src/shared/ForgeConfig.luau` - `rollCost(tier, rolls, scale?)`.
- `src/shared/DroneRegistry.luau` - `cost(tier, owned, scale?)`,
  `bulkCost(tier, owned, count, scale?)`.
- `src/server/ProgressionService.luau` - `progressScale`, `dronePriceScale`,
  scaled `forgeRoll`, `buyDrones`, `droneCostFor`, `buildPayload` fleet and
  `forgeCost`.
- `src/client/InventoryModal.luau` - `groupMeltable`, always-on check boxes,
  `CountFace` badges that print `n/m`, `MELT MULTIPLE`, 46px bar, right-pinned
  `CLEAR` / `SELECT DUPES`.
- `src/client/Modals.luau` - settings rows are full-width buttons with an ON /
  OFF chip; no 108px plaque.
- `src/client/SidePanel.luau` - `gearIcon` tooth rotation, 30px gear canvas,
  28px backpack canvas, icon canvas named.

## Measurements

### Pricing

`forgeCost` read `2 205 000 000 000` at tier 5 (`base 2e8`), `rolls = 2`
(`1.1025x`), which is `2e8 * 1.1025 * 1e4` exactly: the account multiplier is
live, applied last, and sitting on its cap.

Every drone rung priced at exactly `100x` its unscaled value
(`sqrt(1e4)`), read from the sync payload and divided by
`DroneRegistry.cost(tier, owned)`:

| rung | owned | payload cost | raw cost | ratio |
| --- | --- | --- | --- | --- |
| scrap | 91 | 3.670e8 | 3.670e6 | 100.000 |
| molten | 122 | 3.124e12 | 3.124e10 | 100.000 |
| quantum | 70 | 6.455e10 | 6.455e8 | 100.000 |
| celestial | 30 | 4.617e9 | 4.617e7 | 100.000 |
| cosmic | 0 | 1.200e9 | 1.200e7 | 100.000 |

The two sides are deliberately different exponents: Star-Matter scales linearly
because the sink that eats it is the forge, and Aether scales by its square root
because Aether supply does not scale at all. The drone ladder is the brake on
the printer, so it is priced above the flat vent payout on purpose.

### The melt count

Two live melts, both through the same functions the buttons call:

| selection | picked uids | before | after | Scrap |
| --- | --- | --- | --- | --- |
| two `x3` groups and nothing else | 5 | 26 | 21 | +600 |
| four `x3` groups, one copy favorited | 11 | 31 | 20 | +1320 |

The second run is the bug from the ticket. Before the fix the bar printed the
number of *cards* the player ticked and the dialog printed the number of *uids*
the server would take, so a protected copy made the two disagree. Now the ticked
card carries the number it contributes: the favourited group's badge read `2/3`
while its three siblings read `x3`, and the bar read `11 TO MELT`.

A card with nothing meltable has no checkbox. With 18 copies and 18 groups, the
grid rendered 18 check frames and 17 live boxes: the equipped single copy had
none.

### The batch bar

Bar 1318 x 46 design, measured 948 x 33 rendered:

| key | x | width | state |
| --- | --- | --- | --- |
| `EQUIP BEST` | 0 | 190 | always |
| `MELT MULTIPLE` | 190 | 220 | face becomes `MELT 12 +1440` |
| readout | 418 | 642 | `12 TO MELT  ·  +1440 SCRAP` |
| `CLEAR` | 1068 | 86 | hidden until something is ticked |
| `SELECT DUPES` | 1162 | 156 | hidden until a dupe exists |

The gap between `EQUIP BEST` and the melt key is 0. `CLEAR` and `SELECT DUPES`
are pinned to the right edge, `SELECT DUPES` furthest right, so the readout grows
into the middle and nothing jumps when `CLEAR` appears.

### The settings sheet

Three rows at x 34, 289 wide and 39 tall rendered (402 x 54 design), 58 design
px apart, each one a `TextButton` carrying its own title, note and 64 x 28
`ON` / `OFF` chip. A hit test 40px into the label end of the first row returns
`Setting_sfx` as the top interactive object, where the old build returned the
row's inert background because the only target was a 108 x 38 plaque at the far
right.

The write path was exercised end to end: `setting { sfx = false }` -> payload
`sfx = false` -> reopening the sheet printed `sfx=OFF`, then the same call with
`true` restored `sfx=ON`.

### The header icons

| key | key size | canvas | ring | hole | tooth |
| --- | --- | --- | --- | --- | --- |
| gear | 36 x 34 | 30 | 19 | 7 | 4 x 9, rotation `angle + 90` |
| backpack | 40 x 34 | 28 | - | - | body 18 x 15, flap, pocket, straps |

The old gear rotated each tooth by the radial angle alone, which put every
tooth's long axis across the rim instead of pointing out of it: eight 3 x 7 bars
laid tangent to a 16px disc, which is what "broken icons" looked like. The fix
is the 90 degrees, plus a canvas large enough that a 2px outline does not eat the
whole tooth.

## What was actually wrong

- **The melt count.** `InventoryModel.meltable` drops the equipped copy, every
  favorite and the last copy in the vault, and the bar printed the uids that
  survived. Those rules are right; the surface was lying. The fix is on the
  card, not in the rule: a card whose group holds a protected copy prints
  `2/3`, and a group with nothing left prints no checkbox.
- **The settings sheet.** The sheet was never dead. The hit target was a
  108 x 38 plaque at the right edge of a 402px row, which reads as a value, not
  a control. Making the whole row the button is the fix; the toggle face and the
  server round trip were already correct.
- **The icons.** Tooth rotation, not assets. The backpack's stems were parented
  to the icon canvas while the rest of the plates were built by a helper; both
  are on the canvas now and the silhouette has one parent.

## Open

- The Aether ladder is now the binding constraint at high lifetime: a vent still
  pays `0.08` per heat while the cheapest Cosmic costs `1.2e9`. That is the
  intended brake, but it is a balance number, not a settled one. The knobs are
  `Config.ProgressExponent` and `ProgressionService.dronePriceScale`.
- The roll ramp ceiling (`12x`) and the account ceiling (`1e4`) multiply to
  `120 000x` base at the extreme. No profile has been walked to that wall.
- The Scrap reroll stays priced by tier (`12 + 10 * (tier - 1)`), because Scrap
  income is itself priced by tier. It is not a Star-Matter sink and does not take
  the progress multiplier.
