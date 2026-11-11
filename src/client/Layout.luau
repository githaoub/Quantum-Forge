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

--- The narrowest canvas the chrome fits on without overlapping. Below this the
--- canvas letterboxes instead of crushing the strip.
---
--- Raised from 1200 when the utility bank moved into the bar: seven 50px keys, a
--- 88px ASCEND and a 78px DAILY is 556px pinned to the right, and the identity
--- plate plus three currency capsules is 702px pinned to the left. At 1320 that
--- leaves 14px of air between them; at 1200 it was an overlap.
Layout.MIN_WIDTH = 1320

--- Top bar: the identity plate and three currency capsules on the left, the
--- utility bank and the two verbs on the right.
--- 6, not 18: with `IgnoreGuiInset = false` the canvas already starts below the
--- native Roblox bar, and another 18px of air under it read as a second, empty
--- toolbar. The reference hugs the native chrome and so does this.
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
Layout.RAIL_FOOT_H = 108

--- The content rect. The forge card and every section panel are built at
--- exactly this size, so switching sections never moves the frame around them.
Layout.CONTENT_Y = Layout.RAIL_Y
Layout.CONTENT_X = Layout.RAIL_X + Layout.RAIL_W + Layout.RAIL_GAP

--- Chrome keys: the top-bar utility bank. 50 wide, 62 tall, icon over label.
Layout.KEY_W = 50
Layout.KEY_GAP = 5
Layout.KEY_H = 62
Layout.VERB_W = 88
Layout.DAILY_W = 78
Layout.ACTION_GAP = 5

--- Everything the top bar needs on the right: seven utility keys, ASCEND and
--- DAILY. The bar is pinned at both ends, so this number is the floor a canvas
--- width has to clear before anything overlaps.
Layout.UTIL_COUNT = 7
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

--- Recomputes everything that depends on the canvas width. Called once at boot,
--- before the HUD, the forge or the nav is built, and again on every resize.
function Layout.init(width: number)
	Layout.CONTENT_W = width - Layout.MARGIN * 2
	Layout.CONTENT_H = Theme.DesignHeight - Layout.CONTENT_Y - Layout.MARGIN

	Layout.CONTENT_X = Layout.RAIL_X + Layout.RAIL_W + Layout.RAIL_GAP
	Layout.CONTENT_W = width - Layout.CONTENT_X - Layout.MARGIN

	Layout.NAV_RIGHT = Layout.CONTENT_X + Layout.CONTENT_W - Layout.NAV_PAD

	-- The top bar runs the full width, including above the rail: it is the app's
	-- masthead, not a section surface.
	Layout.BAR_X = Layout.MARGIN
	Layout.BAR_W = width - Layout.MARGIN * 2

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
