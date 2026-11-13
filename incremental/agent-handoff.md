---
type: reference
status: live
updated: 2026-11-13
aliases:
  - agent-handoff
tags:
  - process
---

# Agent handoff

Read this before starting work on Quantum Forge.

## Target

The real game is `Quantum Forge`, place `102663811434617`, universe
`10775534186`, held in Team Create. Rojo serve (`rojo serve`, port 34872)
syncs `src/` into that open place. Forge 34 is saved there as place version
333. That save is not a publish: live players still get the last published
version until the owner presses Publish in Studio. `verify.rbxlx` is a local
build with a Baseplate, not a copy of the real place, so never publish it over
the game.

## Load these skills first

The owner has a large skill library and expects the relevant ones to be active,
not just available. After a compaction or in a new session, load them again:

- `roblox-collaboration-mode` first, then the domain skills.
- `roblox-gui` for HUD, menus, dialogs and layout.
- `roblox-game-design` for core loop and FTUE work.
- `roblox-player-psychology` for the first minute, rewards and social proof.
- `roblox-networking` before adding a remote or touching server authority.
- `roblox-studio-mcp` for the Studio cycle.
- `humanizer` before writing player-facing copy or docs.
- `design-taste-frontend` for visual judgement and copy discipline.

The owner also asked for good results, real Studio evidence and a git
checkpoint before large structural changes.

## Current state

Forge 34 is the live pass: a currency unit is a mark, not a word, and the
marks are the uploaded top-bar art. The Fleet rack has five spinning 38px hull
previews and its buy keys read `BUILD 1` / `LOCKED` over an aether price or
`110 DRONES REQUIRED`. The purge key is a red icon plate with the aether payout
on its own line. `ForgeView` converts `InputObject.Position` to a Vector2,
which restores the cursor payout, flash, sound and crit for a real mouse press.
See `incremental/build-log-forge-34.md`. The save is place version 333.

Forge 33 remains the feedback pass: a ready ASCEND or DAILY lights from inside
the plate (accent wash, 2 to 5px ring, 5% plate scale, 6% mark scale), the
strike payout floats from the cursor at 22px, and the crit lands on the blade
stage in a box measured to fit its 46px type. See
`incremental/build-log-forge-33.md`.

Forge 32 remains the page refactor: fleet, runes and tech are full-bleed pages
instead of two-column row stacks. Fleet is a hangar (hull stage, five-row rack,
service deck), runes is a bay and a 2x2 card shelf, and tech is three lanes with
spines and a core/feat sidebar. The top bar repaints every key when the compact
line changes, button faces truncate, and the focus ring restores the stroke it
found instead of a fixed 2px. See `incremental/build-log-forge-32.md`.

The same code was played in the real place: no label failed `TextFits` on any
of the three pages, the compact top bar keys sat inside the bar, and the focus
probe restored a 1px stroke after a 3px white focus ring. Forge 32 was saved as
place version 321.

Forge 31 remains the behind-the-scenes pass: `Main.client` calls
`TradeView.step`, a 4:3 tablet grows the canvas height instead of letterboxing,
the phone top bar switches to 84px keys, and the drone lesson points at PURGE
until the first drone is affordable. See `incremental/build-log-forge-31.md`.

Forge 30 (ADR-124) remains the visual pass: `VIEW` opens the full player card,
the trade desk takes Aether and shows every owned copy, badge art waits behind
`LOADING...`, every overlay banner uses its key's mark, the forge is a 16:10
stage with a 400px console, and the ascend and daily keys scale when they are
actionable.

Known gaps, unchanged:

- No human visual pass on the Forge 32 pages or the Forge 33 pulses yet.
  Geometry, text fit and the pulse envelope were measured in Studio; whether the
  glow is too loud on a real screen has not been judged by a person.
- A gamepad selection pass. The focus restore is code-verified only.
- DataStore writes return 401 here; the profile runs MOCK, so nothing persists
  across sessions and the first-join cards repeat on every Studio play.
- A two-client trade reproduced `NO TRADE OPEN` before the polling fix. The
  fixed client has not been driven through a full offer, accept and commit.
- The purchase prompt does not render in this Studio session.
- Blade meshes fail asset permission and fall back to primitive recipes.
- A failed image is indistinguishable from a slow one, so `LOADING...` can sit
  for eight seconds on an asset that will never load.
