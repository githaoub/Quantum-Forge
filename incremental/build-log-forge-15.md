---
type: build-log
status: shipped
updated: 2026-11-11
aliases:
  - forge-15
tags:
  - build-log
  - crates
  - store
  - runes
  - ui
---

# Forge 15 - The ceremony takes the screen

Forge 14 turned the reveal into a ceremony, but the ceremony was a card: a tier
wash, a stage and a two-column block of odds over the crates page. The model sat
beside a paragraph instead of in the middle of the frame. This pass removes the
card, takes the whole screen, and fixes three things the store had been lying
about.

## What changed

| Surface | Before | After |
| --- | --- | --- |
| Crate reveal | Card over the page, two-column text | Full-screen black takeover, model centred, one line above and one below |
| Crate background | Flat black viewport inside a rounded card | Full-bleed `StageBackdrop` wash, edge to edge, retinted by crate, variant and rarity |
| Overlay coverage | 1213x518 (the canvas sheet) | 1213x634 at `-58` y, i.e. the viewport plus the top-bar inset |
| Batch | One crate model for any pull | Three crates for x3, ten for x10, one click each |
| Strike | Label swap | `Vfx.shockwave` at the cursor, sparks, burst, crate jump-and-turn, pip fill |
| Crate models | One box with a glowing disc | Keyhole lock, iron bands, corner posts; capsule, obelisk, orbital core and a vault wheel |
| Result | 2D silhouette under the blade | Blade only, `frameFill` 0.9, name, rarity, pips, COLLECT |
| Store scroll | `CanvasSize` written in screen pixels, 324 of 372 | `CanvasSize` written in canvas units, 692 of 373 |
| Store top | Nine identical 104px rows | VIP and Starter Forge lead as 176px hero tiles with ribbons |
| VIP | Status only | Grants every other gamepass on join |
| Starter pack | 25 Aether, 15 min | 500K Aether, 20 min |
| Runes | `CRAFT 3` on the button | `CRAFT` on the button, `0 OWNED · 6 SHARDS` on the row |
| Rune cost | 3 / 3 / 4 / 5 | 6 / 6 / 9 / 12 |

## The overlay

`CrateReveal` is a `TextButton` on `Canvas` at `ZIndex 38`: above the rail, the HUD
and the sections, below `Vfx` (40) so the strike ring is not swallowed by the
scrim. `Modal = true` means no click leaks into the page behind it.

`fitScreen` sizes it to `viewport + GuiService:GetGuiInset()` in canvas units and
pushes it up by the inset. The fixed 1686x720 sheet is scaled to 0.72 on the test
window and stops 58 px above the bottom of the screen; the overlay is the one
surface that must not inherit that box, because a lit strip of world along the
bottom of a "black" ceremony is exactly the kind of detail that makes a screen
look unfinished.

The wash is `StageBackdrop.paint` on a full-screen frame with `radius = 0`. Every
band in that module is the size of its parent, so the band edges land on the window
edge and the gradient has no boundary. That is why this reads as light in a room
and the first attempt — three crossed bands sized to the stage — read as brown
rectangles floating in the black.

## The ladder

1. Drop: the group falls in from +7.5 studs, the camera FOV punches from 36 to 30.
2. Land: a 0.16 s settle, `onLanded`, and the prompt becomes `CLICK TO OPEN`.
3. Strike: one click breaks one crate. `openCrate` fades the parts over 0.26 s
   while a `CFrameValue` lifts, turns and tips the model, then it is destroyed.
   A 58px ring fires at the cursor, ten sparks and a burst at the stage, and the
   whole stage shakes.
4. Seal: after the last crate the prompt becomes `SEALED` for 0.3 s.
5. Reveal: the pending answer is shown as a blade on the same stage, with the wash
   retinted to variant and rarity, a flash, a shockwave and a spark burst.

The answer is held, not raced: `deliver` stores the event and `tryReveal` only runs
when the last crate has been clicked, so a fast server cannot cut the ceremony
short.

## Models

Five pools, five silhouettes, all primitives:

- **Standard** — plank crate with an iron frame, corner posts, a lifted lid and a
  lit keyhole.
- **Void** — a fuel drum: cylinder body, heavy caps, belts, a magenta viewport.
- **Quantum** — a stepped obelisk on a plinth, caged, with a diamond crown and
  four floating shards.
- **Celestial** — a dark sphere with a lit heart and three segmented orbital rings
  (twelve tangent bars each; Roblox has no torus).
- **Singularity** — a plate vault with a recessed circular door, a twelve-segment
  wheel, four spokes and eight rim bolts.

The camera is a 30 degree lens, deliberately narrow: at 40 degrees the outer crates
of a three-pull turned outward and a straight row read as a fan.

## Verification

| Thing | State |
| --- | --- |
| Static | `selene src/` 0 errors, 0 warnings, 0 parse errors; `rojo build -o verify.rbxlx` succeeds |
| Coverage | Live `AbsolutePosition` read `0, -57.5` and `AbsoluteSize` `1213 x 634` on a 1213x576 viewport |
| Wash | Captured with no band edge and no uncovered strip at the top |
| x3 rack | Three crates, one click each, `1/3` then `2/3` then reveal |
| x10 rack | Ten Void Capsules, 5x2, `0/10`, ten pips |
| Result | `BEST OF 3`, `DUSK SPIKE`, `SCRAP · PRISMATIC`, three gold pips, `COLLECT 3` |
| Store scroll | `CanvasSize` 692, `AbsoluteCanvasSize` 497, window 373; wheel moved 0 to 72.38 |
| Fleet scroll | `CanvasSize` 608, window 373; wheel and direct write both clamp at 64.38 |
| Rune label | Not yet photographed after the rename |

## Still open

- The store cannot be bought from: every Marketplace id is 0, so every row says
  `SOON`. `scripts/create_store_items.py --apply` needs a key with
  `game-pass:write` and `developer-product:write`.
- Crate and blade meshes still return `User is not authorized to access Asset`, so
  every model above is procedural.
- A x10 pull needs ten free vault slots. The page correctly trims the batch to the
  free slots and charges the trimmed price, but there is no "melt to make room"
  shortcut on the storefront.
