# Build log: the forge, the vault, and the crate

Shipped 2026-11-10. The design record is `ADR-043` in
`incremental/design-decisions.md`; this is the working log of what changed and
what was measured, in the order it was built.

The pass had two halves that landed in one session: the RNG forge (banners, five
rarities, five variants, Scrap, rerolls, the sound kit and the settings sheet) and
the vault overhaul that replaced the sidebar inventory with a full-screen room.

## What shipped

| ask | shipped as |
| --- | --- |
| widen the UI | canvas 1280 -> `Theme.DesignWidth` 1360, side panel 468 -> 500, forge card 770 -> 818 |
| inventory out of the sidebar | `InventoryView.luau` deleted, `InventoryModal.luau` added as a canvas overlay |
| group duplicates | `InventoryModel.luau`: `group`, `meltable`, `meltValue`, `variantRank` |
| equip best | `ProgressionService.equipBest` + `VaultEquipBest` |
| multi-melt | `ProgressionService.salvageMany` + `SELECT DUPES` -> `MELT n +N` |
| a detail surface | `VaultDrawer`: nine stat rows, EQUIP / REROLL / MELT |
| drop the SFX text key | `MuteButton` removed; sound lives in the settings sheet only |
| a gear instead of `SET` | `gearIcon()`: eight teeth, a ring and a bore in 10 primitives |
| a crate roll | `CrateStage` in `ForgeView`: slam, six beats, hold, shatter |

## Files

New:

- `src/client/InventoryModel.luau` - copy grouping and the melt rules, shared by
  the grid, the drawer and the footer.
- `src/client/InventoryModal.luau` - the vault: toolbar, card grid, drawer,
  lifecycle, and the seven action functions the buttons and the Studio seam share.
- `incremental/build-log-forge-07.md` - this file.

Deleted:

- `src/client/InventoryView.luau` - the sidebar Blades tab. Nothing requires it.

Changed:

- `src/client/Theme.luau` - `DesignWidth = 1360`.
- `src/client/Layout.luau` - `SIDE_WIDTH = 500`, with the why in the field doc.
- `src/client/UiKit.luau` - `screen()` fits against
  `camera.ViewportSize - GuiService:GetGuiInset()` instead of `gui.AbsoluteSize`;
  `gradient()` dedupes its stop list and refuses to build a `ColorSequence` from
  one keypoint (the boot-fatal `ColorSequence: requires at least 2 keypoints`).
- `src/client/SidePanel.luau` - `VAULT` key, gear key, `Blades` tab gone,
  `TABS = { Fleet, Runes, Tech, Store }`, default tab `Fleet`.
- `src/client/ForgeView.luau` - `buildRollBar`, `buildCrate`, `revealRoll`,
  `ForgeView.roll`, `rollAnchor`, `isRolling`, `isUnlocked`, `rollNote`.
- `src/client/Main.client.luau` - `InventoryModal.init` / `destroy`, and the
  `QF_Dev` seam (Studio only).
- `src/client/TutorialController.luau` - the forge lesson rings `RollButton`
  instead of the deleted `ForgeRoll`, and no longer sends the player to a tab.
- `src/server/ProgressionService.luau` - `equipBest`, `salvageMany`.
- `src/server/Main.server.luau` - `equipBest` / `salvageMany` actions; the
  `inventory` request now returns `forgedAt`.
- `src/shared/Types.luau` - `InvEntry.forgedAt` (optional).

## The five defects this pass found

Recorded because each one was invisible until something measured it.

1. **`UiKit.gradient` could kill the boot.** A single-colour stop list throws
   `ColorSequence: requires at least 2 keypoints`, and the throw lands inside the
   UI build, so every panel created after the cosmetic call simply never exists.
   Found because the whole side panel was missing from a playtest. The helper now
   dedupes and pads.

2. **`refreshFooter` looked for a child that `UiKit.button` does not make.** The
   melt button kept reading `MELT SELECTED` with two copies selected. `button`
   keeps its label on the `TextButton`; `actionButton` puts it on a child named
   `Face`. Both shapes are handled now.

3. **`forgedAt` was never in the inventory payload.** The drawer's FORGED row
   read `not recorded` for every copy, including a blade forged four seconds
   earlier. The request handler returned `uid`, `id`, `variant` and stopped.

4. **`selectDupes` skipped the group holding the equipped copy.** The most common
   duplicate in the game is a second starter blade, which always shares a group
   with the equipped one, so the button did nothing for a new player. The group
   is selected now; `meltable` drops the equipped uid from the picks.

5. **The drawer's MELT refused groups that hold the equipped copy.** Same root
   cause, one layer down: the handler was keyed off `group.repUid`, which *is* the
   equipped uid for those groups. It now targets `detailMeltTarget()`.

## Measured

Layout, at 0.7194 canvas scale (design px in brackets):

```
canvas        978 x 518   [1360 x 720]
forge card    589 x 414   [ 818 x 576]
side panel    360 x 414   [ 500 x 576]
roll plate     92 x  33   [ 128 x  46]
vault key      43 x  24   [  60 x  34]
gear key       26 x  24   [  36 x  34]   10 primitives
objective      378 x 22   [ 526 x  30]
tabs          114 x 36 each, four of them, Fleet first
vault panel   841 x 435 rendered, 86% x 84% of the canvas
vault card    193 x  85, three columns in the grid
```

The crate sequence, sampled every 0.1s on a live forge:

```
0.1s   visible, y 0.59 -> drop in        seam 0.60
0.4s   rotation  14                      seam 0.52
0.7s   rotation  84                      seam 0.38
0.9s   rotation 210                      seam 0.22
1.1s   rotation 294                      seam 0.06
1.2s   rotation 294 (hold)               seam 0.00
1.4s   hidden - shatter, reveal
```

Wire-level checks, each driven through the same functions the buttons call:

```
vent + 120 clicks       sm   0 -> 180.5      locked false
forge roll              sm 180.5 -> 130.5    inv 1 -> 2   pity 0 -> 1
salvageMany x2 uids     inv 3 -> 1           scrap 0 -> 12
selectDupes             picks 2              worth 12
meltSelected            dialog "Melt 2 copies into 12 Scrap?"
commitMelt              inv 5 -> 3           scrap 0 -> 12
drawer meltDetail       dialog "Melt one of 2 copies of Rusted Cleaver (Standard) into 6 Scrap?"
commitDetailMelt        inv 2 -> 1           scrap 0 -> 6
equipBest               toast "Equipped Coil Shard", equippedUid moves
inventory request       forgedAt present on new copies, 0 on the starter
```

Verification commands:

```
selene src/                       0 errors, 0 warnings, 0 parse errors
rojo build -o verify.rbxlx        built
```

## What the ticket did not ask for and got anyway

- **The `QF_Dev` seam.** Studio's `VirtualInputManager` needs the `RobloxScript`
  capability, so nothing in this environment can click a button. The seam is a
  `BindableFunction` on the ScreenGui that runs inside `Main.client`'s VM, so it
  calls the real handlers rather than copies of them. `RunService:IsStudio()`
  only, destroyed with the GUI. It is the reason four of the five defects above
  were found instead of shipped.
- **`ForgeView.rollNote()` and `isRolling()`.** A refused roll is silent by
  design, which makes "nothing happened" indistinguishable from "the remote
  dropped". The note records the guard that fired.
- **`forgedAt` in the inventory payload.** One field, and the drawer stops lying.

## Still open

- Store listings: the API key lacks `game-pass:write` / `developer-product:write`
  (403 `Scope not authorized`), so every id is `0` and the rows read `SOON`.
- All 26 blade meshes return `User is not authorized to access Asset` in the
  current Studio session; the procedural fallback renders.
- 22 VFX sheets are generated and margin-checked but not uploaded:
  `python scripts/upload_assets.py --vfx --creator user:1416845247`.
- Cache and set-emblem art not generated; prompts are in
  `user-manual/16-salvage-art-prompts.txt`.
- `stylua`, `wally` and `luau-lsp` are not installed, so there is no formatting or
  static-analysis pass beyond `selene`.
- No screenshot of any of this: `screen_capture` returns null on this build.
