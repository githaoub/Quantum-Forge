# Design Decisions

An ADR-style log of every decision that had a real alternative, why this branch was
taken, and what it costs. The costs are listed because a decision without a
downside is usually a decision that was not examined.

---

## ADR-001 — Star-Matter is a plain double, not a mantissa/exponent struct

**Context.** Incremental games reach absurd numbers, and the textbook solution is a
`BigNum { mantissa, exponent }` struct with overloaded arithmetic. That is what
most tutorials do, and it is what the original spec implied.

**Decision.** Use plain IEEE-754 doubles and a suffix table. No struct.

**Why.**

- Doubles are exact to `2^53 ≈ 9.0e15` and finite to `1.8e308`. The economy's
  designed ceiling is `1.4e13` for multipliers and `1.5e13` total spend. The game
  would have to be rebalanced by nine orders of magnitude before precision was the
  limiting factor.
- The hot path is the click handler. A struct means a table allocation per
  addition, and clicking generates 25 operations/second/player, plus drone income,
  plus offline grants. That is a lot of garbage for zero benefit.
- The struct's real value is formatting huge numbers. A suffix table does that in
  one `log10` and one table index, and it is *easier* to tune because the ladder is
  a literal list you can read.

**What it costs.** Above `1e15`, integer increments below the unit in the last
place silently vanish. In practice the player is earning `1e17` per click by then,
so the missing `1` is not observable. If a future feature needs exact large
integers — leaderboard ranks, currency ledgers — it should store a string or a
separate `number`, not retrofit a BigNum through the economy.

**Guard.** `NumberUtil.sanitize` clamps every value on load and on every add, so a
corrupted save containing `NaN` or `inf` cannot propagate into the economy. That
protects against the one failure mode doubles actually have.

---

## ADR-002 — Figma is not in the critical path

**Context.** The original spec assumed designing the UI in Figma and importing it.

**Decision.** The UI is built entirely in Luau. Figma is not used at all. Icons are
generated locally by `scripts/generate_icons.py`.

**Why.**

- The available Figma seat cannot write to files. A View-only seat can read a
  design but not produce one, so the tool could not do the one job it was in the
  pipeline for.
- The call budget is 20/month. A single screen of a game like this takes far more
  than 20 design/read cycles, and running out mid-build would block the work
  entirely.
- Luau-authored UI is the only version that can be diffed, reviewed, and modified
  by an agent or a human without a round trip through a design tool. A `.fig` is a
  binary blob; a `UiKit.luau` is a file you can read.
- The generators are deterministic and offline. Icons can be regenerated on a
  machine with no network, no API key, and no Figma account.

**What it costs.** No designer can iterate visually without running the game. The
mitigation is the `contact_sheet.png` output, which renders all 40 icons at once for
review without launching Studio.

---

## ADR-003 — Fixed 1280x720 canvas with a `UIScale` fit

**Context.** Roblox UIs are usually authored with `UDim2` scale sizes that reflow at
every screen size. That works for simple layouts and falls apart for dense,
panel-based game UIs: text wraps differently, gutters collapse, and a layout that
looks right on desktop looks broken on a phone.

**Decision.** Author every frame at a fixed `1280x720` design resolution using
pixel offsets, then scale the whole tree with a single `UIScale` whose factor is
`min(viewportWidth/1280, viewportHeight/720)`. A letterbox backdrop fills the
remainder.

**Why.**

- One layout, one set of numbers. A panel that is `400px` wide is `400px` wide
  everywhere; the scale factor handles the device.
- `min()` instead of `max()` guarantees the whole UI is always visible. `max()`
  would fill the screen but crop the edges on aspect ratios narrower than 16:9.
- It matches how the rest of the industry builds game HUDs — design at a reference
  resolution, scale the result.

**What it costs.** Nothing reflows: a player on an unusual aspect ratio gets
letterboxing rather than a denser layout. On a very tall phone the UI is smaller
than it could be. This is the correct trade for a game whose UI is a handful of
fixed panels and a large viewport.

**Consequence.** All layout math in `Main.client.luau` is in design pixels. The one
place this shows is `FORGE_WIDTH = 1280 - 24*2 - GAP - 400`, which is a constant at
author time and scaled at runtime.

---

## ADR-004 — In-house session locking instead of ProfileService

**Context.** `ProfileService` (and its successor, `ProfileStore`) is the community
standard for Roblox data persistence. It handles session locking, which prevents two
servers from saving the same player's data concurrently and silently duplicating or
rolling back progress.

**Decision.** Implement session locking directly in `DataManager` using the same
primitive those libraries use: an atomic `UpdateAsync` acquire that writes a
`sessionJobId` and a `sessionTimestamp`, plus a heartbeat that refreshes the
timestamp and a release on leave.

**Why.**

- The project has no Wally dependency and no build step beyond Rojo. Adding a
  package manager to pull one module is a real cost: another tool to install,
  another lockfile, another upgrade path.
- The locking protocol is roughly forty lines. It is not the part of `ProfileStore`
  that is hard — the hard part is the reconciliation logic, which this game does not
  need because its schema is flat and every field has a default.
- Owning the save format means the mock can be swapped in cleanly: when Studio has
  no API access, `DataManager` falls back to an in-memory store with the same
  interface, so the game is playable in a fresh place file with no setup.

**What it costs.** The implementation is less battle-tested than `ProfileStore`.
Specifically, it does not implement the "steal after N seconds of a stale
heartbeat" heuristic as carefully — it uses a timeout plus a force-acquire path.
For a game at this scale, on Roblox's infrastructure, that is sufficient; at
hundreds of thousands of CCU with a live-ops team it would be worth revisiting.

**Guard.** If the acquire fails, the player is kicked with a readable message rather
than loaded on top of another server's session. A duplicated session is worse than
a failed join.

---

## ADR-005 — Blades are primitive chains, not boxes

**Context.** A blade could be one `Part` with a texture, or a mesh from the
marketplace, or a procedural stack of primitives.

**Decision.** Each blade is a chain of parts following a parametric spine
`p(t) = (curve·t², length·t)` with per-shape width, taper, and guard parameters.

**Why.**

- One code path yields five silhouettes (`straight`, `curved`, `glaive`, `scythe`,
  `greatsword`) by changing six numbers. A box-per-blade approach yields five
  identical rectangles.
- No asset IDs means no upload dependency, no moderation queue, and no risk of a
  marketplace asset being deleted out from under the game.
- The shape is data. `BladeRegistry` declares `shape = "scythe"` and the preview
  code knows what that means; adding a sixth shape is one branch, not one model.

**What it costs.** A primitive chain is more parts than a mesh — a greatsword is
around a dozen instances. At 25 blades with only the equipped one rendered per
character, that is irrelevant. It also cannot express surface detail the way a
textured mesh can; the icons in `assets/generated/` carry the visual identity that
the 3D preview cannot.

---

## ADR-006 — One `TechTreeConfig.compute()` for both sides

**Context.** The server must derive authoritative stats from tech levels. The client
must preview "what happens if I buy this" before sending the request. The naive
implementation duplicates the formula in both places, and the two drift.

**Decision.** `TechTreeConfig.compute(levels)` is a shared module. The server calls
it to enforce; the client calls it to preview. No stat is derived anywhere else.

**Why.**

- Drift between a preview and the real value is the single most common bug in
  upgrade UIs. It is also the most damaging: the player is told they will get
  `+25%` and gets `+20%`.
- The module is pure — a levels table in, a stats table out. No side effects, no
  service references, safe to require from either side.
- It makes the effect enum declarative. Adding a node means adding an entry to
  `NODES` and one branch in `compute`; nothing else needs to know.

**What it costs.** The client downloads the full tree definition. That is a few
kilobytes and it is data the UI needs anyway. It also means tech effects cannot be
secret — which is fine for a game where every node is visible in the UI.

---

## ADR-007 — State sync is batched at 10 Hz, never per frame

**Context.** Clicking, drones, heat, and auto-clicks all change state dozens of
times per second. The obvious implementation fires a remote on every change.

**Decision.** One `StateSync` remote per player, coalesced: `Net.setPayloadProvider`
returns the current payload, and `Net.step` sends at most one per `1/Config.SyncHz`
seconds. Discrete moments that need to feel immediate (a crit, a vent, an overheat)
go through a separate `Event` remote.

**Why.**

- 40 players × 30 state changes/second is 1,200 remotes/second. Roblox will happily
  accept that right up until it will not. Batching makes the cost constant and
  independent of how many things changed.
- 10 Hz is above the threshold where a number visibly lags. The heat gauge is the
  only continuously animated value and it is smoothed client-side, so it does not
  depend on the sync rate at all.
- Splitting "state" from "juice" keeps the payload small. The payload is what must
  be consistent; the effects are what must be *fast*. Conflating them means every
  crit has to wait for the next tick.

**What it costs.** Up to 100 ms of latency on anything that is not an event. That is
why clicking is predicted locally (ADR-008) rather than waiting for the server.

**Consequence.** `Types.SyncPayload` is the contract between the two halves of the
game. Changing a field means changing both `ProgressionService.buildPayload` and
every client consumer; there is no schema validation, so the type annotation is the
only guard.

---

## ADR-008 — Optimistic click prediction with a pending buffer

**Context.** At 10 Hz sync, an unpredicted click would take up to 100 ms to move the
number on screen. That is enough to feel broken in a game whose entire loop is
clicking.

**Decision.** On click, the client immediately adds the predicted yield to a
`pendingCredit` buffer rendered on top of the last known server value. On the next
sync, the server's delta is compared against the buffer and the buffer is reduced by
the confirmed amount (clamped at zero). The displayed value is always
`server.sm + pendingCredit`.

**Why.**

- The number responds in one frame without ever drifting: the client is not
  computing an independent total, it is displaying *the server's total plus a claim
  that has not landed yet*. When the claim lands, the buffer shrinks by exactly that
  amount and the total does not move.
- Clamping to zero handles the case where the server rejected a click (rate limit,
  lockout). The buffer cannot go negative, and the next click re-syncs.
- It is a buffer, not an interpolation. Interpolating toward a target makes the
  number feel mushy and can never be exactly right; a buffer is exact by
  construction.

**What it costs.** If the client's prediction disagrees with the server's maths, the
number visibly snaps back. That is why the prediction is a *mirror* of the server
formula (ADR-009) rather than an approximation.

---

## ADR-009 — Client prediction mirrors the exact server strike formula

**Context.** Predicting a click means predicting the sweet-spot bonus, the crit
roll, and the tech multipliers. The lazy approach predicts the base yield and lets
the server add the bonus.

**Decision.** `ForgeView.strike` recomputes the same expression the server uses:
`clickYield × (bandMult if in band) × (critMult if crit rolled locally)`.

**Why.**

- If the client predicted only the base yield, the number would jump *up* on every
  sweet-spot click when the server value arrived, and jump *down* on every miss.
  The player would read that as lag even though it is not.
- The client knows the band, the tech levels, and the blade multiplier — everything
  needed. Predicting the full amount costs nothing extra.
- Crits are rolled independently on both sides. The client's roll is cosmetic; the
  server's roll is authoritative. A mismatch shows as a different number, not as
  lost income, because the buffer reconciles against the server total.

**What it costs.** The formula now exists twice — once in `ProgressionService.strike`,
once in `ForgeView.strike`. This is the one deliberate duplication in the codebase,
and it is deliberate because the alternative (a shared `predictStrike` function) would
still need the client to pass in identical inputs, so the duplication is in the
plumbing, not the risk. The two are checked against each other by the
reconciliation: if they diverge, the number snaps, which is immediately visible.

---

## ADR-010 — Ascension is gated behind a confirmation modal

**Context.** Ascending wipes Star-Matter, Aether, drones, and all owned blades. It
is the single destructive action in the game.

**Decision.** The Ascend button opens a modal that states exactly what is lost and
what is gained, and the confirm button is a distinct press.

**Why.**

- The action is irreversible and, unlike most destructive actions, it is *intended*
  to be repeated. A player will press it dozens of times over the game's life, which
  means the muscle memory to press it will also be present when they do not mean to.
- Stating the earned Cores on the modal turns the decision into an informed one.
  A player should never have to compute `floor((runSM/1e9)^0.5)` in their head.
- It is the only place in the UI where a click destroys progress, so it earns the
  extra click.

**What it costs.** Two clicks instead of one, every prestige. At twenty prestiges
per session that is twenty seconds. Acceptable for the insurance.

---

## ADR-011 — `pcall` lives at the network boundary, not in every handler

**Context.** Any remote handler can throw — a nil profile mid-load, a malformed
payload, a stale blade id. A thrown error inside one handler can take down the
`OnServerEvent` connection for every player on the server.

**Decision.** `Net` wraps every action handler and the request function in a single
`pcall`, logs one line with the action name and player, and returns. Individual
handlers do not wrap themselves.

**Why.**

- One boundary, one log format, one place to change it.
- Per-handler `pcall` is boilerplate that will eventually be forgotten in exactly the
  handler that needed it most. The boundary cannot be forgotten because there is
  nowhere else to put the code.
- It keeps handlers readable: they return `(boolean, reason)` and the boundary
  decides what a failure means.

**What it costs.** A handler cannot distinguish "my error" from "a dependency's
error" at the point of failure. The warn line is the compensation, and it includes
the action name so the log points at the culprit.

---

## ADR-012 — Aura is server-created; the UI is client-only

**Context.** The equipped blade has a visible aura. The obvious implementation is a
local `Highlight` and `ParticleEmitter` on the local character.

**Decision.** `LobbyService` creates the aura server-side and repaints it on a shared
1 Hz loop. Only the local UI is client-authored.

**Why.**

- A client-created aura is invisible to everyone else. Other players are the entire
  point of a cosmetic — an aura nobody sees is not a reward.
- Server-side creation also means the server decides what the aura looks like, so a
  modified client cannot fake ownership.

**What it costs.** One repaint loop for all players rather than one per player, and
newly joined players see the aura up to a second late. Both are invisible in
practice.

---

## ADR-013 — Icons are generated locally, then optionally uploaded

**Context.** The game needs 40 images. They could be hand-drawn, bought, or
generated.

**Decision.** `scripts/generate_icons.py` draws them with Pillow at build time;
`scripts/upload_assets.py` pushes them to Roblox and rewrites `AssetManifest.luau`.
Neither is required to play: the manifest defaults to `rbxassetid://0` and the UI
falls back to vector glyphs.

**Why.**

- The blade catalogue is the source of truth. The script *parses*
  `BladeRegistry.luau`, so adding a blade produces a matching icon with no extra
  step and no chance of drift.
- Local generation is deterministic and offline — no API key, no moderation queue,
  no cost, and it runs on a machine that has never seen Studio.
- Making the upload optional is what keeps a fresh clone playable. A contributor
  can clone, `rojo serve`, and play without owning a single asset.

**What it costs.** The icons are geometric, not painted. They read well at 64–96 px
in a UI, which is all they are asked to do; they would not survive being used as
store-page art.

---

## ADR-014 — `selene.toml` pins `std = "roblox"`

**Context.** Running `selene src/` on a Luau codebase reported ~3,000 parse errors
on type annotations.

**Decision.** Ship a `selene.toml` with `std = "roblox"`.

**Why.** Without it, selene parses as Lua 5.1 and every `: Type` annotation is a
syntax error. The file is not optional config — it is what makes the linter able to
read the language at all.

**What it costs.** Nothing. It is three lines.

**Consequence.** Lint is clean (0 errors, 0 warnings), which means a nonzero exit
from `selene` is always a real finding rather than known noise. That property is
worth protecting: do not add blanket `allow` rules to make a specific error go away.

---

## ADR-015 — The offline cap is 8 hours at 50%

**Context.** Offline earnings can be the most generous or the most abusive system in
an incremental. Roblox's audience returns on irregular schedules.

**Decision.** `min(elapsed, 8h) × passiveYield × 0.5 × offlineMult`.

**Why.**

- Capping at 8 hours means a player who sleeps gets a full reward and a player who
  quits for a month gets the same one. The cap protects the curve from being
  skipped by absence.
- 50% is the rate that makes returning feel like a gift rather than a punishment,
  without making it correct to leave. `offline_core` can raise it to 150%, which
  gives that node a clear identity.
- Basing it on **drone** yield means offline income scales with investment already
  made. A player who never bought drones gets nothing offline, which is the correct
  incentive.

**What it costs.** A player with no drones who goes away for a weekend gets nothing.
That is intended: offline income is a return on the passive layer, not a universal
allowance.

---

## ADR-016 — `Config.Debug` gates logging, not behaviour

**Context.** Debug flags tend to accumulate branches in gameplay code.

**Decision.** `Config.Debug` controls exactly one thing: whether `log()` prints.
`Config.Debug` is `true` in the repo and must be set to `false` before publishing.

**Why.** A debug flag that changes behaviour is a flag that ships in the wrong state
and produces a game nobody tested. A flag that only silences prints is safe in
either state.

**What it costs.** Someone will forget to set it to `false` and ship verbose logs.
That is a cosmetic bug, not a gameplay one — which is the point.

---

## ADR-017 — Onboarding is a strip, not a modal, and it advances on real state

> **Superseded in part by ADR-028.** The *state predicates* and the permanent
> tracker still stand exactly as written below. The strip is no longer the teaching
> surface: five lessons now open as centred modal cards, because the strip was never
> read. The strip survives as the post-tutorial objective tracker.

**Context.** The first playtest produced a player who could click the anvil and
nothing else. The genre default is a dimmed screen with an arrow and a "Next"
button, which players skip without reading, or a silent figure-it-out opening,
which is where this project started.

**Decision.** Three things:

1. Onboarding has no modal, no dimming and no forced click. A 534x44 strip sits in
   the empty band between the top bar and the panels, and the only visual change to
   the rest of the UI is a pulsing outline on the control the current step is about.
2. A step is satisfied by *state*, not by clicking the tutorial's own button. Step
   2 reads `payload.heat >= payload.bandMin`. Step 4 reads `drones >= 1`. A player
   who forges a blade before the guide asks them to is already past that step.
3. The strip converts into a permanent objective tracker after step 5 and never
   disappears. It names the next milestone and the distance to it.

**Why.**

- The predicates make out-of-order play free. There is no "you did it wrong, start
  over" branch, and no path where a completed action is not credited.
- The strip is in dead space. It does not move the forge, the panels, or the side
  panel, so adding onboarding did not cost a single pixel of gameplay.
- A tracker that outlives the tutorial answers "what now" for the rest of the
  session, which is the question a modal tutorial leaves behind.

**What it costs.**

- About 570 lines of client code and six instance names that now have to stay
  stable (`StrikeButton`, `VentButton`, `HeatGauge`, `BuyDrone`, `Tab_*`,
  `BladeAction_*`). Renaming any of them silently disables one step.
- The guide can only teach what the sync payload exposes. A future mechanic
  without a payload field needs a payload change before the guide can mention it.
- Skipping pays the completion reward. The alternative (re-prompting on every
  rejoin) is worse for players, and the reward is 250 Star-Matter and 10 Aether,
  roughly two minutes of play. This is a deliberate choice, not an oversight.

**Guard.** `tutorialCompleted` is persisted, `claimTutorial` sets the flag before
paying, and a second call returns success without paying. The client picks tutorial
mode or tracker mode from the first payload rather than from a boot-time guess, so
a returning player never sees step 1.

---

## ADR-018 — The heat gauge is drawn as an instrument, not a progress bar

**Context.** The gauge is the only place the core mechanic is legible. A single
fill bar that goes from empty to full communicates "fill it up", which is the
opposite of the rule: the player must hold heat *between* 65 and 85.

**Decision.** Draw the track as a ruled scale. Decade ticks with heavier ticks at
50, a stroked band for the sweet spot with the multiplier printed inside it, a
needle at the exact current value, and a track stroke whose colour and thickness
change with state. The status line reads `72% · x2.50 BONUS` in the band and
`OVERHEATED · 3.2s` when locked.

**Why.**

- The band only reads as a target if there are marks around it. Without ticks, 65
  and 85 are unlabelled positions on a gradient.
- The needle answers "which way is this going", which is the question a player
  acts on. Fill height answers "how much", which is the question they already know.
- Changing the rail colour before the fill reaches the danger zone buys roughly
  half a second of warning while the player is still looking at the strike button.

**What it costs.** Roughly 20 extra instances and one update function that touches
five of them per sync tick. Both are inside a single `buildHeat` / `updateHeat`
pair, so there is one place to change and one place to break.

---

## ADR-019 — Surfaces come from a four-rung elevation ladder

**Context.** `Theme.Elevation` existed but was referenced zero times. Fifteen panel
call sites each hand-picked a fill and a transparency between 0.02 and 0.4, so a
card inside a card inside a panel read as one flat sheet: the eye had no depth cue
to tell a region from a row from a readout.

**Decision.** Four explicit rungs, each with exactly one job:

| Tier | Fill | Transparency | Use |
| --- | --- | --- | --- |
| `well` | `panelSunken` | 0.38 | A readout cut into a surface — gauge track, passive-rate strip |
| `item` | `panelSunken` | 0.08 | One discrete row in a list — blade, tech node, shop entry |
| `shell` | `panel` | 0.12 | The region a list lives in — top bar, forge, side panel |
| `raised` | `panelRaised` | 0.04 | The thing the player acts on — primary button, modal, toast |

`UiKit.panel` takes `tier` and reads fill, transparency and stroke weight from it.
Explicit `fill` / `transparency` / `strokeTransparency` still win when a call site
needs an accent tint, because a rarity colour is a semantic, not a depth.

**Why.**

- Depth is the cheapest way to make generated UI stop looking generated. Flat
  surfaces of identical opacity are the single most recognisable tell.
- `item` and `well` deliberately share a fill. What separates a row from a readout
  is depth and stroke weight, not a third grey — adding greys is how a palette
  turns to mud.
- A call site that wants a different opacity now has to say so explicitly, which
  makes the deviation visible in review instead of hiding among fifteen numbers
  that all look equally arbitrary.

**What it costs.** A rung that does not fit a new surface is a temptation to add a
fifth. The rule is that a surface either has a job on this list or it is an accent
tint on an existing rung.

---

## ADR-020 — Every animation goes through one function, and reduce-motion is real

**Context.** The accessibility ADR claimed the UI honoured the client's
reduce-motion setting. It did not: `Theme.reducedMotion()` and `Theme.tween` were
both dead code, while nineteen raw `TweenService:Create` calls animated hover,
toasts, modals, damage numbers, sparks, shake and screen wash regardless of the
setting.

**Decision.** `UiKit.tween` is the only entry point for UI animation and delegates
to `Theme.tween`, which collapses duration to zero when reduce-motion is on.
`Theme.fade` is the one documented exception: an opacity-only tween that keeps its
duration, because a fade is not motion. `Vfx` uses the distinction directly —
under reduce-motion a floating number still appears and fades but does not travel
or punch, bursts are skipped, and shake returns immediately. The lobby camera
sweep in `OrbitalLobby` is deliberately not routed through the kit: it is a world
camera move with its own timing, not UI chrome.

**Why.**

- A setting honoured in some places and not others is worse than no setting,
  because the player cannot predict what will move.
- Deleting feedback entirely (instead of stilling it) punishes the player for
  using an accessibility option. A number that appears in place and fades still
  tells them the click landed.
- One call site to audit when the motion language changes.

**What it costs.** Every future animation has to be written as
`UiKit.tween(instance, duration, goal)`, which is marginally more typing than the
service call. That is the enforcement mechanism.

---

## ADR-021 — The HUD has a loading and a stale state, not a fake zero

**Context.** The top bar painted `0` in all three currency pills before the first
sync landed. After the boot stall was fixed the UI appears instantly, which made
the lie *more* visible: a returning player sees `0` Star-Matter for as long as the
handshake takes, and `0` is a balance a real new player has.

**Decision.** Currency pills render an em dash until the first payload, then snap
to the real totals rather than counting up from the placeholder. The rate strip
doubles as the connection instrument: `LINKING…` before the first payload,
`NO SIGNAL · Ns` in warning colour when `StateStore.staleness()` exceeds three
seconds, and the normal drone/rate text otherwise. The status string is only
written to the instance when it changes.

**Why.**

- The four states of any data region are loading, empty, error and populated. This
  bar previously had two of them and pretended the loading state was `0`.
- A HUD frozen on its last number with no indication is the worst version of
  failure: the player keeps clicking into a void and blames the game.
- The strip already existed and was already the widest piece of text under the
  bar. Reusing it costs nothing and avoids a second status surface.

**What it costs.** One extra branch in the per-frame path and a cached string
comparison. The stale threshold is a judgement call at three seconds; a sync tick
is 100 ms, so three seconds is thirty missed payloads, which is unambiguous.

---

## ADR-022 - Effects are generated white-on-alpha flipbooks, and the rim is subtractive

**Context.** Every strike, vent, overheat and crit fired the same procedural
burst: a handful of GUI frames scaling up and fading out. It reads as a
placeholder because it is one. `video-02-ai-vfx-pipeline.md` asked for layered sprite
sheets with a rim, a body, a hot core and a glow; the first three implementation passes
produced hard-edged donuts, then two straight cones, then a spider of radial
needles, and each failure had the same root cause - compositing, not drawing.

**Decision.**

1. `scripts/generate_vfx.py` draws five effects as four 4x4, 512px sheets each:
   `slash`, `impact`, `vent`, `overheat`, `aura`. All sheets are pure white with
   an alpha channel, so the runtime tints them with `ImageColor3` and one upload
   covers every blade tier.
2. The rim layer is `widen(body, n) - body`, never a dilated copy of the body. A
   dilated copy composited over the body is one thick slab with a hard border -
   a drawn donut. A subtractive band lives only on the silhouette, so tinting
   the rim differently from the body produces an edge highlight instead of a
   fatter shape.
3. The glow layer is `ImageChops.lighter` of a tight blur and a wide blur. One
   radius has no falloff and reads as a flat vignette.
4. The generator measures the 4px edge margin per effect and exits non-zero on a
   violation, so a sheet that would show its own bounding box cannot ship.
5. `src/client/SpriteFx.luau` plays the sheets. `play` returns `false` for
   one-shot effects and `attach` returns `nil` for loops whenever the manifest is
   unuploaded, motion is reduced, or no layer resolved. Every caller therefore
   reads `if not SpriteFx.play(...) then Vfx.burst(...) end`, and a fresh clone
   with `rbxassetid://0` everywhere looks exactly like the build before this ADR.
6. Looping sprites (`aura`) are exempt from the `MAX_ACTIVE` eviction that
   governs clicks. An aura is placed by the game, not by the player, and evicting
   it under an autoclicker would make it blink.

**Why.**

- The failure mode this replaces was invisible in code review and obvious on
  screen. Encoding "rim = grown minus body" as a rule means the next effect does
  not have to rediscover it.
- One shared `Heartbeat` for all live sprites: clicking is unbounded, and a
  connection per strike leaks under an autoclicker.
- The manifest is annotated (`local VfxManifest = {} :: Manifest`). An inferred
  table literal with named keys is sealed, and `Sheets[effect .. "_" .. layer]`
  would not type-check in strict mode. The generator emits the annotation, so
  regenerating cannot reintroduce the bug.
- Determinism is a feature: the same script on the same machine produces
  byte-identical PNGs, which is what makes the review board a reviewable
  artefact rather than a screenshot.

**What it costs.** Twenty-five PNGs and a generator that has to be run before
upload. `aura` is the one effect with no procedural equivalent - if its sheet is
missing, the anvil simply does not gain a halo, which is a missing flourish
rather than a missing signal. The sheets are unuploaded
(`rbxassetid://0`) because `requests` is not installed here, so the shipped build
currently takes the fallback path everywhere.

---

## ADR-023 - The boot path cannot afford one throw, and remote names are keys

**Context.** Three separate playtests reported `LINKING…` forever. The HUD was
painted, the panels were there, and nothing ever arrived. Two bugs caused it, and
the first one hid the second:

1. `BladePreview.mount` set `viewport.Camera`. The ViewportFrame property is
   `CurrentCamera`; the assignment threw *inside* `ForgeView.init`, which runs
   before `StateStore.init()` at the end of `boot()`. The whole client script
   died there, so no subscription was ever made, every `StateSync` was dropped
   (`queue exhausted … 1024 events dropped`), and the HUD sat on its placeholder
   forever.
2. With that fixed, `StateStore.connect` asked for remotes with
   `Remotes.event(Config.Remotes.StateSync)`. `Config.Remotes` maps a key to its
   *class* (`StateSync = "RemoteEvent"`), so the call waited ten seconds for a
   child literally named `RemoteEvent` and gave up. `StateStore.linked` was then
   set to `true` regardless, which is why the boot print claimed a connection
   that did not exist.

**Decision.**

- Fix the property (`CurrentCamera`), and give the camera a parent so it tears
  down with the viewport.
- Look remotes up by the key that names them: `Remotes.event("StateSync")`.
  `Net.init` creates each instance named after its config key, so the key *is*
  the name.
- `StateStore.linked` now reports `syncRemote ~= nil`. A client that cannot see
  the sync remote is not linked, and saying so is the whole point of the flag.
- `BladePreview.mount` frames the blade from `model:GetBoundingBox()` instead of
  hardcoded numbers: aim at the bounds centre, fit the vertical FOV with a 10%
  margin, and sit 26 degrees off the blade's axis. Measured before and after on
  the live build: the pommel sat at `ndcY -1.49` (49% below the frame edge) and
  the blade covered 4% of the width; now it spans `-0.90 … 0.92` and reads as a
  sword rather than a scratch.
- The flavour line gets its own 22px band (`viewport.Size = UDim2.new(1, 0, 1, -22)`)
  instead of being drawn over the render.

**Why.**

- The boot sequence has a single ordering guarantee — UI first, network last —
  and a throw anywhere in the UI half costs the whole session. That is a design
  choice for perceived load time, so every call in it has to be correct rather
  than merely plausible. `--!strict` does not validate engine property names;
  only running the thing does.
- A "linked" flag that lies is worse than one that stays false: the fallback
  paths that read it never fire, so a dead connection looks like a live one with
  zero data.
- A framing bug that no test catches and every player sees is exactly what a
  screenshot is for. The numbers above came from projecting the model's bounds
  through the live camera, not from eyeballing the image.

**What it costs.** Nothing at runtime. The lesson is process: playtest before
claiming a boot fix, and measure the frame the player actually sees.

---

## ADR-024 - Blades are lofted in Blender from the registry, and the export is verified by re-importing it

**Context.** The blade meshes did not exist. The catalogue lived only in
`BladeRegistry.luau` and in `BladePreview`, which builds each blade from ~20
primitives at runtime. The plan was to route prompts through an image model into
Genie and import the result. Three things killed that:

- Genie returns 10-40k triangles for a prop that needs 150, and every pass would
  be a different object, so twenty-five tiers would not share a silhouette
  language.
- A live Blender MCP bridge was already available, and the geometry is a lofted
  extrusion of a handful of numbers. There is nothing for a generative model to
  decide.
- Prompt-to-mesh puts the one thing we actually control - exact orientation,
  scale and pivot - behind an importer dialog nobody can script.

**Decision.**

- `scripts/build_models.py` parses `BladeRegistry.luau` and lofts each blade:
  ten 5-gon rings, a tip fan, and three joined primitives for grip, guard and
  pommel. 150 triangles, 3 750 for the set.
- The stack is authored as contiguous spans, not overlapping volumes:
  `grip` is `0 .. grip_h`, `guard` is `grip_h .. grip_h + guard_h`, the blade
  starts where the guard ends. A shared `layout()` returns those three numbers so
  the blade and the hilt cannot disagree about where the guard is.
- Per-shape `grip` / `guard` fractions. A glaive and a scythe are mostly haft;
  building them on a sword's 16% hilt produces a long dagger.
- Per-shape `tip_frac`. Width is held to that fraction, then converges as
  `(1 - t) ** 0.75`. Tapering from `u = 0` is a spear, and that is exactly what
  the first render showed.
- Export `axis_forward="-Z"`, `axis_up="Y"` so Blender's Z-up becomes Roblox's
  Y-up with the cutting edge facing -Z, and set the origin to the 3D cursor at
  the hilt base before writing.
- `scripts/render_models.py` imports every FBX back, measures it, and renders a
  contact sheet. This is the acceptance gate.

**Why.**

- The first build ran to completion and wrote nothing. Blender's script-file
  executor uses `exec()`, so `__name__ != "__main__"` and the standard guard
  silently skipped `main()`. It reported success with an empty log. Calling
  `main()` unconditionally is what makes both entry points work.
- The first successful build produced spears: taper from `u = 0`, and a guard
  scaled by `guard_h * 0.5` on a unit cube - half the height it needed - so the
  stack had a gap and the model came out 16% short of its tier height. Both were
  invisible in the log (150 tris, plausible file sizes) and obvious in the
  render. That is the whole argument for rendering: numbers agreed with the bug.
- `use_auto_smooth` was removed in Blender 4.1. Assigning it raises
  `AttributeError` on 5.x, which is a hard failure that only appears when the
  line runs.
- A pivot at the bounding-box centre is the default `origin_set` result and it
  is wrong for a held object. Re-importing proves it: `pivotZ = -0.0000` for all
  25 files.
- Half the loft's faces come out wound backwards (rings built bottom-up, tip fan
  and base cap authored from the other side). Roblox renders those as holes, so
  `recalc_face_normals` runs before triangulation.

**Upload.** `Model`, not `Mesh`: the Assets API's `Mesh` type accepts only mesh
data downloaded from the asset delivery API and exists for re-uploading, not
importing. `Model` ingests `.fbx` and returns a package of MeshParts.

The multipart body is `request` (JSON) + `fileContent` (bytes). The previous
version posted flat form fields with the file under `file`, which is not the
documented contract. Verified by pointing the uploader at a local server and
asserting the captured body: both parts present, `assetType` correct, FBX bytes
intact, and the operation poll actually looping twice before `done`.

**The cache keys on geometry, not on the file.** Blender's FBX writer is not
byte-deterministic — the same mesh exported three times gave three different
SHA-256s, because the container carries data that varies per run. Keying the
resumable cache on the file hash meant every `build_models.py` run invalidated
all 25 entries, and since an upload never overwrites an asset that does not
replace anything: it creates a second copy. Quota spent, duplicates accumulated,
and the bug is invisible in the log because re-uploading looks like work.

`build_models.py` therefore writes a `geometryHash` per blade into `index.json`
(a SHA-256 over rounded vertex coordinates and polygon indices, salted with an
`EXPORT_VERSION` that gets bumped when export settings change), and the uploader
uses that as the cache key. Measured: two full rebuilds produce zero
`geometryHash` differences while the FBX file hashes keep moving.

**What it costs, and what it does not do.**

- The meshes are uploaded and recorded, not rendered. `AssetManifest.Meshes` is
  a second table because a mesh id and an image id are indistinguishable strings
  and an `ImageLabel` given a model id shows a grey box. `AssetManifest.mesh()`
  returns nil for every unresolved id, so `BladePreview` keeps its primitive
  path and the game plays identically today.
- Swapping the viewport to `InsertService:LoadAsset` is a separate change. Each
  entry carries `height` and `tris` precisely so that change can measure the
  imported MeshPart and rescale it, since the importer does not promise a
  stud-per-unit scale.
- 150 triangles is deliberately austere. There is no bevel, no fuller geometry,
  no pommel detail. At the size the viewport draws a blade (about 90px tall),
  extra topology is invisible, and the flat colour comes from the registry
  anyway.

---

## ADR-025 - A clean shutdown has to release the session lock, and the flush has to run before the flag

**Context.** Every playtest after a stopped one was kicked with *"Could not load
your forge data. Please rejoin in a moment."* The store showed a lock owned by a
job GUID that no longer existed. Three separate faults combined:

1. `BindToClose` calls `DataManager.shutdown()`, which called `DataManager.save`
   for each profile. `save` opens with `if shuttingDown then return false end`,
   and `shutdown()` had already set `shuttingDown = true` — so the flush was a
   guaranteed no-op and every session silently lost its last `SaveInterval`.
2. `save` writes `lock = { job = jobId, at = os.time() }`. Flushing without
   clearing the lock leaves a live-looking lock on a server that is about to
   die.
3. `DataManager.release` — the only thing that clears the lock — is connected to
   `Players.PlayerRemoving` inside `startAutosave`. `PlayerRemoving` does not
   fire on shutdown. On a real stop, `release` never ran.

`LOCK_STALE_SECONDS` is 60 and the load retry budget is `1 + 1.5 + 3 + 6 ≈ 10.5s`,
so a fresh foreign lock could never age out inside one join. The kick was not
flaky, it was arithmetic.

**Decision.**

- `shutdown()` snapshots `profiles` and then calls `dropLock(keyFor(userId), state)`
  for each one. `dropLock` writes the current state *and* clears the lock in the
  same atomic `UpdateAsync`, so it replaces the flush rather than following it.
  Two writes per player would burn DataStore budget for nothing.
- `shuttingDown` flips after the writes, not before.
- `release` (the `PlayerRemoving` path) shares `dropLock`, and the "keep the lock
  so a crash mid-close still recovers" branch is gone. `UpdateAsync` is atomic:
  if the server dies mid-call the write either lands whole or not at all, and if
  it does not land the lock is still set from acquisition, so the staleness rule
  covers it. Keeping the lock bought no safety.

**Why it took two attempts to diagnose.** The first fix ("flush before flipping
the flag") was correct and insufficient: the lock was still written by `save` and
never cleared, so the second rejoin test was kicked again. I had also assumed the
shutdown path ran through `release`, which it does not. The rejoin test passing
the first time was luck — enough wall-clock had elapsed for the leftover lock to
age past 60s.

**Verification.** Stop and restart separated by **1.6s** (measured), against a
60s window: `kicks=0`, `Rate = "No drones online"`, `dataManagerWarnings=0` (so
the lock was acquired on the first attempt, no retries), `sm=20` intact after a
stop that happened about a second after earning it — against a 30s autosave
interval.

**Cost.** BindToClose now does one write per player instead of zero, and they are
sequential. A full server of 30 players would need 30 round trips inside the 30s
BindToClose budget. At this game's scale that is fine; if the server cap grows,
those writes should be spawned in parallel.

---

## ADR-026 - Blade meshes load on the server, draw as an upgrade over the primitives, and the AABB is computed by hand

`InsertService:LoadAsset` is server-only, so a client that wanted its own meshes
would fetch 25 assets per player instead of 25 per server. `MeshService` loads
them at boot into `ReplicatedStorage.BladeModels/<bladeId>`, four at a time, and
the client clones from there. Load time measured on a live server: 25/25 in
**~3.4s** with four workers; the serial first attempt took ~35s, which meant most
of a player's first minute ran on primitives.

**The mesh is an upgrade, never a dependency.** `BladePreview.build` tries the
mesh first and falls back to primitives; `mount` watches for a late arrival and
swaps it in place with `BladePreview.upgrade`, re-framing the camera afterwards.
That is what keeps the game fully playable with zero uploads, and it is also what
makes a failed upload invisible instead of fatal.

Three engine behaviours had to be worked around, all found by measuring rather
than reading docs:

**`Model:GetBoundingBox()` lies about scaled MeshParts.** A MeshPart keeps its
native `MeshSize` (640 studs for these imports) while `Size` carries the scaled
value (6.4). With a MeshPart alone, GetBoundingBox uses `Size`; add any other
part and it switches to the native extents. A correctly scaled 6.4-stud blade
measured **320.7 studs**. The camera framed from that number and produced a blade
a third of the way across an empty box. `BladePreview.boundsOf` computes the AABB
from `CFrame` and `Size` instead, which is also what the renderer uses.

**`Model:PivotTo` without a `PrimaryPart` is not a stable transform.** The pivot
is whatever the engine last computed, so the first `PivotTo` after geometry
changes translates the model by an extra amount. Measured: a blade whose measured
centre was 2.00 sat at 1.78 after settling — 0.22 studs, enough to push the hilt
out of frame. An invisible `Pivot` part at the hilt base, set as `PrimaryPart`,
pins the transform and gives the turntable the right axis (the haft, not the
middle of the blade).

**Camera framing needs slack, not tightness.** Fitting the height exactly leaves
the near corner of a 3D object projecting outside the frame: the blade's own
depth makes its near edge ~6% larger than a flat plane at the aim distance. At
1.10 the hilt clipped the bottom edge by 3%; 1.30 holds the worst blade
(`entangle_scythe`, whose hook sweeps widest) inside 0.13–0.98 of the frame
through the full bob cycle.

Bob amplitude is proportional to blade height for the same reason: 0.22 studs
reads as a drift on a 9.6-stud primitive and as 5% of the frame on a 4-stud mesh.

---

## ADR-027 — The action remote hands the payload to handlers, and the feedback layer is bounded

Two things shipped together because one was hiding the other.

**The action handler contract is `(player, payload)`.** `Net` routes on the verb to
find the handler, then re-passed the verb as the second argument. Every handler
therefore read the action name as its payload: `forge` looked up a blade called
"forge", `get` returned nil, and `ProgressionService` rejected with `"Unknown blade"`.
Forging and equipping had never worked, and the only symptom on screen was a stack of
red toasts. The toast stack then sat top-centre, on top of the onboarding strip,
translucent — which is why the "NEXT: Forge …" line appeared to have a ghosted
`x1.00` behind it. Two bugs, one screenshot.

Fixed at the boundary: the handler type is `(player: Player, payload: any) -> boolean`,
and the dispatcher drops the verb after routing. Handler signatures in
`Main.server.luau` were already written against `(player, payload)`, so nothing above
the network layer had to change.

**Feedback is transactional and bounded.** Every strike allocates: one floating
label, one 4–6 frame slash, a spark batch driven by a *single* RenderStepped
connection, and two tweens on existing instances (the stage scale and the wash). The
spark connection owns its own lifetime and disconnects when `remaining <= 0` or the
layer is gone; measured on the live build, 14 sparks are all destroyed within 1.15s.

The scale-punch lives on the viewport (`UIScale` inside the clipped stage frame), not
on the container, because the container's neighbours are the heat gauge and a 4%
growth would overlap it. The wash is a sibling frame above the viewport, since a
`ViewportFrame` cannot render GUI strokes or gradients inside its own buffer.

**The showcase window is a lock, not a queue.** `celebrate` sets
`showcaseUntil = now + 2.6` and `ensureBlade` refuses to swap while it is open. The
10 Hz sync would otherwise pull the equipped blade back within ~100 ms and the
player would never see what they just paid for. Only one showcase can exist, so the
guard is a timestamp plus a token, not a list.

**The tracker's ring is re-resolved, never cached.** `TutorialController` keeps a
`desiredTarget` name and re-runs `applyHighlight` four times a second. That is what
moves the pulsing ring from the Blades tab onto the affordable blade's own FORGE
button without a single click handler in the inventory.

Cost: one recursive `FindFirstChild(name, true)` over the canvas at 4 Hz, and up to
~25 candidate cards inside it when the Blades tab is open. Measured at boot: the UI
still builds in 27 ms.

---

## ADR-028 — Onboarding is a modal card with one-shot tab cues, and action state is a plate

Four UI problems, one root cause: the interface was drawn as a wireframe and the
player had to read 11px text to know what state anything was in.

**The guide is a modal, not a banner.** A 44px strip at the top of the screen was
never read; the welcome copy now lives in a centred 480×320 card with a 58% scrim,
a 2.5px accent stroke, a `LESSON n OF 5` counter and exactly one CTA. It sits at
`ZIndex 58/59`, one rung under the offline `WELCOME BACK` modal (`60/61`), so a
returning player collects their offline earnings first and finds the lesson waiting
underneath rather than fighting it for the same pixels.

**A tab is worth one cue, never a standing ring.** The old target function returned
`forgeButton(state) or "Tab_Blades"`, so a player who stepped into FLEET during the
forge lesson kept a gold outline glued to BLADES for the rest of the step. That is
the ghost. Targets are now resolved from the live tab: ring the control when its tab
is open, else emit a `Tab_*` cue exactly once (tracked in `sawTab`) and never again
for that step. `SidePanel.onSelect` re-evaluates on the same frame as the click, so
the ring moves with the player instead of a quarter-second behind. A completed step
destroys its ring in `clearHighlight`, and the post-tutorial tracker only ever rings
a control that is on screen — never a tab.

**The ring is a child of its target,** with a 3px gold stroke plus a 6px halo at 82%
transparency. No absolute-space maths, no `UIScale` compensation, and it dies with
the control when a view is torn down and rebuilt.

**Action state is the plate, not the caption.** `UiKit.actionButton` is the one
control for every CTA in the side panel:

| state | plate | face |
| --- | --- | --- |
| `ready` | accent gradient + 1px lit bevel | ink, `FORGE`, `BUILD 1 · 12`, `R$ 199` |
| `locked` | flat `#181C26` slate, faint border | dim `LOCKED` / cost |
| `equipped` | 16% green tint, matching border | `✓ EQUIPPED` |

The fill is a child frame, not the button's own background: a `UIGradient` on a
`TextButton` multiplies the label as well as the plate. Cards carry a 4px rarity bar
and a live progress bar toward the blade's price (or the tech node's next level), so
"how close am I" is a shape rather than a number to read. Tabs use the same logic at
one-tenth the weight: the active tab is a solid accent pill at 84% transparency; the
rest are transparent with no border, which is also what finally removed the stray
gold line that the old 2px underline left under a deselected tab.

Cost: none measurable. The action button adds two frames and one gradient per row;
the plates only restyle when the state *changes*, guarded by `lastKind`/`lastLabel`,
so a 10 Hz sync does not rewrite 25 `ColorSequence`s a tick.

---

## ADR-029 — The interface is moulded, not outlined: one 3px border, solid plates, and the vent key lives on the heat rail

The reference screenshots (five local captures, `incremental/images/`) settled a
disagreement the previous passes had been losing: the UI was drawn as a set of thin
translucent outlines over a dark background, and the player had to read small text to
know what state anything was in. The reference does the opposite. Every surface is
opaque, every edge is a hard 3px near-black line, and state is a plate colour before it
is a word.

**One outline token.** `Theme.Color.outline = #0F1117` and `Theme.Stroke.thick = 3` are
the house border. `UiKit.stroke` defaults to them, and `UiKit.panel` draws every surface
at `BackgroundTransparency = 0` with a lit 2px top bevel and a dark 5px bottom lip. The
old ladder of translucent fills is gone: `Theme.Elevation` still has four rungs (well,
item, shell, raised) but all four are opaque, so stacking no longer compounds into mud.
The palette is warm (wood banners, `#CE8D4A` → `#8C5628`), which is what makes white
stroked type readable on a header.

**Chrome is a component, not a per-view drawing.** `UiKit.banner` is a wood gradient
plaque with a 30px accent icon square, white GothamBlack type and a hard black glyph
stroke. It is used for the forge header, the side-panel header and every modal,
including the tutorial card and the offline popup, which now share one family: 12px
corners, an overhanging banner at `y = -22`, and a red gradient `X` at the top-right.
`UiKit.badge` is the small outlined chip used for costs, multipliers and categories.

**Actions are plates.** `UiKit.actionButton` keeps its three states but they are now
unmistakable at a glance: `ready` is a solid accent gradient (gold for blades, cyan for
fleet, violet for tech, emerald for the store) with a 3px outline and a one-pixel lit
edge; `locked` is flat `#181C26` with dim type and no stroke tricks; `equipped` is a
green badge. `UiKit.button` is the secondary control (solid, outlined), and the top-bar
`ASCEND` / `DAILY` buttons now carry gradient plates with white stroked faces rather
than a coloured outline. Tabs are solid pills: the active one carries the accent
gradient and white stroked type, the inactive ones sit on slate with no glow, so the
selected tab is the only one with colour.

**The bottom vent bar is deleted, not restyled.** It was 48px of vertical space, a
second heat readout, and a second place to look. The vent key now sits at the right end
of the core-heat rail, same 34px row: below 85% it is a flat slate key reading
`VENT` / `REACH 85%` with the house outline; at 85% it becomes a solid cyan→gold plate
reading `⚡ VENT NOW` / `+N AETHER`; during a lockout it turns red and reads
`PURGE HEAT`. The rail itself stops 140px short to make room, and the threshold tick
recolours with the key. This also removed the row that used to clip against the panel's
bottom edge: the anvil now ends 16 design px above the panel bottom.

Cost: the panels gained a bevel and a lip (two frames each). Everything else is a
property change on the same instance count, and the per-frame work is unchanged — the
vent key's pulse rides the existing render step behind a `ventReady` guard.

**Supersedes the styling half of ADR-028** (the card shape, the 84%-transparency tab
fill and the faint plate edges). The behaviour decisions in ADR-028 — modal lessons,
one-shot tab cues, three-state action buttons — still stand.

---

## ADR-030 — The equipped blade is bound by a viewport attribute, and the drone flies on accumulated time

Two display bugs, one shared root: a viewport was trusted to show what a variable
elsewhere said it showed.

**The header and the model are written from one function.** `ForgeView.mountBlade` is
now the only path that swaps the preview: it resolves the registry entry, tears down
the previous preview, mounts the new one, paints the header from that same entry, and
then reads back `viewport:GetAttribute("BladeId")` — which `BladePreview.mount` sets
from the blade it actually built. A disagreement is logged rather than discovered by a
player. `currentBladeId` is set *after* a successful mount, so a failed mount can no
longer leave the id cache claiming a model that is not on screen, which was the shape
of the original permanent desync: the id was written first, the mount never ran, and
every later sync read "already mounted".

**A celebration yields to an explicit equip.** The forge showcase used to block every
sync for 2.6s, including a sync that reported a blade the player had just equipped by
hand. It now records `showcaseEquipped` when it opens and only holds the viewport while
the equipped blade is either the showcased blade or the one that was already worn. A
third blade ends the showcase immediately. `BladePreview.upgrade` also refuses to swap
geometry when the model's name no longer matches the blade it was mounted for, so a
late mesh callback cannot paint one blade's asset under another blade's name.

**The eight shared mesh ids are geometry dedupe, not a mismap.** `BladeModels` has 25
models but 17 distinct inner `MeshId`s: Nova Reaver and Astral Cutter, Rusted Cleaver
and Cinder Spike, and six other pairs resolve to the same mesh. Their `.obj` files hash
identical on vertex and face data — the pairs differ only in vertex colour, so Roblox
deduped the mesh payload and the registry colour is applied at runtime anyway. Worth
knowing before treating a shared id as a bug.

**The drone's spin cannot come from `tick()`.** `DroneModelBuilder` builds the same
shape either as 40 primitives — a dark core ball with a neon reactor inside, two
segmented hoops at right angles, four swept fins with neon tips, and a nose lens — or
from the uploaded `fleet_drone` mesh, which superseded the primitive build in ADR-031.
The primitive path stays as the fallback so the fleet stage works on a fresh clone.

The obvious spin, `CFrame.Angles(0, tick() * 1.5, math.rad(15))`, does not rotate.
Measured live: `tick()` is ~1.79e9, so the yaw is ~2.69e9 radians, and `CFrame.Angles`
resolves the angle in single precision, where the spacing at that magnitude is ~256
radians. Every frame lands on the same orientation; the recorded look vector was
identical across a 0.35s window, and the drone sat still. The builder accumulates the
frame delta instead (`clock += math.min(dt, 0.1)`), which keeps the angle small and the
turn exact. The blade turntable already worked this way; the drone now matches it.

Both viewport loops declare `local connection: RBXScriptConnection` before the closure
and assign after it. The old inline form referenced a global `connection` inside its
own initializer, which would have errored on the dead-model branch instead of
disconnecting.

---

## ADR-031 — A blade is two uploaded meshes, and a split blade is cut across its width

The catalogue used to be geometry written in Luau: a six-vertex loft, a handful of
prisms for the guard, two spheres for a pommel. It read as a schematic. Every blade is
now sculpted in Blender by `scripts/build_models.py`, exported to FBX, uploaded through
Open Cloud, and loaded at runtime — with the primitive recipes kept as the fallback, so
the game still boots on a clone with no uploads.

**Two objects per asset, because a MeshPart has one `Material`.** `<id>` is the metal
body, `<id>_glow` carries the emissive core, runes and vents. `InsertService:LoadAsset`
returns both with their names intact, and `BladeModelBuilder` classifies by name
(`"glow"` substring) rather than by index or by sibling order, which survives an
insertion-order change. Measured live on the equipped blade:

| part | material | role |
| --- | --- | --- |
| `comets_wake` | `Metal` | body, opaque, registry colour |
| `comets_wake_glow` | `Neon` | channel core, runes, vents |

**The registry's `Neon` and `Glass` describe the blade's energy, not its surface.** Those
values made sense when the body was a primitive slab that glowed, or a transparent shell
with light inside. On a sculpted mesh an emissive body flattens the shading that makes
the bevels legible, and a glass body is literally see-through: measured live, Comet's
Wake rendered as a transparent shell around its core, which is exactly the "hollow sword"
it looked like. `BODY_MATERIALS` now admits only `Metal` and `DiamondPlate`; everything
else falls back to `Metal`, and the light all lives in `_glow`.

**A split blade is cut across its width, not across its thickness.** The first split
build offset two full-width blades along X and left a slot between them — a sandwich.
From most angles you looked straight through the seam, so the sword read as hollow with
a bar floating in it. `loft` now takes a `gap` and emits two lanes, `edge` and `spine`,
that share the outer silhouette: the edge lane keeps the cutting vertex, the spine lane
keeps the thick back, and the walls face each other across the channel. The gap closes
over the last fifth so the tip is one point instead of two prongs. `glow_channel` fills
the channel wall to wall for split blades and stays a proud fuller on solid ones.

**A decoration is sized against the blade's thickness, never its width.** On Comet's Wake
the rune plate measured 0.655 studs across the face of a 0.135-stud blade: a white bar
punched through the steel, which is what actually read as "hollow" in the first report.
Runes are now `thickness × 1.20` wide and `width × 0.42` tall, vents `thickness × 1.15`
by `width × 0.13`. Anything on the flat is thin in X; only the span across the face uses
the width.

**Face order is part of the cache key.** `geometryHash` hashes verts, faces and object
names, and the uploader only re-sends changed entries. Reordering the base caps inside
`loft` would therefore re-upload all 25 blades for a cosmetic diff, so the split path
emits caps in the same order the pre-split builder did — verified by rebuilding and
diffing hashes: exactly the 14 split-bearing blades changed on the split pass, and the
tidy-up pass changed nothing.

**Fog of war is waves of three, and the reveal line cannot name a hidden blade.** Wave
N+1 unlocks when the third blade of wave N is owned. The gate name is printed only when
it belongs to the newest revealed wave; deeper rows count waves instead
(`CLEAR WAVE 6 TO REVEAL`). Printing the gate name unconditionally leaked names the fog
exists to hide — measured live, three rows read `FORGE HADRON SPLITTER TO REVEAL` while
Hadron Splitter was still `???`. The line also moved to the bar row on a mystery card
and took the full width: at 200px against a button that starts at x = -114, it clipped
under the plate.

Live counts after the mesh pass: `BladeModels` holds **26 models / 51 mesh parts** —
two per asset except `rivet_edge`, whose recipe carries no glow at all (`glow = "none"`,
zero runes, plain bar guard, cap pommel), so its emissive object is empty and is not
exported. Inventory thumbnails: **25 of 25 rows render a MeshPart**, measured through
the live `PlayerGui`. Locked waves render the real mesh at `Color3.new(0, 0, 0)` with
`SmoothPlastic` on both body and glow — measured `0,0,0 a=0.0` on `nullbreaker`,
`voidfang` and `entropy_edge`.

---

## ADR-032 — Toasts live in the gap under the anvil, and a corner radius is a number

Five UI problems, three of them traceable to a value that looked right and
resolved wrong.

**`UDim.new(0, UDim.new(0.5, 0))` is `UDim.new(0, 0)`.** `UiKit.corner` takes a
number and builds `UDim.new(0, radius)`. The forge stage called it with a
`UDim`, and the constructor quietly took the *offset* of that UDim — zero. So
the four "soft pools" behind every blade were four hard-edged squares per side,
stacked 320/250/179/129px, with `CornerRadius 0/0` on all of them. Measured
live. The pools are now rounded from a real radius and the cool stack is
mirrored to 82% of the stage width: its 187px right edge lands at 526 of 528,
two pixels inside the frame, where the old 92% placement hung 51px past the
border and read as clipped.

**The stage wash follows the blade.** `Theme.tierBackdrop(tier)` holds the two
colour pairs (warm under the hilt, cool behind the tip) for all five tiers:

| tier | warm | cool |
| --- | --- | --- |
| 1 Scrap | rust `168, 74, 36` | dim amber `122, 88, 26` |
| 2 Forge | molten orange `255, 107, 0` | steel blue `70, 108, 138` |
| 3 Quantum | electric cyan `0, 210, 255` | deep violet `96, 40, 190` |
| 4 Celestial | astral magenta `255, 54, 200` | nebula indigo `43, 46, 143` |
| 5 Cosmic | gold `255, 194, 60` | nebula indigo `58, 43, 143` |

`paintBackdrop` is called from the same place as `paintHeader` — `mountBlade` and
the forge showcase — so the backdrop can never lag a mount by one sync. Verified
live on Rivet Edge (tier 1): the eight pool layers read `168,74,36` and
`122,88,26` exactly.

**The toast stack moved into the only free band on the canvas.** Measured before
choosing: the strike plate ends at design y 670, the canvas is 720 tall, and the
side panel starts at x 834. The free band is 670..706 under the anvil — 37px
tall. So the stack runs *sideways* in it rather than upward: two 360×34 pills at
x 20 and x 388, y 678, ZIndex 30. Verified live at `160,487 259x24` against a
strike at `x 181..710, y 378..482` and a side panel at `x 745` — zero overlap
with any tab, dock or vent key, in either direction.

**A solid fill beats a gradient at 132×34.** The live vent key was a cyan→gold
three-stop ramp with a `⚡` that rendered as tofu wherever the emoji font was
missing. Ready is now solid `#00D2FF`, lockout is solid `#FF6B00`, both with a
2.5px `#0B0E14` stroke, a lit top edge and pure white type with a near-black
outline. Measured live at heat 92: fill `0,210,255`, stroke `2.5` / `11,14,20`,
label `VENT HEAT`, detail `+7 AETHER`, text `255` with stroke transparency 0.
The locked state is untouched.

**The fleet tab is three fixed bands.** 38% hero (172px of the 448px content
column) with the render, a grid and one count pill; a 64px two-column strip
(OUTPUT in gold, PER DRONE in cyan); a 52px dock with BUILD 1 and BUILD 10 and
one footer line. Nothing below the stage changes size as numbers change width,
which is what made the old layout shuffle. The BUILD 10 face carries the
geometric sum of the next ten prices — at 5 base and 1.16 growth that is 106,
not 50.

**Orbit control is one module, two viewports.** `ViewportOrbitController` owns the
pivot for both the blade and the drone. Measured at the time: both viewports idled
at 0.75 rad/s, held at 0.00 rad/s while the button was down, and resumed at 0.75
from the held angle. ADR-033 replaces that drag model — the spin no longer stops,
and dragging orbits the camera instead.

---

## ADR-033 — The anvil was walking, and the turntable was stopping

Four reports from a live playtest. Three were real defects with a single cause
each; the fourth was a layout number that had gone stale against a different
panel width.

**"STRIKE THE ANVIL" drifted up and to the right.** `Vfx.shake` read
`target.Position` at the start of every call and restored that value when the
animation ended. A second shake on the same target begins while the first is
still mid-offset, so the second call captured a *displaced* position and treated
it as home. Every overlapping click therefore moved the anvil a little further,
and the error compounded. The old guard was a single global token, so one shake
could also cancel another target's shake and leave it stuck mid-offset.

The fix is a weak-keyed registry of `{ rest, connection }` per target. Rest is
adopted only when nothing is animating that target, an overlapping call
disconnects its predecessor before starting, and the animation always writes
`rest + offset` from the recorded home.

The button also stopped being shaken at all. It is a full-width child of the
forge card, so any positional offset puts its edge outside the card. The face
now lives in an inset `Content` frame that takes the jitter, and the plate stays
at `{0, 0}, {0, 360}`. `ForgeView.punch(strength)` is the single entry point,
called by a normal strike and by the crit handler in `Main`.

Measured live: 12 real clicks moved Star-Matter from 9.69B to 9.72B with the
button still at `{0, 0}, {0, 360}` and absolute `181.9, 378.4` — identical to the
pre-click rect. A bench run of 30 overlapping shake pairs on the content layer
settled at `0.00, 0.00` drift.

**The turntable stopped when you touched it.** Dragging moved the model, so the
spin froze for the duration of the gesture and resumed from wherever the drag
left it. That reads as a broken display piece: you walk around a sword, the sword
keeps turning.

`ViewportOrbitController` now owns two independent motions. The model spins on Y
every frame at 0.9 rad/s, consulting neither the drag state nor the camera. The
camera orbits the framed centre at the user's yaw and pitch:

```
cam.CFrame = CFrame.new(centre) * CFrame.Angles(0, yaw, 0)
           * CFrame.Angles(pitch, 0, 0) * CFrame.new(0, 0, distance)
```

`distance` and `centre` come from the caller's framing solve, so the orbit radius
is whatever the blade or drone was already framed at; `setFraming` re-solves it
when a late mesh lands. Pitch is clamped to ±40°, both in the drag handler and at
the point of use in the render loop, so a direct write to the public angle fields
cannot put the camera under the floor.

Measured live: the blade spins at 0.90 rad/s *while the mouse button is held
down* — the exact state that used to freeze it. Bench check on a model with
`centre = 0`, `distance = 10`: yaw `0.80` rad, camera elevation `28.6°` from
`pitch = -0.5`, radius `10.0`; forcing `pitch = ±9` rad lands at exactly `-40.0°`
and `+40.0°`.

The drone's initial camera reproduces the old static shot exactly: the frame
reads yaw `143.2°`, radius `5.61` against the authored `atan2(3.1, -4.15) = 143.2°`
and `sqrt(3.1² + 2.1² + 4.15²) = 5.589`.

One verification limit, stated plainly: the bridge's `moveTo` sends
`MouseMovement` events with `Delta = 0`, so a simulated drag cannot drive
`InputChanged` the way a hand does. The camera layer was proven by writing the
angle fields the drag handler writes; the handler itself is a six-line
delta-to-angle map above it.

**Scroll position was thrown away on every tab switch.** `SidePanel.select`
unmounted the view, destroyed its rows and set `CanvasPosition = Vector2.zero`.
The scroll now lives in `savedScroll[tab]`, captured from the outgoing tab before
teardown. Restore cannot be written in the same frame: `AutomaticCanvasSize`
recomputes on the frame *after* the rows are parented, so a position set
immediately is clamped against the old, empty canvas and silently becomes zero.
`restoreScroll` retries across five heartbeats and stops as soon as the value
holds. Measured live: set Blades to 600 on a 1950px canvas, switch to Fleet,
switch back, `CanvasPosition.Y = 600`.

**The objective strip was positioned against a width that no longer existed.**
`TutorialController` had its own `STRIP_X = 304`, `STRIP_W = 534` while the forge
card is `806` wide starting at `14`, so the strip's right edge landed at 838 —
inside the 14px gutter and 4px into the side panel — and its left edge floated
mid-canvas.

There is now one `Layout` module holding margin, gap, side width, top edge and
the status row, required by `Main`, `HudController` and `TutorialController`. The
status row is the passive-rate pill at `14, 96, 284×30` and the objective strip
at `306, 96, 514×30`: same top, same height, and the strip ends exactly on the
forge card's right edge.

Measured live: rate `156,69 204×21`, strip `366,69 369×21`, forge card `156..736`,
side panel starting at `834` design (`745` screen at 0.719 scale). The strip's right
edge is the forge card's right edge, at screen x 735.

**Copy.** The objective lines are `GOAL: Forge Coil Shard (click FORGE)` and its
four siblings. Em dashes are gone from every player-facing string: objective
lines, tutorial modal bodies, and the two combat toasts. The currency
placeholder is `--`, still deliberately not `0`.

**Top bar.** The three currencies are navy capsules (168×58, radius 12, 2.5px
`#0F1117` stroke, gradient from the new `Theme.Color.slateLift`) with a 32px
coloured badge on the left and the number in white with a hard black stroke. The
badges are geometry, not glyphs: a `★` for Star-Matter (already proven in the side
panel banner), a 45° rotated plate with a white facet for Aether, and concentric
circles for Cores. The vent key's `⚡` rendered as tofu on clients without the
emoji font, and nothing here can fall back to a box.

The title is the same `UiKit.banner` the right panel wears — wood gradient, 3px
outline, lit bevel, 30px gold plaque — at 292×52. Measured live: banner
`210×37` at screen scale 0.719 (292×52 design), the three pills and both action
buttons all `41px` tall on the same row, and the guide button's right edge at
`1252` design, which is the bar's content edge.

---

## ADR-034 — The loop gets a second verb, and the store stops selling the grind

Two design analyses (`incremental/video-04-market-positioning.md`, `video-05-onboarding-monetization-qa.md`)
asked for the same thing from different angles: the anvil loop is strong, but
everything around it is a single track. Click, forge, click harder. The idle half
exists and the meta half is thin.

This pass adds three systems to the loop, one telemetry layer under it, a
restructured onboarding, and a storefront rule. It also found one monetization
bug that had been live since the first store build.

### Mastery and rune sockets

Every blade now carries its own strike counter. Ranks land at 100, 400, 1 200,
3 000 and 8 000 strikes, and the rank unlocks sockets: none at rank 0, then one,
one, two, three. A rank announces itself with a toast; the counter survives an
ascension even though the blade itself does not, so a mastered blade comes back
mastered when it is forged again.

Runes are bought with Void Shards and socketed into the equipped blade:

| Rune | Effect | Cost |
| --- | --- | --- |
| Ember | +8% strike yield | 3 shards |
| Tempo | +6% heat cooling | 3 shards |
| Edge | +3% crit chance | 4 shards |
| Prism | +10% Aether from venting | 5 shards |

Shards are the only currency in the game that comes from risk. They drop from a
hot gauge at 6% per strike, or 18% during Overdrive, and only above 55% heat.

`RuneConfig` owns thresholds, sockets and the rune table. `ProgressionService`
owns the sums, and `buildPayload` sends the equipped rack, the unlocked slot
count and the rank. `RuneView` is a new tab between Fleet and Tech and renders
the causal chain in reading order: mastery bar, socket rack, rune shelf.

Sockets are stored as dense arrays of rune ids with `""` for empty, so the save
never carries holes. `DataManager` sanitises the racks on load: unknown blades
and unknown rune ids are dropped rather than coerced, and every rack is padded to
`RuneConfig.MaxSockets`.

### Expeditions

The fleet now does something other than add a number. `ExpeditionConfig` holds
three missions:

| Mission | Squad | Time | Payout | Bonus |
| --- | --- | --- | --- | --- |
| Debris Sweep | 5 | 5 min | 45 Aether | none |
| Deep Salvage | 15 | 15 min | 165 Aether | 1 Core, 1 Shard |
| Void Run | 30 | 60 min | 1 100 Aether | 6 Cores, 4 Shards |

Committed drones produce nothing until the mission lands. That is the whole cost
of the decision, and it makes sending everything a legal gamble rather than a
free upgrade. The payout is snapshotted at dispatch, so swapping to a stronger
blade mid-flight cannot inflate a run already committed. `settleExpedition` pays
on the heartbeat and on join, which is how an offline mission lands before the
first payload is built. Ascending forfeits a mission in flight, because the
drones are part of the run being reset.

The Fleet tab carries the shelf at the bottom: three mission rows while the
fleet is home, one flight line with a progress bar and a countdown while it is
out. Both blocks occupy the same 132px footprint, so nothing below them moves
when a mission launches.

### Overdrive, anomalies, and a streak rail

Ten clean strikes inside the sweet spot, in a row, open a 15 second window where
every strike pays double. A miss or a burn-out breaks the streak, and the strike
that opens the window is not itself doubled. This is separate from the paid 3x
boost, which is a flat multiplier for fifteen minutes and does not care about
timing.

The anvil plate carries the state as ten pips and one line. The rail answers two
questions at once: how close the window is, and whether it is open. During
Overdrive the pips are all lit and the line becomes `OVERDRIVE x2 12s`.

Anomalies ride on top: at 55% heat or above, a strike has a 6% chance to drop two
Void Shards, rising to 18% while Overdrive is active. The drop is separate from
the payout so it reads as a find rather than a bigger number.

### The first minute

A fresh save pays five times the normal strike yield until lifetime Star-Matter
reaches 60. The gate is the lifetime total rather than a timer, so the flourish
lands on the first interactions a player actually makes and never returns after
an ascension. No new save field: `lifetimeStarMatter` already existed.

### Onboarding

There are six lessons now, and none of them are front-loaded:

| Lesson | Opens when |
| --- | --- |
| Welcome | first payload |
| Find the sweet spot | 55% heat and at least 6 strikes |
| Vent before you burn | heat 85% or a lockout |
| Forge a stronger blade | the next blade is affordable |
| Build your first drone | Aether covers `droneCost` |
| Bank the run | run Star-Matter reaches `ascendAt` |

Each lesson closes on a state predicate, and the next one cannot open for eight
seconds after the previous card closes. That gap is the difference between a
tutorial and a slideshow: the player has to strike a few times with the new
knowledge before the next card interrupts.

### Telemetry

`Funnel.log` records one AnalyticsService custom event per milestone per session:
`Session_Start`, `First_Strike`, `First_SweetSpot`, `First_Vent`,
`Forge_<bladeId>`, `First_Drone`, `First_Expedition`, `First_Rune`,
`First_Socket`, `First_Overdrive`, `First_Ascension`, `Tutorial_Done`,
`Feedback_Sent`.

The first implementation forwarded the event to the client and logged from
there. That produced a live console error: `AnalyticsService can only be
executed on the game server`. The call now lives on the server, inside a `pcall`,
because a Studio session without a published place can refuse it and a funnel
event must never break the action that produced it.

### Feedback form

A `FEEDBACK` button sits beside `? GUIDE` in the top bar and opens a modal with
four categories, a capped text box and a send button. The server trims the text,
refuses anything under four characters, and writes a record to its own DataStore
(`QuantumForge_Feedback`). A failed write is warned and printed rather than
thrown: a player who gets an error toast after typing a paragraph will not type
another one.

### Storefront

The store no longer sells raw currency. A cash pack that converts directly into
the currency being ground is the fastest way to make the grind pointless, and the
analysis is specific about it.

Selling, all with placeholder ids until the Marketplace items exist:

- Passes: Fast Forge (99), Auto-Vent (149), 2x Star-Matter (199), VIP Aura (399),
  Eternal Forge (1 499).
- Products: Starter Forge Pack (5), Instant Overdrive (25), Emergency Vent (15),
  Express Salvage (35).

Eternal Forge is the high-ticket sink: +25% to all Star-Matter, permanent, and a
multiplier rather than a number. VIP already grants the extra drone slot through
`droneCapacity`.

The bug: `Starter Forge Pack` granted fifteen minutes of 2x income by writing
`boostX2Until`, and `globalMultiplier` never read that field. The pack sold a
timer that did nothing. `globalMultiplier` now reads the timed 2x, and it stacks
with the permanent pass and the paid 3x instead of replacing either.

### Top bar reflow

Adding a feedback slot to a row that was already full meant restating the row as
arithmetic: brand 240, three pills at 156, ascend 150, daily 118, guide 84,
feedback 106, six 8px gaps. That is 1 214 of the 1 224 available design pixels.

Measured live at 0.719 screen scale: feedback `969..1045`, guide `903..963`, bar
right edge `1057`. Ten pixels of slack, no wrap, no clipped label.

### Verification

Studio playtest, scripted probes only (the bridge's `screen_capture` still
returns null):

- Runes tab builds: `MasteryCard` present, `RANK 0 / 5` rendered, Ember row at
  `y 328..370`.
- Fleet expedition band: hero `176..299`, band `419..540`, Debris Sweep row
  `439..469` (42 design px), dispatch key `959..1028`.
- Feedback modal opens with panel, text box and send key at `608,338 157×33`.
- Streak rail sits at `193..698, y462..478`, inside the anvil Content layer at
  `182..710, y378..482`, so it cannot escape the plate.
- AnalyticsService logs from the server (`LogCustomEvent event fired`), and the
  client-side call that used to throw is gone.
- One real click on a zero save paid `+5` (1 × the 5x opening multiplier) and the
  rail read `STREAK 0/10`, so the prediction, the flourish and the rail are all
  wired to live state.
- No Luau errors in the console. DataStore returns 401 in this Studio session, so
  persistence ran in documented mock mode.

One regression was observed and is not from this pass: every blade mesh returned
`User is not authorized to access Asset` in this session, so the runtime built
all 26 blades procedurally (`0/26 blade models loaded`). The fallback is the
designed path and the game stayed playable; the assets themselves were verified
loaded in an earlier session and need a Studio account with access to the
uploader's assets.

---

## ADR-035 — Nothing interactive sits under 13px, and the type ladder is the only ladder

**Context.** A playtest screenshot of the Runes tab produced the same reading
failure three times over: `0 / 100 STRIKES TO RANK 1`, `SOCKETS 0 OF 3 UNLOCKED`
and `8 VOID SHARDS` were all 12px, and the socket prompts were 10px. The canvas is
fit-scaled to the viewport ([ADR-003](#adr-003---fixed-1280x720-canvas-with-a-uiscalefit)),
so 10 design px renders at 7 screen px on a 1366-wide laptop. The labels were not
merely small; at the size they actually rendered they were below the floor of
legibility, and every one of them carried information the player needed to make a
decision.

**Decision.** `Theme.Text` becomes the single source of type, with a hard floor:

| Token | Old | New | Role |
| --- | --- | --- | --- |
| `Hero` | 50 | 50 | run meter |
| `Title` | 32 | 32 | modals, forge header |
| `Heading` | 23 | 23 | panel titles |
| `Subheading` | 19 | 19 | stat readouts |
| `Body` | 17 | 17 | blade names, row titles |
| `Small` | 15 | 15 | multipliers, hints |
| `Micro` | 12 | **14** | captions, costs, prompts |
| `Tiny` | 10 | **13** | dense rows, badges, counters |

Tab pills move to 16px `GothamBlack`. The five-tab strip was checked against the
real font rather than estimated: `TextService:GetTextSize("BLADES", 16,
GothamBlack)` is 60px and a tab in the 432px panel is 77.6px, so the larger label
fits with 17px to spare. `RUNES` (50.4) and `STORE` (48.8) are the next widest.

Secondary copy gets its own token: `textSecondary = rgb(184, 194, 214)`. The old
`textFaint` is a warm tan chosen to sit on dark slate, and on brown card stock it
sinks into the background — the exact failure the screenshot showed. The cool tone
holds roughly 7:1 against both `slate` and `cardDeep`.

**Layout moves with the type, not the other way round.** A 13–14px line needs an
18–20px band; the cards were giving it 14–16, which is why the text looked both
small *and* cramped. Every affected card was re-cut from the token:

| Surface | Before | After |
| --- | --- | --- |
| Mastery card | 156 | 178 |
| Rune row | 58 | 68 |
| Store row | 78 | 88 |
| Mission row | 42 | 48 |
| Expedition band | 168 | 186 |
| Heat rail + vent key | 34 | 40 |
| Sale badge | 9px | 13px |

**Verification.** Studio playtest, all five tabs, `TextLabel.TextFits` swept across
every visible label in the canvas: **0 clipped labels**. Geometry measured live:
mastery card 128 screen px (178 design × 0.719), rune row 49 (68), expedition band
134 (186), hero 124 (172), a tech buy key 73×23 (101×32).

**Consequence.** The right panel can hold less content per screen than before,
because every row is taller. That is the correct trade: a panel the player has to
scroll is a panel they can read.

---

## ADR-036 — The tutorial ring is an overlay, and every lesson predicate is a floor

**Context.** Two separate failures, one file.

1. The ring was parented **into** its target. Inside the side panel's
   `ScrollingFrame` that means `ClipsDescendants` slices it at the viewport edge
   and the next card paints over it — a gold outline with its top and bottom cut
   off, which reads as a rendering bug rather than as a pointer.
2. The forge lesson completed on `#state.owned >= 2`, and its target was resolved
   by blade id. A player who bought wave 3 without buying wave 2 satisfied neither
   reading, and the guide could point at a blade they had already outgrown. An
   equality test on progression state is a softlock waiting for an explorer.

**Decision.**

*The ring is a top-level overlay.* `TutorialHighlightLayer` is a canvas sibling at
`ZIndex 50`, created before the modal so the lesson card and its scrim stay above
it in sibling order (the canvas uses `ZIndexBehavior.Sibling`, so creation order is
the stacking order). `syncRing` copies the target's `AbsolutePosition` and
`AbsoluteSize` into that layer every `RenderStepped`, grows the rectangle by 5px,
and clamps it to:

- the canvas rectangle, always;
- the visible window of the nearest `ScrollingFrame`, when there is one.

If the target is outside the window it centres the scroll frame on it first
(`CanvasPosition = current ± offset`), and only when it is actually out of view, so
a player scrolling on purpose is never fought.

Cost is split deliberately: the recursive `FindFirstChild` lookup runs at 4Hz,
the geometry copy runs every frame. Reading `AbsolutePosition` is free; a
descendant walk is not.

*Every predicate is a floor.* Lesson completion and lesson targeting both ask
"have you reached at least this", never "is this exact thing true":

| Lesson | Predicate |
| --- | --- |
| Sweet spot | `inSweetSpot` seen, or heat already in band |
| Vent | `vented or as >= 1` |
| Forge | `nextBlade == nil or highestOwnedIndex(state) >= 2` |
| Fleet | `drones >= 1` |
| Runes | `socketSlots >= 1 or next(runes) ~= nil` |
| Ascension | `ascensions >= 1` |
| Tech | any node level `> 0` |

`highestOwnedIndex` walks `BladeRegistry.list()` and returns the position of the
best blade in `state.owned`, so owning Cinder Spike without Scrap Fang counts as
"forged a stronger blade".

*The guide covers the whole loop, in order, eight lessons deep.* Mastery/runes and
tech/ascension were added; both were systems the player met with no card at all.
The counter is `LESSON n OF #STEPS`, so adding a lesson cannot desynchronise it.

**Verification.** Live: layer present, ring around the strike button at
`177,373 537×113` against the button's `182,378 528×104` — 5px proud on all sides,
nothing clipped, card correctly hidden while the ring is up. After three strikes
the ring moved to the heat gauge `177,339 437×38` against `182,344 427×29`, and
after skipping the guide the tracker ringed the real `BladeAction_scrap_fang`
button rather than its tab.

*An escape hatch never sits on the primary action.* The card's `SKIP GUIDE` link
was at y240 while the CTA ran 196..248, and because it was created after the CTA
and shared its `ZIndex`, the label painted straight across the button's bottom
edge — it read as a misplaced control rather than as a secondary action. Sibling
draw order, not position, decides that. The link now sits at 254 with its own
`ZIndex 6`: 6px under the CTA, 20px above the card's bottom edge, and 26 tall so it
is still a touch target. Measured live `334..353` against a CTA ending at `330`,
with zero overlap against any sibling in the card.

---

## ADR-037 — Juice is layered, and every sound comes from an asset that provably exists

**Context.** The click loop had one sound and one effect: a ping with a pitch bump
in the band, and a white flash. A 5x loop played eight times a second sounded
mechanical because every hit was the same tone, and the blade in the viewport did
not answer the hammer at all — the button shook and the model kept turning.

The obvious fix is a real sample pack. The reason it was not done that way is the
one already recorded for the VFX sheets: a marketplace id that has not been
uploaded is a **silent** failure in a published place, and guessing one is worse
than no sound. The 22 generated sheets are still pending upload.

**Decision.**

*Sounds are layered, and the layers are client-shipped assets.* `Sfx` uses three
proven ids from the Roblox client's own `content/sounds` directory:
`electronicpingshort.wav`, `impact_explosion_03.mp3`, `impact_water.mp3`. A strike
is now a high transient over a low body, both jittered 0.95–1.08 so no two hits
land on the same pitch:

| Verb | Layers |
| --- | --- |
| Strike | ping (body) + impact at 2.55× (metal) |
| In-band strike | + ping at 1.5×, climbing 4.5% per streak point |
| Streak complete | impact at 0.55× + rising triad 1.32/1.78/2.38 |
| Vent | water at 1.45× (air) + ping at 0.62× (metal) |
| Forge | impact 0.5× + three pings, 0.05/0.11/0.2s apart |
| Rune | three pings only, 2.0/2.52/3.0 — crystalline, never a strike |

The pool is 14 slots, not 6: one burst can want three layers per click, and reusing
a slot mid-playback truncates the previous hit, which is audible.

*Visual juice answers the hit, not the tick.*

- `Vfx.shockwave` — a transparent frame carrying two `UIStroke`s, scaled outward
  while the strokes fade. The crisp inner ring is the leading edge; the 2.6× wide
  halo is the bloom. A band strike gets a 130px wave, an ordinary hit 88px.
- The stage border (`stageStroke`) is heat-reactive: it ramps from `strokeFaint` to
  the gauge's own colour as heat approaches 65%, turns gold on a full rail, and red
  on a burn-out. `step` breathes it around the resting value the render pass chose.
- The blade's neon parts flash white on every strike. `BladePreview` caches the
  emissive surfaces with their base colours at mount (and again on every mesh
  hot-swap), so the click path is a colour lerp over a small table rather than a
  `GetDescendants` walk.
- Overdrive opening is detected on the `overdriveRemaining` transition, not on every
  sync inside the window — otherwise a 15-second buff would flash fifteen times.

Everything goes through `UiKit.tween` / `Theme.reducedMotion()` per
[ADR-020](#adr-020---every-animation-goes-through-one-function-and-reduce-motion-is-real).
Under reduce-motion the shockwave is omitted entirely (a still ring is a
decoration), the blade does not pitch, and the flash still fades because a fade is
not motion.

**Consequence.** When the real sound sheets upload, `Sfx` is the single file that
changes — every call site is a verb (`strike`, `vent`, `forge`, `rune`, `tech`), not
an asset id.

---

## ADR-038 — One blade per purchase, a guide that never goes silent, and a viewport you can actually drag

Five reports from the same playtest, three of them the same shape: the UI was
telling the player something untrue about what it would do next.

### The blade list opened a whole wave at once

**Context.** Blades were revealed in waves of three, gated on owning the last blade
of the previous wave. Finish a wave and the next three rows became legible in one
frame — a jump, not a reveal.

**Decision.** The list is a staircase. `legibleAt(index)` is true when the index is
the first blade, when the player owns it, or when they own the one before it.
Everything else is fog. A player who owns scattered blades still sees all of them,
so the chain can never hide something already paid for.

The celebration follows: one sound, one flash, one toast naming the single blade
that opened (`"Rivet Edge revealed"`), never a `from → to` range.

**Verification.** Live, fresh save: 2 of 25 rows legible (starter + one target).
After forging that target: 3 of 25 — exactly one new sword.

### The guide went quiet after the runes lesson

**Context.** The card is the teaching surface and the strip is the tracker, and the
strip was hidden for the entire duration of the guide. Between "mastery and runes"
and "bank the run" there is nothing to show, because the ascension lesson waits for
`runSm >= ascendAt`. The screen went silent for minutes, which reads as "the
tutorial ended".

**Decision.** The strip fills every gap. `evaluate` now shows it whenever no card is
on screen and the current lesson has not been delivered yet; `refreshObjective`
gained a `ring()` wrapper so it paints the text without ever touching the guide's
highlight.

**Verification.** Live: after the first three strikes (lesson 1 done, lesson 2 not
triggered) the strip read `GOAL: Forge Rivet Edge (10 / 80)` with the card closed.

### A lesson asked for something the player could not buy

**Context.** The runes card said "Void Shards buy runes" and pointed at the rune
shelf regardless of balance. A player with no shards was being instructed to buy.

**Decision.** `Step` gains optional `bodyFor` and `ctaFor`. The runes lesson picks
one of three scripts from live state — has shards (`SHOW ME`, rings a rune row),
has a socket but no shards (`GOT IT`, explains the drop rule), or neither (`GOT IT`,
rings the mastery card). The ring target moved behind the same check, so it can
never point at a locked button.

### The 3D view could not be dragged

**Context.** `ViewportOrbitController` listened on `viewport.InputBegan`. On this
build that event never fires for mouse buttons — and because the frame was
`Active = true`, every click on it was marked **game-processed**, so the global
listener was blocked too. Dragging the preview did nothing at all.

**Decision.** `Active = false`, and both mouse buttons are handled on
`UserInputService.InputBegan`, gated on the press landing inside the frame
rectangle. RMB works from anywhere inside the view, LMB likewise, and a drag keeps
orbiting after the cursor leaves the frame.

Two coordinate bugs were measured on the way, both of which would have left the
feature broken:

- `UserInputService:GetMouseLocation()` reports from the top of the screen while a
  non-inset `ScreenGui` starts below the top bar. A click at `445,200` read back as
  `GetMouseLocation() = 445,258`. Hover is decided from `InputObject.Position`,
  which shares a space with `AbsolutePosition`.
- `InputObject.Delta` is zero for a synthetic or warped cursor. Deltas are computed
  from successive `Position` values.

**Verification.** Live, by reading the viewport camera's `CFrame.Position`:
LMB drag moved it `3.681,2.789,-7.548 → 7.917,0.912,-3.319`; RMB drag moved it
`7.986,0.820,-3.146 → 6.202,-0.453,-5.754`. Pitch stayed inside the ±40° clamp.

### Two cosmetic corrections

- The forge banner's `⚒` (U+2692) was the only hammer in the UI and rendered as a
  tofu box on clients whose font stack lacked it — the same failure the vent key's
  `⚡` had. Every banner now uses `★`.
- The impact wash was `UDim2.new(1, 0, 1, -22)`, which left a 22px lit strip along
  the bottom of the stage. It is full-bleed now: measured 528×165 against a 528×165
  stage.

---

## ADR-039 — Gamepass art is a third manifest table, and the store badge falls back to the pill

The first approved gamepass badge (`fast_forge`) had to reach the STORE tab without
turning a fresh clone into a wall of empty `ImageLabel`s.

### A third table, not another key in `Assets`

**Context.** `AssetManifest.Assets` is regenerated wholesale by
`scripts/upload_assets.py`: `write_manifest` replaces the table body from the icon
index. Any hand-added key there is deleted on the next upload run.

**Decision.** `AssetManifest.GamepassIcons`, keyed by the same snake_case names
`scripts/generate_gamepass_icons.py` writes (`fast_forge`, `auto_vent`,
`x2_star_matter`, `vip_aura`, `eternal_forge`). The uploader's regex targets
`AssetManifest.Assets = {` and `AssetManifest.Meshes = {` only, so this block
survives regeneration. This is the same reasoning that split `Meshes` out of
`Assets`: different lifecycle, different table.

`gamepassIcon(key)` returns `""` for a missing or placeholder id, not
`rbxassetid://0`. Callers branch on empty to pick a **vector fallback**; a
placeholder id would branch the wrong way and draw an empty `ImageLabel`, which
renders as a grey box and reads as a UI bug rather than a missing asset.

### The badge is 48px, the ring is 2px, and the pill is the fallback

**Context.** `ShopView.buildRow` drew a 56×20 category pill ("FAST", "AUTO") at
`(12, 12)` with the title at x 80.

**Decision.** A pass with art gets a 48×48 circular well at `(10, 20)`, filled with
`Theme.Color.outline`, a 2px `#0F1117` `UIStroke`, and the art `Fit` inside it. The
well is the outline colour on purpose: the generated badge is a disc on transparent
corners, so a near-black well lets those corners vanish into the ring instead of
showing a lighter square behind a circle.

2px is passed explicitly rather than using `Theme.Stroke.thick` (3px). At 48px a
3px ring is 6% of the badge's width and starts eating the art.

A pass with no art — or art whose id has not landed — keeps the text pill exactly
as before. The artifact is unchanged for the four passes that have no badge yet.

`MonetizationConfig.PassDef` gained `icon: string?`, so the wiring lives next to the
pass rather than in a lookup table in the view.

### Measured

Live in the STORE tab, all in 1280×720 design px (canvas scale 0.719):

| Row | Badge | Ring | Text column | Fits |
| --- | --- | --- | --- | --- |
| Fast Forge | 48×48 at (10, 20) | 2px `rgb(15,17,23)`, corner 24 (circle) | x 70, w 214 | title ✓ desc ✓ |
| Auto-Vent AI | none, 56×20 pill | — | x 70, w 214 | title ✓ desc ✓ |
| 2x Star-Matter | none, 56×20 pill | — | x 70, w 214 | title ✓ desc ✓ |
| VIP Quantum Aura | none, 56×20 pill | — | x 70, w 214 | title ✓ desc ✓ |
| Eternal Forge | none, 56×20 pill | — | x 70, w 214 | title ✓ desc ✓ |
| 4 products | none, 56×20 pill | — | x 70, w 214 | title ✓ desc ✓ |

All nine rows are 88 design px tall and every label passes `TextFits`.

### Two independent defects, and the one flag that proves a render

The badge was blank three times before it rendered. The first two diagnoses were
wrong, and both were wrong for the same reason: **no positive signal.** Nothing in
this workspace said "the art is on screen." Two separate defects were real.

**Defect 1 - the raw asset route.** `rbxassetid://` does not work for these Open
Cloud uploads here. Measured with `AssetService:CreateEditableImageAsync`, which
is the same content pipeline `ImageLabel` uses and fails out loud:

| Content | Result |
| --- | --- |
| `rbxassetid://72607419302936` (Image) | `HttpError` |
| `rbxassetid://120466794327225` (earlier Image) | `HttpError` |
| `rbxassetid://99750687814737` (Decal) | `HttpError` |
| `rbxthumb://type=Asset&id=72607419302936&w=420&h=420` | **420x420, RGBA** |
| `rbxthumb://...&w=512&h=512` | `Failed to load texture` (512 is not a served size) |

So `gamepassIcon` resolves through the **thumbnail CDN**, not `rbxassetid://`. The
thumbnail is public and pre-rasterised, which also sidesteps asset permissions. It
is a faithful copy of the art, not an approximation - sampled from the returned
bitmap: corner `(0,0,0,a0)` (transparency preserved), centre `(20,25,35)` ink,
upper field `(193,116,40)` gold.

420 is a served size and ~12x the 34.5 real px the store draws, so nothing is lost.
`AssetManifest.GAMEPASS_THUMB_SIZE` holds it.

**Defect 2 - the art was too dark.** Real, and independent: the first composition
was a steel tool on an obsidian disc, which at the size the store draws it measured
p50 = 28 luminance with 7% of pixels above 120. That is a black circle even when it
loads. See the luminance section below.

The two defects produced the same screenshot, which is why one fix looked like it
had failed when it had only half-worked.

### `ImageLabel.IsLoaded` is the only proof available, and it works

For the whole of this investigation `IsLoaded` read `false`, including on
`rbxasset://textures/ui/common/Brand/Logo.png` used as a control - so it was
dismissed as unreliable and every claim became a measurement of geometry instead.
That was a mistake: geometry proves the frame, never the pixels.

With the thumbnail route in place `IsLoaded` reads **`true`**, and the console shows
no `rbxthumb` failure. It was never broken; it was reporting a genuine non-load.

**So the rule from here: an image is on screen when `IsLoaded` is `true`, not when
the frame has the right size.** The frame was correct and the glass was empty for
three rounds.

Two traps that made the flags look useless:

- `ContentProvider:PreloadAsync` returns `Failure` for *every* content id in this
  session, built-ins included, and fires the callback with a status the caller has
  to read. Do not use it as a pass/fail gate here.
- A failing remote image prints `ContentId: ... failed due to: <reason>`, and an
  absent line means success. Distinguish `Authentication required to access Asset`
  (not distributed yet, or the raw route refusing) from `Asset type does not match
  requested type` (wrong id type) from silence (loaded).

### The badge has a luminance floor, because it is drawn at 35px

The store row is 88 design px, the badge well is 48, and the canvas runs at 0.719
scale, so the badge is **34.5 real px** on screen. That is smaller than the
documented 64px thumbnail target, and it sets a hard rule for the next four
badges: the field has to be bright.

Measured on the shipped art at 48px and 35px downsampled with Lanczos:

| Metric | First composition | Shipped composition |
| --- | --- | --- |
| median luminance (p50) | 28 | **112** |
| share of pixels above 120 | 7.0% | **43.3%** (48px), 41.0% (35px) |
| max | 254 | 255 |

So `_disc` is a gold field (`FIELD_HOT` → `FIELD_DEEP`) and the subject is ink.
Every material moved with it, and each one had to move or it vanished into the
field:

- anvil: steel body → near-black body, `STEEL_LIT` plate band as the only light line
- hammer: steel head → ink head, `STEEL_LIT` bevel and a `SPEC` face cap
- haft: dark gold → walnut brown, `INK` wrap bands
- sparks and shockwave: gold → `SPEC` and `CYAN`
- pre-strike bloom: `GOLD_DEEP`/`GOLD_MID` (invisible on gold) → `FIELD_HOT`/`SPEC`
- rim: lit steel arc (pointless on a bright field) → inset coin bevel, and the
  inner vignette dropped from 0.95 to 0.38 so the rim is not a brown ring

`PASSES` still lists five; `RENDERERS` still has four `None`. `--only auto_vent`
exits non-zero and names the pass, so nothing silently ships a blank badge.

### The things that were never wrong

- The accepted art file is `assets/generated/gamepasses/fast_forge.png`. There is
  no `watermarked_img_9132646308533941993.jpg` anywhere in the repository or in
  the user's Downloads folder; if that file is the intended source, drop it at that
  path and re-upload, because the uploader reads the path, not the name.
- The Open Cloud API key has nothing to do with rendering, and no extra scope was
  needed. It uploads bytes; the client fetches with the player's own session. The
  `asset-delivery-api` 403 seen while diagnosing is a scope on that one endpoint.
- Ownership was never the problem. `game.CreatorId` is `1416845247` and
  `Players.LocalPlayer.UserId` is `1416845247` - the same account that uploaded
  every asset. Every id returned `moderationState: Approved`, `state: Active`,
  `isPublished: true`, and rasterised on the public thumbnail service.

### Final live measurement

`selene src/` 0 errors / 0 warnings / 0 parse errors, `rojo build` 547,574 bytes,
console clean. In the STORE tab, 1280x720 design px at 0.719 canvas scale:

```
Fast Forge  48.0px  loaded=true  rbxthumb://type=Asset&id=72607419302936&w=420&h=420
Auto-Vent AI 48.0px loaded=true  rbxthumb://type=Asset&id=125080652561026&w=420&h=420
2x Star-Matter / VIP Quantum Aura / Eternal Forge / 4 products ..... text pill
```

### Supplied art is a second pipeline, and it is not the generator

`auto_vent` was drawn by an image model, not composed in Python. That splits the set
into two pipelines and they need separate handling.

**The jpg problem.** An image generator returns RGB with the transparency
checkerboard *painted*. Pasting that into the store row gives a grey flag square
around the disc. `scripts/prepare_gamepass_art.py` normalises it: border-connected
low-saturation bright pixels get keyed out (the warm white steam inside the disc is
not border-connected, so it survives), a radial clamp at the 99.5th percentile of
alpha radii kills a stray speck that had dragged the crop square from 980 to 1070,
and the disc is rescaled to the same 0.94 diameter ratio as the procedural badges.

Measured on the shipped `auto_vent.png`: corners `(0,0,0,0)`, alpha bbox
`(14,14,498,499)` on 512, p50 = 179 luminance, 77.7% of pixels above 120, and 76.9%
at 48px. Brighter than `fast_forge`'s 112 because the cyan field is the ground, and
the same rule applies: the field carries the value, the subject is the dark shape.

Random-access crop note: the source disc sat at bbox `(52,52,971,972)`, diameter 921
in a 1024 frame, so the margin was already close to the 0.94 target and no
interpolation lost anything.

**`ImageDraw.floodfill` is a silent no-op in Pillow 13.** It is present, it does not
raise, and it fills nothing: on the `auto_vent` mask it reported 0 pixels where a
BFS found 388,118. The first version of the normaliser used it and produced a
"keyed 0.0% background" pass whose output still looked like a badge, with the
checkerboard intact and the disc 9% too small. The pipeline now uses an explicit
4-connected BFS and prints the keyed percentage, so a regression here is visible as
a number rather than as a shipping bug.

**`SUPPLIED` keeps `--only` honest.** With four `None`s in `RENDERERS`, asking for
`--only auto_vent` used to say "No renderer written yet", which reads as a missing
badge when the badge exists. `SUPPLIED` splits the two answers: supplied passes
report where to normalise them, and only genuinely absent art exits non-zero.

---

## ADR-040 — The badge is 72px, the panel grew to pay for it, and the two Marketplace APIs are not the same API

All nine store rows now show art. Getting there meant three changes that had to
happen in a specific order, because each one constrains the next.

### The badge size is a resolution decision, not a taste decision

**Context.** The first `fast_forge` badge shipped at 48 design px and read as a black
circle. That failure was diagnosed as an art-value problem and fixed as one, but the
underlying number was never addressed: at the 0.719 canvas scale, 48 design px is
**34.5 real px**. Every other thumbnail target in the app is measured in design px and
looks fine on the design frame, which is exactly how a 34.5px element gets shipped.

**Decision.** The well is **72px**, which is **51.8 real px**. The thumbnail behind it
is `rbxthumb` at 420, so there is 8x headroom and no part of the size increase is
interpolation.

**Cost.** The row height went 88 → 104 and the panel had to widen, because a 72px
badge plus a 92px price plate does not leave a usable description column at 432.

### The panel pays for it, and the forge card is what gets spent

**Context.** `Layout.SIDE_WIDTH` was 432, which put the forge card at 806. Rows were
396 wide inside a 400 scroll.

**Decision.** Panel **432 → 468**, forge card **806 → 770**. The text column went
`x 70, w 214` → `x 96, w 224`: the description got *wider* while the badge got 50%
bigger. Price plate unchanged at 92 pinned to `1, -104`, still 8px clear.

The forge card is the right thing to spend. It is a 3D viewport with a full-width heat
rail, so width is slack there; the store column had no slack left. Because the
tutorial ring and the objective strip both read `Layout`, they followed without edits.

Measured live, 1280x720 design px at 0.719 scale:

```
panel=468  row=432x104  headers={GAME PASSES / BOOSTS & UTILITY}
badge=72 r=36 loaded=true   descW=224   titleFits=true  descFits=true   x9 rows
```

### Products get icons through the same path, not a parallel one

**Context.** `ProductDef` had no `icon` field and `ShopView` hardcoded the product row
to `icon = nil`, so four rows could never show art no matter what was uploaded. That
was deliberate: the pass path was proved first.

**Decision.** `ProductDef` gained `icon: string?`, the four products got their keys,
and the row passes `def.icon` through — so products inherit the identical fallback
(pill when the key is missing or the id is empty) with no second code path. The header
above the passes read `PERMANENT UPGRADES` and now reads `GAME PASSES`; the products
keep `BOOSTS & UTILITY`.

### Open Cloud can create the listings, but not with this key

Roblox shipped both endpoints in December 2025, still BETA:

| item | endpoint | scope |
| --- | --- | --- |
| Game Pass | `POST /game-passes/v1/universes/{universeId}/game-passes` | `game-pass:write` |
| Developer Product | `POST /developer-products/v2/universes/{universeId}/developer-products` | `developer-product:write` |

Measured against this key on universe `10775534186`:

| request | result |
| --- | --- |
| `GET /game-passes/v1/universes/.../game-passes` | **200**, `{"gamePasses":[]}` (public listing, no scope needed) |
| `GET .../game-passes/creator` | 403 `Scope not authorized` |
| `POST .../game-passes` | 403 `Scope not authorized` |
| `POST /developer-products/v2/...` | 403 `Scope not authorized` |

So the API is real and the key is read-only on it. Two traps worth recording:

- The body is **`multipart/form-data` with an `imageFile` part**, a file upload. A JSON
  body with `imageId` is wrong, and because a missing scope also returns 403, a wrong
  body and a wrong key look identical from the outside. The first attempt here was
  JSON with `imageId` and blamed the scope for both.
- `URLError`-free 404s appear on plausible paths: `/developer-products/v1/...` and
  `/game-passes/v1/openapi.json` both 404, while the real `v2` POST returns 403 rather
  than 404. A 404 means the path is wrong; a 403 means the path is right and the key is
  thin. Reading those two as the same thing wastes a pass.

`scripts/create_store_items.py` encodes all of it: `--check` prints the plan without
writing, the bare run creates and prints the id map, `--apply` patches
`MonetizationConfig.luau`. It exits with the exact Creator Dashboard edit when it hits
the scope gate instead of pretending it worked.

### The patterned-plate case

`x2_star_matter` came back from the generator as a disc on a dotted grey plate inside
a white margin. The background key removed only the white band, so `disc bbox` was the
whole canvas and the plate would have shipped as a square behind the circle. `--ring-clamp`
cuts at the disc's own ink contour instead: it finds the outermost radius whose full
circumference is dark, walks outward over the anti-aliased edge, and falls back to the
alpha percentile when no ring clears the threshold. Result on that file: keyed 3.4% →
clamped at r=440 → bbox `(71,71,952,952)`, and the plate is gone.

---

## ADR-041 — Fifteen list badges get a permanent folder, a shared well, and rows that grew to fit them

### Art lands in `assets/badges/`, not in `assets/generated/`

**Context.** The fifteen badges came out of an image model as
`Gemini_Generated_Image_<hash>.jpg`, all 1024x1024, all circular discs on a
checkerboard. `assets/generated/` is pipeline output that scripts rewrite;
hand-curated art that cannot be regenerated does not belong there.

**Decision.** `assets/badges/` holds the shipped 512px PNGs. Originals go to
`assets/badges/source/` with a contact sheet, so the JPEG a badge was cut from is
never lost. Filenames are slugs from day one (`fleet_sweep.png`, `rune_ember.png`,
`tech_crit.png`), which is what the manifest and the configs key on, so no rename
step exists between download and code.

All fifteen were normalised by `scripts/prepare_gamepass_art.py` with
`--no-preview`, producing transparent corners and the same 0.94 disc ratio the store
badges use. One of them, `fleet_sweep`, came back on flat white instead of a
checkerboard; the keyer treats both as border-connected bright pixels, so the output
is identical, but the prompt guide now asks for the checkerboard explicitly.

### One well, three sizes

**Context.** `ShopView` already had a local badge well: plate, `Fit` image, 2px ink
ring, 1px accent ring. Three more views needed the same object at 44, 60 and 56 px.

**Decision.** Extract `UiKit.badgeWell(parent, { image, size, accent })`. It returns
nil when the image string is empty, which is the honest no-art path: callers skip the
well and the row keeps its text layout. `ScaleType.Crop` rather than `Fit` because the
source is a square badge with transparent corners, so filling the circle is exactly
right.

**Consequence.** `ShopView` keeps its local version for now. It draws at 72px with a
`Fit` scale and predates the helper; migrating it is a separate, testable change, not
a drive-by during an art drop.

### Rows grew where the art needed air

| list | art | before | after |
| --- | --- | --- | --- |
| Fleet | 44px | row 48, band 186, shelf 152 | row 54, band 204, shelf 170, pitch 56 |
| Runes | 60px | row 68 | row 78, effect column 226 → 200 |
| Tech | 56px | row 106 | unchanged; name and description shift to x 80 |

The tech card is the one that did not need height: a 56px badge fits beside a 21px
title and a two-line description inside 106px, and the effect row, pips and buy
button keep their existing full-width positions. The rune row needed both height and
a narrower text column, because its effect line sits beside the count and the action
button; at 14px the longest description is 154px, so 200px leaves 26px of clearance
without wrapping.

Fleet and runes scroll, so the height is paid for by scrolling, not by cutting copy.

### Measured

```
Mission_sweep  row 412x54   art 44 loaded=true  labels fit 2/2
Rune_prism     row 432x78   art 60 loaded=true  labels fit 3/3
Tech cards x8  row 432x106  art 56 loaded=true  labels fit 4/4
```

Seven of the eight tech thumbnails read `IsLoaded=false` on the first sample and
`true` after a scroll; that is CDN fetch latency for new uploads, not a bad asset.
The same pattern showed on the store badges and resolved within a minute.

### Config carries the key, not the view

`ExpeditionConfig.Mission`, `RuneConfig.Rune` and `TechTreeConfig.Node` each gained
`icon: string?`. The views read `def.icon` and pass it to `AssetManifest.uiArt`. No
string concatenation in the view and no id in the view: the same rule the store
follows, so a re-upload is a one-line manifest change.

---

## ADR-042 - Bigger list art, and a Salvage loop that answers the session-time notes

### The ask

Two things arrived together: make the list icons bigger (store untouched), and
refactor the loop against `incremental/video-06-mvp-rng-session-time.md`. The
second is the one with design weight, so it goes first below.

### What the video actually asked for

Four levers, in order of leverage:

1. Pre-acquisition RNG. The roll happens *before* the reward, so the reward has
   anticipation.
2. A real time hurdle. A hatch timer is what stretches a session and what makes a
   rejoin worth something.
3. A collection that cannot be completed in one sitting. That is D1 and D7.
4. Low cognitive load. One verb, one decision per surface.

Speed-to-market, the video's headline, does not apply: this game is past MVP. The
loop shape is what transferred.

### The Salvage rack

One new band in the Fleet tab, below the expeditions.

| rarity | weight | crack | Aether | Cores | Shards | sigil chance |
| --- | --- | --- | --- | --- | --- | --- |
| Scrap | 58 | 0s | 60 | 0 | 0 | 8% |
| Alloy | 28 | 45s | 260 | 1 | 1 | 30% |
| Prime | 10 | 180s | 1200 | 5 | 4 | 70% |
| Void | 4 | 600s | 7000 | 22 | 14 | 100% |

**Rarity is rolled at drop.** The sealed slot is drawn in its rarity colour, so
the player can see a Void cache and want it before opening it. A mystery box with
the lid painted on is the failure mode this avoids.

**Cracking runs on `os.time()`.** Not a client tween, not a per-session counter. A
Prime cache started at minute two is still cracking at minute five; a Void cache
started before bed is ready on rejoin. That single field is the session stretcher
and the rejoin reason.

**The meter stops when the rack is full.** Three slots, 40 strikes per drop. A
fourth cache cannot drop, so hoarding is a visible decision. The meter turns amber
and says `RACK FULL`.

**Rewards are computed at claim.** A cache parked overnight is worth what the
player's blade is worth when they open it, not what it was worth when they were
small. This is the opposite of the expedition snapshot, and deliberately so:
expeditions are commitments, caches are found objects.

### The sigil codex

Twelve sigils, four sets of three, 12% chance weighted by rarity up to a guaranteed
Void drop. A completed set is a permanent multiplier, and the four sets map onto
the four rune stats so the bonus code is the same shape as `RuneConfig.sum`:

| set | stat | bonus |
| --- | --- | --- |
| Ember | click | +6% strike |
| Tempo | cool | +8% cooling |
| Edge | crit | +3% crit |
| Prism | vent | +12% vent yield |

A sigil roll on a completed codex melts into bonus Cores rather than paying
nothing. A 1-in-1 duplicate is the one drop that must never read as a miss.

`SalvageConfig.bonus(owned)` returns the same `{ clickMult, coolMult, critChance,
ventMult }` shape as `RuneConfig.sum`, so:

- `clickYield` multiplies `clickMult`
- `strike` adds `critChance` to the crit roll
- `vent` multiplies `ventMult`
- the heartbeat multiplies heat decay by `coolMult`

No second code path, and the UI never computes a bonus it only displays.

### Server authority and cost

`crackCache` and `claimCache` are two new actions registered in `Main.server`.
Index validation, rarity validation and clock comparison are all server-side.
Nothing the client sends decides a reward.

The payload grew by `cacheMeter`, `cacheGoal`, an array of at most three
`{ rarity, readyAt, secondsLeft }`, `sigils`, and `codexSets`. That is roughly 120
bytes at 10Hz, against a payload that already carries the socket rack and the
tech map. Acceptable; if it ever matters, `sigils` can be sent as a bitfield.

`DataManager` schema 2 -> 3. `sanitiseCaches` drops a cache with an unknown rarity
rather than re-rolling it, because a free re-roll on a corrupted save is a free
upgrade. `sanitiseSigils` drops unknown ids.

### Icons got bigger; the store did not

The store badge was already tuned to its row and its luminance floor was measured
at the current size. It stays at 72 design px.

| list | before | after | row | band |
| --- | --- | --- | --- | --- |
| Fleet | 44px | **64px** | 54 -> 72 | 204 -> 266, shelf 170 -> 228, pitch 56 -> 76 |
| Runes | 60px | **88px** | 78 -> 104 | scroll pays for it |
| Tech | 56px | **80px** | 106 -> 132 | name/description move to x 104 |

Fleet text starts at x 84 and the mission rows are 412 wide, so the name column is
`1, -220` = 192px, which clears the 104px SEND button by 16px. Rune text starts at
x 108 with width `1, -238` = 194px, clearing the action button by 4px at the
longest description (154px at 14px). The tech card is the only one that needed
height: an 80px badge beside a 24px title and a two-line description does not fit
in 106px without clipping the description's second line.

### Measured live, 1280x720 design px on the 0.719 canvas

```
Mission_sweep  row 412x72   art 64  loaded=true  labels fit 2/2
Rune_ember     row 432x104  art 88  loaded=true  labels fit 3/3
Tech card x8   row 432x132  art 80  loaded=true  labels fit 4/4
Salvage band   432x164  slots=3
Codex band     432x142  rows=4
```

Exercised: 40+ strikes dropped a Scrap Cache, the slot read `CRACK`, a tap moved
it to `CLAIM` with `+60 AE`, and a second tap emptied the slot and paid out.
Console clean, `selene` 0/0/0.

### What was rejected

- **A second currency for caches.** The loop already has four. Caches pay the
  three that exist plus sigils.
- **A timer on the core strike.** The anvil is the game. Putting a cooldown on it
  to stretch a session would trade the only good thing for a metric.
- **A battle pass.** Not earned by this video, and not shippable without the
  Marketplace scope that is still missing.
- **Art as a dependency for the new band.** The rack is typographic and works at
  zero uploads. `user-manual/16-salvage-art-prompts.txt` holds the eight optional
  images, and the codex does not need them to function.

---

## ADR-043 - The vault is a room, not a tab, and the forge roll is a stage

### The ask

The forge shipped with its inventory squeezed into the side panel's Blades tab.
Three problems showed up the moment a player owned more than four copies:

1. The tab was **468px wide**. Two cards per row, each too narrow for a stat row,
   so the drawer and the card both wrapped to three lines.
2. **Every copy was its own card.** Four Standard Rusted Cleavers buried every
   other blade in the game.
3. **Melt was one copy per confirm.** Salvaging ten spares meant ten dialogs.

Rolling had a matching problem: the server answered the forge, the viewport
punched and flashed, and the blade simply appeared. There was no object between
the press and the reward, so there was nothing to anticipate.

### The ask, answered

| ask | shipped as |
| --- | --- |
| wider UI | canvas 1280 -> **1360** design px, side panel 468 -> **500**, forge card 770 -> **818** |
| a real inventory surface | `InventoryModal`, a canvas-level overlay at 86% x 84% of the canvas |
| stop the duplicate wall | copies grouped by `id|variant` through `InventoryModel.group` |
| batch melt | `SELECT DUPES` -> `MELT n +N` -> `salvageMany` in one request |
| a detail surface | sliding `VaultDrawer`: nine stat rows plus equip / reroll / melt |
| a crate | `CrateStage` in `ForgeView`: slam, six accelerating beats, hold, shatter |

### Why the width went to 1360 and not to the viewport

An elastic canvas was built, measured, and pulled. `UiKit.screen` widened the
design space to `viewportWidth / scale` and returned it, `Layout.applyWidth`
recomputed the panels, and it worked on the first frame: 1213px viewport, 1686px
design space, forge card 818 -> 1140. It broke on the second frame that mattered,
which is any resize. Every panel positions itself from `Layout` **at build time**;
moving the width afterwards needs resize hooks on the forge card, the side panel
and the objective strip, and none of them have one. A phone rotating would leave
every panel sized for the previous orientation.

A fixed 1360 canvas letterboxes on anything wider than 16:9 and is worth less
space than an elastic one, but it is correct at every orientation and needs no
lifecycle work. 1360 is the point where the forge card gains 48px without the
side panel paying for its own growth.

One bug came out of that experiment and stayed fixed: the old `apply()` fitted
against `gui.AbsoluteSize`, which is a **800x600 placeholder** on the frame a
ScreenGui is created. The canvas is now fitted against
`camera.ViewportSize - GuiService:GetGuiInset()`, which is the box the engine
actually lays the ScreenGui out in. Measured live at 0.7194 scale, 978x518
rendered from a 1360x720 design space.

### Grouping lives in a module, not in the view

`InventoryModel.group` is the only place that decides two copies are the same
thing. The grid, the drawer and the footer all read it, and `meltable` /
`meltValue` mirror the server's rules (never the equipped copy, never the last
copy) so the count on the button is the count the server receives. A client that
computed that number twice would eventually show `MELT 4` for three valid picks.

`Group.repUid` is the equipped copy when the group holds it, otherwise the first.
That is the uid the drawer's EQUIP and REROLL act on. MELT is the exception: it
takes `detailMeltTarget()`, the first uid that is *not* equipped, because keying
the melt off the representative refused every duplicate of the blade in hand,
which in practice is the second starter blade every player owns.

### The toolbar is module functions, not closures

`selectDupes`, `selectionSummary`, `meltSelected`, `commitMelt`, `equipBest`,
`meltDetail` and `commitDetailMelt` are exported from `InventoryModal` rather than
captured inside `build`. Two reasons, one of them the real one:

- The confirm dialog's accept button and the melt body must be the same code, or
  the number in the dialog can drift from the number sent.
- Studio's `VirtualInputManager` needs the `RobloxScript` capability, so
  automated verification **cannot click a button**. A `BindableFunction` named
  `QF_Dev` runs its callback in `Main.client`'s VM and calls those same functions.
  It exists only when `RunService:IsStudio()`, and it dies with the GUI.

That seam found two real defects that a screenshot would not have: the melt count
never repainted because `refreshFooter` looked for a child named `Face` on a
button built by `UiKit.button` (which keeps its label on the button itself), and
`forgedAt` was missing from the inventory payload entirely, so every drawer read
`not recorded`.

### The roll is a stage, not a pulse

`CrateStage` is a clipped, transparent layer above the blade viewport and below
the reveal wash. The crate is primitives: a 132px box, two bands, four rivets, a
lit seam and a rotated core. A mesh would need an upload and moderation; this
reads at 132px and tweens with the same `Theme.tween` as everything else.

The sequence, measured live at 0.7194 scale:

| t | what happens |
| --- | --- |
| 0.00s | crate drops from y -0.45 to centre, 150px -> 132px, `Sfx.roll()` |
| 0.18s | slam: viewport shake 16, first `Sfx.rollTick` |
| 0.19-1.07s | six beats: rotation += 14..84 each, seam 0.60 -> 0.12, tick pitch climbs |
| 1.07-1.41s | hold: seam tweens to 0 (full glow), nothing moves |
| 1.41s | shatter: crate hidden, `Vfx.shockwave` + `Vfx.burst` + white flash + `Sfx.forge()`, then `celebrate` and `Sfx.result(rank)` |

The server's answer is parked in `pendingRoll` by `celebrate` and released at the
shatter, so packet timing never decides when the blade appears. A refused roll
never produces an answer, so the wait is bounded at 3.2s and the crate fizzles
instead of pretending.

`Theme.reducedMotion()` skips the crate entirely: the reveal is the interaction,
and the server call is not delayed.

### What was rejected

- **Rewriting `InventoryView` in place.** The sidebar tab and a full-screen
  overlay share almost no layout, and a rewrite keeps the broken thing alive until
  the new one is perfect. The tab was deleted. `InventoryView.luau` is gone.
- **Keeping the Blades tab as a summary that opens the vault.** Two doors to one
  room, and the one in the header is the one a player can find at 84% of the
  screen. The `VAULT` key replaced it.
- **An uploaded gear icon.** Moderation before it renders, and the icon has to
  scale with the button. The gear is eight radial teeth and a bored ring in 17
  primitives.
- **A mesh crate.** The upload pipeline is already the bottleneck for 22 VFX
  sheets and 26 blade meshes. The crate is three frames and a seam.

### The numbers

```
canvas       1360 x 720 design   0.7194 scale   978 x 518 rendered
forge card    818 x 576 design   side panel    500 x 576
roll plate    128 x 46 design    vault key      60 x 34
gear key       36 x 34 design    gear frames     10 primitives
vault panel    86% x 84% of canvas
card          193 x 85 rendered (vault grid, 3 columns at 1360)
```

## ADR-044 - The fleet is a ladder, and the anvil is the whole stage

### The ask

Two dead ends showed up once the forge was a real surface.

The fleet was a **flat list**: one drone type, one price curve, a hard cap of 50,
and `passiveYield` multiplying a single `drones` count. Every purchase after the
first dozen was priced out of reach by `1.15^owned` while paying the same flat
0.6, so the tab had nothing left to say by the time a player had twenty of them.
Two upgrades existed (cost growth, capacity) and neither of them was **content**.

The forge had a **black box** under the blade. The viewport was a 486px stage
with the heat rail, streak pips, yield readout and `STRIKE THE ANVIL` prompt
stacked in a separate panel underneath it, and the strike target was a 128x46
button in that panel. The largest, most obvious object on the primary screen was
not clickable, and a third of the card was a dead strip of `Theme.colors.bg`.

### The ask, answered

| ask | shipped as |
| --- | --- |
| drones worth buying forever | `DroneRegistry`: five rungs, no cap, efficiency rising across tiers |
| a visible ladder | five 83x50 keys in the Fleet tab, each with owned count and an unlock meter |
| each rung looks different | per-tier hull and glow colours, rung-specific hardware, mesh only on rung 1 |
| the whole viewport strikes | `StrikeButton` is a transparent full-bleed layer over a 486px stage |
| no black box | heat, streak, yield and prompt painted on a scrim inside the stage |
| no uploaded UI icons | backpack and gear drawn in `UiKit` style from primitives |

### The ladder

`DroneRegistry` is shared code, because the server prices a drone and the client
prints its price, its gate and its yield. Two copies of a five-row table drift
the first time a number moves.

| tier | name | first copy | growth | yield/s | unlocks at |
| --- | --- | --- | --- | --- | --- |
| `scrap` | Scrap Drone | 5 AE | 1.16 | 0.6 | 0 owned |
| `molten` | Molten Core | 150 AE | 1.17 | 22 | 15 owned |
| `quantum` | Quantum Vector | 6 000 AE | 1.18 | 900 | 45 owned |
| `celestial` | Celestial Swarm | 250 000 AE | 1.19 | 42 000 | 120 owned |
| `cosmic` | Cosmic Dreadnought | 12 000 000 AE | 1.20 | 2 400 000 | 300 owned |

Two numbers decide whether buying up is worth doing, and they pull in opposite
directions:

- **Inside a tier**, `baseCost * growth^owned` means the hundredth Scrap Drone
  costs 1.16^99 = 2.3 million times the first. That is the pressure that pushes
  a player to the next rung.
- **Across tiers**, yield per Aether at the first copy rises: 0.120 for scrap,
  0.147 molten, 0.150 quantum, 0.168 celestial, 0.200 cosmic. That is the reward
  for climbing.

The ratios matter more than the numbers. Late-scrap efficiency is 0.147, so
Molten opens at exactly the rate the hundred-and-something-th scrap drone was
already paying, and every rung after that is strictly better than the ceiling of
the one below. A player is never wrong to buy the newest unlocked rung, and is
never forced to.

The gate is **total drones owned**, not currency. A currency gate would need a
second wallet or a second readout; a fleet-size gate is a number the tab already
prints on every key. It also means the ladder cannot be skipped by a lucky
payout: 300 drones is 300 clicks of buying, at any rung.

There is no cap. `DroneRegistry.SaneMax = 1e9` exists to clamp an expedition
squad and a hostile payload, not to stop a player. `DroneRegistry.cost` clamps
to `1e308` because `1.16^owned` reaches `inf` around owned = 4 000, and a button
that prints `inf` for the price is worse than one that prints an absurd number.

### The migration is one line of arithmetic

`ProfileState.drones: number` became `ProfileState.fleet: { [string]: number }`
and the save schema went **4 -> 5**. `DataManager.reconcile` moves a legacy
count into the cheapest rung (`fleet.scrap = drones`) and drops the old field,
because a legacy player's drones were all scrap drones by definition. `fleet` is
sanitised on load the same way the rest of the profile is: unknown tier ids are
dropped, counts are floored and clamped, and a non-table becomes `{}`.

`SyncPayload.fleet` ships the ordered entry list, not the raw map, so the Fleet
tab never sorts five keys on a 10 Hz repaint. Each `FleetEntry` carries `id`,
`count`, `cost`, `bulk`, `unlocked` and `unlockAt`; the buy dock prints from the
entry and the server prices from the registry, and both read the same function.

`buyDrones` takes `{ id, count }`. A bare number still means "the best unlocked
tier", because that is what the old single-button payload was, and a client that
has not reloaded should not buy the wrong thing.

### An expedition spends the cheapest drones first

`dispatch` deducts from the bottom of the ladder up. A mission costs 5 drones;
five scrap drones produce 3/s and five cosmic drones produce 12M/s, so the same
mission taken off the top of the fleet would cost four million times the income
for the same Aether. Cheapest-first is the only reading that does not punish a
player for owning good drones.

### The stage is the strike target

`ForgeView` now builds one 486px stage below the banner and paints everything
inside it:

| layer | z | what it is |
| --- | --- | --- |
| blade viewport | 1 | `BladePreview` at `frameFill 0.64`, `aimBias 0.13` |
| `HudScrim` | 6 | 148px gradient bottom band, `BackgroundTransparency` graded |
| `HeatGauge` | 7 | 578x40 rail at `1, -64`, CORE HEAT label over it |
| `VentStrip` | 7 | 132x40 vent key at the rail's right |
| `StreakRail` | 7 | 714x20 pips at `1, -88` |
| `StrikeButton` | 8 | 746x450 transparent `Active` layer, `Activated` fires a strike |

The scrim exists because the blade is rendered, not composited. A gauge drawn
straight onto a lit render is unreadable wherever the emissive trim passes under
it, and a `UIGradient` on a 148px band costs less than a texture and needs no
upload. `StrikeButton` sits **above** the scrim and below nothing, so the HUD
labels are visible but every pixel of the render is a strike, including the
pixels under the rail.

`BladePreview.mount` gained `opts { frameFill, aimBias }`. The forge passes
`0.64` and `0.13`: a taller stage wants a bigger blade, and the hilt has to clear
the heat rail, so the aim point drops from the model centre to 13% below it. The
vault preview and the forge preview now share one framing function with two
number pairs instead of two copies of the same camera maths.

### What was rejected

- **Keeping `droneCap` as a "soft" ceiling.** A cap is a wall with a number on
  it, and the number was the only thing the old tab had to say after 20 drones.
- **A mesh per rung.** 26 blade meshes are already unauthorized in this Studio
  session and four more uploads is four more moderation waits. Rungs 2-5 are
  procedural: exhaust bells, photon cubes, satellite pods, outrigger pods, on a
  1.0-1.18 scale staircase. The silhouettes read apart at 220px.
- **Uploaded backpack and gear icons.** Same reason as the crate: moderation
  before it renders, and an icon has to scale with its key. Both are drawn as
  `UiKit`-style primitives with a 2px `#0F1117` outline, nine frames for the
  backpack and eleven for the gear.
- **A second price table on the client.** The Fleet tab prints `cost` and `bulk`
  straight from the payload entry, which the server built from `DroneRegistry`.
- **Helper copy under the buy dock** ("drones in flight earn nothing", "prices
  rise with every copy"). The meter shows the gate and the label shows the
  price. A player who can read a number does not need the sentence.

### The numbers

```
canvas         1360 x 720 design   0.7194 scale   978 x 518 rendered
forge card      818 x 576 design
stage           746 x 450 rendered  (486 design px tall)
StrikeButton    537 x 324 rendered  at 213,220  (746 x 450 design, full bleed)
HeatGauge       578 x 40 design     at y -64     VentStrip  132 x 40
StreakRail      714 x 20 design     at y -88     HudScrim   746 x 148
vault key        40 x 34 design  (9 icon frames)
gear key         36 x 34 design  (11 icon frames)
FleetHero       464 x 236 design   DroneViewport 448 x 220
DroneLadder     464 x 82 design    5 rungs 83 x 50
buy dock        208 x 46 design    (BUILD 1 / BUILD 10)
FleetStrip      464 x 64 design
```

Drone silhouette on the stage, measured through `Camera:PointToObjectSpace` at
`distance = 8.8`, `centre = (0, -0.42, 0)`:

```
scrap      27 parts   x 125..201   y 31..113
molten     45 parts   x 117..205   y 34..110
quantum    53 parts   x 119..204   y 36..107
celestial  77 parts   x 109..227   y 33..111
cosmic     99 parts   x 104..232   y 30..114
```

220px of stage, 448px of width, and every rung lands between y 30 and y 114: the
name plate holds the top 30px and the buy dock the bottom 42px, so no rung can
grow into either.

---

## ADR-045 - The vault is a split view, and a favorite is a promise

### The ask

The full-screen vault was a grid with a drawer. Three 268px cards per row at
1360 design px, a 344px drawer that slid in from the right when a card was
clicked, and a `STATS` sub-button on every card. Clicking a card **toggled a
batch selection**; the drawer was the only way to see a blade's numbers.

That is three gestures for one job. Reading a card meant click, wait for a
slide, read, close. Melting one spare meant the same drawer. And the drawer was
laid out as two columns of label and value with different vertical offsets, so
the numbers drifted a line apart at some sizes.

### The ask, answered

| ask | shipped as |
| --- | --- |
| four columns | 221 x 184 cards, 14px gap, 926px of grid |
| a live render per card | `ViewportFrame` thumbnails, no letter plates |
| clicking inspects | `VaultCardHit` opens the inspector on that group |
| no STATS button | the card click is the stats button |
| a permanent inspector | 380px pane, tall turntable, six stat rows, three-key dock |
| favourites | per-uid set, server-owned, protected from both melt paths |
| batch melting survives | `SELECT DUPES` then `MELT SELECTED`, no per-card ticks |
| a capped room | `Config.InventoryMax = 60`, the forge refuses past it |

### The geometry is the decision

The panel is 94% of a 1440px canvas: 1354 design px. Four 221px cards and three
14px gaps is 926. The inspector is 380. The 12px gutter between them and the two
18px outer pads are the rest: 926 + 12 + 380 + 36 = 1354.

The ticket asked for a ~32% inspector. 380 of 1354 is 28%. Four columns is the
hard requirement and 32% would force 3 columns at this width, so the pane takes
the largest width that keeps four cards per row. The inspector is permanent, so
it is not a loss of usable area: the pane is the point.

### Favourites are a promise

A favorite is stored as `favorites: { [uid]: boolean }` in the profile, schema 6,
mirrored into the sync payload so the grid can paint the star without a fetch.
It is a promise with three parts:

1. **The server enforces it, not the UI.** Both melt paths refuse a favored uid
   (`salvage`, `salvageMany`), so a stale client cannot melt one.
2. **It survives the list.** `sanitiseFavorites` drops uids that no longer exist,
   which is what stops a melted copy leaving a permanent phantom in the filter.
3. **It is a preference, not an asset.** Ascension clears the inventory and the
   set with it, because the uids it protects are gone.

Verified live: favoriting one of two selected spare copies dropped the batch from
2 picks to 1, and a direct `salvage` on the favored uid left `invCount` at 17.

### Card clicks are not ticks

The old card click toggled batch selection, which meant the most common gesture
(a player reading their own blades) shared a control with the least common one
(melting spares). The run changed that:

- **Body click** inspects. Always. It never changes the selection.
- **`SELECT DUPES`** selects every group with more than one copy. Groups holding
  the equipped copy are included; the pick builder drops that uid, so the batch
  melts the spares and never the blade in hand.
- **`MELT SELECTED`** is the only card-driven melt, and it always confirms.

`InventoryModel.meltable` is the single place the rule lives: not equipped, not
favorite, never the last copy. The footer count and the server's answer read the
same table, so the number in the dialog is the number the server is asked for.

### Thumbnails are a window, not a wall

Sixty cards would be sixty `BladeModelBuilder` models and sixty cameras. The
grid builds a render only for rows inside the scroll window (plus one card of
margin), on a 240ms tick, and clears the model when the card leaves. A fifteen
card inventory measured 15/15 built; a sixty card inventory would hover around
12 mounted. Each model is 3 to 4 parts on the procedural path.

The rarity glow under each render is three nested rounded frames at 116 / 88 / 62
and rising transparency, because a UI fill only interpolates linearly: a single
gradient in a card corner reads as a stripe, not a bloom.

## ADR-046 - The roll price ramps 5% per roll and resets with the banner

The forge charged `tier.cost` flat: 50 Star-Matter for the first roll of a
banner and 50 for the hundredth. A player who could afford one roll could afford
every roll, which removes the only reason to bank income between them.

The price is now a function of the rolls already taken at the current banner:

```
cost = floor(tier.cost * min(1.05 ^ rolls, 12))
```

Three properties matter:

- **It is bounded.** `1.05 ^ rolls` overflows to `inf` around 14 000 rolls on a
  double; the clamp keeps the number finite so the button prints a price instead
  of `inf`.
- **The ceiling is reachable and survivable.** 12x base arrives at
  `ceil(ln 12 / ln 1.05) = 51` rolls. Past that the price is flat again, so a long
  session never prices the loop out of existence.
- **It resets per banner.** `forgeRollTier` tracks which banner the counter
  belongs to; crossing a tier boundary zeroes `forgeRolls`, because the new
  banner already costs more and carrying the ramp would double-charge the same
  progression step. Ascension resets both.

The server owns the number and publishes it as `forgeCost`, so the button, the
refusal message and the charge cannot disagree. Verified live across two rolls:
`4 000 000 -> 4 200 000 -> 4 410 000`, with `rolls` at 1 and 2.

## ADR-047 - Onboarding is one card on the first join, and then nothing

### What the old guide did

`TutorialController` held eight lessons. Each one opened a centred modal when
the player crossed a threshold: heat 55, vent, first forge, first fleet purchase,
first rune, ascension, tech. Between cards it showed a strip along the top of the
forge card naming the next goal, and after the last card the strip stayed for
the rest of the session.

That is eight interruptions plus a card that never leaves. It also had a bug
that made it worse: `modalCta` was never assigned, so the CTA button only hid the
card. The guide advanced by itself when the player happened to satisfy the next
step's predicate, which is a pop-up arriving mid-swing with no click behind it.

### What it does now

One card, on the first join, with one CTA. Dismissing it writes `guideSeen` and
`tutorialCompleted`, and the controller stops: no second card, no strip, no
ring, no fallback card on a slow join. The top bar's "?" button is the only way
to see it again, and replaying it does not touch the flags.

The strip is gone from the module and from `Layout`. Its share of the status row
went to the rate strip, which is now the full width of the forge card (878px)
instead of a 284px pill with 594px of empty band beside it.

`TutorialController` went from 1389 to 884 lines: the strip, the tracker, the
five-step tab cues and the four helpers that only those lessons used are gone
with them.

The one seam this added is `guideReset`, which clears both flags so QA can replay
a first join without wiping a profile. It refuses outside Studio, because
`tutorialCompleted` gates a one-time reward.

## ADR-048 - The canvas is 1440x720, and the side panel is 520

Four vault columns need 926px and the inspector needs 380. At the old 1360 the
two do not fit, so the canvas grew. The side panel grew with it, from 500 to 520,
because its store rows were already at the limit of a 72px badge plus two lines
of 14px copy.

| | before | after |
| --- | --- | --- |
| canvas | 1360 x 720 | 1440 x 720 |
| side panel | 500 | 520 |
| forge card | 818 | 878 |

The canvas stays fixed. ADR-043 records what an elastic canvas did to every
panel on resize: a `UIScale` fit that recomputes panel sizes mid-resize is a
layout that reflows under the player's cursor. One number moved, every offset
scaled with it, and the 16:9 composition is unchanged.

At a 1036x518 viewport the fit is 0.7194, which is the scale every measurement
in this repo divides by.

## ADR-049 - Sinks scale with lifetime Star-Matter, and drones scale by its root

A fixed price table is only a sink while the income it was tuned against still
applies. Drones multiply `passiveYield` by the blade multiplier, so a late
account earns in seconds what the tier-5 banner was priced to cost in hours; the
forge becomes a free purchase and the ladder stops being a ladder.

The anchor is `lifetimeStarMatter`: monotonic, survives ascension, and it is the
number that actually grew. The curve is

```
progressScale(lifetime) = min((lifetime / 1e9) ^ 0.5, 1e4)
```

which is exactly `1` below the reference, so no existing early-game price moved.
`ForgeConfig.rollCost(tier, rolls, scale)` takes the multiplier as an argument
because the module is shared and the profile is not; the server applies it last,
so the within-banner ramp and the account growth multiply instead of one
swallowing the other.

Drones take the square root of the same number, and the reason is asymmetry in
the income, not taste: Star-Matter income scales with the blade multiplier, and
Aether income does not scale with anything except vent multipliers, which are
finite. A linear scale on the Aether ladder would price it out of existence the
moment a player rolled a good blade. The square root at least keeps the first
ten rungs honest.

The cap (`1e4`) exists because the ramp ceiling (`12x`) multiplies with it, and
`120 000x` base is already a number no profile has walked to. The cap is a
guardrail, not a design target.

Rejected: run Star-Matter as the anchor. It resets on ascension, so the same
account would buy the same forge roll at two prices minutes apart. Rejected:
ascension count. It is monotonic but coarse, and a player who never ascends
still needs the sink to track their income.

## ADR-050 - The batch bar speaks copies, and a tick only exists where it melts

The reported bug was "the first item I select does not count". The rule behind it
was correct - `meltable` drops the equipped copy, every favorite and the last
copy in the vault - but the surface printed a number the player did not pick. A
ticked card and the bar disagreed by one whenever the group held a protected
copy, and a card with nothing meltable still had an invisible box over it that
answered a click by doing nothing.

Three changes, one rule: **a tick exists only where a copy will melt, and the
card prints how many it contributes.**

- `groupMeltable(group)` mirrors the server's three exclusions once, and every
  surface reads it: the checkbox, `SELECT DUPES`, the badge.
- The count badge prints `x3` when all three melt and `2/3` when one is protected.
  That badge is the only place the player learns why three became two, so it
  carries the fraction rather than a tooltip.
- A group with nothing meltable has no checkbox at all, and `SELECT DUPES` skips
  it. A tick that contributes nothing is the same bug one layer down.

The bar counts uids, not cards, and now says so: `12 TO MELT`, not
`12 SELECTED`. Ticking five `x3` cards and seeing `15` is the correct reading of
a card that represents three copies.

`MELT SELECTED` became `MELT MULTIPLE` and moved next to `EQUIP BEST` on the
house red (`redDeep` plate, `red` stroke). The bar dropped from 56 to 46 design
px: at 0.7194 that is 40 real px, still a comfortable key, and the grid gained
ten. `CLEAR` and `SELECT DUPES` are pinned to the right edge so the readout can
grow without the left pair moving.

## ADR-051 - A settings row is the switch

The sheet was reported dead twice. It was not: the hit target was a `108 x 38`
plaque at the right edge of a `402px` row, which reads as the current value of
the setting rather than as a control, and a player who taps the row's label gets
nothing.

The row is now the `TextButton`. Title and note are children of it, the `ON` /
`OFF` chip is a child of it, and the whole 402 x 54 surface flips the switch.
The chip keeps the colour change because colour alone is not a state for a
colour-blind player, but it is now decoration on a full-width target rather than
the target itself.

Hit test at the label end of the first row returns `Setting_sfx` as the top
interactive object. The server round trip was exercised: `setting { sfx = false }`
came back as `sfx = false` on the next payload and the reopened sheet printed
`OFF`.

## ADR-052 - The gear's teeth point outward, and that is a 90 degree fix

The header gear shipped as eight bars laid tangent to the rim. A frame's long
axis is `+Y`; rotating it by the radial angle alone leaves the long axis across
the rim, so every tooth overlapped the ring and the silhouette read as a
scatter of specks. The rotation is `angle + 90`, and the tooth is now `4 x 9` on
a `30px` canvas instead of `3 x 7` on a `26px` one, because a 2px outline on a
3px bar leaves one pixel of fill.

The backpack moved from a `24px` canvas to `28px`, and its handle stems were
re-parented from the button to the icon canvas so every plate shares one parent
and one scale. Both icons keep the 2px `#0F1117` outline and the no-upload rule:
a moderated asset cannot be iterated on in a playtest, and these have to move
with the panel.

## ADR-053 - The melt mode owns the card tray, and the batch key is a switch

`MELT MULTIPLE` is not a trigger. Pressing it arms a mode: the key becomes a
slate `CANCEL`, every card that owns a meltable copy grows its tick box, and a
click anywhere on the card tray toggles that copy. The heat of the key is the
instruction, and the tray being the hit target is the answer to "the box is
22px and my finger is not".

This supersedes the always-visible box in ADR-050. That pass made the box
permanent so the batch key would not need discovery; the key is now a full
`MELT MULTIPLE` plate in red at the left of the strip, so discovery is solved
where it should have been solved, and a tick box can go back to meaning "this
card is queued".

The destructive action is a **separate plate** at the far right of the bar,
`MELT n  +x`, and it only exists while something is ticked. One key cannot be
both a mode switch and the thing that deletes copies: the same press that arms
the batch would melt an old selection if the player forgot about it. Cancel is
the way out; the confirm is the way through.

Disarming clears the ticks, and so does closing the vault. A tick survives
nothing, because a tick the player cannot see is a copy they think they backed
out of.

## ADR-054 - The stage wash is composited, because a radial does not exist

`UIGradient` interpolates along one axis. There is no radial fill, and the old
answer - four nested rounded frames per pool at rising transparency - leaves a
hard step at every ring. On a 486px forge stage that reads as contour lines; on
a 221px card it reads as a target.

The wash is now six layers, all procedural and all one `Frame` each:

| layer | what it is |
| --- | --- |
| base | one opaque ramp, `deep(cool)` to `deep(warm)`, 68% toward the void |
| bloom | two crossed bands, transparent at both ends, 78% / 81% at the centre |
| diagonal | two accent bands at 42 and 138 degrees |
| shaft | one narrow accent band raked at 118 degrees |
| vignette | the void at the floor, fading up |
| settle | cards only: the plate colour, opaque at the bottom edge |

Where the bands cross, the colours add. Where they run out, the base shows. No
step, no asset, no upload, and the corners fall off without a second pass.

Two colour decisions matter more than the geometry. **The base carries the
rarity and the accent carries the variant.** A card passing tier green as `warm`
and variant orange as `cool` composites to olive at equal weight, which made
every card look the same; the card now passes the rarity twice and the variant
as `accent`. And **a card is not a small stage**: at 136px a narrowed band reads
as a stripe, so `tile` keeps the wide ramp, drops the diagonals and the shaft,
lifts the floor (`depth` 0.5 instead of 0.68) and keeps a wider vignette. The
card's wash stops at 136px and settles into the plate over 46px, so the name and
the stat row sit on a flat surface.

The forge and the fleet pass `Theme.tierBackdrop`; the vault passes the blade's
rarity and variant. `setColors` re-tints in place, so an equip or a card click
costs four `ColorSequence` writes, not a rebuild.

## ADR-055 - The orbit press comes from a control over the render

A `ViewportFrame` does not fire `InputBegan` for a mouse button on this build,
and `UserInputService.InputBegan` reports `processed = true` for any press that
lands on a `GuiButton`. That is two separate walls:

- the forge render is covered by the full-bleed `StrikeButton`, so every press
  on the anvil is processed before the global listener sees it;
- the vault inspector sits above a full-screen dimmer, which is a `TextButton`,
  so every press inside an open modal is processed by the scrim.

Neither can be fixed by ignoring `processed`: the forge's `VENT` key and the
vault's own keys would then start camera drags. So the controller takes
`Options.surface` - the control that receives the press - and connects to that
control's own `InputBegan`. The forge passes its `StrikeButton`; the inspector
gets a transparent `VaultStageGrab` above the render, which also stops the
dimmer from stealing the click. Motion and release stay global, so a drag that
leaves the surface keeps orbiting.

The fleet hero keeps the global path: nothing covers its render, so there is no
surface to name and no reason to add one.

## ADR-056 - A roll is priced in strikes, not only in banner tiers

`ForgeConfig.rollCost` was `tier.cost * 1.05^rolls * progressScale`. The
deduction was always happening; the number was simply invisible. Live, the test
profile sat at `sm = 608.9T` with a per-click yield of `16.1B` and a Cosmic roll
price of `288,687,958` - eighteen thousandths of one click. Three rolls in a row
moved the balance by less than the income that arrived while the crate was
falling, which reads as "rolling is free".

The banner price is now a floor, not the whole price:

```
cost = max(bannerPrice, clickYield * RollIncomeStrikes)   -- 18 strikes
```

`clickYield` is the un-critical per-strike yield, passed in by the server
(`ProgressionService.forgeRoll` and `buildPayload`). Early runs still pay the
banner price because their income is small; a late profile pays a fraction of a
second of its own output. The first live read after the change was
`290,105,676,000` for the same profile, which is exactly `18 x 16.1B`.

`Main.server` also pushes a payload on the same frame a roll succeeds. The tick
would land inside 200ms, but a counter that visibly does not move is the report,
and "it syncs eventually" is not an answer to a player watching the number. The
push is one `buildPayload`, not a new event shape.

## ADR-057 - Currency art is a separate manifest table, and the vector survives until preload

The three PNGs are not generated by `generate_icons.py` and are not uploaded by
`upload_assets.py`, so they get `AssetManifest.CurrencyArt` and their own
uploader (`scripts/upload_currency.py`). `currencyArt` resolves through the
thumbnail CDN for the same reason `uiArt` does: an Open Cloud `Image` upload does
not reliably rasterise through `rbxassetid://` inside an `ImageLabel`.

Two details are load-order, not taste:

- `ImageTransparency` starts at 1 and the drawn badge stays underneath. Only a
  confirmed `ContentProvider:PreloadAsync` fades the PNG in and the plate, stroke
  and glyph out. A moderated or missing asset leaves the vector badge, so the
  "zero grey boxes on join" rule holds even when the CDN does not answer.
- The thumbnail edge is **150**, not an arbitrary 160. The service answers
  `invalid thumbnail size` for squares outside its table; 150x150 and 420x420 are
  the square options, and 150 matches a 26-32px draw without shipping a 420px
  bitmap.

Live: all three labels reported `loaded=true` and `ImageTransparency=0`, and the
capture shows the shard, flask and core sitting on the navy pills with the plates
retired.

## ADR-058 - The roll is not gated by the forge lockout

The overheat lock is a strike lock: it exists because the anvil adds heat and the
gauge has to be able to punish a player who ignores it. A crate roll spends
Star-Matter and touches no heat, so gating it on `payload.locked` was a bug with
a misleading shape: a burned-out player had a dead roll button for five seconds
with no explanation printed on it.

Removed from both places: the roll affordance no longer ANDs affordability with
`not payload.locked`, and `ForgeView.roll` no longer returns early on
`live.locked`. The strike key and the gauge still say OVERHEATED / PURGE HEAT, so
the restriction is named where it applies. Live evidence: a roll was accepted
with `locked=true`, the gauge reading `OVERHEATED 3.0s`, and inventory moved
18 -> 19.

## ADR-059 - The BEST BLADE board carries a parallel copy record

An OrderedDataStore holds `userId -> integer`, so the model, variant, condition
and affixes behind a player's best-blade number need a second store. On each
submit, the strongest copy by `ForgeConfig.powerCopy` is written to
`QF_BestBlade_v1` as `{ id, variant, grade, element, prefix, suffix, mult,
display }`.

Read cost is bounded: the board is a top-20 page, details are read once per row
and cached for 60s (a missing record is cached for 15s so a first submit is not
hidden for a minute), and the panel only requests while it is open. Your own row
skips the store entirely and uses the live `myDetail`, which is why the first
look at the board already shows a model.

The row paints the model with `BladePreview.thumbnail` and takes its multiplier
from the detail record, not from `entry.text`. The ordered value can lag by one
submit interval; a row whose number and model disagree is worse than a row that
is one refresh behind.

## ADR-060 - Quality tiers are derived from the copy, never stored as a second multiplier

The QUALITY codex adds twenty-four bands (`Chipped-` through `Transcendent++`)
without adding a power axis. The band is `grade + step`, where step is the
within-family score of element x prefix x suffix against four thresholds
(1.00 / 1.20 / 1.45 / 1.72); the multiplier printed on the cell is the copy's
true product from `ModifierConfig.power`.

A stored quality multiplier would double-count every grade already in the save
and inflate the economy by the size of the ladder. The discovery key is
`quality:<id>` and is marked at forge time with the other axes, so the tab fills
from real rolls. The codex total moved from 68 to 117 keys: 50 blades (25
hand-authored + 25 generated), 5 variants, 8 elements, 6 grades, 24 affixes, 24
quality bands.

## ADR-066 - The strike stays two layers; layers go where there is no identity yet

The video-07 note argues that a single clip per action reads as a UI blip, and
that the shape is transient, body, tail. Applied to the strike, that meant
`hit.wav` as the hammer face, `impact_explosion_03` at 2.1x as the anvil's mass,
and `metal.ogg` as the ring, with the band climbing a semitone ladder.

It shipped, it was played, and it was worse on the first listen. `hit.wav` is a
body blow, not a hammer face: the click lost its metal edge and gained a wooden
thump underneath it. `impact_explosion_03` has a sustained tail, and at eight
clicks a second that tail does not read as weight, it smears the transient that
makes the strike feel like a strike.

So the strike is exactly what it was: `electronicpingshort` at 1.0 and
`impact_explosion_03` at 2.55x, plus the two band pings climbing by
`1 + 0.045 * streak`. `Sfx.roll` went back to two layers (a third knock in the
wind-up made it sound like the crate had already landed), `Sfx.forge` went back
to five (the added `hit` and `metal` pushed the low thud forward until the
reveal read as a door closing), and `Sfx.streakComplete` kept the five layers it
shipped with.

What survived is everything that had no identity to lose:

- `Sfx.crit()` fires from the server's `crit` event. The crit already had a white
  flash, a `CRIT +N` floater and a shockwave, and it was silent.
- `Sfx.crateLand()` replaces the `rollTick(1)` the crate used to land on. Phase
  one of the roll is the heaviest object in the game and it was a ping.
- `Sfx.crateShatter()` gives phase three its own crack instead of borrowing the
  fanfare.
- `rollTick` climbs a major pentatonic ladder in semitones
  (`0 2 4 7 9 12 14 16 19 21 24`) instead of a ratio, so a roll winds up in one
  key. The old `1.045 ^ n` drift never landed on a note.
- The vent gained an air layer under its water hiss, the UI tick gained a click
  under its ping, and the tab switch gained a third note.

The rule this pass leaves behind: **layering is for events that have no
established identity.** A crate landing, a crit, a shatter, a vent - nobody has
heard those before, so a stack of three is free. The strike has been heard a
million times, so adding to it is a remix, and a remix has to be judged by ear
before it ships. This environment cannot hear, which settles it.

Asset provenance is unchanged and still checked: five client-shipped ids were
confirmed with `ContentProvider:PreloadAsync` in Edit mode before they entered
the file. `sounds/swoosh.wav` and `sounds/bell.wav` both report
`Enum.AssetFetchStatus.Failure` and are not in it. The pool stays at 24 slots:
four layers times eight clicks a second is 32 requests, and a reused slot
truncates the previous hit audibly.

## ADR-067 - The vault drawer is two columns, and REROLL is a button

**The drawer clipped three facts.** Ten rows at 20px need 200px of column; the
well is 132px tall, which is six rows and a sliver. COOLING, MASTERY and SOCKETS
were printed by the code and never visible - the rune lock, the rune count and
the cooling multiplier were all below the clip line on every copy.

The well is now two columns, split by meaning rather than by count:

| Column | Width | Facts |
| --- | --- | --- |
| identity | 176 | MULTIPLIER, GRADE, ELEMENT, PREFIX, SUFFIX |
| performance | 136 | VARIANT, CRIT, COOL, MASTERY, SOCKETS |

The widths come from measurements at the 13px rung, not from a grid: the left
column has to hold "of the Colossus" (98px) and the right only ever prints
numbers. Five rows of 20px is 100 in 120 of content, so both columns end well
above the floor. A conditionally empty PREFIX leaves a hole in the left column
instead of shuffling the right one.

Two things had to change to make it work. `statRow` gained a label fraction,
because a 58/42 split is right for a 336px row and wrong for a 136px one. And
the well lost its `UIListLayout`: with one, both columns were laid out at the
same x and the drawer was a pile of overlapping text. The first capture of this
pass shows exactly that, which is why the layout is gone.

**REROLL had no button.** `ProgressionService.rerollVariant` has existed since
the Salvage rack shipped, the handbook quotes its price (`12 + 10 * (tier - 1)`
Scrap), and nothing in the client ever called it. The sink for duplicate blades
was a server function nobody could reach. It now sits in the drawer beside MELT,
targets the copy on the turntable (the one the player is looking at), greys out
when Scrap is short, and confirms with the price and the fact that the roll can
come back worse. Melting still skips the equipped and favorited copies, because
melting the blade in hand is a mistake while rerolling your main is the point.

Verified live on the test profile: five rerolls spent 160 Scrap, `standard`
became `overclocked`, the card badge and tint repainted, the multiplier moved
45.11K -> 72.18K, the melt quote moved +30 -> +67, and the drawer reprinted
CRIT +0% -> +5%, VARIANT x1.00 -> x1.60.

`Handle.dragTravel` is exposed for the same reason the surface exists: a caller
that shares its press with an action needs to tell a tap from a drag. The forge
does not gate on it today - the strike fires on press, on purpose - but the
number is there for the day a tap-to-strike variant is worth trying.

## ADR-061 - A trade request is an invite, not a session

The first build opened a desk the moment one player pressed ASK. That is a
notification dressed as consent: the target got a panel they never agreed to,
and the 240 second session clock started running against someone who had not
looked at the screen.

`TradeService.request` now records an invite and nothing else:

```lua
invites[targetUserId] = os.clock() + INVITE_SECONDS   -- 20
inviting[player.UserId] = targetUserId
```

`respond(player, fromUserId, accept)` is the only path that creates a session,
and it emits `tradeStarted` to both clients on accept. A decline, an expiry or a
second request from the same forger all clear the invite through
`dropInvitesFor`, so a target cannot be holding two live invites from one
player.

The invite is 20 seconds for a reason: it has to be short enough that a stale
card is never on screen when the sender has walked away, and long enough that a
player reading a shop panel will still catch it. The client renders a countdown
from a local deadline and the server owns the real one, so a client that stops
ticking loses nothing.

## ADR-062 - The desk syncs one draft, and privacy rides the roster

`TradeView` keeps a single local draft (`offerUids`, `offerOrder`,
`offerShards`) and pushes it on every toggle through `tradeOffer`. The server
clamps against the real inventory, clears both accept flags and sets the trade
locks. There is no local "pending" state to reconcile: the next payload is the
truth, including the case where the copy was melted on another server between
two toggles.

Repaint work is gated by three signatures rather than by equality of the whole
state:

| Change | Rebuilds |
| --- | --- |
| `sessionKey` (partner, phase) | the whole desk |
| `theirSignatureOf(state)` | the partner's offer strip only |
| `inventorySignature()` | the picker grid only |

Without those gates the 0.35s poll rebuilt two banks of spinning
`ViewportFrame`s four times a second, which is the difference between a live
desk and a slideshow on a phone.

The privacy toggle is read in two places on purpose. The server refuses the
request in `TradeService.request` when `settings.trades` is false, and
`playersFor` also returns the flag so the rail can paint `OFF` before the player
spends a round trip on an ASK that will be turned away. One is the gate, the
other is the honest label; both read the same field.

## ADR-063 - LihFolk ships as a sky and one tiled band, behind its own manifest

The vault is a large pack with meshes, materials, animations and VFX. Almost all
of it would have to be re-authored to match the game's 3px outline and flat
plates, and a licensed third-party material imported into the economy would make
every future art pass argue with it.

The integration is therefore narrow on purpose:

- `LihFolkArt.band` is one hammered gold albedo, tiled at 180px behind the
  handbook hero band at 50% transparency. It sits under a scrim, so it is
  texture, not illustration.
- `LihFolkSky` holds the six night faces. `AssetManifest.hasSkybox()` is true
  only when all six resolve, and `LobbyService.applySky` either applies the
  whole pack or destroys any stale sky and leaves the procedural night lighting
  alone. Half a skybox is a visible seam.

The seven ids live in their own tables with `LIHFOLK_EDGE = 420`, so
`upload_assets.py` and `upload_currency.py` cannot overwrite an id they did not
create.

The sky is uploaded and mapped but switched off: `Config.UseLihFolkSky = false`.
With Image ids every face preloads `Success` and the renderer draws a black dome;
with Decal ids the engine logs `Asset type does not match requested type` and
falls back. Neither route puts pixels on the dome at the current size, and a
black sky is worse than the procedural one it would replace. The switch is a
one-line flip the day a face renders.

## ADR-064 - The handbook replaces the spotlight tutorial

The old onboarding was a chain of spotlight cards that dimmed the UI and pointed
at one control at a time. It taught the first minute and nothing after it: a
player who came back a week later had no way to ask what a quality band was.

`HandbookView` is ten pages (loop, heat, crate, variants, quality, vault, fleet,
runes, ascend, trade), each with a lead, three steps, four facts, a live art
panel and a tip. Navigation is a rail on the left, so any page is one click from
any other. The welcome card is now a single sheet whose CTA opens the handbook at
the loop page, and the GUIDE key in the top bar opens the same book.

Two rules keep it from becoming a wiki of stale numbers:

- Every figure is read at paint time from the config the game runs on, through a
  `pages()` closure rather than a module-level table. Half the numbers are the
  player's own (copies, scrap, heat, cores), so the book has to be rebuilt on
  open.
- The art panel uses the live seam where one exists: the blade page mounts
  `BladePreview`, the vault page melts the equipped copy through the same
  `ForgeConfig.salvageCopy` the melt button calls. An invented "+N" next to a
  page that promises real numbers is the one thing the book cannot do.

## ADR-065 - Thumbnails face the camera, and they light themselves

Every static thumbnail in the game was a hairline. `BladePreview.thumbnail`
baked `HERO_YAW` (25 degrees) into the model, but the blade mesh is built with
its flat facing local +X, and the thumbnail camera sits 26 degrees off -Z. At 25
degrees of yaw the flat is still almost edge-on, so a 69px card drew the
specular edge of a sword and nothing else.

The fix is geometry, not contrast:

```lua
local THUMB_YAW = math.pi * 0.5 - AZIMUTH - math.rad(18)
```

Putting the flat normal on the camera direction is `90 - AZIMUTH`; the extra 18
degrees is the same three-quarter turn the hero pose uses, so the copy keeps a
lit side and a shadowed side. Facing the camera then exposed the second problem,
which was that dark steel on a `void` plate at 28px is invisible no matter which
way it points: `Ambient` now runs at full white with a fixed key direction, which
keeps the bevel and the variant glow readable at card size.

The change is in one function, so the vault grid, the codex, the boards, the
handbook and both trade strips all improved together.

---

Honest list of things that are not done, so they are not mistaken for oversights:

| Gap | Impact | Notes |
| --- | --- | --- |
| Monetization IDs are all `0` | Store rows read `SOON`; nothing can be bought | By design. Storefront shows `SOON` instead of a price, the click answers with a toast, and the server refuses to prompt. Creating the items is a Creator Dashboard step — Open Cloud cannot create passes or products. |
| No `stylua` formatting pass | Style is hand-consistent | `stylua` is not installed in this environment; code follows a single style by hand. |
| No automated tests | Regressions are caught by playtest | The economy is pure functions; `TechTreeConfig.compute` and `NumberUtil` are the obvious first unit-test targets under Lune. |
| Leaderboards absent | No cross-server competition | Nothing in the loop requires them; `lifetimeStarMatter` is already tracked and ready to sync. |
| Studio plugin bridge unverified | Playtest is scripted or manual | The official `StudioMCP` bridge (`%LOCALAPPDATA%\Roblox\mcp.bat`) is wired into opencode as `studiomcp` and drives `execute_luau`, `start_stop_play` and `get_console_output` against the live place. Its `screen_capture` returns null on this build, so every visual claim in this repo is backed by geometry measurement (bounds, NDC, AbsoluteRect) rather than a screenshot. The older npx `robloxstudio-mcp` plugin route still times out and is not needed. |
| VFX sprite sheets unuploaded | Effects use the procedural fallback | 22 sheets are generated and margin-checked in `assets/generated/vfx/`. The blade meshes are uploaded (26/26, moderation approved) and wired into the viewport and the fleet stage; only the sheets remain. |
| No auto-generated LODs | Full mesh always drawn | 586–1 064 triangles per blade at the current ring count. Nothing to decimate at thumbnail size; revisit if the loft gains detail. |
| No mobile-specific input tuning | Touch works via `Activated` | The strike button is large enough; no gesture layer exists. |
| Blade meshes unauthorized in the current Studio session | Playtest renders the procedural fallback for all 26 blades | Console reads `User is not authorized to access Asset` for every mesh id; `0/26 blade models loaded`. The assets loaded in an earlier session, so this is an account/asset permission issue, not a pipeline change. |
| No live exercise of the Overdrive text or an expedition payout | Both paths are code-verified only | Overdrive needs ten in-band strikes, which simulated input cannot time, and the payout needs a five minute wait. The rail renders live (`STREAK 0/10`), and the payload fields and settle path were read. |
| Funnel events have no dashboard yet | Events are logged, not read | `Funnel.log` sends to AnalyticsService. Reading them back is the Creator Dashboard's job. |
| Runes lesson variants are code-verified only | Reaching them needs shards or rank 1 | The three scripts are pure functions of payload state; a live pass would need a profile with 3+ shards or 100 strikes on one blade. The default branch (no shards, no socket) is the one every new player sees first. |
| Gamepass badge renders at 51.8 real px, not 72 | The luminance floor is still the binding constraint | Measured: 72 design px in a 104px row, on a canvas at 0.719 scale. The first art composition read as a black circle at 34.5px (p50 = 28, 7% above 120); the shipped gold field measures p50 = 112 with 43% of pixels above 120, and holds at the new size. The list badges inherit the same rule: bright field, ink subject. |
| Salvage cache and sigil art not generated | The rack and codex are typographic | By design: the rack ships with rarity colour, a state word and a reward hint, so the loop is playable with zero uploads. `user-manual/16-salvage-art-prompts.txt` holds the eight optional images (4 caches, 4 set emblems). |
| A timed crack (45s and above) not exercised live | Only the 0s Scrap path was clicked end to end | The clock is `os.time()` and the payload field was read as `secondsLeft`; a 45s wait was not spent in the playtest. The arithmetic is in `crackCache` and `buildPayload`. |
| Codex set completion not exercised live | The multiplier path is code-verified | Needs three specific sigils. `SalvageConfig.bonus` is a pure function of the owned map and was reviewed against `RuneConfig.sum`; the four stat multipliers are wired into click, crit, vent and heat decay. |
| Gamepass badge art resolves through the thumbnail CDN, not `rbxassetid://` | One hop of indirection, and `type=Asset` thumbnails are the only route proven to load here | `AssetService:CreateEditableImageAsync` returns `HttpError` for the badge Image, the badge Decal and an earlier badge Image alike, while `rbxthumb://type=Asset&id=<id>&w=420&h=420` returns a real 420x420 RGBA bitmap. Verified live: `ImageLabel.IsLoaded = true` for the store badge. If a future upload loads on the raw route, swapping `gamepassIcon` back is a two-line change. |

| Vault buttons are driven through the `QF_Dev` seam, not by pointer input | The handlers, the confirm dialog and the server round-trip are exercised; the `Activated` wiring itself is not | Studio's `VirtualInputManager` needs the `RobloxScript` capability, which the MCP sandbox does not have. `InventoryModal.open` / `selectDupes` / `meltSelected` / `commitMelt` / `meltDetail` / `commitDetailMelt` / `equipBest` are the same functions the buttons call, and the seam invokes them inside `Main.client`'s VM. |
| No screenshot of the widened layout or the crate | Every visual claim here is a measurement | `screen_capture` returns null on this Studio build. The canvas, both panels, the roll plate, the vault key, the gear key and all four tabs were measured through `AbsolutePosition` / `AbsoluteSize` and divided by the 0.7194 canvas scale. |
| The vault has not been opened on a phone | Card width on a small screen is arithmetic, not a measurement | The panel is 86% x 84% of the canvas, which is device-independent by design, and the grid is a `UIGridLayout` with fixed 193px cards. A 720p phone in landscape lands the same design space as desktop; a portrait phone letterboxes 1360x720 down and the panel shrinks with it. Not tested on hardware. |
| Drawer EQUIP and REROLL were not clicked through the drawer | Both server actions were exercised directly (`equip`, `reroll`) and the drawer repaints from the payload | The drawer buttons send the same verbs with `group.repUid`; the wiring is two `StateStore.send` calls. EQUIP BEST was exercised end to end through the seam and produced the `Equipped ...` toast. |
| The crate sequence is verified by sampling, not by eye | Rotation, seam transparency and visibility were sampled at 0.1s intervals across a real forge | Readings: visible at 0.1s dropping from y 0.59 to 0.50, rotation 14 -> 294, seam 0.60 -> 0.00, hidden by 1.4s, inventory +1. Whether it *feels* good is a human judgement this environment cannot make. |
| Early pool is five blades, all Standard-heavy | The roll reveal usually shows a Rusted Cleaver | Measured over eight rolls: five copies of `rusted_cleaver standard`, one `rivet_edge`, one `coil_shard`. Variant weight puts Standard at 74 of 100, so the fanfare reads the same most of the time. That is a tuning question for `ForgeConfig`, not a bug in the stage. |
| Drone rungs 2-5 are procedural, not meshed | Rung 1 reads as a hull with a lit core; rungs 2-5 read as primitives at 220px | Only `fleet_drone` was uploaded. Each higher rung is built from the same core plus rung-specific hardware (exhaust bells, photon cubes, satellites, outrigger pods) on a 1.0-1.18 scale staircase, so the silhouettes separate by outline rather than by detail. Adding meshes is four uploads and four moderation waits. |
| Only the scrap rung was bought live | The other four price paths are code-verified and rendered locked | A playtest earned 8 Aether, bought one Scrap Drone (`aether 8 -> 3`, `drones 0 -> 1`), and the quantum key read `LOCKED AT 45` on both buy faces. Reaching Molten in a session needs 150 Aether, which is 1 875 heat worth of venting. |
| The ladder has no ceiling, and the ascension gate has not been re-tuned for it | A player deep in the Cosmic rung can cross 1e9 run Star-Matter in seconds | 300 Cosmic Dreadnoughts pay 720M/s before blade and tech multipliers. That is the ladder working as designed, but it makes `AscendThreshold` (1e9) a formality at the top of the fleet. Raising the gate or scaling it by ascension count is a balance pass, not a bug in the registry. |
| Aether income does not scale, so the top two rungs are content nobody can reach | Molten and Quantum are playable; Celestial (120 owned) and Cosmic (300 owned) are not | A vent pays 6.8 AE at 0.08/heat, and nothing multiplies it with fleet size or ascension count. Cheapest route to the gates, all-scrap: 15 = 252 AE (37 vents), 45 = 24 807 AE (3 648 vents), 120 = 1.7e9 AE, 300 = 6.8e17 AE. The ladder's shape is settled; the supply curve is the missing half. Options are written out in `game-design-math.md` section 5.5. |
| The backpack and gear keys are 40x34 and 36x34 primitives | They read clean at 0.7194 scale, not at 2x | Nine and eleven frames respectively, each with a 2px `#0F1117` outline drawn in a `UiKit` frame. No `UIScale` per icon; they grow with the panel. |
| No screenshot of the full-bleed stage or the ladder | Every framing claim is a projection measurement | `screen_capture` returns null on this Studio build. The strike layer, the scrim, the gauge, all five rung silhouettes and the buy dock were measured through `AbsolutePosition` / `AbsoluteSize` and `Camera:PointToObjectSpace`.
| Vault thumbnails render the procedural fallback, not the uploaded meshes | Cards show a 3-4 part silhouette instead of the sculpted blade | All 26 mesh ids still return `User is not authorized to access Asset` in this session, so `BladeModelBuilder.hasMesh` is false and every `ViewportFrame` builds the primitive chain. The framing maths does not change when the meshes authorize; only the silhouette does. |
| The inspector is 28% of the panel, not the ~32% the ticket named | The pane is 380px in a 1354px panel | Four 221px columns plus three 14px gaps is 926px, and 926 + 12 + 380 + 36 = 1354 exactly. A 32% pane (433px) would drop the grid to three columns at this canvas width, and four columns is the requirement that cannot move. |
| The inspector turntable is one live mount, remounted only on group change | Opening fifty cards does not build fifty models | `paintInspector` compares `inspectorMountedKey` to the group key before calling `BladePreview.mount`, so the 10Hz repaint cannot restart the spin. Verified by mounting a card, waiting through several payloads, and reading the same `BladeId` attribute on the stage. |
| Favourites are verified through the remote, not through the star button | The guard and the payload are proven; the tap target is not | `Action("favorite", { uid })` flipped the set on and off in the sync payload, `vaultFilter("favorites")` narrowed the grid to 0 cards for an unfavorited set, and a `salvage` on a favored uid left `invCount` at 17. The card star and the dock key call `InventoryModal.toggleFavorite`, the same function the seam drives. |
| The roll ramp is verified over two rolls, not fifty-one | The curve is a formula with a clamp, exercised at its base | `forgeCost` read 4 000 000, then 4 200 000 after one roll, then 4 410 000 after the second, with `forgeRolls` at 1 and 2. The 12x ceiling and the banner reset are code paths read against `ForgeConfig.rollCost` and `forgeRollTier`, not walked live. |
| The first-join card is verified across two joins in one Studio session | The latch is proven, the cold-start is not | Join one showed the 480x300 card over a visible scrim with no strip; `skipGuide` wrote `guideSeen = true` and `tutorialCompleted = true`; join two showed `cardVisible = false`, `scrim = false`, `strip = false`. Studio's mock profile persists between playtests, so the reset went through the Studio-only `guideReset` action rather than a fresh profile. |
| The progress multiplier is pinned at its cap in the test profile | The curve below the cap is arithmetic, not a measurement | `forgeCost` read `2.205e12` = `2e8 * 1.1025 * 1e4` at `rolls = 2`, which proves the multiplier is applied and clamped. A profile between `1e9` and `1e17` lifetime was not walked, so the intermediate `sqrt` values are read off `Config.progressScale`, not off the HUD. |
| The Aether ladder stalls above roughly 45 owned drones at high lifetime | Drone growth is the brake on the Star-Matter printer, and this is the brake biting | A vent still pays `0.08` per heat while `dronePriceScale` reaches `100x` at the cap. The cheapest Cosmic now costs `1.2e9` Aether against a `61.6 a/s` fleet. The exponent is the knob; this pass chose the brake on purpose. |
| The Scrap reroll and the tech tree do not take the progress multiplier | Two sinks stay on their own curves | Reroll is priced by forge tier (`12 + 10 * (tier - 1)`) and Scrap income is priced by the same tier, so a second multiplier would double-charge. The tech tree is a finite meta ladder paid in Quantum Cores, which are already gated by ascension. |
| `screen_capture` returns null but still renders a capture | Visual claims no longer have to be measurements alone | On this Studio build the tool's return value is `null` while the capture arrives in the client. Six captures were read by eye this pass (vault bar, selected ticks, `2/3` badge, settings rows, header icons) and cross-checked against `AbsolutePosition` / `AbsoluteSize`; earlier honesty rows that say "no screenshot" were written before the capture path was used. |
| The gear and backpack are still primitives, not art | They read as a cog and a bag at 21px, not as illustration | Gear: six 4 x 9 teeth on a 19px ring with a 7px bore. Backpack: 18 x 15 body plus flap, pocket, handle and straps. Every plate carries the same 2px outline; there is no per-icon `UIScale`. |
| The settings rows were never dead, only small | The sheet opened and the switches flipped on the old build | The failing half was the hit target: a `108 x 38` plaque inside a `402px` row. The row is now the `TextButton` and a hit test 40px into the label end returns `Setting_sfx`. A pointer was not synthesised; `VirtualInputManager` is capability-locked, so the claim rests on hit testing plus the server round trip. |
| The batch melt counts uids, not cards | A player who ticks five `x3` cards sees `MELT 15` | That is the intended reading and the card badge says so, but it is a semantics choice, not a law: per-copy ticks would show fifteen checkboxes and a different grid. The `n/m` badge is the compromise that keeps 4-column cards while making the number honest. |
| Pointer input is synthesised now, but only for the mouse | The click paths in this pass are measured, not inferred | Studio MCP exposes `user_mouse_input` (`moveTo`, `mouseButtonDown` / `Up`, `mouseButtonClick`). It drove a real card click, a real selection click and three real drags. `VirtualInputManager` is still capability-locked and was not used. Touch, gamepad and keyboard were not exercised. |
| The forge strike fires on the press that starts an orbit drag | Orbiting the anvil costs one strike | Six clicks on the anvil drove core heat to 4% and the strike cadence to `HOT 3.0/s`, so the core loop still works with the orbit attached. Firing on release instead would put a full click of latency on every strike; that trade was refused. |
| The batch confirm dialog was opened, not accepted, this pass | The plate, the payload and the dialog are proven; the accept click is pre-existing | `meltSelected` returned true and built the dialog. The accept path (`commitMelt` -> `salvageMany`) was exercised end to end in the forge-10 pass and is unchanged. |
| `SELECT DUPES` selected nothing in the test profile | The enabled path is code-verified; the disabled path was seen live | The mock profile holds 22 groups of one copy each, so `count > 1` never matched and the key stayed `locked`. `toggleSelect` and the confirm were exercised through a card click instead. |
| The card wash values are tuned by eye, not measured | Contrast and saturation are judgement calls | `depth 0.5`, bloom `0.74/0.76`, vignette `0.18/0.78` on tiles; `depth 0.68`, `0.78/0.81`, `0.04/0.68` on stages. Four captures were compared before settling. No luminance measurement was taken, unlike the badge pass. |
| `dragTravel` is exposed but not consumed | The field exists for a tap/drag gate that was not shipped | The forge strikes on press, so there is nothing to gate. The field is read by the Studio seam and reserved for a future tap-to-strike variant. |
| The LihFolk sky is uploaded, mapped and switched off | The lobby runs the procedural night, not the pack sky | `Config.UseLihFolkSky = false`. With Image ids all six faces preload `Success` and the renderer draws a black dome; with Decal ids the engine logs `Asset type does not match requested type` for every face and falls back. `LobbyService.applySky` is written and reachable, so the switch is the only edit between here and a working sky. |
| The trade handshake was proven through the preview seam, not between two clients | Every state renders and the server path is unchanged, but two live players were not on the desk at once | `tradePreview` drives the desk with the mock partner and the full payload; `tradeInvitePreview` drives the invite card at 20s. The countdown was watched to expiry and the card closed itself, which is the client half of the invite timer. The accept-to-session step and the `trades = false` refusal are read in `TradeService` and were not walked with a second session attached. |
| Thumbnail ambient was raised by eye | Legibility is a judgement, not a measurement | Full white ambient plus a fixed key direction was compared against 180/255 grey on the vault grid at 69px and the trade picker at 28px. Both were captured. No luminance floor was computed the way the gamepass badge was. |
| The handbook facts are live, so two captures of the same page can differ | A screenshot is a snapshot of a profile | The eight-digit numbers move with the profile. Anything quoted in this log is the value at capture time, not a constant. |
| The strike mix was judged by ear, and the first attempt failed | A three-layer strike shipped, was heard once, and was reverted the same session | No test in this environment can hear a mix. The rule recorded in ADR-066 is that layers go on events with no established identity (crit, crate land, shatter, vent); a sound the player already knows only changes on a listen, not on a rationale. |
| REROLL's confirm dialog was not clicked | The guard, the spend and the repaint are proven; the dialog button is not | Studio's MCP sandbox cannot synthesise a pointer press, so the seam calls commitDetailReroll directly, the way commitDetail skips the melt dialog. The confirm body and the affordability grey-out were read and captured. |
| The two-column drawer was measured at one canvas scale | 0.7194 only, on a 1520x720 viewport | Columns are fixed px and rows are fixed 20px inside a 336px content box, so the relationship is scale-invariant by construction. A portrait phone letterboxes and the panel shrinks with the canvas; that has still not been looked at on hardware. |
| The new strike-adjacent sounds have not been reviewed | crateLand, crateShatter, crit and the ollTick ladder all shipped unheard | They fire on events that had no sound at all, which is the safer half of ADR-066, but 'no sound' to 'some sound' is still an ear judgement. A roll and a crit are the two things to listen for next session. |

## ADR-068 - The screen is the app: elastic canvas, nav strip, two-column sections

The UI was a 1440x720 letterboxed canvas on a near-black backdrop: a forge card
on the left, a 520px tab column on the right, and black showing through every
gap. On a 2:1 window the canvas fit exactly, so nothing was technically
letterboxed, and the screen still read as a web page floating in a void — the
backdrop was `void` (9, 8, 10) and it was doing most of the visual work.

Four changes, each answering a specific failure:

**The canvas is full-bleed and its width is elastic.** Height stays 720 design
px; the width is `viewportWidth / (viewportHeight / 720)`, so the canvas covers
the window edge to edge at boot and a wider window gets more layout instead of
bars. `UiKit.screen` reads its measurement from the *ScreenGui* rather than
`camera.ViewportSize - GuiService:GetGuiInset()`, because the inset reports zero
while the native topbar is momentarily hidden and the first measurement lands in
exactly that window; that bug produced a 576-tall canvas centred in a 518-tall
region, with the top 24px of the bar off screen. A resize re-primes `Layout` and
repositions the roots (`HudController.layout`, `Sections.layout`,
`ForgeView.layout`); nothing is rebuilt, because every card below the roots is
already elastic in X and a rebuild would restart the blade viewport, the embers
and the crate.

**The top bar hugs the native chrome.** `TOPBAR_Y = 6` under the inset, 76 tall,
with the identity plate pinned left, the currency pills beside it and ASCEND /
DAILY / GUIDE pinned right. The brand banner was replaced by the identity plate:
the player's face, display name, `@handle`, a rank chip (ascensions + 1) and a
progress bar to the next ascension — the same `Config.AscendThreshold` the
ASCEND button reads, so the two can never disagree. The thumbnail is
`GetUserThumbnailAsync` (an `rbxthumb://` id, no upload, no moderation) behind a
`pcall`, with the initial as the permanent fallback.

**One nav strip carries everything.** Five section tabs, the live rate band, the
three overlay keys (codex, boards, feedback) and the vault and settings keys, in
one 46px row. The tab row and the rate band split the leftover width: tabs take
the most that still leaves the band 240, capped at 168 each, and the band takes
the rest. Measured: at 1200 the tabs are 130 and the band 242; at 1685 they are
168 and 537. The rate readout moved here from its own full-width row.

**Sections are two columns.** A single column at 1665 design px stretches: two
500px buttons in one row, five 330px ladder rungs. The reference runs two columns
of cards for exactly that reason. Rows are built by the existing views into a
zero-size sink and sorted one frame later: a plain `TextLabel` is a section
header in every view, so a header and its cards are one block; a block longer
than 1.6 screens (the tech tree) is cut into equal chunks at row boundaries; and
blocks are dealt to whichever column is shorter. Store now reads GAME PASSES
left / BOOSTS & UTILITY right with every header above its own cards; runes reads
blade left / shelf right; tech splits 3/4 nodes.

What was refused: a fixed grid with per-view cell definitions (every view would
have needed a rewrite for one asset), and rebuilding the UI on resize (a visible
stutter for a window change the player makes once).

### Honesty

| Thing | State | Note |
| --- | --- | --- |
| The resize path was exercised by the Studio play window growing, not by a user drag | The grow fires `ViewportSize` and re-primes `Layout`; the reflow functions are the same ones the drag would call | Measured before and after: at boot the canvas was clamped to 1200 design px in an 863x518 region, after the grow it was 1685x720 filling 1212x517. A drag on a second monitor was not performed. |
| The two-column split is tuned by eye at one width | 1685x720 design, 1212x517 physical, UIScale 0.7194 | The grouping rules are structural, but whether tech reads better as 3/4 or 4/3 is a judgement made from one capture. |
| Scroll restoration was not re-walked after the two columns | `savedScroll` still stores the scroll's `CanvasPosition.Y` | The canvas is now measured from the taller column instead of `AutomaticCanvasSize`, because the automatic path refused to measure automatic children and produced a 0-height canvas over 400px of rows. Returning to a scrolled section was read in code, not photographed. |
| The identity plate has no click target | It is a readout, like the reference's profile block | No profile sheet exists to open. |
| `GetUserThumbnailAsync` was never seen failing | The pcall path is unexercised | The initial letter is painted underneath from the first frame, so a failed fetch is a correct-looking fallback rather than a grey box. |

## ADR-069 - The economy is thinned at the source, not at the price

The drone side of the curve was climbing faster than the click side, so a fleet
bought in the first ten minutes paid for the rest of the run. The fix is in the
registry, not in a multiplier: `DroneRegistry` yields were cut by roughly 45%,
per-tier growth rose by 0.035 so the ladder still rewards climbing, and the tier
gates moved to 32 / 110 / 320 / 800 lifetime Aether. `TechTreeConfig.drone_lattice`
was added beside the existing lattice nodes at +12% per level, eight levels, cost
3 growth 1.85, so the fleet has its own long sink instead of riding the global
one.

The rarity column was the other half. `ForgeConfig.RarityWeights` had a top band
wide enough that a Void or better dropped often enough to flatten the chase. It
now reads Scrap 55 / Forged 29 / Astral 13 / Void 2.4 / Quantum 0.35. Every crate
carries its own column built from the same shape, so the thinning lands on all
five pools rather than on the starter one.

What was refused: cutting the drone cost instead (it moves the wall, it does not
remove it), and a global income multiplier (it would have hidden the same
imbalance in the click path).

## ADR-070 - Five crates are five weight tables, priced against their own rung

There used to be one pool whose odds improved as the lifetime banner advanced.
That made the banner a price list and the roll a single decision: wait, then buy
the same thing. `ForgeConfig.Tiers` is now five records, each with an `id`, a
`short`, a `blurb`, its own `weights` column, an `accent`, a model `shape` and a
`pity` goal. The ladder is Standard 50 / Void 1,400 / Quantum 90,000 / Celestial
6M / Singularity 400M, unlocked at 0 / 60K / 8M / 600M / 400B lifetime
Star-Matter.

Three consequences were deliberate:

- **The ramp is per crate.** `forgeRolls` belongs to the crate named by the
  profile's `forgeCrate`. Switching crates starts a fresh ramp, because a pricier
  crate already pays more per roll and carrying the ramp across would charge the
  same step twice.
- **The pity goal is the crate's.** `forgePityGoal` reads the crate being rolled.
  Printing the lifetime banner's goal over a crate's counter produced `15 / 8`.
- **The income floor scales with the rung.** A flat `18 strikes` floor made every
  pool quote the same number the moment income passed the top banner price -
  live, Standard and Singularity both read 673.40B, so the cheap pools were pure
  upside. `ForgeConfig.floorStrikes` multiplies the floor by the crate's tier:
  18 / 36 / 54 / 72 / 90.

Pity is still "Void or better", drawn from the crate's own column, so a pool that
does not stock Quantum cannot be forced into it.

## ADR-071 - The ten-pull is one transaction and one event

`forgeRoll(player, crateId, count)` prices the batch with `bulkRollCost`, which
sums the geometric ramp the price actually is, charges once, clamps `count` to the
free inventory slots, and reports **one** `forged` event carrying the best copy of
the batch plus `batch` and `crate` fields. Ten separate events would have queued
ten crate animations and ten reveal plates behind each other.

The reveal reads `10 COPIES - BEST OF THE PULL` and the blade under it, so the
result is honest about what the batch was without pretending the other nine copies
do not exist. The batch price is not `10 * cost`: at the floor it is, because every
term of the sum is the floor; above the floor the ramp makes the batch cost what
ten presses would have.

## ADR-072 - The crate page is a section, and the crate is profile state

The first build of the multi-crate browser was a modal over the forge. It was
wrong for the same reason the handbook was wrong as a spotlight: the page is a
place you return to, not an interruption. `CratesView` is now a full-bleed section
at nav key `crates`, built by `Sections` from a `pageCards` table exactly the way
`ForgeView`'s card is. The nav owns hiding: a page section hides the row host and
shows one card.

The page owns its own crate viewport (a 300px rail of the five pools, a 268px
model viewport, an odds strip of five weighted chips, a result plate, and the two
roll keys). The forge card keeps its quick-roll keys and a chip that switches to
the page through `Sections.select("crates")`.

**The crate is profile state**, not a roll argument that the server infers. Picking
a pool sends the `crate` action, which sets `forgeCrate` and resets the ramp for
that crate; `forgeRoll` refuses an unknown id instead of silently falling back
(it used to fall back to the banner, which quietly moved the player's ramp).
Without that round-trip the next sync painted the old pool back over the one the
player had just chosen - observed live, twice, before the action existed.

## ADR-073 - The starter hour rides the existing boost, and the daily track is records

The new-player boost is `Config.StarterBoostSeconds = 3600`, granted once on the
join that creates the profile, and it does not invent a second multiplier path:
`grantStarterBoost` writes `boostX2Until`, the same field the game pass writes, so
income, the HUD chip and the boost art all agree without a branch. `starterBoostAt`
is the idempotency flag. It is also granted to existing saves on their next join,
which is deliberate at this stage of testing: the curve can be re-measured without
wiping a profile.

The card is the one locked shell in the game - no close key, one `START FORGING`
button - because it is the only message that has to be read before play. It fires
from the `starter` event after the first payload, not on the keypress that created
the profile, so the number it describes is already the number the income formula
is using.

`Config.DailyTrack` replaced `Config.DailyRewards` as seven records carrying
`aether`, `scrap`, `starMatter`, `cores` and a `label`. Day seven pays one Quantum
Core. `claimDaily` pays every field in the record, and the Daily Ritual page
(`DailyView`) paints the whole week with claimed days dimmed to 45% text, today's
card gold, and next-up labelled explicitly. The first build of that page filled a
560px panel with 300px cards and left a dead band in the middle of every day; the
cards are 252 and the panel 470.

## ADR-074 - The top bar becomes a toolbar

Nine controls competed for one 46px nav row: five tabs, three overlays, the rate
band, the vault and the gear. The fix is the reference's: the utility keys move up
to the identity bar and the nav row keeps tabs and rate.

The top bar is now seven 50x62 keys (VAULT, CODEX, BOARDS, TRADE, NOTES, GUIDE,
SETUP), each a 22px vector mark over a 13px label, then ASCEND (88) and DAILY (78)
with their badges, pinned right. `Layout.RIGHT_CLUSTER` is the floor the canvas
must clear before anything overlaps, and `MIN_WIDTH` rose 1200 to 1320 to hold it;
the currency pill width dropped 156 to 148 to buy back the difference. Measured at
1665 design px: the bar is 1198 wide, the action bank starts at 795 and is 399
wide, the identity plate ends at 526, and 269px of air sits between them.

The badges are the only reason DAILY and ASCEND can be icon-sized: the count is
the label. `rateText` gained `x2 BOOST <time>` so the starter hour and the game
pass share one readout instead of adding a fourth pill.

## ADR-075 - The codex expands to 5,733,000 combinations

`ModifierConfig` grew from a small set to 13 elements (added gale, cinder, abyss,
aureate, prism), 8 grades (added sublime and primordial), 20 prefixes (added
tempered, ashen, stormwrought, hoarfrost, obsidian, lucent, writhing, godsteel)
and 20 suffixes (added deep, longdark, ninthhour, glass, hunger, quiet, sun,
makers). The quality ladder is 32 bands. The live codex counter reads `5733000`
combinations and `32` qualities; both numbers are computed from the tables, not
typed in.

The expansion was checked against the roll path rather than only against the
catalogue: a ten-pull from Void returned `Tempered - Forged` on the reveal plate,
which is one of the new prefixes in the existing format.

### Honesty

| Thing | State | Note |
| --- | --- | --- |
| Crate selection was proven with the `QF_Dev` seam, not by clicking the rail | `crateSelect` calls the same `pick` the rail calls | The rail rows and the selection border were photographed after a select; the pointer path itself was not synthesised. |
| The starter card's `START FORGING` key was not clicked | The locked shell has no other exit | The card and its geometry were photographed; the close path is the same `shell.close` every modal uses. |
| The daily claim was observed as already-collected, not as a fresh payout | `claimDaily` had already run on this profile | The seven cards, the streak count, the next-up label and the dimmed claimed days were verified on screen. |
| The forge card's crate chip was verified in code, not by tapping | It calls `ForgeView.openCrates`, assigned by `Main` to `Sections.select("crates")` | The same selection is exercised through `openCrates` on the seam. |
| `selene` is still the only static pass | `stylua`, `wally`, `luau-lsp` are not installed | 0 errors, 0 warnings, 0 parse errors; `rojo build` writes `verify.rbxlx`. |

---

## ADR-076 - The Foundry Instrument system

The UI read as "vibe coded" because every screen was built from a different
vocabulary: gradients on buttons, bevels on panels, text strokes on labels, four
radii, five accents. The refactor replaces the vocabulary instead of repainting
the screens.

`Theme` now ships one palette with five surfaces (`void`, `backdrop`, `panel`,
`panelRaised`, `panelSunken`), four stroke weights (`hair` 1, `thin` 1, `thick`
2, `bold` 3), and one action accent: ember `#FF7A2F`. Cyan is the cool/vent
signal, gold is mastery and Quantum, and every other hue is a rarity tint. The
type ladder was lowered so the smallest player-facing string is 13 design px:
46 / 30 / 22 / 18 / 16 / 15 / 14 / 13. `Theme.Font.Black` is GothamBold; the old
Black face was the source of the shouty headings.

`UiKit.panel` no longer bevels or lips by default. `UiKit.button`,
`actionButton` and `tab` are flat fills with a 1px rule; the tab is an underline,
not a pill. `UiKit.banner` is a flat steel plate with a left-aligned title, an
optional subtitle and an optional accent plaque. `Theme.onColor(fill)` picks ink
or white, so a saturated key never carries white text on a light fill.

Measured: the top bar is 1198 x 76 design px at a 1665px canvas; the rail is 92
wide; the content rect starts at `RAIL_X + RAIL_W + RAIL_GAP`.

## ADR-077 - A rail replaces the tab strip, and the rate moves to its foot

Seven tabs, a rate band, three overlays and two verbs competed for one row. The
rail takes navigation off the top: six 56px items with drawn marks (dim/lit
pairs), a 108px foot that now carries the rate readout, and a full-width top bar
that is chrome only. `Layout.NAV_H` is 0 and `CONTENT_X` is computed from the
rail, so a section change never moves the frame.

The section header is one 64px plate repainted on select, not seven banner
plates built and hidden. It carries an accent mark, the section title, the
kicker and an index (`RUNES / 6`). Page sections (forge, crates) hide it and
draw their own 64px banner, because their cards are full-bleed.

## ADR-078 - The forge loses the deck and the roll column

The gray scrim under the stage is gone. The strike stage now runs to the bottom
edge and three controls float over it: a 240x64 ember strike key at bottom-left
with a heavy 3px outline, a centered 380x78 heat dial (label, 30px figure, 12px
ruled bar, one caption), and a 136x64 purge key at bottom-right. Nothing is a
full-width plate, so no control covers the blade.

The roll column (ROLL, x10, crate chip, scrap/pity footer, pity meter) was
deleted. Rolling is a purchase decision and it has a page; the forge's job is the
strike. `ForgeView.roll` / `rollAnchor` / `crateFor` remain only for the `QF_Dev`
seam and `CratesView`.

The strike key's sublabel changed from `N /s` to `+N SM`: a click pays once, and
`/s` belongs on the strike-speed readout.

## ADR-079 - Heat gets a lean point instead of a lockout

The lockout was removed in the previous pass; this pass makes heat matter again
without taking the anvil away. `Config.PenaltyFrom = 90`, `PenaltyMult = 0.5`.
Past 90% every strike pays half until the player purges. The gauge prints
`OVERHOT YIELD x0.5` in danger, the fill turns danger, and the purge key is the
way back. A clicker that stops accepting clicks loses the player; a clicker that
pays half for standing in the red is a rule they can read and leave.

The gauge itself changed shape twice in this refactor: the old full-width rail
read as a loading bar, a number-only dial lost the sweet-spot position, and the
shipped version is a 12px ruled bar under a 30px figure. One caption follows the
state (`BAND 65-85`, `SWEET SPOT x2.5`, `PURGE TO COOL`, `OVERHOT YIELD x0.5`).
The fill is a solid state colour, not a blue-to-red ramp.

Measured on a live profile with the `stats` / `vent` dev seam: at 99.4% heat the
payload paid 2,911.6; after one purge, at 6.1%, the same build paid 5,823.2.
Exactly 0.5x, with no overdrive or boost running on either read.

## ADR-080 - Crates, Fleet, Runes and Store rebuilt on the Foundry grid

CRATES: the header is a 64px banner. The five odds chips became one stacked bar
(drawn common to rare) with a five-column legend, because five equal cards said
every outcome was equally likely. The rare 0.35% sliver is now a sliver. Two
equal roll keys became one quiet `ROLL` (40%) and one dominant `ROLL x10` (60%)
in the crate accent.

FLEET: the 150px full-width hero was an empty hangar. It is now 208px, two
columns: a 42% drone stage on the left and identity, three figures and the BUILD
keys on the right. The ladder prints full rung names (`CELESTIAL SWARM`, not
`CEL`) because three-letter codes are a debug readout.

RUNES: the left column was a 178px card in a 470px column. It is now a 470px
blade bay: equipped blade, rank, mastery meter, three 84px sockets, a live
`socketed bonus` grid (strike/cool/crit/vent) and the Void Shard wallet. The
bonus grid is the number the shelf is selling and it was not on the screen
before.

STORE: group headers became `GAME PASSES / 5` and `BOOSTS & UTILITY / 4` at 15px
instead of 14px captions. Prices still read `SOON` because no listing id is
configured; that is honest, not unfinished.

The Fleet stage exposed a dead asset: the sculpted drone's MeshParts are not
authorized in this place, so the viewport was empty. `DRONE_MESH_READY = false`
forces the procedural hull until the mesh is published. The viewport ambient
also rose to (152,168,200) and the camera to 6.4 units so the hull reads against
the stage.

## ADR-081 - The vault gets a Map of Content

`incremental/quantum-forge.md` is the vault's start-here note: a table of the
live docs, the current build state, ADR and build-log links, and three method
habits. YAML frontmatter (`type`, `status`, `updated`, `aliases`, `tags`) was
added to `code-map.md`, `ui-refactor-direction.md`, `build-log-forge-12.md` and
`game-design-math.md`; `game-design-brief.md` already had it. The vault is a
junction to `incremental/`; the repo stays the source of truth, so no note moves
into the vault.

### Honesty

| Thing | State | Note |
| --- | --- | --- |
| Forge, crates, fleet, runes and store were photographed in a live play session | 1536 x 864 captures after the module reload | The canvas carries UIScale 0.7193, so screen pixels are not design pixels. |
| Heat penalty is observable and applied | Gauge read 99%, `OVERHOT YIELD x0.5` and the danger fill were on screen | A/B at the same build: 99.4% paid 2,911.6, 6.1% paid 5,823.2, exactly 0.5x with no overdrive or boost. Driven through the `stats` / `vent` dev seam. |
| Roll keys were driven through `QF_Dev`, not clicked | `openCrates` / `sideTab` select the page; `CratesView.roll` was not invoked | No pointer synthesis in this environment. The keys' `Activated` handlers are the same calls the seam uses. |
| The sculpted drone mesh is invisible here | A red test part rendered in the same viewport; the mesh parts did not | The source model's MeshParts carry a MeshId that does not resolve in this place. The primitive hull is now forced. |
| `DROP ODDS` bar was read visually | Segment widths match the five weights at 55.14 / 29.87 / 13.83 / 2.41 / 0.35% | The legend and the sorted order were checked against `ForgeConfig.odds`. |
| Store listings still read `SOON` | No Marketplace id is configured | The API key lacks `game-pass:write` / `developer-product:write`; `scripts/create_store_items.py --apply` has not run. |
| `selene` is still the only static pass | 0 errors, 0 warnings, 0 parse errors | `stylua`, `wally` and `luau-lsp` are not installed; `rojo build -o verify.rbxlx` succeeds. |

---

## ADR-082 — Research is text-first, and every pass ends in the vault

**Context.** The first six notes in the vault are video breakdowns. Video is a slow
research medium here: there is no transcript to quote, the player cannot be
searched, and a claim has to be remembered rather than linked. The GitHub pass was
run to answer the same questions from material that can be read, quoted, and
checked against source code.

**Decision.** A research pass uses GitHub topics, curated lists, and the primary
repository or design-skill pack. It lands as **one synthesis note**, not a reading
log: `game-design-research.md` holds the findings, the audit, and a ranked action
list. A note must say what was read, what was skimmed, and what was not opened.
Video notes stay in the record as historical source analyses; they are not
rewritten when the game changes.

**Why.**

- A linked repository can be re-read; a remembered video cannot.
- Source code is the honest version of a game's design. READMEs describe intent;
  `stargaze.js` shows what the reset actually pays.
- One synthesis note is maintainable. Seven half-filled reading notes are not.
- The audit is the deliverable. A research note that does not change a decision is
  a bibliography.

**What it costs.** GitHub research over-represents developers who publish code. It
says little about player sentiment, retention curves, or what a ten-year-old on a
phone actually enjoys. The findings are therefore **hypotheses**, not measurements.
Every action in the research note carries a size and a "not built" status until a
live session proves it.

**Vault cleanup, same pass.** The unreferenced `images/actually-from-youtube.png`
was removed. The five UI reference captures were renamed to
`images/ui-reference-01..05.png` and kept because ADR-080 cites them as evidence.
`project-readme.md` was kept as the long-form record but marked superseded where the
Forge 13 UI and the lean point changed the truth; deleting it would have lost the
asset pipeline and the systems history. Old build logs were kept: they are measured
history, and the index links them. The rule is **delete duplicates and dead
artifacts, not history**.

**Guard.** A research note ends with an **Audit** and an **Honesty** table. No
action is marked shipped until it is built and verified. No stale rule is left
standing in `game-design-brief.md`, `game-design-math.md` or `project-readme.md`;
where a doc disagrees with an ADR, the ADR wins and the doc gets a pointer.

---

## ADR-083 — The crate reveal is a ceremony, not a text swap

**Context.** The Forge 13 pass rebuilt the crates page into a real section, but the
reveal was still one shatter and a label swap. A ten-pull reported only its best
copy and a `x10` caption, so nine of the ten things the player paid for were
invisible. Pity printed its threshold (`PITY 11 ROLLS`) instead of progress. Two
fairness bugs sat under the surface: a maxed Thermal Calibration reached a 95 band
while the lean point started at 90, so the top five points paid half under a 2.5x
caption; and the gauge drew the build-time 65-85 band forever, so the screen
disagreed with the economy whenever the tech moved the band.

**Decision.**

- The server's `forged` event carries `results` (every copy in roll order),
  `power`, `equipped`, `newBlade` and `newVariant`. The top-level fields remain
  the best copy for older callers.
- The crates page stages a five-beat reveal: drop, six-beat rattle, held charge,
  crack, copy. The charge bar, the last tick, the anticipation ring and the
  `REVEAL_HOLD` pause are all part of the wind-up.
- Rank 3 and up get rays and a beam; rank 4 and up get an extra ring after the
  first; rank 5 delays the info entrance by 0.34 s so the copy lands alone.
- A batch pull gets a ribbon under the result, one cell per copy, variant on the
  left edge and rarity on the bottom edge. Each cell lands 0.06 s after the last;
  the best copy is marked by blade id and power.
- Pity is drawn as progress: `PITY 3 / 11`, one tick per roll, and
  `GUARANTEE NEXT ROLL` at the edge. The card explains that the counter follows
  the profile and only resets when a Void or better lands.
- Crate unlocks are per run. The copy says `RUN`, not `LIFETIME`.
- Thermal Calibration clamps `sweetSpotMax` to `Config.PenaltyFrom` (90), and the
  heat gauge repaints its band from `payload.bandMin` / `payload.bandMax` on every
  sync. A full-height 90% tick marks the lean point.
- Rarity colours come from `BladeRegistry.RARITY_INFO`. Quantum is mint, not the
  gold used for Star-Matter; the same word no longer means two colours on two
  screens.
- `BACK TO POOL` exits a result without buying another pull. `QF_Dev` gains
  `cratePreview` (force a reveal) and `crateDismiss` (the same path the button
  takes).

**Why.**

- Anticipation is the lever the research note ranks highest for the crate. A
  ten-pull has to show ten things or the batch is a discount, not a run.
- Pity is a near-miss. A threshold is a rule; progress is a near-miss.
- A rule the player can see has to match the rule the server pays. The 90 tick and
  the band clamp make the lean point legible before the player crosses it.
- The crate is the peak of the session. A peak needs a shape, a rise, and a
  landing; the old reveal only had the landing.

**What it costs.**

- Press to result is about 2 s (drop, six beats, hold, flash). A player in a hurry
  pays it on every pull; the ten-pull amortises it across ten copies.
- The page is a bigger state machine: idle, charge, hold, reveal, result, ribbon,
  dismiss. The `QF_Dev` seams are the only way to drive it without a pointer.
- The ribbon depends on the server payload. A legacy event with no `results` falls
  back to the best copy and hides the strip.

### Honesty

| Thing | State | Note |
| --- | --- | --- |
| Static gates | `selene src/` 0 errors, 0 warnings, 0 parse errors; `rojo build -o verify.rbxlx` succeeds | `stylua`, `wally` and `luau-lsp` are still not installed. |
| Charge phase | Property read at 0.9 s: bar visible, fill 0.63, caption `BREACHING`, tag hidden | Not photographed at the exact beat; the screen capture latency is longer than the hold. |
| Ten-pull ribbon | Live pull returned 10 copies; the strip showed all 10, the best cell marked, power 4.18K, auto-equipped | The stagger was seen as a completed strip, not as a mid-sequence frame. |
| Top-rarity reveal | `cratePreview quanta_verge` forced Prismatic/Quantum; rays, ring and `NEW BLADE` rendered | The natural 0.35% path was not observed. The preview has no power, so the power row hides. |
| Dismiss path | `crateDismiss` returned result hidden, rest visible, tag hidden, one WorldModel mounted | The `BACK TO POOL` button was not clicked with a pointer; the seam calls the same function. |
| Heat band | 99% showed `OVERHOT YIELD x0.5`; vent to 43% showed `BAND 55-90` with the 90 tick | The band now follows the payload; the clamp is in `TechTreeConfig`. |
| Pity label | Live page read `PITY 9 / 11` and `GUARANTEE IN 2`; ticks filled to 9 | The guarantee switch was not crossed in this session. |
| Sounds | New heavier roll ticks and the result fanfare call are code-verified | The kit is unchanged apart from `rollTick`; the new layers were not heard in this pass. |
| Result layout | `BackToPool` 285-299, `PullRibbon` 309-333 at the test window, so the two do not overlap | Absolute positions were checked because the screenshot scale hides 10 px. |

## ADR-084 - The crate ceremony takes the whole screen

**Context.** The reveal shipped as a card floating over the crates page: a tier
wash, a stage, and a two-column block of odds and pity. That card covered two
thirds of the width and fought the page behind it, and the model — the one thing
the player paid for — sat beside a paragraph of type instead of in the middle of
the frame. Darkening the card only made it read as a modal dialog.

**Decision.**

- The ceremony is a canvas-level overlay above every page and below `Vfx`, not a
  card. The page behind it is gone for the duration: the scrim is opaque black,
  with a `StageBackdrop` wash painted full-bleed behind the props. The wash has no
  edge because every band inside it is exactly the size of the frame it is painted
  on, and that frame is the window.
- The overlay is measured against the real viewport, not the canvas sheet: it is
  pushed up by `GuiService:GetGuiInset()` and sized to `viewport + inset` in canvas
  units, so it covers the strip the fixed 1686x720 sheet leaves uncovered. CoreGui's
  top bar sits outside every game GUI and is left alone.
- The model is the announcement: one small pool line above, a click prompt below,
  pips for the pull, and a name plus one stat line after the reveal.
- A pull of three mounts three crates and a pull of ten mounts ten, laid out by
  `CratePreview.layout`. One click breaks one crate. `Activated` can arrive twice
  for a synthetic press and release, so a 120 ms floor collapses the duplicate.
- The strike answers with the anvil's own effect: a `Vfx.shockwave` at the cursor
  plus sparks and a burst, then the crate jumps, turns and fades.
- `Vfx.pointer` subtracts `GuiService:GetGuiInset()` once. `GetMouseLocation` is
  viewport space and `AbsolutePosition` is GUI space; without the correction every
  ring landed 58 px below the cursor on this build.

**What it costs.** The overlay covers the HUD, so the player cannot watch their
balance while opening. The wash is a full-screen composite of seven frames: cheap,
not free on a low-end phone.

## ADR-085 - Scroll canvases are measured in canvas units

**Context.** The store and the fleet both refused to scroll even with rows hanging
below the window. `Sections.fitCanvas` measured `column.AbsoluteSize.Y` and wrote
it straight into `Content.CanvasSize`. `AbsoluteSize` is already multiplied by the
canvas `UIScale` (0.72 on the test window), while a `CanvasSize` offset is
multiplied on the way out. The store therefore reported a 451-unit canvas over
372 pixels of window, which renders as 324 pixels of canvas: shorter than the
content, and impossible to scroll.

**Decision.** `fitCanvas` divides the measured height by the canvas `UIScale`
before writing `CanvasSize`. `AutomaticSize` never writes back into `Size`, so the
scale is read from the canvas's own `UIScale` rather than inferred from the column.

**What it costs.** One extra `FindFirstChildOfClass("UIScale")` per fit. The fit
runs on column size changes, not per frame.

## ADR-086 - VIP is a bundle, not a badge

**Context.** `vipAura` shipped as status only, so a player who bought it still had
to buy Fast Forge, Auto-Vent, 2x Star-Matter and Eternal Forge separately. That is
a storefront that punishes its biggest buyer.

**Decision.** `refreshPasses` expands an owned VIP into every other configured
pass after the individual ownership checks. The grant is server-side and persisted
like any other pass, so a later revocation of VIP does not take the other passes
back with it.

**What it costs.** VIP cannibalises the four smaller passes. It is priced at R$499
against R$1499 for Eternal Forge alone, so the bundle is the cheaper path on
purpose: one purchase beats five prompts.

## ADR-087 - A batch reward has an afterglow, and the claim is a curtain

**Context.** The full-screen ceremony fixed the reveal but spent its whole budget
on the payoff. A x3 or x10 still ended on one blade and a `COLLECT 3` key, so
nine of the ten swords the player paid for were invisible. The key also closed
the overlay on the same frame it was pressed, which read as the screen being
yanked away. And the blade turntable could catch the hero shot edge-on, so a
still looked like a stick.

**Decision.**

- The result state gives 64 px of the viewport back to a copy rail. Every copy in
  the transaction gets a chip: dice name, rarity, and a gold `BEST` tag on the
  copy the server marked. Chips stagger in left to right so the row is read.
- `COLLECT` is locked for 0.55 s after the reveal. The key is a dismissal, not a
  skip: a press before the player has seen the result is ignored.
- The claim plays its own beat (white wash, shockwave, sparks, claim stinger,
  rumble) and closes 0.14 s later, behind a VFX flash that lives above the scrim.
  The cut is hidden by the celebration instead of being the celebration.
- `BladePreview.mount` accepts `spin`. The ceremony passes `spin = 0`, so the
  reward holds the hero yaw and the player can orbit it by drag. The forge and
  vault keep their turntables.

**What it costs.** The rail costs 64 px of blade height and ten labels on a
ten-pull. The claim costs 0.14 s of dead time that is covered by the flash.

## ADR-088 - A click inside a panel is not a dismiss

**Context.** The vault, codex, leaderboard, handbook and trade desk all sit on a
`TextButton` dimmer. The panel itself is a `Frame`, and a Frame does not sink
pointer input. A click on a gap between cards, under the inspector, or on the
banner's empty space fell through to the dimmer and closed the whole sheet. To a
player that is the UI randomly disappearing while they are reading it.

**Decision.** The dimmer checks the pointer against the panel's `AbsolutePosition`
and `AbsoluteSize` and ignores the click when it lands inside the panel. The
gutter around the sheet remains a close target. `ModalShell` and the vault's
private overlay both implement the guard; a future modal that uses either gets
it for free.

**What it costs.** One `GetMouseLocation` and two rectangle reads per close
attempt. A panel that covers the whole screen has no dismiss-by-click path and
must keep its close key; every current panel does.

## ADR-089 - The store is a price ladder, and VIP is the bundle

**Context.** ADR-086 priced VIP at R$499, below Eternal Forge, and put Fast Forge
above Eternal Forge in the storefront. Every listing was still a placeholder id,
so the store read `SOON` and could not sell anything. The starter pack also
advertised 25 Aether, which is not a starter pack.

**Decision.**

- Prices are a ladder: Fast Forge 99, Auto-Vent 149, 2x Star-Matter 199, Eternal
  Forge 1499, VIP 1699. Eternal Forge is the strongest permanent and is priced
  above every other item except the bundle; it is listed directly under VIP.
- VIP is cheaper than the sum of the other four passes (1946), and grants every
  other pass on purchase, not only on the next join.
- The Open Cloud script is idempotent: it lists existing passes and developer
  products by name, creates only what is missing, and patches the ids back into
  `MonetizationConfig`. Creating a listing does not charge Robux; only a
  purchase does.
- The starter pack pays 500K Aether and 20 minutes of double income.

**What it costs.** VIP saves the player 247 Robux and cannibalises four smaller
passes. The ladder is tuned to make the bundle the obvious second purchase, not
the first: a player who only wants one convenience still has a 99 Robux door.

## ADR-090 - A crate unlocks on the run, and a locked pool is still a window

**Context.** The crate ladder was written against lifetime Star-Matter and later
moved to run Star-Matter (`ProgressionService` gates both the quote and the roll
on `state.runStarMatter` and refuses with "unlocks at N run Star-Matter"). The
crates page, the build log and the project readme still said lifetime, and
`ForgeConfig.crateUnlocked(tier, lifetime)` survived as a second, wrong definition
of "unlocked" that nothing called.

**Decision.**

- One authority: a pool is unlocked when `StateStore` carries a quote for it.
  The server only prices pools whose `unlock` the run has passed, so the client
  never re-derives the gate. `ForgeConfig.crateUnlocked` is deleted.
- A locked pool is browsable. Clicking its rail row still selects it, the 3D
  silhouette still mounts, and the info column still prints the name, blurb and
  odds. The player can inspect what they are climbing toward.
- A locked pool is not rollable. All three keys read `LOCKED` with no price, the
  stage swaps the pity row for an `OPEN AT N` bar and a run-percentage caption,
  and `roll` returns before it opens the ceremony or sends `forge`.
- The gates themselves did not move: 0 / 60K / 8M / 600M / 400B, now read against
  the run so an ascension re-opens the climb.

**What it costs.** A locked pool has no pity readout and no stage action, so the
page is honest about being locked without offering a shortcut. A player who
ascends loses access to the top pools they were browsing, which is the point of
the run gate but will read as a demotion unless the rail's percentage makes the
next climb obvious.

## ADR-091 - VIP needs a body, not only four multipliers

**Context.** VIP is the most expensive listing in the store and grants four
passes. Every one of those passes is a number: two income multipliers, a click
rate, an auto-vent rule. Nothing on screen changed after the purchase except the
store row, so the bundle's only feedback was a toast. Worse, the character aura
that was supposed to carry the flex was anchored: `AuraRing` was created
`Anchored = true` and then welded to the root, so it stayed at the spawn point
while the player walked away.

**Decision.**

- The sync payload carries one `vip` boolean. The client never receives the pass
  map: it prints a badge, it does not decide a grant.
- `ProfilePlate` paints a gold `VIP` chip on the handle row, and the `@handle`
  gives up the width. The chip is 38x14 design px at the 13px floor, gold fill,
  ink text, and hidden unless the flag is set.
- `LobbyService` paints the aura in two layers. The inner ring and the motes keep
  the equipped blade's rarity glow; the outer `VipRing` and the floating
  `VipTag` are gold and only exist for VIP. Additive, because a VIP holding a
  Quantum blade should still read as Quantum first.
- The 1Hz repaint cache keys on blade id **and** VIP, so a purchase shows within a
  second without a rejoin. The ring is unanchored so the weld can actually carry
  it with the character.

**What it costs.** Two extra instances per character rather than a shader, and a
64px billboard that can add noise to a crowded bridge (`MaxDistance` 80 keeps it
from being readable across the whole platform). Gold is already the leaderboard
and gold-rarity colour, so the VIP ring has to stay outside the rarity ring to
keep the two readings apart.

## ADR-092 - Six clicks to a secret, one claim per sword

**Context.** The crate opened on one press and the whole batch was taken by one
`COLLECT 10`. Both compressed the two moments the ceremony exists for: the
suspense before the answer and the afterglow after it. A single press cannot be
suspenseful, and one key that swallows ten swords is a receipt, not a reward.

**Decision.**

- A single crate and a triple both cost six clicks; a ten-pull costs ten. The
  triple divides its six clicks in two per crate, so every crate takes a light
  hit and then a heavy one. A ten-pull keeps one click per crate because ten
  crates are already ten objects on screen.
- The click budget comes from the batch the server actually charged, and `open`
  derives `perCrate = strikeTotal / batch`, so a pull trimmed to three slots by
  vault space is a six-click triple, not a mispriced ten.
- The result is a queue. The best copy is shown first (it is the payoff the
  reveal just sold), then the rest in roll order. Every claim is a beat: chip
  greys to `CLAIMED`, rarity flash, spark cone, `Sfx.claim`, 0.3s key lock while
  the hero swaps. The last claim is the exit.
- `Sfx.claimAll` is the downbeat for the last copy; a ten-pull that ended on the
  same note as its tenth claim would feel like the loop never resolved.

**What it costs.** A ten-pull is now ten presses to finish, and a player who
wants to leave has to tap through the queue. The key hides for 0.3s between
copies, which is dead input on purpose: a held mouse must not eat two swords.

## ADR-093 - Light is a sprite, and the gunshot is not in the kit

**Context.** The ceremony's light was painted with bare Frames: a 4px column
with a vertical gradient and nine 2px rays. A gradient on one axis cannot make a
soft edge, so the column read as a white bar and the fan as debug lines. The
sound kit also carried `impact_explosion_03` and `swordslash`, which read as a
stray gunshot and a blade whip under a wooden box.

**Decision.**

- The column, source halo, floor pool and result halo are `smoke_main.dds`, a
  proven-present client texture with a real falloff. The star and the eight
  needle shafts are `sparkles_main.dds`. `whiteCircle.png` was tested and
  rejected: it is a hard flat disc, not a glow.
- One `NumberValue` drives every beam layer through `paintBeam(strength)`, so
  the wind-up cannot desynchronise into four tweens landing on different frames.
  The column is faint at rest, grows with each strike, opens for the hold, and
  flashes on the reveal.
- `impact_explosion_03` and `swordslash` are removed from `Sfx`, not just from
  the crate. The body is `hit.wav`, the crack `snap.mp3`, the ring `metal.ogg`,
  the tick `clickfast.wav`, the air `impact_water.mp3`.
- A heartbeat is a pitched-down thud, not an explosion; a claim is a ping pair
  over the ring of the blade.

**What it costs.** Three textures instead of zero. They ship with the client, so
there is no upload to fail, but they are also not authored for this game: the
smoke puff is a smoke puff, and the star is the stock four-point sparkle. The
alternative was a flat rectangle, which is worse.

## ADR-094 - A locked pool is local browse state

**Context.** ADR-090 described locked pools as browsable, but the page still
sent `crate` to the server on every pick. The server refused the locked id (it
must not switch the profile's ramp to a pool the run has not opened), and the
next sync followed `forgeCrate` back to the old crate. The browse lasted one
tick, which is why it still read as "I cannot view locked crates".

**Decision.** `pick` sends nothing for a pool with no quote. `CratesView` keeps
a `browsingLocked` flag and the sync loop skips the server-follow while the
selected pool has no quote. As soon as the pool unlocks, the flag clears and the
server is authoritative again.

**What it costs.** One more piece of client state that has to be cleared on a
real pick. A future action that assumes `selected` is always the profile's
`forgeCrate` would be wrong while a locked pool is being inspected; the roll
path already reads the quote, not the selection.

## ADR-095 - The top crate pays a Quantum once in fifty, not once in six

**Context.** Singularity Vault had Quantum at 16% and Celestial at 8%, so the
rarest blade was routine by the time a player could afford the top pool. Every
pull at the top was also Astral-or-better 88% of the time, which made the
lower rarities decorative.

**Decision.** The five weight columns were rewritten so expected rarity rank
still climbs every rung (1.63 / 2.09 / 2.45 / 2.74 / 2.99) while the top rarity
stays rare: Quantum is 0.4 / 1.2 / 1.5 / 2 / 2 percent. Astral and Void absorb
the difference. Pity still forces Void-or-better on schedule, drawn from the
crate's own column, so a bad streak has a floor without making Quantum common.

**What it costs.** A top-tier ten-pull now has roughly an 18% chance of one
Quantum instead of a near-certain one. That is the point: the codex is a chase
again, and the lower pools keep a reason to exist.

## ADR-096 - The rail is the claim queue

**Context.** The claim queue was best-first, but the rail was painted in roll
order. On a ten-pull the best copy was often the last roll, so the first claim
put the gold outline on the last chip while the hero read COPY 1 OF 10. The
player read that as the order being random, and the outline looked stuck on the
last sword instead of tracking the claim.

**Decision.** The rail is painted in claim order. The best copy is the first
chip, the rest follow in roll order, and `claimQueue` is that same list.
`paintRail` takes an explicit `order` and stores each chip by copy index. The
gold edge and the bottom rail are a cursor: `showCopy` moves them with every
claim, claimed chips grey to `CLAIMED`, and the best chip keeps its gold tag
until it is taken. The active chip gets a 3px gold outline and a gold rail;
inactive chips fall back to their rarity edge.

**What it costs.** The rail is no longer a literal roll receipt; it is a claim
queue. The chip names are display positions, not roll indices, so any future
code that maps a chip back to a roll must go through `claimQueue`.

## ADR-097 - The crate is a major scale

**Context.** The crate clicks were a pentatonic tick, the sealed hold climbed a
pentatonic riser, and the reveal landed on arbitrary pitches. The sequence had
no key, so the clicks read as a timer rather than as a phrase. The request was
to study the do-re-mi method and apply it to the chest opening.

**Decision.** The crate click ladder is the major scale. A six-click pull plays
do re mi fa sol do; a ten-click pull plays do re mi fa sol la ti do sol do.
`index` is the click within the whole pull, so a triple's two clicks per crate
continue the phrase instead of restarting it on every crate. The sealed hold's
riser is the top of the scale ending on ti, the leading tone that cannot resolve
by itself. The reveal fanfare is a C-major arpeggio (do sol do mi sol do), the
claim is a sol-do fourth, and the final claim adds a low do. Every note is the
same `electronicpingshort` sample pitched by playback speed, so the sequence
adds no asset and cannot fail an upload.

**What it costs.** The melody is only as expressive as one short ping, and the
key is relative: playback speed 1.0 is "do", so the scale is consistent inside
the game but not with an external track. The anvil keeps its pentatonic ladder;
the crate and the anvil are deliberately different instruments.

## ADR-098 - The crate sells the hit with a flash, not a camera move

**Context.** The anvil feels right and the crate did not, and the difference was
not the model: the forge answers every press with a full-screen flash, a punch
and sparks. The crate answered with a small shockwave. The first fix added a
stage zoom and a large shake on every click, which made the crate read as the
camera being knocked around rather than as the crate being hit.

**Decision.** The per-click answer is a scrim flash in the crate accent (white
on the click that gives the seal), a wider shockwave, more sparks, and a
burst on the opening blow. The stage no longer scales per click; the shake is
1.3-4.5px, and the reveal is 6+1.2*rank. The crate knock tilts 7/10 degrees
and pulls the lens 3 units instead of 14/18 and 7. The reveal keeps one 1.08
scale punch and adds a fast white ring inside the rarity ring, the forge's
Vfx.resultWash for Void-Touched and Prismatic, and a 0.18 s name slam.
The orbit controller now ignores the first 8px of cursor travel, so a twitchy
press on the full-screen strike button cannot rotate the preview; a real drag
still orbits. Crate sound gains are 1.35-1.4x, the tick ladder is louder,
and the shatter gained a slow air layer for mass.

**What it costs.** A ten-pull strobes the scrim ten times in about two
seconds. The wash is capped at 0.42 until the final click and fades in 80-130
ms, so it reads as impact rather than as a strobing screen; reduced motion
collapses it with every other tween. The camera deadzone delays the start of a
drag by 8px everywhere, which is below the perception threshold for a real
drag and above the jitter of a click.

## ADR-099 - Impulse prices, and both boosts on the chip

**Context.** The store shipped a ladder from 99 to 1699 Robux: Eternal Forge at
1499, VIP at 1699, the passes at 99-199. That is a price for a game with an
audience. On a small game nobody spends 1000 Robux on a convenience, so the
top of the shelf sold nothing and the 99 Robux door still asked for a decision.
Emergency Vent was also a paid copy of the free vent key: it charged Robux for
a button the player already had, which reads as a trap once discovered.

The HUD had the mirror problem. The chip printed the timed 2x from the Starter
Pack in the same dim grey as a drone count, and the paid 3x was not in the sync
payload at all. The server already multiplied both boosts in
`globalMultiplier`, but a player who bought the 3x saw no change on screen, so
the stack looked broken.

**Decision.** Every pass is 59 and VIP is 119, so the bundle (119) stays half
of buying the four passes separately (236). The Starter Forge Pack is 9.
Emergency Vent is delisted: the listing is off sale, the config entry and
storefront order entry are gone, and `MonetizationService` keeps a retired
receipt map so a purchase made before the delisting still settles instead of
retrying forever.

`paidBoostRemaining` is now in the sync payload. The HUD multiplies the timers
like the server does (2x and 3x print as x6), counts down to the first boost to
expire, and paints the line gold instead of the dim grey used for drone counts.

**What it costs.** There is no high-ticket sink any more: revenue per conversion
is small, and the bet is volume and goodwill. The VIP row's "Buy separately"
total is computed from the live prices, so a future price change moves that
sentence without a second edit. The retired Emergency Vent listing still exists
in the Creator Dashboard; it is off sale and unreachable from the game.

## ADR-100 - A bought pass says BOUGHT; a consumable never does

**Context.** Every pass button stayed a green price key after the player owned
it. The server ignored the second prompt, but the storefront still looked like
it was selling something the account already had, so a bought pass was
indistinguishable from a buyable one until the click did nothing.

**Decision.** The sync payload carries `ownedPasses = state.passes`, and
`ShopView` keeps its pass rows by config key and repaints them from that table.
An owned pass prints `BOUGHT` on the same green plate, with `Active` off, so it
reads as a receipt rather than a call to action. VIP is a bundle, so buying it
flips every pass row at once. Products under `BOOSTS & UTILITY` are consumables
and deliberately never print `BOUGHT`: Starter Forge, Instant Overdrive and
Express Salvage stay buyable no matter how many times they have been bought.

**What it costs.** The store now depends on a table it used to ignore, and the
button is repainted on every 10 Hz sync. That is a few property writes for five
rows. It also means a pass granted outside `state.passes` would still look
buyable until the grant reaches the same table, which is why every grant path
already writes through `grantPass`.

## ADR-101 - The crate floor is quoted in seconds of income

**Context.** The test profile had every pool open and was buying Singularity
rolls for a fraction of one click. Two things had drifted: the unlock gates were
low enough that the whole ladder arrived early, and the income floor was
`18` strikes of click yield. A late profile clicks several times a second, so
eighteen strikes was two or three seconds of play. The sink was being charged;
it just read as free.

**Decision.** The gates widen to `0 / 2e5 / 3e7 / 2.5e9 / 1.5e12` run
Star-Matter. The floor is now stated in seconds:
`RollIncomeSeconds = 18`, multiplied by the crate's rung (`18 / 36 / 54 / 72 /
90` seconds) and by `RollIncomeClickRate = 6`, the base clicks per second the
quote assumes. `ProgressionService.clickIncomePerSecond` supplies the per-click
yield at that rate, and both the quote and the charge call the same function.
`bulkRollCost` sums the floor with the same `1.05` per-roll ramp as the banner
price, so a ten-pull still costs what ten singles would. The handbook prints
seconds, and a locked rail row says `<1% TO OPEN` instead of a dead `0%`.

**What it costs.** A fresh profile's first Standard roll is 540 Star-Matter at
the opening fivefold strike, not 90, which is about eighteen seconds of assumed
clicking. The second crate is a 2e5 gate rather than 6e4. The floor uses click
income, not passive income, so a drone fleet does not silently reprice the
crates; Fast Forge also does not raise the quote, because the rate is the base
rate rather than the player's own.

## ADR-102 - The forge gets a room tone, and the crate loses its wind

**Context.** Between anvil hits the game was silent, which read as dead rather
than as quiet. The crate also carried an `impact_water` layer in its landing,
shatter and tick sounds; at crate pitch it reads as a wind whoosh over the
ceremony rather than as weight.

**Decision.** `Music.luau` loops APMOfficial's "Dark Pulsing Synth"
(`rbxassetid://9042781325`, a free Creator Store track, 2:24) at `0.16` under
the sound kit. It fades in over 2.4 seconds, fades out over 0.5, cancels an
in-flight gain tween before starting another, and has its own persisted
`settings.music` switch rather than riding on `settings.sfx`. `Main.client`
applies it on the first payload and the MUSIC row in `Sections.openSettings`
flips it. The crate's `crateLand`, `crateShatter` and `crateTick` no longer play
the water layer. Vent, overheat, burnout and melt keep their steam hiss: those
verbs are air, and the sound is the event rather than a bed.

**What it costs.** One more asset dependency and one more migration field in
`sanitiseSettings`: a save written before the MUSIC row inherits its old `sfx`
value, so a muted player does not come back to a loop, while a new save starts
with music on. The switch is separate, so a player can run the anvil dry or keep
the bed with the effects muted, which is the point. The crate landing is drier
now; if it needs air later, it should be a purpose-built riser rather than the
water impact returning.

## ADR-103 - Audio is a level, not a switch

**Context.** The settings sheet could only mute. A player who wanted the crate
quieter had two choices: full mix or silence, and the only way to make the crate
sound bigger was to change the mix for everyone.

**Decision.** `Settings.sfx` and `Settings.music` become `sfxVolume` and
`musicVolume`, both 0..1 and persisted. The settings sheet draws them as 0..100
sliders: the percentage is the readout, the whole 26px strip is the hit area, and
0 is the mute. `Sfx.setVolume` is the one gain every layer passes through;
`Music.setVolume` scales the 0.16 bed and pauses at zero without restarting the
track when the level returns. A drag applies locally on every step and writes
the latest value after a 120 ms settle, so a sweep is one action on the wire.
Old saves migrate once: a muted boolean becomes 0, an unmuted one becomes the
default level (0.8 SFX, 0.55 music), not full.

**What it costs.** Two numeric fields instead of two booleans, and every audio
call now reads a multiplier. The crate mix was raised in the same pass because a
default 0.8 would otherwise have made it quieter than the build players already
heard: `crateLand` gained a low chest layer, `crateBreak` and `crateShatter`
gained body, and the tick, heartbeat and riser all moved up. The old `sfx` and
`music` keys are still accepted by `setSetting` so a client that was already open
during the deploy does not get a rejected write.

## ADR-104 - The strike plate leaves, the stage keeps the click

**Context.** The forge had a 240x64 orange STRIKE key in the lower-left corner.
It was the only saturated rectangle on a screen whose subject is a blade, so the
eye went to the button rather than the sword. It also duplicated the stage,
which was already a full-bleed hit target.

**Decision.** Delete the key. The transparent full-bleed `StrikeButton` remains,
with the same `InputBegan` handler, so every pixel of the render still strikes
and the latency is unchanged. What is left in the corner is a small caption,
`STRIKE  +N SM`, which turns sweet-spot gold when the band is live. The heat dial
and the purge key keep their own clicks above the stage layer.

**What it costs.** The verb is now carried by the render and the caption rather
than a button face. That is enough for a player who has already struck once, and
the tutorial and the `STRIKE SPEED` readout still name the action. A first-join
player who does not read the caption has the whole stage as the target, which is
the larger affordance anyway.

## ADR-105 - A crit is a gold ring, not a bigger flash

**Context.** A crit already fired a gold float, a screen flash and a spark
burst. At strike speed that read as "a slightly bigger hit"; there was no shape
the player could learn to look for, and the sound arrived without a matching
silhouette.

**Decision.** The crit branch calls `Vfx.strikeBurst(anchor, gold, 2.3, true)`
when no sprite sheet is available. That composite adds a gold shockwave ring to
the sparks and the flash, and `Sfx.crit` still fires on the same server event.
The ring expands from 32px to roughly 100px over 0.28s, which is long enough to
register and short enough not to sit over the next strike.

**What it costs.** Three more tweens on the crit frame and one more frame in the
VFX layer. The ring is skipped under reduce-motion, like every other travelling
effect, so the crit still has the float and the flash for those players.

## ADR-106 - A mesh renders only after its content fetch succeeds

**Context.** `InsertService:LoadAsset` can return a Model whose MeshParts have
names, sizes and CFrames but no renderable mesh, because the experience is not
allowed to fetch the asset. `applyMesh` counted the parts, returned true, and the
viewport showed an empty stage. That is the "the sword sometimes does not show up
at all" report. The primitive recipe existed the whole time; it was simply never
reached.

**Decision.** `BladeModelBuilder` keeps a per-asset state: unknown, verified or
failed. `verifyMesh` gathers every `MeshPart.MeshId`, calls
`ContentProvider:PreloadAsync`, then requires
`GetAssetFetchStatus == Enum.AssetFetchStatus.Success` for every id. Until that
lands, `meshSource` returns nil and the primitive recipe renders. `watch` fires
only on a verified asset, so the mesh hot-swaps in place when the fetch succeeds.
A failed mesh never replaces a visible sword.

**What it costs.** The first viewport on a server renders primitives for a few
seconds longer than before, and a client that cannot fetch the mesh keeps them
for the session. That is the correct trade: a visible placeholder beats an
invisible upgrade. The checks run once per asset in a background task, never on
the UI path.

## ADR-107 - Forge Feats keep the next goal alive

**Context.** The next-goal rail could go blank. Crates, drones and tech are all
finite, and after the tree is maxed the game answered "what now?" with nothing.
The economy still moved, but there was no named target. External design sources
agree on the failure mode: an incremental without a visible next goal is a
number going up in an empty room.

**Decision.** Add `FeatConfig`, thirty-five one-time feats across fortune,
lifetime cores, ascensions, tech levels, blade mastery, codex discoveries,
sigil sets and fleet size. Every feat is +1% to click and drone yield, scored
from counters the save already keeps, so there are no new fields and no claim
button. The Tech section gets a gold FORGE FEATS card: completed count, the
permanent bonus, the progress bar and the four nearest incomplete goals.
`NextGoal` adds the nearest feat as a candidate, which keeps the rail foot alive
after every other ladder is finished.

**What it costs.** `clickYield` and `passiveYield` now build a feat snapshot, so
the hot path walks the mastery map and the thirty-five-row table. The tables are
small and the alternative was a second cached counter that could drift. The
bonus is deliberately modest: 35% at full completion sits under one blade step,
so feats are direction, not a replacement for the blade ladder. The feat card
reads existing counters, which means a hand-edited save can complete a feat it
did not earn; the bonus is small enough that this is not worth a signature.


## ADR-108 - The visual guide is a work-order card, not a popup

**Context.** The onboarding had collapsed to a single welcome card whose only
lesson was a `START FORGING` key. The eight-card spotlight chain before it was
deleted for good reasons: it dimmed the game, it interrupted, and its predicate
wiring let steps advance on their own. Neither shape taught the loop a new player
actually has to run in the first two minutes: strike until the core can vent,
purge, spend the Aether on a drone, then open a crate. The requirement was a
visual guide that stays out of the way, in a text box, with no black overlay and
no popup, every step optional, and a way to watch it again from the handbook.

**Decision.** `TutorialController` is eight coach notes. Each note is a 360x176
card with a step counter, a title, one or two sentences, a progress rule and a
`SKIP` key, plus a gold marker on the live control: a 2px rounded ring grown 6px
outside a button or rail tab, and four 26px corner brackets on the forge stage,
which is a full-bleed region that already carries a gold border, so a second
frame there would read as a double border. The card is placed relative to the
target (right, left, above, inside the stage's dead top-left corner) and clamped
to the canvas; the closing note stays where the previous note was instead of
hopping onto another live control. Targets are resolved by name on every poll,
and a target on a hidden section drops the marker rather than pointing at empty
space.

The steps are strike, purge, save for a drone, open FLEET, build a drone, open
CRATES, roll a blade, done. Prices and thresholds are read from the payload and
`Config` at paint time, never typed into copy. Advancement comes from real
actions: heat at the vent line, the `vent` event, the Aether balance, the active
rail tab, a drone count above the run's starting count, and a blade count above
the run's starting count. Nothing is a click-through carousel.

Step 2 is the whole reason the server is involved. The gauge cools at 5/s, so by
the time a player reads "press PURGE" the heat that made the key legal is gone.
The client sends `tutorialHold` when the run starts. While armed, `ForgeService`
caps heat gain at `Config.VentThreshold`, stops decay once the gauge reaches it,
and suppresses the auto-vent pass. The hold clears on the real vent, on skip, on
leave, and after 120 seconds, so a client cannot park the gauge forever. Strikes
while held are also denied the sweet-spot multiplier, because a frozen 85 would
otherwise be the top of the band and a free 2.5x.

The handbook's rail foot carried the `SKY + METAL: LIHFOLK` credit. That slot is
now `REPLAY VISUAL GUIDE`: it closes the book, then starts the notes. It reads
GUIDE RUNNING and is inert while a run is live, so two runs cannot overlap. The
top bar's GUIDE key is the same escape hatch: SKIP during a run, the handbook
after it. `guideSeen` and `tutorialCompleted` keep their old meaning; a replay
pays no second reward.

**What it costs.** The card has to be positioned by hand per target, so a future
layout change can leave a note in an awkward corner; the fallbacks (top-right,
clamped, marker dropped) keep it readable but not pretty. The heat hold is a
server-side special case in the strike path. Its blast radius is bounded: two
minutes, one account, no multiplier, no auto-vent, and the reward path is
unchanged. The guide also cannot force the player to stay on the step's section,
which is deliberate: a marker that follows the player is better than a lock.

## ADR-109 - The guide runs to the store, in actions

**Context.** The eight-note guide ended on the first blade roll. The vault,
runes, tech and store were never pointed at, so a new player learned the strike
loop and then had to discover the four systems that give the loop its next goal
without any help. The requirement was to extend the same text box through the
vault and equip-best flow, the cache, the rune shelf, the tech tree, the top-bar
utilities and the store, with every step optional and no forced purchase.

**Decision.** `TutorialController` now carries nineteen notes. After the first
roll it adds `KEEP THE BLADE` for the ceremony, then vault, equip-best and close,
then runes and a reading card about mastery and sockets, then tech and a reading
card about permanence, then the utility bank and the store. Reading cards carry
a `NEXT` key because there is no player action to watch; every other step
advances on a real event or a real tab change. The vault notes work because the
guide layer moved to `ZIndex 80`, above the vault overlay at 31 and the blocking
cards at 60-65, while the card itself keeps its own 22. The store note only
highlights the rail tab; it does not ask for a press and cannot charge anything.

Two steps exist because the loop has a beat the old list skipped. The first
cache is claimed after the first drone, and the crate ceremony must be dismissed
before the vault can be reached, so `COLLECT` is its own note and the cache note
targets the first occupied slot rather than slot 1.

**What it costs.** The first run is longer, about four extra minutes of reading
and taps. The guide now depends on more instance names across five views, and a
rename breaks the marker silently because the target resolves by name. The
nineteen-step table also makes a replay longer, which is why `SKIP` stays on
every card and the handbook replay is still one press.

## ADR-110 - The first onboarding cache is always the Scrap Cache

**Context.** The cache lesson asks the player to crack a cache and claim it. A
cache's rarity is rolled at drop, and a Prime carries a 2:45 crack timer. In
Studio the tutorial landed on a Prime and parked the next step behind a
countdown that no copy could shorten. A lesson about the tap should not be a
lesson about waiting.

**Decision.** `ProgressionService.addSalvageMeter` checks `guideSeen`. While it
is false, every drop is `SalvageConfig.Rarities.common`, the instant Scrap
Cache. Once the guide is finished or skipped, the normal weighted table returns.
The flag already existed for the guide latch and the one-time reward, so no new
profile field or migration was needed.

**What it costs.** A new player sees commons during the guide instead of a lucky
early Prime. A player who reads slowly can receive more than one forced common.
The rule is tied to a tutorial flag, so a replay on a finished account does not
get it, which is correct: a replay is not a first run.

## ADR-111 - An ascent can be inspected before it is affordable

**Context.** The top-bar ASCEND key used to refuse below the threshold with a
toast. A player deciding whether to save for the reset could not see the target
or the payout without crossing it first, and the refusal read as a broken key
rather than a locked door.

**Decision.** `HudController.ascendHandler` always opens the confirmation sheet.
When the balance is short, the body prints the threshold and the current total,
and the affirmative key is painted through `Modals.confirm(..., lockedReason)`:
a slate plate, a locked label, no handler. When the balance is there, the body
prints the cores and the key is live. The server still checks
`pendingCores(state)`, so a modified client cannot ascend for free.

**What it costs.** The sheet now has a state that cannot act, which is one more
thing to keep honest as the ascend economy changes. The locked face carries the
threshold rather than the shortfall, because a one-billion target read as
"NEED 1000.00M" when subtracted from a small balance. The shortfall lives in the
body, where there is room for it.

## ADR-112 - A hint waits for an empty toast rail

**Context.** Five contextual decisions can open at once: an ascent, a daily, a
claimable cache, an empty rune socket and a new drone rung. On the first pass
they were pushed from the same payload as the guide's completion reward. The
rail holds two toasts, so the third push evicted the first, and the daily hint
was the one that vanished. A hint that removes a receipt is worse than no hint.

**Decision.** `Nudges.luau` owns the contextual layer. It starts muted, because
the guide is already pointing at the same controls. An edge is only consumed
when the line can actually be shown: not paused, at least three seconds since
the last nudge, and `Notifications.count() == 0`. Gates keep their latch open
while they wait, so a daily that was ready during the guide still speaks after
it. The drone line names the best rung in reach and marks the lower rungs as
covered; the line does not repeat when Aether is spent and earned again. Tab
glows stay in `Sections.refreshTabBadges` because they re-evaluate with the
layout, and the ascent and daily buttons keep their breathing strokes in
`HudController.step`. Expedition completion gets a receipt in `Main.onFeedEvent`
because it is a payout, not a standing state.

**What it costs.** A hint can be delayed by a busy feed, and a state that opens
and closes before its turn is lost. That is the intended trade: a receipt is
always more important than a reminder. The nudge layer also depends on the toast
module exposing a count, which is now part of that module's small public surface.

## ADR-113 - Four samples leave the kit, and the strike goes back

**Context.** The strike was rebuilt in `df0474b` from `impact_explosion_03` to
`snap.mp3`, and the rest of the kit leaned on `snap`, `hit`, `metal` and
`impact_water` for every body, ring and air layer. A play pass rejected all four
by ear: the dry block, the body blow, the steel ring and the splash. The strike
that shipped before that commit was the one the player remembered as right.

**Decision.** `Sfx.luau` now uses three samples: `electronicpingshort`,
`clickfast` and `impact_explosion_03`. The four rejected ids are gone from the
source, not muted behind a flag. `Sfx.strike` is restored to the pre-`df0474b`
mix: the ping body plus `impact` at 2.55x, with the sweet-spot pings unchanged.
Every other cue was re-voiced on the three remaining samples, using the impact
as the low body, the click as the transient and the ping as the metal. Vent,
overheat and burnout lost their water layer and now read through the ping and
the click; melt keeps a falling tick over a low impact.

**What it costs.** The kit has less timbral range. There is no air layer left,
so a vent is a falling ping rather than steam, and a crate break is a click over
a body instead of a wooden crack. The upside is a coherent palette a player can
learn, and the strike is the exact sound that was approved. The old ids remain
in the historical ADRs and build logs because those entries record what was
tried, not what ships.

## ADR-114 - A crit is a base chance, and a flash is the whole screen

**Context.** The crit ring only fired when a blade rolled a crit variant or a
rune, salvage set or tech node supplied crit chance. A fresh account starts at
zero, so the gold circle the crit is built around was effectively a late-game
effect. Separately, `Vfx.flash` painted inside the game canvas. The canvas is
measured to the game area, so the wash stopped at the letterbox on a narrow
window, sat under the crate ceremony, and never reached the top bar. Both the
crit yellow and the forge white read as partial rectangles rather than screen
events.

**Decision.** `Config.BaseCritChance` is `0.05`, and `TechTreeConfig.compute`
seeds `critChance` with it. The tech node, runes, salvage sets and variants add
on top of the same total. The `Vfx.flash` wash is no longer a child of the
canvas: `Vfx.init` builds a `VfxFlash` frame on the ScreenGui at `ZIndex 100`,
and every crit, forge, ascension and overheat wash is parented there. The
function also takes an optional `duration`, so a caller can match a short stage
beat without stacking half-second washes. The procedural crit ring starts at
180px and expands to roughly 3.2x, because the 420px sprite sheet is still
unuploaded and the old fallback was a 32px ripple.

**What it costs.** A 5% base crit is about +20% expected click yield at 5x, so
the curve is slightly richer than the design math in `game-design-math.md`. The
number is one constant in `Config` if that trade needs revisiting. The flash
layer is now above every panel by design, so a future full-screen overlay has to
accept a wash on top of it; that is the intended ordering for a flash.

## ADR-115 - The strike is a ping, and the flash gets its own screen

**Context.** The strike had been narrowed to one pitched
`impact_explosion_03` sample, and on listen the click was still a thud with a
blast tail. The ping that made the original strike readable had been buried under
it. Separately, `Vfx.flash` moved to a frame on the game ScreenGui, but the game
ScreenGui is measured to the game area: it sets `IgnoreGuiInset = false`, so on a
1280x720 window the screen is 1212x520 inside a 1212x578 viewport. Every wash
therefore left a 58px strip of untouched screen at the top, which is exactly what
"the flash does not cover the whole screen" looks like. The forge's white pop was
worse: it was still `flashViewport`, a frame clipped to the 3D stage.

**Decision.** `impact_explosion_03` is gone from the game. The strike is now one
purpose-built metal ping, rendered from six inharmonic plate modes plus a 10ms
hammer transient, with the band answer the same instrument a fourth up and the
crit an octave above it. Four samples were rendered and uploaded to the account
that owns the place: `STRIKE`, `BAND`, `CRIT`, `ANVIL`. `PING` and `CLICK` stay as
the client assets that carry melody and interface, so the kit is two families
instead of one palette stretched over every verb.

The wash lives on `VfxScreen`: a dedicated `ScreenGui` at `DisplayOrder 500` with
`IgnoreGuiInset = true`, holding one `VfxFlash` frame. That covers the raw
viewport including the top bar and lands above every panel and the crate ceremony.
`Vfx.flash` recycles three wash frames round-robin instead of creating a frame per
call, and it rebuilds the layer lazily if `init` ran before the PlayerGui existed.
`Vfx.init` adopts an existing layer instead of creating a second one.

`ForgeView` no longer owns a stage-local wash. `flashViewport` became
`screenFlash`, which forwards to `Vfx.flash`, so the strike pulse, the overdrive
open, the forge result and the crate reveal all paint on the same screen layer.

**What it costs.** Four uploaded audio assets are now part of the build, so a
fresh place needs them published with the account. Per-click washes are full
screen, so their peaks were lowered (0.15 white, 0.22 gold) to keep a ten-click
streak from strobing. A wash above every panel is deliberate, and any future
full-screen overlay has to accept being washed over.

## ADR-116 - One pool per sample, a chord on the green bar, and a real screen shake

**Context.** The sound kit shared 24 `Sound` instances and rewrote `SoundId` on
every cue. Reassigning `SoundId` invalidates the decoder buffer attached to that
instance, so a click could start a frame or more after the press while the new
asset resolved. That is the delay the forge click had. Separately, the sweet spot
answered with the same sample as an ordinary hit, only pitched up, so the reward
for precision was a slightly higher version of the normal click. And the only
shake on a strike was a 4px jitter on the clipped blade viewport, which reads as
the stage rattling rather than the screen taking a hit.

**Decision.** `Sfx` now owns one pool per sample, sized per cue
(`STRIKE` 10, `SWEET` 5, `CRIT` 3, `ANVIL` 6, `PING` 6, `CLICK` 6). The
`SoundId` is set once at creation, never again, and `Sfx.preload` warms every
pool through `ContentProvider:PreloadAsync` during boot. `play` picks the next
slot from that sample's pool, so `:Play()` starts on the press frame.

The green bar gets its own hit: a fifth-stacked metal chord with a low thump and a
short glint, uploaded as `SWEET` (97522852807133). It is a different sound, not a
louder one, and it lifts two semitones per in-band streak point so a run builds.

`Vfx.shakeScreen` shakes the canvas, which every panel is a child of, so a strike
moves the HUD instead of only the blade. The viewport shake stays moderate because
the viewport is full-bleed inside a clipped frame. Base magnitudes: 7 design px
on a normal click, 9 on a band hit, 11 on a crit, 15 on a forge result and 8 on a
crate landing.

**What it costs.** Thirty-six `Sound` instances exist from boot, which is more
resident audio than the old shared pool, but every one holds a decoded buffer that
is already being played. The screen shake moves the whole canvas, so any code that
reads `AbsolutePosition` during a shake sees the displaced value; nothing in the
client keys off that mid-frame.

## ADR-117 - The paid multiplier stacks forever, its clock never passes an hour

**Context.** Instant Overdrive was a flat 3x for fifteen minutes. A consumable
that replaces its own value cannot be bought twice in a row: a second purchase
while the first is live only overwrote the clock, so the store asked the player
to wait before giving it money again. The multiplier is the part that should
compound; the clock is the part that should not.

**Decision.** `overdriveStacks` is a saved integer. `globalMultiplier`
multiplies by `OverdriveMultiplier * max(1, stacks)` while `overdriveUntil`
is in the future. Every grant adds a stack and sets `overdriveUntil = now +
min(OverdriveSeconds, OverdriveMaxSeconds)`, which is one hour. Duration is a
hard ceiling, not an extension: a recharge with forty minutes left trades those
minutes for another stack. Charges are never spent, so the multiplier survives
expiration; a player with thirty charges who lets the hour lapse keeps x90 and
only needs one more charge to run it again.

The HUD chip prints the live product from `paidBoostMult`, which the server
computes: x6 with a 2x pass and one charge, x12 with two, x90 at thirty. The
client never derives the multiplier from a count it cannot see.

Storefront copy names which half stacks. Instant Overdrive: "Multiplier stacks
infinitely, and with 2x Star-Matter. Duration does not stack: each charge resets
the hour." 2x Star-Matter and Eternal Forge: "Stacks with every boost; it does
not add to their duration." Instant Overdrive shares the 176px hero row and the
gold ribbon treatment with the Starter Forge Pack, tagged `STACKABLE` instead
of `FIRST BUY`, so the repeatable offer looks repeatable at a glance.

**What it costs.** There is no cap on the multiplier, so one account can print an
arbitrarily large number for an hour. That is the offer, but the economy has to
treat the top end as unbounded; `overdriveStacks` is the only saved integer
that maps directly to income, and it is the first field to check if a leaderboard
ever looks wrong. The count is monotonic, so a refund is a manual data edit.

## ADR-118 - The scroll hint gets its own strip under the list

**Context.** The store is two columns of tall cards and its scroll rect ended at
the panel edge. A 4px scrollbar was the only signal that more rows existed, and
players stopped at the first screen, assuming the visible rows were the whole
store. A bottom pill is the standard affordance, but overlaying it on the list
would cover a row's buy button.

**Decision.** The panel reserves a 28px footer strip. `Sections.SCROLL_INSET_Y`
shortens the scroll rect in both `init` and `layout`, and `ScrollHint` is
anchored to the panel bottom inside that strip. It is a gold pill reading
`SCROLL DOWN`, shown only when `AbsoluteCanvasSize.Y - AbsoluteSize.Y > 8`
and hidden once the player is within 6px of the end. It listens to canvas size,
canvas position and frame size, so it also appears on any other overflowing
section rather than being store-only.

The first implementation subtracted `CanvasSize.Y`, which is a `UDim`, from a
pixel height. That error aborted `Sections.init` and took the whole client boot
with it: no `QF_Dev` seam, no state sync. The check now uses
`AbsoluteCanvasSize`.

**What it costs.** Every row section loses 28px of list height whether or not it
overflows. The rows are already sized to the taller column, so the visible cost
is padding; the benefit is that the hint can never sit on a button. The pill is a
`Frame`, not a button, so it never captures input.

## ADR-119 - The shelf is a catalog, and the paid clock owns the countdown

**Context.** The first store refresh gave every offer the same plate with a
taller variant, floated a gold ribbon under the text, and printed an owned pass
in the same solid emerald as a live price. Two columns of cards ended unevenly,
the fold cut a row in half with a yellow pill sitting on its buy button, and the
shelf read as a list of keys rather than a store. Separately, the HUD chip
counted down to the first boost to expire, so an Instant Overdrive bought under
the one-hour welcome boost still read the welcome clock and looked like it had
not applied.

**Decision.** The shelf is a catalog with one card system and two heights.

- Passes are gold (permanent), boosts are aether (timed), and the action plate
  is emerald on every row. Category colour is only allowed on the rail, the tag,
  the halo and the border; it never becomes the button.
- Group headers are lane signs: name on the left, count on the right, one
  hairline under both. The count sits 12px in from the edge so the scrollbar
  never crowds it.
- A standard row is 92 tall: a 13px category eyebrow (`INCOME`, `CLICKS`,
  `HEAT`, `EXPEDITION`), an 18px name, a two-line 14px sentence, a 60px badge
  and a 100x38 price plate.
- A featured row is 172 tall: a gold tag over a 26px name, a one-line store
  voice blurb, three 13px fact chips, a 112px badge with a soft halo and a
  124x48 plate. The tag and the chips carry the facts; the blurb carries the
  pitch, and neither repeats the other.
- An owned pass uses the kit's `equipped` state: a green tint and border, not a
  solid plate. A receipt is a state, not the loudest buy button on screen.
- The boosts column closes with a policy card, `NO SHORTCUTS`, not another
  offer. It states what the shelf refuses to sell and gives the shorter column
  a designed ending.
- The scroll footer holds a quiet `MORE BELOW` lane sign and a 36px wash that
  fades the cut row into the panel. The fade is what makes the fold read as a
  page edge instead of a clipped card.

The chip now counts down the paid clock whenever it is live. The multiplier is
still the product of the paid track and the welcome/Starter 2x, so the number is
honest, but the timer belongs to the boost the player buys and recharges. Taking
the minimum of the two made a fresh hour look inert.

**What it costs.** Three colours are in play (gold, aether, emerald), so the
accent has to stay structural or the shelf turns into a paint chart. The fade
covers the bottom 36px of the list, so a row cut there cannot be read as a whole
card; that is the point, and the lane sign sits below it. The policy card is not
a product and carries no price, so the group count stays at three. The ticker
fix changes what the chip counts down, not what it multiplies: a player watching
the clock will see the paid hour, and the multiplier still drops when the
shorter boost expires.

## ADR-120 - The store is a page with two shelves

**Context.** ADR-119 gave the store a card system, but it was still eight rows
poured into the generic two-column distributor. The distributor balanced the
columns by height, so the second shelf started wherever the first stopped; the
boosts sat under a 28px footer strip, and the store needed its own scroll hint
because the offers did not fit. Every offer had the same left-to-right shape, so
a bundle and a consumable read as the same object. On an account that owns every
pass, five full-width green BOUGHT plates formed the loudest line on the page.

**Decision.** The store is a full-bleed page like the forge and the crate vault
(`page = true`, `ShopView.card()`), not a host section.

- One 618px card, 20px inset. A masthead (44px gold mark, 30px QUANTUM STORE,
  13px subtitle, a `NO CURRENCY PACKS` chip, one rule) sits above two shelves.
- The permanent shelf is five 246px cards across. The boost shelf is three 188px
  cards across. Both rows are placed by `ShopView.layout()` from the live content
  width, so a resize moves the cards instead of re-flowing the page.
- Every card uses the same 6px radius, 16px inset, 64px badge and full-width
  40px emerald plate. Category colour lives on the tag, the fact line, the halo
  and the border, never on the verb.
- VIP is the bundle: raised fill, gold border, gold halo, `BEST VALUE` tag. Its
  fact line is computed from the live pass prices (`R$ 236 SEPARATELY`).
- Instant Overdrive is the repeat purchase: raised fill, aether border and halo,
  `STACKABLE` tag. Its copy is `Each charge adds ×3 for one hour.` and the idle
  summary is `MULTIPLIER STACKS · CLOCK RESETS TO 1 HR`; a live charge replaces
  the summary with `LIVE ×N · nM LEFT`.
- Owned passes keep the kit's `equipped` plate and take a faint emerald border.
  VIP keeps its gold border, because the bundle's identity is more useful than
  its receipt. The pass shelf header prints `n / 5 OWNED`.
- Nothing scrolls. The store hides the section host, so the scroll footer that
  still serves fleet, runes, tech and stats is not part of this page.

**What it costs.** The card has a fixed 618px height, so the copy budget is part
of the design: three 14px lines on a pass card, one 14px line on a boost card.
`TextService:GetTextSize` measured every string at the narrowest card width
before the build; the longest boost pitch is 260px against a 343px band, and the
longest pass title is 127px against 187px. The two shelves share no automatic
layout, so adding a fourth boost is a geometry change, not a list append. The
store no longer has a scroll hint because it no longer has anything below the
fold; the hint remains for the row sections.

ADR-119's row geometry and group headers are superseded. Its HUD clock rule
stands: the rail-foot chip counts down the paid hour whenever it is live.

**Verification.** Studio, Client, 1212x578 viewport: the card is 1121x446 at
(83,66); five pass cards 210px wide at y=156; three boost cards 357px wide at
y=365; every `TextLabel.TextFits` is true; no badge/description overlap. The
dev account owns all five passes, so the shelf paints `BOUGHT` and `5 / 5 OWNED`.
Switching to fleet hides the store card and switching back restores it.
`selene src` is clean and `rojo build` succeeds.
