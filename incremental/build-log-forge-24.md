---
type: build-log
status: shipped in Studio, not yet published
updated: 2026-11-12
aliases:
  - forge-24
tags:
  - build-log
  - forge
  - monetization
  - store
---

# Forge 24 - The boost that wants to be bought again

Instant Overdrive was a fifteen minute 3x that punished a second purchase: the
new clock overwrote the old one, so buying while the first was live threw away
time. The offer is now a multiplier that stacks without a ceiling and a clock
that never passes one hour, which makes the repeat purchase the point.

## What changed

| Surface | Before | After |
| --- | --- | --- |
| Paid multiplier | flat 3x | `3 * max(1, overdriveStacks)`, no cap |
| Paid duration | 900s, extended by re-buying | 3600s ceiling, reset on every charge |
| Save field | `overdriveUntil` only | `overdriveUntil` + `overdriveStacks` |
| HUD chip | hardcoded x3 | `paidBoostMult` from the server |
| Instant Overdrive row | 104px list row | 176px hero row, two slots |
| Row tag | `BOOST` | `STACKABLE` gold ribbon |
| Store overflow | 4px scrollbar only | gold `SCROLL DOWN` pill in a footer strip |

## The stack

`overdriveStacks` is a saved integer, clamped to a non-negative whole number on
load. `globalMultiplier` multiplies by `OverdriveMultiplier * max(1, stacks)`
while `overdriveUntil` is in the future, so an expired boost contributes nothing
even though the stacks remain on the profile. Every grant adds a stack and sets
`overdriveUntil = now + min(OverdriveSeconds, OverdriveMaxSeconds)`.

The reset, not the extension, is the design. A charge with forty minutes left
trades those minutes for a stack, so a player who wants to keep a large
multiplier live has to recharge on the hour rather than once a day. The server
sends `paidBoostMult` in the sync payload; the chip prints the product it is
actually earning, including the 2x pass.

Measured against a fake state in the server context:

| stacks | passes | `globalMultiplier` |
| --- | --- | --- |
| 0 | none | 3 |
| 1 | none | 3 |
| 2 | none | 6 |
| 5 | none | 15 |
| 2 | 2x Star-Matter live | 24 |
| 9 | expired | 1 |

`OverdriveSeconds` reports 3600. The grant path itself is code-read: a Studio
purchase prompt cannot be completed, and the MCP probe VM does not share
`DataManager` state with the running server.

## The copy

The three multiplier offers now say which half compounds:

- Instant Overdrive: "3x Star-Matter for 1 hour. Multiplier stacks infinitely,
  and with 2x Star-Matter. Duration does not stack: each charge resets the
  hour."
- 2x Star-Matter: "Doubles all Star-Matter income, forever. Stacks with every
  boost; it does not add to their duration."
- Eternal Forge: "+25% to all Star-Matter income, forever. Stacks with every
  boost; it does not add to their duration."

Instant Overdrive moved into the same 176px hero tile as the Starter Forge Pack,
with a gold `STACKABLE` ribbon in place of `FIRST BUY`. That is the "two slots"
the Starter pack already occupied: a test account that owns both now sees two
tall tiles in the right column instead of one tall tile and a list row.

## The scroll hint

Two columns of tall cards overflow on a laptop, and the only affordance was the
thin scrollbar at the panel edge. The section panel now reserves a 28px footer
strip for a gold `SCROLL DOWN` pill:

- `Sections.SCROLL_INSET_Y` is 128, applied in `init` and `layout`.
- The pill sits exactly at the scroll rect's bottom edge, with no gap and no
  overlap.
- It shows while `AbsoluteCanvasSize.Y - AbsoluteSize.Y > 8` and hides within
  6px of the end.
- It is a `Frame`, so it never captures a click meant for a buy button.

The first version subtracted `CanvasSize.Y`, which is a `UDim`, from a pixel
height. The error fired inside `Sections.init`, so the client never reached
`QF_Dev` or `StateStore.init`: a blank store and a dead dev seam. The check now
uses `AbsoluteCanvasSize`.

## Verification

- `selene src`: 0 errors, 0 warnings, 0 parse errors.
- `rojo build default.project.json`: succeeds.
- Studio, Server: the multiplier table above, against synthetic states.
- Studio, Server: `MonetizationConfig.OverdriveSeconds` is 3600 in the running
  module.
- Studio, Client: store shows 8 rows, with VIP, Starter Forge Pack and Instant
  Overdrive as 127 real px hero rows (176 design px).
- Studio, Client: `STACKABLE`, `FIRST BUY` and `BEST VALUE` ribbons all fit.
- Studio, Client: the Instant Overdrive description wraps inside its label;
  `TextFits` is true.
- Studio, Client: the hint shows at the top (`overlap = false`, gap 0), hides at
  the end of the list (`CanvasPosition.Y` 145), and returns when scrolled back.
- Studio, Client: no `Sections` errors in the console after the fix.

## Still open

- A real purchase has not been completed; the prompt path and the grant
  arithmetic are code-read.
- Touch and gamepad have not been checked on the new hero tile or the footer
  strip.
- Persistence is still MOCK in Studio (DataStore returns 401), so
  `overdriveStacks` has not survived a save and reload.
