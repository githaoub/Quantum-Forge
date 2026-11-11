---
title: Video Analysis — AI Procedural Layered VFX & Sprite Pipelines
source_url: https://youtu.be/7VQpF5ERE0M
author: YorusDevs
tags:
  - roblox
  - vfx
  - ai-pipeline
  - sprite-sheets
  - asset-generation
---

# Video Analysis: Procedural Layered VFX Generation via Code & MCP

## Overview & Core Strategy
Instead of using flat AI image generators (which yield static, sticker-like textures) or hand-drawing assets, leverage an AI agent connected via Model Context Protocol (MCP) or local Python scripts to draw complex visual effects (VFX) **shape-by-shape, layer-by-layer, and frame-by-frame as pure code**.

For **Quantum Forge: Blade Evolution**, this allows us to generate custom blade auras, slash animations, core explosions, and elemental particles locally without manual design bottlenecks.

---

## Key Pipeline Principles

### 1. Multi-Layer Construction
* Never ask an AI to generate a single composite texture. 
* Break every VFX into distinct structural layers with dedicated responsibilities:
  * **Rim / Outline:** Sharp, high-contrast framing edge.
  * **Body:** The core mass/shape of the effect.
  * **Hot Core:** High-intensity center or leading edge.
  * **Glow / Bloom:** Soft outer falloff.

### 2. Pure White Base Asset Rule (Color Agnosticism)
* **Everything must be drawn in pure white on a dark/transparent canvas.**
* *Why:* This allows the Roblox game engine (via `UIGradient`, `ImageColor3`, or custom particle emitters) to dynamically tint and color the exact same base asset into multiple elements (Blue Plasma, Toxic Poison, Void Purple, Solar Gold) at runtime. One base asset serves infinite themes.

### 3. Flipbook & Animation Sequencing (Sprite Sheets)
* Slashes and impacts are animations, not single images.
* Instruct the AI or script to generate **4x4 (16-frame) sprite sheet flipbooks** where the effect scales in, evolves, and decays.
* **Taper Rule:** Prevent flat-edge cutoffs at frame borders. Every stroke must taper cleanly to a point at both ends across all frames.

### 4. Guarding Against AI Visual Pitfalls
When instructing AI agents to generate or script procedural vector/raster assets, enforce these hard constraints:
* **Taste & Polish Check:** Explicitly forbid dated or simplistic low-poly aesthetics ("Nintendo 64 look"). Require dynamic flowing lines, jagged natural tears, and high-fidelity gradients.
* **Edge Margin Rule:** Nothing can touch within 4 pixels of the canvas edge to prevent hard square bounding box artifacts when rendered in 3D space.
* **Moderation / Safety Rule:** Avoid dense, unshaded red shapes that resemble blood or gore (which risk Roblox content safety filters). Restrict red tones strictly to stylized thermal glow, fire flames, or smoke.

---

## Actionable Prompt Template for DeepSeek / Asset Agents
When tasking DeepSeek or a coding agent to build or generate our VFX/asset pipeline scripts (such as a Python Pillow script or Luau particle configurator), feed it this directive:

```text
Design a procedural asset generation script that outputs layered, pure-white sprite sheets (4x4 grid, 512x512 per frame) for [EFFECT_NAME]. 
Constraints:
1. Output separate layers: Rim, Body, HotCore, and Glow.
2. Render in pure white (#FFFFFF) on a transparent background so the engine can dynamically tint it.
3. Apply jagged, organic flow lines with tapered points (no flat blunt cutoffs).
4. Enforce a strict 4px margin from canvas borders to avoid bounding box artifacts.
5. Export metadata for frame timing and sprite sheet coordinates.
```

---

## Build log — what actually shipped (2026-11-09)

The spec above is the brief. This is what the implementation ended up being, and
the parts of the brief that turned out to be under-specified.

### Files

| Path | Role |
| --- | --- |
| `scripts/generate_vfx.py` | Draws every effect, enforces the 4px margin, writes `index.json` and `VfxManifest.luau`. |
| `src/shared/VfxManifest.luau` | Generated. `Sheets` (flat `effect_layer` → asset id), `Effects` (frames/fps/loop), `layer()`, `isReal()`. |
| `src/client/SpriteFx.luau` | Plays the sheets. One shared `Heartbeat`, `play` for one-shots, `attach` for loops. |
| `assets/generated/vfx/` | 20 layer sheets + 2 particles + `contact_sheet.png` + `review.png` + `index.json`. |
| `scripts/upload_assets.py --vfx` | Uploads sheets and re-emits the manifest through the generator's own emitter. |

Effects: `slash`, `impact`, `vent`, `overheat` (one-shot) and `aura` (loop-safe,
frame 15 wraps to frame 0 with no seam). Particles: `particle_spark`,
`particle_ember` (single images, not flipbooks).

### The three compositing rules the brief did not state

Drawing was never the problem; compositing is where four passes failed.

1. **The rim must be subtractive.** `rim = widen(body, n) - body`, never a
   dilated body. A dilated copy pasted over the body is one thick slab with a
   hard border — a drawn donut. No amount of jitter fixes it, because the defect
   is in the compositing, not the silhouette.
2. **The glow is two radii blended with `ImageChops.lighter`.** A single blur
   radius has no falloff and reads as a flat vignette behind the shape. A tight
   halo keeps the shape legible; a wide bloom supplies the light.
3. **A ring that has not shattered is clip-art.** A continuous band is a drawn
   donut. `impact` and `overheat` use 6–8 tapered arcs with uneven gaps and
   slightly different radii, plus a wide soft lobed ring modulating the front.

### Radial needles are always a spider

Any arrangement of straight shards emanating from one shared centre reads as a
spider or a pinwheel, however it is jittered. What works instead:

- **tangential arc smears** at varying radii — debris thrown off a front;
- **wide-lobed rings** — the shock itself;
- **jagged paths with a wide root and a pointed tip** — fracture;
- **arcs that never touch the core** — expanding heat, so the core stays the
  only focal point.

`overheat` originally used cracks converging on the centre. It now uses four
tangential heat arcs plus embers, and the core flash is the only thing at the
middle.

### Smoke needs persistent identity

`vent` re-seeded its RNG per frame in one pass, so every frame had a different
puff layout and the plume boiled like TV static. Puff parameters are now drawn
once (`vent_puffs()`), and the frame only advances a phase —
`u = (phase + t * k) % 1` — with alpha fading to zero at the top so a wrapped
puff never pops back in at the mouth.

The cone silhouette comes from a gaussian lateral offset whose width grows with
height. Columns with a linear drift term trace two straight edges no matter how
much noise is added on top.

### Measured, not asserted

The generator prints the worst margin per effect and exits non-zero if any sheet
is under 4px:

| Effect | Worst margin | Frame |
| --- | --- | --- |
| `slash` | 32px | 512 |
| `impact` | 4px | 512 |
| `vent` | 8px | 512 |
| `overheat` | 12px | 512 |
| `aura` | 39px | 512 |

One common centre-anchored scale per effect (`margin_factor` +
`scale_about_centre`) keeps margin compliance from making the effect pulse in
size across frames.

Determinism was verified directly: two consecutive runs produce byte-identical
PNGs, which is what lets the upload step key off content hashes.

### Runtime contract

- Sheets are pure white on transparent. Opening one directly shows nothing —
  always composite on a dark board before judging it (`review.png` is exactly
  that).
- `SpriteFx.play` returns `false` and `SpriteFx.attach` returns `nil` when the
  manifest is unuploaded, motion is reduced, or no layer resolved. Every call
  site keeps a procedural fallback:
  `if not SpriteFx.play(...) then Vfx.burst(...) end`.
- `aura` is exempt from the `MAX_ACTIVE` eviction that governs clicks. It is
  placed by the game; evicting it under an autoclicker would make it blink.
- One-shot effects refuse to loop and looping effects refuse to play once, so a
  sheet cannot be used in the wrong role by accident.
- `Sfx` uses `rbxasset://` engine samples, so audio needs no upload either.

### Manifest shape

`VfxManifest` is annotated (`local VfxManifest = {} :: Manifest`). An inferred
table literal with named keys is sealed, and `Sheets[effect .. "_" .. layer]`
does not type-check in strict mode. The emitter writes the annotation, so
regenerating cannot reintroduce the bug.

### What is still open

Nothing here is uploaded. `requests` is not installed in this environment, so
every id is `rbxassetid://0` and the game takes the procedural fallback
everywhere. Running `python scripts/upload_assets.py --vfx --creator user:<id>`
after `pip install -r requirements.txt` is the only remaining step; `--dry-run`
already lists the 22 sheets and their sizes.
