--!strict
-- Screen geometry, in design pixels.
--
-- One module rather than a set of locals per controller, because the chrome and
-- the content have to agree on four numbers: where the bar ends, where the nav
-- begins, where every section starts, and how tall it is allowed to be.
--
-- The right-hand panel is gone. This describes a full-width column: a top bar
-- hugging the Roblox topbar, a nav strip that also carries the utilities, the
-- live rate and the two chrome keys, and one content rect that every section
-- fills edge to edge.
--
-- **The width is elastic.** Height is fixed at the 720 design rung; the width is
-- whatever the viewport has left at that scale, so an ultrawide monitor gets
-- more layout instead of black bars. `UiKit.screen` returns the width it picked,
-- reports later resizes through a callback, and `Main` re-primes this module
-- before anything is built and again on every resize, so consumers read a plain
-- number at build time.

local Theme = require(script.Parent.Theme)

local Layout = {}

Layout.MARGIN = 10
Layout.GAP = 10

--- True on a phone-scale canvas. `UiKit.screen` reports the fit it chose; below
--- 0.6 the 46px mouse key is a 28px finger target, so the bar switches to the
--- 84px key and drops the profile plate. The iPad and the desktop keep the
--- original row.
Layout.COMPACT = false

--- The actual design height. It is 720 on every landscape window, but a 4:3
--- tablet used to letterbox the canvas to a 720-tall band and leave 200px of
--- wallpaper above and below. `UiKit.screen` now grows the canvas to the
--- viewport instead, and this is the height every view reads.
Layout.CANVAS_H = Theme.DesignHeight

--- The narrowest canvas the chrome fits on without overlapping. Below this the
--- canvas fills the width and grows taller instead of letterboxing.
---
--- Eight 46px utility keys, an 88px ASCEND and a 78px DAILY is 570px pinned to
--- the right, and the identity plate plus three currency capsules is 702px
--- pinned to the left. At 1300 that leaves 28px of air between them, which is
--- wider than the old seven-key bar had.
Layout.MIN_WIDTH = 1300

--- Top bar: the identity plate and three currency capsules on the left, the
--- utility bank and the two verbs on the right.
--- 6, not 18: with `IgnoreGuiInset = false` the canvas already starts below the
--- native Roblox bar, and another 18px of air under it read as a second, empty
--- toolbar. The reference hugs the native chrome and so does this.
---
--- The 76px row is the mouse layout. A phone at 0.49 fit turns that into a 22px
--- key face, which is below every touch guideline, so the compact row is 92px
--- with an 84px key. `Layout.init` swaps the numbers.
Layout.TOPBAR_Y = 6
Layout.TOPBAR_H = 76

--- Geometry.
---
--- The horizontal tab strip is gone. Sections live in a left rail, which frees
--- the 52px the strip used to take and gives every screen that much more canvas.
Layout.NAV_Y = Layout.TOPBAR_Y + Layout.TOPBAR_H + 6
Layout.NAV_H = 0

--- The rail that carries the section list, and the content rect beside it.
Layout.RAIL_W = 92
Layout.RAIL_GAP = 14
Layout.RAIL_X = Layout.MARGIN
Layout.RAIL_Y = Layout.NAV_Y + 4
Layout.RAIL_ITEM_H = 56
Layout.RAIL_ITEM_GAP = 4
--- The foot carries three readouts now: connection, rate, and the next goal.
--- 128 keeps a clear 8px gap between the goal text and its progress rule; at 108
--- the bar sat on the text's last row.
Layout.RAIL_FOOT_H = 128

--- The content rect. The forge card and every section panel are built at
--- exactly this size, so switching sections never moves the frame around them.
Layout.CONTENT_Y = Layout.RAIL_Y
Layout.CONTENT_X = Layout.RAIL_X + Layout.RAIL_W + Layout.RAIL_GAP

--- Chrome keys: the top-bar utility bank. 46 wide so eight of them still fit
--- beside the identity block at the 1300 canvas floor.
Layout.KEY_W = 46
Layout.KEY_GAP = 4
Layout.KEY_H = 62
Layout.VERB_W = 88
Layout.DAILY_W = 78
Layout.ACTION_GAP = 4

--- Everything the top bar needs on the right: eight utility keys, ASCEND and
--- DAILY. The bar is pinned at both ends, so this number is the floor a canvas
--- width has to clear before anything overlaps. Recomputed by `init` because
--- the compact row uses wider keys.
Layout.UTIL_COUNT = 8
Layout.RIGHT_CLUSTER = Layout.UTIL_COUNT * Layout.KEY_W
	+ (Layout.UTIL_COUNT - 1) * Layout.KEY_GAP
	+ Layout.ACTION_GAP
	+ Layout.VERB_W
	+ Layout.ACTION_GAP
	+ Layout.DAILY_W

--- Tab sizing. The row is the elastic element: it takes as much of the strip as
--- it can while leaving the rate band at least `RATE_MIN`, and never grows past
--- `TAB_W_MAX` so a five-tab row on an ultrawide does not turn into five empty
--- billboards.
Layout.TAB_GAP = 4
Layout.TAB_W_MIN = 112
Layout.TAB_W_MAX = 200
Layout.RATE_MIN = 280
Layout.RATE_MAX = 560
Layout.RATE_H = 30
Layout.TAB_X = Layout.CONTENT_X + 10

--- How many sections the nav has to carry. `Sections` sets this at load; the
--- default keeps `Layout` usable on its own.
Layout.TAB_COUNT = 5

--- Inner gutter of the nav strip, on both ends. The rate band is pinned this far
--- from the right edge, so the strip's plate has an edge on both sides.
Layout.NAV_PAD = 10

--- Recomputes the geometry that depends on the canvas. Called once at boot,
--- before the HUD, the forge or the nav is built, and again on every resize.
---
--- `height` is normally 720. A 4:3 tablet asks for a taller canvas because
--- `UiKit.screen` grows it rather than letterboxing; the content rect follows,
--- so the forge fills the extra room instead of leaving a navy band under it.
---
--- `compact` is the phone row: wider keys, a shorter rail item, and a slightly
--- taller bar. It is decided from the fit, not from a device name.
function Layout.init(width: number, height: number?, compact: boolean?)
	Layout.CANVAS_H = height or Theme.DesignHeight
	Layout.COMPACT = compact == true

	if Layout.COMPACT then
		Layout.TOPBAR_H = 92
		Layout.KEY_W = 84
		Layout.KEY_H = 84
		Layout.VERB_W = 116
		Layout.DAILY_W = 100
		Layout.RAIL_ITEM_H = 52
		Layout.RAIL_FOOT_H = 120
	else
		Layout.TOPBAR_H = 76
		Layout.KEY_W = 46
		Layout.KEY_H = 62
		Layout.VERB_W = 88
		Layout.DAILY_W = 78
		Layout.RAIL_ITEM_H = 56
		Layout.RAIL_FOOT_H = 128
	end

	Layout.RIGHT_CLUSTER = Layout.UTIL_COUNT * Layout.KEY_W
		+ (Layout.UTIL_COUNT - 1) * Layout.KEY_GAP
		+ Layout.ACTION_GAP
		+ Layout.VERB_W
		+ Layout.ACTION_GAP
		+ Layout.DAILY_W

	Layout.NAV_Y = Layout.TOPBAR_Y + Layout.TOPBAR_H + 6
	Layout.NAV_H = 0
	Layout.RAIL_Y = Layout.NAV_Y + 4
	Layout.CONTENT_Y = Layout.RAIL_Y
	Layout.CONTENT_X = Layout.RAIL_X + Layout.RAIL_W + Layout.RAIL_GAP

	Layout.CONTENT_W = width - Layout.CONTENT_X - Layout.MARGIN
	Layout.CONTENT_H = Layout.CANVAS_H - Layout.CONTENT_Y - Layout.MARGIN

	Layout.NAV_RIGHT = Layout.CONTENT_X + Layout.CONTENT_W - Layout.NAV_PAD

	-- The top bar runs the full width, including above the rail: it is the app's
	-- masthead, not a section surface.
	Layout.BAR_X = Layout.MARGIN
	Layout.BAR_W = width - Layout.MARGIN * 2
	Layout.TAB_X = Layout.CONTENT_X + 10

	-- Kept assigned even though the strip is gone: `HudController` and the old
	-- call sites still read these fields, and a nil here crashes at runtime
	-- rather than at selene.
	local count = math.max(Layout.TAB_COUNT, 1)
	local gaps = Layout.TAB_GAP * (count - 1)
	local room = Layout.NAV_RIGHT - 12 - Layout.TAB_X - gaps - Layout.RATE_MIN
	local tabW = math.clamp(math.floor(room / count), Layout.TAB_W_MIN, Layout.TAB_W_MAX)

	Layout.TAB_W = tabW
	local tabsEnd = Layout.TAB_X + count * tabW + gaps
	local rateW = math.clamp(Layout.NAV_RIGHT - tabsEnd - 12, Layout.RATE_MIN, Layout.RATE_MAX)
	Layout.RATE_W = rateW
	Layout.RATE_X = Layout.NAV_RIGHT - rateW
	Layout.RATE_Y = Layout.NAV_Y + (Layout.NAV_H - Layout.RATE_H) / 2
end

Layout.init(Theme.DesignWidth)

return Layout
