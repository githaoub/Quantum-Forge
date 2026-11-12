---
type: build-log
status: shipped in Studio, not yet published
updated: 2026-11-12
aliases:
  - forge-29
tags:
  - build-log
  - ftue
  - social
  - ui
---

# Forge 29 - Four taps to the loop, and the room has names

The first join opened two full-screen cards at once: a welcome card and the
first note of a nineteen-step guide. A player who does not read had to dismiss a
wall before touching the anvil, and the guide then spent most of its run
explaining the vault, runes, tech and the store to someone who had not yet
earned a second blade. This pass cuts the first minute to four notes, makes them
opt-in, and gives the server a face: a roster of everyone in it.

## The first join is a sequence

The welcome card lands first and owns the screen. `START FORGING` closes it.
Only then does a small consent card ask `WANT A QUICK TOUR?`, with `SHOW ME` and
`I'LL PLAY`. The X counts as `I'LL PLAY`. A decline writes `guideSeen`, so the
question is asked once per account, and the GUIDE key still opens the handbook
with `REPLAY VISUAL GUIDE` at the bottom.

The offer waits one beat after the starter fades before it appears. The two
cards cannot share a frame. `Modals.shell` also clears the prompt's dismiss hook
when another card takes its place, so a welcome card that lands late cannot close
the question and record "I'll play" for a player who never answered.

## Four notes, one action each

The guide is now `strike`, `purge`, `drone`, `done`:

| Card | Title | Body |
| --- | --- | --- |
| 1 | TAP THE BLADE | Fill the heat bar. |
| 2 | PURGE | Turn the heat into Aether. |
| 3 | BUILD A DRONE | Purge until you have 7 Aether. / Press BUILD 1. It earns while you do nothing. |
| 4 | THAT IS THE LOOP | Tap. Purge. Build. Roll. Repeat. |

The card is 344x172, down from 360x212, because the copy no longer needs three
lines. `SKIP` keeps its name on every card and the closing card carries one big
`DONE`, so the escape hatch never has to be decoded at the last step.

The drone card opens FLEET itself 0.9 s after the price turns affordable. The
old chain had a separate "open FLEET" card, which is a navigation instruction
dressed as a lesson.

## Why there is no roll card

A standard roll is 2 700 SM on a fresh account. At a base yield of 1 to 2 per
strike that is several minutes of tapping, so a roll step would either stall the
guide behind an unaffordable price or demand 100 presses before it could start.
The last card names rolling instead, the CRATES tab badges when a roll is
affordable, and the handbook holds the cache, roll, vault, equip, rune, tech, top
bar and store lessons.

## The guide steps out of the way

The guide layer moved from `ZIndex 80` to 40. The short guide never asks the
player to act inside a panel, so a vault, codex, roster or trade sheet simply
covers it. `ModalShell` now counts open shells, and the guide's 10 Hz tick hides
the card, ring and badge while that count is above zero, then paints them again
on the next tick after the close. The first build had the card floating over the
roster it was covering, which is worse than no note.

## The welcome card

The card shows the Star-Matter crystal instead of the x2 pass badge, because the
card is about the currency being doubled. The art is the owner's PNG, uploaded
to the creator account as `130744451781228`, and the drawn bolt stays underneath
as the fallback. The bolt only fades once `IsLoaded` is true.

The duplicate `60 MINUTES` line under the big `x2` is gone, and the note is one
sentence: `Strikes and drones pay double. The clock is already running.`

One bug found on the way: an `ImageLabel` at `ImageTransparency = 1` never
loads, so the first version kept the fallback forever. The art now starts opaque
under the fallback and the fallback fades over it.

## The roster

`CREW` is a new top-bar key between RANKS and TRADE. It opens a 980x640 panel
with a ranked list of everyone in this server and a card for the selected player:
the best blade in the shared preview, Star-Matter, lifetime Star-Matter, Aether,
drones, ascensions, copies, playtime, and the top three blades with power and
variant. `CHEER` sends a one-off toast with no currency attached.

The server builds the answer. `roster` reads each live profile from
`DataManager` and returns only the public slice; a client cannot send a stat
because the request carries none. Settings, purchases, favourites and trade
state stay private. Requests are budgeted at one per player per second, the panel
asks on open and every ten seconds, and it repaints only when the signature
changes. `cheer` checks that the target is a real player in this server, refuses
a self-cheer, and rate-limits the sender to one per eight seconds.

## The crate kicker

`COPY 1 OF 6` sat on the stage's top edge, where the black wash ate it. It is now
44 design px above the stage and one type step up, `Theme.Text.Tiny` in
`textSecondary`: `POOL 01 / 05 · STANDARD FORGE CRATE` at the top, then
`COPY n OF m` in the same object during the click ladder.

## The two labels that did not fit

The bar went from seven 50px keys to eight 46px keys, and two labels lost
letters. `TextService:GetTextSize` at 13px GothamBold: `BOARDS` 52px, `PEOPLE`
47px, `RANKS` 41px, `CREW` 36px. The keys are `RANKS` and `CREW` now, and all
eight faces report `TextFits = true`. `Layout.MIN_WIDTH` dropped from 1320 to
1300 with the narrower keys.

The consent card also exposed an old modal miss: the close key sat at `-30` from
the right edge, so its 38px face ended 8px outside the card and read as a red
square floating beside the panel. It is at `-44` now, which leaves the face 4px
inside and still lifts it 9px over the banner corner.

## Studio evidence

- Fresh join: only the welcome card was visible. `Art.IsLoaded = true`,
  `ImageTransparency = 0`, fallback bolt and notch at transparency 1. Copy read
  `2X STAR-MATTER`, `FOR YOUR FIRST 60 MINUTES`, `x2`, and the one-sentence note.
- After `START FORGING`: the consent card only, guide still hidden. After
  `SHOW ME`: `STEP 1 OF 4`, `TAP THE BLADE`, `Fill the heat bar.`, ring on the
  stage at 1479x473 (0.72 scale).
- Fifty strikes reached heat 85 and moved to `STEP 2 OF 4`, `PURGE`. A purge
  paid 6 Aether and moved to `STEP 3 OF 4`, `BUILD A DRONE`. The passive vent
  took the balance to 12, the tick selected FLEET, and the card switched to
  `Press BUILD 1. It earns while you do nothing.`
- A real click on `BUILD 1` built the drone and moved to `STEP 4 OF 4` with
  `DONE`. A real click on `DONE` cleared the card, returned the top-bar key to
  `GUIDE`, and the server reported `tutorialCompleted = true`,
  `guideSeen = true`.
- A real click on `CREW` opened the roster; the guide card and ring were
  `Visible = false` while it was up, and came back on the tick after the X.
- The roster showed one row with the YOU tag. The card mounted `RUSTED CLEAVER`,
  read `PLAYED 4m 6s`, six figures at 0 except copies 1, and one top-blade cell
  at `x1.00`, `STANDARD`.
- All eight top-bar faces fit. The crate kicker sat at screen `y = 34`, 780 wide,
  `TextSize = 14`, `TextFits = true`.
- `selene src` reports 0 errors, 0 warnings, 0 parse errors; `rojo build` writes
  the place file.

## Not done

- A second real player has not been in the server, so the roster has only been
  seen with one row and the cheer path has not been clicked end to end.
- The touch and gamepad layouts have not been checked against the eight-key bar.
- The roll card is gone from the first minute; whether a player finds CRATES on
  their own is a retention question the next telemetry pass should answer.
