# Build log: the drone ladder, the full-bleed stage, and the hand-drawn icons

Shipped 2026-11-10. The design record is `ADR-044` in
`incremental/design-decisions.md`; this is the working log of what changed and
what was measured, in the order it was built.

The pass was a refinement, not a new system: strip the helper copy, replace two
text keys with icons, give the forge a stage instead of a black box, and turn the
flat 50-drone fleet into a five-rung ladder that never runs out. Every number
below was read out of the running place at 0.7194 canvas scale, then divided back
into design pixels.

## What shipped

| ask | shipped as |
| --- | --- |
| no helper copy | expedition note, rune shard footer, shop purchase note, vault hint all deleted |
| icons, not text keys | `backpackIcon()` 40x34, nine frames; `gearIcon()` 36x34, eleven frames |
| the viewport is the button | `StrikeButton` 746x450 transparent full-bleed `Active` layer over a 486px stage |
| no black box | `buildHud`: 148px scrim holding heat rail, streak pips, yield, prompt |
| a fleet that keeps going | `DroneRegistry`: five rungs, no cap, rising efficiency |
| five rungs on screen | five 83x50 ladder keys with owned count and unlock meter |
| each rung looks different | per-tier hull/glow, rung hardware, mesh only on rung 1 |
| a 3D preview per rung | `DroneModelBuilder.mount(viewport, tierId, { distance, centre })` |

## Files

New:

- `src/shared/DroneRegistry.luau` - the five rungs, the pricing curves, the
  unlock gates, and the one clamp that keeps a price finite.
- `incremental/build-log-forge-08.md` - this file.

Changed:

- `src/shared/Types.luau` - `ProfileState.fleet`, `FleetEntry`, `SyncPayload.fleet`,
  `droneTier` on the action payload. `drones` and `droneCap` gone.
- `src/shared/Config.luau` - `DroneCostBase`, `DroneCostGrowth`, `DroneMax`
  removed; `BaseDroneYield = 0.6` kept as the pre-first-drone fallback.
- `src/shared/ForgeConfig.luau` - tier display names: Scrap Forge, Molten
  Crucible, Astral Sanctum, Void Foundry, Cosmic Engine. Costs and gates unchanged.
- `src/server/DataManager.luau` - `SCHEMA_VERSION = 5`, `fleet = {}` default,
  `sanitiseFleet`, legacy `drones` -> `fleet.scrap` in `reconcile`.
- `src/server/ProgressionService.luau` - tiered `passiveYield`, `fleetTotal`,
  `droneCostFor`, `droneCost`, ordered `fleetEntries` in the payload, the
  `buyDrones { id, count }` payload, expedition gate on fleet size, ascension
  clears `fleet`.
- `src/client/DroneView.luau` - hero stage, `buildLadder`, `mountTier`, the
  three-column strip, `select` / `selected` exports.
- `src/client/DroneModelBuilder.luau` - per-tier hull and glow, `TIER_SCALE`,
  `build(model, tierId)`, `mount(viewport, tierId, opts)`.
- `src/client/ForgeView.luau` - full-height stage, `buildHud`, crate 180px, the
  strike path now shakes the viewport.
- `src/client/BladePreview.luau` - `framingOf(camera, model, fill, bias)` and
  `mount(..., opts)`.
- `src/client/SidePanel.luau` - `VAULT` text key -> backpack icon, gear rebuilt
  with an 8-tooth ring, shared `iconCanvas` helper.
- `src/client/InventoryModal.luau` - "Click a card to select" deleted.
- `src/client/HudController.luau` - `N DRONES` / `NO DRONES`.
- `src/client/Main.client.luau` - `QF_Dev` gains `fleetTier` and `fleetState`.
- `src/server/Main.server.luau` - `buyDrones` forwards the whole payload.

## The six defects this pass found

1. **`Config.DroneMax` survived the deletion.** Three call sites still read the
   constant after it was removed from `Config`, which is a `nil` index at runtime
   and a selene undefined-variable warning at build time. Replaced with
   `DroneRegistry.SaneMax`.
2. **`abbreviateRate` already appends `/s`.** The fleet strip formatted
   `abbreviateRate(rate) .. " / sec"` and printed `0/s / sec`. The strip now
   prints the function's own result.
3. **selene shadowing, three files.** `ProgressionService` reused `tier` for both
   the registry row and the loop variable, `ForgeView` shadowed `stage`, and
   `SidePanel` shadowed `root`. Renamed to `rung`, `stage` -> the local frame,
   and `root` -> `host`.
4. **`iconCanvas` parented to the module, not the icon.** The helper drew its
   children onto the module-level `root` table instead of the icon frame it was
   handed, so both icons built nine and eleven frames that were never visible.
   Found by counting descendants on the finished frames, not by looking at them.
5. **The tab badge still read `droneCap`.** `refreshTabBadges` computed
   `drones .. "/" .. droneCap`; after the schema change `droneCap` is `nil` and
   the badge throws on the first payload. It now prints the fleet total.
6. **PowerShell wrote a BOM into `SidePanel.luau`.** `Set-Content -Encoding UTF8`
   prefixes `EF BB BF`, which selene reads as `parse_error: unexpected
   character`. Rewritten through
   `[System.IO.File]::WriteAllText($path, $text, [System.Text.UTF8Encoding]::new($false))`.

## Measured

Canvas 1360x720 design at 0.7194 scale, 978x518 rendered.

```
forge card      818 x 576 design
stage           746 x 450 rendered      (486 design px tall)
StrikeButton    537 x 324 rendered at 213,220   (746 x 450 design)
HeatGauge       578 x 40 design at y -64
VentStrip       132 x 40 design
StreakRail      714 x 20 design at y -88
HudScrim        746 x 148 design
crate           180 x 180 design
side panel      500 x 576 design
backpack key     40 x 34  (9 frames)
gear key         36 x 34  (11 frames)
FleetHero       464 x 236 design
DroneViewport   448 x 220 design
DroneLadder     464 x 82 design
rung key         83 x 50 design
buy dock        208 x 46 design
FleetStrip      464 x 64 design
```

Strike layer and HUD, read live after the last cosmetic pass:

```
StrikeButton   Active = true, ZIndex 8
HeatGauge      ZIndex 7, parented to the stage Frame
CORE HEAT      3 heat labels inside the forge card
STRIKE prompt  ZIndex 7
```

Drone silhouettes at `distance = 8.8`, `centre = (0, -0.42, 0)`, projected
through `Camera:PointToObjectSpace`:

```
scrap      27 parts   x 125..201   y 31..113
molten     45 parts   x 117..205   y 34..110
quantum    53 parts   x 119..204   y 36..107
celestial  77 parts   x 109..227   y 33..111
cosmic     99 parts   x 104..232   y 30..114
```

Every rung fits between y 30 and y 114 of a 220px stage, so the name plate (top
30px) and the buy dock (bottom 42px) never overlap a hull.

Purchase, end to end through the real remote:

```
44 x Action("click")  -> heat 91 -> Action("vent") -> aether 8
Action("buyDrones", { id = "scrap" })  -> aether 3, fleet.scrap 1
rung key reads SCR | 1
Action("fleetTier", "quantum") -> both buy faces read LOCKED AT 45
```

Build gates:

```
selene src/                     0 errors, 0 warnings, 0 parse errors
rojo build -o verify.rbxlx      built
client LogService               no errors
```

## What the ticket did not ask for and got anyway

- **Forge tier names.** Scrap Forge / Molten Crucible / Astral Sanctum / Void
  Foundry / Cosmic Engine. The old names were the banner's rarity word twice
  over; these read as places.
- **The crate went 132 -> 180.** A 132px crate on a 486px stage read as a prop.
- **`DroneView.select` / `selected`.** A locked rung can be previewed without a
  purchase, which is what makes the ladder legible before it is affordable.
- **The strike now shakes the viewport, not a panel.** With the whole stage as
  the target, shaking anything smaller reads as a bug.

## Still open

- Store listings still cannot be created: the API key lacks `game-pass:write` and
  `developer-product:write`, so all ids are `0` and the rows read `SOON`.
- All 26 blade meshes return `User is not authorized to access Asset` in this
  Studio session; the procedural fallback renders.
- 22 VFX sheets are generated and unuploaded:
  `python scripts/upload_assets.py --vfx --creator user:1416845247`.
- No `stylua` / `wally` / `luau-lsp` in this environment; `selene` is the only
  static pass.
- `screen_capture` returns null, so every visual claim here is a measurement.
- Only the scrap rung was bought live. Molten needs 150 Aether, which is 1 875
  heat worth of venting in a session that does not persist.
- `AscendThreshold` (1e9) has not been re-tuned against a Cosmic fleet that pays
  720M/s before multipliers.
