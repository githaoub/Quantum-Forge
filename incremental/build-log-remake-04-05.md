# Gameplay remake: analyses 04 and 05

Two notes asked for the same thing from different angles. `video-04-market-positioning`
wanted the loop to have more than one verb; `video-05-onboarding-monetization-qa` wanted the opening
ninety seconds, the funnel and the storefront fixed before launch. This is what
shipped in `ADR-034`.

## What changed

| Analysis item | Shipped as | Where |
| --- | --- | --- |
| Expedition / salvage sub-loop | Three missions that spend drones for a timed payout | `ExpeditionConfig`, `ProgressionService.dispatch/settleExpedition`, Fleet tab band |
| Post-acquisition RNG | Void Shards from hot-gauge anomalies, 6% / 18% under Overdrive | `ForgeService.strike`, `Config.Anomaly*` |
| Ten clean strikes reward | Skill Overdrive, 15 s at `×2`, shown as ten pips | `Config.StreakForOverdrive`, `ForgeService`, `ForgeView` streak rail |
| Blade mastery and sockets | Ranks at 100/400/1 200/3 000/8 000, up to three runes | `RuneConfig`, `ProgressionService`, `RuneView` |
| Contextual lessons only | Eight lessons, each on a state threshold, 8 s apart | `TutorialController` |
| Immediate wow moment | First strikes pay `×5` until lifetime SM reaches 60 | `Config.WowMoment*`, `ProgressionService.clickYield` |
| Milestone funnel | AnalyticsService events, once per session, server-side | `Funnel`, called from forge/progression |
| No raw currency packs | Store sells passes, boosts, utility and a 5 Robux starter | `MonetizationConfig`, `ShopView` |
| High-ticket sink day one | Eternal Forge pass, 1 499, `×1.25` forever | `MonetizationConfig`, `globalMultiplier` |
| In-game feedback | `FEEDBACK` button, four categories, DataStore sink | `FeedbackView`, `FeedbackStore`, `HudController` |

## Bugs found on the way

- The Starter Forge Pack granted fifteen minutes of double income by writing
  `boostX2Until`, and `globalMultiplier` never read that field. The pack sold a
  timer that did nothing. Fixed, and it stacks with the pass and paid 3x.
- Funnel events were logged from the client. The live console answered with
  `AnalyticsService can only be executed on the game server`. Moved to the server
  inside a `pcall`.
- The lesson counter still read `LESSON 1 OF 5` after the sixth lesson was added.

## Measured in a live playtest

Screen scale 0.719, so design px = measured px / 0.719.

| Thing | Measurement |
| --- | --- |
| Top bar row | feedback `969..1045`, guide `903..963`, bar right edge `1057` |
| Currency pills | `345..457`, `463..575`, `580..693`, 42 px tall (58 design) |
| Streak rail | `193..698, y 462..478` inside Content `182..710, y 378..482` |
| Runes tab | `MasteryCard` present, `RANK 0 / 5`, Ember row `y 328..370` |
| Fleet expedition band | band `419..540`, Debris Sweep row `439..469`, dispatch key `959..1028` |
| Feedback modal | panel visible, text box present, send key `608,338 157×33` |
| First click | `+5` on a zero save (1 × 5x opening), rail reads `STREAK 0/10` |
| Console | no Luau errors; analytics event fired server-side; DataStore 401, mock mode |

## What is not verified

- Overdrive text (`OVERDRIVE x2 12s`) was not seen live: ten timed in-band strikes
  cannot be produced by the simulated mouse bridge. The 0/10 state is confirmed.
- An expedition payout was not waited out; the settle path is code-verified.
- Every blade mesh returned `User is not authorized to access Asset` in this
  session, so the game rendered the procedural fallback for all 26 blades. The
  assets loaded in an earlier session and need a Studio account with access.
- Marketplace IDs are still `0`; the store shows `SOON` until the items exist.

---

# Polish pass: readable right panel, overlay guide, juice (2026-11-10)

Three separate fixes, one root cause each. Recorded in `ADR-035` to `ADR-037`.

## 1. The right panel was set below the readability floor

The screenshot read `0 / 100 STRIKES TO RANK 1`, `SOCKETS 0 OF 3 UNLOCKED` and
`8 VOID SHARDS` at 12px, with socket prompts at 10px. The canvas is fit-scaled, so
10 design px is 7 screen px on a 1366-wide laptop. Those were not "small captions",
they were unreadable.

| Token | Was | Now |
| --- | --- | --- |
| `Theme.Text.Micro` | 12 | **14** |
| `Theme.Text.Tiny` | 10 | **13** |
| Tab pills | 15 | **16** |
| Sale badge | 9 | **13** |
| `textSecondary` | did not exist | `#B8C2D6` |

Cards were re-cut so the larger type has a band to live in: mastery card 156 → 178,
rune row 58 → 68, store row 78 → 88, mission row 42 → 48, expedition band 168 → 186,
heat rail and vent key 34 → 40.

Verified with a `TextLabel.TextFits` sweep across every visible label on all five
tabs: **0 clipped**. The five-tab strip was checked against the real font
(`BLADES` is 60px at 16px Black, a tab is 77.6px) rather than estimated.

## 2. The tutorial ring was being clipped by its own scroll frame

The ring was parented *into* its target, so the side panel's `ScrollingFrame` sliced
it at the viewport edge and the next card painted over it.

It now lives on a top-level overlay (`TutorialHighlightLayer`, `ZIndex 50`, created
before the modal so the card stays above it) and copies the target's rectangle every
`RenderStepped`, clamped to the canvas and to the scroll window. If the target is out
of view the scroll frame is centred on it first.

Lesson predicates were also rewritten as floors: `highestOwnedIndex(state) >= 2`
instead of `#owned >= 2`, `as >= 1` instead of a session flag, any tech level `> 0`.
A player who explores ahead can no longer be asked to redo a step or softlock the
guide. Mastery/runes and tech/ascension became lessons 6 and 8, so the guide now
covers every system in the loop.

Measured live: ring `177,373 537×113` around the strike button at
`182,378 528×104` — 5px proud on all sides, nothing cut.

## 3. The click loop got ears and a shockwave

`Sfx` was one ping. It is now layered from three assets that provably ship inside
the Roblox client (`electronicpingshort.wav`, `impact_explosion_03.mp3`,
`impact_water.mp3`), because a marketplace id that has not uploaded yet fails
silently. Every layer is pitch-jittered 0.95–1.08, and the in-band chime climbs with
the streak counter.

New effects: an expanding `Vfx.shockwave` ring on band strikes and crits, a
heat-reactive stage border that goes gold on a full rail, a gold flash detected on
the Overdrive transition (once, not per sync), and a white emissive flash on the
blade's neon parts driven by a cached part list.

## What is still not verified

- The shockwave and emissive flash fire on the click path but were not *seen*:
  `screen_capture` returns null on this bridge. The click path ran clean with no
  Luau errors and `82` Star-Matter banked from four real clicks.
- The ring's scroll-centring path is code-verified; the strike button is not inside
  a `ScrollingFrame`, so only the unclamped branch was exercised live.
- `0/26` blade meshes still return `User is not authorized to access Asset` in this
  session, so the emissive flash ran against procedurally built blades.

---

# Second polish pass: reveal pacing, guide continuity, draggable preview (2026-11-10)

Five playtest notes, recorded in `ADR-038`.

## One sword per purchase

Blades used to open in waves of three: finish a wave, three rows became legible at
once. The list is a staircase now - owning a blade reveals the next one, nothing
else. Live check on a fresh save: 2 of 25 rows readable (starter + one target);
after forging that target, 3 of 25.

## The guide no longer goes quiet

The objective strip was hidden for the whole guide, so the minutes between the
runes lesson and the ascension lesson were silent. The strip now fills every gap
where no card is on screen and the next lesson has not triggered. Live: after
three strikes the strip read `GOAL: Forge Rivet Edge (10 / 80)`.

## The runes card stops asking for the impossible

`Step` gained `bodyFor` / `ctaFor`. The runes lesson reads the balance at the
moment it opens and says one of three things: craft it now (3 shards), here is how
shards drop (socket but no shards), or rank 1 is 100 strikes (neither). Its ring
only targets a rune button the player can actually press.

## The 3D view is draggable

`ViewportFrame.InputBegan` never fires for mouse buttons on this build, and
`Active = true` marked every click game-processed so the global listener was
blocked too - which is why dragging did nothing. `Active = false` plus a global
handler gated on the frame rectangle fixes it, for LMB and RMB, touch included.

Two coordinate traps found by measurement: `GetMouseLocation()` is offset from
`AbsolutePosition` by the GUI inset (a click at `445,200` read `445,258`), and
`InputObject.Delta` is zero for a warped cursor. Hover uses `InputObject.Position`;
deltas are computed from successive positions.

Proof, reading the preview camera's `CFrame.Position`:

| Gesture | Before | After |
| --- | --- | --- |
| LMB drag | `3.681, 2.789, -7.548` | `7.917, 0.912, -3.319` |
| RMB drag | `7.986, 0.820, -3.146` | `6.202, -0.453, -5.754` |

## Cosmetic

- The hammer glyph on the forge banner replaced with the star every other banner
  uses; it was the last hammer in the UI and carried the same tofu risk the vent
  key's lightning bolt had.
- The impact wash is full-bleed: measured 528x165 over a 528x165 stage, instead of
  stopping 22px short.


## The lists get real art

Fifteen badges arrived from Nano Banana 2 and now sit in the Fleet, Rune and Tech
lists. The art lives in `assets/badges/` (permanent) with the originals and a
contact sheet in `assets/badges/source/`; nothing in that folder is script output.

`scripts/prepare_gamepass_art.py --src <jpg> --dst assets/badges/<slug>.png
--no-preview` keys the checkerboard, clamps to the disc and writes a 512px RGBA
with transparent corners. All fifteen measure corner alpha 0. Ids go in
`AssetManifest.UiArt` and resolve through `rbxthumb://` at 420, the same route the
store badges use.

Rows grew to fit the art. Fleet 48 -> 54 with a 44px badge (band 186 -> 204),
runes 68 -> 78 with a 60px badge, tech stays 106 with a 56px badge in the corner.
The rune effect column narrowed from 226 to 200 so it clears the action button
with 26px to spare; the longest description at 14px is 154px.

`UiKit.badgeWell` is the shared well: circular plate, `Crop`-scaled image, 2px ink
ring, optional 1px accent. It returns nil for an empty image string, so a clone
with no uploads keeps text-only rows.

Live at 0.719 scale: fleet `412x54`, runes `432x78`, tech `432x106`, every label
`TextFits`, all fifteen `IsLoaded` once scrolled into view. Off-screen badges read
`false` until they are scrolled to, which is the content provider behaving normally
and not a missing asset.
