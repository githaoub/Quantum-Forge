---
type: build-log
status: shipped in Studio, not yet published
updated: 2026-11-12
aliases:
  - forge-25
tags:
  - build-log
  - store
  - design
  - monetization
---

# Forge 25 - The shelf becomes a catalog

The first pass made the store taller without making it a store: every offer was
the same plate, the owned state was the same solid green as a live price, the two
columns ended unevenly, and a yellow pill sat on the buy button at the fold. This
pass gives the section a hierarchy and a brand, and makes the paid clock visible.

## What changed

| Surface | Before | After |
| --- | --- | --- |
| Store identity | emerald tab and plaque | gold tab and plaque |
| Pass accent | emerald | gold (permanent) |
| Boost accent | aether | aether (timed), unchanged |
| Action plate | emerald, also used for owned | emerald for buy, `equipped` tint for `BOUGHT` |
| Standard row | 104, no eyebrow, 72 badge | 92, 60 badge, 13px category eyebrow |
| Featured row | 176, ribbon under the text | 172, gold tag above 26px name, facts chips, 112 badge with halo |
| Group header | `GAME PASSES / 5` | name left, count right, one hairline |
| Shorter column | ended at Express Salvage | closes on a `NO SHORTCUTS` policy card |
| Fold | row cut under a gold pill | 36px wash above a `MORE BELOW` lane sign |
| HUD chip | counted down the first boost to expire | counts down the paid clock when live |

## The rules applied

The rebrand follows the taste rules that map to a game storefront:

- One card system, one radius, one action plate. The two heights (92 and 172)
  are a rhythm, not a second style.
- Category colour is structural: rail, tag, halo, border. The verb is always
  emerald.
- No fact twice. The eyebrow names the domain, the sentence sells the effect,
  the chips hold the numbers. The hero blurb never repeats a chip.
- No empty column. The policy card is content a store should have, not filler.
- No half card at the fold. The wash turns the cut into a page edge.
- Type floor 13. Hero 26, row 18, body 14, labels 13.

## The recharge complaint

The grant was resetting `overdriveUntil` correctly. The chip was not showing it:
it took `min(boostRemaining, paidBoostRemaining)`, so a 60-minute charge bought
during the 59-minute welcome boost still printed 59m. The chip now shows the paid
clock whenever the paid boost is live, and the welcome or Starter 2x clock only
when no paid boost is running. The multiplier remains the product of both.

The full receipt path is still code-read here: Studio cannot complete a real
product purchase from this tool, and the MCP probe VM does not share
`DataManager` state with the running server. The user can test the purchase in
Studio.

## Verification

- `selene src`: 0 errors, 0 warnings, 0 parse errors.
- `rojo build default.project.json`: succeeds.
- Studio, Client: 9 cards in the store (5 passes, 3 products, 1 policy card).
- Studio, Client: rows measure 66 real px (92 design), heroes 124 real px
  (172 design) at the 0.722 canvas scale.
- Studio, Client: every label reports `TextFits = true`; chips range from 44 to
  97 real px and all fit the 450px hero text column.
- Studio, Client: the scroll bottom and the hint top both sit at 487; the fade
  spans 461 to 487; the hint hides at the end of the list and returns on scroll.
- Studio, Client: the gold store plaque and STORE tab render from the section
  accent change.
- Studio, Client: no new console errors.

## Still open

- The purchase itself has not been completed; the chip fix is verified in code
  and the payload carries `paidBoostMult`, but the one-hour reset needs a real
  receipt.
- Touch and gamepad have not been checked on the hero tag, facts chips or the
  footer lane sign.
- Persistence is still MOCK in Studio (DataStore 401), so `overdriveStacks` has
  not survived a save and reload.
