# Forge 34: the units are marks, and the rack is a ladder

Date: 2026-11-13

## The complaint

Four things in one pass:

1. The fleet's hull rack read as decoration. Five dark rows with a name and a
   count did not say "pick a drone", and the buy keys printed a bare
   `LOCKED  ·  110`, which does not tell a player what 110 counts.
2. The daily cards spelled out `SM`, `CORES` and `AETHER` while the top bar
   already draws a mark for every one of them. The owner does not want the
   names in the UI at all, except on the top bar count.
3. The purge key carried two words, an anvil-adjacent glyph and a payout line
   that could collide with it. It also had to turn red when it was pressable,
   so the aether mark on the payout is visible.
4. Every anvil click was raising
   `Vfx:252 invalid argument #1 (Vector2 expected, got Vector3)`. The server
   strike still landed, but the client aborted the rest of the feedback path,
   so the flash, the sound, and the payout never ran for a real mouse press.

## What changed

### Fleet

- Each rack row carries a 38px `ViewportFrame` with the same
  `DroneModelBuilder.mount` the hero uses, spinning at 0.9 rad/s with the 15°
  bank. Five previews per page, each cleaned up through `rackPreviewCleanups`
  before the card is destroyed.
- The buy keys are two lines. `BUILD 1` or `BUILD 10` sits on top, and an
  aether mark plus the price sits under it. A locked hull reads `LOCKED` over
  `110 DRONES REQUIRED`: the registry's real gate, now explained instead of
  changed.
- The selected row keeps its 2px glow border, so the preview and the selection
  state agree.

### Currency marks

- `Icons.currency` builds the vector mark and then lays the uploaded top-bar
  art over it once `ContentProvider:PreloadAsync` resolves. One preload per
  asset, then every later row swaps in the same frame. The vector stays as the
  first-frame and missing-upload fallback.
- `UiKit.currencyRow` is the inline unit: a holder, a 24px mark canvas, and an
  automatic-width label. Every price and payout that used to say `SM` now uses
  it.
- Converted surfaces: the daily headline grows a crystal under each number and
  the reward rows become mark-and-number lines; the crates rail and roll keys,
  the fleet buy keys, expedition payouts, salvage caches, player wallet cells,
  leaderboard rows and tabs, the tech header and the ascend payout line.
- Inline marks are 16px design. The top bar keeps its 32px PNG badges and its
  captions, which is the one place the owner asked to keep the names.

### Purge key

- Pressable: `redDeep` plate, 3px red ring, white 32px vent mark centred at
  y=32, and the aether mark + payout on their own line at y=52. The payout no
  longer shares the icon's box.
- Locked: slate plate, outline ring, grey mark and `REACH 85%`. The two states
  keep the same 380x88 footprint, so the console never shifts.
- The mark is a tray with three plumes, not the anvil.

### Strike fix

`InputObject.Position` is a Vector3. `ForgeView` now converts it to a Vector2
before calling `strike`, and `Vfx.screenPoint` is only ever given a Vector2.
This restores the cursor payout, the flash, the sound and the crit path for a
real mouse press, not just for the `QF_Dev` seam.

## Evidence

Studio, 1212x576 game area, canvas 1686x720 at 0.719.

- Fleet: five previews with 27, 45, 53, 77 and 99 parts. Their orientation
  advanced 30.9° to 31.8° per 0.6s sample. Both buy keys read `LOCKED` over
  `110 DRONES REQUIRED` at 256 and 300 design px wide. `BuyDrone` art sat at
  x=528.7 with the price at x=540.2, a 2px gap under the face.
- Daily: 5 currency rows and 18 mark canvases in the overlay; no visible
  `SM`, `AETHER` or `CORES` label. Day 5's unit mark measured 18 design px and
  its first row 16px, with the 110px rule clear of both.
- Crates: the four open pools show a star mark and a price; the locked
  Singularity hides the row and shows `20% TO OPEN`; roll-key costs centred at
  0.0px offset.
- Purge ready: plate `(176, 52, 52)`, ring `(255, 107, 107)` at 3px, white mark
  32 design px, payout row at y=460.4 physical with a 3px gap to the mark.
  Locked: slate plate, `5, 7, 11` ring at 2px, `REACH 85%`.
- Strike: a dev strike produced `+28.09K` and `CRIT  +140.43K`, both
  `TextFits=true`; the console held no `Vfx` or `ForgeView` errors afterward.
- `selene src`: 0 errors, 0 warnings, 0 parse errors.
  `rojo build default.project.json -o verify.rbxlx`: success.
- Saved to the real place as version 333, note
  `Forge 34: currency icons, fleet previews, purge key, strike fix`. Not
  published.

## Open

- A human look at the 16px marks on the owner's screen. The uploaded art is
  detailed for that size; if it reads as a smudge, the single knob is the
  `iconSize` at each call site, and the vector fallback is already the same
  glyph.
- The handbook and store blurbs still name the currencies in prose. An
  explainer has to name its subject; labels no longer do.
- Unchanged blockers: DataStore 401 / MOCK mode, the purchase prompt, blade
  meshes falling back to primitives, 22 unuploaded VFX sheets, and the
  touch/gamepad passes.
