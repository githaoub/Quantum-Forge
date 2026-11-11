---
title: Quantum Forge — Blade Evolution
status: built — v0.1.0, pre-publish
updated: 2026-11-11
tags:
  - roblox
  - incremental
  - quantum-forge
---

### Game Concept: **Quantum Forge: Blade Evolution**

> **Status note.** This note was rewritten on 2026-11-09 to describe the game that
> was actually built, not the one originally pitched. Six claims in the first draft
> turned out to be wrong once implementation started; they are listed in
> [[#7. What the original plan got wrong]] rather than quietly deleted, because the
> pattern of what a plan gets wrong is more reusable than the plan.
>
> **Forge 13 update (2026-11-11).** The heat lockout is gone; past 90% the core runs
> lean at ×0.5 until the player purges (ADR-079). The UI also moved from a tab strip
> to the Foundry Instrument rail, and the forge roll column moved to the CRATES page
> (ADR-076…080). Where this note and an ADR disagree, the ADR wins.
>
> Authoritative numbers live in `src/shared/Config.luau`. This note explains intent;
> the code is the source of truth for values. Engine-level reasoning is in
> `design-decisions.md` (ADR-001…082) in the repo.

A **Sci-Fi / High-Fantasy Weapon Smithing Incremental** aimed at the older slice of
the Roblox audience — the ones who care about auras, sleek surfaces and optimisation
rather than a big map. Built solo, from generated code, with no hand-placed geometry.

---

## 1. Core Fantasy & Visual Identity

**The pitch.** You are a Master Armorer on an orbital forge, harvesting stellar debris
to craft and evolve legendary energy blades across dimensional eras.

**What the player actually sees.** Two layers, not one:

- **A real 3D spawn lobby** — the Orbital Command Bridge, assembled at runtime from
  primitives in `LobbyService.luau`. No models, no asset IDs, no Studio placement, so
  the whole environment is tunable by editing numbers. Each character carries a
  server-side `Highlight`, an aura ring and a particle emitter tinted by the rarity of
  their equipped blade, so the flex is visible to other players.
- **A ScreenGui HUD** authored entirely in Luau on an elastic canvas: height fixed at
  the 720 design rung, width picked from the viewport (1440 default, 1320 minimum)
  and scaled by `UIScale`. Top bar, left rail, full-width section, modal layer.

The original pitch said "rendered entirely through SurfaceUIs." It isn't, and
shouldn't be: a clicker's entire economy runs through its HUD, and a ScreenGui is the
only surface that scales predictably across phone, tablet, desktop and console.

---

## 2. The Core Loop

1. **Strike.** Click the anvil. Each strike adds heat and yields Star-Matter.
2. **Hold the band.** Heat decays on its own. Sustained clicking climbs the gauge;
   stopping drops it. The band is where the money is — see §3.
3. **Vent.** Let heat climb past 85% and vent it for Aether Shards instead of
   burning out.
4. **Forge blades.** Spend Star-Matter up the blade chain. Each blade is a permanent
   multiplier, and each new rarity tier is a visible step change.
5. **Deploy drones.** Spend Aether on passive Star-Matter income.
6. **Spend Cores.** Ascend, then buy tech nodes with Quantum Cores.
7. **Ascend again.** Repeat with a permanently faster ramp.

The loop closes in about 7–17 minutes on a first run. That is the number that
matters: the first ascension has to land inside one sitting or the prestige hook
never fires.

---

## 3. The Unique Hook: thermal management as an instrument

This replaced the original "balance automated cooling pumps / mini-events" pitch.

Heat is a **sweet spot**, not a fill bar. The rule the player has to learn:

| Heat | State | Effect |
| --- | --- | --- |
| 0 – 65% | cold | base yield |
| **65 – 85%** | **in the band** | **×2.5 Star-Matter** |
| 85 – 90% | venting legal | can vent for Aether |
| 90 – 100% | lean | **×0.5 yield until purged**, still strikeable |
| 100% | capped | heat holds at 100; purge is the way back |

`+2.5` heat per click, `−5`/second decay. Holding the band under 25 clicks/second is
the actual skill expression, and it is legible without a tutorial because the gauge
is drawn as a ruled instrument with decade ticks, a stroked band with the multiplier
printed inside it, and a live needle — not as a progress bar. A progress bar would
communicate "fill it up," which is the opposite of the rule.

Venting pays `0.08` Aether per point of heat released, so the heat itself is never
wasted. Overshooting still costs you the band multiplier and time, never your
progress. Past 90% the core runs lean: every strike pays half until the player
purges, but the anvil never stops accepting clicks. That is the difference between a
rule the player can read and leave, and a lockout that takes the game away
(ADR-079).

**Why not the aura/stance system from the pitch?** Aura exists as a server-created
visual on the equipped blade (ADR-012). Active combat stances do not — there is no
combat, and a "stance" in a game with no fights is a menu with a costume on.

---

## 4. What is implemented

| System | State | Notes |
| --- | --- | --- |
| Forge loop + heat gauge | shipped | 25 clicks/s server rate limit |
| Blade chain | shipped | 25 blades, 5 tiers: Scrap → Forged → Astral → Void → Quantum |
| Drones | shipped | five rungs, no cap, 1.16–1.20 growth, gates on fleet size |
| Ascension | shipped | `floor((runSM / 1e9)^0.5)` Cores |
| Tech tree | shipped | 8 nodes, 5–10 levels each |
| Offline earnings | shipped | 8h cap at 50% efficiency |
| Daily streak | shipped | 7-day table, 5 → 50 Aether |
| Playtime milestones | shipped | 5 checkpoints, 5min → 2h |
| Tutorial | shipped | one first-join card, 250 SM + 10 Aether, no recurring pop-ups |
| Session locking | shipped | in-house, atomic `UpdateAsync` (ADR-004) |
| Blade icons | generated | 40 icons, Python + Pillow, not Figma |
| Monetization | wired, **disabled** | 9 items, all IDs `0` |
| Leaderboards | absent | `lifetimeStarMatter` is tracked and ready |

**Pacing.** ~1.08h to the final blade at a perfect 5 clicks/s in band with no tech;
~2.7h at a casual 2 clicks/s. Total ladder spend is ~1.5e13 Star-Matter. The roll
price climbs 5% per roll to a 12x ceiling and resets with the banner, so a batch of
fifty Scrap Forge rolls costs 10 467 instead of 2 500.

---

## 5. Monetization (designed, deliberately inert)

Nine entries exist in `MonetizationConfig.luau`, all with `id = 0`. Every entry point
in the UI checks both `enabled` and a non-zero ID, so each one no-ops. Nothing is
purchasable until real IDs are pasted in and `Config.Debug` is set to `false`.

- **Gamepasses (5):** Fast Forge · Auto-Vent AI · 2x Star-Matter · VIP Quantum Aura ·
  Eternal Forge
- **Developer products (4):** Starter Forge Pack · Instant Overdrive · Emergency
  Vent · Express Salvage

The philosophy from the source video holds: sell **convenience and speed**, never
access. Auto-Vent AI removes the timing skill for players who don't want it;
Emergency Vent dumps heat instantly; Express Salvage buys back time on an expedition.
None of them gates progress that a free player cannot reach.

The cosmetic-gacha idea from the pitch is not built. A gacha with forty icons and no
art pipeline is a loot box with nothing in it.

---

## 6. Build constraints that shaped the design

- **No manual Studio work.** Every instance is created in code. This is why the UI is
  a ScreenGui rather than a designed surface, and why the lobby is primitives.
- **Figma is out of the critical path** (ADR-002). The seat is View-only at 20 calls
  per month, which cannot support a 200-asset pipeline. Icons are generated locally
  and uploaded as an optional second step.
- **Big numbers are plain doubles** to `~1e308` with a suffix table (ADR-001), not a
  mantissa/exponent struct. The hot path is the click handler at 25 ops/second.
- **State sync is batched at 10Hz**, never per frame (ADR-007). Clicks are predicted
  client-side and reconciled on each sync (ADR-008), so input feels instant without
  lying to the player.

---

## 7. What the original plan got wrong

Recorded because the failure pattern repeats, not to relitigate the pitch.

1. **"Rendered entirely through SurfaceUIs."** Wrong surface for a HUD-driven game.
   Fixed by a scaled ScreenGui.
2. **"Figma to generate 200+ blade icons in under an hour."** The tool access did not
   exist. Actual: 40 icons, generated in Python. The lesson is that the plan assumed
   a capability without checking it.
3. **"Balance automated cooling pumps / mini-events."** Too vague to implement and
   too fiddly to learn. Fixed by a strict sweet-spot band.
4. **"Blades unlock active Combat Stances."** Presupposed a combat system that was
   never specified. Cut.
5. **Monetization categories were listed as four.** Actual shape is nine items across
   two purchase types, because gamepasses and developer products are not
   interchangeable.
6. **No numbers anywhere.** Every figure in the pitch was qualitative. The first real
   design work was choosing actual curves, and that changed the feel more than any
   of the above.

---

## 8. Open questions

- **First-session retention is unproven.** The tutorial exists and the pacing maths
  says 7–17 minutes to first ascension, but nobody has played it end to end. This is
  the only number that decides whether the game works.
- **No automated tests.** The economy is pure functions; `TechTreeConfig.compute`
  and `NumberUtil` are the obvious first targets under Lune.
- **Nothing published.** No place ID, no thumbnails, no gameplay video. The source
  video is explicit that a missing gameplay preview is the single most expensive
  mistake available, and it has not been made *yet*.

---

*See also: [[video-01-profit-per-ccu]] for the strategy this was built against —
including which parts of it survived contact.*
