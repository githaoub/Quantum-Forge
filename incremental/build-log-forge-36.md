# Forge 36: the store stops selling the grind, and tech becomes a tree

Date: 2026-11-13

## The complaint

The honest monetization review found four problems the store could not defend:
a false `NO CURRENCY PACKS` badge, a 500K Aether Starter Pack that skipped the
first three drone rungs, an Overdrive stack that multiplied without a ceiling,
and an Express Salvage that sold back a timer. The same pass had two visual
complaints. The tech page was three lanes with headers and spines, which read as
a template rather than an upgrade tree. Several screens still used coloured
rules as decoration, and those rules made the UI look generated.

## Monetization

### Starter Forge Pack

The pack no longer grants currency. It gives twenty minutes of 2x income, and
the first pack also adds a permanent 5% income bonus. The bonus is stored as
`passes.starterForge`, so a repeat purchase cannot stack a second passive
multiplier. Every later pack only extends the 2x clock.

### Instant Overdrive

Stacking stays. The curve does not. The first charge is 2x, and every extra
charge adds 1x instead of multiplying:

```
overdriveMult(stacks) = 2 + (stacks - 1)
```

Ten charges read x11, not x59,049. The clock still resets to one hour on every
charge, so the multiplier can climb while the timer cannot. With the welcome 2x
and ten charges the live product is x22.

### Express Salvage

The timer skip is gone. One purchase now shortens every future expedition by
25%, stored as `passes.expressSalvage`. A second receipt is refused with
`Expedition charter is already active` instead of charging twice. The computed
clocks are 300 to 225 seconds, 900 to 675, and 3600 to 2700. Mission cards round
a shortened clock up (225 reads 4M), and the in-flight bar reads the clock the
mission was dispatched with (`expTotal`), so buying the charter mid-flight
cannot retime a mission already away.

### VIP

VIP keeps its bundle and gains one cosmetic: a gold strike trail in `ForgeView`
when `payload.vip` is true. The store copy names the trail.

### Store claims

`NO CURRENCY PACKS` is gone. The subtitle now says
`Passes are permanent. Boosts run on a clock.` The pass formerly titled
`2x Star-Matter` is titled `2x Income` in the game, with the blurb
`Doubles all forge income, forever.` Eternal Forge reads
`+25% to all forge income, forever.` Product cards state the clock, the stack
rule and the permanent expedition cut. No card copy names a currency.

The Marketplace listing still uses its original `2x Star-Matter` name because
`scripts/create_store_items.py` uses names as its idempotency key. Renaming the
script entry before the live listing is renamed would create a duplicate pass.
The in-game card is what changed.

## Tech tree

The page is now one gated graph, not three lanes.

- Eight nodes and a root tile. `start_might` opens `crit_forge` at level 3,
  `thermal_calibration` at level 2, and `drone_lattice` at level 2.
  `crit_forge` opens `auto_click` at level 2, `thermal_calibration` opens
  `vent_efficiency` at level 2, `drone_lattice` opens `offline_core` at level 2,
  and `offline_core` opens `head_start` at level 2.
- `TechTreeConfig` gained `requires`, `requiresLevel`, `requirement` and
  `available`. `compute` clamps every level to `maxLevel`.
- Tiles are 140 x 92 design px. The root is an 88px circle. Long copy, the
  price and the buy key live in a 300px inspector on the right.
- Connectors are neutral ink. A link is lit when the path is open, meaning the
  child is bought or its gate is met and the next level is on sale. Links past
  a closed gate stay dim. There are no lane spines, branch stripes or accent
  ticks.
- A gated tile shows a lock mark. The inspector prints the exact gate, for
  example `REQUIRES CRITICAL FORGE LV 2`, and the buy key reads `LOCKED`.
- `ProgressionService.buyTech` returns `Requires <parent> Lv<n>` when the gate
  is closed. `DataManager.sanitiseTech` drops unknown ids and clamps levels.
- `TechTreeView.select(id)` and `TechTreeView.preview(levels, qc)` are the
  Studio seams. Preview paints a copy of the payload and leaves the stored
  payload alone, so the next sync or selection reads the real profile.
- `ShopView.preview(owned)` is the matching seam for the store's bought state.

## Accent sweep

- Codex tabs use one neutral selected fill (`woodLight`) instead of six accent
  fills. The six tab accents are gone from `TABS`.
- The 4px rarity bar across every codex cell is gone, in both the blade grid and
  the quality grid. Rarity still reads in the caption and the thumbnail.
- `UiKit.tab` uses a white underline, not the tab's accent. The rail's active
  bar is white, not the section accent.
- Bars that carry a value stay: heat, next-goal progress, pity, and the variant
  bars in the vault and trade grids. A bar that only decorates a card does not.
- No connector or rule uses a gradient.

## Evidence

Studio, 1212 x 576 game area, canvas 1686 x 720 at `UIScale` 0.719.

Store, after `shopPreview({ starterForge = true, expressSalvage = true,
x2StarMatter = true })`:

- Masthead `QUANTUM STORE`, subtitle
  `Passes are permanent. Boosts run on a clock.` No trust chip.
- Pass titles `VIP`, `2x Income`, `Fast Forge`, `Auto-Vent AI`, `Eternal Forge`.
  The `2x Income` blurb is `Doubles all forge income, forever.`
- Summary `1 / 5 OWNED` with only a pass owned. The two bought products paint
  a dark `BOUGHT` plate; the Starter fact reads
  `20 MIN OF 2X · +5% OWNED`. Express Salvage keeps
  `PERMANENT · 25% SHORTER` in emerald.
- Codex: six tabs, active `BLADES` sampled `(46, 54, 68)` against inactive
  `(18, 22, 29)`. The modal held 50 cells; the 4px bar is gone from both cell
  builders.

Tech:

- Gated `auto_click` at `start_might = 3, crit_forge = 1`:
  `LEVEL 0 / 10`, `NOW NONE`, `NEXT +0.5 strikes/s`,
  `REQUIRES CRITICAL FORGE LV 2`, buy key `LOCKED`, tree `4 / 59`. The
  `crit_forge` to `auto_click` link was 0.20 opacity; the four open links were
  0.45.
- Affordable `auto_click` at `start_might = 3, crit_forge = 2`, 711.54K cores:
  buy key `BUY LEVEL`, no gate line, tree `5 / 59`. The `crit_forge` to
  `auto_click` link became 0.45.
- Mastered `start_might`: `LEVEL 10 / 10`, `NOW +250% strike yield`,
  `NEXT MASTERED`, buy key `MASTERED`, tree `59 / 59`.
- Mastered `crit_forge`: `LEVEL 5 / 5`, `NOW +20% crit`, `NEXT MASTERED`,
  buy key `MASTERED`.
- All eight node labels reported `TextFits = true`; inspector lines fit at
  13 design px. `TechCanvas` measured 871.8 x 378.4 screen px and the inspector
  215.8 x 378.4.
- `MonetizationConfig.overdriveMult` returned 1, 2, 3 and 11 for 0, 1, 2 and
  10 charges. `StarterPermanentIncome` was 0.05 and `ExpeditionTimeScale` 0.75.
- Fleet, without the charter: `5 DRONES · 5M`, `15 DRONES · 15M` and
  `30 DRONES · 1H`, all `TextFits = true`. The shortened quotes (4M, 12M, 45M)
  and the dispatched-clock bar are computed and code-read; the charter itself
  was not purchased in this session.

`selene src`: 0 errors, 0 warnings, 0 parse errors.
`rojo build default.project.json -o verify.rbxlx`: success.
Saved to the real place as version 345. Not published.

## Open

- DataStore writes still return 401 here and the profile runs MOCK, so no grant
  in this pass has survived a rejoin on this machine.
- The purchase prompt does not render in this Studio session. No Starter,
  Overdrive, Express or VIP transaction was tested end to end.
- Ten live Overdrive charges were not purchased. The helper and the payload path
  were verified; the purchase path was not.
- The Marketplace listing is still named `2x Star-Matter`. The in-game card is
  `2x Income`. The live listing has to be renamed in the Creator Dashboard if
  the purchase prompt must match.
- The gated and affordable tech states were painted through the Studio preview
  seam on a maxed seeded profile. A natural low-level account has not walked the
  tree.
- No human visual pass on the new store, tech or codex screens yet. The
  screenshots exist; whether the density and the lock marks feel right on a
  real display is still a person's call.
- A true clean-account first join, a two-client trade, the touch and gamepad
  paths, the blade meshes, the 22 VFX sheets, the 420px crit disc, the crate
  sound kit and the `ContentId ... Asset type does not match` console errors
  remain as before.
