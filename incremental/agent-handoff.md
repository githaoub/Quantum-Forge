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
syncs `src/` into that open place. Forge 36 is saved there as place version
345. That save is not a publish: live players still get the last published
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

Forge 36 is the store and tech pass. The store no longer sells currency: the
Starter Pack grants twenty minutes of 2x and a first-purchase-only +5% income,
Overdrive stacks by +1x per charge (ten charges are x11), and Express Salvage is
a permanent 25% expedition cut. The false `NO CURRENCY PACKS` chip is gone, the
`2x Star-Matter` card is `2x Income`, and the card copy no longer names a
currency. Tech is now a gated graph with short tiles, neutral connectors and a
300px inspector; the gated tile carries a lock and the inspector prints
`REQUIRES <PARENT> LV <n>`. The codex tab strip and cell bars lost their
decorative accents. See `incremental/build-log-forge-36.md`, ADR-129,
ADR-130 and ADR-131. The save is place version 345, not published.

The live Marketplace listing is still named `2x Star-Matter`. The in-game card
is `2x Income`. Rename the listing in the Creator Dashboard if the purchase
prompt must match; do not change the name in `scripts/create_store_items.py`
first, because the script looks listings up by name and would create a second
pass.

Forge 35 remains the onboarding pass: the first-join guide has five steps and
teaches both currencies. Step 2's ring follows the job (blade while the bar is
short, purge key at the line), and it advances on the vent alone, which removes
the 6.8-versus-7 Aether dead end. Step 3 names the live drone price and opens
FLEET after the 0.9 s beat. Step 4 names the live standard crate price, opens
CRATES, rings `ROLL` and advances on a new vault copy. Step 5 hands the player
to the GUIDE section and promises a replay. Replays skip the two purchase
lessons. See `incremental/build-log-forge-35.md` and ADR-128.

`incremental/monetization-review.md` was the honest read of the store. Forge 36
addresses four of its seven findings: the false claims, the Starter Pack, the
Overdrive ceiling and the Express Salvage timer skip. The VIP reprice, an
expression product beyond the VIP trail, a season track and measurement remain
open. The review is still the source for the next pricing decision.

Forge 34 remains the currency pass: a currency unit is a mark, not a word, and
the marks are the uploaded top-bar art. The Fleet rack has five spinning 38px
hull previews and its buy keys read `BUILD 1` / `LOCKED` over an aether price or
`110 DRONES REQUIRED`. The purge key is a red icon plate with the aether payout
on its own line. `ForgeView` converts `InputObject.Position` to a Vector2,
which restores the cursor payout, flash, sound and crit for a real mouse press.
See `incremental/build-log-forge-34.md`. That save was place version 333.

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

Known gaps:

- DataStore writes return 401 here; the profile runs MOCK, so nothing persists
  across sessions. Every Forge 36 grant was verified in-session only.
- The purchase prompt does not render in this Studio session. No Starter,
  Overdrive, Express or VIP transaction was tested end to end.
- Ten live Overdrive charges were not purchased. The helper and payload path
  returned 2, 3 and 11 for 1, 2 and 10 charges; the receipt path was not driven.
- The gated and affordable tech states were painted through the Studio preview
  seam on a maxed seeded profile. A natural low-level account has not walked
  the tree.
- No human visual pass on the Forge 36 store, tech or codex screens yet. The
  screenshots exist; density and the lock marks are still a person's call.
- A true clean-profile first-join walk. The Forge 35 drone and crate cards were
  rendered with temporary forced gates because the seeded profile already owned
  a drone and four copies; the gates were restored before the save.
- A two-client trade reproduced `NO TRADE OPEN` before the polling fix. The
  fixed client has not been driven through a full offer, accept and commit.
- A gamepad selection pass. The focus restore is code-verified only.
- Blade meshes fail asset permission and fall back to primitive recipes.
- A failed image is indistinguishable from a slow one, so `LOADING...` can sit
  for eight seconds on an asset that will never load.
- 22 VFX sheets are unuploaded, the 420px crit disc is not live, and no human
  has heard the crate sound kit.
- The console still reports many `ContentId ... failed due to: Asset type does
  not match requested type` errors.
- Touch, gamepad, a real charged 10-pull, a five-minute expedition settle, 1B
  Star-Matter and the no-dev-pass path remain unverified.
