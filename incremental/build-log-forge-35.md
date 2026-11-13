# Forge 35: the guide teaches both currencies, and the purge dead end is gone

Date: 2026-11-13

## The complaint

The owner sent a screenshot of step 2. The card said `TAP UNTIL THE BAR IS
FULL` while the gold ring sat on the purge key, and the heat bar was nowhere
near the line. The guide also taught only Aether, never told the player what a
crate costs or why they should care about Star-Matter, and ended with
`THAT IS THE LOOP` without saying where the rest of the game was explained.

## The dead end

Step 2 had two jobs. It taught the purge, and it waited for
`payload.as >= dronePrice(payload)`. One purge at the line is 85 heat times
`Config.AetherPerHeat` (0.08), which pays 6.8 Aether against a first drone that
costs 7. So a player who purged exactly at the line stayed on step 2 with:

- a card that said `Turn the heat into Aether`
- a ring on the purge key, which was locked until the bar refilled
- no instruction to strike again

The ring also did not follow the copy. At low heat the card said `Tap until the
bar is full` and still pointed at the purge key. Both paths read as a broken
button.

## What changed

### Five steps, each one job

1. `TAP THE BLADE`. `Every strike pays Star-Matter. Fill the heat bar.` The
   first mention of Star-Matter now happens on the first action, not on the
   crate step.
2. `PURGE THE HEAT`. The ring follows the job: the blade stage while the bar is
   short, the purge key once it reaches 85. Advance is `sawVent` alone. Earning
   the drone is the next step's problem.
3. `BUILD A DRONE`. Names the live first-rung price and the player's current
   Aether. The ring points at the blade, at the purge key when the bar is full,
   at the FLEET tab, then at `BUILD 1`. The page opens itself 0.9 s after the
   price is affordable.
4. `OPEN A CRATE`. Names the live standard crate price and the player's current
   Star-Matter. While short, the ring points at the blade and the purge key.
   Once affordable, the card says so and opens CRATES after the same 0.9 s
   beat. On CRATES the ring moves to `ROLL` and the card says
   `Press ROLL. It forges your first blade.` The step advances on a new vault
   copy, not on the page opening.
5. `THE REST IS YOURS`. `Tap, purge, build, roll. The rest is yours to figure
   out. The GUIDE section explains every system, and you can replay this tour
   any time.` The card stays where the last note was, so it does not cover the
   roll keys on the crates page.

### Replays do not demand purchases

The drone step is gated on `dronesAtStart == 0`. The crate step is gated on
`invCount <= 1 and forgeRolls == 0`, because the starter blade counts as one
copy. A replay on a leveled account walks strike, purge and the closing note
instead of asking for a 300M hull or a second crate.

### Presentation

- Card height 172 to 210, body box 48 to 78 design px. The closing note is
  three lines and reports `TextFits = true`.
- The crate step's body names the price in both states, so the player reads the
  Star-Matter number even when they already have enough.
- The rail foot now says `1 DRONE`, not `1 DRONES`.

## Evidence

Studio, 1212x576 game area, canvas 1686x720 at 0.719.

- Step 2, low heat: body `Tap the blade until the bar is full.`; ring at
  `(89.9, 124.5)` size `812 x 378`, the blade stage. The purge key measures
  `281 x 71` at `(908.5, 418.7)`, so the ring was not on it.
- Step 2, heat 99: body `Press the purge key. Heat becomes Aether.`; ring on
  the purge key at the same `281 x 71` rect. The red key carried the vent mark
  and its own `+6` payout line.
- Step 3: `Press BUILD 1. It earns Star-Matter while you do nothing.` The
  0.9 s tick opened FLEET; the ring measured `192 x 41` around `BuyDrone`
  (`184 x 33` at `454.5, 296.4`).
- Step 4: `The first crate costs 515.58K Star-Matter. You have enough.
  Opening CRATES.` The tick opened CRATES; the ring measured `229 x 55` around
  `RollOne` (`222 x 46` at `325.1, 425.9`); the body became
  `Press ROLL. It forges your first blade.`
- Step 5: `STEP 5 OF 5`, body bounds 215 x 31 inside a 218 x 56 box,
  `TextFits = true`, `DONE` visible. The card position did not move from the
  previous note.
- A replay on the seeded profile skipped the two purchase steps and went
  step 1, step 2, closing note. No `TutorialController` errors in the console.
- `selene src`: 0 errors, 0 warnings, 0 parse errors.
  `rojo build default.project.json -o verify.rbxlx`: success.
- Saved to the real place as version 337, note
  `Forge 35: guide teaches both currencies and the crate, fixes the purge dead end`.
  Not published.

## Open

- A true first-join walk on a clean profile was not possible in this Studio
  session. The profile is seeded (one drone, four copies) and the store runs
  MOCK, so the drone and crate gates correctly skipped. Their cards and targets
  were rendered with temporary forced gates, then the gates were restored
  before the save. The five-step chain still needs one pass on a genuinely new
  account.
- The purchase prompt and DataStore writes are still unverified, so no
  monetization number in this build has been tested with a real transaction.
