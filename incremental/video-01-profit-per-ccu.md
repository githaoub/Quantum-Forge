---
title: Video analysis 01 — the 1.9M Robux blueprint
status: source material — annotated 2026-11-09
tags:
  - roblox
  - strategy
  - research
---

### Executive Summary: The 1.9M Robux Blueprint

In the video *"How My 100 Player AI Roblox Game Made 2,000,000 Robux (NO BULLSH*T)"*, creator **Tap** breaks down the unvarnished reality of building profitable Roblox games using AI agents without needing massive development teams, complex 3D map building, or millions of concurrent users (CCU).

His primary case study is his debut game, **Incremental Piece** (an anime incremental clicker released in April 2026), which generated **1.9 million Robux (~$7,000 USD)** and sustained residual monthly revenue (90,000+ Robux/month) despite peaking at only **100 CCU** and currently averaging just 5 active players.

---

## 1. The Myth of CCU vs. Profitability

* **The Trap of Oversaturated Niches:** Beginners frequently flood trending, low-barrier clones (e.g., *"Steal an Egg"*, *"Steal a Fossil"*, or endless animal-feeding copycats). These niches are fiercely competitive, require massive ad budgets to bypass Roblox's publishing and discovery filters, and suffer from abysmal conversion rates because players are bombarded with hundreds of identical thumbnails.
* **Low CCU, High Margin:** You do not need 100,000 CCU to build a lucrative game. By targeting specific, high-retention genres—such as **incremental/clicker games**—and structuring aggressive, progression-critical monetization, a game with just 50–100 CCU can yield thousands of dollars in passive income.

---

## 2. The Three Essential Tools for AI-Driven Development

Tap rejects expensive third-party GUI kits and subscription scams, advocating for a lean, highly optimized AI agent stack:

| Tool | Role & Workflow Integration |
| --- | --- |
| **Claude (Pro / Max tiers)** | The core logic, coding, and game systems engine. Scaling from Pro to Max tiers (or utilizing multi-account parallel agent workflows) allows you to generate robust scripts, UI components, and game loops. |
| **Obsidian** | Acts as a **persistent workflow memory vault**. Instead of starting from scratch every project, you instruct Claude to ingest and query your Obsidian vault—storing transcripts of successful developer strategies, past code modules, VFX concepts, and balancing formulas across games. |
| **Figma (+ Figma MCP)** | Essential for rapid asset production. Connected via MCP, multiple Claude agents can generate hundreds of game assets (e.g., 250+ anime cards in under an hour), stunning user interfaces, and high-converting marketing thumbnails. |

---

## 3. Game Selection & Genre Strategy: Why Incremental Games Win

* **Building Constraints:** Incremental games (inspired by hits like *Fruit Piece Incremental* and *JJK Incremental*) bypass the need for complex, hand-crafted 3D map building, making them ideal for solo developers leveraging AI models (like DeepSeek Coder/Flash or Claude) to handle code and UI.
* **Unique Mechanics Over Clones:** While copying a successful concept is a safe starting point, you must introduce a unique hook. For instance, *Incremental Piece* differentiated itself from standard clickers by introducing a complex **summoning system** and distinct progression tabs that immediately signaled higher production value to players.

---

## 4. Marketing, Thumbnails, and the "Video Trap"

* **Thumbnail Volume & QA Testing:** Never rely on a single AI-generated thumbnail. Generate **100+ thumbnail variations**, conduct strict visual QA tests (comparing them side-by-side on different screens), and isolate the top 10 highest-performing options for ad campaigns. Games like *Survive the Kaiju* achieved exceptional CTRs (5%+ across hundreds of thousands of impressions) by clearly communicating the core fantasy and survival stakes.
* **The Mandatory Video Preview Mistake:** Tap highlights a critical pitfall from his game *Anime Stickman RNG*: spending hundreds of dollars on ad clicks with terrible player-to-play conversion rates (e.g., 1,000 clicks but only 25 players). The culprit? **Failing to include a gameplay video on the game page.** Players need to instantly visualize themselves in the gameplay loop through an active video preview before committing to play.

---

## 5. Strategic Monetization for Low-CCU Success

To extract high revenue from a small player base, monetization must tie directly into player progression urgency:

* **Automation & Convenience:** Offering game passes like **Autoplay** and **2x Generation Speed**.
* **Gacha & Progression Bundles:** Selling resource packs (gems, summoning scrolls, reroll tokens) that alleviate grinding friction in competitive environments, compelling dedicated players to convert into paying users.

---

## 6. What survived contact

Added 2026-11-09, after building [[game-design-brief]] to this brief. The summary above stays
as written — it is a record of what the video said. This section is what happened
when it was applied.

| Recommendation | Outcome |
| --- | --- |
| **Obsidian as persistent workflow memory** | Correct, and under-used. The vault held the plan and then went stale for the whole build; the design reasoning ended up in the repo's `design-decisions.md` instead, where it does not travel to the next project. The advice is right and was followed badly. |
| **Claude as the core logic engine** | Correct. Every system — server, client, economy, UI — is generated. No third-party GUI kit was needed. |
| **Figma + Figma MCP for asset batching** | **The one that failed.** "250+ cards in under an hour" assumes a paid seat and unlimited API calls. Reality: View-only seat, 20 calls per month. The pipeline cannot exist, so it was cut entirely and replaced with 40 locally-generated icons (Python + Pillow). *Check tool access before designing a pipeline around it.* |
| **Incremental as the genre for solo + AI** | Correct, and more than he says. No map building, no animation, no combat — but it does not follow that the UI is cheap. The HUD is the game, and it took longer than the economy maths. |
| **"Unique hook over clone"** | Correct. The sweet-spot heat band is the only thing that distinguishes this from a generic clicker, and it took several passes to find. The first two ideas (cooling pumps, combat stances) were unimplementable. |
| **Monetize convenience and speed, not access** | Adopted as-is. Auto-Vent AI and Skip Thermal Lockout sell back time the player already lost. Neither gates anything a free player cannot reach. |
| **Cosmetic gacha** | Not built. A gacha needs an art pipeline; there isn't one. |
| **100+ thumbnail variants with visual QA** | Not started. Highest-value unexecuted advice in the document. |
| **Gameplay video on the game page** | Not started. He is specific that omitting this burned real ad spend — 1,000 clicks into 25 players. It is free to avoid and has not been avoided yet. |

### The transferable lesson

The video's advice is mostly sound. The failure mode was not the advice — it was
**assuming a tool capability without verifying it**, then discovering the gap after
the design depended on it. Figma's seat limits were knowable in the first five
minutes. The same class of error is worth watching for elsewhere: Roblox publishing
fees, upload quotas, and the plugin bridge all have access constraints that are cheap
to check and expensive to discover late.
