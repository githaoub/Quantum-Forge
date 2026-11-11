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

local ShopView = {}

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

type RowOpts = {
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
	onBuy: () -> (),
}

local function buildCategoryPill(row: Frame, text: string, accent: Color3): Frame
	local pill = UiKit.create("Frame", {
		BackgroundColor3 = accent,
		BackgroundTransparency = 0.84,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(56, 20),
		Position = UDim2.fromOffset(ICON_X, ICON_Y + 26),
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
local function buildIconBadge(row: Frame, imageId: string, accent: Color3): Frame
	local well = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.outline,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
		Position = UDim2.fromOffset(ICON_X, ICON_Y),
	}) :: Frame
	well.Name = "PassBadge"
	UiKit.corner(well, math.floor(ICON_SIZE * 0.5))
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

local function buildRow(parent: Instance, order: number, opts: RowOpts): Frame
	local row = UiKit.panel(parent, {
		tier = "item",
		radius = Theme.Radius.md,
		stroke = opts.accent,
		strokeTransparency = 0.86,
	})
	row.Size = UDim2.new(1, -4, 0, ROW_H)
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
		buildIconBadge(row, iconId, opts.accent)
	else
		buildCategoryPill(row, opts.badge, opts.accent)
	end

	local title = UiKit.label(row, {
		text = opts.name,
		size = Theme.Text.Body,
		font = Theme.Font.Heading,
		color = Theme.Color.text,
	})
	title.Position = UDim2.fromOffset(TEXT_X, 10)
	title.Size = UDim2.new(1, TEXT_W, 0, 22)

	local desc = UiKit.label(row, {
		text = opts.description,
		size = Theme.Text.Micro,
		color = Theme.Color.textSecondary,
		wrap = true,
	})
	desc.Position = UDim2.fromOffset(TEXT_X, 36)
	desc.Size = UDim2.new(1, TEXT_W, 0, 58)

	-- The emerald price plate. `R$` plus the display price, never a bare GET:
	-- the number is the affordance, and it is the same shape on every row.
	local handle = UiKit.actionButton(row, {
		accent = Theme.Color.good,
		height = 34,
		radius = Theme.Radius.sm,
		size = Theme.Text.Small,
		label = string.format("R$ %d", opts.price),
		handler = function()
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
	handle.button.Position = UDim2.new(1, -104, 0.5, -17)
	handle.button.Size = UDim2.fromOffset(92, 34)
	-- An item with no Marketplace id behind it cannot be bought, so it does not
	-- quote a price. A live "R$ 149" plate that answers with a toast is the UI
	-- claiming a product exists; "SOON" is the same row telling the truth.
	if opts.configured then
		handle.set(if opts.enabled then "ready" else "locked", string.format("R$ %d", opts.price), Theme.Color.good)
	else
		handle.set("locked", "SOON", Theme.Color.textFaint)
	end

	return row
end

local function buildHeader(parent: Instance, text: string, order: number)
	local label = UiKit.label(parent, {
		text = text,
		size = Theme.Text.Micro,
		font = Theme.Font.Heading,
		color = Theme.Color.textSecondary,
	})
	label.Size = UDim2.new(1, -4, 0, 20)
	label.LayoutOrder = order
end

function ShopView.init(parent: Instance)
	local order = 0

	buildHeader(parent, "GAME PASSES", order)
	order += 1

	-- Stable display order: a Lua table's iteration order is not guaranteed, so
	-- declaring it explicitly keeps the storefront from reshuffling between
	-- sessions.
	local passOrder = MonetizationConfig.PassOrder
	for _, key in passOrder do
		local def = MonetizationConfig.Passes[key]
		if def then
			buildRow(parent, order, {
				name = def.name,
				description = def.description,
				badge = def.badge,
				icon = def.icon,
				price = def.price,
				accent = Theme.Color.good,
				enabled = def.enabled,
				configured = def.id ~= 0,
				onBuy = function()
					StateStore.send("prompt", { kind = "pass", key = key })
				end,
			})
			order += 1
		end
	end

	buildHeader(parent, "BOOSTS & UTILITY", order)
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
				onBuy = function()
					StateStore.send("prompt", { kind = "product", key = key })
				end,
			})
			order += 1
		end
	end
end

function ShopView.destroy()
	-- Rows own their own connections; destroying the container is enough.
end

return ShopView
