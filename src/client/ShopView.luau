--!strict
-- The store is a page, not a list of rows in the section host.
--
-- Why a page. A pass is a permanent decision and a boost is a repeat purchase;
-- stacking them in one column hid the second shelf under a fold and put the
-- same card shape around a bundle and a consumable. The page is a shelf: five
-- permanent passes on top, three boosts under them, every offer visible at
-- once. Nothing scrolls, so no price can hide below the edge.
--
-- Hierarchy, in the order a player reads it:
--   1. The masthead names the shop and states the one rule: no currency packs.
--   2. Permanent passes are gold. The bundle carries the shelf's gold tag and
--      halo, because it is the only offer that replaces the other four.
--   3. Boosts are aether. Instant Overdrive is the repeat purchase, so it is the
--      raised card on the lower shelf, its tag says STACKABLE, and its facts
--      line reports the live multiplier when the player has one running.
--   4. Every action plate is emerald. Category colour never becomes the verb.
--
-- The client only ever says "prompt for this key". The server decides whether
-- the key exists, whether it is configured, and what it is worth.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MonetizationConfig = require(Shared:WaitForChild("MonetizationConfig"))
local AssetManifest = require(Shared:WaitForChild("AssetManifest"))
local Types = require(Shared:WaitForChild("Types"))

local Theme = require(script.Parent.Theme)
local UiKit = require(script.Parent.UiKit)
local StateStore = require(script.Parent.StateStore)
local Notifications = require(script.Parent.Notifications)
local Icons = require(script.Parent.Icons)
local Layout = require(script.Parent.Layout)

local ShopView = {}

-- ---------------------------------------------------------------------------
-- Geometry
-- ---------------------------------------------------------------------------

-- The card is 618 design px tall. The two shelves are measured from the top
-- rather than stacked with automatic sizes: a shop where the second row moves
-- when a description wraps is a shop that breaks on every copy edit.
local PAD = 20
local PASS_H = 246
local BOOST_H = 188
local TILE_GAP = 14
local PASS_HEADER_Y = 98
local PASS_Y = 124
local BOOST_HEADER_Y = 388
local BOOST_Y = 414
local ICON = 64
local PASS_PLATE_H = 40
local BOOST_PLATE_H = 40

type Face = {
	--- Small category word beside the badge. Nil when the card carries a tag.
	eyebrow: string?,
	tag: string?,
	blurb: string,
	--- One scannable value under the divider. Never a repeat of the blurb.
	fact: string,
}

--- Permanent offers. The bundle's fact is built at init from the live prices,
--- so the value claim is a number instead of an adjective.
local PASS_FACE: { [string]: Face } = {
	vipAura = {
		tag = "BEST VALUE",
		blurb = "Every pass, plus the badge and aura.",
		fact = "EVERY PASS · ONE BILL",
	},
	x2StarMatter = {
		eyebrow = "INCOME",
		blurb = "Doubles all income, forever. Adds no boost time.",
		fact = "×2 STAR-MATTER",
	},
	fastForge = {
		eyebrow = "CLICKS",
		blurb = "Doubles accepted clicks per second.",
		fact = "×2 CLICK RATE",
	},
	autoVent = {
		eyebrow = "HEAT",
		blurb = "Vents at 85% heat automatically.",
		fact = "AUTO VENT AT 85%",
	},
	eternalForge = {
		eyebrow = "INCOME",
		blurb = "+25% to all income, forever. Adds no boost time.",
		fact = "+25% INCOME",
	},
}

local PRODUCT_FACE: { [string]: Face } = {
	starterForge = {
		eyebrow = "STARTER",
		tag = "FIRST BUY",
		blurb = "Aether and twenty minutes of double income.",
		fact = "500K AETHER · 20 MIN",
	},
	instantOverdrive = {
		eyebrow = "BOOST",
		tag = "STACKABLE",
		blurb = "Stacks forever, and with 2x. Each charge resets the hour.",
		fact = "×3 PER CHARGE · 1 HOUR",
	},
	expressSalvage = {
		eyebrow = "EXPEDITION",
		blurb = "Instantly completes any expedition in flight.",
		fact = "COMPLETES ANY EXPEDITION",
	},
}

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local root: Frame? = nil
local ownedPasses: { [string]: boolean } = {}
local passTiles: { PassTile } = {}
local passFrames: { Frame } = {}
local boostFrames: { Frame } = {}
local ownedSummary: TextLabel? = nil
local overdriveFact: TextLabel? = nil
--- `StateStore.onSync` returns an unsubscribe function, not a connection.
local passSubscription: (() -> ())? = nil

type PassTile = {
	frame: Frame,
	key: string,
	def: MonetizationConfig.PassDef,
	handle: UiKit.ActionHandle,
	stroke: UIStroke,
	baseColor: Color3,
	baseTransparency: number,
	paint: string,
}

--- Minutes left on a paid boost. The ceiling is one hour, so 60 reads as 1H
--- rather than a countdown that flickers between 59M and 60M.
local function timeLeft(seconds: number): string
	local minutes = math.max(1, math.ceil(seconds / 60))
	if minutes >= 60 then
		return "1H"
	end
	return string.format("%dM", minutes)
end

-- ---------------------------------------------------------------------------
-- Pieces
-- ---------------------------------------------------------------------------

--- A gold or aether tag anchored to the top-right of a card. Automatic width
--- keeps the plate tight to the word instead of stretching to a guessed size.
local function buildTag(parent: Instance, text: string, accent: Color3): TextLabel
	local tag = UiKit.label(parent, {
		text = text,
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.onColor(accent),
		align = Enum.TextXAlignment.Center,
	})
	tag.Name = "Tag"
	tag.AutomaticSize = Enum.AutomaticSize.X
	tag.Size = UDim2.fromOffset(0, 22)
	tag.BackgroundColor3 = accent
	tag.BackgroundTransparency = 0
	tag.AnchorPoint = Vector2.new(1, 0)
	tag.Position = UDim2.new(1, -16, 0, 16)
	UiKit.corner(tag, 4)

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = tag

	return tag
end

--- Badge art in a circular well with a 2px ink ring. The ring is deliberately
--- 2px, not the 3px house stroke: at 64px a 3px ring starts eating the art.
local function buildBadge(parent: Instance, imageId: string, accent: Color3)
	local well = UiKit.create("Frame", {
		Name = "Badge",
		BackgroundColor3 = Theme.Color.outline,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(ICON, ICON),
		Position = UDim2.fromOffset(16, 16),
	}) :: Frame
	UiKit.corner(well, math.floor(ICON * 0.5))
	UiKit.stroke(well, Theme.Color.outline, 2, 0)
	well.Parent = parent

	local art = UiKit.create("ImageLabel", {
		Name = "Art",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Image = imageId,
		ScaleType = Enum.ScaleType.Fit,
	}) :: ImageLabel
	art.Parent = well

	local accentStroke = UiKit.create("UIStroke", {
		Color = accent,
		Thickness = 1,
		Transparency = 0.7,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}) :: UIStroke
	accentStroke.Parent = well
end

--- Fallback when no badge art is uploaded. A category plate, not an empty
--- ImageLabel: a fresh clone with no uploads still has a shop.
local function buildCategoryPlate(parent: Instance, text: string, accent: Color3)
	local plate = UiKit.create("Frame", {
		Name = "Badge",
		BackgroundColor3 = accent,
		BackgroundTransparency = 0.86,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(ICON, ICON),
		Position = UDim2.fromOffset(16, 16),
	}) :: Frame
	UiKit.corner(plate, Theme.Radius.card)
	UiKit.stroke(plate, accent, 1, 0.55)
	plate.Parent = parent

	local label = UiKit.label(plate, {
		text = text,
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = accent,
		align = Enum.TextXAlignment.Center,
	})
	label.Size = UDim2.fromScale(1, 1)

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 4)
	pad.PaddingRight = UDim.new(0, 4)
	pad.Parent = plate
end

--- A shelf header: a 3px category tick, the lane name, a live summary on the
--- right, and one rule under both. The rule is the shelf edge; the cards sit
--- 4px under it.
local function buildShelf(parent: Instance, y: number, text: string, accent: Color3, summary: string): TextLabel
	local tick = UiKit.create("Frame", {
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(PAD, y + 2),
		Size = UDim2.fromOffset(3, 14),
	}) :: Frame
	UiKit.corner(tick, 2)
	tick.Parent = parent

	local name = UiKit.label(parent, {
		text = text,
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.textDim,
	})
	name.Position = UDim2.fromOffset(PAD + 11, y - 2)
	name.Size = UDim2.new(1, -(PAD * 2 + 200), 0, 18)

	local right = UiKit.label(parent, {
		text = summary,
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Right,
	})
	right.Position = UDim2.fromOffset(PAD, y - 2)
	right.Size = UDim2.new(1, -PAD * 2, 0, 18)

	local rule = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.stroke,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(PAD, y + 22),
		Size = UDim2.new(1, -PAD * 2, 0, 1),
	}) :: Frame
	rule.Parent = parent

	return right
end

--- The price plate. Same emerald key on every card, full width at the foot, so
--- the affordance is in the same place no matter what is above it.
local function buildPlate(parent: Instance, height: number, y: number, opts: {
	label: string,
	kind: UiKit.ActionKind,
	handler: () -> (),
}): UiKit.ActionHandle
	local handle = UiKit.actionButton(parent, {
		accent = Theme.Color.good,
		height = height,
		radius = Theme.Radius.sm,
		size = 15,
		kind = opts.kind,
		label = opts.label,
		handler = opts.handler,
	})
	handle.button.Position = UDim2.fromOffset(16, y)
	handle.button.Size = UDim2.new(1, -32, 0, height)
	return handle
end

-- ---------------------------------------------------------------------------
-- Cards
-- ---------------------------------------------------------------------------

local function buildPassCard(parent: Frame, key: string, def: MonetizationConfig.PassDef, separateTotal: number): PassTile
	local accent = if key == "vipAura" then Theme.Color.gold else Theme.Color.stroke
	local transparency = if key == "vipAura" then 0.62 else 0
	local card = UiKit.panel(parent, {
		tier = if key == "vipAura" then "raised" else "item",
		radius = Theme.Radius.card,
		stroke = accent,
		strokeTransparency = transparency,
	})
	card.Name = "PassCard_" .. key
	card.Size = UDim2.fromOffset(280, PASS_H)
	local stroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke

	local face = PASS_FACE[key] or {
		eyebrow = nil,
		tag = nil,
		blurb = def.description,
		fact = def.badge,
	}

	-- The bundle is the one poster on the shelf. A soft gold disc behind the
	-- badge gives it weight without a second card style or a gradient.
	if key == "vipAura" then
		local halo = UiKit.create("Frame", {
			BackgroundColor3 = Theme.Color.gold,
			BackgroundTransparency = 0.9,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(ICON + 24, ICON + 24),
			Position = UDim2.fromOffset(4, 4),
		}) :: Frame
		UiKit.corner(halo, math.floor((ICON + 24) * 0.5))
		halo.Parent = card
	end

	local iconId = if def.icon then AssetManifest.gamepassIcon(def.icon) else ""
	if iconId ~= "" then
		buildBadge(card, iconId, Theme.Color.gold)
	else
		buildCategoryPlate(card, def.badge, Theme.Color.gold)
	end

	if face.tag then
		buildTag(card, face.tag, Theme.Color.gold)
	elseif face.eyebrow then
		local eyebrow = UiKit.label(card, {
			text = face.eyebrow,
			size = Theme.Text.Tiny,
			font = Theme.Font.Black,
			color = Theme.Color.textFaint,
		})
		eyebrow.Position = UDim2.fromOffset(88, 24)
		eyebrow.Size = UDim2.new(1, -104, 0, 16)
	end

	local title = UiKit.label(card, {
		text = def.name,
		size = 20,
		font = Theme.Font.Heading,
		color = Theme.Color.text,
	})
	title.Position = UDim2.fromOffset(16, 82)
	title.Size = UDim2.new(1, -32, 0, 28)

	local desc = UiKit.label(card, {
		text = face.blurb,
		size = Theme.Text.Micro,
		color = Theme.Color.textSecondary,
		wrap = true,
	})
	desc.Position = UDim2.fromOffset(16, 112)
	desc.Size = UDim2.new(1, -32, 0, 52)

	local rule = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.strokeFaint,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(16, 168),
		Size = UDim2.new(1, -32, 0, 1),
	}) :: Frame
	rule.Parent = card

	local factText = if key == "vipAura" and separateTotal > def.price
		then string.format("R$ %d SEPARATELY", separateTotal)
		else face.fact
	local fact = UiKit.label(card, {
		text = factText,
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = if key == "vipAura" then Theme.Color.gold else Theme.Color.textDim,
	})
	fact.Position = UDim2.fromOffset(16, 172)
	fact.Size = UDim2.new(1, -32, 0, 16)

	local handle = buildPlate(card, PASS_PLATE_H, 190, {
		label = if def.enabled and def.id ~= 0 then string.format("R$ %d", def.price) else "SOON",
		kind = if def.enabled and def.id ~= 0 then "ready" else "locked",
		handler = function()
			if ownedPasses[key] == true then
				return
			end
			if not def.enabled then
				return
			end
			if def.id == 0 then
				Notifications.push("This pass is not on sale yet.", "warn")
				return
			end
			StateStore.send("prompt", { kind = "pass", key = key })
		end,
	})

	return {
		frame = card,
		key = key,
		def = def,
		handle = handle,
		stroke = stroke,
		baseColor = accent,
		baseTransparency = transparency,
		paint = "",
	}
end

local function buildBoostCard(parent: Frame, key: string, def: MonetizationConfig.ProductDef): (Frame, TextLabel)
	local accent = Theme.Color.aether
	-- Instant Overdrive is the repeat purchase. It keeps the old hero slot by
	-- being the one raised card on the lower shelf, in aether rather than gold.
	local featured = key == "instantOverdrive"
	local card = UiKit.panel(parent, {
		tier = if featured then "raised" else "item",
		radius = Theme.Radius.card,
		stroke = if featured then Theme.Color.aether else Theme.Color.stroke,
		strokeTransparency = if featured then 0.7 else 0,
	})
	card.Name = "BoostCard_" .. key
	card.Size = UDim2.fromOffset(300, BOOST_H)

	local face = PRODUCT_FACE[key] or {
		eyebrow = nil,
		tag = nil,
		blurb = def.description,
		fact = def.badge,
	}

	if featured then
		local halo = UiKit.create("Frame", {
			BackgroundColor3 = Theme.Color.aether,
			BackgroundTransparency = 0.9,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(ICON + 24, ICON + 24),
			Position = UDim2.fromOffset(4, 4),
		}) :: Frame
		UiKit.corner(halo, math.floor((ICON + 24) * 0.5))
		halo.Parent = card
	end

	local iconId = if def.icon then AssetManifest.gamepassIcon(def.icon) else ""
	if iconId ~= "" then
		buildBadge(card, iconId, accent)
	else
		buildCategoryPlate(card, def.badge, accent)
	end

	if face.tag then
		buildTag(card, face.tag, accent)
	end

	if face.eyebrow then
		local eyebrow = UiKit.label(card, {
			text = face.eyebrow,
			size = Theme.Text.Tiny,
			font = Theme.Font.Black,
			color = Theme.Color.textFaint,
		})
		eyebrow.Position = UDim2.fromOffset(88, 16)
		eyebrow.Size = UDim2.new(1, -178, 0, 16)
	end

	local title = UiKit.label(card, {
		text = def.name,
		size = 20,
		font = Theme.Font.Heading,
		color = Theme.Color.text,
	})
	title.Position = UDim2.fromOffset(88, 32)
	title.Size = UDim2.new(1, -178, 0, 26)

	local desc = UiKit.label(card, {
		text = face.blurb,
		size = Theme.Text.Micro,
		color = Theme.Color.textSecondary,
		wrap = true,
	})
	desc.Position = UDim2.fromOffset(16, 84)
	desc.Size = UDim2.new(1, -32, 0, 20)

	local rule = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.strokeFaint,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(16, 106),
		Size = UDim2.new(1, -32, 0, 1),
	}) :: Frame
	rule.Parent = card

	local fact = UiKit.label(card, {
		text = face.fact,
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.textFaint,
	})
	fact.Name = "Fact"
	fact.Position = UDim2.fromOffset(16, 110)
	fact.Size = UDim2.new(1, -32, 0, 18)

	buildPlate(card, BOOST_PLATE_H, 132, {
		label = if def.enabled and def.id ~= 0 then string.format("R$ %d", def.price) else "SOON",
		kind = if def.enabled and def.id ~= 0 then "ready" else "locked",
		handler = function()
			if not def.enabled then
				return
			end
			if def.id == 0 then
				Notifications.push("This item is not on sale yet.", "warn")
				return
			end
			StateStore.send("prompt", { kind = "product", key = key })
		end,
	})

	return card, fact
end

-- ---------------------------------------------------------------------------
-- State paint
-- ---------------------------------------------------------------------------

local function paintPass(tile: PassTile)
	local owned = ownedPasses[tile.key] == true
	local def = tile.def
	local kind: UiKit.ActionKind
	local label: string
	local accent: Color3
	if owned then
		kind, label, accent = "equipped", "BOUGHT", Theme.Color.emerald
	elseif def.enabled and def.id ~= 0 then
		kind, label, accent = "ready", string.format("R$ %d", def.price), Theme.Color.good
	else
		kind, label, accent = "locked", "SOON", Theme.Color.textFaint
	end

	if tile.paint ~= kind .. ":" .. label then
		tile.paint = kind .. ":" .. label
		tile.handle.set(kind, label, accent)
	end

	-- The border carries ownership, not the plate alone: a bought pass should
	-- read as a finished card from across the shelf. It stays faint so five
	-- owned passes do not draw five green frames around the shelf. VIP keeps
	-- its gold border: the bundle's identity outranks its receipt.
	if owned and not (tile.key == "vipAura") then
		tile.stroke.Color = Theme.Color.emerald
		tile.stroke.Transparency = 0.78
	else
		tile.stroke.Color = tile.baseColor
		tile.stroke.Transparency = tile.baseTransparency
	end
end

local function applyState(state: Types.SyncPayload)
	ownedPasses = state.ownedPasses or {}

	local owned = 0
	for _, tile in passTiles do
		if ownedPasses[tile.key] == true then
			owned += 1
		end
		paintPass(tile)
	end

	if ownedSummary then
		local text = string.format("%d / %d OWNED", owned, #passTiles)
		if ownedSummary.Text ~= text then
			ownedSummary.Text = text
			ownedSummary.TextColor3 = if #passTiles > 0 and owned == #passTiles
				then Theme.Color.emerald
				else Theme.Color.textFaint
		end
	end

	if overdriveFact then
		local remaining = state.paidBoostRemaining or 0
		local text, color
		if remaining > 0 then
			-- The multiplier is the live paid track, not an assumed x3: ten
			-- charges read x30 even though each charge is worth x3.
			local mult = math.max(1, math.floor((state.paidBoostMult or 1) + 0.5))
			text = string.format("LIVE ×%d · %s LEFT", mult, timeLeft(remaining))
			color = Theme.Color.aether
		else
			text = "×3 PER CHARGE · 1 HOUR"
			color = Theme.Color.textFaint
		end
		if overdriveFact.Text ~= text then
			overdriveFact.Text = text
			overdriveFact.TextColor3 = color
		end
	end
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

local function placeRow(frames: { Frame }, y: number, height: number, total: number)
	local count = #frames
	if count == 0 then
		return
	end
	local width = math.floor((total - TILE_GAP * (count - 1)) / count)
	local x = 0
	for index, frame in frames do
		local w = if index == count then total - x else width
		frame.Position = UDim2.fromOffset(PAD + x, y)
		frame.Size = UDim2.fromOffset(w, height)
		x += w + TILE_GAP
	end
end

function ShopView.layout()
	local card = root
	if card == nil then
		return
	end
	card.Size = UDim2.fromOffset(Layout.CONTENT_W, Layout.CONTENT_H)
	card.Position = UDim2.fromOffset(Layout.CONTENT_X, Layout.CONTENT_Y)
	local inner = Layout.CONTENT_W - PAD * 2
	placeRow(passFrames, PASS_Y, PASS_H, inner)
	placeRow(boostFrames, BOOST_Y, BOOST_H, inner)
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------

function ShopView.init(canvas: Frame, x: number, y: number, width: number, height: number)
	if root then
		return
	end

	local card = UiKit.panel(canvas, {
		tier = "shell",
		radius = Theme.Radius.xl,
		bevel = true,
	})
	card.Name = "Store"
	card.Size = UDim2.fromOffset(width, height)
	card.Position = UDim2.fromOffset(x, y)
	card.Visible = false
	root = card

	-- Masthead. The mark is the only place the store wears its accent as a
	-- filled square; everything under it is plate and rule.
	local mark = UiKit.create("Frame", {
		Name = "Mark",
		BackgroundColor3 = Theme.Color.gold,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(PAD, 19),
		Size = UDim2.fromOffset(44, 44),
	}) :: Frame
	UiKit.corner(mark, Theme.Radius.sm)
	mark.Parent = card

	local markIcon = UiKit.create("Frame", {
		Name = "Glyph",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(24, 24),
	}) :: Frame
	markIcon.Parent = mark
	Icons.build(markIcon, "store", 24, Theme.onColor(Theme.Color.gold))

	local title = UiKit.label(card, {
		text = "QUANTUM STORE",
		size = 30,
		font = Theme.Font.Black,
		color = Theme.Color.text,
	})
	title.Position = UDim2.fromOffset(PAD + 56, 11)
	title.Size = UDim2.new(1, -(PAD * 2 + 56 + 200), 0, 34)

	local subtitle = UiKit.label(card, {
		text = "Every offer multiplies the run you already have.",
		size = Theme.Text.Tiny,
		color = Theme.Color.textSecondary,
	})
	subtitle.Position = UDim2.fromOffset(PAD + 56, 47)
	subtitle.Size = UDim2.new(1, -(PAD * 2 + 56 + 200), 0, 16)

	local trust = UiKit.label(card, {
		text = "NO CURRENCY PACKS",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.gold,
		align = Enum.TextXAlignment.Center,
	})
	trust.Name = "TrustChip"
	trust.AutomaticSize = Enum.AutomaticSize.X
	trust.Size = UDim2.fromOffset(0, 28)
	trust.BackgroundColor3 = Theme.Color.gold
	trust.BackgroundTransparency = 0.9
	trust.AnchorPoint = Vector2.new(1, 0)
	trust.Position = UDim2.new(1, -PAD, 0, 25)
	UiKit.corner(trust, 14)
	UiKit.stroke(trust, Theme.Color.gold, 1, 0.55)

	local trustPad = Instance.new("UIPadding")
	trustPad.PaddingLeft = UDim.new(0, 12)
	trustPad.PaddingRight = UDim.new(0, 12)
	trustPad.Parent = trust

	local headerRule = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.stroke,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(PAD, 86),
		Size = UDim2.new(1, -PAD * 2, 0, 1),
	}) :: Frame
	headerRule.Parent = card

	ownedSummary = buildShelf(
		card,
		PASS_HEADER_Y,
		"PERMANENT PASSES",
		Theme.Color.gold,
		string.format("%d OFFERS", #MonetizationConfig.PassOrder)
	)
	buildShelf(card, BOOST_HEADER_Y, "BOOSTS & UTILITY", Theme.Color.aether, "ALWAYS AVAILABLE")

	-- The bundle's value claim is the sum of the passes it replaces. The row
	-- shows that sum as a fact, so "best value" is arithmetic.
	local separateTotal = 0
	for _, other in MonetizationConfig.PassOrder do
		local otherDef = MonetizationConfig.Passes[other]
		if otherDef and other ~= "vipAura" then
			separateTotal += otherDef.price
		end
	end

	passTiles = {}
	passFrames = {}
	for _, key in MonetizationConfig.PassOrder do
		local def = MonetizationConfig.Passes[key]
		if def then
			local tile = buildPassCard(card, key, def, separateTotal)
			table.insert(passTiles, tile)
			table.insert(passFrames, tile.frame)
		end
	end

	boostFrames = {}
	for _, key in MonetizationConfig.ProductOrder do
		local def = MonetizationConfig.Products[key]
		if def then
			local boost, fact = buildBoostCard(card, key, def)
			table.insert(boostFrames, boost)
			if key == "instantOverdrive" then
				overdriveFact = fact
			end
		end
	end

	local inner = width - PAD * 2
	placeRow(passFrames, PASS_Y, PASS_H, inner)
	placeRow(boostFrames, BOOST_Y, BOOST_H, inner)

	local current = StateStore.current
	if current then
		applyState(current)
	end
	passSubscription = StateStore.onSync(applyState)
end

function ShopView.card(): Frame?
	return root
end

function ShopView.destroy()
	if passSubscription then
		passSubscription()
		passSubscription = nil
	end
	if root then
		root:Destroy()
		root = nil
	end
	passTiles = {}
	passFrames = {}
	boostFrames = {}
	ownedSummary = nil
	overdriveFact = nil
	ownedPasses = {}
end

return ShopView
