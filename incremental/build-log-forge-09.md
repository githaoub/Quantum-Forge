# Build log: the vault split view, the roll ramp, and a guide that stops

Shipped 2026-11-11. The design record is `ADR-045` through `ADR-048` in
`incremental/design-decisions.md`; this is the working log of what changed and
what was measured, in the order it was built.

The pass had four jobs: turn the vault from a grid-with-a-drawer into a split
view with a permanent inspector, widen the canvas so four cards and the
inspector fit, make the forge's roll price climb instead of sitting at one
number, and cut onboarding down to a single first-join card. Every number below
was read out of the running place at 0.7194 canvas scale, then divided back into
design pixels.

## What shipped

| ask | shipped as |
| --- | --- |
| a full-width banner | 1354px, edge to edge, red X sitting on it at x 1304 |
| a scrap pill | `SCRAP` capsule, slate, 2.5px outline, cog badge, 200 x 46 |
| an owned counter | `OWNED` capsule, 170 x 46, prints `17 / 60` and turns warm at the cap |
| filter pills | `ALL` / `EQUIPPED` / `FAVORITES`, 100 x 38 each |
| a sort key | `MULTIPLIER v` / `RARITY v` / `NEWEST`, 210 x 38, cycles on click |
| four columns | 221 x 184 cards, 14px gap, 926px of grid, measured 16 cards in 4 columns |
| live card renders | `VaultThumb` per card, 96 x 96, no `S`/`F` letter plates |
| click inspects | card body opens the inspector, selection moved to `SELECT DUPES` |
| a permanent inspector | 380 x 476 pane: turntable, six stat rows, three-key dock |
| stats on one line | label and value both full-height in the row, measured delta 0.00px |
| favourites | per-uid set in the profile, star on the card, protected from both melts |
| a batch bar | `EQUIP BEST` / `SELECT DUPES` / `MELT SELECTED`, no helper copy |
| a climbing roll price | `floor(base * min(1.05^rolls, 12))`, reset per banner |
| no ghost blade | the mounted blade hides the instant the roll starts |
| a sunken crate stage | 300px dais, three halos, 112px scanner window |
| one onboarding card | 480 x 300, first join only, `guideSeen` latch, no strip |
| a wider canvas | 1440 x 720, side panel 500 -> 520, forge 818 -> 878 |

## Files

New:

- `incremental/build-log-forge-09.md` - this file.

Changed:

- `src/shared/Types.luau` - `ProfileState.favorites`, `forgeRolls`,
  `forgeRollTier`, `guideSeen`; `SyncPayload.invMax`, `favorites`,
  `forgeRolls`, `masteryAll`, `guideSeen`.
- `src/shared/Config.luau` - `InventoryMax = 60`.
- `src/shared/ForgeConfig.luau` - `RollCostGrowth = 1.05`, `RollCostCap = 12`,
  `rollCost(tier, rolls)`, `rollsToCap()`.
- `src/server/DataManager.luau` - `SCHEMA_VERSION = 6`, `favorites` and
  `forgeRolls` defaults, `sanitiseFavorites`, clamps on the roll counter and the
  banner index.
- `src/server/ProgressionService.luau` - inventory ceiling in `forgeRoll`,
  the ramp and the per-banner reset, favorite guards on `salvage` and
  `salvageMany`, `setFavorite`, `markGuideSeen`, `resetGuide`, `forgeCost` in
  the payload, `favorites` / `invMax` / `forgeRolls` / `masteryAll` on the wire.
- `src/server/Main.server.luau` - `favorite`, `guideSeen` and `guideReset`
  actions; `guideReset` refuses outside Studio.
- `src/client/InventoryModal.luau` - rewritten as a split view.
- `src/client/InventoryModel.luau` - `meltable` and `meltValue` take the
  favorite set.
- `src/client/Theme.luau` - `DesignWidth = 1440`.
- `src/client/Layout.luau` - `SIDE_WIDTH = 520`, `STRIP_*` gone.
- `src/client/HudController.luau` - rate strip spans the forge card (878px).
- `src/client/ForgeView.luau` - `BladeViewport` named, the old blade hides at
  roll start, `CrateDais` / halos / `CrateWindow`, `paintCrateStage`,
  `tintCrateStage`.
- `src/client/TutorialController.luau` - one card, no strip, no tracker,
  `guideSeen` on dismissal, no fallback card.
- `src/client/Main.client.luau` - `QF_Dev` gains `favoriteAt`, `vaultFilter`,
  `vaultSort`, `vaultState`, `skipGuide`, and `rolls` on `forgeState`.

## What the vault is made of

```
panel        1354 x 662      (94% x 92% of 1440 x 720)
banner       1354 x 54       x 0..1354
close key      38 x 38       x 1304..1342, y 8
toolbar             y 64
scrap pill    200 x 46
owned pill    170 x 46       at x 208
filter pills  100 x 38       at x 390 / 498 / 606
sort key      210 x 38       right-aligned
grid          926 x 476      at 18,120
card          221 x 184      gap 14
inspector     380 x 476      at 956,120
stage well    356 x 184
stats well    356 x 132      six rows
dock          EQUIP 356 x 36, FAVORITE 172 x 34, MELT 172 x 34
batch bar    1318 x 56       at y 596
```

The inspector and the grid share a top edge (120) and a bottom edge (596). That
is not a coincidence: both sizes subtract `BANNER_H + 10 + TOOLBAR_H + 10 +
BATCH_H + 10` from the panel, so a change to any of the four constants moves
both columns together.

A card render, projected through the thumbnail camera and measured in the
rendered 69 x 69 box:

```
blackstar_glaive | standard     3 parts     x 16..51     y 4..59
```

That is a 35 x 55 silhouette inside 69 x 69 of card, which is the same framing
the drawer's 96px render used, carried over intact. Behind it sit three nested
glow frames (116 / 88 / 62, transparency 0.80 / 0.86 / 0.92) tinted to the blade
tier, and the dock's melt key reads `MELT  +60 SCRAP` on 105px of its 160px
inner width.

## The four defects this pass found

1. **`modalCta` was never assigned.** The guide's CTA button hid the card and
   then had nothing to call, so the guide advanced on the next step's predicate
   firing against live state. That is the exact shape of the "recurring
   mid-game pop-up": a card arriving with no click behind it, twenty minutes
   into a session. The CTA now ends the guide.
2. **`tutorialCompleted` was the only onboarding flag, and the server writes it.**
   Nothing recorded "this player has seen the first join", so the guide had no
   latch that could not be re-opened by the reward path. `guideSeen` is that
   latch, and it is written by the client on dismissal and never read by the
   reward path.
3. **The objective strip owned half the status row.** `RateStrip` was 284px and
   the strip filled the rest; deleting the strip left a pill on a 594px empty
   band. The rate strip now spans the forge card, and `Layout.STRIP_*` is gone
   rather than orphaned.
4. **`UiKit.grid` cell size is design px, so a scale division lies.** The first
   vault measurement reported a 307 x 256 card because `CellSize.Offset` was
   divided by the canvas scale a second time. `AbsoluteSize` is in rendered px
   and does need dividing; layout offsets do not. The card was 221 x 184 all
   along.

Two more, caught before they shipped: `refreshCounts` and `rebuildGrid` were
referenced above their `local function` definitions after the rewrite was
reordered (`rebuild` / `refreshCounts` are now forward-declared), and `Vfx`,
`filterRow` and `inspector` were left as unused locals by the same rewrite.

## The crate stage

Sampled during a real roll through the `QF_Dev` seam:

```
at 0.35s   oldBladeVisible = false   dais = true   crate = true   window = true
dais       300 x 300 design
window     112 x 112 design (81 x 81 rendered)
at 3.6s    bladeVisible = true       dais = false
```

The dais is a sunken 300px circle with three concentric halos at 250 / 190 /
132. UI fills have no radial mode, so the "radial" gradient is three tinted
circles at rising transparency. The halos are painted to the banner colour
before the crate drops and re-tinted to the variant at the reveal, so the colour
of the stage is part of the answer.

The scanner window shows a matte silhouette of a random blade *from the banner's
pool*, never the rolled blade: it teases the tier without pre-empting the only
moment that matters.

## The roll ramp

```
base 4 000 000   rolls 0  -> cost 4 000 000
roll 1           rolls 1  -> cost 4 200 000   (+5.00%)
roll 2           rolls 2  -> cost 4 410 000   (+5.00%)
```

`ceil(ln 12 / ln 1.05) = 51` rolls to the 12x ceiling. The number is owned by
the server and published as `forgeCost`, so the button, the refusal text and the
charge read the same field.

## The guide

```
join 1   cardVisible = true   480 x 300 at 480,210   scrim = true   strip = false
         'WELCOME TO QUANTUM FORGE' 21px, body 16px, cta 'START FORGING' 19px
         counter hidden (one card, nothing to count)
skip     payload guideSeen = true   tutorialCompleted = true
join 2   cardVisible = false   scrim = false   strip = false
```

`TutorialController` went from 1389 to 884 lines. Removed: the objective strip,
the tracker, `affordCount`, `forgeButton`, `fleetButton`, `tabCue`,
`firstWithPrefix`, `forgeReady`, the seven lessons after the welcome, `vented`,
`sweetSeen`, `sawTab`, and the `Layout` / `RuneConfig` / `TechTreeConfig`
requires that only those paths used.

## Build gates

```
selene src/                     0 errors, 0 warnings, 0 parse errors
rojo build -o verify.rbxlx      built
client LogService               no errors
```

## What the ticket did not ask for and got anyway

- **`Config.InventoryMax = 60`.** The vault header needs a denominator, and an
  uncapped grid is a room with no walls. The forge refuses past the ceiling with
  a reason instead of minting a 61st copy.
- **`masteryAll` on the payload.** The inspector shows mastery for whatever
  copy is being looked at, not only the equipped one. Twenty-five numbers on a
  10Hz payload is cheaper than a second fetch.
- **The `EQUIPPED` tag is the accent bar.** A green ribbon across the card top
  is both the strongest signal and the only place on a 221px card where the word
  fits without stealing a row from the name.
- **`guideReset`, Studio only.** QA cannot replay a first join without wiping a
  profile otherwise, and Studio's mock profile persists between playtests.
- **The rate strip spans the card.** It was 284px beside the guide's strip; with
  the strip gone, a full-width band is the only shape that does not read as a
  missing panel.

## Still open

- Store listings still cannot be created: the API key lacks `game-pass:write` and
  `developer-product:write`, so all ids are `0` and the rows read `SOON`.
- All 26 blade meshes return `User is not authorized to access Asset` in this
  Studio session; every viewport renders the procedural fallback, thumbnails
  included.
- 22 VFX sheets are generated and unuploaded:
  `python scripts/upload_assets.py --vfx --creator user:1416845247`.
- No `stylua` / `wally` / `luau-lsp` in this environment; `selene` is the only
  static pass.
- `screen_capture` returns null, so every visual claim here is a measurement.
- Studio DataStore is unavailable, so the playtest profile is a mock that
  persists between sessions; progress is not real progress.
- The vault has not been opened on a phone. Four columns at 926px design is
  arithmetic, not a hardware test.
- The 60-copy ceiling is enforced in code and published as `invMax`; a sixty-one
  card inventory was not built to watch it refuse.
- Aether supply still does not scale with the fleet, which leaves the top two
  drone rungs unreachable. Recorded in `game-design-math.md` section 5.5.
