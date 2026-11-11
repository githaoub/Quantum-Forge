---
type: reference
status: live
updated: 2026-11-11
aliases:
  - code-map
tags:
  - code-map
  - architecture
---

# Code map

A working map of `src/`, written so a fresh session can find the right file
without reading 700 KB of Luau. Every path is relative to the repo root. If a
module is not listed here, it is either a leaf helper or generated.

## The shape in one paragraph

`default.project.json` maps `src/shared` to `ReplicatedStorage.Shared`,
`src/server` to `ServerScriptService.Server`, and `src/client` to
`StarterPlayer.StarterPlayerScripts.Client`. The server owns a `ProfileState`
per player, mutates it through service modules, and batches a `SyncPayload` to
the client at 10 Hz. The client mirrors the payload in `StateStore`, renders it
with pure view modules, and sends verbs back through one `Action` RemoteEvent.
Discrete moments (crit, vent, forged, ascend) use a separate `Event` remote.
Everything is code: no Studio-authored UI, no models, no marketplace assets
required.

## Boot order

Server, `src/server/Main.server.luau`:

1. `Net.init()` creates `Remotes/Action`, `StateSync`, `Event`, `RequestState`.
2. `MonetizationService.init()` connects MarketplaceService if it is available.
3. `DataManager.start()` starts session locking, autosave, offline grants.
4. Action handlers are registered (`click`, `vent`, `forge`, `crate`, `equip`,
   `salvage`, `reroll`, `setting`, `ascend`, `buyDrone`, `buyTech`, `dispatch`,
   `claim`, `crackCache`, `claimCache`, `buyPass`, `buyProduct`, `claimDaily`,
   `tradeRequest`, `tradeRespond`, `tradeOffer`, `tradeAccept`, `tradeDecline`).
5. `LobbyService.build()` constructs the Orbital Bridge.
6. On join, `DataManager.load` -> `settleExpedition` -> `grantStarterBoost` (once,
   latched by `starterBoostAt`) -> `starter` event, then the first payload.
7. A Heartbeat loop steps `ForgeService` (heat decay, auto-clicks, missions) and
   flushes dirty profiles every 10 seconds.

Client, `src/client/Main.client.luau`:

1. `UiKit.screen("QuantumForge")` creates the ScreenGui, the elastic canvas
   (`Layout.MIN_WIDTH` 1320, UIScale to fit) and the event sink.
2. `Vfx.init`, `SpriteFx.init`, `Notifications.init`, `Modals.init`.
3. `HudController.init`, `ForgeView.init`, then `CratesView.init` (the CRATES page
   card), then `Sections.init(canvas, ForgeView.card(), { crates = ... })`,
   `OrbitalLobby.init`.
4. `InventoryModal`, `CodexView`, `LeaderboardView`, `TradeView`,
   `HandbookView`, `DailyView`, `TutorialController`, `FeedbackView`.
5. `StateStore.init()` last: it links the remotes, requests the first state, and
   starts the sync/event subscriptions. Nothing above this point may yield on a
   remote.

## Shared modules (`src/shared`)

| file | owns | change it when |
| --- | --- | --- |
| `Config.luau` | Every tunable: heat rates, sweet spot, vent, economy, retention, ascension threshold, `BaseDroneYield` fallback, the progress pricing curve (`ProgressReference`, `ProgressExponent`, `ProgressCap`, `progressScale`), `StarterBoostSeconds`, and `DailyTrack` (seven reward records). | Balancing the core loop or how hard the account scales its sinks. |
| `Types.luau` | `ProfileState`, `SyncPayload`, `FeedEvent`, `BladeInstance`, `InvEntry`, `Settings`, `DailyReward`, `CrateQuote`. The network contract. | Any new persisted or synced field. Add both sides in the same pass. |
| `BladeRegistry.luau` | 50 blade patterns: the 25 hand-authored ones plus one generated blade per shape per tier (25 more), built deterministically at require time so client and server agree. `get`, `list`, `nextUnowned`. | Adding art or changing a blade's identity. Prices are no longer here; see `ForgeConfig`. |
| `ForgeConfig.luau` | Five crate records (`Tiers`, each with `id`/`short`/`blurb`/`weights`/`accent`/`shape`/`pity`/`cost`/`unlock`), plus `crate`, `tierFor`, `tierAt`, `crateUnlocked`, `odds`, `pityWeights`, the variant table, reroll costs, salvage values, `power()`, `rollCost(tier, rolls, scale?, income?)`, `bulkRollCost(tier, rolls, count, ...)` and `floorStrikes` (18 per crate rung). | Tuning RNG, variants, duplicate economy, a crate's odds or the roll price curve. The account multiplier and income are passed in by the server; the module is shared. |
| `ModifierConfig.luau` | The four modifier axes (13 elements, 8 grades, 20 prefixes at 30%, 20 suffixes at 22%), `roll()`, `power()`, `bonus()`, `condition()`, `displayName()`, and the derived 32-band quality ladder (`qualityId`, `qualityOf`, `qualityLadder`). 5,733,000 catalogue combinations. | Adding an element, grade or affix, or moving the quality thresholds. Never add a second multiplier here: `power` is the product the copy already carries. |
| `TechTreeConfig.luau` | Eight prestige nodes and `compute()`, the single stat derivation. | Adding a tech node or a stat. |
| `RuneConfig.luau` | Mastery thresholds, socket counts, the twelve runes and `sum()`. | Rune balance or mastery pacing. |
| `SalvageConfig.luau` | Cache rarities, crack clocks, reward tables, twelve sigils in four sets, `bonus()`. | Cache drops or codex bonuses. |
| `ExpeditionConfig.luau` | Mission squads, durations, payouts. | Adding or rebalancing a mission. |
| `DroneRegistry.luau` | The five drone rungs (cost, growth, yield, unlock gate, hull and glow), `cost(tier, owned, scale?)`, `bulkCost(tier, owned, count, scale?)`, `unlocked`, `next`, `bestUnlocked`, `SaneMax`. | Adding a rung or moving a price. Both the server and the Fleet tab read it; the account multiplier is passed in, never read here. |
| `MonetizationConfig.luau` | Pass and product placeholders. All ids are `0`. | After the Creator Dashboard items exist. |
| `AssetManifest.luau` | Generated ids for UiArt, GamepassIcons, currency art (`CurrencyArt.sm/as/qc`), Vfx sheets, blade meshes, thumb sizes, plus the third-party blocks `LihFolkArt` / `LihFolkSky` with `LIHFOLK_EDGE = 420`, `hasSkybox()` and `lihfolkArt()`. | Icons and meshes only via `scripts/upload_assets.py`; currency only via `scripts/upload_currency.py`; LihFolk only via `scripts/upload_lihfolk.py`; never by hand. |
| `Remotes.luau` | Typed remote accessors with timeouts. | A new remote name. |
| `NumberUtil.luau` | Suffix formatting (`1.2K`, `3.4M`), safe arithmetic, multipliers. | A new display format. |

## Server modules (`src/server`)

| file | owns | change it when |
| --- | --- | --- |
| `Main.server.luau` | Boot, the action registry, Heartbeat. | Adding a verb or changing boot order. |
| `Net.luau` | Remote creation, `onAction`, `onRequest`, payload provider, event send. | The transport changes. |
| `DataManager.luau` | Save schema (currently 7), defaults, sanitisers (including `sanitiseFleet`, `sanitiseCodex`, `forgeCrate` and `starterBoostAt`), session lock, autosave, offline grant, `markDirty`, `get`. | A persisted field is added or migrated. |
| `ProgressionService.luau` | Derived stats, blade multiplier, `progressScale` / `dronePriceScale` / `runScale`, forge roll (crate + batch priced by `bulkRollCost`), `selectCrate`, equip, salvage, reroll, the drone fleet (`fleetTotal`, `droneCostFor`, `buyDrones`), tech, ascension, the daily track (`claimDaily`, seven records), `grantStarterBoost`, `addAether` / `addCores`, codex marking (`markCodex`, `syncCodex`), payload assembly (including `forgeCosts` per crate and `forgeCrate`). | Any economy rule or payload field. Every price the client sees is computed here, once, with the account multiplier applied. |
| `ForgeService.luau` | Heat physics, click validation and prediction reconcile, vent, crit, anomaly, auto-clicks, cache meter. `isLocked` gates strikes only; the crate roll is priced and gated elsewhere. | The strike loop or heat rules. |
| `LeaderboardService.luau` | Five OrderedDataStores, 8s read cache, 45s submit, name resolution, the parallel `QF_BestBlade_v1` copy record, mock preview fallback. | Adding a board or changing what a row carries. |
| `TradeService.luau` | Trade invites (20s, `request` / `respond` / `dropInvitesFor`), sessions (240s), offer validation and clamping, trade locks, atomic commit, vault-capacity check, and the `playersFor` roster with `busy` / `pending` / `trades` flags. | Trading rules, the invite handshake, or the privacy gate. |
| `MonetizationService.luau` | Receipt handling, pass checks, prompts. | Store behaviour. |
| `LobbyService.luau` | Orbital Bridge geometry, per-character auras, and `applySky`, which applies the LihFolk sky and its lighting recipe only when `Config.UseLihFolkSky` is on and all six faces resolve. | Lobby visuals. |
| `Funnel.luau` | `AnalyticsService` milestones, once per session. | A new funnel event. |
| `FeedbackStore.luau` | Player reports to their own DataStore. | The feedback form contract. |

## Client modules (`src/client`)

| file | owns | change it when |
| --- | --- | --- |
| `Main.client.luau` | Boot, event feed, settings application, 10 Hz smoothing loop, Spacebar input, teardown. | A new top-level system or feed event. |
| `Theme.luau` | Colours, type scale, spacing, radii, durations, `reducedMotion()`, `tween`, `fade`, `tierBackdrop`, `rarityColor`. | Any global style change. |
| `UiKit.luau` | Every widget: panel, label, button, action button, tab, bar, badge well, scroll, modal screen, dissolve. All UI goes through it. | A widget's behaviour or a new primitive. |
| `Layout.luau` | Design-space geometry for the full-width column: top bar, nav strip, content rect, tab and rate geometry, `init(width)` for the elastic canvas. | The screen split changes or the chrome gains a row. |
| `StateStore.luau` | Mirrored payload, pending-credit prediction, inventory fetch and cache, sync/event/inventory listeners, `setting()`. | The client needs a new stream. |
| `ForgeView.luau` | Anvil, full-height strike stage, `buildHud` (heat rail, streak pips, yield, prompt, full-bleed `StrikeButton`), blade viewport, roll column, crate viewport and scanner window, forge showcase, ambient embers. | The primary screen. |
| `HudController.luau` | Top bar: identity plate, three currency pills (PNG badge over a drawn fallback), seven 50x62 utility keys (vault, codex, boards, trade, notes, guide, setup) with vector icons over 13px labels, ASCEND and DAILY verbs with badges, the rate readout (over the nav strip) including the `x2 BOOST` chip, smoothing and the stall detector, `layout()`. Handler table: `vaultHandler` / `codexHandler` / `boardsHandler` / `tradeHandler` / `feedbackHandler` / `settingsHandler` / `dailyHandler`. | Top-bar layout or a new currency. Overlay keys are wired by `Main`, not here. |
| `ProfilePlate.luau` | Identity plate: `GetUserThumbnailAsync` head shot, display name, `@handle`, rank chip, progress to the next ascension from `Config.AscendThreshold`. Readout only. | The top-left identity block. |
| `CratePreview.luau` | The 3D crate models: five families (`crate` / `capsule` / `relic` / `core` / `vault`) with `styles()`, the drop/land/rattle/hold timeline, `play(tint, cues)`, `stop`, `destroy`. | Crate geometry or the roll timeline. |
| `CratesView.luau` | The CRATES section page: 300px pool rail, 268px model viewport, five-chip odds strip, result plate with batch/name/affixes/pity, single and ten roll keys, the reveal sequence, and the `onSelect` callback into `ForgeView`. Selecting a pool also sends the `crate` action. | The multi-crate surface, odds display, or the roll reveal. |
| `DailyView.luau` | The Daily Ritual: a seven-card track from `Config.DailyTrack`, streak head, claim key, claimed/today/next-up states, repaint on sync. | Daily rewards UI. |
| `Icons.luau` | Drawn vector header marks (vault, codex, boards, trade, feedback, guide, gear, ascend, daily). | A header icon. |
| `ModalShell.luau` | Dim, panel, banner, close, Escape, ZIndex for codex, boards and trade. Panels rebuild only their `body`. | A new full-screen panel. |
| `CodexView.luau` | Discovery index: 6 tabs, silhouettes, the 24-band quality grid, `setTab`. | Codex content. |
| `LeaderboardView.luau` | Five board tabs, currency rows, BEST BLADE rows with a 64px model, PREVIEW badge, `setBoard`, signature-gated repaint. | Board presentation. |
| `TradeView.luau` | Trade desk: partner rail with `ASK` / `WAIT` / `OFF`, two offer columns with live turntables, 208px picker grid on static thumbnails, shard stepper, accept/withdraw footer. Repaints are gated by `sessionKey`, `theirSignatureOf` and `inventorySignature`. A single local draft is pushed on every toggle. | Trading UI or the desk's sync cadence. |
| `Sections.luau` | The nav strip (elastic tabs and the rate band slot) plus the section host: two columns, banner and kicker per section, scroll restore, tab badges, `layout()`. Page sections (`forge`, `crates`) are registered as `page = true` and handed full-bleed cards through `Sections.init(canvas, forgeCard, pageCards)`; the host hides the row columns for them. | Adding a section, a page card, or a header control. |
| `InventoryModal.luau` | The blade vault: split view, banner, toolbar (scrap, owned, filters, sort), 4-column grid with live thumbnails, permanent inspector with a two-column stat drawer, the `EQUIP BEST` / `MELT MULTIPLE` batch strip, and the four drawer verbs (EQUIP, FAVORITE, REROLL, MELT). | Inventory UI or any vault action. `groupMeltable` is the one place the three melt exclusions are mirrored; `detailMeltTarget` picks a spare copy while REROLL acts on the copy on the turntable; the mode owns the card click, the confirm plate owns the melt. |
| `InventoryModel.luau` | Copy grouping by the six-axis key `id\|variant\|grade\|element\|prefix\|suffix`, meltable picks (equipped, favorite and last-copy guards), melt value, `displayName` / `condition`. Shared by the grid, the inspector and the batch bar. | What counts as "the same blade" or "may be melted". |
| `DroneView.luau` | Fleet stage, the five-rung ladder, drone purchase, expeditions, salvage band, codex band. `select` / `selected` preview a locked rung. | Fleet, missions, caches. |
| `RuneView.luau` | Mastery bar, socket rack, rune shelf. | Runes or sockets. |
| `TechTreeView.luau` | Tech nodes and ascend entry. | Tech tree UI. |
| `ShopView.luau` | Passes and products. | Store UI. |
| `Modals.luau` | Offline grant, the locked starter card (no close key, one `START FORGING`), generic confirm, settings sheet (each row is the switch). | A new blocking dialog. |
| `FeedbackView.luau` | Feedback form. | Feedback fields. |
| `Notifications.luau` | Toasts, throttling. | Toast behaviour. |
| `HandbookView.luau` | The 10-page forge handbook: rail nav, 1120 x 700 modal, hero band tiled with the LihFolk albedo, steps, fact cards, live art panels and tips. Every figure is read at paint time through `pages()`. | Handbook copy or a new page. Numbers must come from config, never be typed in. |
| `TutorialController.luau` | One first-join card whose CTA opens `HandbookView` at the loop page, `guideSeen` latch. The spotlight chain is gone. | Onboarding. |
| `BladePreview.luau` | Viewport framing (`framingOf` with fill and aim bias), turntable, orbit, glow flash, variant tint, and the static `thumbnail` path with `THUMB_YAW = 90 - AZIMUTH - 18` and full-white ambient. | How a blade is shown. The thumbnail pose is shared by the vault, codex, boards, handbook and both trade strips. |
| `BladeModelBuilder.luau` | Procedural blade recipes and mesh hot-swap. | Blade geometry. |
| `DroneModelBuilder.luau` | Per-rung procedural hull, `build(model, tierId)` and `mount(viewport, tierId, opts)`. | Drone geometry. |
| `ViewportOrbitController.luau` | Drag/orbit/idle motion for a viewport. Presses come from `Options.surface` when a control sits over the render; `handle.dragTravel` separates a tap from a drag. | Camera feel. |
| `StageBackdrop.luau` | The gradient wash behind a 3D stage: opaque base ramp, crossed gradient bands, accent shaft, vignette, optional settle plate; `setColors` re-tints in place. | The look of a stage or card art well. |
| `Vfx.luau` | Floaters, bursts, spark cones, shockwave rings, lightning, ambient embers, shake, flash. | Screen juice. |
| `SpriteFx.luau` | Layered sprite-sheet playback with tint. | Flipbook effects. |
| `Sfx.luau` | 24-slot sound pool and every cue; local mute. Two layers on the strike, three on the events that had no sound before (`crit`, `crateLand`, `crateShatter`); `rollTick` climbs a pentatonic ladder. | Audio coverage or mix. Read ADR-066 before adding a layer to a sound players already know. |
| `OrbitalLobby.luau` | Ambient lobby visuals on the client. | Lobby mood. |

## Data flow

```
click / action  ->  Main.server action handler
                ->  ForgeService or ProgressionService mutates ProfileState
                ->  DataManager.markDirty
                ->  Net payload provider (buildPayload) at 10 Hz
                ->  StateStore.current + onSync listeners
                ->  views repaint in place
```

Inventory is event-shaped, not tick-shaped:

```
forge / equip / salvage / salvageMany / reroll / ascend  ->  state.invVersion += 1
payload.invVersion changes  ->  StateStore fetches RequestState("inventory")
                            ->  onInventory -> InventoryModal rebuilds groups
```

Rules that keep this honest:

- The server is authoritative for every reward. The client predicts clicks only,
  through `StateStore.predictClick`, and reconciles on the next payload.
- A mutation that can change the copy list must bump `invVersion`
  (`ProgressionService.markInventory`). Missing that is a stale UI, not a sync
  bug.
- `equippedBlade` is the pattern id used by mastery and sockets. `equippedUid`
  is the exact copy. A Prismatic Rusted Cleaver shares mastery with a Standard
  one.
- `DataManager.get` may return `nil` in a probe or before load. Every handler
  checks it.

## Where to change common things

| want | file | note |
| --- | --- | --- |
| Strike yield or heat | `Config.luau` + `ForgeService.luau` | `ProgressionService.clickYield` is the one formula. |
| Blade multiplier | `BladeRegistry.luau` | Variant multiplier is applied by `ForgeConfig.power`. |
| Forge price or odds | `ForgeConfig.luau` | `Tiers`, `RarityWeights`, `Variants`, `rollCost`'s ramp. |
| How hard sinks scale with the account | `Config.luau` | `ProgressReference`, `ProgressExponent`, `ProgressCap`. Drones take the root of the same curve in `ProgressionService.dronePriceScale`. |
| Pity length | `ForgeConfig.luau` | `Tiers[].pity`. |
| Duplicate value | `ForgeConfig.luau` | `salvageValue`, `rerollCost`. |
| A drone rung, price or gate | `DroneRegistry.luau` | The server and the Fleet tab both read it; never re-price in a view. |
| A new persisted field | `Types.luau`, `DataManager.luau`, `ProgressionService.buildPayload` | Bump `SCHEMA_VERSION` when the shape changes. |
| A new action | `Main.server.luau` | Register with `Net.onAction`; validate every argument. |
| A new tab | `Sections.luau` | Add to `SECTIONS`; every view needs `init` and `destroy`. The tab row is sized from `Layout.TAB_COUNT`, which `Sections` sets at load. |
| A new currency pill | `HudController.luau` | The top row is width-locked; see the comment at `PILL_W`. |
| A new sound | `Sfx.luau` | Add a function, call it at the verb. Do not hardcode a new asset id without proving it loads, and do not add a layer to a sound players already know without listening to it (ADR-066). |
| A new fact in the vault drawer | `InventoryModal.paintInspector` | `addId` for what the copy is, `addPerf` for what it does. Ten rows fit at five per column; a sixth fact in one column will clip. |
| A new effect | `Vfx.luau` | Every effect must self-destroy and honour `setEnabled` / `reducedMotion`. |
| A new badge image | `AssetManifest.luau` via uploader | Upload `assetType: "Image"`, resolve with `rbxthumb://type=Asset`. |
| A third-party art drop | `scripts/upload_lihfolk.py`, then `AssetManifest.LihFolkArt` | Its own cache and its own manifest blocks, so the generated icon and currency ids cannot be overwritten. Check the pack licence before uploading. |
| A handbook page or a fact on one | `HandbookView.luau` | Add to `pages()`. Numbers come from config at paint time; a typed-in figure is a bug. |

## Conventions that are enforced

- `--!strict` on every module. `selene src/` must be 0/0/0 before a build.
- UI is built with `UiKit`, not raw `Instance.new`, except inside `UiKit` and
  module-owned custom widgets.
- Animation goes through `UiKit.tween` or `Theme.tween` so `reducedMotion()`
  collapses it. Never a bare `TweenService:Create` in a view.
- Connections are tracked with `UiKit.track` or disconnected in `destroy`.
  Views are mounted and destroyed on every tab switch; a leaked listener shows
  up as duplicate toasts after five minutes.
- Network sync is batched. Never send per-click state; predict locally and let
  the payload correct it.
- Minimum type sizes in design px: card titles and tabs 16-18, descriptions and
  stats at least 13, buttons 14-15 bold. Secondary copy uses
  `Theme.Color.textSecondary`.
- Player-facing strings use no em dashes. Use `·` or a plain hyphen.
- Offsets, prices, weights and clocks live in a config module, not in a view.

## Verification

```powershell
selene src/                 # 0 errors, 0 warnings, 0 parse errors
rojo build -o verify.rbxlx  # succeeds; the file is a test artefact
```

Live checks use the Studio MCP bridge. Typical recipe:

1. `list_roblox_studios` and pick the instance.
2. `start_stop_play` with `is_start = true`.
3. Wait about 27 seconds for the client to build.
4. `execute_luau` against `datamodel_type = "Client"` to inspect `AbsoluteRect`,
   label `TextFits`, `ImageLabel.IsLoaded`, or module state.
5. `get_console_output` for errors.

Known environment limits:

- `screen_capture` returns `null` on this Studio build *and still renders the
  capture*: pass a `capture_id` (`ScreenCapture_1`, `ScreenCapture_2`, ...) and the
  image arrives in the client even though the tool result is empty. Measurements
  are still the cheap route for geometry, but a visual claim can be backed by a
  capture; the forge-10 pass read six of them.
- Blade meshes currently return `User is not authorized to access Asset` in
  some sessions. The procedural fallback is the shipped path; the mesh path is
  a hot swap when the assets are authorized.
- 22 VFX sprite sheets are generated but unuploaded. `SpriteFx` falls back to
  `Vfx` when a sheet is missing.
- The API key lacks `game-pass:write` and `developer-product:write`, so the
  store items cannot be created from Open Cloud. All monetization ids are `0`.

## The vault

All `.md` files live in `incremental/`. Start at `incremental/README.md` for the
index, then this file, then `design-decisions.md` for the reasoning behind any
number that looks odd. `project-readme.md` is the player-facing and developer
overview; `game-design-math.md` is the derivation.
