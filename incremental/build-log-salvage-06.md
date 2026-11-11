# Build log: the Salvage loop

Shipped 2026-11-10 against `video-06-mvp-rng-session-time.md`. The ADR is
`ADR-042` in the repo root; this is the working record of what changed and what
was measured.

## What the video asked for, and what shipped

| lever | shipped as |
| --- | --- |
| RNG before the reward | rarity rolled at drop, drawn on the sealed slot |
| a real time hurdle | `os.time()` crack clock, 0 / 45 / 180 / 600 by rarity |
| a collection that takes days | twelve sigils, four sets, permanent set multipliers |
| low cognitive load | one tap per slot, one button per rune, one per tech node |

Speed-to-market was the video's headline and does not apply here. The loop shape
was the transferable part.

## Files

New:

- `src/shared/SalvageConfig.luau` - rarities, weights, crack times, rewards,
  twelve sigils, four sets, `rollRarity`, `rollSigil`, `bonus`, `setProgress`.
- `incremental/build-log-salvage-06.md` - this file.
- `user-manual/16-salvage-art-prompts.txt` - eight optional art prompts, same
  contract as `15-stuff.txt`.

Changed:

- `src/shared/Types.luau` - `CacheState`, `SyncCache`, profile fields
  `cacheMeter` / `caches` / `sigils`, payload fields.
- `src/server/DataManager.luau` - schema 3, `sanitiseCaches`, `sanitiseSigils`,
  meter clamp.
- `src/server/ProgressionService.luau` - `salvageBonus`, `addSalvageMeter`,
  `crackCache`, `claimCache`, payload build, click multiplier.
- `src/server/ForgeService.luau` - meter fill on every strike (manual and
  auto-click), crit and vent and cooling bonuses, drop toast.
- `src/server/Main.server.luau` - `crackCache` / `claimCache` actions.
- `src/client/DroneView.luau` - `SalvageBand` and `CodexBand`, 64px mission art.
- `src/client/RuneView.luau` - 88px rune art, row 104.
- `src/client/TechTreeView.luau` - 80px node art, card 132.

## Measured

```
Mission_sweep  row 412x72   art 64  loaded=true  labels fit 2/2
Rune_ember     row 432x104  art 88  loaded=true  labels fit 3/3
Tech card x8   row 432x132  art 80  loaded=true  labels fit 4/4
Salvage band   432x164  slots=3   meter 0/40 -> 35/40 -> drop
Codex band     432x142  rows=4
```

Text clearance on the tech card, measured from the card origin:

```
name x104 w206   level chip x316
desc/effect x104 w202   buy button x318
```

`selene src/` 0 errors / 0 warnings / 0 parse errors. `rojo build` 584,294 bytes.
Console clean after a full playtest restart.

## Exercised end to end

Forty-plus strikes filled the meter and dropped a Scrap Cache. The slot read
`SCRAP CACHE / CRACK / TAP TO START`. A tap on the sealed slot ran the 0-second
crack and the slot moved to `CLAIM / +60 AE`. A second tap emptied the slot and
paid out.

Not exercised: a timed crack (45s and above) and a codex set completion. Both are
clock or data driven and are listed in the honesty table.

## The renames

The vault was nine files whose names did not say what they contained. Now:

| old | new |
| --- | --- |
| `GAMEIDEA.md` | `game-design-brief.md` |
| `VIDEOANALYSIS-01.md` | `video-01-profit-per-ccu.md` |
| `VIDEOANALYSIS-02.md` | `video-02-ai-vfx-pipeline.md` |
| `VIDEOANALYSIS-03.md` | `video-03-232-swords-3d-pipeline.md` |
| `VIDEOANALYSIS-04.md` | `video-04-market-positioning.md` |
| `VIDEOANALYSIS-05.md` | `video-05-onboarding-monetization-qa.md` |
| `VIDEOANALYSIS-06.md` | `video-06-mvp-rng-session-time.md` |
| `NANO-BANANA-PROMPT-GUIDE.md` | `art-prompts-nano-banana.md` |
| `REMAKE-04-05.md` | `build-log-remake-04-05.md` |

Every cross-reference in the repo, the vault, `scripts/generate_vfx.py` and the
Obsidian workspace file was rewritten in the same pass. `README.md` is
the new index: naming rules, one-line thesis per note, and the reading order for a
fresh session.

## What is still open

- Four cache badges and four set emblems: prompts written, not generated.
- A 45-second crack and a codex completion in a live session.
- The store is still `SOON` until the API key gets `game-pass:write` and
  `developer-product:write`.
