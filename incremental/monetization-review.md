# Monetization review

Date: 2026-11-13

## Sources

- Roblox, [Monetization](https://create.roblox.com/docs/production/monetization):
  players downvote strategies they dislike; appointment timers that can be
  removed or brought forward are unpopular on Roblox; promotions must be
  transparent and must not use false urgency; paid random items need
  `PolicyService`.
- Roblox, [Monetization foundations](https://create.roblox.com/docs/production/game-design/monetization-foundations):
  items are durable or consumable, enhancement or expression; the shop should
  be integrated, contextual and inviting; a season pass with free and premium
  tracks is one of the three pillars, alongside items and the shop.
- Wikipedia, [Video game monetization](https://en.wikipedia.org/wiki/Video_game_monetization):
  paid loot boxes are regulated in several markets; dark patterns have drawn
  enforcement; the EU published virtual-currency principles in 2025 and
  California AB 2426 requires clear licence disclosure.

The short version of "good monetization":

1. The free game is complete. Money buys speed, convenience or expression, not
   access to the core loop.
2. The player knows what they are buying, in plain words, before the prompt.
3. No artificial friction is sold back. A timer that exists only to be skipped
   is a tax on patience.
4. Randomness is transparent, pity is visible, and Robux does not buy the
   random roll without the policy checks.
5. The price ladder is coherent. A bundle should not make every single item
   look like a mistake.
6. The goods match the fantasy of the game. A forge sells forge things.
7. It is measured: view, prompt, purchase, repeat. Without that, price changes
   are guesses.

## What we have

| Offer | Price | What it does | Verdict |
| --- | --- | --- | --- |
| VIP | 119 | Every pass, badge, aura | Genuine 236 to 119 bundle, but it undercuts every 59 pass |
| 2x Star-Matter | 59 | Doubles all SM income, forever | Clear, permanent, fits the loop |
| Fast Forge | 59 | Doubles accepted clicks per second | Clear, permanent, fits the loop |
| Auto-Vent AI | 59 | Vents at 85% automatically | Convenience, does not remove content |
| Eternal Forge | 59 | +25% SM income, forever | Clear but the smallest effect at the same price |
| Starter Forge Pack | 9 | 500K Aether + 20 min of 2x SM | Raw currency, skips the early loop, contradicts the store badge |
| Instant Overdrive | 25 | x3 SM for an hour, stacks with no cap | Honest copy, but uncapped power |
| Express Salvage | 35 | Instantly completes an expedition | Sells back a timer, poor value next to a permanent pass |

The crate system is soft-currency only. Odds are printed, pity is shown, and
Robux cannot buy a roll directly. That is the strongest part of the economy.

## What is good

- **No content is paywalled.** Every system, blade, drone and ascension is
  reachable without Robux.
- **The copy is concrete.** Descriptions say what the multiplier is, how long
  it lasts, and that the clock resets. The VIP comparison is a real sum of the
  four individual passes.
- **No fake urgency.** There are no countdowns, no "last chance", no rotating
  fake discounts.
- **The random system is transparent.** Five pools, printed odds, visible pity.
  No Robux to roll.
- **The shop is integrated and contextual.** Category tags (`INCOME`, `CLICKS`,
  `HEAT`), owned count, real prices and a permanent row before consumables.

## What is not good enough

### 1. The store makes two claims that are false

The store badge says `NO CURRENCY PACKS`, and the banner says
`Every offer multiplies the run you already have`. The first product on the
page is 500K Aether for 9 R$. That is a currency pack, and it is a flat grant,
not a multiplier. A player who notices will trust the next claim less. Fix the
badge and the banner, or change the product.

### 2. The Starter Pack skips the best part of the game

A first drone costs 7 Aether. The next rungs start at 900, 42K and 2.6M. Five
hundred thousand Aether buys the first three rungs and a piece of the fourth on
day one. The pack is priced to convert, but it removes the first hour of
discovery that the new guide is trying to teach. It is the single most damaging
product in the store.

### 3. VIP makes the individual passes look overpriced

All four other passes cost 236 together. VIP costs 119 and includes them plus
the badge and aura. The discount is real, but it means a player who buys one 59
pass has made a worse decision than a player who waits for VIP. Either raise
VIP to about 199, or limit it to three passes plus the badge, or price the
individual passes lower.

### 4. Express Salvage sells back a timer

Roblox's own guidance says timers that can be removed or brought forward are
unpopular with its users. The product is also 35 R$ for one expedition, which is
more than half the price of a permanent pass. Replace it with something durable:
a second expedition slot forever, or a permanent 25% shorter expedition. If it
stays, price it at 9 to 15 R$ and make it clear it is a one-shot.

### 5. Overdrive has no cap

Each charge is x3 for an hour, charges multiply, and thirty charges are x90.
The copy is honest about it, which is good, but an uncapped paid multiplier on
a game with Aether and Star-Matter leaderboards is a whale lever. Cap the
stack at five charges (x15), or make extra charges add time instead of
multiplying. Keep the one-hour clock reset; that part is clear.

### 6. There is no expression product and no season pass

Every offer is enhancement. The game has a strong blade and forge identity, so
one cosmetic (anvil trail, blade aura, forge skin) at 49 to 99 R$ is the
cheapest low-risk addition. A free plus premium season track is the missing
Roblox pillar and the best retention lever, but it needs enough content to
fill a season. Do not ship a thin one.

### 7. It cannot be measured yet

The purchase prompt does not render in this Studio session, DataStore writes
return 401 and the profile runs MOCK, and no funnel has been read. Until those
are fixed, no price change can be called an improvement. The `Funnel` module
already exists; the events need to cover store open, card view, prompt and
purchase result.

## Verdict

**Ethically, this is above the Roblox average. Commercially, it is not good
enough yet.**

The foundation is right: no paywalled content, no Robux loot boxes, printed
odds, real bundle math, no fake urgency. Those are the hard things to get right,
and they are already right.

The product mix is the weak part. One raw currency pack undermines the first
hour, one timer skip copies a pattern Roblox users dislike, one bundle makes the
individual passes look like bad deals, and one boost has no ceiling. The store
also has no expression item and no season track, so it earns from a narrow
slice of players.

## Order of work

1. Remove the false claims (`NO CURRENCY PACKS`, `Every offer multiplies`).
2. Rework the Starter Pack so it does not skip the first three drone rungs.
3. Cap Overdrive stacking.
4. Replace Express Salvage with a durable expedition upgrade.
5. Reprice VIP or the individual passes.
6. Add one cosmetic.
7. Fix DataStore, the purchase prompt and the funnel.
8. Add a free plus premium season track once there is content to fill it.

Do not add a ninth product before steps 1 and 7. More offers on an unmeasured,
unpersisted store is noise.
