---
type: build-log
status: shipped in Studio, not yet published
updated: 2026-11-12
aliases:
  - forge-28
tags:
  - build-log
  - crates
  - economy
  - ui
---

# Forge 28 - Keep the batch moving, and stop the faucets apologising

Two unrelated complaints landed in the same pass. The crate ceremony made the
player press CLAIM once per copy, which is up to ten presses of a key whose only
job was to read the next name. And the two appointment loops paid less than the
loop that runs by itself: the daily track paid 5 to 50 Aether and the missions
paid 45 / 165 / 1 100, while one Void cache paid 7 000. The Fleet tab also read
`BUILD 1 · 1.2K`, which never said what the 1.2K was.

## The claim-all key

A batch result now carries a second key beside the main one:

- It is a quiet plate, 158x50 design px, to the right of the 260px claim key.
- The label carries the count: `CLAIM ALL 3`, `CLAIM ALL 10`.
- It is hidden on a single copy, because there is nothing to skip.
- It appears with the claim key after the 0.22 s result lock, and hides while a
  claim is swapping so a held mouse cannot double-fire it.
- Pressing it marks every remaining chip on the rail and calls the existing
  `claimOut`, so the exit is the same white flash, screen shake and
  `Sfx.claimAll` the last claim always used.

The copies are granted when the server answer arrives; the queue is the reading
order, not the payout. The key changes how long the player looks at names, never
what they get.

## The blade turns

`BladePreview.mount` already supported an idle turntable rate; the crate passed
`spin = 0` to hold the pose. It now passes `1.1`, a full turn every 5.7 s. The
forge hero has always spun, so holding the crate blade still made the reveal read
as a model swap next to it.

## The daily track

| Day | Aether | Scrap | Star-Matter | Cores |
| --- | --- | --- | --- | --- |
| 1 | 10 000 | 250 | - | - |
| 2 | 25 000 | 500 | - | - |
| 3 | 60 000 | 750 | - | - |
| 4 | 150 000 | 1 000 | 250 000 | - |
| 5 | 350 000 | 1 500 | 1 000 000 | - |
| 6 | 800 000 | 2 000 | 5 000 000 | - |
| 7 | 2 500 000 | 3 000 | 25 000 000 | 3 |

A week is 3 895 000 Aether. Day one is already a Debris Sweep, and day seven is
64% of the week. Scrap stays at 250 to 3 000 because reroll costs are 12 to 52;
a daily should not delete that sink. The last card still carries the Cores,
which are the only part of the week that survives an ascension.

## The expeditions

| Mission | Squad | Time | Aether |
| --- | --- | --- | --- |
| Debris Sweep | 5 | 5 min | 15 000 |
| Deep Salvage | 15 | 15 min | 200 000 |
| Void Run | 30 | 60 min | 4 000 000 |

Those are base numbers. The dispatch snapshot still multiplies by the equipped
blade and the account multiplier, which is why a live sweep on a 5x account
showed `+75K AETHER`. The missions are sized against the drone ladder: a sweep
is a Quantum Vector, a void run is a Celestial Swarm. The salvage rack keeps its
own job as the steady faucet and the sigil source instead of being the better
mission.

## The unit on the price

`BUILD 1 · 7 AETHER` and `BUILD 10 · 177 AETHER`. The locked state still reads
`LOCKED AT 32`, because that number is a drone count, not a price. The mission
rows and the cache hints moved to `NumberUtil.compact`, so a payout reads
`+200K AETHER` and `+4M AETHER` rather than `+200.00K`.

`NumberUtil.compact` is a display helper only: it takes the abbreviated string
and drops trailing zeros in the decimal part (`10.00K` becomes `10K`, `1.50K`
becomes `1.5K`, `1.24K` is untouched). Live counters keep the two decimals so a
rising number does not change width every tick.

## Studio evidence

- A three-crate preview result showed `CLAIM ALL 3` at 709,456 (114x36 at the
  0.72 canvas scale). Pressing it marked the queue and closed the ceremony.
- A ten-crate preview showed `CLAIM ALL 10`; the same press closed it. A
  single-copy result showed no key.
- The result blade's `LookVector` moved from `(-0.40, 0.08, 0.91)` to `(0.39,
  0.08, 0.92)` in 0.7 s, which is the 1.1 rad/s turntable.
- The first daily claim granted exactly 10 000 Aether (fleet read 0 before, 10 000
  after).
- Ten scrap drones were bought for 173 Aether, and the keys repainted to
  `BUILD 1 · 41 AETHER` / `BUILD 10 · 1.04K AETHER`.
- A Debris Sweep dispatched with 10 drones in the fleet showed `+75K AETHER` and
  a 4:52 countdown, which is the snapshotted 15 000 x 5.
- Every daily card and every repainted Fleet label reported `TextFits = true`
  after layout settled.
- `selene src` is 0/0/0 and `rojo build default.project.json` succeeds.

## What is not verified

- **Touch and gamepad.** The new key was only pressed with a mouse on a desktop
  viewport.
- **A real ten-pull.** The walk was the `crateStage 10` preview, which uses the
  same queue and the same claim path but does not charge or write the vault.
- **The expedition settle.** The payout snapshot was read on the flight line;
  the five minute wait and the offline settle were not played.
- **A published place.** The live profile is MOCK because API services are off,
  so the new daily values have not been written to a DataStore.
