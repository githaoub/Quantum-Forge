---
type: build-log
status: shipped
updated: 2026-11-12
aliases:
  - forge-17
tags:
  - build-log
  - crates
  - ceremony
  - balance
  - audio
---

# Forge 17 - Six clicks to a secret

The ceremony had the right beats and the wrong body. The crate opened on one
press, the light was painted with rectangles, the top pool handed out a Quantum
every six rolls, and a locked pool snapped back to the last unlocked one before
the player could read it. This pass fixes the sequence, the light, the odds and
the browse.

## What changed

| Surface | Before | After |
| --- | --- | --- |
| Single crate | 1 click | 6 clicks: five shakes, then it breaks |
| Triple crate | 3 clicks | 6 clicks: two shakes per crate |
| Ten-pull | 10 clicks | 10 clicks, one per crate (unchanged) |
| Result | One `COLLECT n` for the whole batch | One `CLAIM i / n` per copy, best first |
| Rail | Decoration | Receipts: current copy gets a cursor, claimed ones grey to `CLAIMED` |
| Light column | Two 4px Frames with a gradient | Three soft sprites driven by one strength value |
| Burst | Nine flat 2px lines | Soft halo, four-point star, eight sparkle needles |
| Floor | None | A soft pool under the crate, lit from the first frame |
| Sounds | `impact_explosion_03` and `swordslash` in the mix | Removed; the kit is wood, metal, click and air |
| Locked pools | Snapped back to the server's crate | Browsable: model, name, blurb, odds, `LOCKED` keys |
| Singularity Quantum | 16% | 2% |
| Celestial Quantum | 8% | 2% |

## The click ladder

`strikeTotal` is 6 for a single or a triple and 10 for a ten-pull, computed from
the batch the server actually charged. `perCrate = strikeTotal / batch` is 6, 2
and 1. Each press maps `beat` onto the crate's six-step rattle, so a triple's
second hit is already the heavy one. The last press of the pull starts the
0.62s sealed hold.

The click count is the suspense. One press that opens a box is a button; six
presses that shake it is a lock, and the player can feel the difference before
the payoff.

## The claim queue

`result.results` is the queue. The best copy is claimed first, because that is
the payoff the reveal just showed; every other copy follows in roll order. Each
claim is its own beat: the chip greys to `CLAIMED`, the room flashes the copy's
rarity, a spark cone fires, `Sfx.claim` rings, and the key hides for 0.3s while
the hero swaps. The ten-pull ends on the tenth claim, which is also the exit:
white flash, shockwave, `Sfx.claimAll`, and the overlay closes behind it.

Claiming is not a formality. The old `COLLECT 10` key took the whole batch in one
press and closed the screen on the same frame, so the afterglow was a receipt
the player never read.

## The light

The old column was a 4px Frame with a vertical gradient, and the ray fan was
nine 2px Frames. Both looked like what they were. The new light is built from
three `rbxasset://` textures that ship with the client and were checked with
`PreloadAsync`:

| Texture | Use |
| --- | --- |
| `particles/smoke_main.dds` | column wash, core, source halo, floor pool |
| `particles/sparkles_main.dds` | four-point star and the eight needle shafts |
| `whiteCircle.png` | rejected: a hard flat disc, not a glow |

`paintBeam(strength)` moves all four layers from one number. The column is faint
at rest, grows with every strike, opens to 0.75 for the hold, flashes to 1 on the
reveal and fades under the burst.

## The sound

`impact_explosion_03.mp3` is a gunshot transient and `swordslash.wav` is a blade
whip. Both were removed from the kit, not just from the crate: the low body is
now `hit.wav`, the crack is `snap.mp3`, the ring is `metal.ogg`, the tick is
`clickfast.wav` and the air is `impact_water.mp3`. The crate break is a crack
plus a wooden knock; the heartbeat is a pitched-down thud; the claim is a rising
ping pair over the ring of the blade.

## Locked pools

The page sent `crate` to the server even when the pool was locked. The server
refused, the next sync painted the old crate back, and the browse lasted one
tick. `pick` now sends nothing for a locked pool, and the sync loop keeps the
local selection while the selected pool has no quote. Verified live on a profile
at 2.9M run Star-Matter: the Singularity Vault mounted, printed `OPEN AT
400.00B` / `0% THIS RUN` and three `LOCKED` keys, and stayed on screen.

## Balance

The top crate's Quantum weight was 16%, which made the rarest blade a routine
drop and the codex a formality. The columns now move weight into Astral and Void
without handing out the top rarity:

| Crate | Scrap | Forged | Astral | Void | Quantum |
| --- | ---: | ---: | ---: | ---: | ---: |
| Standard | 55 | 29 | 13 | 2.6 | 0.4 |
| Void | 33 | 38 | 20.2 | 7.6 | 1.2 |
| Quantum | 18 | 34 | 34 | 12.5 | 1.5 |
| Celestial | 9 | 30 | 41 | 18 | 2 |
| Singularity | 4 | 22 | 47 | 25 | 2 |

The expected rarity rank still climbs every rung (1.63 to 2.99); the top crate
now pays a Quantum once in fifty rolls, not once in six.

## Round 2 - the rail walks and the crate sings

The first pass ordered the claim queue best-first but painted the rail in roll
order. On a ten-pull the best copy was often the last chip, so the gold outline
sat on the last sword while the hero read `COPY 1 OF 10`. The first claim looked
arbitrary. The rail is now painted in the same order as the queue: best first,
then roll order. The gold edge and the bottom rail are a cursor, not a
permanent badge, so they move to the next chip on every claim; claimed chips
grey to `CLAIMED` and the best keeps its gold tag until it is taken.

The clicks are a do-re-mi ladder now. Six clicks play do re mi fa sol do; ten
play do re mi fa sol la ti do sol do. `index` is the click within the whole
pull, so a triple's two clicks per crate continue the phrase instead of
restarting it. The sealed hold's riser climbs the top of the scale and stops on
ti, and the reveal resolves to a C-major arpeggio (do sol do mi sol do). The
claim is a sol-do fourth; the final claim adds a low do. The anvil keeps its
pentatonic ladder on purpose: it is a different instrument.

`Main.client` no longer fires the result fanfare while `CrateReveal.isOpen()`,
so the ceremony owns the resolution. Before this, the server answer played the
fanfare during the shake, before the reveal.

### Round 2 verification

| Thing | State |
| --- | --- |
| Rail order | x10: first chip is the best copy, hero matches it, the rest follow in roll order |
| Outline | After one claim, chip 1 is `CLAIMED` and grey, chip 2 carries the 3px gold edge and gold rail, hero and `CLAIM 2 / 10` match |
| Full claim | Nine remaining presses close the overlay on the tenth; the rail clears with the scrim |
| Scale | `Sfx.crateTick` probe: click 1 = 1.000 (do), click 2 = 1.122 (re); click 6 of six = 2.007 (do) with a 0.500 low do |
| Riser | `Sfx.riser(5)` sets 1.260 / 1.340 / 1.494 / 1.676 / 1.886 (mi fa sol la ti) |
| Fanfare | `Sfx.forge` sets 0.500 / 0.749 / 1.260 / 1.498 / 2.000 (do sol mi sol do) |

## Verification

| Thing | State |
| --- | --- |
| Static | `selene src/` 0 errors, 0 warnings, 0 parse errors; `rojo build -o verify.rbxlx` succeeds |
| x1 | `0 / 6` at rest, six clicks, `SEALED` at 6/6, reveal |
| x3 | `0 / 6`, six clicks with two per crate, two crates left at 3/6 |
| x10 | `0 / 10`, ten clicks, ten chips, `CLAIM 1 / 10` |
| Claims | x3: best claimed first, hero swaps, chips grey to `CLAIMED`, closes on the third |
| Claims | x10: ten claims, overlay closes on the tenth |
| Locked browse | Singularity selected at 2.9M run SM, model + odds + `OPEN AT 400.00B` + `LOCKED` keys, no snap-back |
| Odds | Singularity prints Scrap 4 / Forged 22 / Astral 47 / Void 25 / Quantum 2 |
| Sound | No `IMPACT` or `SWISH` reference remains in `Sfx.luau` |

## Still open

- The marketplace listings exist; a live purchase was still not attempted.
- The crate meshes are still primitives. The light sells them; a sculpted mesh
  would sell them harder, and the upload is still blocked.
