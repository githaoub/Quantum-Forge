---
type: build-log
status: shipped
updated: 2026-11-11
aliases:
  - forge-14
tags:
  - build-log
  - crates
  - ui
  - reveal
---

# Forge 14 - The breach

The crates page already looked like a Foundry section. The roll still felt like a
form submission: one shatter, then a flat panel swapped the crate's facts for the
result. A ten-pull named its best copy and hid the other nine behind `x10`.
Pity printed the finish line instead of the distance to it.

This pass rebuilt the reveal as a staged ceremony and made the two visible rules
match what the server pays. The page is the same section; the peak is new.

## What changed

| Surface | Before | After |
| --- | --- | --- |
| CRATES stage | Flat black viewport, crate or blade, result text in a nested card | Full-bleed tier wash, dais, floor rule, stage watermark, info scrim, beam, rays on rank 3+ |
| Roll | Drop, six ticks, shatter, label swap | Drop, six-beat rattle, charge bar, anticipation ring, held beat, crack flash, fanfare, viewport punch |
| Ten-pull | `BEST OF 10` caption over one copy | Ribbon of every copy, 0.06 s stagger, variant edge + rarity bar, best cell marked |
| Result info | `JUST FORGED`, name, one line, scan rule | Kicker, variant and rarity in their own colours, name, condition, power, affix, auto-equipped, pity, `NEW BLADE` / `NEW VARIANT` |
| Exit | Rolling again or switching pools | `BACK TO POOL` returns to the crate |
| Pity | `PITY 11 ROLLS` (the threshold) | `PITY 9 / 11`, one tick per roll, gold goal tick, `GUARANTEE IN 2` |
| Unlock clock | "LIFETIME" in the rail and note | "RUN", with `135.22M / 600.00M` progress on the locked rows |
| Quantum colour | Gold, clashing with the mint blade rarity | Mint, from `BladeRegistry.RARITY_INFO` |
| FORGE band | Gauge drew a fixed 65-85 while the server paid the tech band | Gauge repaints `bandMin` / `bandMax` every sync; full-height 90% lean tick |
| Thermal Calibration | Max band reached 95, but the lean point starts at 90 | `sweetSpotMax` clamps to `Config.PenaltyFrom` (90) |

## Measurements

- Charge phase at 0.9 s: bar visible, fill `0.63`, caption `BREACHING`, rarity
  tag hidden.
- Ten-pull, live: 10 copies returned, ribbon showed all 10, best cell `JADE FANG`
  marked, `POWER 4.18K`, `AUTO-EQUIPPED`, `PITY 8 / 11`.
- Top-rarity preview, `cratePreview quanta_verge`: Prismatic/Quantum, rays, ring,
  `NEW BLADE`; power row hidden because the preview carries no power.
- Dismiss: `crateDismiss` returned result hidden, rest visible, tag hidden, one
  WorldModel mounted.
- Heat: 99% showed `OVERHOT YIELD x0.5`; a vent to 43% showed `BAND 55-90` with
  the 90 tick on the gauge.
- Layout check at the test window: `BackToPool` 285-299, `PullRibbon` 309-333,
  so the exit and the ribbon do not overlap.
- `selene src/`: 0 errors, 0 warnings, 0 parse errors. `rojo build` writes
  `verify.rbxlx`.

## Server contract

`forged` now carries `results` (every copy in roll order), `power`, `equipped`,
`newBlade` and `newVariant`. The top-level fields stay the best copy so older
callers, the anvil reveal and the notifications do not change. Discovery flags
are read before `markCodex`, per copy, so a ten-pull can contain two firsts.

## New dev seam

`QF_Dev` gained `cratePreview <bladeId>` and `crateDismiss`. The preview forces a
Prismatic reveal so the top-rarity treatment can be checked without waiting for
a 0.35% pull; the dismiss calls the same function as `BACK TO POOL`.

## Open

- The new roll ticks and the result fanfare were not heard in this pass.
- The ten-pull stagger was captured as a completed strip, not mid-sequence.
- `BACK TO POOL` was driven through `crateDismiss`, not a pointer.
- The natural 0.35% Quantum path was not observed; the preview is forced.
- The remaining research actions are still open: `NEXT` line, offline-card
  ceremony, rail unlock dot, store demotion.

See ADR-083 for the decision record and the full honesty table.
