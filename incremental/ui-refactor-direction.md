---
type: design
status: live
updated: 2026-11-11
aliases:
  - ui-refactor-direction
tags:
  - ui
  - direction
---

# UI refactor: Foundry Instrument

Direction note for the full UI pass. The old build was "chunky simulator": warm
wood chrome, 3px black outlines on everything, a gradient banner on every card,
white GothamBlack with a hard black stroke, and every element the same weight. It
was consistent and it read as a template, because nothing was more important than
anything else.

## The one-line brief

A machine face, not a dashboard. The forge is an instrument the player operates:
steel, rules, a gauge, one hot accent, figures in mono, and exactly one object
that matters on each screen.

## Rules

1. **One focal object per screen.** Forge: the blade. Crates: the crate. Fleet:
   the drone. If two things compete, one is wrong.
2. **Three surfaces, never four.** `well` (cut in), `shell` (the region),
   `raised` (the thing you press). Depth comes from value, not from bevels.
3. **One border weight.** 1px `stroke` on containers, 1px `strokeBright` on the
   pressed target. The 3px black outline survives only on the primary key of a
   screen, where it reads as a stamped plate rather than as decoration.
4. **Sharp corners.** 3-4px on controls, 6px on panels, 0 on rules. Rounded
   corners were half of the "mobile app" read.
5. **No gradients on chrome.** Flat fills. The only gradient allowed is light
   falling on the workpiece (stage wash, blade glow).
6. **Left-aligned type.** Centered copy is reserved for a key face and a big
   number. Every region opens with an eyebrow (13px, faint) and a title
   (22-30px), both flush left, with the body under them.
7. **Mono for every figure.** Prices, yields, timers, counts. Gotham for words,
   Code for numbers, no exceptions.
8. **One accent per region.** Ember for action, cyan for information, gold for
   currency. Never two accents in the same block unless one is a rarity colour
   describing an item.
9. **Empty space is material.** A 40px gutter is not a bug. The old build filled
   every gap, which is why it read as noise.
10. **Motion is a response, not decoration.** 120ms hover, 90ms press, one
    entrance per screen. No looping glow, no pulsing borders.

## Palette

| token | value | use |
| --- | --- | --- |
| void | #06070A | screen bed |
| sheet | #0A0C10 | backdrop behind the app |
| well | #0B0E13 | inset tracks, gauge beds |
| shell | #13171D | region panels |
| raised | #1D232C | keys, rows, modal plates |
| line | #262E3A | 1px container stroke |
| lineBright | #3A4454 | pressed target stroke |
| text | #F4F7FB | primary |
| textDim | #C8D0DC | secondary |
| textFaint | #8E99A9 | eyebrows, captions |
| ember | #FF7A2F | the action accent |
| cool | #7BE4FF | information, aether |
| gold | #FFC13D | currency, star-matter |
| quantum | #A78BFA | tech, runes, crates |
| good | #5BE39A | owned, claimed |
| warn | #FFB454 | heat warning |
| danger | #FF6B6B | overheat, destructive |

Rarity colours do not change: they are item identity, not chrome.

## Type

| role | font | size |
| --- | --- | --- |
| hero figure | GothamBlack | 46 |
| screen title | GothamBold | 30 |
| region title | GothamBold | 22 |
| subhead | GothamBold | 18 |
| body | GothamMedium | 16 |
| small | GothamMedium | 15 |
| label | GothamBold | 13, uppercase |

13 design px is still the floor. Figures use Code at the same rung as the words
around them, one step larger when they are the point of the block.

## Composition per surface

- **Top bar**: identity left, three currency readouts, then a single verb cluster
  (ASCEND, DAILY). Utility keys move into the left rail footer as a small row;
  they are tools, not verbs, and they were drowning the real actions.
- **Left rail**: six sections, icon over label, active item carries an ember bar
  on its left edge and white text. Below the sections: the live rate, then the
  utility row.
- **Section header**: eyebrow (section kicker), title, and one right-aligned fact
  (count, price, state). No banner, no plaque, no centred title.
- **Forge**: blade stage takes the left two thirds. The right third is an
  instrument column: heat gauge, yield figure, roll block, crate chip. The strike
  key sits under the stage, full width of the stage, and is the only element on
  the screen with a heavy outline.
- **Crates**: crate is the focal object, pool list is a left rail inside the
  section, odds are a single stacked bar plus five labelled rows (not five equal
  cards), and the two roll keys differ in weight: single is secondary, ten is
  primary.
- **Modals**: one flat plate on a dim scrim, title top-left, close top-right,
  content under a 1px rule. No banner overhang.

## What was refused

- A serif or art-deco direction: Roblox serif rendering at 13px is mush, and the
  codex already carries the "artifact" feeling through colour.
- Keeping the horizontal tab strip: six equal tabs were the single strongest
  "template" signal, and the rail buys back 60px of vertical space on a screen
  that needs it.
- Restyling tokens only: the surface language was half the problem, the equal
  card grids were the other half.

## Order of work

1. Tokens (`Theme`) and primitives (`UiKit`): every screen changes at once.
2. Chrome: top bar and left rail.
3. Forge, then Crates.
4. Fleet, Runes, Tech, Store.
5. Modals: vault, codex, boards, trade, daily, handbook, settings, starter.
6. Verification: selene, build, live capture at desktop and narrow.
