---
type: build-log
status: shipped in Studio, not yet published
updated: 2026-11-12
aliases:
  - forge-21
tags:
  - build-log
  - forge
  - audio
  - vfx
---

# Forge 21 - One click, one ring, one screen

The forge click was still carrying a metal ping under the impact sample, and the
crit that the gold ring belongs to was almost never rolled on a new account.
The yellow crit wash and the white forge wash also stopped at the canvas edge.
This pass narrows the click, gives every blade a base crit chance, and moves the
wash to the screen.

## What changed

| Surface | Before | After |
| --- | --- | --- |
| Forge click | Ping body plus pitched impact | One `impact_explosion_03` sample, with the band answer the same sample higher |
| Crit chance | 0% until a variant, rune, set or tech node supplied it | `Config.BaseCritChance` = 5% on every account |
| Crit ring | 32px procedural ripple when the sprite sheet is missing | 180px ring expanding to ~3.2x |
| Crit wash | Inside the canvas, under the ceremony | `VfxFlash` on the ScreenGui at `ZIndex 100` |
| Forge white wash | Crate overlay and canvas only | Same screen-wide layer |
| Ascension and overheat | Canvas wash | Screen-wide wash |

## The screen layer

`UiKit.screen` sizes the canvas to the game area, not the raw viewport. A wash
parented to the canvas therefore stops at the letterbox on a narrow window and
sits below the crate ceremony, which is why the yellow crit and the white forge
flashes read as partial rectangles. `Vfx.init` now builds a `VfxFlash` frame on
the ScreenGui itself, above the canvas at `ZIndex 100`, and `Vfx.flash` writes
only there. `flash` also takes an optional duration so a short stage beat does
not leave a half-second wash behind.

## The ring

The crit path asks `SpriteFx` for the 420px impact sheet first. The sheets are
still unuploaded, so it falls back to `Vfx.strikeBurst`. That fallback used to
add a 32px ripple, which is the same scale as an ordinary strike. The crit
branch now adds a 180px ring with a 3.2x spread and a 6px stroke, so the shape
is legible without the sheet.

## Verification

- `selene src`: 0 errors, 0 warnings, 0 parse errors.
- `rojo build`: succeeds.
- Studio, Client: `TechTreeConfig.compute({}).critChance` reads `0.05`.
- Studio, Client: `Sfx.strike(true, 5)` plays three `impact_explosion_03` layers
  and no ping.
- Studio, Client: a forced crit event paints two 1212x482 washes on
  `QuantumForge.VfxFlash` at `ZIndex 100`, covering the full ScreenGui.
- Studio, Client: the same crit draws a 6px gold ring that reaches 247px at
  0.05s and keeps expanding, next to the ordinary 2px 57px ripple.

## Still open

- The sprite sheets are still unuploaded, so the 420px disc is not what plays.
- The 5% base crit adds about 20% expected click yield; if the economy needs
  the old curve back, change the one constant.
- The ring and wash have not been checked on touch or gamepad.
