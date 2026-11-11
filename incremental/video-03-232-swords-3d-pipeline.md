---
title: Video Analysis — 232 Roblox Swords Workflow & 3D AI Generator Evaluation
source_url: https://youtu.be/FA_d0M3-Onw
author: YorusDevs
tags:
  - roblox
  - 3d-assets
  - ai-pipeline
  - tripo
  - luma-genie
  - blender
---

# Video Analysis: How I made 232 Roblox Swords with AI (Full Workflow)

## Overview & Core Strategy
Creator **YorusDevs** details a production pipeline for batch-generating 232+ game-ready 3D weapon models (swords, scabbards, pedestals) for Roblox using AI image design, 3D conversion tools, automated Blender script cleanup via Claude, and bulk Roblox Studio importing.

---

## The 5-Step Production Pipeline

### Step 1: Design Sheets & Clean References
* **The Rule:** 3D AI models copy reference images literally. If your image has artifacts, text, or background elements, the 3D model will be distorted ("mid").
* **Execution:** Generate clean style-consistent asset sheets on a plain white background. **Remove all magic effects, smoke, glowing auras, and text/measurements.** Aura and particle effects must be handled via engine code later; otherwise, the 3D generator turns them into solid, heavy geometry blocks.

### Step 2: Image-to-3D Conversion (Choosing the Right Generator)
* Standard web generators output bloated meshes (e.g., 1.4 million triangles), which exceed Roblox's performance limits (~20,000 triangles per mesh).
* Use game-asset profiles or tools with explicit face/polygon limits to cap meshes between 1,500 and 6,000 triangles.
* Always perform a dry run or check token/credit consumption before running bulk conversions.

### Step 3 & 4: Automated Blender Cleanup via Claude
Raw AI models export unscaled, misoriented, and uncentered assets (e.g., a tiny dagger and a giant sword both sizing at 1 meter, or clipping through geometry). 
* **No Manual Clicking:** Instead of manual editing, instruct Claude to write automated background Python scripts for Blender to:
  * Stand models upright with the sharp edge facing the swing direction.
  * Scale assets to real-world Roblox studs (e.g., katana = 4 studs, spear = 6.5 studs).
  * Define grip positions and fit scabbards.
  * Generate 2D UI render card previews straight from the 3D model.

### Step 5: Bulk Roblox Uploading
* For hundreds of items, write a script to upload meshes and manifest data straight into Roblox Studio via Open Cloud or automated batch importers.

---

## 3D Generator Evaluation & Fact-Check

We evaluated the primary tools mentioned in the workflow and community alternatives based on two criteria: **Free tier generosity** and **Reliability of model downloads**.

| Generator | Free Tier Generosity | Download Reliability | Verdict / Notes |
| :--- | :--- | :--- | :--- |
| **Tripo3D** | **Low.** Gives a small initial credit pool that depletes fast after a dozen generations. | **Yes**, supports GLB, OBJ, FBX, but locks advanced features/retopology behind paid plans. | Good for automated CLI batching, but free credits vanish too quickly for heavy prototyping. |
| **Meshy** | **Moderate.** Monthly credit pool, but can feel restrictive. | **Inconsistent/Problematic** (frequent user reports of export blocking or download failures). | Skipped due to download friction experienced during testing. |
| **Luma Genie** | **High.** Generous free research preview tier with no hard paywalls blocking basic browser exports. | **Yes**, direct, free browser downloads of standard `.glb` files. | **Current Best Bet for Prototyping.** Generates 4 variations per prompt, though it lacks granular polygon reduction sliders (requires a quick Blender decimation step for Roblox budgets). |

---

## Flexibility & Future-Proofing Note
Because 3D AI generation technology evolves rapidly and tools frequently change their pricing or limits, **this pipeline is modular**. If Luma Genie or Tripo proves restrictive during production, the pipeline can swap the 3D generation step to any alternative tool as long as it outputs standard `.glb/.fbx` files that feed into our automated Blender script cleaning loop.

---

# Shipped build log — 2026-11-10

The 3D generation step was **skipped entirely**. Steps 2–5 were implemented, but
step 1 (AI image → AI mesh) was replaced with a procedural loft driven by the
game's own data. Genie would have returned 10–40k triangles per blade and a
different object every run; the geometry is a handful of numbers, so a generator
adds nothing but variance and an importer dialog nobody can script.

## What exists now

| File | Role |
| :--- | :--- |
| `scripts/build_models.py` | Parses `BladeRegistry.luau`, lofts 25 blades, exports `.fbx` + `.obj` to `assets/models/`, writes `index.json` |
| `scripts/render_models.py` | Re-imports every `.fbx`, measures it, renders `assets/models/contact_sheet.png` |
| `scripts/blender.cmd` | Launcher: finds `blender.exe` (PATH, then newest `%ProgramFiles%\Blender Foundation\Blender*`) and runs a script with `--background` |
| `scripts/upload_assets.py --mesh` | Open Cloud `Model` upload, resumable cache, rewrites `AssetManifest.Meshes` |
| `src/shared/AssetManifest.luau` | `Meshes` table + `mesh()` accessor, kept separate from `Assets` |

Measured on the current build: **150 triangles per blade, 3 750 total**, heights
exactly `4.0 / 4.6 / 5.2 / 5.8 / 6.4` studs by tier, `pivotZ = -0.0000` on all 25
after an FBX round trip.

## Where the video's advice was right, and where it was not

- **Right:** scaling is the failure mode. Every export is sized in the asset, and
  the round-trip check reports the measured height so a regression shows up as a
  number, not a vibe.
- **Right:** orientation matters and must be baked in, not fixed later in Studio.
  `axis_forward="-Z"`, `axis_up="Y"` is the whole story.
- **Wrong for this project:** "3D AI models copy reference images literally" is
  true, but it argues *against* using one here. Our reference is a Luau table of
  eight numbers per blade. Copying it literally is exactly what the loft does,
  deterministically, for free.
- **Still unknown:** whether a generated mesh would look better at catalogue
  scale. At ~90px tall in the viewport, 150 triangles of flat colour is not the
  limiting factor; the silhouette is, and silhouette is a data problem.

## The three bugs worth remembering

1. **Blender's script executor uses `exec()`.** `__name__` is not `"__main__"`, so
   `if __name__ == "__main__": sys.exit(main())` does nothing. The first run
   reported success and wrote zero files.
2. **A unit cube's scale *is* its dimension.** The guard was scaled by
   `guard_h * 0.5`, leaving a gap, and the blade was anchored at `guard_h` while
   the grip ran `0 .. grip_h` — so the blade grew out of the middle of the
   handle and the model was 16% short. Both produced a clean log: 150 tris,
   plausible file sizes.
3. **Tapering from `u = 0` is a spear.** A sword holds its width and spends the
   last third losing it. This was only visible in a render; every number agreed
   with the bug.

## What is still open

- `entangle_scythe` has the strongest hook in the catalogue (`bend = 0.28`). It
  reads correctly in the contact sheet and stays inside the viewport frame
  (measured 0.13–0.98 through a full bob cycle), but nothing has been judged by
  eye yet — the bridge's `screen_capture` returns null on this build.
- The mesh pipeline has no visual regression test. Every check so far is
  numeric: bounds, tri counts, projected NDC, asset metadata.

## Mesh runtime (2026-11-10, later the same day)

Meshes are drawn in game. `MeshService` loads all 25 through
`InsertService:LoadAsset` on the server into `ReplicatedStorage.BladeModels`;
`BladePreview` clones, rescales and frames them. Verified live:

| Check | Result |
| :--- | :--- |
| Server load | 25/25 in ~3.4s (four workers; serial was ~35s) |
| Client draw | mesh present in the viewport, `size=(0.60, 4.00, 0.36)` |
| All 25 blades | mesh used for every one, height matches the manifest exactly, 4.00 / 4.60 / 5.20 / 5.80 / 6.40 |
| Framing | 0.13–0.98 of frame height through the bob, worst-case scythe included |

Three engine traps cost the time, all recorded in ADR-026:

- `Model:GetBoundingBox()` reports a MeshPart's **unscaled** native extents once
  the model holds any other part — a 6.4-stud blade measured 320.7. Bounds are
  now computed from `CFrame` and `Size`.
- `Model:PivotTo` with no `PrimaryPart` applies an extra translation on the first
  frame; an invisible pivot part at the hilt base pins it.
- Fitting the camera height exactly clips the near corner of a 3D blade. Margin
  is 1.30, and the bob is proportional to blade height.

## Upload run (2026-11-10)

| Step | Result |
| :--- | :--- |
| Meshes built | 25 blades, 150 tris each, 3 750 total |
| Uploaded | 25/25 to `user:1416845247`, all `Approved` |
| Manifest | `AssetManifest.Meshes` fully resolved, 0 placeholders |
| Re-run | `25 meshes in index, 0 to upload` |

Two traps found on the way, both recorded in ADR-024:

- Blender's FBX writer is not byte-deterministic, so a cache keyed on the file
  hash re-uploads everything after every rebuild — and uploads never overwrite,
  so that means duplicates, not replacements. Fixed with a `geometryHash`.
- `blender` is not on PATH after a default Windows install. `scripts\blender.cmd`
  resolves the newest `%ProgramFiles%\Blender Foundation\Blender*` so the command
  survives Blender upgrades.

## UI overhaul & click juice (2026-11-10, later again)

Two on-screen bugs turned out to share a server root cause.

**The `Unknown blade` cards were the network layer talking.** `Net` routed on the
verb and then re-passed it to the handler as the second argument. Every handler read
the action name as its payload, so `forge` looked up a blade called `"forge"` and
rejected with `Unknown blade`. Forging and equipping had never worked. Four
rejections stacked as toasts at top-centre — translucent, so the onboarding strip
underneath showed through and read as a ghosted `x1.00` behind `NEXT: Forge …`.

Fixed at the boundary (`(player, payload)`), and the toast stack moved to the
bottom-right where nothing lives.

| Check | Result |
| :--- | :--- |
| Forge via the real remote | `scrap_fang` forged, SM 3.07K → 3.06K, Aether 48 → 49, multiplier ×2.40 |
| Celebration | header and viewport mesh changed to `scrap_fang` in the same tick |
| Toast | `Forged Scrap Fang`, bottom-right stack |
| Tracker | `NEXT: Forge Rivet Edge — hit FORGE` / `READY`, ring on `BladeAction_rivet_edge` |
| Refresh, clean session | no console errors |

**Layout, measured rather than eyeballed** (design canvas, 1280×720, drawn at 0.72
scale in the test viewport):

| Check | Result |
| :--- | :--- |
| `VENT HEAT` inside the card | 12.0 design px gap below it, 48 px tall (was 4 px — visually clipped by the 22 px corner radius) |
| Stack | viewport 218 (42%), heat block 50, strike 124 (23.8%), vent 48 |
| Painted elements over the strip | 0 (was the toast stack) |
| Elements spilling outside the canvas | 0 visibly; 139 fully clipped inside the scroll views |
| Blade fill | 70.8–77.1% of frame height, hero camera 26° azimuth / 11° elevation, never touching an edge |

**Juice added:** floating `+yield` with a second `x2.5` marker in the band,
gravity sparks in a single connection, scale-punch on the viewport, white/gold stage
wash, 3D slam on the strike, heat-reactive glow on the anvil, `STRIKE SPEED` cadence
chip, and a four-beat forge celebration with a three-note chime synthesised from the
one built-in sample. All of it routes through `UiKit.tween`, so reduce-motion zeroes
the travel and drops the sparks entirely.

Not verified: a human eyeball pass (`screen_capture` is null on this bridge) and the
full five-step guide, because the dev profile is already past it. The step-5
`READY` path is the same `forgeReady` branch the tracker uses, which was verified.

## Polish pass: spotlight tutorial, clean blades, vent clarity, real panels (2026-11-10, last)

**The tutorial is now a modal card.** A centred 480×320 card with a 58% scrim at
`ZIndex 58/59`, one rung under the offline modal. Measured live: card centre exactly
on the canvas centre, stroke 2.5px at 0.35 transparency, scrim settled at
`BackgroundTransparency = 0.42`.

**The stuck gold outline was a target-resolution bug, not a drawing bug.** Step 4's
target was `forgeButton(state) or "Tab_Blades"`; the fallback fired on every tick the
player was on another tab, so the ring re-parented to BLADES and stayed there. Targets
now resolve from `SidePanel.activeTab()`: the control when its tab is open, else a
one-shot `Tab_*` cue recorded in `sawTab`. `SidePanel.onSelect` re-evaluates on the
same frame as the click.

Live check of the ring lifecycle on the client DataModel:

| Step | Observation |
| :--- | :--- |
| Card shown | `LESSON 1 OF 5`, `WELCOME TO QUANTUM FORGE`, CTA `START FORGING` |
| CTA pressed | ring count = 1, on `StrikeButton` |
| 3 strikes | ring count = 1, moved to `HeatGauge`; card hidden |
| Top-bar `SKIP GUIDE` | ring count = 0, strip visible, button back to `? GUIDE` |
| Any tab switch | no ring on any `Tab_*` at any point |

**`? GUIDE` becomes `SKIP GUIDE` while a lesson runs.** Without that, a player who
dismissed a card had no way out of the guide until they finished it: the card's own
skip is inside the card, and the scrim blocks the top bar while it is up.

**The yellow ring and floating dots are gone by deletion.** `buildAura` stacked a
translucent `PartType.Cylinder` disc across the blade plus 3–6 orbiting balls; on a
bright rarity colour that reads as a flat yellow disc cutting the sword in half.
Replaced with geometry that is part of the sword: serrated edge wedges (tier 2+), a
fuller that runs 34/55/78% of the blade by tier, a chevron crossguard (tier 2+) and
faceted neon cores at the ricasso (tier 3+). Live scan across 26 viewports: **0**
parts named `AuraRing*`, `Mote*` or `Shell`.

**Vent row, two states.** Below 85%: a sunken gauge with a heat-coloured fill, a
2px tick at the threshold, `THERMAL VENT: LOCKED` and `72% · REACH 85%`. At 85%+:
a solid cyan→amber plate, 2.5px stroke at 0.05, pulsing on the render step,
`⚡ VENT HEAT NOW` / `+7 AETHER`. Live: heat driven to 92% through the real `click`
remote → plate visible, fill hidden → vented → heat 0, `+7 Aether` toast, row back
to the gauge. The row's bottom edge sits 40 design px above the canvas bottom.

**Panels.** `UiKit.actionButton` gives every panel CTA three unmistakable states
(gradient / slate / green badge). Live: `FORGE` and `EQUIP` render the gradient,
`✓ EQUIPPED` the badge, `LOCKED` the slate plate with its cost; 25 blade cards each
carry a 4px rarity stripe (bronze → steel → violet → mint) and a progress bar; 8 tech
nodes carry a level bar; `Store` shows `R$ 199 / 149 / 99 / 399 / 25 / 49 / 99 / 249
/ 15` with `2X / AUTO / FAST / VIP / BOOST / QC / VENT` category pills; the active tab
is the only tab with a fill (`0.84`) and the only one with a visible border.

`Config.Debug` is now `false`.

## Reference-style UI rewrite: outlined plates, banner chrome, vent on the rail (2026-11-10, final)

Five local reference captures in `incremental/images/` set the target: opaque surfaces,
a hard 3px near-black border on every control, warm wood header banners with white
stroked type, solid gradient action plates, sunken dark tracks, a red X on modals. The
old build was thin translucent outlines over a dark field, so every state had to be
read rather than seen. `Theme.luau`, `UiKit.luau`, `Modals.luau`, `SidePanel.luau`,
`HudController.luau` and each panel view were restyled against that, and the bottom
vent bar was removed.

**What changed, file by file**

| file | change |
| :--- | :--- |
| `Theme.luau` | opaque elevation ladder, `outline = #0F1117`, wood/tan chrome, gold/cyan/violet/emerald accents, 12px house radius |
| `UiKit.luau` | `panel` bevel + lip, `banner` (icon plaque, right tab), `badge`, `closeButton`, gradient `button`, restyled `actionButton`/`tab`/`bar` |
| `Modals.luau` | one shell for every modal: 470×330 card, overhanging banner, 3px outline, red X, 0.28 scrim |
| `TutorialController.luau` | lesson card uses the same shell: 480×300, wood title banner, gradient CTA, X; `SKIP GUIDE` still in the top bar |
| `SidePanel.luau` | wood header banner, solid tab pills, one `UIListLayout` for the life of the panel (re-created layouts were stacking on tab switches) |
| `HudController.luau` | solid pill cards with accent stripes, gold/violet `ASCEND` and emerald `DAILY` gradient plates |
| `ForgeView.luau` | heat header + rail + vent key on one row; bottom vent bar deleted; anvil grows to 144px |

**Measured live (client DataModel, 0.719 canvas scale; divide by 0.719 for design px)**

| item | measurement |
| :--- | :--- |
| Forge panel | 586×400 scaled → 815×556 design, top at y=140, 16px bottom gap under the anvil |
| Heat rail | `Size = (1, -140)`, 34px tall; sits at design y 312 inside the forge column |
| Vent key | 132×34 design, flush right; locked state `VENT` / `REACH 85%`, slate plate, `#0F1117` 3px stroke, fill hidden |
| Ready plate | gradient keypoints sampled `67,215,245 → 255,194,60` (cyan→gold), fill frame present and hidden while locked |
| Tutorial card | 345×215 scaled → 480×299 design, centred on the canvas; banner title `WELCOME TO QUANTUM FORGE`; CTA 252×52 design; `LESSON 1 OF 5` |
| Ring after CTA | exactly one ring, parented to `StrikeButton`; top-bar label `SKIP GUIDE` |
| Ring after three strikes | moved to `HeatGauge`; later landed on `VentStrip` for the vent lesson |
| Offline modal | 470×330 design card live with `WELCOME BACK`, `+8.01M`, `COLLECT`; dismiss returns the modal root to invisible |
| Tabs | `Tab_Blades` at screen y=145, 44px banner above, active pill the only filled tab |

`selene src/` → 0 errors / 0 warnings / 0 parse errors. `rojo build -o verify.rbxlx` → clean.

**Open on this pass:** the vent key's locked state was driven live to 61% heat and
photographed by measurement; the 85% flip itself was not held long enough to capture
because simulated clicks through the MCP bridge only land a few per second and heat
decays at 5/s between round trips. The flip is the same `canVent` conditional that was
driven end-to-end through the real `vent` path in the previous pass (locked at 72% →
ready at 92% → vent → heat 0, `+7 Aether`), and the ready gradient is present in the
live instance. It needs one human click-through, not a code change.

## Equipped-blade binding and the fleet stage (2026-11-11)

**The blade desync was a write-before-mount cache.** `ensureBlade` stored the requested
id before it resolved the blade or checked the viewport, then mounted. Any early return
left the cache pointing at a model that was never built, and every later sync saw
"already mounted" and skipped. The mount is now one function that resolves, mounts,
paints the header from the same table, and reads back the id the viewport recorded.

| check (live client) | result |
| :--- | :--- |
| boot | `header=Nova Reaver  attr=nova_reaver  model=nova_reaver` |
| equip Rusted Cleaver | `header=Rusted Cleaver  attr=rusted_cleaver  model=rusted_cleaver`; badge moved to that card |
| equip Nova Reaver again | `header=Nova Reaver  attr=nova_reaver  model=nova_reaver` |
| four tab round-trips | `droneViewports=1`, blade binding unchanged |

The 25 blade models resolve to 17 distinct inner `MeshId`s. The eight shared ids are
pairs whose OBJ vertex/face data hash identical (Nova Reaver ↔ Astral Cutter, Rusted
Cleaver ↔ Cinder Spike, and six more); they differ only in vertex colour, which the
viewport overwrites from the registry. Geometry dedupe, not a mismap.

**The Fleet tab now has a stage.** A 180px viewport in the hero card, with the drone
count, capacity, live income and fleet bar overlaid on the render, and the buy controls
under it.

| measurement | value |
| :--- | :--- |
| viewport | 244×129 scaled → 339×179 design (stage 180) |
| drone model | `Drone`, 40 parts, `PrimaryPart = Core` |
| spin | pivot look vector changes across a 0.60s window (`spun=true`) |
| tab churn | exactly 1 `DroneViewport` after four switches → no leaked mounts |
| overlay | `6`, `/ 50 ONLINE`, `PRODUCING 23.40K/s` |

**`tick() * 1.5` does not spin a model.** The yaw lands at ~2.69e9 radians and
`CFrame.Angles` keeps the angle in single precision; spacing at that magnitude is ~256
radians, so every frame produces the same orientation. Measured: look vectors identical
across 0.35s, drone stationary. The builder accumulates `dt` instead. This is recorded
in ADR-030 because the expression looks correct and will be reached for again.

`selene src/` → 0 errors / 0 warnings / 0 parse errors. `rojo build -o verify.rbxlx` →
386,562 bytes.

## Sculpt pass: the blades are real meshes

Everything above was built from Luau primitives. This pass replaced the 25 blade shapes
and the fleet drone with FBX meshes sculpted by `scripts/build_models.py`, uploaded
through Open Cloud, and loaded at runtime — with the primitive recipes kept as the
fallback, so a clone with zero uploads still plays.

| measurement | value |
| :--- | :--- |
| assets | 26 meshes (25 blades + `fleet_drone`), 26 `.fbx`, 771 544 bytes on disk |
| triangles | 586–1 064 per blade, 476 for the drone, 21 540 total |
| heights | 4.02–6.68 studs, tier base 4.0 / 4.6 / 5.2 / 5.8 / 6.4 plus grip and guard |
| unique geometry hashes | 25 of 25 blades (the old build had 8 pairs deduping to one inner `MeshId`) |
| upload | 26/26 accepted, `Model` asset type, creator `user:1416845247` |
| live load | `ReplicatedStorage.BladeModels` = 26 models / 51 mesh parts in ~9s, 4 workers |
| inventory | 25 of 25 rows render a `MeshPart` thumbnail |
| forge viewport | `comets_wake[Metal]` + `comets_wake_glow[Neon]` |
| fleet stage | `fleet_drone[Metal]` + `fleet_drone_glow[Neon]`, `build=true` |
| locked waves | `nullbreaker`, `voidfang`, `entropy_edge` → `SmoothPlastic 0,0,0 a=0.0` |

**Two objects, not one.** A `MeshPart` carries a single `Material`, so a metal blade with
a glowing core has to be two objects: `<id>` and `<id>_glow`. `InsertService:LoadAsset`
returns both named, and the builder classifies on the `"glow"` substring. `rivet_edge` is
the one single-object blade — its recipe has `glow = "none"`, no runes, a plain bar guard
and a cap pommel, so there is nothing emissive to export.

**The registry's `Neon` and `Glass` are energy, not surface.** Comet's Wake rendered as a
transparent shell around its core at first: `Glass` was a sensible body material for a
primitive build with light inside it, and is a hollow sword on a sculpted one. `Neon`
flattens every bevel the mesh exists to show. `BODY_MATERIALS` admits `Metal` and
`DiamondPlate` only; everything else falls back to `Metal`, and all light lives in
`_glow`.

**The split read as a sandwich, then as a hole.** The first split build offset two
full-width blades along X with a slot between them — from most angles you looked straight
through the seam. `loft` now cuts across the width into `edge` and `spine` lanes that
share the silhouette, closing the channel over the last fifth so the tip is one point.
The second report was the rune plate: `width × 0.30` across the face, 0.655 studs on a
0.135-stud blade — a white bar punched through the steel. Marks on the flat are
`thickness × 1.20` in X, `width × 0.42` in Y; vents `thickness × 1.15` by `width × 0.13`.

**Face order is part of the cache key.** `geometryHash` covers verts, faces and object
names, and the uploader re-sends only what changed. Reordering the base caps in `loft`
would have re-uploaded all 25 blades for a cosmetic diff, so the split path emits caps in
the pre-split order. Verified by hash diff: 14 blades changed on the split pass (the
split-bearing ones), 0 on the tidy-up pass.

**Fog of war is waves of three, and the reveal line stopped leaking names.** Wave N+1
opens when the third blade of wave N is owned. The gate is named only when it belongs to
the newest revealed wave; deeper rows read `CLEAR WAVE 6 TO REVEAL`. Before the fix,
three rows read `FORGE HADRON SPLITTER TO REVEAL` while Hadron Splitter was still `???`.
The line also moved to the bar row and took full width — 200px against a button starting
at x = -114 clipped it under the plate.

`selene src/` → 0 errors / 0 warnings / 0 parse errors. `rojo build -o verify.rbxlx` →
421,890 bytes.

## UI pass: toasts, vent plate, fleet bands, orbit, tier wash

| check (live) | measurement |
| :--- | :--- |
| toast rect | `160,487 259×24` screen → design x 20..380, y 678..712 |
| strike plate | `181..710 × 378..482` screen → design y 526..670 |
| side panel | x 745 screen (834 design) — toasts stop 450px short |
| vent ready (heat 92) | fill `0,210,255`, stroke `2.5 / 11,14,20`, `VENT HEAT`, `+7 AETHER`, text `255` stroke 0 |
| fleet hero | 123px screen of a 448px column → 38.2% |
| fleet strip | `OUTPUT` gold `255,194,60`, `PER DRONE` cyan `67,215,245` |
| dock faces | `BUILD 1 · 5` ink, `BUILD 10 · 106` gold (geometric sum of ten) |
| blade orbit | idle 0.75 rad/s, held 0.00, released 0.75 |
| drone orbit | idle 0.85 rad/s, held 0.00, released 0.75 |
| pitch clamp | bench model `upY = 0.819` (cos 35°) for `pitch` and `extraPitch`; destroy freezes |
| tier 1 wash | `168,74,36` / `122,88,26` on all eight pool layers |
| right pool | 187px at left 339, right 526 of a 528px stage — 2px inside |
| corner radii | 70/54/39/23 warm, 57/44/31/19 cool (were all `0/0`) |

**`UiKit.corner` takes a number, and a UDim resolves to zero.** `UDim.new(0, UDim.new(0.5, 0))`
does not error — it takes the offset of the inner UDim, which is 0. Every "soft
circle" behind the blade was a hard square. That is the misaligned-boxes report.

**The toast stack had nowhere to go.** Bottom-right sat on the side panel dock,
top-centre on the onboarding strip, top-left on the currency pads, and the bottom
of the forge panel is the strike plate. The free band is 37px tall under the anvil,
so the stack runs sideways in it: two 360×34 pills, ZIndex 30, verified clear of
every clickable rect.

`selene src/` → 0 errors / 0 warnings / 0 parse errors. `rojo build -o verify.rbxlx` →
435,278 bytes.

## Bugfix pass: anvil drift, camera orbit, scroll memory, status row

Four reports. Three had a single root cause each; the fourth was a stale layout
number.

| check (live) | result |
| :--- | :--- |
| strike button rect, 12 real clicks | `{0,0},{0,360}` before and after; absolute `181.9,378.4` unchanged |
| star-matter across those clicks | 9.69B → 9.72B, so the clicks did register |
| overlapping shake bench | 30 shake pairs on one target, settles at `0.00,0.00` |
| blade spin while mouse held | 0.90 rad/s |
| drone spin while mouse held | 0.94 rad/s |
| drone camera | yaw `143.2°`, radius `5.61` vs authored `143.2°` / `5.589` |
| camera bench (`centre 0`, `distance 10`) | yaw `0.80` rad, elevation `28.6°` at pitch `-0.5`, radius `10.0` |
| pitch clamp | `pitch = ±9` rad lands at exactly `-40.0°` / `+40.0°` |
| scroll memory | Blades `600` → Fleet → Blades, `CanvasPosition.Y = 600` on a 1950px canvas |
| status row | rate `156,69 204×21`, strip `366,69 369×21`, forge `156..735`, side panel `745..` |
| top bar | banner `210×37` (292×52 design), pills and action keys all `41px` tall, guide edge `1252` design |

**The drift was a moving reference point.** `Vfx.shake` captured `target.Position`
at the start of each call, and an overlapping call began while the previous offset
was still applied. Each click adopted a displaced position as home. Fixed with a
per-target `{ rest, connection }` registry, and the anvil plate stopped being
shaken at all: the jitter runs on an inset `Content` frame so the full-width plate
cannot leave the card.

**Drag now moves the camera, never the spin.** `ViewportOrbitController` spins the
model at 0.9 rad/s unconditionally and orbits the camera at the player's angles
with a ±40° pitch clamp enforced in the render loop as well as in the handler.

Bridge limit, recorded so nobody repeats the attempt: `moveTo` produces
`MouseMovement` events with `Delta = 0`, so a simulated drag cannot drive the drag
path. The camera maths was verified by writing the angle fields the handler writes.

`selene src/` → 0 errors / 0 warnings / 0 parse errors. `rojo build -o verify.rbxlx` →
447,276 bytes.

## Note on running the scripts

`blender` is not on PATH for a default Windows install, so
`blender --background --python …` fails with "not recognized". Use
`scripts\blender.cmd build_models.py` instead — it resolves the newest
`%ProgramFiles%\Blender Foundation\Blender*` folder, which also survives Blender
upgrades. Both scripts were verified under `--background` (exit 0): the build
reports 25 blades + the drone at 21 540 triangles, the render reports `pivotZ =
-0.0000` for all 25 and writes the contact sheet.

