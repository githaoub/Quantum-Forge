# Forge 31: trade polling, tablet fill, phone targets, drone gate

Date: 2026-11-12

## What was actually broken

**The trade desk never polled.** `TradeView.step` existed but `Main.client` did
not call it. Opening TRADE requested the partner list and the trade state once,
painted the idle page, and then stopped looking. A second player could accept an
invite, the server could open a real session, and both desks still read
`NO TRADE OPEN` forever. This was the whole two-client trade failure.

**A 4:3 tablet got a 720-tall strip.** `UiKit.screen` always mapped 720 design
px onto the full viewport height. When the viewport was narrower than the
1300-wide floor, the canvas letterboxed: an iPad showed a 720-tall app band with
about 150px of wallpaper above and below. The UI was technically inside the
screen and still read as broken.

**The phone top bar was a row of 20px keys.** The desktop row is 46 design px
per utility key. At a phone fit near 0.45 that is a 20x27px touch target, below
every touch guideline. The trade request popup, the guide card and every overlay
inherited the same tiny type because the whole 720px design height was squeezed
into a 320px content rect.

**The drone lesson pointed at a locked key.** The guide advanced to BUILD A
DRONE on the first vent, then pointed at the FLEET tab or a grey BUILD 1 while
the player still had less Aether than the drone cost. That reads as the game
asking for a purchase the player cannot make.

## What changed

- `Main.client` now calls `TradeView.step(dt)` every render frame. The desk
  polls the session at 0.35s and the partner list at 2s.
- `TradeView.step` requests both over spawned tasks with in-flight guards, so a
  slow RemoteFunction cannot stall a frame every third of a second.
- `UiKit.screen` now fills the width when the viewport is narrower than the
  floor's aspect, and grows the design height instead of letterboxing. It
  returns the real height as a fifth value.
- `Layout.init` accepts that height, stores `Layout.CANVAS_H`, and computes the
  content rect from it. Notifications use the same height, so toasts stay on the
  bottom edge on a tall canvas.
- `Layout.init` also accepts a compact flag. Below a 0.6 fit the top bar becomes
  a 92px row with 84px keys, the 240px profile plate is hidden, and the three
  currency capsules keep only their mark and number. The rail item shrinks to
  52px so the foot still clears it.
- `HudController` places the compact icons, labels and verb detail from the key
  height instead of the old fixed offsets.
- The drone guide stays on the forge and rings the purge key while the first
  drone is unaffordable. It only points at FLEET and BUILD 1 once the Aether is
  actually there.
- The trade request card says Aether, not Void Shards.

## Evidence

- iPad Pro M5 (13in), 1375x1032: forge root measured 1174x819 at design
  position 116,92; the app filled the screen instead of letterboxing.
- iPhone 17 Pro fit, 750x381 viewport: top bar measured 1652x92 with 37x37
  utility keys and a 52x37 ASCEND, up from 20x27. The profile plate is gone and
  the three currency capsules show mark plus value.
- `selene src`: 0 errors, 0 warnings, 0 parse errors.
- `rojo build default.project.json -o verify.rbxlx`: writes the place file.

## Not yet verified

- A complete two-client trade after the polling fix. The server and both clients
  were exercised before the fix and reproduced `NO TRADE OPEN`; the fixed client
  was not driven through offer, accept and commit.
- The drone guide on a fresh profile with less than the drone price.
- Phone modals and the trade desk at 37px keys. The top bar was measured, the
  panel contents were not.
