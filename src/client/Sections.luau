--!strict
-- The main-screen section host.
--
-- The old UI was a 520px column bolted to the right of the forge: Fleet, Runes,
-- Tech and Store were tabs inside a panel narrower than the vault modal, and
-- every list in them was one card wide. This replaces that with a single
-- full-width screen per subsystem, under one nav strip.
--
-- Ownership:
--   * the nav strip (tabs, vault key, settings key) lives here;
--   * the rate readout is built by `HudController` and positioned inside the
--     strip from `Layout`, because that module already owns the stall detector;
--   * the forge card is built by `ForgeView` and simply hidden while another
--     section is on screen. Rebuilding it on every tab switch would restart the
--     viewport, the embers and the crate, which is a visible stutter for a view
--     the player returns to constantly.
--
-- Only one management view is mounted at a time. Tearing down a view destroys
-- its subscriptions, so nothing accumulates as the player clicks between
-- sections - the bug that makes a menu-heavy game feel heavy after five minutes.
-- Views are rebuilt from the current payload on every visit, which is cheap and
-- guarantees the section is correct after an ascension.

local Theme = require(script.Parent.Theme)
local UiKit = require(script.Parent.UiKit)
local StateStore = require(script.Parent.StateStore)
local Sfx = require(script.Parent.Sfx)
local Vfx = require(script.Parent.Vfx)
local Modals = require(script.Parent.Modals)
local Layout = require(script.Parent.Layout)
local TechTreeConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("TechTreeConfig"))

local DroneView = require(script.Parent.DroneView)
local RuneView = require(script.Parent.RuneView)
local TechTreeView = require(script.Parent.TechTreeView)
local ShopView = require(script.Parent.ShopView)

local Sections = {}

type SectionDef = {
	key: string,
	label: string,
	title: string,
	kicker: string,
	accent: Color3,
	icon: string,
	--- True for a section that owns a full-bleed card instead of a panel of rows.
	--- The forge is one; so is the roll page. A page is a whole screen with its
	--- own composition, which the two-column card distributor cannot lay out.
	page: boolean?,
	--- Nil for the forge: that section is the card `ForgeView` already owns.
	init: ((Instance) -> ())?,
	destroy: (() -> ())?,
}

local SECTIONS: { SectionDef } = {
	{
		key = "forge",
		label = "FORGE",
		title = "THE FORGE",
		kicker = "STRIKE THE ANVIL  ·  ROLL THE CRATE  ·  CHASE THE VARIANT",
		accent = Theme.Color.gold,
		icon = "★",
		page = true,
	},
	{
		key = "crates",
		label = "CRATES",
		title = "CRATE VAULT",
		kicker = "FIVE POOLS  ·  ODDS ON THE TABLE  ·  SINGLE OR TEN",
		accent = Theme.Color.quantum,
		icon = "▣",
		page = true,
	},
	{
		key = "fleet",
		label = "FLEET",
		title = "DRONE FLEET",
		kicker = "BUY DRONES  ·  SEND EXPEDITIONS  ·  SPEND AETHER",
		accent = Theme.Color.cyan,
		icon = "▲",
		init = DroneView.init,
		destroy = DroneView.destroy,
	},
	{
		key = "runes",
		label = "RUNES",
		title = "RUNE FORGE",
		kicker = "MASTER THE BLADE IN HAND  ·  SOCKET SHARDS  ·  STACK BONUSES",
		accent = Theme.Color.quantum,
		icon = "◆",
		init = RuneView.init,
		destroy = RuneView.destroy,
	},
	{
		key = "tech",
		label = "TECH",
		title = "TECH TREE",
		kicker = "SPEND QUANTUM CORES  ·  PERMANENT MULTIPLIERS",
		accent = Theme.Color.quantum,
		icon = "✦",
		init = TechTreeView.init,
		destroy = TechTreeView.destroy,
	},
	{
		key = "store",
		label = "STORE",
		title = "QUANTUM STORE",
		kicker = "GAME PASSES  ·  BOOSTS AND UTILITY",
		accent = Theme.Color.emerald,
		icon = "¤",
		init = ShopView.init,
		destroy = ShopView.destroy,
	},
}

local byKey: { [string]: SectionDef } = {}
for _, def in SECTIONS do
	byKey[def.key] = def
end

-- The nav is the only module that knows how many sections exist, and the strip
-- geometry lives in `Layout`. Hand it the count at load, before Main primes the
-- layout, so the tab row and the rate band split the strip correctly.
Layout.TAB_COUNT = #SECTIONS

local content: ScrollingFrame? = nil
local host: Frame? = nil
local columns: { Frame } = {}
local rowSink: Frame? = nil
local distributor: (() -> ())? = nil
local forge: Frame? = nil
--- Full-bleed cards owned by page sections, keyed by section key.
local pages: { [string]: Frame } = {}
local nav: Frame? = nil
local tabRow: Frame? = nil
local tabHandles: { [string]: UiKit.TabHandle } = {}
local banners: { [string]: Frame } = {}
local kickers: { [string]: TextLabel } = {}
local active: string? = nil
local settingsListener: (() -> ())? = nil

--- Scroll offset per section, captured on the way out and restored on the way
--- back. A twenty-row store is not something a player wants to re-scroll.
local savedScroll: { [string]: number } = {}
local scrollEpoch = 0
local pendingRestore: string? = nil

--- Fired after a section becomes active.
Sections.onSelect = nil :: ((name: string) -> ())?

--- Overlay handlers used to live here. They moved to `HudController` with the
-- utility bank: the nav strip only carries section tabs and the rate band now,
-- and the top bar owns every key that opens a modal.

-- ---------------------------------------------------------------------------
-- Mounting
-- ---------------------------------------------------------------------------

local function unmount()
	if active then
		local def = byKey[active]
		if def and def.destroy then
			def.destroy()
		end
	end
	-- Only the rows go. The two columns and the sink are the host's furniture
	-- and live for as long as the panel does.
	for _, column in columns do
		for _, child in column:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end
	active = nil
end

local function highlight(name: string)
	for key, handle in tabHandles do
		handle.setActive(key == name)
	end
end

--- Keeps the "you can buy something in here" glow without touching the pill
--- fill: only the face of an inactive tab changes colour.
local function tintFace(name: string, color: Color3?)
	local handle = tabHandles[name]
	if handle == nil then
		return
	end
	local face = handle.button:FindFirstChild("Face")
	if face and face:IsA("TextLabel") then
		face.TextColor3 = color or Theme.Color.locked
	end
end

--- Which section is on screen.
function Sections.activeTab(): string?
	return active
end

--- Puts a returning section back where the player left it.
---
--- `AutomaticCanvasSize` recomputes the canvas on the frame *after* the rows are
--- parented, so a position written in the same frame is clamped against the
--- previous, empty canvas and silently snaps to zero. Retry across a few
--- heartbeats until the canvas is tall enough to hold the value.
local function restoreScroll()
	local box = content
	if box == nil then
		return
	end

	scrollEpoch += 1
	local epoch = scrollEpoch
	local target = savedScroll[active or ""] or 0
	local tab = active

	if target <= 0 then
		box.CanvasPosition = Vector2.zero
		pendingRestore = nil
		return
	end

	pendingRestore = tab
	task.spawn(function()
		for _ = 1, 5 do
			task.wait()
			if epoch ~= scrollEpoch or box.Parent == nil then
				return
			end
			box.CanvasPosition = Vector2.new(0, target)
			if box.CanvasPosition.Y >= target - 1 then
				break
			end
		end
		if epoch == scrollEpoch then
			pendingRestore = nil
		end
	end)
end

function Sections.select(name: string)
	local def = byKey[name]
	if def == nil or content == nil or host == nil then
		return
	end
	if active == name then
		return
	end

	-- Capture before teardown: the rows are about to be destroyed, and the
	-- canvas position goes with them.
	if active and active ~= pendingRestore and content then
		savedScroll[active] = content.CanvasPosition.Y
	end

	unmount()
	active = name
	highlight(name)

	for key, banner in banners do
		banner.Visible = key == name
	end
	for key, kicker in kickers do
		kicker.Visible = key == name
	end

	if def.init then
		host.Visible = true
		if forge then
			forge.Visible = false
		end
		for _, card in pages do
			card.Visible = false
		end
		-- Rows go to the sink, which sorts them into the columns one frame later.
		local target: Instance = rowSink or content
		def.init(target)
		if distributor then
			task.defer(distributor)
		end
		restoreScroll()
	else
		-- A page section is a whole card, the way the forge is. Hide the host
		-- rather than building a panel of rows behind a card that covers it.
		host.Visible = false
		for key, card in pages do
			card.Visible = key == name
		end
		if content then
			content.CanvasPosition = Vector2.zero
		end
	end

	local callback = Sections.onSelect
	if callback then
		callback(name)
	end
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

--- Opens the settings sheet and applies a switch the moment it flips.
---
--- Named rather than inlined because the gear button and the Studio dev seam must
--- run the same code: the sheet writes through the server, so a test that calls
--- `Modals.settings` with its own callback proves nothing about the button.
function Sections.openSettings()
	local current = StateStore.current
	local values = if current
		then current.settings
		else { sfx = Sfx.isEnabled(), vfx = Vfx.isEnabled(), shake = true, trades = true }
	Modals.settings(values, function(key: Modals.PreferenceKey, value: boolean)
		if key == "sfx" then
			Sfx.setEnabled(value)
		elseif key == "vfx" then
			Vfx.setEnabled(value)
		elseif key == "shake" then
			Vfx.setShakeEnabled(value)
		end
		StateStore.send("setting", { key = key, value = value })
	end)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

--- One tab's width.
---
--- The tabs are the elastic element on the strip: their width is whatever
--- `Layout` managed to leave between the left edge and the rate band, so the
--- strip never shows a hole between STORE and the readout on a wide window and
--- never overlaps on a narrow one.
local function tabWidth(): number
	return Layout.TAB_W
end

local function placeTabs()
	local row = tabRow
	if row == nil then
		return
	end
	local width = tabWidth()
	row.Size = UDim2.fromOffset(#SECTIONS * width + Layout.TAB_GAP * (#SECTIONS - 1), 34)
	for _, handle in tabHandles do
		handle.button.Size = UDim2.fromOffset(width, 34)
	end
end

--- Moves the strip and the section host after a window resize.
---
--- The strip and the panel take their size straight from `Layout`. Section
--- content is deliberately not touched: rows are elastic in X, so a wider section
--- is the same rows with more room, which is what a resize should mean.
---
--- The utility keys moved to the top bar. A strip that carried tabs, three
--- overlays, the rate readout, the vault and the gear was five controls deep on a
--- 46px band, and every one of them was competing with the tab row for width.
function Sections.layout()
	if nav == nil then
		return
	end
	nav.Size = UDim2.fromOffset(Layout.CONTENT_W, Layout.NAV_H)
	nav.Position = UDim2.fromOffset(Layout.CONTENT_X, Layout.NAV_Y)

	if host then
		host.Size = UDim2.fromOffset(Layout.CONTENT_W, Layout.CONTENT_H)
		host.Position = UDim2.fromOffset(Layout.CONTENT_X, Layout.CONTENT_Y)
	end

	placeTabs()
end

function Sections.init(canvas: Frame, forgeCard: Frame?, pageCards: { [string]: Frame }?)
	-- Nav strip. One solid plate across the full width: sections on the left,
	-- the rate readout and the overlay keys on the right. The rate readout is
	-- built by `HudController` and floats over this strip at ZIndex 12, because
	-- that module already owns the stall detector and the two facts belong
	-- together.
	local strip = UiKit.panel(canvas, {
		tier = "shell",
		radius = Theme.Radius.lg,
	})
	strip.Name = "Nav"
	strip.Size = UDim2.fromOffset(Layout.CONTENT_W, Layout.NAV_H)
	strip.Position = UDim2.fromOffset(Layout.CONTENT_X, Layout.NAV_Y)
	nav = strip

	local row = UiKit.create("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, (Layout.NAV_H - 34) / 2),
		Size = UDim2.fromOffset(#SECTIONS * (Layout.TAB_W + Layout.TAB_GAP), 34),
	}) :: Frame
	row.Parent = strip
	tabRow = row
	UiKit.hlist(row, Layout.TAB_GAP, Enum.VerticalAlignment.Center)

	local width = tabWidth()
	for index, def in SECTIONS do
		local handle = UiKit.tab(row, {
			text = def.label,
			accent = def.accent,
			width = width,
			height = 34,
			onSelect = function()
				Sections.select(def.key)
			end,
		})
		local button = handle.button
		button.Name = string.format("Tab_%s", def.label)
		button.LayoutOrder = index
		tabHandles[def.key] = handle
	end

	settingsListener = StateStore.onSync(function(payload)
		-- Keep the audio gate honest on a fresh client: the saved preference is
		-- authoritative, and applying it on every payload cannot fight a local
		-- tap because the tap writes through the server first.
		Sfx.setEnabled(payload.settings.sfx)
	end)

	-- Section panel. Every management screen is the same shell, the same banner
	-- position and the same scroll rect, so switching sections swaps content
	-- without moving the frame the player is looking at.
	local panel = UiKit.panel(canvas, {
		tier = "shell",
		radius = Theme.Radius.xl,
	})
	panel.Name = "Section"
	panel.Size = UDim2.fromOffset(Layout.CONTENT_W, Layout.CONTENT_H)
	panel.Position = UDim2.fromOffset(Layout.CONTENT_X, Layout.CONTENT_Y)
	panel.Visible = false
	host = panel

	for _, def in SECTIONS do
		if def.init then
			-- Header: a banner only as wide as its title, with the kicker set
			-- beside it. A full-width 21px plank with one word in the middle was
			-- the same mistake the side panel made in reverse: it took the whole
			-- screen and said one thing.
			local banner = UiKit.banner(panel, {
				text = def.title,
				position = UDim2.fromOffset(18, 14),
				width = UDim2.fromOffset(430, 46),
				size = 21,
				accent = def.accent,
				icon = def.icon,
			})
			banner.Name = "Banner_" .. def.key
			banner.Visible = false
			banners[def.key] = banner

			local kicker = UiKit.label(panel, {
				text = def.kicker,
				size = Theme.Text.Micro,
				font = Theme.Font.Label,
				color = Theme.Color.textFaint,
			})
			kicker.Name = "Kicker_" .. def.key
			kicker.Position = UDim2.fromOffset(466, 26)
			kicker.Size = UDim2.new(1, -484, 0, 22)
			kicker.TextYAlignment = Enum.TextYAlignment.Center
			kicker.Visible = false
			kickers[def.key] = kicker
		end
	end

	local scroll = UiKit.scroll(panel)
	scroll.Name = "Content"
	scroll.Size = UDim2.new(1, -36, 1, -112)
	scroll.Position = UDim2.fromOffset(18, 92)
	content = scroll

	-- Two columns. At 1685 design px a single column of rows stretches a card to
	-- the full width: two 500px buttons inside one row, five 330px ladder rungs.
	-- That is not a wide layout, it is a narrow one pulled apart. The reference
	-- runs two columns of cards for exactly this reason, so sections do too.
	--
	-- Each column stacks its own rows and sizes to its own height; the scroll
	-- frame takes the taller of the two. Rows are handed to a zero-size sink and
	-- re-parented on arrival into whichever column is currently shorter, which
	-- keeps every view's own code untouched: they parent a row, it lands, and
	-- the balance is the host's business.
	local function makeColumn(x: UDim2, name: string): Frame
		local column = UiKit.create("Frame", {
			Name = name,
			BackgroundTransparency = 1,
			Position = x,
			Size = UDim2.new(0.5, -Theme.Space.sm / 2, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		}) :: Frame
		UiKit.vlist(column, { gap = Theme.Space.sm, padBottom = Theme.Space.lg })
		column.Parent = scroll
		return column
	end

	local left = makeColumn(UDim2.new(0, 0, 0, 0), "ColumnLeft")
	local right = makeColumn(UDim2.new(0.5, Theme.Space.sm / 2, 0, 0), "ColumnRight")
	columns = { left, right }

	-- The canvas is measured, not automatic. `AutomaticCanvasSize` refuses to
	-- size a canvas from children that are themselves automatic, and the result
	-- was a 0-height canvas over 400px of rows: the section simply could not be
	-- scrolled. Each column knows its own height, so the scroll takes the taller
	-- of the two whenever either changes.
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.None
	local function fitCanvas()
		if content == nil then
			return
		end
		local height = 0
		for _, column in columns do
			height = math.max(height, column.AbsoluteSize.Y)
		end
		content.CanvasSize = UDim2.fromOffset(0, height + Theme.Space.lg)
	end
	for _, column in columns do
		UiKit.track(column, column:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitCanvas))
	end

	local sink = UiKit.create("Frame", {
		Name = "Sink",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 0),
	}) :: Frame
	sink.Parent = scroll
	rowSink = sink

	-- Rows are handed to a zero-size sink and sorted into the columns here, one
	-- frame later.
	--
	-- The rules, in order of how much they matter:
	--   1. A plain `TextLabel` is a section header in every one of these views,
	--      so a header and the cards under it are one block. "BOOSTS" never ends
	--      up at the bottom of the left column with its buttons at the top of the
	--      right.
	--   2. A block taller than a screen and a half is a list, not a group — the
	--      tech tree is nine nodes under one header — so it is cut into equal
	--      chunks at row boundaries. Below that, a block stays whole even if it
	--      overshoots one column.
	--   3. Blocks are dealt to whichever column is currently shorter.
	type Row = { obj: GuiObject, height: number, header: boolean }
	type Block = { rows: { Row }, height: number }

	local function distribute()
		if sink.Parent == nil then
			return
		end

		local measured = if content then content.AbsoluteSize.Y else 0
		local screenful = math.max(measured, 300)

		-- One ordered pass: heights first, because a row reports its real height
		-- only once it has a width, and nothing here can be parented twice.
		local rows: { Row } = {}
		for _, child in sink:GetChildren() do
			if child:IsA("GuiObject") then
				table.insert(rows, {
					obj = child,
					height = math.max(child.AbsoluteSize.Y, 18),
					header = child:IsA("TextLabel"),
				})
			end
		end

		local groups: { Block } = {}
		local group: Block? = nil
		for _, entry in rows do
			if entry.header or group == nil then
				group = { rows = {}, height = 0 }
				table.insert(groups, group)
			end
			table.insert(group.rows, entry)
			group.height += entry.height
		end

		local blocks: { Block } = {}
		for _, source in groups do
			if source.height > screenful * 1.6 then
				local chunks = math.max(2, math.ceil(source.height / screenful))
				local per = source.height / chunks
				local chunk: Block = { rows = {}, height = 0 }
				local running = 0
				for index, entry in source.rows do
					table.insert(chunk.rows, entry)
					chunk.height += entry.height
					running += entry.height
					if running >= per and index < #source.rows then
						table.insert(blocks, chunk)
						chunk = { rows = {}, height = 0 }
						running = 0
					end
				end
				if #chunk.rows > 0 then
					table.insert(blocks, chunk)
				end
			else
				table.insert(blocks, source)
			end
		end

		local leftHeight = 0
		local rightHeight = 0
		for _, block in blocks do
			local target = if leftHeight <= rightHeight then left else right
			for _, item in block.rows do
				item.obj.Parent = target
			end
			if target == left then
				leftHeight += block.height
			else
				rightHeight += block.height
			end
		end
	end

	distributor = distribute

	if forgeCard then
		forge = forgeCard
		pages.forge = forgeCard
		forgeCard.Visible = true
	end

	if pageCards then
		for key, card in pageCards do
			pages[key] = card
			card.Visible = false
		end
	end

	Sections.layout()
	Sections.select("forge")
end

--- Routes server toasts that are purely informational. Kept here so the nav can
--- flash the relevant tab when something it owns changes.
function Sections.refreshTabBadges()
	local state = StateStore.current
	if state == nil then
		return
	end

	-- Fleet tab glows when the next drone on the best unlocked rung is affordable.
	if active ~= "fleet" then
		local canBuy = state.as >= state.droneCost
		tintFace("fleet", if canBuy then Theme.Color.cyan else nil)
	end

	-- Tech tab glows when any node is affordable.
	if active ~= "tech" then
		local anyAffordable = false
		for _, node in TechTreeConfig.list() do
			local level = state.tech[node.id] or 0
			if level < node.maxLevel and state.qc >= TechTreeConfig.cost(node, level) then
				anyAffordable = true
				break
			end
		end
		tintFace("tech", if anyAffordable then Theme.Color.quantum else nil)
	end
end

function Sections.destroy()
	unmount()
	if settingsListener then
		settingsListener()
		settingsListener = nil
	end
	if nav then
		nav:Destroy()
		nav = nil
	end
	if host then
		host:Destroy()
		host = nil
	end
	content = nil
	forge = nil
	table.clear(pages)
	table.clear(tabHandles)
	table.clear(banners)
	table.clear(kickers)
	table.clear(savedScroll)
	table.clear(columns)
	rowSink = nil
	distributor = nil
	tabRow = nil
	pendingRestore = nil
	scrollEpoch += 1
end

return Sections
