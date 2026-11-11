---
type: build-log
status: shipped
updated: 2026-11-11
aliases:
  - forge-13
tags:
  - build-log
  - ui
  - foundry
---

# Forge 13 - The four sections

One pass over CRATES, FLEET, RUNES and STORE on the Foundry Instrument system,
plus the last two forge corrections: the strike key's payout label and a solid
heat fill.

## What changed

| Surface | Before | After |
| --- | --- | --- |
| CRATES | Five equal odds chips, two equal roll keys, 46px header | 64px banner, one stacked odds bar with a five-column legend, quiet `ROLL` (40%) + dominant `ROLL x10` (60%) |
| FLEET | 150px full-width hero; name plate and keys on the stage; 3-letter rung codes | 208px two-column hero (42% drone stage), three figures and BUILD keys on the right, full rung names |
| RUNES | 178px mastery card in a 470px column | 470px blade bay: blade, rank, mastery, three 84px sockets, live socketed-bonus grid, shard wallet |
| STORE | 14px group captions | `GAME PASSES / 5` and `BOOSTS & UTILITY / 4` at 15px |
| FORGE | Strike sublabel `N /s`; blue-to-red heat fill | `+N SM`; solid state colour |

## Measurements

- Heat penalty, live A/B on the same build: 99.4% heat paid `2,911.6`, 6.1% paid
  `5,823.2`. Exactly 0.5x, no overdrive or boost on either read.
- Drone stage: viewport 220 x 138 screen px inside the 42% column. The uploaded
  hull's MeshParts are not authorized, so the primitive path is forced.
- Crates odds bar: 55.14 / 29.87 / 13.83 / 2.41 / 0.35, drawn common to rare.
- `selene src/`: 0 errors, 0 warnings, 0 parse errors. `rojo build` writes
  `verify.rbxlx`.

## New dev seam

`QF_Dev` gained `strike`, `vent` and `stats` so a heat run can be driven without
pointer synthesis. `forgeState` now returns `heat` instead of the deleted
`locked` field.

## Open

- Store listings still read `SOON`: the API key lacks `game-pass:write` and
  `developer-product:write`.
- The sculpted drone mesh needs publishing to this place; flip
  `DRONE_MESH_READY` when it is.
- Roll, craft, socket and purchase keys are code-verified through the seam, not
  clicked.
