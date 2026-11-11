---
type: build-log
status: done
updated: 2026-11-11
aliases:
  - build-log-forge-12
tags:
  - build-log
  - forge
---

# Forge 12 - crate, economy, modifiers, codex, boards, trade, and the currency art

Shipped 2026-11-11. The design record is `ADR-056` through `ADR-067` in
`design-decisions.md`; this file is the measured half.

The ticket was the feature-expansion and pacing pass: a real 3D crate for the
roll, an economy fix for the post-ascension price wall, modifier axes on every
copy, retention surfaces (codex, leaderboards, trading), drawn top-bar icons,
the QUALITY ladder, a larger blade catalogue, and the three custom currency
PNGs. It then picked up a second ticket: currency art in the HUD, BEST BLADE
rows with the real model, the 2D dais removed from under the crate, the purge
heat roll lock removed, and the roll price re-based.

A third ticket closed the pass: the trade desk rebuilt around a request and an
accept, a ten-page handbook replacing the spotlight tutorial, the LihFolk vault
surfaces uploaded and wired, and the thumbnail pose fixed across every surface
that shows a blade.

A fourth ticket opened it again for game feel: the sound kit gained the events it
was missing and lost the layers that made the strike worse, the vault inspector
drawer was split in two so its last three facts became visible, and the REROLL
verb the handbook had been quoting a price for finally got a button.

Everything below was checked against a live playtest on place `102663811434617`
with the Studio seam (`QF_Dev`) and the state remote, because pointer input is
not synthesised on this build.

---

## 1. The crate

`src/client/CratePreview.luau` builds a 4 x 3.2 x 4 stud crate from 15 parts and
5 neon seams, mounts it in a transparent 300 x 300 `ViewportFrame`, and runs one
timeline: drop, land with a squash, six rattle beats, hold. The caller subscribes
to `onLanded` / `onBeat` / `onReady`, so the tick sounds and screen shake land on
the frames the model actually moves. `moveTo` cancels the in-flight tween, so a
`stop` mid-rattle cannot leave the crate hovering into the next roll.

The stage under it is now the viewport and nothing else. It used to carry a
sunken dais with three concentric halos, re-tinted to the banner. At Cosmic the
tier colour is `122,255,196`, so the report saw it as "a 2D green circle behind
the crate". Live inspection of `CrateStage` after the change: 21 descendants,
all of them `CrateViewport` / `CrateWorld` / `ForgeCrate` / parts / camera /
offset value. No dais, no halos.

## 2. The roll price

`Config.runScale(run, lifetime)` blends the account progress tax by the run's
share of lifetime, and `bannerTier` reads `runStarMatter`. `ForgeConfig.rollCost`
now takes an optional `income` and floors the banner price at
`clickYield * 18` (`ForgeConfig.RollIncomeStrikes`).

| profile | click yield | banner price | charged |
| --- | ---: | ---: | ---: |
| before | 16.1B | 288,687,958 | 288,687,958 |
| after | 16.1B | 288,687,958 | 290,105,676,000 |

The deduction existed before; the price was eighteen thousandths of one click, so
three rolls moved the balance less than the income arriving while the crate fell.
`Main.server` now pushes a fresh payload on the frame a roll succeeds, so the
number moves when the roll does.

## 3. Modifier axes and the quality ladder

`src/shared/ModifierConfig.luau` owns the third through sixth roll axes: 8
elements, 6 grades, 12 prefixes at 30%, 12 suffixes at 22%. Empty axes are
optional on the wire and multiply by 1, so a schema-6 copy does not gain power
retroactively.

`ForgeConfig.powerCopy` / `salvageCopy` take the whole copy, and every consumer
(vault, equip-best, boards, trade) goes through them, so ranking cannot disagree.

The QUALITY tab is derived, not stored: `grade + step`, where step is the
within-family score against `1.00 / 1.20 / 1.45 / 1.72`, four pips and a true
multiplier. Twenty-four bands, from `Chipped-` to `Transcendent++`. The codex
total is 117 keys and the header reads `2.03M COMBINATIONS` after the catalogue
doubled.

## 4. Codex, boards, trading

- Codex: six tabs (`BLADES`, `QUALITY`, `VARIANTS`, `ELEMENTS`, `GRADES`,
  `AFFIXES`), silhouettes for undiscovered cells, `quality:<id>` discoveries
  marked at forge time. Live: `37 / 117 DISCOVERED`.
- Leaderboards: five boards, 20 rows, 8s read cache, 45s submit. If
  `GetSortedAsync` fails, the service serves seeded rows flagged `mock`, and the
  header says PREVIEW. BEST BLADE reads a parallel `QF_BestBlade_v1` record per
  player and paints a 64px model, the affixed name, the condition, the variant
  chip and the exact multiplier. Your own row uses the live copy, so it renders
  before the first submit.
- Trading: 240s sessions, 8 blades and shards a side, offered uids locked
  against melt and reroll, both accepts cleared on any change, vault capacity
  checked before the first mutation.
- HUD: four drawn peers (`GUIDE`, `FEEDBACK`, `CODEX`, `BOARDS`) at 69/77/69/69
  px, none clipped, right edge flush with the bar.

## 5. Currency art

Three PNGs with the chroma field removed, uploaded as Open Cloud `Image` assets
by `scripts/upload_currency.py`:

| key | file | id |
| --- | --- | --- |
| `sm` | `star_matter.png` | `99249193231278` |
| `as` | `aether.png` | `78550197900852` |
| `qc` | `cores.png` | `99765313424130` |

`AssetManifest.CurrencyArt` holds the ids; `currencyArt` resolves them through
the thumbnail CDN at 150 x 150. The HUD keeps the drawn badge until
`ContentProvider:PreloadAsync` confirms the bitmap, then fades the PNG in and the
plate, stroke and glyph out. Live: all three `ImageLabel`s reported
`loaded=true`, `ImageTransparency=0`, and the capture shows the shard, flask and
core on the navy pills with no plate behind them.

## 6. The trading desk

`TradeService` was rebuilt around an invite instead of a session (ADR-061).
`request` writes an invite with a 20 second deadline and returns; `respond`
creates the session on accept and emits `tradeStarted` to both clients. Every
exit path drops the invite through `dropInvitesFor`, so a target can hold at most
one invite per sender, and a declined or expired card cannot be accepted later.

`playersFor` now carries three flags per forger: `busy` (in a session), `pending`
(has an invite out to you) and `trades` (your own settings). The rail paints
`ASK`, `WAIT` or `OFF` from that payload, so the state is honest before any round
trip.

`TradeView` was rewritten to match the brief:

- Two offer columns under `YOUR OFFER` and `THEIR OFFER`. Rows are full column
  width, 381 x 64 design px, because a 60px thumbnail beside a 100px name
  truncated every title in the first build.
- Your offer rows are the click target and carry a tick. Toggling pushes the
  draft immediately through `tradeOffer`; the server clamps, clears both accept
  flags and sets the trade locks.
- Both offer strips run live turntables (`BladePreview.mount`), tinted by
  variant. The picker grid stays on `thumbnail`, counted at twenty spinners
  against five.
- The picker is 208px tall: two rows of 100 with an 8px gap, no vertical
  padding, because 4px of padding clipped the bottom row by a hairline.
- Footer is `ACCEPT THE TRADE` / `WITHDRAW`, with a 3 second `acceptArmed` window
  so a double tap cannot accept on the frame the desk opens.
- The shard stepper clamps to `shardsOwned` and steps by 100.

Repaints are gated by signatures (ADR-062): `sessionKey` rebuilds the desk,
`theirSignatureOf(state)` rebuilds the partner strip, `inventorySignature()`
rebuilds the picker. The poll runs at 0.35s.

`Modals.tradeRequest` is a 470 x 304 card: a plaque with the sender's name at
28px black, one line of body copy, a local countdown that flips to `EXPIRED` in
danger red, and `DECLINE` / `ACCEPT`. The server owns the real deadline; the
client only stops showing a button that would be refused.

The privacy row is the fourth switch in the settings sheet, which now fits four
rows at 400px with no overflow. `settings.trades` defaults on for new profiles,
defaults on in `sanitiseSettings` for legacy saves, and is read by both the
server gate and the roster flag.

## 7. LihFolk

Seven images were staged, hashed and uploaded through `scripts/upload_lihfolk.py`
against creator `user:1416845247`:

| Key | Asset id |
| --- | --- |
| `sky_bk` | 127948154052495 |
| `sky_dn` | 127509473987572 |
| `sky_ft` | 93704348378287 |
| `sky_lf` | 114213263580640 |
| `sky_rt` | 76004822288802 |
| `sky_up` | 71420941898331 |
| `band` | 102992694705193 |

The uploader reuses `upload_assets.py` for the multipart and commit dance, keeps
its own cache, and rewrites only the `LihFolkArt` / `LihFolkSky` blocks in
`AssetManifest`, so the generated icon and currency ids cannot be clobbered.

One surface shipped: the gold albedo tiles at 180px behind the handbook hero band
at 50% transparency, under a scrim, so it reads as texture rather than artwork.
The handbook rail credits `SKY + METAL: LIHFOLK` at the bottom.

The sky is mapped and off. Six faces at 1024 x 1024 preload `Success` as Image
ids and the renderer draws a black dome; uploaded as Decal ids the engine logs
`ContentId ... failed due to: Asset type does not match requested type` for every
face and falls back to the default sky. Both routes were tested live, including a
temporary `Sky` in Edit mode and a bound camera pointed at the dome. The pack's
licence allows use in an experience and private upload, not redistribution, which
the three-house-art rule already respects; the sky sits behind
`Config.UseLihFolkSky` so the flip is one line when a face renders.

## 8. The handbook

`HandbookView` is 10 pages in a 1120 x 700 modal: a 232px rail on the left, a
604px content column with a 108px hero band, three numbered steps, four fact
cards, a live art panel at 360px and a tip strip at the bottom.

Pages: loop, heat, crate, variants, quality, vault, fleet, runes, ascend, trade.
`PREV` / `NEXT` sit at the footer with the page label between them; the rail rows
are direct jumps. The `GUIDE` key in the top bar and the welcome card both open
it, the welcome card at the loop page.

Every number is read at paint time through `pages()`, from the same configs the
game runs on: `Config`, `ForgeConfig`, `ModifierConfig`, `RuneConfig`,
`TechTreeConfig` and the live `StateStore`. The art panels use the real seam:
the loop page mounts the equipped blade, the vault page calls
`ForgeConfig.salvageCopy` on the equipped copy, the heat page reads `state.heat`
for the needle, and the trade page draws the same two-column exchange the desk
uses.

Copy fixes this pass, all against config:

- The climb step counts strikes against decay instead of quoting a strike count
  that a slow tap never reaches.
- The variant page said "overcooked" and "two percent of rolls" for a pair that
  is 4 in 100.
- The quality page's fourth fact is `TOP BAND / MYTHIC++` instead of a sentence
  in a number slot.
- Bar tracks moved from `panelSunken` to `void` plus a hairline outline. Twelve
  values of contrast is not a track; empty bars read as stray stubs before this.
- The heat gauge got a `CURRENT HEAT` label so the big number is not a riddle.

`TutorialController` is now a single welcome card with a `guideSeen` latch, and
its CTA opens the handbook. The old spotlight chain is gone.

## 9. Thumbnails

Every static thumbnail in the game was a hairline, and the cause was geometry
(ADR-065). `thumbnail` baked the hero yaw of 25 degrees into a mesh whose flat
faces local +X, against a camera 26 degrees off -Z, so the flat stayed edge-on
and a 69px card drew one bright edge.

`THUMB_YAW = 90 - AZIMUTH - 18` puts the flat on the camera with a three-quarter
turn. Facing the camera exposed the second problem: dark steel on a `void` plate
is invisible at 28px regardless of angle, so `Ambient` runs at full white with a
fixed key direction. The vault grid, codex, boards, handbook and both trade
strips all use the same function and all improved together.

Measured: the vault card stage is 69px and the blade fills 78% of it, the trade
offer stage is 34.5px, the trade picker 28.8px. Before the fix the projected
width at 69px was under a pixel; after it the face is the widest part of the
silhouette.

## 10. Game feel: the strike, the vault drawer and the missing verb

This pass started from a pasted note (`video-07-game-feel-ui-audio.md`) that
prescribed four things: a layout rework, a three-layer sound kit, a longer roll
sequence and two economy changes. The layout and the roll had shipped in earlier
passes, the two economy changes contradicted ADRs written after testing the
alternative, and the note itself ended with an instruction to build a file that
does not exist. It was rewritten as a ledger of what is shipped, what is
superseded and what was deliberately not copied, then the two real gaps were
built.

**The sound kit was layered, and the strike was reverted the same day.** The
experiment is recorded in ADR-066 because the failure is the useful part:
`hit.wav` is a body blow, so the click lost its metal and gained a wooden thump,
and the sustained tail of the explosion bed smeared the transient. The strike,
the roll, the fanfare and the streak gate are back to the mixes that were tuned
against play. What stayed are the events that had no sound at all: `crit` (the
server event fired a white flash and a floater into silence), `crateLand` (the
heaviest object in the game landed on a ping), `crateShatter` (phase three
borrowed the fanfare), the vent's air layer, and a `rollTick` that climbs a
pentatonic ladder instead of a drifting ratio.

**The vault inspector printed three facts nobody could see.** Ten stat rows at
20px need 200px; the drawer is 132px, so COOLING, MASTERY and SOCKETS sat below
the clip line on every copy - including the two rune facts that explain the rune
lock. The drawer is now two columns split by meaning (identity on the left at
176px, performance on the right at 136px, 24px gutter), five rows each, ending
88px above the floor. Widths are measured, not guessed: the left column has to
hold `of the Colossus` at 98px at the 13px rung.

Two traps, both caught in the first capture: `statRow`'s 58/42 split is right for
a 336px row and wrong for a 136px one, so it takes a fraction now; and the well's
`UIListLayout` laid both columns out at the same x, which drew the drawer as a
pile of overlapping text until it was removed.

**REROLL had a price and no button.** `ProgressionService.rerollVariant` shipped
with the Salvage rack, the handbook quotes `12 + 10 * (tier - 1)` Scrap, and no
client code ever called it: the sink for duplicate blades was a server function
nobody could reach. It is now the fourth drawer key, targets the copy on the
turntable, greys out under cost, and confirms with the price plus the fact that
the roll can come back worse.

Live walk: five rerolls spent 160 Scrap, the variant went `standard` ->
`overclocked`, the card badge and tint repainted, the multiplier moved 45.11K ->
72.18K, the melt quote +30 -> +67, and the drawer reprinted CRIT +0% -> +5% and
VARIANT x1.00 -> x1.60.

## 11. Verification

- `selene src/` -> 0 errors, 0 warnings, 0 parse errors.
- `rojo build -o verify.rbxlx` -> built clean, repeatedly.
- Live: roll accepted while `locked=true` and the gauge read `OVERHEATED 3.0s`
  (the purge heat bug); inventory moved 18 -> 19; the roll button read
  `298.11B SM` against `770.33T`.
- Live: BEST BLADE row `entangle_scythe`, `Entangle Scythe of Dawn`,
  `PRISMATIC`, `Chipped Frost`, `x2.30B`.
- Live: QUALITY grid, 24 cells, name / multiplier / step / pips all inside the
  132px card at `UIScale`.
- Live: `CrateStage` has no dais or halo descendants.
- Live: trade desk at 593 x 446 design px, picker 208 tall, both offer strips
  spinning, footer `ACCEPT THE TRADE` / `WITHDRAW`, status `PREVIEW has
  accepted. Your move.`
- Live: invite card at 470 x 304, countdown ran to expiry and closed itself.
- Live: settings sheet, four rows including `ALLOW TRADE REQUESTS`, no overflow
  at 400px.
- Live: all ten handbook pages captured; bar tracks, heat label, band texture and
  fact cards checked at 0.7194 scale.
- Live: vault grid blades read as swords at 69px after the thumbnail fix.
- Live: strike mix confirmed at runtime — `electronicpingshort` at 0.200/0.97,
  `impact_explosion_03` at 0.100/2.63, plus the two band pings; no `hit` layer.
- Live: vault drawer, two columns at 823 and 967 absolute (176 and 136 design px,
  24px gutter), five rows per column, last row 86px tall and ending above the
  well floor. No row overlaps its neighbour's value.
- Live: REROLL via the seam, five times; scrap spent, variant changed, drawer and
  card repainted.

## 12. Full-bleed layout: the screen is the app

The complaint was "our UI feels cramped", with the reference image as the target
and no black background. The right-hand panel was the first half of it: a 520px
tab column beside a forge card, on a 1440x720 canvas that fit a 2:1 window
exactly, floating on a `void` backdrop.

- `Layout.luau` rewritten. The side column is gone; one full-width column with a
  76px top bar at y=6, a 46px nav strip, and one content rect every section
  fills. Width is elastic: 720 design px of height, width from the viewport.
- `UiKit.screen` is full-bleed and returns the design width it measured, plus an
  `onResize` callback. The measurement is read from the ScreenGui, not from
  `ViewportSize - GetGuiInset`, because the inset reports zero while the native
  topbar is hidden and that is when the first measurement runs.
- `Sections.luau` replaces `SidePanel.luau`: the nav strip (tabs, rate band,
  codex/boards/feedback keys, vault, settings), the section host and the two
  columns. `Sections.layout()` repositions the chrome on a resize.
- `ProfilePlate.luau` is new: face, display name, `@handle`, rank chip and the
  progress bar to the next ascension, built from `GetUserThumbnailAsync` and
  `Config.AscendThreshold`.
- `HudController` rebuilt the bar: identity plate left, three pills, ASCEND /
  DAILY / GUIDE right. The brand banner, and the three 96-108px overlay buttons,
  are gone — the overlays moved to the nav as icon keys.
- `ForgeView.init` takes an explicit height, and `ForgeView.layout()` re-places
  the card on resize.
- `Theme` gained `sky` / `skyLift` / `skyDeep`; the wallpaper is a three-stop
  navy gradient painted on the ScreenGui, so it also covers a letterbox after a
  resize.

Measured live at 1212 x 517 physical (1685 x 720 design, UIScale 0.7194):

- Canvas 0,0 1212x517; wallpaper 1212x517; no letterbox at boot after the
  play-window grow was picked up by the resize path.
- Top bar 7,4 1198x54; identity group 526 wide; actions at 933..1195.
- Nav 7..1205; tabs 168 design each (14..630 physical); rate band 888..1425
  design; keys at 1433 / 1577 / 1625 design.
- Section panel 7,100 1198x410; scroll 1172x329.
- Fleet: left column 583x414 (hero, strip, ladder, expedition), right 583x320
  (salvage, sigil codex); canvas 432 over a 329 view, so it scrolls.
- Store: left 430 tall with GAME PASSES over six cards; right 349 with BOOSTS &
  UTILITY over its cards; every header above its own rows.
- Runes: blade card left, RUNE SHELF and four runes right.
- Tech: header + three nodes left, four nodes right, canvas 528.
- `wired` verb: codex, boards, feedback, guide and trade all true.

Known trade-offs, recorded rather than hidden: the two-column split is judged by
eye at one width; the identity plate is a readout with no destination; and the
resize path was proven by the Studio play window growing, not by a user drag.

## 13. Balance: the fleet and the rarity column

The drone side of the curve was outrunning the click side. The fix is in the
registry: `DroneRegistry` yields fell by about 45%, per-rung growth rose by 0.035
(the ladder still pays to climb), and the gates moved to 32 / 110 / 320 / 800
lifetime Aether. `TechTreeConfig` gained `drone_lattice`: +12% fleet yield per
level, eight levels, cost 3 growth 1.85, so the fleet has its own long sink.

`ForgeConfig.RarityWeights` thinned to Scrap 55 / Forged 29 / Astral 13 / Void 2.4
/ Quantum 0.35. Each crate builds its column from that shape, so the chase is
longer in every pool, not only the starter one.

## 14. Five crates and the roll page

`ForgeConfig.Tiers` is now five `Tier` records: `id`, `short`, `name`, `blurb`,
`cost`, `unlock`, `pity`, `scrap`, `weights`, `accent`, `shape`. The ladder:

| crate | cost | unlock (lifetime SM) | pity | shape |
| --- | ---: | ---: | ---: | --- |
| Standard Forge Crate | 50 | 0 | 12 | crate |
| Void Capsule | 1,400 | 60,000 | 11 | capsule |
| Quantum Relic | 90,000 | 8,000,000 | 10 | relic |
| Celestial Core | 6,000,000 | 600,000,000 | 9 | core |
| Singularity Vault | 400,000,000 | 400,000,000,000 | 8 | vault |

> **Superseded.** These gates now read run Star-Matter, not lifetime, so an
> ascension re-opens the climb (ADR-090). The numbers did not change.

`ForgeConfig` gained `crate(id)`, `tierAt(n)`, `crateUnlocked`, `odds(tier)`,
`rollRarity(forcePity, tier)`, `floorStrikes(tier)` and `bulkRollCost`. Pity is
still Void-or-better, drawn from the crate's own column.

**The crate page is a section.** `CratesView` is a full-bleed card registered in
`Sections` at key `crates` (`page = true`), handed to the nav through a
`pageCards` table the same way `ForgeView`'s card is. The nav hides the two-column
row host for a page section and shows exactly one card, so the tab switch costs
nothing and the crate viewport is never rebuilt. The forge card keeps the quick
roll keys and its crate chip switches tabs via `Sections.select("crates")`.

**Selection is profile state.** `crateSelect` sends the `crate` action, which sets
`forgeCrate` and starts that crate's ramp at zero. `forgeRoll` now refuses an
unknown id instead of falling back to the banner: the fallback used to move a
player's ramp silently. Before the action existed, the 10 Hz payload painted the
old pool back over the pick - observed twice.

**The floor is per rung.** A flat `18 strikes` floor made all five pools quote the
same price once income passed the top banner: live, Standard and Singularity both
read 673.40B. `floorStrikes` scales it by the crate's tier (18 / 36 / 54 / 72 /
90), which restored the ladder.

Measured on the live profile (Void selected, pity 7/11, 39 copies):

| action | cost shown | inventory |
| --- | ---: | --- |
| ROLL | 1.35T SM | 39 -> 40 |
| ROLL x10 | 13.47T SM | 40 -> 50 |

The ten-pull is one transaction: one charge, one `forged` event with `batch = 10`
and `crate = "void"`, clamped to the free slots, and the plate reads
`10 COPIES - BEST OF THE PULL`, `CURSED SLAGSPITE`, `Tempered - Forged`,
`PITY 8/11`.

Persistence was proven with a restart: select Celestial, let the 15s autosave
land, stop and start play. The page adopted `celestial` from the first payload
while the tab was still hidden, before any rail press.

## 15. The starter hour

`Config.StarterBoostSeconds = 3600`. `ProgressionService.grantStarterBoost` writes
`boostX2Until` (the field the game pass already writes) and latches
`starterBoostAt`, so there is no second multiplier path. Existing saves receive it
on their next join as well - deliberate at this stage, so the curve can be
re-measured without wiping a profile.

The card is the one locked modal: `Modals.starter` builds a shell with no close
key, a gold boost plate (`x2_star_matter` art over a drawn bolt fallback), `x2`,
`60 MINUTES`, and a single `START FORGING` key. It fires from the `starter` event
after the first payload, so the boost it describes is already in the income the
HUD is showing. Measured card: 396 x 304 design px; the top bar chip read
`x2 BOOST 25m 44s` behind it.

## 16. The daily track

`Config.DailyTrack` is seven records (`aether`, `scrap`, `starMatter`, `cores`,
`label`) and `claimDaily` pays every field. Day seven pays one Quantum Core. The
Daily Ritual page is a modal track: seven cards, streak head, claim key, claimed
days dimmed to 45% text, today gold, next-up labelled. First build filled a 560px
panel with 300px cards and left a dead band in every card; the shipped numbers are
252 tall in a 470 panel, which leaves the body 411 design px and the note under
the claim key inside the plate.

## 17. The codex expansion

`ModifierConfig` now carries 13 elements (added gale, cinder, abyss, aureate,
prism), 8 grades (added sublime, primordial), 20 prefixes (added tempered, ashen,
stormwrought, hoarfrost, obsidian, lucent, writhing, godsteel) and 20 suffixes
(added deep, longdark, ninthhour, glass, hunger, quiet, sun, makers). The quality
ladder is 32 bands. Live codex counter: `combos 5733000`, `qualities 32`. A Void
ten-pull returned `Tempered - Forged`, so the new affixes are in the roll path and
not only in the catalogue.

## 18. The top-bar toolbar

The utility keys moved out of the nav strip, which is now tabs and rate only. The
top bar carries seven 50 x 62 keys (VAULT, CODEX, BOARDS, TRADE, NOTES, GUIDE,
SETUP) with 22px vector icons over 13px labels, then ASCEND (88) and DAILY (78)
with vector badges. `Layout.MIN_WIDTH` rose to 1320 and `PILL_W` fell to 148.

Measured at 1665 design px (1212 x 518 physical, UIScale 0.7193): the bar is
1198 x 54, the action bank starts at x795 and is 399 wide, the identity plate ends
at 526, and 269px of air sits between them. Six tabs fit the nav at 162 design px
each at `MIN_WIDTH`, with the rate band at its 280 floor.

## 19. Open

- The LihFolk sky is uploaded, mapped and switched off (see section 7).
- The trade handshake was proven through the preview seam, not between two live
  clients. The invite, the desk, the offer sync and the countdown are live; the
  accept-to-session step is code-verified.
- 26 blade meshes still return `User is not authorized to access Asset`; the
  procedural chain renders everywhere, including the board thumbnails.
- 22 VFX sheets remain unuploaded (`scripts/upload_vfx.py` / `--vfx`).
- Store listings still read `SOON`; the key lacks `game-pass:write` and
  `developer-product:write`.
- `stylua`, `wally` and `luau-lsp` are not installed; `selene` is the only static
  pass.
- The new strike-adjacent sounds (`crit`, `crateLand`, `crateShatter`, the
  `rollTick` ladder) shipped unheard. They add to events that were silent, which
  is the safer half of ADR-066, but a roll and a crit still need a listen.
- The drawer's confirm dialog for REROLL was not clicked; the seam calls
  `commitDetailReroll` the way it calls `commitDetailMelt`. No pointer input is
  available in this build.
- DataStore submits trail a live session by up to 45s by design; the boards and
  the detail record share that cadence.
- The crate rail, the ten-pull key and the starter card's `START FORGING` key were
  driven through `QF_Dev`, not by pointer input; no pointer synthesis exists in
  this build. The pick, the price, the charge, the copy count and the reveal were
  read from the live client.
- The Daily Ritual was observed with today already claimed (streak 2/7). A fresh
  claim and the streak reset were not walked on a second profile.
- `rojo serve` keeps the open Studio place in sync; a client module edited while a
  session is live is picked up by the next play session, not the current one. Two
  rounds of this pass were measured against a session that predated the edit and
  had to be restarted.
- AI art prompts for the five crate models, the boost badge and the utility icon
  set are written into `user-manual/`; no image has been generated from them.

