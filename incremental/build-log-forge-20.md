---
type: build-log
status: shipped in Studio, not yet published
updated: 2026-11-12
aliases:
  - forge-20
tags:
  - build-log
  - forge
  - onboarding
  - tutorial
  - hints
---

# Forge 20 - The guide crosses the whole loop

Forge 19 stopped teaching at the first blade. A player learned to strike, purge,
build a drone and roll once, then the notes walked away before the vault, the
rune shelf or the core sink had been named. This pass extends the same
work-order card through the rest of the loop and adds a quiet hint layer for the
decisions that keep opening after the guide is gone.

## What changed

| Surface | Before | After |
| --- | --- | --- |
| Guide length | 8 notes, ended on the first roll | 19 notes through vault, runes, tech, top bar and store |
| Card size | 360x176 | 360x212, plus a `NEXT` key on reading steps |
| Vault | Never mentioned | `OPEN THE VAULT`, `EQUIP BEST`, `BACK TO THE FORGE` |
| Roll ceremony | Not mentioned | `KEEP THE BLADE` waits for `COLLECT` |
| Cache | Not mentioned | `CLAIM THE CACHE` after the first drone |
| First-run cache | Random rarity, could be a 2:45 Prime | Always the instant Scrap Cache until the guide is answered |
| Runes | Not mentioned | Tab, then a card about mastery, sockets and per-blade runes |
| Tech | Not mentioned | Tab, then a card about permanence across an ascent |
| Top bar | Not mentioned | Brackets on the utility bank, one self-explanatory line |
| Store | Not mentioned | Tab highlight and a line that nothing there is required |
| Ascend before the balance | Toast refusal, no sheet | Sheet opens with the confirm painted `NEED 1.00B SM` and inert |
| Guide layer Z | 20, below every modal | 80, above the vault and the blocking cards |
| After the guide | Tab glows only | Edge-triggered toasts for ascend, daily, cache, rune socket and drone rung |
| Toast collisions | First of a burst was evicted | One nudge at a time, only onto an empty rail, 3s apart |

## The nineteen notes

1. `STRIKE THE BLADE` - brackets on the stage; advance at 85 heat.
2. `PURGE THE CORE` - ring on the purge key; advance on the `vent` event.
3. `SAVE FOR A DRONE` - ring on the heat block; advance when Aether covers the
   first rung.
4. `OPEN THE FLEET` - rail tab; advance when that tab is active.
5. `BUILD A DRONE` - `BuyDrone`; advance when the fleet count grows.
6. `CLAIM THE CACHE` - first slot holding a cache; advance when the rack count
   drops. The body swaps between crack, cracking and ready.
7. `OPEN THE CRATES` - rail tab; advance when that tab is active.
8. `ROLL A BLADE` - `RollOne`; advance when the blade count grows.
9. `KEEP THE BLADE` - `COLLECT`; advance when the ceremony closes.
10. `OPEN THE VAULT` - top-bar `VaultButton`; advance when the sheet is open.
11. `EQUIP THE BEST` - `VaultEquipBest`; advance on the press itself, because the
    strongest copy can already be the equipped one.
12. `BACK TO THE FORGE` - `VaultClose`; advance when the sheet is closed.
13. `OPEN THE RUNES` - rail tab; advance when that tab is active.
14. `HOW RUNES WORK` - reading card over `MasteryCard`; `NEXT`.
15. `OPEN THE TECH TREE` - rail tab; advance when that tab is active.
16. `WHAT TECH IS FOR` - reading card over `TechHeader`; `NEXT`.
17. `THE TOP BAR` - brackets on `Actions`; `NEXT`.
18. `THE STORE` - tab highlight; `NEXT`, with no purchase and no forced visit.
19. `THE LOOP IS YOURS` - `FINISH` ends the run.

Gated steps are skipped when their subject is absent, so a cache note cannot
flash when no cache dropped. The vault, rune and tech cards are placed beside
the controls and clamped to the canvas, and the guide layer now sits above the
vault sheet so the `EQUIP BEST` note is readable while the vault is open.

## The first cache

The cache lesson needs a cache the player can finish. A random Prime carries a
2:45 crack timer, which parks the guide behind a countdown after the first
drone. While `guideSeen` is false, `addSalvageMeter` drops the instant Scrap
Cache. Once the guide is finished or skipped, the normal rarity table returns.

## The locked ascent

`ASCEND` now opens the same confirmation sheet whether or not the balance is
there. When it is short, the body prints the threshold and the current total,
and the confirm key is painted as a locked plate with the requirement on its
face. The key has no handler in that state, so a click cannot send `ascend`.
The server still refuses a direct request with "Not enough Star-Matter this
run", so the lock is visible on the client and real on the server.

## The hint layer

`Nudges.luau` watches the payload after the guide:

- an ascent is affordable
- the daily is ready
- a salvage cache is claimable
- a rune is owned and a socket is free
- a drone rung the player does not own is affordable

Each line is edge triggered and latched, so a state that stays open says one
thing once. The drone line names the best rung in reach and marks the lower ones
as covered, because one line about the ladder is enough. The layer starts muted:
the guide owns the screen until it starts or decides the account has seen it.
While muted, no edge is consumed, so a daily that was already ready when the
guide ended still speaks afterwards.

The toast rail holds two. Three simultaneous nudges used to evict the first, so
the layer now speaks only onto an empty rail, one line every 3 seconds. Studio
showed the completion receipt first, the daily next, and the new drone rung
after that, with nothing pushed off the rail.

Tab glows live in `Sections.refreshTabBadges`, not in the nudge layer. Fleet
glows for an affordable drone or a claimable cache; tech glows for an affordable
node; runes glow when a rune can be socketed. The ascend and daily buttons keep
their breathing strokes in `HudController.step`. An expedition that comes back
now gets a receipt toast in `Main.onFeedEvent`.

## Verification

- `selene src`: 0 errors, 0 warnings, 0 parse errors.
- `rojo build`: succeeds.
- Studio, Client, fresh join: the starter card is dismissed, the guide reads
  `GUIDE 01 / 19`, and the stage gets four gold brackets.
- Studio, Client: 42 strikes reach 85, purge pays `+6 Aether`, auto-vent on the
  second bar reaches the drone price, FLEET opens step 4, `BUILD 1` reaches the
  cache note.
- Studio, Client: the first cache reads `SCRAP CACHE` with no timer. One tap
  turns it into `CLAIM`, the card body changes to "The cache is ready", the
  second tap pays `+300 Aether` and the guide moves to CRATES.
- Studio, Client: CRATES, `ROLL`, then the `KEEP THE BLADE` card. Six clicks on
  the crate expose `COLLECT`; the ring sits on it and the press advances to the
  vault.
- Studio, Client: VAULT opens over the forge, the guide card stays readable
  above it, `EQUIP BEST` advances, `X` closes and advances to RUNES.
- Studio, Client: RUNES, `NEXT`, TECH, `NEXT`, the brackets land exactly on the
  `Actions` frame, `NEXT`, the STORE tab is highlighted, `NEXT`, and `FINISH`
  sets `guideSeen` and `tutorialCompleted` and hides the card and ring.
- Studio, Client: at 250 Star-Matter the ascend sheet opens, the body reads
  "needs 1.00B", the confirm reads `NEED 1.00B SM`, and a click on it leaves the
  sheet open with the balance unchanged.
- Studio, Client: after `SKIP`, the completion receipt is alone at 1.6s, the
  daily nudge lands at 5.6s, and the scrap drone line lands at 9s. No toast was
  evicted.

## Still open

- The blade meshes still fail to load in Studio (`Requester does not have
  permission for Asset`), so every blade renders through the primitive recipe.
- DataStore is still in mock mode (`HTTP 401`); progress does not persist.
- The 22 VFX sheets are still unuploaded.
- The full guide on a fresh account without the dev passes has not been played;
  the dev account owns auto-vent, fast-forge and every boost.
- The ascend-ready confirm path is code-read, not played: 1B Star-Matter is out
  of reach in a Studio session.
- Touch and gamepad placement of the longer cards has not been checked.
- The crate gates, the roll floor and the music loop still have no end-to-end
  playthrough.
