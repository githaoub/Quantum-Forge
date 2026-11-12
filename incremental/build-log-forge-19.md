---
type: build-log
status: shipped in Studio, not yet published
updated: 2026-11-12
aliases:
  - forge-19
tags:
  - build-log
  - forge
  - onboarding
  - tutorial
---

# Forge 19 - The guide is a note beside the control

The first join had one card with one key and no lesson in between. The old
spotlight chain was deleted years of design ago for dimming the screen and
interrupting the game, so the first two minutes were being taught by nothing.
This pass rebuilds the guide as eight coach notes: a work-order card that never
covers the screen, a gold marker on the exact control, and one escape hatch on
every step.

## What changed

| Surface | Before | After |
| --- | --- | --- |
| First join | One welcome card, CTA opened the handbook | Eight coach notes anchored to the live controls |
| Screen treatment | Dimmed scrim, centred 480x300 plate | No scrim, no dim, no blocking layer |
| Marker | `TutorialHighlightLayer` ring at `ZIndex 50` | Ring at `ZIndex 21`, brackets for the forge stage |
| Skip | CTA only | `SKIP` on every card, top-bar `GUIDE` becomes `SKIP` |
| Heat during the purge lesson | Cooled while the player read | Frozen at the vent line by `tutorialHold` |
| Auto-vent during the lesson | Fired at the line, swallowing the purge | Suppressed while the hold is armed |
| Handbook rail foot | `SKY + METAL: LIHFOLK` | `REPLAY VISUAL GUIDE` |
| Replay while running | Not possible, no state | Reads `GUIDE RUNNING`, inert |

## The eight notes

1. `STRIKE THE BLADE` - four corner brackets on the stage; advance at 85 heat.
2. `PURGE THE CORE` - ring on the purge key; advance on the `vent` event.
3. `SAVE FOR A DRONE` - ring on the heat block; advance when Aether covers the
   first rung.
4. `OPEN THE FLEET` - ring on the rail tab; advance when that tab is active.
5. `BUILD A DRONE` - ring on `BuyDrone`; advance when the fleet count grows.
6. `OPEN THE CRATES` - ring on the rail tab; advance when that tab is active.
7. `ROLL A BLADE` - ring on `RollOne`; advance when the blade count grows.
8. `THE LOOP IS YOURS` - no marker, `FINISH` ends the run.

Every price and threshold is read at paint time: `Config.VentThreshold` for the
heat copy, `fleet[1].cost` for the drone, `forgeCosts[crate].one` for the roll.
The bodies swap between "you can afford it" and "here is what it costs" without
the card changing shape.

The card is placed relative to the marker: right of a rail tab, left of a small
key, inside the stage's empty top-left corner, and clamped to the canvas. The
closing note stays in the previous note's spot instead of hopping onto another
live control. Targets resolve by name every 100ms, and a target on a hidden
section drops the marker rather than pointing at an empty stretch of panel.

## The freeze

The requirement was literal: step 2 must hold the gauge so it can neither rise
nor fall until the player presses PURGE. That cannot live on the client, because
`ForgeService.strike` and the heartbeat both write `state.heat`.

`tutorialHold` arms a 120-second window per player. While armed:

- `strike` caps the next heat at `math.max(Config.VentThreshold, state.heat)`, so
  a cold gauge climbs to 85 and stops, and a gauge already above the line does
  not get pulled down by a strike.
- the heartbeat skips decay once heat is at the line, so the bar is genuinely
  frozen while the note is read.
- `autoVent` is suppressed, otherwise the pass would purge the lesson away before
  the player ever sees the key.
- the sweet-spot multiplier is withheld. A frozen 85 is the top of the 65..85
  band, and without this rule any client could hold a permanent 2.5x.

The hold clears on the real vent, on skip, on leave, and on expiry. Observed in
Studio: 85 after three idle seconds, still 85 after eight more strikes, Aether
still 0 (auto-vent did not fire), then `+6 Aether` and step 3 on the purge.

## The handbook key

The rail's bottom strip used to end in the LihFolk credit. It is now a 232x40
gold plate that closes the book and restarts the notes. `HandbookView` does not
require `TutorialController`; `Main` wires `onReplayGuide`, which keeps the
dependency one-way. While a run is live the key is painted `locked` with the
label `GUIDE RUNNING` and the handler refuses, so two runs cannot overlap.

`guideSeen` and `tutorialCompleted` keep their old meaning and their one-time
reward. A replay reads both as already true and sends neither.

## Verification

- `selene src`: 0 errors, 0 warnings, 0 parse errors.
- `rojo build`: succeeds.
- Studio, Client, fresh join: the starter card is dismissed, then the first note
  lands on the stage with four gold brackets and the card in the top-left.
- Studio, Client: 42 strikes reach exactly 85; step 2 opens, the gauge holds at
  85 through three idle seconds and eight extra strikes, and auto-vent does not
  fire on an account that owns it.
- Studio, Client: pressing the real purge key (`VentStrip`) pays `+6 Aether` and
  advances to step 3; the heat block gets the ring.
- Studio, Client: FLEET tab -> step 5, `BUILD 1` -> step 6, CRATES tab -> step 7,
  `ROLL` -> step 8 with `FINISH`.
- Studio, Client: `FINISH` sets `guideSeen` and `tutorialCompleted` true, hides
  the card and pays the tutorial reward.
- Studio, Client: handbook shows `REPLAY VISUAL GUIDE`, no `HandbookCredit`; the
  press closes the book and restarts at step 1; with a run live the same key
  reads `GUIDE RUNNING` and does nothing.
- Studio, Client: top-bar `GUIDE` reads `SKIP` during a run and ends it.

## Still open

- The dev account owns every pass, so the fresh-account path without auto-vent
  has not been run end to end. The suppression path is the one that was played.
- No touch-device check of the card placement. The card and marker are clamped
  to the canvas, but a phone's narrower canvas has not been seen.
- DataStore is still in mock mode (`HTTP 401`), and all 26 blade meshes still
  fail `LoadAsset` with `Requester does not have permission for Asset`.
- The 22 VFX sheets are still unuploaded.
- No live Robux purchase has tested the post-receipt `BOUGHT` flip.
- The crate gates and the 18-second roll floor have not been played end to end.
