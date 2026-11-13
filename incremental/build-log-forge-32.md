# Forge 32: fleet, runes and tech are pages, and the tablet chrome fits

Date: 2026-11-13

## What was actually broken

**The management rows were dealt into two columns by height.** `Sections`
measured each block and stacked them into a left and right column of half the
panel. Fleet, runes and tech do not have blocks of matching height, so the deal
left one column longer than the other. On a wide canvas that empty band read as
a missing panel, not as breathing room. The sections were also text lists: a
50px key strip for the fleet, full-width rune rows, and one node card repeated
down the page.

**The top bar was built once from the phone row.** `HudController` placed the
compact 84px keys at boot and only moved the bar root on resize. A Studio window
or a rotated tablet that crossed the 0.6 fit line kept the phone keys inside the
76px bar. The labels had no truncation, so a long buy or verb line ran under the
bar edge.

**The focus ring restored a fixed 2px border.** `UiKit.focus` wrote
`Theme.Stroke.thick` on `SelectionLost` no matter what the control carried
before the focus. A 1px card kept a 2px ring after the pointer or the gamepad
moved on, which is what made a highlight look like it had escaped its control.

## What changed

- Fleet, runes and tech are `page = true` full-bleed cards. `Main` builds them
  once at boot beside the forge, crate and store cards, and `Sections.layout`
  owns their outer rect. The two-column host no longer deals them.
- Fleet is a hangar: a 3D hull stage and a five-row hull rack on the top row,
  then expedition, salvage and sigil codex as a three-card service deck, then
  three field notes. Rack rows carry the hull name, owned count and unlock
  meter. The buy keys price the selected rung.
- Runes is a bay and a shelf: blade name, rank chip, mastery meter, three
  sockets, a 2x2 socketed-bonus grid and a blade-record note in the bay; a 2x2
  rune card grid in the shelf, each card with art, effect and a CRAFT or SOCKET
  plate. A four-step strike to craft chain and a five-rank mastery ladder sit
  under them.
- Tech is three lanes, each with a header, a spine and its node cards. The
  sidebar holds the core reserve, the four nearest forge feats and the branch
  totals. The heat lane ends in a live readout instead of an empty fourth slot.
- `HudController` now keeps handles to the chrome and repaints every key, verb,
  pill and group at the current `Layout` values. A compact boot that grows into
  a tablet gets the wide row, and the reverse works too.
- `UiKit.button` and `UiKit.actionButton` clip their children and truncate the
  face. The face inset is 6px each side, so a long label ends in an ellipsis
  inside the plate rather than under the border.
- `UiKit.focus` snapshots the stroke colour, thickness and transparency when
  selection arrives and restores exactly that on selection lost.
- The canvas, rail and section host clip descendants. A hover fill, a stroke or
  a pulse on an edge control cannot paint into the wallpaper band.
- The fleet expedition reward moved to its own line. The joined squad, time and
  payout string was the one label that did not fit at 13px on a tablet.

## Evidence

Studio, Client, one continuous session per device.

- iPad Pro M5 (13in), 1375x1032, fit 1.058:
  - bar 1353x80 at y6; utility keys 48x65 at y13, all inside the bar; ASCEND
    93x65 and DAILY 84x67 at the right edge, inside the canvas.
  - fleet page 1241x866; hero 779x317, rack 407x317, service cards 391x317
    each; body canvas 727 against a 768 window, so the page fits without a
    scroll.
  - runes page: bay 503x487, shelf 683x487, chain 1199x118, ladder 1199x126.
  - tech page: sidebar 317x660, three lanes 275x621 each, notes 856x116.
  - full-page scan: zero offscreen controls, zero labels that fail `TextFits`
    on all three pages.
- HD 720, 1280x720, fit 0.919:
  - bar 1260x69; keys 42x57; every face and verb reports `TextFits`.
  - each page scrolls inside its own body; the pieces below the fold are
    reachable, not clipped by the page.
- iPhone 16 Pro Max sim, 830x439:
  - compact row 819x48; keys 44x44 at y5; ASCEND 61x44 and DAILY 53x45, all
    inside the bar. No label overflow on any page.
- `selene src`: 0 errors, 0 warnings, 0 parse errors.
- `rojo build default.project.json -o verify.rbxlx`: writes the place file.

## Not yet verified

- A human visual pass on the three new pages. This pass measured geometry and
  text fit; it did not judge the composition on a real screen.
- The gamepad selection ring on hardware. The restore path is code-verified,
  not driven with a pad.
- Real phone hardware. The Studio simulator caps the iPhone resolution to the
  host window, so the measured compact row is a small-window fit, not a 6.9in
  panel.
- DataStore, purchases, blade meshes and the two-client trade gaps from Forge
  31 are unchanged.
