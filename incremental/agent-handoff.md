---
type: reference
status: live
updated: 2026-11-12
aliases:
  - agent-handoff
tags:
  - process
---

# Agent handoff

Read this before starting work on Quantum Forge.

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

Forge 30 (ADR-124) is the live pass: `VIEW` opens the full player card, the
trade desk takes Aether and shows every owned copy, badge art waits behind
`LOADING...`, every overlay banner uses its key's mark, the forge is a 16:10
stage with a 400px console, and the ascend and daily keys scale when they are
actionable.

Known gaps, unchanged:

- DataStore writes return 401 here; the profile runs MOCK, so nothing persists
  across sessions and the first-join cards repeat on every Studio play.
- Only one player has ever been in the server, so roster selection, cheer and a
  live trade have never been exercised with two real clients.
- The purchase prompt does not render in this Studio session.
- Blade meshes fail asset permission and fall back to primitive recipes.
- A failed image is indistinguishable from a slow one, so `LOADING...` can sit
  for eight seconds on an asset that will never load.
