---
type: index
project: quantum-forge
status: live
updated: 2026-11-11
tags:
  - quantum-forge
  - index
---

# Quantum Forge

Home note for the design record. Everything in this folder is versioned with the
repo; this note is the map, not a duplicate. If a fact is only written here, it
is in the wrong place.

> [!info] How to use this vault
> Open the vault at `Obsidian Vault/quantum-forge`, which is a junction into
> `roblox-incremental/incremental`. Do not move files into Obsidian; the repo is
> the source of truth and the vault is a lens over it.
>
> Open this note with `Ctrl+O` → `quantum-forge`. Every other note is one hop
> away from here, so the folder tree never needs to be browsed.

## Start here

| I want to… | Open |
| --- | --- |
| know what shipped last | [[build-log-forge-12]] |
| know why a rule exists | [[design-decisions]] |
| find a module | [[code-map]] |
| build the current UI | [[ui-refactor-direction]] |
| check the economy | [[game-design-math]] |
| check the pitch | [[game-design-brief]] |
| run art generation | [[art-prompts-nano-banana]] |

## Live state

> [!success] Shipped
> Balance pass, five-crate pools, starter boost, daily track, codex expansion,
> crate page section, foundry-instrument UI tokens, left rail, control deck.
>
> [!warning] Blocked
> 26 blade meshes return `User is not authorized to access Asset`. 22 VFX sheets
> unuploaded. No pointer synthesis in the Studio build, so interactive paths are
> driven through `QF_Dev`.

## The decision log

`design-decisions.md` is append-only. Link to one decision by heading, never by
copying it:

- [[design-decisions#ADR-075]] — page sections
- [[design-decisions#ADR-074]] — crate pools
- [[design-decisions#ADR-073]] — daily track
- [[design-decisions#ADR-072]] — starter boost
- [[design-decisions#ADR-071]] — toolbar
- [[design-decisions#ADR-070]] — cursor VFX
- [[design-decisions#ADR-069]] — balance pass

## Build logs

Newest first. Each log is one pass, with measurements and the open list at the
end.

- [[build-log-forge-12]]
- [[build-log-forge-11]]
- [[build-log-forge-10]]
- [[build-log-forge-09]]
- [[build-log-forge-08]]
- [[build-log-forge-07]]
- [[build-log-salvage-06]]
- [[build-log-remake-04-05]]

## Systems

- [[code-map]] — module ownership, boot order, verbs
- [[game-design-math]] — curves, gates, income
- [[project-readme]] — the long-form project record
- [[README]] — repo layout and commands

## Notes on method

Three habits keep this vault useful:

1. **One index, no deep trees.** A new note gets linked from here the same day it
   is written. Folders are for assets only.
2. **Unique titles.** Obsidian resolves links by filename. Two notes called
   `notes.md` in different folders break every link silently.
3. **Facts live where they are maintained.** This note links; it never restates a
   number that lives in `design-decisions.md` or `code-map.md`.
