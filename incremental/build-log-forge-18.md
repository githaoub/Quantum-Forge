---
type: build-log
status: shipped in Studio, not yet published
updated: 2026-11-12
aliases:
  - forge-18
tags:
  - build-log
  - forge
  - audio
  - settings
  - meshes
  - retention
---

# Forge 18 - A stage, a slider and a reason to stay

The forge had a button bigger than its sword, the crate was mixed under the
anvil, the settings sheet could only mute, a failed mesh could replace a visible
sword with an empty viewport, and the next-goal rail went blank once the finite
ladders were finished. This pass fixes all five and adds the first account-wide
goal ladder that is not another currency.

## What changed

| Surface | Before | After |
| --- | --- | --- |
| Forge strike | 240x64 orange `STRIKE` key | No key; full-bleed stage keeps every click, small payout caption |
| Crit | Float, flash, sparks | Plus a gold shockwave ring on the same server event |
| Crate landing | 3 layers, 0.34 / 0.17 / 0.11 | 4 layers with a low chest hit, 0.42 / 0.18 / 0.13 / 0.12 |
| Crate break | 0.30 / 0.24 final | 0.42 / 0.34, plus 0.26 low body and 0.22 ring |
| Crate shatter | 0.22 / 0.24 / 0.14 | 0.34 / 0.30 / 0.18, plus 0.12 sub |
| Crate tick | 0.09 base, +0.014 per click | 0.11 base, +0.016 per click |
| Heartbeat / riser | 0.30 / 0.09 base | 0.38 / 0.12 base |
| Sound settings | One ON/OFF switch | 0..100 slider, persisted, 0 is mute |
| Music settings | One ON/OFF switch | 0..100 slider, scales the 0.16 bed and pauses at 0 |
| Mesh fallback | Any replicated MeshPart model | Only after every mesh fetch reports `Success` |
| Long-term goals | Finite crates, drones, tech | 35 Forge Feats, +1% all yield each, nearest four shown |

## The strike plate leaves

The key was the only saturated rectangle on a screen whose subject is a blade.
It also duplicated a target that already covered the whole render. The
transparent `StrikeButton` stays, so the click path and its zero-release
latency are untouched; the corner keeps a `STRIKE  +N SM` caption that turns
gold inside the band.

Removing the plate also gives the layout back 240x64 of lower-left stage. The
heat dial and the purge key still sit above the hit layer, so their own clicks
win.

## The crit ring

`Main` previously answered a crit with `Vfx.flash`, a gold float and a
`Vfx.burst`. At speed that was a bigger hit, not a different one. The fallback
now calls `Vfx.strikeBurst(anchor, gold, 2.3, true)`, which adds a 32px gold
shockwave ring expanding to roughly 100px over 0.28s. `Sfx.crit` is unchanged
and still lands on the server event, so the sound and the shape arrive together.
The ring is skipped under reduce-motion, where the float and the flash remain.

## The crate mix

The ceremony was mixed under the anvil because the anvil is the sound the player
hears twenty-five times a minute. A crate opens once every few minutes, so it can
carry more weight without fatigue. Every layer moved up, and two new low bodies
were added: one under the landing and one under the shatter. The do-re-mi ladder
and the riser also gained level, so the phrase that resolves on the reveal is
audible over the strike loop.

The settings slider is 100% of this mix. A default of 0.8 means the new crate is
still louder than the old one at the same slider position, which is the point.

## Audio is a level

`Settings` now stores `sfxVolume` and `musicVolume` instead of booleans. A
muted old save migrates to 0; an unmuted one migrates to 0.8 SFX and 0.55 music.
The settings sheet draws two 72px rows with a 6px track, a 14px knob and a 26px
hit strip. A drag applies locally on every step and writes the latest value once
the hand settles for 120 ms, so a sweep is one action on the wire.

Music at 0 fades out and pauses; a level above 0 resumes the same loop rather
than restarting it. Verified live: setting music to 35% produced
`ForgeMusic.Volume == 0.056`, which is `0.16 * 0.35`.

## The invisible sword

`InsertService:LoadAsset` can return a Model full of MeshParts that the
experience cannot fetch. The old `applyMesh` counted the parts and returned true,
so the primitive recipe never ran and the viewport showed the stage with no
sword. `BladeModelBuilder` now scores each replicated model:

1. Gather every `MeshPart.MeshId`.
2. `ContentProvider:PreloadAsync` the ids.
3. Require `GetAssetFetchStatus == Success` for every one.
4. Only then let `meshSource` return the model.

Until that lands, the primitive blade stays on screen. `watch` fires only on a
verified asset, so the mesh still hot-swaps in place when the fetch succeeds.
A failed mesh never replaces a visible sword.

This Studio session still reports 0/26 models loaded and
`Requester does not have permission for Asset`, so the fallback is what renders
here. The fix is for the live case where a model replicates but its mesh does
not render.

## Forge Feats

The next-goal rail could return nil once every crate and drone was open and the
tech tree was maxed. The research notes agree on the failure: an incremental
without a visible next goal is a number going up in an empty room. The answer
here is not another currency. It is thirty-five one-time feats drawn from
counters the save already keeps:

| Family | Count | Source |
| --- | --- | --- |
| Fortune | 6 | lifetime Star-Matter |
| Cores | 5 | lifetime Quantum Cores |
| Ascension | 4 | ascension count |
| Tech | 4 | total tech levels |
| Mastery | 5 | distinct blades, max rank |
| Codex | 7 | discoveries, completed sigil sets |
| Fleet | 4 | total drones |

Every feat is +1% to click and drone yield, so full completion is +35%. That is
deliberately under one blade step: feats give direction, not a replacement for
the ladder. The Tech section carries a gold FORGE FEATS card with the count, the
bonus, a progress bar and the four nearest incomplete goals. `NextGoal` adds the
nearest feat as a candidate, so the rail foot still has an answer after the tree
is finished.

The sources behind that choice: Anthony Pecorella's *The Math of Idle Games*
(prestige should reset toward a visible next target), the incremental design
codex's "no unlock deserts" rule, and RoClicks' next-goal pill pattern. All three
point at the same thing: show one explicit next target, and make the endgame a
milestone rather than a bigger number.

## Verification

- `selene src`: 0 errors, 0 warnings, 0 parse errors.
- `rojo build`: succeeds.
- Studio, Client: `StrikeKey` absent, `StrikeButton` present, blade viewport has
  37 primitive parts.
- Studio, Client: settings sheet opens with `80%` and `55%` readouts, both
  sliders drag and persist through the server (`sfxVolume 0.1`, `musicVolume
  0.35` observed in the next payload).
- Studio, Client: Tech section shows `FORGE FEATS`, `0 / 35`,
  `PERMANENT +0% ALL YIELD`, and four nearest goals.
- Studio, Server: DataStore is still in mock mode (`HTTP 401`), and all 26 blade
  meshes still fail `LoadAsset` with `Requester does not have permission for
  Asset`. Neither blocks the primitive path; both remain live-deploy checks.

## Still open

- Publish and verify the mesh path where the universe grants resolve.
- The 22 VFX sheets are still unuploaded.
- No live Robux purchase has tested the post-receipt `BOUGHT` flip.
- The crate gates and the 18-second roll floor have not been played end to end.
- No speaker check of the new crate mix; the levels are measured, not heard.
