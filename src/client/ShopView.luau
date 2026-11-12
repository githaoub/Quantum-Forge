--!strict
-- Storefront. The client only ever says "prompt for this key" — the server
-- decides whether the key exists, whether it is configured, and what it is
-- worth. Nothing here can be used to grant itself anything.
--
-- Shipping with placeholder IDs (0) is safe: the server refuses to prompt for
-- an unconfigured entry. Rather than let those rows look identical to live ones
-- and eat the click silently, the row says so and skips the remote.
--
-- The row is built like a real storefront: a category pill beside the name, a
-- two-line description, and an emerald price plate (`R$ 99`) instead of a
-- generic GET.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MonetizationConfig = require(Shared:WaitForChild("MonetizationConfig"))
local AssetManifest = require(Shared:WaitForChild("AssetManifest"))

local Theme = require(script.Parent.Theme)
local UiKit = require(script.Parent.UiKit)
local StateStore = require(script.Parent.StateStore)
local Notifications = require(script.Parent.Notifications)
local Types = require(Shared:WaitForChild("Types"))

local ShopView = {}

--- Rows are built once. Pass ownership arrives later (join refresh or a
--- purchase), so the buttons are kept by key and repainted from the sync.
local ownedPasses: { [string]: boolean } = {}
local passRows: { [string]: { handle: UiKit.ActionHandle, def: MonetizationConfig.PassDef } } = {}
--- Last painted face per row. The sync runs at 10 Hz, and calling `set` every
--- packet would wipe the hover tint under the cursor. Compare first, repaint only
--- when the receipt or the price actually changes.
local passPaint: { [string]: string } = {}
--- `StateStore.onSync` returns an unsubscribe function, not a connection. The
--- old `:Disconnect()` call took the whole section teardown down with it, which
--- left the store painted over the next section.
local passSubscription: (() -> ())? = nil

--- Row geometry. 104 tall holds a 72px badge beside a 22px title and a
--- three-line 14px description with 8px to spare. The badge is 72 rather than
--- 56 because the store actually draws it at 0.719 scale: 48 design px was
--- 34.5 real px, which is where the first badge art died. 72 design px is 51.8
--- real px, and the thumbnail behind it is 420, so nothing is thrown away.
local ROW_H = 104
local ICON_SIZE = 72
local ICON_X = 10
local ICON_Y = 16
local TEXT_X = ICON_X + ICON_SIZE + 14
--- Leaves exactly 8px between the text column and the 92px price plate, which
--- is pinned at `1, -104`.
local TEXT_W = -(TEXT_X + 112)

--- Feature rows. The two offers worth leading with — the VIP bundle and the
--- starter pack — take a 176px plate with a 112px badge, a ribbon and a larger
--- price, so the storefront has a top rather than nine identical rows. The
--- distributor deals blocks, not columns, so a full-width banner would need a
--- layout change; a tall tile reads as a banner inside the grid it already has.
local HERO_H = 176
local HERO_ICON = 112
local HERO_TEXT_X = ICON_X + HERO_ICON + 16
local HERO_TEXT_W = -(HERO_TEXT_X + 132)

type RowOpts = {
	--- Pass config key. Only pass rows carry it; products are consumables and
	--- never print `BOUGHT`.
	key: string?,
	name: string,
	description: string,
	badge: string,
	--- Key into `AssetManifest.GamepassIcons`. Nil, or a key with no uploaded
	--- id, keeps the text pill.
	icon: string?,
	price: number,
	accent: Color3,
	enabled: boolean,
	configured: boolean,
	hero: boolean?,
	ribbon: string?,
	onBuy: () -> (),
}

local function buildCategoryPill(row: Frame, text: string, accent: Color3, y: number): Frame
	local pill = UiKit.create("Frame", {
		BackgroundColor3 = accent,
		BackgroundTransparency = 0.84,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(56, 20),
		Position = UDim2.fromOffset(ICON_X, y),
	}) :: Frame
	UiKit.corner(pill, 4)
	UiKit.stroke(pill, accent, Theme.Stroke.hair, 0.55)
	pill.Parent = row

	local label = UiKit.label(pill, {
		text = text,
		size = Theme.Text.Tiny,
		font = Theme.Font.Heading,
		color = accent,
		align = Enum.TextXAlignment.Center,
	})
	label.Size = UDim2.fromScale(1, 1)

	return pill
end

--- The badge art, in a circular well with a 2px ink ring.
---
--- Deliberately 2px and not `Theme.Stroke.thick` (3px): at 48px the ring is
--- 4% of the badge's width, and 3px starts eating the art. The brief for the
--- store badges calls 2px, so it is passed explicitly rather than by token.
---
--- The well behind the image is the outline colour, not the row's plate. The
--- generated art is a disc on transparent corners, so a near-black well lets
--- those corners disappear into the ring instead of showing a lighter square
--- behind a circle.
---
--- No procedural stand-in lives behind the art. A hand-drawn approximation of
--- an approved badge is a placeholder wearing the badge's clothes: it looks
--- deliberate when the real art is merely late, and it hides the failure.
local function buildIconBadge(row: Frame, imageId: string, accent: Color3, size: number, y: number): Frame
	local well = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.outline,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(size, size),
		Position = UDim2.fromOffset(ICON_X, y),
	}) :: Frame
	well.Name = "PassBadge"
	UiKit.corner(well, math.floor(size * 0.5))
	UiKit.stroke(well, Theme.Color.outline, 2, 0)
	well.Parent = row

	local art = UiKit.create("ImageLabel", {
		Name = "Art",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Image = imageId,
		ScaleType = Enum.ScaleType.Fit,
	}) :: ImageLabel
	art.Parent = well

	-- A 1px accent ring inside the well ties the badge to the row's colour
	-- family without tinting the art. Faint enough that it reads as a bevel.
	local accentStroke = UiKit.create("UIStroke", {
		Color = accent,
		Thickness = 1,
		Transparency = 0.7,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}) :: UIStroke
	accentStroke.Parent = well

	return well
end

local function buildRow(parent: Instance, order: number, opts: RowOpts): (Frame, UiKit.ActionHandle)
	local hero = opts.hero == true
	local height = if hero then HERO_H else ROW_H
	local iconSize = if hero then HERO_ICON else ICON_SIZE
	local iconY = if hero then 16 else ICON_Y
	local textX = if hero then HERO_TEXT_X else TEXT_X
	local textW = if hero then HERO_TEXT_W else TEXT_W

	local row = UiKit.panel(parent, {
		tier = if hero then "raised" else "item",
		radius = Theme.Radius.md,
		stroke = opts.accent,
		strokeTransparency = if hero then 0.7 else 0.86,
	})
	row.Name = if hero then "HeroRow" else "ShopRow"
	row.Size = UDim2.new(1, -4, 0, height)
	row.LayoutOrder = order

	local stripe = UiKit.create("Frame", {
		BackgroundColor3 = opts.accent,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 4, 1, -26),
		Position = UDim2.fromOffset(0, 13),
	}) :: Frame
	UiKit.corner(stripe, 2)
	stripe.Parent = row

	-- Badge art when it exists, category pill when it does not. The pill is not
	-- a placeholder for missing art - it is the fallback that survives a fresh
	-- clone with no uploads, so the row never renders an empty ImageLabel.
	local iconId = if opts.icon then AssetManifest.gamepassIcon(opts.icon) else ""
	if iconId ~= "" then
		buildIconBadge(row, iconId, opts.accent, iconSize, iconY)
	else
		buildCategoryPill(row, opts.badge, opts.accent, iconY + iconSize - 30)
	end

	local title = UiKit.label(row, {
		text = opts.name,
		size = if hero then Theme.Text.Heading else Theme.Text.Body,
		font = Theme.Font.Heading,
		color = Theme.Color.text,
	})
	title.Position = UDim2.fromOffset(textX, if hero then 14 else 10)
	title.Size = UDim2.new(1, textW, 0, if hero then 26 else 22)

	local desc = UiKit.label(row, {
		text = opts.description,
		size = Theme.Text.Micro,
		color = Theme.Color.textSecondary,
		wrap = true,
	})
	desc.Position = UDim2.fromOffset(textX, if hero then 46 else 36)
	desc.Size = UDim2.new(1, textW, 0, if hero then 86 else 58)

	if hero and opts.ribbon then
		local ribbon = UiKit.create("Frame", {
			BackgroundColor3 = Theme.Color.gold,
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(textX, 118),
			Size = UDim2.fromOffset(96, 22),
		}) :: Frame
		UiKit.corner(ribbon, 3)
		ribbon.Parent = row
		local ribbonLabel = UiKit.label(ribbon, {
			text = opts.ribbon,
			size = Theme.Text.Tiny,
			font = Theme.Font.Black,
			color = Theme.onColor(Theme.Color.gold),
			align = Enum.TextXAlignment.Center,
		})
		ribbonLabel.Size = UDim2.fromScale(1, 1)
	end

	-- The emerald price plate. `R$` plus the display price, never a bare GET:
	-- the number is the affordance, and it is the same shape on every row.
	local handle = UiKit.actionButton(row, {
		accent = Theme.Color.good,
		height = 34,
		radius = Theme.Radius.sm,
		size = Theme.Text.Small,
		label = string.format("R$ %d", opts.price),
		handler = function()
			if opts.key ~= nil and ownedPasses[opts.key] == true then
				return
			end
			if not opts.enabled then
				return
			end
			if not opts.configured then
				Notifications.push("This item is not on sale yet.", "warn")
				return
			end
			opts.onBuy()
		end,
	})
	handle.button.Position = UDim2.new(1, if hero then -124 else -104, 0.5, if hero then -22 else -17)
	handle.button.Size = UDim2.fromOffset(if hero then 112 else 92, if hero then 44 else 34)
	-- An item with no Marketplace id behind it cannot be bought, so it does not
	-- quote a price. A live "R$ 149" plate that answers with a toast is the UI
	-- claiming a product exists; "SOON" is the same row telling the truth.
	if opts.configured then
		handle.set(if opts.enabled then "ready" else "locked", string.format("R$ %d", opts.price), Theme.Color.good)
	else
		handle.set("locked", "SOON", Theme.Color.textFaint)
	end

	return row, handle
end

--- Repaints every pass button from the server's ownership table. A bought pass
--- keeps its green key but stops being a key: the label is the receipt, and
--- `Active` is off so a hover cannot make it look buyable again. Products are
--- deliberately absent: a consumable is never owned.
local function applyPasses(state: Types.SyncPayload)
	ownedPasses = state.ownedPasses or {}
	for key, entry in passRows do
		local def = entry.def
		local kind: UiKit.ActionKind
		local label: string
		local accent: Color3
		if ownedPasses[key] == true then
			kind, label, accent = "ready", "BOUGHT", Theme.Color.good
		elseif def.enabled and def.id ~= 0 then
			kind, label, accent = "ready", string.format("R$ %d", def.price), Theme.Color.good
		else
			kind, label, accent = "locked", "SOON", Theme.Color.textFaint
		end

		local paint = string.format("%s:%s", kind, label)
		if passPaint[key] ~= paint then
			passPaint[key] = paint
			entry.handle.set(kind, label, accent)
		end
		entry.handle.button.Active = kind == "ready" and ownedPasses[key] ~= true
	end
end

--- Group header. A 14px caption over a stack of 104px plates was invisible, so
--- the header is now a 15px black rule-of-the-store sign with the count beside
--- it. It stays a TextLabel because the row distributor uses that class to keep
--- a header attached to the rows it introduces.
local function buildHeader(parent: Instance, text: string, count: number, order: number)
	local label = UiKit.label(parent, {
		text = string.format("%s   /   %d", text, count),
		size = Theme.Text.Small,
		font = Theme.Font.Black,
		color = Theme.Color.textDim,
	})
	label.Size = UDim2.new(1, -4, 0, 24)
	label.LayoutOrder = order
end

function ShopView.init(parent: Instance)
	local order = 0
	passRows = {}
	passPaint = {}

	buildHeader(parent, "GAME PASSES", #MonetizationConfig.PassOrder, order)
	order += 1

	-- Stable display order: a Lua table's iteration order is not guaranteed, so
	-- declaring it explicitly keeps the storefront from reshuffling between
	-- sessions.
	local passOrder = MonetizationConfig.PassOrder
	local separateTotal = 0
	for _, other in passOrder do
		local otherDef = MonetizationConfig.Passes[other]
		if otherDef and other ~= "vipAura" then
			separateTotal += otherDef.price
		end
	end
	for _, key in passOrder do
		local def = MonetizationConfig.Passes[key]
		if def then
			local description = def.description
			if key == "vipAura" and separateTotal > def.price then
				description = string.format("%s Buy separately: R$ %d.", description, separateTotal)
			end
			local _, handle = buildRow(parent, order, {
				key = key,
				name = def.name,
				description = description,
				badge = def.badge,
				icon = def.icon,
				price = def.price,
				accent = Theme.Color.good,
				enabled = def.enabled,
				configured = def.id ~= 0,
				hero = key == "vipAura",
				ribbon = if key == "vipAura" then "BEST VALUE" else nil,
				onBuy = function()
					StateStore.send("prompt", { kind = "pass", key = key })
				end,
			})
			passRows[key] = { handle = handle, def = def }
			order += 1
		end
	end

	-- The first payload may already be in hand (a repaint after a hot reload);
	-- otherwise the sync below paints as soon as it lands.
	local current = StateStore.current
	if current then
		applyPasses(current)
	end
	passSubscription = StateStore.onSync(applyPasses)

	buildHeader(parent, "BOOSTS & UTILITY", #MonetizationConfig.ProductOrder, order)
	order += 1

	local productOrder = MonetizationConfig.ProductOrder
	for _, key in productOrder do
		local def = MonetizationConfig.Products[key]
		if def then
			buildRow(parent, order, {
				name = def.name,
				description = def.description,
				badge = def.badge,
				icon = def.icon,
				price = def.price,
				accent = Theme.Color.aether,
				enabled = def.enabled,
				configured = def.id ~= 0,
				hero = key == "starterForge",
				ribbon = if key == "starterForge" then "FIRST BUY" else nil,
				onBuy = function()
					StateStore.send("prompt", { kind = "product", key = key })
				end,
			})
			order += 1
		end
	end
end

function ShopView.destroy()
	if passSubscription then
		passSubscription()
		passSubscription = nil
	end
	passRows = {}
	passPaint = {}
	ownedPasses = {}
	-- Rows own their own connections; destroying the container is enough.
end

return ShopView
