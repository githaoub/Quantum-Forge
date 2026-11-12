---
type: build-log
status: shipped in Studio, not yet published
updated: 2026-11-12
aliases:
  - forge-22
tags:
  - build-log
  - forge
  - audio
  - vfx
---

# Forge 22 - Ping first, and a flash that is actually the screen

The click still had an explosion under it, and the wash still had a strip of
screen above it. This pass renders a new metal ping family, removes the last
blast from the kit, and gives the wash its own full-screen layer.

## What changed

| Surface | Before | After |
| --- | --- | --- |
| Forge click | Pitched `impact_explosion_03` | One uploaded metal ping `STRIKE` |
| Band answer | Same blast higher | `BAND`, the same instrument a fourth up |
| Crit | Blast plus two pings | `CRIT`, an octave above, one low body |
| Body cues | `impact_explosion_03` | `ANVIL`, a heavy metal hit |
| Wash host | Frame on the game ScreenGui | `VfxScreen`, `IgnoreGuiInset`, order 500 |
| Wash coverage | 1212x520 of a 1212x578 viewport | Full 1212x578 |
| Forge white | Frame clipped to the 3D stage | `Vfx.flash` on the screen layer |
| Wash allocation | New frame and tween per call | Three frames recycled |

## The new samples

Four samples were rendered from six inharmonic plate modes plus a 10ms hammer
transient, then normalized and uploaded to the account that owns the place:

| Key | Id | Length | Use |
| --- | --- | --- | --- |
| `STRIKE` | 71886932584271 | 0.50s | forge click |
| `BAND` | 139799433605109 | 0.40s | sweet spot answer |
| `CRIT` | 121142281920008 | 1.05s | crit |
| `ANVIL` | 95191181057410 | 0.45s | crates, forge, ascent |

The strike was kept short on purpose. At ten clicks a second a 0.8s ring stacks
into a drone; 0.5s with a 0.12s fade leaves the ring audible between clicks and
nothing ringing on top of itself. `PING` and `CLICK` stay because they are client
assets that resolve offline and they carry the melodies.

## The screen layer

`UiKit.screen` measures the canvas to the game area, and `IgnoreGuiInset = false`
keeps it below the Roblox top bar. The measured numbers in Studio were a 1212x578
viewport with a 1212x520 game screen, so a wash on that screen could never be
full screen. `VfxScreen` is its own `ScreenGui` at `DisplayOrder 500` with
`IgnoreGuiInset = true`; the `VfxFlash` frame inside it now measures 1212x578.
`ForgeView` stopped owning a wash entirely: `flashViewport` became `screenFlash`,
which forwards to `Vfx.flash`.

## Verification

- `selene src`: 0 errors, 0 warnings, 0 parse errors.
- `rojo build`: succeeds.
- Studio, Client: one `VfxScreen` exists at `DisplayOrder 500`, `IgnoreGuiInset`
  true, measured 1212x578 against a 1212x578 viewport while the game screen is
  1212x520.
- Studio, Client: `Vfx.flash` produces a 1212x578 wash on `VfxScreen.VfxFlash`.
- Studio, Client: `Sfx.strike(false)` plays `STRIKE` only; `Sfx.strike(true, 5)`
  adds `BAND`; `Sfx.crit()` plays `CRIT` plus one low `ANVIL`.
- Studio, Client: all four uploaded ids preload at their authored lengths (0.50,
  0.40, 1.05, 0.45).
- Studio, Server to Client: a forced crit paints two full-screen 1212x578 gold
  washes and a 6px ring that reaches 344px at 0.08s.

## Still open

- The samples were rendered offline and checked with a classifier, not with a
  human ear on the final mix. The band and crit layers are the ones to audition.
- The sprite sheets are still unuploaded, so the 420px crit disc is still the
  procedural ring.
- Per-click screen washes have not been checked on touch or gamepad.
