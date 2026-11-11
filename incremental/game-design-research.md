---
type: research
status: live
updated: 2026-11-11
aliases:
  - game-design-research
  - research-github
tags:
  - research
  - game-design
  - retention
  - ui
---

# Game design research: loops, retention, and what makes it fun

This is the text-first research pass. The earlier notes in this vault are video
breakdowns; this one uses GitHub repositories, design-skill packs, and the source
code of shipped incrementals. The question is not "what is a good game" in the
abstract. It is: **which levers make an incremental worth returning to, and which
of those levers does Quantum Forge already pull?**

The note ends with an audit and a ranked action list. Nothing in the action list
has been built unless it says so.

> [!info] How this was researched
> GitHub topics and curated lists first (`awesome-game-design`,
> `gamedesign-playlist`, `GDC-Index`), then the primary material they point at:
> a game-design skill bundle, the READMEs and source of four incrementals, and the
> 2DGD book's loop chapter. Code and shipped UI were read before opinions were
> formed. The honesty table at the end separates what was read from what was only
> skimmed.

## The short answer

Fun is not a feature and it is not a number that goes up. In an incremental it is
the rate at which five things happen at once:

| Lever | The player's question | What carries it in Quantum Forge |
| --- | --- | --- |
| **Clarity** | "What do I do now?" | one focal object per screen, a visible strike key, a gauge with one caption |
| **Mastery** | "Can I get better at this?" | the heat band, the lean point, overdrive streaks, rune sockets |
| **Anticipation** | "What is behind the next roll?" | crate slam, rattle, shatter, rarity reveal, pity counter |
| **Collection** | "What am I completing?" | 25 blades, variants, the codex, five crate pools |
| **Status** | "Who can see it?" | equipped blade aura, leaderboards, VIP aura, trade desk |

The rest of this note is the evidence and the gaps.

## 1. The loop is the product

The design-skill bundle defines a core loop as a **repeatable motivational
circuit**, not a sequence of actions. Four questions have to be answerable:

1. What does the player do?
2. What does the game return?
3. What state changes because of it?
4. Why does the player want another cycle?

If the fourth question has no answer, the loop is incomplete. If the loop cannot
be said in one breath, it is muddy. If the "loop" is really a progression track,
it is scaffolding, not the engine.

Quantum Forge's loop in one breath:

```
strike -> heat rises -> yield is multiplied in the band
       -> Star-Matter buys blades, drones and tech
       -> the next strike is bigger or faster -> strike again
```

The support loops are separate:

| Loop | Verb | What it returns | Why it exists |
| --- | --- | --- | --- |
| Forge | strike | Star-Matter, heat, overdrive | the core engine |
| Crates | roll | blades, variants, scrap | collection and anticipation |
| Fleet | build | passive Star-Matter | idle and offline progress |
| Runes | socket | mastery multipliers | specialisation |
| Tech | ascend | permanent rules | prestige |
| Daily | claim | Aether, scrap, cores | appointment and return |

The Forge 13 pass deleted the roll column from the forge. That was a loop fix, not
a layout fix: rolling is a **purchase decision**, and it was competing with the
strike. The forge now has one verb. The crates page owns the roll. This is the
cleanest example in the project of the research rule "separate the core loop from
its support systems" (ADR-078).

**Implication.** Protect the strike loop's latency and feedback above every other
surface. A 50 ms delay on a crate animation is invisible; a 50 ms delay on the
strike is the game feeling bad.

## 2. Fun is a stack of aesthetics

The MDA framework (Mechanics, Dynamics, Aesthetics) says the designer builds
mechanics, the player experiences dynamics, and the emotional result is the
aesthetic. It names eight aesthetics: sensation, fantasy, narrative, challenge,
fellowship, discovery, expression, and submission.

Quantum Forge is not trying to serve all eight. It serves five:

| Aesthetic | Where it lives | Is it strong? |
| --- | --- | --- |
| **Challenge** | heat band, lean point, overdrive streak | yes, and it is the differentiator |
| **Discovery** | crate pools, variants, codex, anomalies | yes, the crate is the peak |
| **Expression** | blade choice, variant, aura, rune build | medium; the blade is visible but the build is not |
| **Submission** | drones, offline income, idle time | yes, 8 h at 50% |
| **Fellowship** | leaderboards, trade desk, auras in the lobby | thin; asynchronous only |

The practical rule: **a system that serves no aesthetic is a chore.** The store
serves monetization, which is a business need, not a fun need. That does not make
it wrong, but it explains why it should not sit in the same visual weight as the
five play sections.

Self-Determination Theory adds the psychological layer: autonomy, competence, and
relatedness. Quantum Forge is strong on autonomy (six systems, meaningful choice
of what to spend on) and competence (the heat band is a real skill). Relatedness
is the weak leg: leaderboards and trade are comparison, not connection. Do not add
a social system just to fill the column; asynchronous comparison is enough for a
solo incremental.

## 3. Goal density is the retention engine

The goal-density audit asks a better question than "how long is the game": **when
the player opens it, how quickly can they find a meaningful goal that fits the time
they have?**

A meaningful goal is both attainable in the current session and consequential in
the larger game. Strong games offer goals at three horizons at once:

| Horizon | Quantum Forge examples | State |
| --- | --- | --- |
| **Short** (seconds to one session) | one strike, one crate roll, one daily claim, one cache crack | strong |
| **Mid** (several sessions) | next blade, next drone rung, next rune rank, a codex set | strong |
| **Long** (days to weeks) | first ascension, 25-blade completion, leaderboard rank, variant collection | visible but thin at the top |

The failure patterns to watch for:

- **Goal drought**: nothing meaningful to do. Not the current problem.
- **Goal smog**: too many competing goals, no priority. The current risk. Six rail
  sections, a daily track, salvage caches, codex pages, boards, trade, and store
  all ask for attention.
- **Mid-term gap**: good micro-goals and big aspirations, nothing in between.
- **Long-term fog**: sessions happen but no larger arc gives them meaning.
- **Unsafe exit**: the player feels punished for stopping.
- **Obligation loop**: return triggers create pressure rather than anticipation.

Quantum Forge's short and mid horizons are healthy. The long horizon exists but is
mostly a leaderboard and a completion set; the **first ascension** is the real
long goal and it lands in 7–17 minutes, which is the right first-session target.
The risk is not a drought. It is that the player cannot tell which of the six
sections is the next best move.

**Action candidate:** one `NEXT` line in the rail foot, computed from the cheapest
available unlock (next blade, next drone, next tech node, or the daily). It answers
"what now?" without adding a seventh panel. This is the highest-value small change
in the audit.

## 4. Retention is return pull, not pressure

The Zeigarnik effect says unfinished things stay in the mind. That is useful when
the open loop is legible, meaningful, self-directed, and finite enough to imagine
closing. It is toxic when there are too many loops, when they are low-value, or
when the game nags about them.

Quantum Forge's return triggers:

| Trigger | Cadence | Type | Verdict |
| --- | --- | --- | --- |
| Offline earnings card | on return, 8 h cap at 50% | reward + closure | healthy |
| Daily track | 7 days | appointment | healthy if it stays one |
| Salvage caches | unix-clock crack | anticipation | healthy |
| Pity counter | per crate | near-miss protection | healthy, but the label is ambiguous |
| Codex sets | long | collection | healthy |
| Leaderboards | slow | status | thin, but honest |

The rule that falls out of the research: **one appointment, one near-miss, one long
arc.** More than that and the game becomes a chore list. The daily track is the
appointment. The pity counter is the near-miss. The codex and the blade ladder are
the long arc. Do not add a second daily, a second energy bar, or a second timed
claim.

The **peak-end rule** adds a second rule: players remember the strongest moment and
the ending, not the average. The crate opening is the strongest moment in the game
(slam, wind-up, shatter, reveal). The ending of a session is currently whatever the
player does last; there is no closing beat. The offline card is the opening beat on
return, and it already pays the fleet's output. It could also name the best thing
that happened and the next goal, which would turn a cold open into a small
ceremony.

An incremental should never punish leaving. The offline cap and passive drones
already make stopping safe. Keep it that way. Heat decay while away is fine; a
"the core cooled and you lost the run" rule would be hostile.

## 5. Randomness must feel fair

The perceived-randomness audit makes one distinction that matters more than any
probability table: **input randomness** happens before the player chooses, and
**output randomness** happens after they commit.

- **Output randomness on the crate is correct.** The roll is the product. The
  player pays, watches, and gets a result. The animation is the point.
- **Input randomness on the strike would be fatal.** A click that sometimes pays
  nothing would undermine the heat skill and make the core loop feel rigged.

Quantum Forge already does the important things:

- one stacked odds bar drawn common to rare, so the 0.35% sliver looks like a
  sliver;
- a visible pity guarantee (8–12 rolls depending on the crate);
- a ten-roll batch that smooths streak pain;
- a price ramp that is shown before the player commits.

The gap is the **pity label**. `PITY 8 ROLLS` reads as "you have eight rolls of
pity banked." It is actually the threshold. The state already carries
`forgePity` and `forgePityGoal`, so the honest label is `PITY 3 / 8` or
`GUARANTEE IN 5`. This is a one-line copy fix with a real perception payoff: the
player can see progress toward the guarantee instead of guessing.

Two more rules from the audit:

- **Do not hide weights.** Opaque weighting is where "the game knows what I need"
  stories come from.
- **Do not make pity too clever.** A single-player incremental does not need
  exploit-proof obfuscation; legibility is worth more than mystery.

## 6. UI is the game's explanation

The "vibe coded" diagnosis in `ui-refactor-direction.md` was correct: the old build
had a consistent vocabulary but no hierarchy. Every card had the same weight, so
nothing was important. The Foundry Instrument system fixed that with five rules
that are really perception rules:

1. **One focal object per screen.** The eye needs a destination.
2. **One accent per region.** Two accents means neither is an accent.
3. **Mono for figures, sans for words.** Numbers should look like measurements.
4. **Rules, not bevels.** A 1 px line separates; a bevel decorates.
5. **Motion is a response.** A hover or a press confirms agency; a looping glow
   competes with the thing the player is trying to read.

The incremental repos add two UI patterns worth copying:

- **Progressive disclosure.** Particle Clicker hides an upgrade until its
  requirements are met and the player can nearly afford it. The upgrade list is
  never a wall of locked rows. Quantum Forge shows all six rail sections from the
  start; that is fine for navigation, but a new section could carry a dot when it
  first unlocks something, the way SpaceCompany's tech tree raises a tab alert.
- **Live preview of the reset.** SpaceCompany's rebirth screen shows the Dark
  Matter gain before the player commits. Quantum Forge's ascension modal should do
  the same: show the cores the current run is worth, not just a warning.

Feedback latency is part of UI. The client predicts the strike, the server confirms
at 10 Hz, and the number/sound/shake land immediately. That is the correct order.
Never make the player wait for the server to see that a click worked.

## 7. What the shipped incrementals actually do

| Repository | Pattern worth taking | Pattern to leave |
| --- | --- | --- |
| [SpaceCompany](https://github.com/sparticle999/SpaceCompany) | rebirth previews the Dark Matter payout, offers respecs, confirms the reset, and tech unlocks whole tabs with alerts | resource-chain sprawl; dozens of tabs and storages |
| [Particle Clicker](https://github.com/particle-clicker/particle-clicker) | upgrades appear only when the player is close to affording them and the requirements are met, then disappear when bought | hidden requirements; the player cannot plan |
| [Level 13](https://github.com/nroutasuo/level13) | technologies slowly unlock new aspects of the game; survival, base-building and a seeded world | text-first pacing is slower than a Roblox session |
| [Evolve](https://github.com/pmotschmann/Evolve) | clicker + idler + micromanagement; an explicit rule that a new feature cannot make the game easier without making something else harder | prestige layers that require a wiki |
| [PokéClicker](https://github.com/pokeclicker/pokeclicker) | collection breadth as the long arc: routes, gyms, dungeons, shinies | content volume that a solo dev cannot match |
| [2DGD_F0TH](https://github.com/2DGD-F0TH/2DGD_F0TH) | input -> update -> draw as the minimum loop abstraction | none; it is a textbook, not a game |

The Evolve rule is the one to write on the wall:

> "If you want to contribute a new feature it can not arbitrarily make something
> easier without making something else harder."

That is the balance version of "a feature that serves no aesthetic is a chore."

## 8. Audit of Quantum Forge

| Lens | Finding | Evidence | Action | Size |
| --- | --- | --- | --- | --- |
| Core loop | clean; one verb on the forge | ADR-078 deleted the roll column | none | — |
| Aesthetics | challenge, discovery, submission strong; expression medium; fellowship thin | heat band, crates, drones, boards | do not add social just to fill the column | — |
| Goal immediacy | the player can see six sections but not the next best one | rail has no `NEXT` readout | add one `NEXT` line to the rail foot | M |
| Goal density | short and mid strong; long is thin at the top | first ascension 7–17 min; leaderboard is the only long status | keep the first ascension; make the codex completion visible | S |
| Open loops | one appointment, one near-miss, one long arc | daily, pity, codex | do not add a second daily or energy bar | — |
| Peak-end | the crate is a strong peak; the session has no closing beat | crate sequence; offline card is the return beat | add "best thing + next goal" to the offline card | S |
| Randomness | odds and pity are honest; the pity label is ambiguous | `PITY 8 ROLLS` used the threshold, not progress | `PITY 3 / 8` or `GUARANTEE IN 5` | XS, shipped |
| Fairness | the lean point is legible and soft; no lockout | ADR-079, gauge caption, danger fill | add a 90% tick; clamp Thermal Calibration's band to 90 or paint 90–95 as lean | S, shipped |
| Anticipation (crates) | the crate had a slam and a shatter, but the reveal was a text swap; a ten-pull showed only its best copy | `CratesView`, `FeedEvent` | staged reveal, every-copy ribbon, rarity ceremony | L, shipped |
| UI hierarchy | Foundry system is consistent; navigation is flat | one accent, 1 px rules, 92 px rail | add a new-unlock dot; keep the rail at six | S |
| Feedback | strike is predicted; crate has slam/wind-up/shatter | client prediction, Sfx/Vfx | none | — |
| Monetization | convenience, not access; store reads `SOON` | 5 passes + 4 products, all ids 0 | do not gate progress; finish listings when the key allows | — |

### Ranked actions

1. **Pity label progress** (`XS`, shipped 2026-11-11). Read `StateStore.current.forgePity` /
   `forgePityGoal` in `CratesView.paintOdds` and print `PITY 3 / 8`. The page now
   draws one tick per roll, a gold goal tick, and `GUARANTEE IN N`. One line, no
   layout change, immediate fairness gain.
2. **A 90% tick on the heat gauge, and a decision about the widened band** (`S`,
   shipped 2026-11-11). The lean point is a rule the player should see before they
   cross it, not only after. The gauge now repaints `bandMin` / `bandMax` from the
   payload, a full-height 90% tick marks the lean point, and `sweetSpotMax` clamps
   to `PenaltyFrom` so the top of a maxed band cannot pay `0.5x` under a `2.5x`
   caption (see `game-design-math.md` §7).
3. **One `NEXT` line in the rail foot** (`M`, shipped 2026-11-11). Cheapest
   available unlock: next blade, next drone, next tech node, or the daily. This is
   the return-player answer to "what now?" and the antidote to goal smog. The rail
   foot now prints `NEXT / CRATE / 44%` and resolves the cheapest gate from the
   same payload the sections use (ADR-084).
4. **Offline card names the best thing and the next goal** (`S`). The card
   already pays the fleet; add one line of context. This is the peak-end fix for
   the session boundary.
5. **New-unlock dot on the rail** (`S`). SpaceCompany's tab alerts, reduced to
   one dot. Show it only when a section has something the player can afford or
   has never opened.
6. **Demote the store from the play rail** (`M`). The store is monetization, not
   a loop. A top-bar coin key or a utility-row entry would reduce the rail to
   five play sections. This is a product decision, not a UI tidy-up.
7. **Measure the first-session funnel** (`M`, no code). Time to first crate,
   first drone, first ascension. Targets: under 90 s, under 3 min, under 17 min.
   The funnel already logs `First_Strike`, `First_SweetSpot`, `First_Vent`,
   `Forge_<blade>`, `First_Drone` and `First_Ascension`; the missing piece is a
   dashboard that turns those events into the three times.

Items 1–5 are safe to build without a new system. Item 6 needs a product call.
Item 7 is measurement, not design.

## 9. What not to do

- **No lockouts.** A clicker that stops accepting clicks loses the player who was
  enjoying the loop. The lean point is the correct shape (ADR-079).
- **No RNG on the strike.** Randomness belongs on the crate, where the player has
  opted into a roll.
- **No hidden odds.** The stacked bar is the trust signal.
- **No second daily, energy bar, or timed claim.** One appointment is a ritual;
  three are a job.
- **No feature without an aesthetic.** If you cannot name which of the five
  aesthetics it serves, it is a chore.
- **No progression mistaken for the loop.** Blades and drones are the ladder. The
  strike is the game.
- **No equal-weight cards.** The "vibe coded" read came from every element having
  the same visual weight. Hierarchy is the fix, not more decoration.

## Sources

| Source | What it gave |
| --- | --- |
| [Stanestane/game-design-skills-bundle](https://github.com/Stanestane/game-design-skills-bundle) | core-loop extraction, goal density, perceived randomness, peak-end, Zeigarnik, fairness, autonomy/competence/relatedness |
| [sparticle999/SpaceCompany](https://github.com/sparticle999/SpaceCompany) | rebirth preview, respec, reset confirmation, tech-gated tabs with alerts (`stargaze.js`, `techData.js`) |
| [particle-clicker/particle-clicker](https://github.com/particle-clicker/particle-clicker) | upgrades become visible only when near-affordable and requirement-met (`gameobjects.js`, `json/upgrades.json`) |
| [nroutasuo/level13](https://github.com/nroutasuo/level13) | technologies slowly unlock new aspects; survival + base-building + seeded world |
| [pmotschmann/Evolve](https://github.com/pmotschmann/Evolve) | clicker + idler + micromanagement; the "no easier without harder" contribution rule |
| [pokeclicker/pokeclicker](https://github.com/pokeclicker/pokeclicker) | collection breadth as the long arc |
| [2DGD-F0TH/2DGD_F0TH](https://github.com/2DGD-F0TH/2DGD_F0TH) | input -> update -> draw loop abstraction (`chapters/004_GameDev_Basics/001_GameLoop.md`) |
| [Roobyx/awesome-game-design](https://github.com/Roobyx/awesome-game-design) | index of GDDs, postmortems, pitches and templates |
| [kkga/gamedesign-playlist](https://github.com/kkga/gamedesign-playlist) | canonical reading list: MDA, Costikyan, Daniel Cook, Design 101 |
| [Zilize/GDC-Index](https://github.com/Zilize/GDC-Index) | GDC design/business session summaries, 2024–2025 |
| [Roblox/creator-docs](https://github.com/Roblox/creator-docs) | platform production docs; not deep-read in this pass |

## Honesty

| Claim | State |
| --- | --- |
| The skill bundle was read | Seven skills read in full: core loop, goal density, perceived randomness, peak-end, Zeigarnik, fairness, need satisfaction. The rest of the catalog was skimmed. |
| The incremental repos were read | READMEs for SpaceCompany, Particle Clicker, Level 13, Evolve and PokéClicker; specific source files for SpaceCompany (`stargaze.js`, `techData.js`) and Particle Clicker (`gameobjects.js`, `upgrades.json`). Not every system in every repo. |
| MDA was read | The framework is cited from the canonical paper and the playlist; the PDF fetch was blocked in this environment, so the eight aesthetics are from the standard summary, not a fresh close read. |
| The GDD archive was read | No. `awesome-game-design` was used as an index; the linked GDDs and postmortems were not opened. |
| The recommendations were tested | No. Items 1–7 are design hypotheses ranked by expected effect and cost. The pity label and the 90% tick are the cheapest to verify in a live session. |
| The audit numbers are current | Yes, from `Config.luau`, `ForgeConfig.luau`, `CratesView.luau`, `MonetizationConfig.luau` and the ADR log on 2026-11-11. |
