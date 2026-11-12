---
type: build-log
status: shipped in Studio, not yet published
updated: 2026-11-12
aliases:
  - forge-30
tags:
  - build-log
  - ui
  - trade
  - social
---

# Forge 30 - The screen has a face, and the desk takes Aether

The owner reviewed nine screenshots. The first minute was cleaner after Forge 29
but the room still had no readable profile, the trade desk was not usable, and
the chrome disagreed with itself: a `CREW` key that opened a roster, a star
plaque on every panel, a 26px plaque on the forge banner beside a 40px one on
every section, and section icons that read as dark blobs next to the chunky
surfaces they sat on.

## VIEW opens a person, not a list

The `CREW` key is `VIEW`. Four capitals measure 34px at 13px GothamBold, so the
label still fits the 46px key, and the word now matches what the panel does.

The panel is 1120x680. The roster is 250px: head shot, display name, lifetime
Star-Matter, rank and a `YOU` tag. The detail is a second request, `playerDetail`,
because one vault can hold sixty copies and four rune racks. It fills the whole
card:

- header: avatar, display name, handle, rank, playtime, CHEER
- best blade: the shared 3D preview, variant, condition, multiplier, mastery,
  sockets and the socketed runes
- twelve public figures across four rows: Star-Matter, lifetime, Aether, cores,
  shards, scrap, drones, ascensions, copies, codex, runes, tech levels
- daily streak, expedition state and sigil count
- the rune shelf and the tech ladder
- every blade the player owns, in a wrapping grid

Selection paints first and asks second. The old build re-requested the roster on
click and refused a repaint while the request was in flight, which is why the
second player could not be opened. The new path sets the selected id, paints the
list, shows a skeleton, and retries the detail four times in the background.

`roster` stays at one request per player per second. `playerDetail` is budgeted
at one per 0.4s. Both answers are built by the server from `DataManager`;
settings, purchases, favourites and trade state never leave it.

## The trade desk takes Aether

The desk traded Void Shards. The economy does not sell blades for shards, and a
stepper is the wrong control for a number a player wants to type. It now:

- offers every owned copy, including the equipped and favorited ones, tagged
  `WORN` or starred rather than hidden
- takes a typed Aether amount, digits only, clamped to the balance on the client
  and again on the server at offer time and at commit
- carries `MAX` and `OF 2.4K`, so the ceiling is visible without a tooltip
- refuses an offer that would leave either player with zero blades
- runs `ProgressionService.equipBest` when the equipped copy leaves
- keeps the eight-copy limit per side

## The chrome agrees with itself

Every top-bar key now names its own panel: VAULT, CODEX, RANKS, VIEW, TRADE,
NOTES, GUIDE, SETUP. Each overlay banner draws that same mark. `ModalShell`
takes `spec.icon`; the card shells take a `kind`; the crate, vault and feedback
banners use the crates, vault and feedback marks. Plaque sizes are 36px on a
54px modal banner and 40px on a 64px section banner.

`Icons.luau` was redrawn as a solid silhouette with the details cut in ink. The
old marks put a 2px ring around every 4px bar, which left one pixel of fill at
22px and read as a dark smudge. The new set holds up at 18px on a plaque and at
22px in the top bar. `guide` is a pennant instead of a question glyph; `codex` is
an open book, because the closed book read as the letters `IE`.

## The forge has a control column

The forge banner sat on an 18px inset with a 26px plaque, so it was 2px lower,
4px narrower and visibly lighter than the Fleet banner it sat beside. It now
uses the same 16px rect, 64px height and 40px plaque as every section banner.

The stage was 1282x514, a 2.5:1 letterbox with the strike caption, heat gauge and
purge key pinned to three distant corners. The stage is now 16:10 with a 400px
console beside it, and the console holds all three:

- core heat, value, ruled gauge, band and lean point
- strike speed and the streak rail
- the strike payout, with the Star-Matter crystal instead of `SM`
- the purge key, full width, anchored to the console's bottom edge

## Small fixes

- The welcome card lost its duration subtitle and its note. It reads `2X
  STAR-MATTER`, the crystal plate, `x2`, `START FORGING`.
- `UiKit.artLoading` puts a `LOADING...` plate in a badge well after 0.2s if the
  bitmap has not loaded, and gives up after eight seconds. Rune, tech and store
  art all go through `badgeWell` or the shop's own badge, so they inherit it.
- The trade picker shows six skeleton cards until the inventory answers.
- The ascend and daily keys scale 3% and thicken their ring to 4px while their
  action is available. The old 2px stroke breathing was too quiet beside nine
  other keys.

## Verification

Studio, Client, one continuous session at the 1678x720 design canvas.

- Forge: banner at 16, 64 tall, 40px plaque, anvil mark; stage and console both
  end at the card's bottom edge; purge key 380x88 on the console bottom; the
  blade rendered and the strike caption read `STRIKE +5.05` beside the crystal.
- Player view: roster row, avatar, `YOU` tag, `#1 OF 1`, `PLAYED 4m 18s`; best
  blade `RUSTED CLEAVER`, `STANDARD`, `x1.00`, `MASTERY 1`, `SOCKETS 0/1`;
  figures `1.62K` Star-Matter and lifetime, `24` Aether, `10` shards, `1 / 60`
  copies; `ALL BLADES` title clears the best-blade card.
- Trade desk: `TRADE DESK` banner with the trade mark; FORGERS ONLINE rail;
  `TRADING WITH PREVIEW`; typed `400` Aether, `MAX`, `OF 2.4K`; their `250`;
  picker card tagged `WORN`; `ACCEPT THE TRADE` and `WITHDRAW`.
- Runes, tech and store: section banners carry the 40px section mark; all badge
  art loaded, so no `LOADING...` plate was left behind.
- Top bar: all eight labels read, `VIEW` in place of `CREW`, the CODEX mark is an
  open book.
- `selene src` reports 0 errors, 0 warnings, 0 parse errors; `rojo build` writes
  the place file.

Not verified: two real players in one server, so roster selection, cheer and a
live trade have only been exercised with one client. The purchase prompt and
DataStore writes still fail in this Studio session (API services off, MOCK
profile), so nothing here proves persistence.
