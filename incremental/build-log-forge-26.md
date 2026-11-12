---
type: build-log
status: shipped in Studio, not yet published
updated: 2026-11-12
aliases:
  - forge-26
tags:
  - build-log
  - store
  - design
  - monetization
---

# Forge 26 - The store becomes a shelf

ADR-119 made the store look like a catalog, but it was still eight rows poured
into the generic two-column distributor. The distributor balanced columns by
height, so the boost shelf started wherever the passes ended. The store needed
its own scroll hint because the offers did not fit, and every offer had the same
left-to-right shape. On an account that owns every pass, five full-width green
BOUGHT plates were the loudest line on the page.

This pass moves the store to its own page and gives it a shelf.

## What changed

| Surface | Before | After |
| --- | --- | --- |
| Section type | host section, two-column distributor | `page = true`, full-bleed card |
| Structure | 8 rows, one after another | 5 pass cards on one shelf, 3 boost cards under them |
| Scroll | 28px footer strip and `MORE BELOW` hint | none; every offer is on screen |
| Masthead | 64px section banner | 86px store masthead with a 44px gold mark, 30px title, trust chip |
| Pass card | 92px row | 246px vertical card |
| Boost card | 92/172px row | 188px vertical card |
| Badge | 60/112px well | 64px well on every card |
| Action plate | 100x38 or 124x48, right anchored | full-width 40px plate at the card foot |
| Owned pass | green plate, green row border | `equipped` plate, faint emerald card border |
| VIP | row with a tag | raised gold card with a halo and `BEST VALUE` |
| Instant Overdrive | row with a tag | raised aether card with a halo and `STACKABLE` |
| Paid clock | HUD chip only | also a live card fact: `LIVE xN / nM LEFT` |

## The two shelves

The top shelf is permanent. Five cards across, 14px apart, each with a 64px
badge, a 20px name, a 14px sentence, a value line and a 40px emerald plate. The
bundle is the hero: raised fill, gold border, gold halo, `BEST VALUE` tag, and a
fact line built from the live pass prices (`R$ 236 SEPARATELY`).

The bottom shelf is disposable income. Three cards across from the same system,
shortened to 188px: badge and name share the top row, the pitch is one line, and
the fact line sits above the plate. Instant Overdrive is the hero here: raised
fill, aether border, aether halo, `STACKABLE` tag. While a charge is running its
fact line becomes `LIVE x6 / 43M LEFT`, so the store itself answers whether the
hour applied. The rail-foot chip counts the same paid clock.

Owned passes keep the kit's `equipped` plate and take a faint emerald border.
VIP keeps its gold border, because the bundle's identity is more useful than its
receipt. The shelf header prints `n / 5 OWNED` and turns emerald at five.

## Structural changes

- `ShopView.luau` is rebuilt around `init(canvas, x, y, w, h)`, `card()` and
  `layout()`. It owns the card, both shelves and the state paint. It no longer
  receives rows from `Sections`.
- `Sections` registers `store` as `page = true` and no longer requires
  `ShopView`. The old `init` and `destroy` hooks are gone.
- `Main.client` builds the store before the nav host, passes `store` into
  `Sections.init` beside `crates`, re-flows it on resize, and destroys it with
  the rest of the UI.
- `ShopView.layout()` places both rows from the live content width. It does not
  use the distributor, so a resize cannot move a card into the other column.

## Verification

- `selene src`: 0 errors, 0 warnings, 0 parse errors.
- `rojo build default.project.json`: succeeds.
- Studio, Client, 1212x578 viewport: card 1121x446 at (83,66).
- Five pass cards 210px wide at y=156, 177 tall (246 design).
- Three boost cards 357px wide at y=365, 135 tall (188 design).
- Every `TextLabel.TextFits` is true.
- Boost badge ends at y=423, description starts at y=426, so the old badge /
  description overlap is gone.
- `TextService:GetTextSize` at the narrowest card width: longest boost pitch
  275px against 343px, longest pass title 127px against 187px, every fact line
  under 187px.
- Switching to fleet hides the store card; switching back restores it.
- The dev account owns all five passes, so the page paints `BOUGHT` and
  `5 / 5 OWNED` and VIP still shows `BEST VALUE`.
- No new console errors.

## Still open

- The purchase prompt did not render again in this Studio session, even from a
  direct client `PromptProductPurchase` call. The page's button fires and the
  server received `product:instantOverdrive`, so the page path is proven; treat
  the missing dialog as a Studio session limit. The one-hour reset still needs a
  real receipt on the user's side.
- Touch and gamepad have not been checked on the full-bleed page, the shelf
  plates or the trust chip.
- Persistence is still MOCK in Studio (DataStore 401), so `overdriveStacks` has
  not survived a save and reload.
- The 22 VFX sheets are still unuploaded; unrelated to this page.
