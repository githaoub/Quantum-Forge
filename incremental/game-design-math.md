# Quantum Forge — Game Design & Math

Every number in this document is derived from the shipped config, not aspirational.
Where a table exists, it was generated from `src/shared/BladeRegistry.luau` and
`src/shared/Config.luau` and will go stale if those change. Regenerate rather than
trust the copy.

---

## 1. Pillars

| Pillar | What it means mechanically |
| --- | --- |
| **The forge is a rhythm, not a button** | Clicking has a cost (heat). Holding the sweet spot pays 2.5x. Holding it forever requires modulating your click rate. |
| **Progress is visible in the world** | Each blade is a distinct 3D silhouette and colour, rendered in the preview frame. Its rarity tints the aura on your character, so other players can read your progress at a glance. |
| **Every reset buys a different game** | Ascension grants Quantum Cores that buy *rules*, not numbers (wider band, auto-clicks, free starting blades). |
| **Idle is a floor, not a ceiling** | Drones produce a meaningful passive income, but active play with tech out-earns them. |
| **Nothing is a dead end** | A player who burns out, idles, or loses a streak always has a legal next action. |

---

## 2. Currencies and the loop

```
                     ┌──────────────────────────┐
   click / drones ──▶ │      Star-Matter (SM)    │ ──▶ forge blades (permanent, per-run)
                     └──────────────────────────┘
                                  │
                                  │ at 1e9 run SM
                                  ▼
                     ┌──────────────────────────┐
                     │   Quantum Cores (QC)     │ ──▶ tech tree (permanent, forever)
                     └──────────────────────────┘
                                  ▲
                                  │
                     ┌──────────────────────────┐
   heat ≥ 85 ───────▶│    Aether Shards (AS)    │ ──▶ drones (reset on ascend)
                     └──────────────────────────┘
```

Three currencies, three time horizons:

- **Star-Matter** is the run currency. Resets on ascend. Spent on blades.
- **Aether Shards** are the *within-run* meta currency. Reset on ascend, spent on
  drones. Earned only by venting heat, which means skill converts to passive income.
- **Quantum Cores** are the permanent currency. Never reset. Spent on the tech tree.

The resets are deliberately staggered. Blades reset on ascend, drones reset on
ascend, cores never reset. A player always has one thing that survives.

---

## 3. The heat model

### 3.1 Rules

| Constant | Value | Source |
| --- | --- | --- |
| Heat per accepted click | `+2.5` | `Config.HeatPerClick` |
| Heat decay | `−5.0 / s` (continuous) | `Config.HeatDecayPerSec` |
| Sweet spot | `65 … 85` | `Config.SweetSpotMin/Max` |
| Sweet spot multiplier | `×2.5` | `Config.SweetSpotMultiplier` |
| Vent legal at | `≥ 85` | `Config.VentThreshold` |
| Overheat | `100` | `Config.OverheatAt` |
| Lockout on overheat | `5 s` | `Config.OverheatLockout` |
| Grace to vent instead | `1.5 s` | `Config.OverheatGrace` |
| Aether per heat vented | `0.08` | `Config.AetherPerHeat` |
| Click rate limit | `25 / s` | `Config.ClickRateLimit` |

### 3.2 The core equation

Heat is a leaky bucket. At a sustained `c` clicks per second:

```
dHeat/dt = 2.5·c − 5
```

So:

- `c < 2` → heat never rises. You cannot reach the sweet spot by tapping slowly.
- `c = 2` → **equilibrium**. Heat is flat at whatever value you left it at.
- `c > 2` → heat climbs linearly at `(2.5c − 5)` per second.

This is the whole mechanic in one equation. The intended discovery is that
`c = 2` is the only rate at which the gauge holds still — and holding still inside
65–85 is where the money is.

### 3.3 Time to traverse the gauge

From 0 to the band, then across the band, then to burnout:

| Clicks/sec | 0 → 65 | 65 → 85 | 85 → 100 | Time in band before burnout |
| --- | --- | --- | --- | --- |
| 4 | 15.4 s | 4.0 s | 3.0 s | 4.0 s |
| 6 | 8.7 s | 2.2 s | 1.7 s | 2.2 s |
| 10 | 3.3 s | 1.0 s | 0.75 s | 1.0 s |
| 15 | 1.9 s | 0.57 s | 0.43 s | 0.57 s |
| 25 (cap) | 1.1 s | 0.35 s | 0.26 s | 0.35 s |

Two properties fall out of the numbers, and both are load-bearing:

1. **The band cannot be skipped.** Heat arrives in 2.5-point packets, so from 84.9
   the next click lands at 87.4 — still inside. Every path to 100 crosses the band.
   The player always gets a warning window of at least ~0.26 s, and typically ~1 s.
2. **Bursting is strictly worse than holding.** A 10 cps burst spends 3.3 s at 1x
   climbing to the band, then 1.0 s at 2.5x inside it. Net multiplier over that
   window is `(32.5 + 10·2.5) / 42.5 ≈ 1.35x`. Dropping to 2 cps the moment the
   band is entered pays `2.5x` forever. The optimal line is: burst in, then settle
   to exactly the decay rate.

That second property is what makes the mechanic a skill rather than a mash.

### 3.4 Vent economics

Venting dumps all heat for Aether and resets the gauge:

```
Aether = floor(heat · 0.08 · ventMult · efficiency)
```

`efficiency` is `1.0` normally, `0.25` when venting during the grace window after
an overheat.

| Vent at | Aether (no tech) | Aether at `vent_efficiency` 8/8 (+200%) |
| --- | --- | --- |
| 85 (minimum legal) | 6 | 20 |
| 92 | 7 | 22 |
| 100 | 8 | 24 |

Venting higher is worth more, which creates the tension: the maximum payout sits
one point below the lockout. Skilled play rides 95–99 and vents on the way down;
lazy play vents at 86.

**Overheat penalty.** Missing the vent costs the player 75% of the value *and* the
heat itself: they get `floor(100 · 0.08 · 0.25) = 2` Aether instead of 8, plus 5
seconds of no clicking. Heat still decays during the lockout, so when the lock
ends the player resumes at ~75 heat — already in the band, which softens the
punishment into a tempo reset rather than a stall.

### 3.5 Why the rate limit is 25/s

The heat system self-limits earnings: past `c = 2` you are racing toward a lockout,
not earning more. The 25/s cap is therefore almost never the binding constraint for
an honest player — it exists purely so an autoclicker cannot gain anything a human
with good rhythm could not. `Fast Forge` doubles it to 50/s, which changes the
*feel* (faster band entry) more than the ceiling.

---

## 4. The blade curve

### 4.1 Design target

Each blade should be a satisfying, *visible* jump — roughly `2.4x` multiplier for
`3.2x` cost. That ratio is deliberate: it means the next blade is always a little
further away than the last in time, but always clearly worth it. It also means
twenty-four steps span nine orders of magnitude without any single step feeling
like a wall.

### 4.2 Full catalogue

`×Mult` and `×Cost` are ratios against the previous blade. `CumCost` is total
Star-Matter spent to own everything up to and including that row.

| # | Blade | Rarity | Multiplier | Cost | ×Mult | ×Cost | CumCost |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Rusted Cleaver | Scrap | 1 | 0 | — | — | 0 |
| 2 | Scrap Fang | Scrap | 2.4 | 25 | 2.40 | — | 25 |
| 3 | Rivet Edge | Scrap | 5.8 | 80 | 2.42 | 3.20 | 105 |
| 4 | Coil Shard | Scrap | 14 | 260 | 2.41 | 3.25 | 365 |
| 5 | Cinder Spike | Scrap | 34 | 820 | 2.43 | 3.15 | 1.18e3 |
| 6 | Iron Vigil | Forged | 81 | 2.6e3 | 2.38 | 3.17 | 3.78e3 |
| 7 | Forgebrand | Forged | 195 | 8.4e3 | 2.41 | 3.23 | 1.22e4 |
| 8 | Temperline | Forged | 470 | 2.7e4 | 2.41 | 3.21 | 3.92e4 |
| 9 | Anvil's Oath | Forged | 1.1e3 | 8.6e4 | 2.34 | 3.19 | 1.25e5 |
| 10 | Slagspite | Forged | 2.7e3 | 2.8e5 | 2.45 | 3.26 | 4.05e5 |
| 11 | Nova Reaver | Astral | 6.5e3 | 8.8e5 | 2.41 | 3.14 | 1.29e6 |
| 12 | Starlight Falchion | Astral | 1.6e4 | 2.8e6 | 2.46 | 3.18 | 4.09e6 |
| 13 | Comet's Wake | Astral | 3.8e4 | 9.0e6 | 2.38 | 3.21 | 1.31e7 |
| 14 | Gravwell Sabre | Astral | 9.0e4 | 2.9e7 | 2.37 | 3.22 | 4.21e7 |
| 15 | Astral Cutter | Astral | 2.2e5 | 9.2e7 | 2.44 | 3.17 | 1.34e8 |
| 16 | Nullbreaker | Void | 5.2e5 | 2.9e8 | 2.36 | 3.15 | 4.24e8 |
| 17 | Voidfang | Void | 1.25e6 | 9.4e8 | 2.40 | 3.24 | 1.36e9 |
| 18 | Entropy Edge | Void | 3.0e6 | 3.0e9 | 2.40 | 3.19 | 4.36e9 |
| 19 | Event Horizon | Void | 7.2e6 | 9.6e9 | 2.40 | 3.20 | 1.40e10 |
| 20 | Blackstar Glaive | Void | 1.7e7 | 3.1e10 | 2.36 | 3.23 | 4.50e10 |
| 21 | Hadron Splitter | Quantum | 4.2e7 | 9.8e10 | 2.47 | 3.16 | 1.43e11 |
| 22 | Quanta Verge | Quantum | 1.0e8 | 3.1e11 | 2.38 | 3.16 | 4.53e11 |
| 23 | Singularity Blade | Quantum | 2.4e8 | 1.0e12 | 2.40 | 3.23 | 1.45e12 |
| 24 | Entangle Scythe | Quantum | 5.8e8 | 3.2e12 | 2.42 | 3.20 | 4.65e12 |
| 25 | The Forge Eternal | Quantum | 1.4e9 | 1.0e13 | 2.41 | 3.12 | 1.47e13 |

**Curve health**

| Metric | Value | Range |
| --- | --- | --- |
| Mean multiplier ratio | **2.405** | 2.34 – 2.47 |
| Mean cost ratio | **3.195** | 3.13 – 3.26 |
| Total multiplier span | `1.4e9` | — |
| Total spend | `1.47e13` | — |

The ratios stay inside a `±6%` band across twenty-four steps, which is why no
blade feels like a soft step or a hard wall. If you re-tier a blade, check both
ratios against their neighbours before committing.

### 4.3 Pacing

Click income at any point:

```
SM/click = 1 · bladeMultiplier · clickMult · globalMult · (2.5 if in band)
```

Assume perfect play — `5 clicks/sec`, always in the band, no tech, no passes. Each
blade's affordability time is measured against the blade owned *before* it:

| Milestone | Time played | Blade owned |
| --- | --- | --- |
| 0:00 | 0 s | Rusted Cleaver |
| 0:02 | 2 s | Scrap Fang |
| 0:14 | 14 s | Iron Vigil (first Forged) |
| 1:09 | 69 s | Nova Reaver (first Astral) |
| 4:54 | 294 s | Nullbreaker (first Void) |
| 20:55 | 1255 s | Hadron Splitter (first Quantum) |
| **1:04:42** | 3882 s | The Forge Eternal (final) |

**Scaling rule:** these times are inversely proportional to effective clicks per
second. A casual player averaging 2 cps in the band takes `2.5x` as long — about
**2.7 hours**. Someone who never finds the band takes longer still.

So the honest bracket for a clean first run is **1 to 3 hours**, and the very first
ascension lands at roughly **7 minutes (perfect) to 17 minutes (casual)**. Both
figures are in the range where a new player sees a prestige before they get bored,
and a dedicated one has something to chase all evening.

### 4.4 The roll price ramp

A flat price means the hundredth roll of a banner costs exactly what the first one
did, so a player who can afford one roll can afford every roll, and there is no
reason to bank income between them. The price now climbs with the rolls already
taken at the current banner:

```
cost(rolls) = floor(base · min(1.05^rolls, 12))
```

`1.05^rolls` reaches the 12x ceiling at `ceil(ln 12 / ln 1.05) = 51` rolls and then
stays flat, so a long session never prices the loop out of existence. The clamp is
also load-bearing in the arithmetic: a double overflows to `inf` around 14 000
rolls, and the button would print `inf` without it.

Roll price across the first fifty rolls of the Scrap Forge (base 50):

| rolls taken | price | spent on the batch so far |
| --- | --- | --- |
| 0 | 50 | 50 |
| 10 | 81 | 629 |
| 20 | 132 | 1 653 |
| 30 | 216 | 3 322 |
| 40 | 351 | 6 040 |
| 50 | 573 | 10 467 |
| 51+ | 600 | flat |

The last column is the sum of the prices, and it is the number that matters: the
first fifty rolls cost **10 467** Star-Matter instead of 2 500, a 4.2x increase in
the price of the same amount of content. At the Scrap Forge's click income that is
the difference between emptying the banner in two minutes and spending the first
few minutes deciding which rolls to keep.

Two rules keep it from becoming a wall:

- **The counter is per banner.** Crossing into a new tier zeroes `forgeRolls`
  (`forgeRollTier` tracks which banner the counter belongs to). The new banner
  already costs 18x more, and carrying the ramp across would double-charge the
  same progression step.
- **Ascension zeroes both.** The roll ramp belongs to the run that just ended.

The ceiling matters more at the top than at the bottom. At the Cosmic Engine
(base 2e8) the 12x cap is 2.4e9, which is a rounding error against a fleet that
pays 7.2e8/s; the ramp is felt in the first two banners, where clicks are the only
income and 4.2x on a batch is real time.

### 4.5 The account multiplier

The ramp answers "how many rolls have I taken at this banner". It cannot answer
"how rich am I", because it resets by design. The second multiplier is anchored
on lifetime Star-Matter, which is monotonic and survives ascension:

```
progressScale(lifetime) = min((lifetime / 1e9) ^ 0.5, 1e4)
cost(tier, rolls) = max(1, floor(tier.cost · min(1.05^rolls, 12) · progressScale))
```

It is exactly `1` below `1e9`, so nothing in the early game moved. The exponent is
`0.5` because income scales roughly linearly with the blade multiplier: a square
root keeps the price rising while the ratio of price to income still falls.

| lifetime Star-Matter | multiplier | Cosmic Engine price (rolls = 0) |
| --- | --- | --- |
| 1e9 | 1 | 2.0e8 |
| 1e10 | 3.16 | 6.3e8 |
| 1e12 | 31.6 | 6.3e9 |
| 1e14 | 316 | 6.3e10 |
| 1e17 | 1e4 (cap) | 2.0e12 |

Drones take the square root of the same number, `sqrt(progressScale)`, which is
the fourth root of the lifetime ratio. The asymmetry is deliberate: Aether income
is `heat · 0.08 · ventMult`, and `ventMult` is a finite tech and rune product, so
Aether does not grow with the blade. A linear multiplier would put the ladder out
of reach; the fourth root slows it down without sealing it. At the cap the drone
price is `100x` base.

Both curves are read from the payload, never recomputed in a view: the server
computes `forgeCost`, `fleet[].cost` and `fleet[].bulk` once, and the client
prints them. A client-side recomputation cannot drift from the charge.

What does **not** take the multiplier, and why:

- **Scrap rerolls.** `12 + 10 * (tier - 1)`, and Scrap income is priced by the
  same tier through `salvageValue`. A second multiplier would double-charge.
- **Quantum Cores / the tech tree.** Cores come from ascension, which is already
  proportional to the run being reset. The tree is finite and self-limiting.

---

## 5. Drones

### 5.1 Cost — five rungs, no ceiling

Drones are bought, never rolled. `DroneRegistry` is the whole ladder and both
sides read it: the server prices a copy, the Fleet tab prints the same number.

| rung | first copy | growth | yield/s | unlocks at (total owned) |
| --- | --- | --- | --- | --- |
| `scrap` Scrap Drone | 5 AE | 1.16 | 0.6 | 0 |
| `molten` Molten Core | 150 AE | 1.17 | 22 | 15 |
| `quantum` Quantum Vector | 6 000 AE | 1.18 | 900 | 45 |
| `celestial` Celestial Swarm | 250 000 AE | 1.19 | 42 000 | 120 |
| `cosmic` Cosmic Dreadnought | 12 000 000 AE | 1.20 | 2 400 000 | 300 |

```
cost(n)   = floor(baseCost · growth^n)        n = copies owned in that rung
bulk(k)   = first · (growth^k − 1) / (growth − 1)
```

The count is unbounded and there is no capacity to buy. The only ceiling in the
code is `DroneRegistry.SaneMax = 1e9`, which clamps an expedition squad and a
hostile payload, not a fleet.

| copies owned in rung | scrap | molten | quantum | celestial | cosmic |
| --- | --- | --- | --- | --- | --- |
| 1 | 5 | 150 | 6 000 | 250 000 | 12M |
| 5 | 9 | 281 | 11 632 | 501 334 | 24.9M |
| 10 | 19 | 616 | 26 612 | 1.2M | 61.9M |
| 20 | 83 | 2 962 | 139 286 | 6.8M | 383M |
| 50 | 7 201 | 329 001 | 20.0M | 1.26e9 | 9.1e10 |

### 5.2 Why climbing is always worth it

The gate is tuned so that the first copy of a new rung costs about what the next
copy of the rung below costs. That holds at every step:

| at the gate | next copy of the rung below | first copy of the new rung | gain |
| --- | --- | --- | --- |
| 15 owned | scrap #16: 46 AE / 0.6 = **76.7** AE per SM/s | molten #1: 150 / 22 = **6.82** | **11.2x** |
| 45 owned | molten #16: 1 580 AE / 22 = **71.8** | quantum #1: 6 000 / 900 = **6.67** | **10.8x** |
| later rungs | same shape, since the gate always fires while the rung below is still in its cheap tail | | ~11x |

So a player is never wrong to buy the newest unlocked rung, and is never forced
to: a rung below is always available and always worse per Aether, which is what
makes the ladder a ladder rather than a wall.

The gate is **total drones owned**, which creates a second, unplanned job for the
cheap rung. The cheapest way to raise the *count* is always more scrap drones
(5 AE base with the lowest growth), while the cheapest way to raise *income* is
the premium rung. Reaching 45 owned costs 24 807 AE all-scrap. Buying 30 molten
instead costs 97 102 AE for the same count. So the junk rung stays useful all the
way up, and the ladder is really two curves at once: count, and yield.

### 5.3 Yield

```
SM/s = Σ (copies[rung] · yield[rung]) · droneYieldMult · bladeMultiplier · globalMultiplier
```

Passive income is multiplied by the **equipped blade**, which is the key
integration decision: forging a better blade accelerates the idle layer too, so
there is no point at which the player must choose between active and passive
progress. Both scale off the same number.

`BaseDroneYield = 0.6` survives only as the pre-first-drone fallback, so a player
with no drones still sees a non-zero rate in the HUD.

### 5.4 Active versus passive

Units are "multiples of bladeMultiplier per second". One scrap drone is 0.6, one
molten is 22, one cosmic is 2.4M, so the comparison is now a function of how far
up the ladder a player has climbed rather than a fixed fleet:

| Configuration | Income (×bladeMult/s) |
| --- | --- |
| 45 scrap, no drone tech | 27.0 |
| 15 scrap + 30 molten, no drone tech | 669 |
| 15 scrap + 30 molten, `drone_lattice` 10/10 (+200%) | 2 007 |
| 5 clicks/s in band, no click tech | 12.5 |
| 5 clicks/s in band, `start_might` 10/10 (+250%) | 43.8 |
| 5 clicks/s in band, 2x Star-Matter pass | 87.5 |

The old flat fleet paid 30/s at its cap and clicking had overtaken it. A molten
fleet pays 22x that, and the cosmic rung pays 2.4M per drone, which is the point:
the ladder exists so the passive layer keeps pace with a prestige economy that
multiplies clicks by hundreds.

The invariant is unchanged: **active play is always additive, never redundant**.
Total income is `clicks + drones`, so a player who clicks while drones run is
always ahead of one who does not.

**Balance lever:** if drones run away with the game, raise `DroneRegistry`
growth before touching a yield. Growth stretches the tail inside a rung without
flattening the next one, and the gates are count-based so they do not move when a
price does.

### 5.5 Reachability — the open problem

Aether income does not scale. It comes from venting (0.08 per heat, 6.8 AE per
85-heat vent), first-time forge bonuses (1 to 16), dailies (5 to 50), the tutorial
(10) and expeditions (45 / 165 / 1 100). Nothing multiplies it with fleet size or
ascension count. Measured against the gates:

| gate | cheapest route | AE | vents at 6.8 AE | realistic? |
| --- | --- | --- | --- | --- |
| 15 owned (molten) | 15 scrap | 252 | 37 | yes, first session |
| 45 owned (quantum) | 45 scrap | 24 807 | 3 648 | a long grind |
| 120 owned (celestial) | 120 scrap | 1.7e9 | 2.5e8 | no |
| 300 owned (cosmic) | 300 scrap | 6.8e17 | 1.0e17 | no |

The bottom rungs of the ladder are playable; the top rungs are content that
exists and cannot be reached at current Aether rates. The account multiplier
(`sqrt(progressScale)` on drone prices, §4.5) does not change that shape: it
scales the price with lifetime, while the supply stays flat, so it makes the
upper rungs *later* rather than cheaper. That is the intended brake on a fleet
that multiplies the passive Star-Matter yield by the blade multiplier, but it is
still a brake, not a fix. Closing the gap means one of: an Aether multiplier on
vent yield tied to fleet size, an ascension-scaled vent payout, or pricing the
upper rungs in Star-Matter instead of Aether. It is
named here rather than tuned blind, because the ladder's shape is settled and the
supply curve is the missing half.

---

## 6. Ascension

### 6.1 Formula

```
cores = floor( (runStarMatter / 1e9) ^ 0.5 )
```

Gated at `runStarMatter ≥ 1e9`. Requires an explicit confirmation, because it
destroys the run.

### 6.2 Why square root, and why *run* Star-Matter

The exponent decides how much a longer run is worth. Linear would reward idling
in a single run forever; logarithmic would make a second prestige pointless. The
square root sits between: doubling the run is worth `1.41x` the cores, so a player
is always better off ascending and starting a stronger run than grinding an
exponentially slower one.

Using **run** (not lifetime) Star-Matter is the part that makes prestiges
repeatable. With lifetime earnings, cores would be a function of total playtime and
the second ascension would be worth almost nothing more than the first. With
per-run earnings, every ascent resets the counter and every run is measured on its
own merits.

### 6.3 Payout table

| Run Star-Matter | Cores | Cores per order of magnitude |
| --- | --- | --- |
| 1e9 | 1 | — |
| 4e9 | 2 | — |
| 1e10 | 3 | 3.0 |
| 2.5e10 | 5 | 2.5 |
| 1e11 | 10 | 3.3 |
| 4e11 | 20 | 3.3 |
| 1e12 | 31 | 3.4 |
| 1e13 | 100 | 3.4 |

Roughly **3 cores per decade** of run income once past the first prestige, which
makes the tech tree's costs easy to reason about: a node that costs 30 Cores is
"one decade of progress away".

### 6.4 What resets

| Reset on ascend | Kept |
| --- | --- |
| Star-Matter (current + run) | Quantum Cores |
| Aether Shards | Tech tree levels |
| Drones | Ascension count |
| Fleet (every rung, counts and all) | Quantum Cores |
| Heat and lockout | Blades granted by `head_start` |
| Owned blades | Lifetime Star-Matter |

The player keeps enough blades to skip the opening minutes (`head_start`), and the
new run begins with a multiplier from the tech tree. A second run is materially
faster than the first even with zero purchases, which is the definition of a
prestige that feels good.

---

## 7. Tech tree

Cost of the next level: `floor(costBase · costGrowth^level)`.

| Node | Effect | Max | Base | Growth | Total at max |
| --- | --- | --- | --- | --- | --- |
| Forged Momentum | `+25%` click yield / level | 10 | 1 | 1.6 | `+250%` |
| Thermal Calibration | `+0.25` sweet spot mult and `±2` band width / level | 5 | 2 | 2.0 | `×3.75`, band `55–95` |
| Drone Lattice | `+20%` drone yield / level | 10 | 2 | 1.7 | `+200%` |
| Vent Efficiency | `+25%` vent Aether / level | 8 | 2 | 1.7 | `+200%` |
| Offline Core | `+25%` offline yield / level | 8 | 3 | 1.8 | `+200%` |
| Critical Forge | `+4%` chance of a 5x click / level | 5 | 4 | 2.2 | `20%` @ `5x` = `+80%` EV |
| Phantom Hammer | `+0.5` auto-clicks/sec / level | 10 | 5 | 2.0 | `5/s` automatic |
| Head Start | `+1` free blade at run start / level | 5 | 3 | 2.5 | start at blade 6 |

Two design notes:

- **Thermal Calibration is the best node in the game and is priced accordingly.**
  Widening the band to `55–95` makes the sweet spot reachable in 2.5 s instead of
  3.3 s and holdable with far more slack, which is worth more than any flat
  multiplier because it raises the *ceiling* of skilled play rather than the floor.
  The band is clamped so `sweetSpotMax ≤ 95` (`OverheatAt − 5`) — there is always
  5 points of runway before burnout, no matter how much the band is widened.
- **Phantom Hammer autoplays the mechanic at a fixed rate** (0.5 clicks/s per level,
  capped at 20 strikes per frame). At max level it is 5 clicks/s, which in the band
  would be 12.5× bladeMult/s — competitive with manual play, but it cannot modulate
  its rate, so it will drift toward overheat on its own. It is a convenience, not a
  replacement.

### 7.1 One source of truth

`TechTreeConfig.compute(levels)` produces the entire stat block. The server calls it
for authority, the client calls it for previews. There is no second copy of any
formula anywhere in the codebase, which is why the UI can show exactly the numbers
the server will apply.

---

## 8. Retention systems

### 8.1 Daily streak

Rewards by streak day: **5, 8, 12, 18, 25, 35, 50** Aether.
A seven-day cycle is **153 Aether** — about 19 full vents, or 61% of the 252 AE
that unlocks the Molten rung at 15 scrap drones. The exponential shape (5 → 50)
means day 7 alone is a third of the week's value, which is what keeps a streak
from being abandoned on day 5.

- Claimable every 24 h.
- A gap of more than 48 h resets the streak to zero. The 24–48 h window is
  deliberate grace: one missed evening does not destroy a week.

### 8.2 Playtime milestones

Reward is `floor(seconds / 60)` Aether, paid once each:

| Milestone | Reward |
| --- | --- |
| 5 min | 5 |
| 15 min | 15 |
| 30 min | 30 |
| 60 min | 60 |
| 120 min | 120 |

Total **230 Aether** over the first two hours — a meaningful chunk of the early
drone curve (the first ten drones cost 107) without trivialising it. Milestones are
idempotent via `claimedMilestones`, so a reconnect cannot double-pay.

### 8.3 Offline earnings

```
offline = passiveYield · 0.5 · offlineMult · min(elapsed, 8h)
```

- Payout only after 60 s away, so a reconnect does not fire a modal.
- Hard cap of 8 hours, so a week away is not a shortcut.
- 50% efficiency is the standard "welcome back, but come back" rate. At
  `offline_core` 8/8 it becomes 150% — a genuine reason to buy that node.

Offline income uses **drone yield**, not click yield: it is a return on investment
already made, not a substitute for playing.

---

## 9. Monetization

All IDs ship as `0` and every entry point checks `enabled` plus a non-zero ID, so a
clean clone prompts nothing and throws nothing.

| Product | Type | Effect | Design role |
| --- | --- | --- | --- |
| Auto-Vent AI | Pass | Vents automatically at 85% | Removes the fail state for players who find the rhythm stressful |
| 2x Star-Matter | Pass | `×2` all SM income | The standard, honest accelerator |
| VIP Quantum Aura | Pass | Cosmetic status; no gameplay effect | Status, not power: the badge is the purchase, and nothing in the ladder is gated behind it |
| Fast Forge | Pass | 50 clicks/s instead of 25 | Comfort; the heat system still limits earnings |
| Eternal Forge | Pass | `×1.25` all SM income | The high-ticket permanent sink |
| Starter Forge Pack | Product | 25 Aether + 15 min `×2` | The 5 Robux first purchase |
| Instant Overdrive | Product | 15 min of `×3` | Burst for a session, not permanent |
| Emergency Vent | Product | Clears the lockout and resets heat | Pure convenience; never required |
| Express Salvage | Product | Finishes an expedition in flight | Time, not currency |

**The rule every product obeys:** nothing is exclusive, nothing is time-gated
content, and nothing removes another player's advantage. There are no raw
Star-Matter or Aether packs: a cash-to-currency pack would let a payer skip the
number the game is built around grinding. The permanent multipliers stack
multiplicatively in `globalMultiplier`, and the timed 2x from the Starter Pack is a
separate field (`boostX2Until`) so it stacks with the pass and the paid 3x instead
of replacing either.

`2x Star-Matter` interacts multiplicatively with everything, including offline and
drone income, because it lives in `ProgressionService.globalMultiplier`. That is
intentional: a pass that only doubled *clicking* would feel like a trap the moment
the player started idling.

---

## 10. Big numbers

The economy tops out around `1.4e13` Star-Matter and `1e13` per-blade cost, but the
math is built for `1e308` because a player with maxed tech can overshoot the
catalogue. Values are plain IEEE doubles:

- Exact integers to `2^53 ≈ 9.0e15`.
- Finite to `1.8e308`.
- No `NaN` or `Inf` can enter a save: `NumberUtil.sanitize` clamps every value on
  load and every add.

Formatting walks a suffix ladder (`K, M, B, T, Qa, Qi, Sx, Sp, Oc, No, Dc, Ud, Dd,
Td, Qad, Qid, Sxd, Spd, Ocd, Nod, Vg, Uvg, Dvg, Tvg, Qavg, Qivg, Sxvg, Spvg, Ocvg,
Novg, Tg`) and falls back to scientific notation above `1e36`.

The rationale for not using a mantissa/exponent struct is in
`design-decisions.md` — the short version is that the hot path is a click handler
and the struct would allocate on every operation for no reachable gain.

---

## 11. Tuning levers

Ordered by how much damage each one does if you get it wrong.

| Lever | File | Effect | Safe range |
| --- | --- | --- | --- |
| `HeatDecayPerSec` | `Config.luau` | Sets the equilibrium click rate (`decay / heatPerClick`) | 3–8 |
| `SweetSpotMin/Max` | `Config.luau` | Band width → skill ceiling | width 15–30 |
| `SweetSpotMultiplier` | `Config.luau` | Reward for holding | 2.0–3.5 |
| Blade `multiplier` | `BladeRegistry.luau` | Per-step power | ratio 2.2–2.6 |
| Blade `cost` | `BladeRegistry.luau` | Per-step pacing | ratio 3.0–3.5 |
| `DroneRegistry` `growth` | `DroneRegistry.luau` | Passive tail length inside a rung | 1.14–1.22 |
| `DroneRegistry` `yield` | `DroneRegistry.luau` | Step change between rungs | keep the ~11x gate ratio |
| `DroneRegistry` `unlockAt` | `DroneRegistry.luau` | How long a rung is the goal | 15 / 45 / 120 / 300 |
| `AscendExponent` | `Config.luau` | Prestige reward curve | 0.4–0.7 |
| `OfflineEfficiency` | `Config.luau` | Return-on-absence | 0.3–0.7 |
| `BaseDroneYield` | `Config.luau` | Passive floor before the first drone | 0.4–0.8 |

Changing `HeatDecayPerSec` without changing `HeatPerClick` silently changes the
`c = 2` equilibrium, which invalidates every pacing number in section 4. Change both
together or not at all.

---

## 12. Reproducing these tables

The blade table and ratio summary come from parsing the registry:

```powershell
python -c "
import re, pathlib
t = pathlib.Path('src/shared/BladeRegistry.luau').read_text(encoding='utf-8')
rows = re.findall(r'id = \"([^\"]+)\".*?multiplier = ([^,]+),\s*cost = ([^,]+)', t, re.S)
for i, (bid, m, c) in enumerate(rows, 1):
    print(i, bid, m, c)
"
```

The heat tables are closed-form from `dHeat/dt = 2.5c − 5` and do not need code.

---

## 13. Mastery, runes and anomalies

### 13.1 Mastery ladder

Every accepted strike adds one point to the equipped blade's mastery counter. The
counter is per blade and survives an ascension.

| Rank | Strikes | Sockets |
| --- | --- | --- |
| 0 | 0 | 0 |
| 1 | 100 | 1 |
| 2 | 400 | 1 |
| 3 | 1 200 | 2 |
| 4 | 3 000 | 3 |
| 5 | 8 000 | 3 |

Rank 1 lands inside the first minute of real play (100 strikes is roughly 40–60
seconds of clicking). Rank 5 is a multi-hour goal for a blade the player actually
uses, which is the point: mastery is a reason to keep a blade you like instead of
trading it the moment a stronger one drops.

### 13.2 Rune table

| Rune | Effect | Per rune | Cost |
| --- | --- | --- | --- |
| Ember | `clickMult` | +8% | 3 |
| Tempo | `coolMult` | +6% | 3 |
| Edge | `critChance` | +3 points | 4 |
| Prism | `ventMult` | +10% | 5 |

Three Embers is `1.08³ = 1.26`, so a fully socketed rank-5 blade with three Embers
pays 26% more per strike. Costs are deliberately flat: the sink is the socket
count, not a rising price, and a player with one socket is not priced out of
experimenting.

### 13.3 Anomaly drops

```
chance = 0.06 + (0.18 if forgeOverdriveActive)
if heat >= 55 and random() < chance then +2 Void Shards
```

Expected shards per 100 strikes held above 55% heat: **12** normally, **36** during
Overdrive. A single Ember costs 3, so the first rune is roughly 25 hot strikes.
Void Shards are the only currency that does not reset on ascend.

---

## 14. Expeditions

| Mission | Squad | Seconds | Aether | Cores | Shards |
| --- | --- | --- | --- | --- | --- |
| Debris Sweep | 5 | 300 | 45 | 0 | 0 |
| Deep Salvage | 15 | 900 | 165 | 1 | 1 |
| Void Run | 30 | 3 600 | 1 100 | 6 | 4 |

The comparison that matters is against idling. A scrap drone at
`BaseDroneYield = 0.6` and a 1× blade produces 36 SM/min. Five drones idling for
five minutes produce 180 SM. Debris Sweep pays 45 Aether; Aether converts to
drones at 5 for the first scrap copy, and a drone multiplies blade output forever.
The short mission is deliberately worse than idling in SM terms and better in
Aether terms, because Aether is the currency the active player is short of.

The squad is taken off the **cheapest rung first**. Five Scrap Drones produce
3 SM/s and five Cosmic Dreadnoughts produce 12M SM/s, so a top-down deduction
would charge a thousand times the income for the same payout.

Payout is snapshotted at dispatch:

```
payout = floor(mission.aether × bladeMultiplier × globalMultiplier)
```

so swapping blades mid-flight cannot inflate a committed run. Committed drones are
subtracted in `passiveYield`, which also means offline income ignores them.

Ascending forfeits a mission in flight. Mastery, runes and shards survive.

---

## 15. Overdrive and the first minute

### 15.1 Skill Overdrive

Ten consecutive in-band strikes open a 15 second window where the click
multiplier is `×2`. The triggering strike is not doubled: `clickYield` reads the
window state before it is set.

Expected value: at a 2 clicks/s rhythm inside the band, 10 strikes take 5 seconds
and the window covers ~30 strikes. The reward is therefore about 30 extra strike
yields per 35 seconds of precise play, which is meaningful without making the band
mandatory. A miss resets the count to zero, and so does a burn-out.

Paid Overdrive (`overdriveUntil`) is a separate `×3` for fifteen minutes and does
not touch the streak. Anomaly chance reads the skill window, not the paid one.

### 15.2 First-minute multiplier

```
if lifetimeStarMatter < 60 then clickMult ×= 5
```

The first blade costs 25, the second 90. At 1 SM per strike the first blade takes
25 clicks, which is a bad first minute. At 5× it takes 5. The gate is the lifetime
total rather than a timer, so the flourish lands on the first interactions the
player actually makes, and it cannot be re-triggered by ascending.
