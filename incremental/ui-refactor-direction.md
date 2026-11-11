---
type: design
status: shipped
updated: 2026-11-11
aliases:
  - ui-refactor-direction
tags:
  - ui
  - direction
  - foundry
---

# UI refactor: Foundry Instrument

The direction note for the Forge 13 UI pass. It is kept as the rationale for the
rules, not as a build order: the build order is done, and the authoritative token
values live in `Theme.luau` and the ADR log. Where this note and an ADR disagree,
the ADR wins.

The old build was "chunky simulator": warm wood chrome, 3px black outlines on
everything, a gradient banner on every card, white GothamBlack with a hard black
stroke, and every element the same weight. It was consistent and it read as a
template, because nothing was more important than anything else.

## The one-line brief

A machine face, not a dashboard. The forge is an instrument the player operates:
steel, rules, a gauge, one hot accent, figures in mono, and exactly one object that
matters on each screen.

## Rules

1. **One focal object per screen.** Forge: the blade. Crates: the crate. Fleet: the
   drone. Runes: the blade bay. If two things compete, one is wrong.
2. **Five surfaces, never a gradient.** `void` (screen bed), `backdrop` (behind the
   app), `panel` (region), `panelRaised` (pressable), `panelSunken` (inset track).
   Depth comes from value, not from bevels.
3. **One border weight at rest.** 1px `stroke` on containers; 1px `strokeBright`
   on the pressed target. The 3px outline survives only on the primary key of a
   screen (the strike key), where it reads as a stamped plate, not decoration.
4. **Sharp corners.** Radius 3 on controls, 4 on rows, 6 on panels, 8 on the
   largest plates. Rules are square. Rounded corners were half of the "mobile app"
   read.
5. **No gradients on chrome.** Flat fills. The only gradient allowed is light
   falling on the workpiece: the stage wash, the blade glow, the crate seam.
6. **Left-aligned type.** Centering is reserved for a key face and a big figure.
   Every region opens with an eyebrow (13px, faint) and a title (22–30px), both
   flush left, with the body underneath.
7. **Mono for every figure.** Prices, yields, timers, counts, ranks. Gotham for
   words, Code for numbers, no exceptions.
8. **One accent per region.** Ember `#FF7A2F` for action, cyan for the vent/cool
   signal, gold for currency, quantum for tech and runes. Two accents in one block
   is only legal when one is a rarity colour describing an item.
9. **Empty space is material.** A 40px gutter is not a bug. The old build filled
   every gap, which is why it read as noise.
10. **Motion is a response, not decoration.** 120ms hover, 90ms press, one entrance
    per screen. No looping glow, no pulsing borders. Animation goes through
    `UiKit.tween` / `Theme.tween` and respects `Theme.reducedMotion()`.

## Palette

These are the `Theme.Color` names, not a parallel palette. Use the token.

| token | use |
| --- | --- |
| `void` | screen bed |
| `backdrop` | the sheet behind the app |
| `panel` | region panels |
| `panelRaised` | keys, rows, modal plates |
| `panelSunken` | inset tracks, gauge beds |
| `stroke` | 1px container rule |
| `strokeBright` | pressed target rule |
| `strokeFaint` | dividers inside a panel |
| `text` | primary |
| `textDim` | secondary |
| `textFaint` | eyebrows, captions |
| `actionOrange` | the action accent (ember) |
| `cyan` | information, vent, aether |
| `gold` | currency, Star-Matter |
| `quantum` | tech, runes, crates |
| `good` / `warn` / `danger` | owned/claimed, heat warning, lean/destructive |

Rarity colours do not change: they are item identity, not chrome. `Theme.onColor`
picks ink or white for text on a saturated fill; a key never carries white text on
a light fill.

## Type

| role | font | size |
| --- | --- | --- |
| hero figure | GothamBold | 46 |
| screen title | GothamBold | 30 |
| region title | GothamBold | 22 |
| subhead | GothamBold | 18 |
| body | GothamMedium | 16 |
| small | GothamMedium | 15 |
| micro | GothamMedium | 14 |
| tiny / label | GothamBold, uppercase | 13 |

13 design px is the floor (ADR-035). `Theme.Font.Black` is GothamBold; the old Black
face was the source of the shouty headings. Figures use Code at the same rung as the
words around them, one step larger when they are the point of the block.

## Composition per surface

- **Top bar**: full width, identity left, three currency readouts, then one verb
  cluster (ASCEND, DAILY). It is chrome only; navigation is not in it.
- **Left rail**: 92px wide, six 56px items, icon over label, active item carries an
  ember bar on its left edge and white text. The 108px foot carries the live rate
  and the utility row. `Layout.NAV_H` is 0.
- **Section header**: one 64px repainted plate with an accent mark, title, kicker
  and index (`RUNES / 6`). Page sections (forge, crates) hide it and draw their own
  64px banner because their cards are full-bleed.
- **Forge**: the stage runs to the bottom edge with no scrim or deck. Three controls
  float over it: STRIKE 240×64 bottom-left (ember, 3px outline), CORE HEAT 380×78
  centered (label, 30px figure, 12px ruled bar, one caption), PURGE 136×64
  bottom-right. There is no roll column; rolling lives on CRATES (ADR-078).
- **Crates**: crate is the focal object, the pool rail is inside the section, odds
  are one stacked bar with a five-column legend, and the two roll keys differ in
  weight: `ROLL` 40% quiet, `ROLL x10` 60% dominant in the crate accent.
- **Fleet**: 208px two-column hero. A 42% drone stage on the left; identity, three
  figures and `BUILD 1` / `BUILD 10` on the right. The ladder prints full rung names,
  not three-letter codes.
- **Runes**: a 470px blade bay (blade, rank, mastery meter, three 84px sockets, live
  socketed-bonus grid, Void Shard wallet) beside the shelf.
- **Store**: two counted group headers at 15px (`GAME PASSES / 5`,
  `BOOSTS & UTILITY / 4`) over a two-column catalog.
- **Modals**: one flat plate on a dim scrim, title top-left, close top-right, content
  under a 1px rule. No banner overhang. The vault is a full-screen grid with a
  permanent inspector and the batch bar order `EQUIP BEST`, `MELT MULTIPLE` →
  `CANCEL`, `SELECT DUPES`, `CLEAR`.

## What was refused

- A serif or art-deco direction: Roblox serif rendering at 13px is mush, and the
  codex already carries the "artifact" feeling through colour.
- Keeping the horizontal tab strip: six equal tabs were the strongest "template"
  signal, and the rail buys back vertical space on a screen that needs it.
- Restyling tokens only: the surface language was half the problem, the equal card
  grids were the other half.
- A gradient banner per card: one repainted 64px section banner replaced seven.

## Verification

The pass is done when `selene src/` is 0/0/0, `rojo build -o verify.rbxlx` writes,
and a live session at desktop and narrow widths shows one focal object per screen,
no text under 13 design px, and no white text on a light fill. The measurements are
in `build-log-forge-13.md`; the decisions are ADR-076…080.
