---
type: build-log
status: shipped in Studio, not yet published
updated: 2026-11-12
aliases:
  - forge-23
tags:
  - build-log
  - forge
  - audio
  - vfx
---

# Forge 23 - On the press frame, a chord on the green bar, and a shake you can see

Three complaints, one cause each: the click sounded late, the green bar sounded
like the normal click, and the shake was only rattling the blade inside its frame.

## What changed

| Surface | Before | After |
| --- | --- | --- |
| Sound triggering | 24 slots with `SoundId` rewritten per cue | One pool per sample, `SoundId` set once |
| Decoder | Loaded on first use of each slot | `Sfx.preload()` warms every pool at boot |
| Green bar | Same sample as a click, pitched up | `SWEET`, a fifth-stacked chord with a thump |
| Streak | Playback speed drift | Two semitones per in-band point, capped at five |
| Shake host | Blade viewport only, 4px | Canvas plus viewport |
| Normal click | 0 screen px | 7 design px |
| Green bar | 0 screen px | 9 design px |
| Crit | 0 screen px | 11 design px |
| Forge result | 0 screen px | 15 design px |
| Crate landing | 0 screen px | 8 design px |

## Why it felt late

`Sfx` used to own 24 `Sound` instances and set `sound.SoundId = asset` on every
call. Reassigning `SoundId` drops the decoded buffer for that instance, so the next
`Play()` could wait while the asset resolved. With four uploaded samples and six
client ones cycling through the same 24 slots, that happened constantly.

The kit now keeps a pool per sample: 10 `STRIKE`, 5 `SWEET`, 3 `CRIT`, 6 `ANVIL`,
6 `PING`, 6 `CLICK`. The `SoundId` is assigned when the pool is built and never
touched again, and `Sfx.preload()` runs during boot. Measured in Studio: calling
`Sfx.strike()` and reading `IsPlaying` in the same frame now returns a live slot.

## The green bar

`SWEET` is a different instrument, not a louder one. It stacks a root, a fifth, an
octave and a twelfth with a low thump under it and a 90ms glint on top, so the
green bar is a chord where the normal click is a single note. Each in-band point
lifts the whole chord two semitones (capped at five), so a clean run climbs.

## The shake

`Vfx.shakeScreen` shakes the canvas. Every panel is a child of it, so the HUD takes
the hit and the wash layer stays still. The blade viewport still jitters, at 6px per
unit of strength, because it is full-bleed inside a clipped frame and a large offset
exposes the frame edge.

Measured in Studio on a forced crit: the canvas offset moved for 14 frames with a
peak of 8 design pixels, then returned exactly to rest.

## Verification

- `selene src`: 0 errors, 0 warnings, 0 parse errors.
- `rojo build`: succeeds.
- Studio, Client: 36 `SfxSlot` instances exist at boot across six sample pools.
- Studio, Client: `Sfx.strike()` puts a slot in `IsPlaying` on the same frame.
- Studio, Client: `Sfx.strike(true, 4)` plays `SWEET` at 1.56x plus one `PING`.
- Studio, Client: all four uploaded samples preload at 0.50 / 0.72 / 1.05 / 0.45s.
- Studio, Server to Client: a forced crit shakes the canvas for 14 frames, peak 8
  design pixels, then restores the rest position.

## Still open

- The queue of new samples was checked by classifier and measurement, not by a
  human ear on the final mix.
- Screen shake on touch and gamepad has not been checked.
- The 420px crit sprite sheet is still unuploaded; the ring is procedural.
