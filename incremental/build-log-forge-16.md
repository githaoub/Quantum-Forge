---
type: build-log
status: shipped
updated: 2026-11-11
aliases:
  - forge-16
tags:
  - build-log
  - crates
  - store
  - monetization
  - ceremony
---

# Forge 16 - The afterglow

The full-screen ceremony made the reveal a moment. It did not make a batch feel
like a batch: a x3 or x10 still ended on one sword and a key that closed the
screen on the press. This pass gives the result an afterglow, gives the sealed
beat a real hold, and fixes the two interface bugs that made the vault and store
feel unreliable.

## What changed

| Surface | Before | After |
| --- | --- | --- |
| Batch result | Best copy only | Copy rail: every sword, best in gold, staggered in |
| Collect | Closes on the first press | Locked 0.55 s, then a claim beat and a masked cut |
| Sealed hold | 0.30 s, no light | 0.62 s, light column, vignette closes, riser, two heartbeats |
| Crate strike | Rattle tick only | Crack + wooden knock, heavier on the last crate, rumble |
| Reveal | One flash, one ring | Rarity flash, white flash on rank 4+, ray fan, dust, rumble |
| Blade in the result | Turntable could catch it edge-on | Holds the hero yaw, drag to orbit, `spin = 0` |
| Vault / codex / boards | Clicking empty panel space closed the sheet | Only the gutter closes; panel clicks are ignored |
| Locked pools | Selectable, model mounted, keys read `LOCKED` | Unchanged behaviour, now the only definition of unlocked (quote, not lifetime) |
| Store | Placeholder ids, every row `SOON` | Real passes and products, live ids, prices |
| VIP | R$499, below Eternal Forge | R$1699, above Eternal Forge, row prints `Buy separately: R$ 1946` |
| Eternal Forge | Last in the pass list | Second row, directly under VIP |
| Starter pack | 25 Aether, 15 min | 500K Aether, 20 min |

## The rail

`paintResult` now knows every copy: the server already sends `results` in roll
order. The result viewport gives up 64 px to `CopyRail`, which draws one 58 px
chip per copy (92 px max, 6 px gaps, 980 px total). The chip carries the blade
name, its rarity, a 3 px rarity bar, and a gold `BEST` plate on the copy the
server marked. Chips fade in at 35 ms intervals.

The collect key is deliberately late: `RESULT_LOCK = 0.55` seconds. The first
version appeared on the same frame as the flash, which meant a player holding
the mouse down skipped the thing they had just paid for.

## The claim

`COLLECT` is a verb now. It hides the key, fires a shockwave and sparks, shakes
the stage, plays `Sfx.claim`, pulses the pad, and writes a white `Vfx.flash` on
the layer above the scrim. The overlay closes 0.14 s later, while that flash is
still at full brightness. The player sees the celebration, not the `Visible =
false` frame.

## The hold

The sealed beat is 0.62 s. In that window the beam lights, the vignette grows
from 170 to 230 px on the sides and 110 to 160 px on the top and bottom, a
five-note riser climbs the same pentatonic ladder as the strike, two heartbeats
land 200 ms apart, and the pad builds in three steps. The hold only runs once
per pull, after the last crate, so a ten-pull does not pay it ten times.

## The bugs

**Empty panel space closed the vault.** The panels are `Frame`s and Frames do not
sink pointer input, so a click on a gap between cards fell through to the dimmer
`TextButton`. `ModalShell` and `InventoryModal` now ignore a dimmer click whose
pointer is inside the panel's absolute rect. Verified live: clicking the empty
banner space of the vault and the codex left both open.

**Melt had a confirm, but the user could not find it.** The batch `MELT n` key
and the inspector `MELT` key both call `Modals.confirm`. Verified live: `MELT A
SELECTION` / `Melt 2 copies into 26 Scrap?` / `MELT ALL`.

## The store

The Open Cloud script created all nine listings. Creating a listing is free;
only a purchase charges Robux. The ids are patched into `MonetizationConfig`, so
the rows show `R$ 1699`, `R$ 1499`, `R$ 99`, `R$ 199`, `R$ 149` and the four
product prices instead of `SOON`.

| Item | Price | Why |
| --- | --- | --- |
| VIP | 1699 | Bundle: every pass, below the 1946 sum |
| Eternal Forge | 1499 | Strongest permanent, above every single pass |
| Fast Forge | 99 | Entry door |
| 2x Star-Matter | 199 | Broad multiplier |
| Auto-Vent AI | 149 | Chore removal |
| Starter Forge | 5 | First purchase |
| Instant Overdrive | 25 | Burst |
| Emergency Vent | 15 | Rescue |
| Express Salvage | 35 | Time |

## Verification

| Thing | State |
| --- | --- |
| Static | `selene src/` 0 errors, 0 warnings, 0 parse errors; `rojo build -o verify.rbxlx` succeeds |
| Store ids | 9 listings created; rows read `R$ ...`, no `SOON` |
| VIP row | `R$ 1699` with `BEST VALUE` and `Buy separately: R$ 1946.` |
| Pass order | VIP, Eternal Forge, Fast Forge, 2x Star-Matter, Auto-Vent |
| Locked pools | Code-verified: the rail selects, the model mounts, the keys read `LOCKED`, `roll` returns before it sends `forge`. The test profile has every pool open, so this was not walked live |
| Store scroll | Canvas 692 over a 373 px window; wheel moved 0 to 100 |
| Vault click-through | Click inside the panel leaves `vaultOpen` true |
| Codex click-through | Click inside the panel leaves `codexOpen` true |
| Melt confirm | `Melt 2 copies into 26 Scrap?` / `MELT ALL` live |
| x3 rail | 3 chips, best marked, `COLLECT 3` |
| x10 rail | 10 chips, best marked, `COLLECT 10` |
| Claim | One press closes the overlay; flash persists over the cut |
| Haptics | Guarded by `IsMotorSupported`; not heard on a pad in this session |

## Still open

- A ten-pull with fewer than ten free vault slots now quotes the trimmed tier
  (x3 price for 3 slots). The note says `Vault space: rolling 3 of 10`. There is
  still no "melt to make room" shortcut on the crates page.
- The ray fan is nine 2 px frames. It is hidden by reduce motion, but it is still
  a full-screen overlay on a low-end phone.
- The marketplace listings exist, but a live purchase was not attempted: that
  would spend the user's Robux.
