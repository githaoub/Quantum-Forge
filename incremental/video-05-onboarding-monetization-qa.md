Here is the copy-pasteable `video-05-onboarding-monetization-qa.md` breaking down every core insight from the video (`I Made 3 Viral Roblox Games in a Row (Here's What I Wish I Knew Sooner)` by Tizzy RBLX) and mapping each lesson directly onto *Quantum Forge: Blade Evolution* and our `design-decisions.md` architecture.

---

```markdown
# video-05-onboarding-monetization-qa: Post-Mortem Lessons on Onboarding, Progression Funnels, Monetization & QA

* **Source Video:** [I Made 3 Viral Roblox Games in a Row (Here's What I Wish I Knew Sooner)](http://www.youtube.com/watch?v=_JyiKfNNqls) — Tizzy RBLX (2026-10-14)
* **Core Focus:** Post-mortem data and operational mistakes from *Raise Anomaly* (peaked ~20k CCU, ~6%–8% D1 retention fixed up to ~16% D1), covering frictionless 90-second onboarding, contextual tutorials, progression funnel telemetry, early-launch monetization, and live-server QA.

---

## 1. The 90-Second Frictionless Onboarding & Contextual Tutorials

### Video Breakdown
* **Eliminate First-90-Second Micro-Friction:** Early players dropped off simply from having to manually equip an item in their hotbar or walk to a shop before experiencing the core reward loop [00:02:57, 00:03:03, 00:03:51]. Top games auto-equip items and pre-seed initial resources (e.g., placing 3 starter food items directly in the player's inventory) so they experience the core payoff immediately [00:03:21, 00:04:13, 00:04:45].
* **Engineer an Immediate "Wow" Moment:** Make the very first loop interaction exaggerated and rewarding (e.g., making the creature grow 5x bigger on its first feed) so the player immediately understands *why* the loop is fun before setting them free [00:05:16, 00:05:33].
* **Contextual Tutorials Over Info-Dumping:** Never teach secondary systems (shops, plot upgrades, trails) during the opening tutorial [00:05:44, 00:06:15]. Trigger mini-tutorials **only at the exact moment the player hits a real state threshold** (e.g., teaching where to buy food only after their 3 free starter items run out, or teaching plot upgrades the first time they hit max capacity) [00:04:32, 00:06:34, 00:07:04].
* **Avoid Rapid Context Switching:** After teaching a player an upgrade, let them *feel* the power spike in gameplay before introducing the next menu or mechanic [00:07:34].

### Application to *Quantum Forge: Blade Evolution*
* **Current Alignment (`ADR-017` / `ADR-028`):** We already moved from an ignored top strip to centered modal cards and state-driven predicates[cite: 17].
* **Actionable Upgrade:**
  1. **Tighten the 5-Lesson Modal Sequence:** Avoid front-loading all 5 lessons back-to-back in the first 60 seconds. Keep Lesson 1 focused strictly on **Striking the Anvil** and hitting the **Green Sweet Spot** for an exaggerated early visual/currency spike.
  2. **Convert Later Lessons into Pure Contextual Triggers:** Only trigger the **Vent Heat** modal the first time the player actually crosses `85%` heat; only trigger the **Fleet** modal once they have collected enough Aether to afford their first drone (`BUILD 1`); and only trigger **Tech Tree** education once they reach their first `ASCEND` milestone.

---

## 2. Data-Driven Progression Balancing (No Winging It)

### Video Breakdown
* **The "Dev Account" Blind Spot:** Testing exclusively on a progressed developer account hides early-game bottlenecks [00:08:49]. Always playtest from a **fresh alt account** and log exact timestamps for every milestone (e.g., *Minute 1: First unlock; Minute 5: Zone 3 reached*) [00:09:01, 00:09:15].
* **Granular Milestone Funnel Telemetry:** Track every single progression step in analytics (e.g., *Purchased Upgrade 1*, *Purchased Upgrade 2*, *First Plot Expansion*) [00:10:27, 00:10:39]. A steep drop-off between two consecutive steps (like only 60% buying Upgrade 1 and 26% upgrading plots) pinpoints an exact pricing wall or UI discoverability failure [00:10:44, 00:11:20].
* **Structured Tester Progression Logs:** Have dedicated playtesters grind a fresh save for 2–3 hours and log exact timestamps, costs, and friction notes for every single tier unlock, then feed those logs alongside your economy numbers to balance mid- and late-game pacing [00:11:43, 00:12:17, 00:12:40].

### Application to *Quantum Forge: Blade Evolution*
* **Addressing Our Known Gap (`design-decisions.md`):** We currently rely on manual Studio playtests without automated economy telemetry or milestone funnels[cite: 17].
* **Actionable Upgrade:**
  1. **Instrument Progression Funnels:** Log `AnalyticsService` custom funnel events for:
     * `First_Strike` -> `First_SweetSpot` -> `First_Vent` -> `Forge_ScrapFang` -> `Forge_RivetEdge` (Wave 1 Complete) -> `First_Drone_Built` -> `First_Ascension`.
  2. **Fresh-Save Pacing Audit:** Run a timed 15-minute fresh-save benchmark recording exact timestamps for each of the 3-blade mystery waves (`ADR-031`) to ensure there is no dead "waiting wall" between Wave 1 (*Rivet Edge*) and Wave 2 (*Iron Vigil*)[cite: 17].

---

## 3. Launch-Ready Monetization & Economy Protection

### Video Breakdown
* **Cross the Player-to-Payer Threshold Early:** Include ultra-low-cost, stackable entry products (5–9 Robux tier multipliers) and repeatable consumables (e.g., instant timers/boosts) right at launch to convert non-payers into payers [00:16:30, 00:16:45, 00:17:04].
* **Launch High-Ticket "Whale Sinks" & True Limiteds on Day 1:** Waiting two weeks to add high-Robux limited items or prestige utilities cuts ARPDAU in half (jumping from ~1.0 to ~2.0 once added) [00:14:42, 00:14:58, 00:17:42].
* **Never Sell Raw Currency Packs That Break the Curve:** Selling direct cash packs or spawning overpowered items too frequently fries the game's progression economy and kills long-term retention [00:15:25, 00:15:36].

### Application to *Quantum Forge: Blade Evolution*
* **Addressing Our Known Gap (`Monetization IDs = 0`):** Our `STORE` tab currently displays `SOON` across all rows[cite: 17].
* **Actionable Upgrade:**
  1. **No Raw Star-Matter / Aether Cash Packs:** Keep our store strictly focused on **permanent multipliers** (`2x Star-Matter`, `Auto-Vent AI`, `Fast Forge`), **consumable timed buffs** (`Instant Overdrive` 15-min boost), and **cosmetic/utility status** (`VIP Quantum Aura +1 Drone Slot`) so whales accelerate their loop without skipping the blade progression ladder.
  2. **Add a 5–9 Robux "Starter Forge Pack" Entry Product:** Give new players a low-friction first purchase (e.g., `15m 2x Overdrive + 25 Aether`) to cross the player-to-payer threshold early [00:16:45, 00:17:04].

---

## 4. In-Game Player Feedback & Live-Server QA

### Video Breakdown
* **In-World Feedback Prompt:** Place an accessible feedback prompt/mailbox directly in the game so players can submit bug reports and balance complaints, then batch-summarize submissions to spot recurring friction [00:18:11, 00:18:21, 00:18:31].
* **Always Test on a Published Live Test Place:** Studio playtests miss replication delays, DataStore race conditions, and live network edge cases [00:19:07, 00:19:14]. Use a dedicated published staging place with real testers to catch economy exploits and mobile UX issues before pushing updates to main [00:19:07, 00:19:38].

### Application to *Quantum Forge: Blade Evolution*
* **Actionable Upgrade:**
  1. **Add a Compact Feedback Button in Top HUD / Settings:** Route player submissions to a webhook or DataStore log so real player friction (like UI clipping or confusing mechanics) is captured immediately.
  2. **Enforce Live Staging Verification (`ADR-025`):** Always validate session locking, `InsertService:LoadAsset` mesh loading (`ADR-026`), and mobile `UIScale` touch targets on a published Roblox test place rather than relying solely on local Studio runs[cite: 17].

---

## 5. Summary Action Checklist for *Quantum Forge*

| Priority | System | Action Item |
| :--- | :--- | :--- |
| **P0** | **Onboarding** | Gate later tutorial modals (`Vent`, `Fleet`, `Ascend`) behind contextual state triggers instead of front-loading them [00:06:34]. |
| **P0** | **Telemetry** | Add `AnalyticsService` funnel tracking across Waves 1–3, First Vent, First Drone, and First Ascension to catch pacing walls [00:10:27, 00:13:20]. |
| **P1** | **Monetization** | Wire real Developer Product & Gamepass IDs into `AssetManifest`, including a 5–9 Robux starter consumable, while avoiding raw currency packs [00:15:36, 00:17:04]. |
| **P1** | **QA & Feedback** | Add a lightweight player feedback form and verify all UI scaling and mesh loads on a published Roblox staging place [00:18:17, 00:19:07]. |

```
> Shipped in ADR-034. Implementation, measurements and open items: `build-log-remake-04-05.md`.
