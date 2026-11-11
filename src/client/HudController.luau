--!strict
-- Top bar: the three currencies, the ascension readout, and the daily claim.
--
-- Numbers are smoothed toward their server value with exponential decay rather
-- than snapped. At 10Hz a snapped number stutters visibly; smoothed, it looks
-- like it is counting up under its own momentum. The smoothing is display-only
-- — nothing here affects economy state.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local NumberUtil = require(Shared:WaitForChild("NumberUtil"))
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))
local AssetManifest = require(Shared:WaitForChild("AssetManifest"))

local Theme = require(script.Parent.Theme)
local Layout = require(script.Parent.Layout)
local UiKit = require(script.Parent.UiKit)
local Icons = require(script.Parent.Icons)
local ProfilePlate = require(script.Parent.ProfilePlate)
local StateStore = require(script.Parent.StateStore)

local HudController = {}

--- Set by Main so the ascend button can ask for confirmation before firing.
HudController.ascendHandler = nil :: (() -> ())?

--- Set by Main so the "?" button can restart the onboarding guide.
HudController.guideHandler = nil :: (() -> ())?

--- Set by Main: the utility bank is chrome, the overlays are not. Keeping the
--- wiring up here means `HudController` never requires a modal module, and a key
--- with no handler is a silent no-op instead of a boot failure.
HudController.vaultHandler = nil :: (() -> ())?
HudController.codexHandler = nil :: (() -> ())?
HudController.boardsHandler = nil :: (() -> ())?
HudController.tradeHandler = nil :: (() -> ())?
HudController.feedbackHandler = nil :: (() -> ())?
HudController.settingsHandler = nil :: (() -> ())?
HudController.dailyHandler = nil :: (() -> ())?

type Pill = {
	root: Frame,
	value: TextLabel,
	sub: TextLabel,
	current: number,
	target: number,
	format: (number) -> string,
}

local pills: { [string]: Pill } = {}
local topBar: Frame? = nil
local rateStrip: Frame? = nil
local profileHandle: ProfilePlate.Handle? = nil
local ascendButton: TextButton? = nil
local ascendLabel: TextLabel? = nil
local ascendStroke: UIStroke? = nil
local dailyButton: TextButton? = nil
local dailyStroke: UIStroke? = nil
local dailyLabel: TextLabel? = nil
local guideButton: TextButton? = nil
local guideTextLabel: TextLabel? = nil
local unsubscribe: (() -> ())? = nil
local pulse = 0

-- Four states for every number on this bar: loading (no payload yet), live,
-- stale (payload exists but the server went quiet), and the populated value.
-- Painting 0 before the first sync is a lie — 0 is a real balance a fresh player
-- can have, so the placeholder is a pair of hyphens instead.
local PLACEHOLDER = "--"
local STALE_AFTER = 3

local hasPayload = false
local rateText = "No drones online"
local statusKey = ""
local rateValueLabel: TextLabel? = nil
local rateValueShown: boolean? = nil

-- ---------------------------------------------------------------------------
-- Building blocks
-- ---------------------------------------------------------------------------

-- Ten slots on the bar: the profile plate at 240, three pills at 156, then
-- ascend 140, daily 112 and guide 96. The plate and the verb group are pinned to
-- opposite ends, so the elastic space on the bar is the single gap between the
-- currencies and ASCEND — which is where a wider window should breathe, not
-- inside a pill.
local PILL_W = 148
local PILL_H = 58
local PLATE_W = 240
local LEFT_W = PLATE_W + Theme.Space.sm + PILL_W * 3 + Theme.Space.sm * 2

--- Draws the uploaded PNG on top of the vector badge and retires the vector
--- once the bitmap is actually resident.
---
--- The order is deliberate. `ImageTransparency` starts at 1, so the well is
--- never empty while the CDN answers; a failed preload leaves the drawn badge
--- in place rather than a grey box, which is the `IsLoaded` failure the ticket
--- asked about. Only a confirmed load fades the plate, stroke and glyph out
--- underneath the art.
local function attachCurrencyArt(badge: Frame, key: string)
	local source = AssetManifest.currencyArt(key)
	if source == "" then
		return
	end

	local image = UiKit.create("ImageLabel", {
		Name = "CurrencyArt",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(30, 30),
		ScaleType = Enum.ScaleType.Fit,
		Image = source,
		ImageTransparency = 1,
		ZIndex = 8,
	}) :: ImageLabel
	image.Parent = badge

	task.spawn(function()
		local ok = pcall(function()
			ContentProvider:PreloadAsync({ image })
		end)
		if not image.Parent then
			return
		end
		if not ok then
			return
		end
		Theme.fade(image, 0.16, { ImageTransparency = 0 })
		local stroke = badge:FindFirstChildOfClass("UIStroke")
		if stroke then
			Theme.fade(stroke, 0.16, { Transparency = 1 })
		end
		for _, child in badge:GetDescendants() do
			if child ~= image then
				if child:IsA("Frame") then
					Theme.fade(child, 0.16, { BackgroundTransparency = 1 })
				elseif child:IsA("TextLabel") then
					Theme.fade(child, 0.16, { TextTransparency = 1 })
				end
			end
		end
		Theme.fade(badge, 0.16, { BackgroundTransparency = 1 })
	end)
end

--- Currency icon, drawn rather than typed.
---
--- The vent key's `⚡` came out as tofu on clients whose font stack lacked the
--- glyph. These are geometry instead: one proven glyph for the star, a rotated
--- plate for the crystal, concentric circles for the core. None of them can fall
--- back to a box.
---
--- When the custom currency PNG exists, it is laid over this drawing and the
--- drawing retires. The vector stays as the fallback because it is already
--- correct at 32px and a missing upload is not an error state.
local function buildBadge(parent: Frame, accent: Color3, kind: string)
	local artKey = if kind == "star" then "sm" elseif kind == "crystal" then "as" else "qc"
	local badge = UiKit.create("Frame", {
		Name = "Badge",
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(32, 32),
		Position = UDim2.new(0, 9, 0.5, -16),
		ZIndex = 2,
	}) :: Frame
	UiKit.corner(badge, 9)
	UiKit.stroke(badge, Theme.Color.outline, 2.5, 0)
	badge.Parent = parent

	-- Lit cap. One translucent pixel row is the difference between a moulded
	-- badge and a flat colour square.
	local bevel = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.white,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -12, 0, 1),
		Position = UDim2.fromOffset(6, 3),
		ZIndex = 3,
	}) :: Frame
	bevel.Parent = badge

	if kind == "star" then
		local glyph = UiKit.label(badge, {
			text = "★",
			size = 18,
			font = Theme.Font.Black,
			color = Theme.Color.outline,
			align = Enum.TextXAlignment.Center,
		})
		glyph.Size = UDim2.fromScale(1, 1)
		glyph.ZIndex = 3
		attachCurrencyArt(badge, artKey)
		return
	end

	if kind == "crystal" then
		local outer = UiKit.create("Frame", {
			BackgroundColor3 = Theme.Color.outline,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(17, 17),
			Rotation = 45,
			ZIndex = 3,
		}) :: Frame
		UiKit.corner(outer, 3)
		outer.Parent = badge

		-- Rotation is inherited, so the facet stays at 45 rather than doubling to
		-- an axis-aligned square.
		local facet = UiKit.create("Frame", {
			BackgroundColor3 = Theme.Color.white,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(7, 7),
			ZIndex = 4,
		}) :: Frame
		facet.Parent = outer
		attachCurrencyArt(badge, artKey)
		return
	end

	-- Core: cold ring, thin gap, hot centre.
	local ring = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.outline,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(19, 19),
		ZIndex = 3,
	}) :: Frame
	UiKit.corner(ring, 10)
	ring.Parent = badge

	local disc = UiKit.create("Frame", {
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(11, 11),
		ZIndex = 4,
	}) :: Frame
	UiKit.corner(disc, 6)
	disc.Parent = ring

	local core = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.outline,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(5, 5),
		ZIndex = 5,
	}) :: Frame
	UiKit.corner(core, 3)
	core.Parent = ring

	attachCurrencyArt(badge, artKey)
end

local function buildPill(
	parent: Frame,
	order: number,
	accent: Color3,
	caption: string,
	format: (number) -> string,
	icon: string
): Pill
	-- Navy capsule rather than a warm panel: the currency strip is an instrument
	-- sitting on wood, and three wood chips on a wood bar disappear into it.
	local root = UiKit.create("Frame", {
		Name = caption,
		BackgroundColor3 = Theme.Color.slate,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(PILL_W, PILL_H),
		LayoutOrder = order,
	}) :: Frame
	UiKit.corner(root, 12)
	UiKit.gradient(root, { Theme.Color.slateLift, Theme.Color.slate }, 90)
	UiKit.stroke(root, Theme.Color.outline, 2.5, 0)
	root.Parent = parent

	buildBadge(root, accent, icon)

	local value = UiKit.label(root, {
		text = PLACEHOLDER,
		size = Theme.Text.Heading,
		font = Theme.Font.Numeric,
		color = Theme.Color.text,
		stroke = true,
	})
	value.Position = UDim2.fromOffset(48, 8)
	value.Size = UDim2.new(1, -56, 0, 26)

	local sub = UiKit.label(root, {
		text = caption,
		size = Theme.Text.Micro,
		font = Theme.Font.Body,
		color = accent,
	})
	sub.Position = UDim2.fromOffset(48, 34)
	sub.Size = UDim2.new(1, -56, 0, 16)

	return {
		root = root,
		value = value,
		sub = sub,
		current = 0,
		target = 0,
		format = format,
	}
end

local function buildAscendButton(parent: Frame): TextButton
	local button = UiKit.button(parent, {
		text = "",
		fill = Theme.Color.panel,
		stroke = Theme.Color.outline,
		accent = { Theme.Color.quantumDeep, Theme.Color.quantum },
		height = 58,
		radius = Theme.Radius.md,
		handler = function()
			if HudController.ascendHandler then
				HudController.ascendHandler()
			else
				StateStore.send("ascend")
			end
		end,
	})
	button.Size = UDim2.fromOffset(Layout.VERB_W, Layout.KEY_H)
	button.LayoutOrder = 7

	-- The mark sits above the word, same grammar as the utility keys beside it, so
	-- the whole right end of the bar reads as one row of icons rather than as two
	-- buttons that happen to be next to a toolbar.
	local mark = Icons.build(button, "ascend", 20, Theme.Color.gold)
	mark.Position = UDim2.fromOffset((Layout.VERB_W - 20) / 2, 5)
	mark.ZIndex = 2

	local label = UiKit.label(button, {
		text = "ASCEND",
		size = Theme.Text.Small,
		font = Theme.Font.Black,
		color = Theme.Color.text,
		align = Enum.TextXAlignment.Center,
		stroke = true,
	})
	label.Position = UDim2.fromOffset(0, 26)
	label.Size = UDim2.new(1, 0, 0, 18)
	label.ZIndex = 2

	local detail = UiKit.label(button, {
		text = "0 QC",
		size = Theme.Text.Tiny,
		color = Theme.Color.text,
		align = Enum.TextXAlignment.Center,
		stroke = true,
	})
	detail.Position = UDim2.fromOffset(0, 43)
	detail.Size = UDim2.new(1, 0, 0, 14)
	detail.ZIndex = 2
	detail.Name = "Detail"

	ascendLabel = detail
	ascendStroke = button:FindFirstChildOfClass("UIStroke")
	return button
end

local function buildDailyButton(parent: Frame): TextButton
	local button = UiKit.button(parent, {
		text = "",
		fill = Theme.Color.panel,
		stroke = Theme.Color.outline,
		accent = { Theme.Color.emeraldDeep, Theme.Color.emerald },
		height = 58,
		radius = Theme.Radius.md,
		handler = function()
			-- The reward is no longer a one-tap claim: DAILY opens the track, and
			-- the track's own key fires the claim. A player who cannot see what
			-- day seven pays has no reason to come back for it.
			if HudController.dailyHandler then
				HudController.dailyHandler()
			else
				StateStore.send("claimDaily")
			end
		end,
	})
	button.Size = UDim2.fromOffset(Layout.DAILY_W, Layout.KEY_H)
	button.LayoutOrder = 8

	local mark = Icons.build(button, "daily", 20, Theme.Color.emerald)
	mark.Position = UDim2.fromOffset((Layout.DAILY_W - 20) / 2, 5)
	mark.ZIndex = 2

	local label = UiKit.label(button, {
		text = "DAILY",
		size = Theme.Text.Small,
		font = Theme.Font.Black,
		color = Theme.Color.text,
		align = Enum.TextXAlignment.Center,
		stroke = true,
	})
	label.Position = UDim2.fromOffset(0, 26)
	label.Size = UDim2.new(1, 0, 0, 18)
	label.ZIndex = 2

	local detail = UiKit.label(button, {
		text = "not ready",
		size = Theme.Text.Tiny,
		color = Theme.Color.text,
		align = Enum.TextXAlignment.Center,
		stroke = true,
	})
	detail.Position = UDim2.fromOffset(0, 43)
	detail.Size = UDim2.new(1, 0, 0, 14)
	detail.ZIndex = 2

	dailyLabel = detail
	dailyStroke = button:FindFirstChildOfClass("UIStroke")
	return button
end

--- One utility key: a 22px vector mark over a 13px label, 50x62.
---
--- This is the shape the reference uses for its utility row, and it is the only
--- one that survives seven keys abreast: icon-only keys are unlabelled puzzles,
--- and label-only keys at 96px each is what made the old bar look like a menu.
local function buildKey(parent: Frame, opts: {
	name: string,
	icon: string,
	label: string,
	tint: Color3,
	order: number,
	handler: () -> (),
}): TextButton
	local button = UiKit.button(parent, {
		text = "",
		fill = Theme.Color.panelSunken,
		stroke = Theme.Color.stroke,
		height = Layout.KEY_H,
		radius = Theme.Radius.sm,
		handler = opts.handler,
	})
	button.Name = opts.name
	button.Size = UDim2.fromOffset(Layout.KEY_W, Layout.KEY_H)
	button.LayoutOrder = opts.order

	local icon = Icons.build(button, opts.icon, 22, opts.tint)
	icon.Position = UDim2.fromOffset((Layout.KEY_W - 22) / 2, 7)
	icon.ZIndex = 2

	local label = UiKit.label(button, {
		text = opts.label,
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.textSecondary,
		align = Enum.TextXAlignment.Center,
	})
	label.Name = "Face"
	label.Position = UDim2.fromOffset(0, 34)
	label.Size = UDim2.new(1, 0, 0, 16)
	label.ZIndex = 2

	return button
end

--- Replays the onboarding guide. Labelled rather than a bare "?", because the
--- guide is also the only place a returning player can re-read the loop, and the
--- drawn mark is the same one the sheet's rows use.
local function buildGuideButton(parent: Frame): TextButton
	local button = buildKey(parent, {
		name = "GuideButton",
		icon = "guide",
		label = "GUIDE",
		tint = Theme.Color.gold,
		order = 6,
		handler = function()
			if HudController.guideHandler then
				HudController.guideHandler()
			end
		end,
	})
	guideButton = button
	guideTextLabel = button:FindFirstChild("Face") :: TextLabel?
	return button
end

--- Swaps the guide key between "GUIDE" and the live "SKIP" state.
---
--- The icon stays put in both states now. It used to give way to a centred word,
--- which was right when the key was 38px tall and one line; at 62px with a mark
--- above the label, hiding the mark would leave a hole where a picture was.
function HudController.setGuideLabel(text: string, active: boolean)
	if guideButton == nil then
		return
	end
	local label = guideTextLabel
	if label then
		label.Text = text
		label.TextColor3 = if active then Theme.Color.starMatter else Theme.Color.textSecondary
	end
	local stroke = guideButton:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = if active then Theme.Color.starMatter else Theme.Color.stroke
	end
end
-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

--- Re-places the bar and the rate readout after a window resize.
---
--- Nothing here rebuilds: the identity group is pinned left, the verbs are
--- pinned right and the pills sit in a list, so only the two roots have to move
--- when the canvas widens. The gap between the currencies and ASCEND absorbs the
--- difference, which is the whole point of pinning them apart.
function HudController.layout()
	if topBar then
		topBar.Size = UDim2.fromOffset(Layout.CONTENT_W, Layout.TOPBAR_H)
		topBar.Position = UDim2.fromOffset(Layout.CONTENT_X, Layout.TOPBAR_Y)
	end
	if rateStrip then
		rateStrip.Size = UDim2.fromOffset(Layout.RATE_W, Layout.RATE_H)
		rateStrip.Position = UDim2.fromOffset(Layout.RATE_X, Layout.RATE_Y)
	end
end

function HudController.init(canvas: Frame)
	local bar = UiKit.panel(canvas, {
		tier = "shell",
		radius = Theme.Radius.lg,
	})
	bar.Name = "TopBar"
	bar.Size = UDim2.fromOffset(Layout.CONTENT_W, Layout.TOPBAR_H)
	bar.Position = UDim2.fromOffset(Layout.CONTENT_X, Layout.TOPBAR_Y)
	topBar = bar

	-- Left group: identity, then the three currencies. A list rather than hand
	-- offsets because the profile plate is the only child whose width is not a
	-- constant and the three pills have to stay flush against it.
	local left = UiKit.create("Frame", {
		Name = "Identity",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.fromOffset(LEFT_W, Layout.TOPBAR_H),
	}) :: Frame
	left.Parent = bar
	UiKit.hlist(left, Theme.Space.sm, Enum.VerticalAlignment.Center)

	profileHandle = ProfilePlate.build(left)
	local plate = profileHandle.root
	plate.LayoutOrder = 0

	pills.starMatter = buildPill(left, 1, Theme.Color.starMatter, "STAR-MATTER", NumberUtil.abbreviate, "star")
	pills.aether = buildPill(left, 2, Theme.Color.aether, "AETHER", NumberUtil.abbreviate, "crystal")
	pills.quantum = buildPill(left, 3, Theme.Color.quantum, "CORES", NumberUtil.abbreviate, "core")

	-- Right group: the utility bank, then the two verbs. Every control on this
	-- end is the same 62px key with a mark over a word, which is what makes seven
	-- utilities and two verbs read as one toolbar instead of as a pile.
	local right = UiKit.create("Frame", {
		Name = "Actions",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 0),
		Size = UDim2.fromOffset(Layout.RIGHT_CLUSTER, Layout.TOPBAR_H),
	}) :: Frame
	right.Parent = bar
	UiKit.hlist(right, Layout.ACTION_GAP, Enum.VerticalAlignment.Center)

	-- Vault first: it is the thing a player opens twenty times a session, and it
	-- inherits the slot the old icon row occupied on this side of the bar.
	buildKey(right, {
		name = "VaultButton",
		icon = "vault",
		label = "VAULT",
		tint = Theme.Color.gold,
		order = 1,
		handler = function()
			if HudController.vaultHandler then
				HudController.vaultHandler()
			end
		end,
	})

	buildKey(right, {
		name = "CodexButton",
		icon = "codex",
		label = "CODEX",
		tint = Theme.Color.quantum,
		order = 2,
		handler = function()
			if HudController.codexHandler then
				HudController.codexHandler()
			end
		end,
	})

	buildKey(right, {
		name = "BoardsButton",
		icon = "boards",
		label = "BOARDS",
		tint = Theme.Color.emerald,
		order = 3,
		handler = function()
			if HudController.boardsHandler then
				HudController.boardsHandler()
			end
		end,
	})

	buildKey(right, {
		name = "TradeButton",
		icon = "trade",
		label = "TRADE",
		tint = Theme.Color.cyan,
		order = 4,
		handler = function()
			if HudController.tradeHandler then
				HudController.tradeHandler()
			end
		end,
	})

	buildKey(right, {
		name = "FeedbackButton",
		icon = "feedback",
		label = "NOTES",
		tint = Theme.Color.magenta,
		order = 5,
		handler = function()
			if HudController.feedbackHandler then
				HudController.feedbackHandler()
			end
		end,
	})

	guideButton = buildGuideButton(right)

	buildKey(right, {
		name = "SettingsButton",
		icon = "settings",
		label = "SETUP",
		tint = Theme.Color.textFaint,
		order = 7,
		handler = function()
			if HudController.settingsHandler then
				HudController.settingsHandler()
			end
		end,
	})

	ascendButton = buildAscendButton(right)
	dailyButton = buildDailyButton(right)

	-- Rate readout. A compact instrument on the right end of the nav strip,
	-- between the utility keys and the vault and settings keys. Same ownership:
	-- this module already runs the stall detector, so the numbers and the
	-- honesty about them stay in one place.
	--
	-- It is parented to the canvas, not the strip, because the strip is built by
	-- `Sections` after this module runs. ZIndex 12 keeps the whole readout above
	-- the strip, which sits at the default.
	local strip = UiKit.panel(canvas, {
		tier = "well",
		radius = Theme.Radius.sm,
	})
	strip.Name = "RateStrip"
	strip.Size = UDim2.fromOffset(Layout.RATE_W, Layout.RATE_H)
	strip.Position = UDim2.fromOffset(Layout.RATE_X, Layout.RATE_Y)
	strip.ZIndex = 12
	rateStrip = strip

	local rateLabel = UiKit.label(strip, {
		text = "LINKING…",
		size = Theme.Text.Micro,
		color = Theme.Color.textFaint,
	})
	rateLabel.Position = UDim2.fromOffset(10, 0)
	rateLabel.Size = UDim2.new(1, -130, 1, 0)
	rateLabel.Name = "Rate"

	-- The steady number gets its own field, right-aligned and in the currency's
	-- colour. It is the value the player is actually watching, and two facts glued
	-- into one string with a separator is how a HUD starts reading as machine output.
	rateValueLabel = UiKit.label(strip, {
		text = "",
		size = Theme.Text.Micro,
		font = Theme.Font.Numeric,
		color = Theme.Color.starMatter,
		align = Enum.TextXAlignment.Right,
	})
	rateValueLabel.Position = UDim2.fromOffset(10, 0)
	rateValueLabel.Size = UDim2.new(1, -20, 1, 0)
	rateValueLabel.Name = "RateValue"
	rateValueLabel.Visible = false

	pills.rate = {
		root = strip,
		value = rateLabel,
		sub = rateLabel,
		current = 0,
		target = 0,
		format = NumberUtil.abbreviateRate,
	}

	unsubscribe = StateStore.onSync(function(state: Types.SyncPayload)
		HudController.apply(state)
	end)
end

--- The rate strip is also the connection instrument. It is the only place on
--- screen that can honestly say "I have not heard from the server", and a HUD
--- frozen on its last number without saying so is worse than one that admits it.
local function renderStatus()
	local rate = pills.rate
	if rate == nil then
		return
	end

	local live = false
	local text: string
	local color: Color3
	if not hasPayload then
		text = "LINKING…"
		color = Theme.Color.textFaint
	else
		local age = StateStore.staleness()
		if age > STALE_AFTER then
			text = string.format("NO SIGNAL   %.0fs", age)
			color = Theme.Color.warn
		else
			text = rateText
			color = Theme.Color.textDim
			live = true
		end
	end

	-- Only touch the instances when the rendered state actually changes; this runs
	-- every frame.
	if text ~= statusKey then
		statusKey = text
		rate.value.Text = text
		rate.value.TextColor3 = color
	end
	if rateValueLabel and live ~= rateValueShown then
		rateValueShown = live
		rateValueLabel.Visible = live
	end
end

--- Pushes a payload into the display targets.
function HudController.apply(state: Types.SyncPayload)
	local first = not hasPayload
	hasPayload = true

	pills.starMatter.target = state.sm
	pills.aether.target = state.as
	pills.quantum.target = state.qc

	if profileHandle then
		profileHandle.apply(state)
	end

	-- On the first payload the counters snap to the real totals. Counting up from
	-- the placeholder would animate a number the player never had.
	if first then
		pills.starMatter.current = state.sm
		pills.aether.current = state.as
		pills.quantum.current = state.qc
	end

	local passive = state.passiveYield
	pills.rate.target = passive
	if rateValueLabel then
		rateValueLabel.Text = NumberUtil.abbreviateRate(passive)
	end
	-- The status field is a 14px caption, so it carries one short fact. The rate
	-- itself lives in its own right-aligned field below.
	--
	-- A live multiplier outranks the drone count: double income is the loudest
	-- fact on this bar while it lasts, and the fleet size is already printed on
	-- the Fleet tab. The chip is the only place the starter boost exists after
	-- its modal was dismissed, so it is not optional decoration.
	rateText = if state.boostRemaining and state.boostRemaining > 0
		then string.format("x2 BOOST  %s", NumberUtil.abbreviateTime(state.boostRemaining))
		elseif state.drones > 0 then string.format("%s DRONES", NumberUtil.abbreviate(state.drones))
		else "NO DRONES"

	-- Ascension: show the payout, not the raw total. The player cares about
	-- what the button will give them.
	--
	-- The detail line is 88px wide at 13px, so it carries one number and nothing
	-- else. The old `(x3)` ascension suffix pushed `+398.33K QC (x3)` over the
	-- key's edge and into the SETUP key beside it.
	if ascendLabel then
		local thresholdReached = state.sm >= Config.AscendThreshold
		if thresholdReached then
			local cores = math.floor((state.sm / Config.AscendThreshold) ^ Config.AscendExponent)
			ascendLabel.Text = string.format("+%s QC", NumberUtil.abbreviate(cores))
			ascendLabel.TextColor3 = Theme.Color.text
			ascendLabel.TextTransparency = 0
		else
			local remaining = Config.AscendThreshold - state.sm
			ascendLabel.Text = string.format("↓ %s", NumberUtil.abbreviate(remaining))
			ascendLabel.TextColor3 = Theme.Color.text
			ascendLabel.TextTransparency = 0.3
		end
	end

	if dailyLabel then
		if state.dailyReady then
			dailyLabel.Text = string.format("DAY %d", state.dailyStreak % #Config.DailyTrack + 1)
			dailyLabel.TextColor3 = Theme.Color.text
			dailyLabel.TextTransparency = 0
		else
			dailyLabel.Text = "CLAIMED"
			dailyLabel.TextColor3 = Theme.Color.text
			dailyLabel.TextTransparency = 0.3
		end
	end

	renderStatus()
end

--- Runs the smoothing loop. Called once from Main on RenderStepped.
function HudController.step(dt: number)
	pulse += dt

	local factor = 1 - math.exp(-14 * dt)

	for _, pill in pills do
		if hasPayload and pill.value ~= pill.sub then
			pill.current += (pill.target - pill.current) * factor
			-- Snap once the difference is imperceptible so the text stops
			-- re-rendering for a value nobody can see change.
			if math.abs(pill.target - pill.current) < 0.001 then
				pill.current = pill.target
			end
			pill.value.Text = pill.format(pill.current)
		end
	end

	-- Ascend button breathes when it is actionable.
	if ascendButton and ascendStroke then
		local ready = StateStore.current ~= nil and StateStore.current.sm >= Config.AscendThreshold
		if ready then
			ascendStroke.Transparency = 0.25 + math.abs(math.sin(pulse * 2.4)) * 0.45
		else
			ascendStroke.Transparency = 0.85
		end
	end

	if dailyButton and dailyStroke then
		local ready = StateStore.current ~= nil and StateStore.current.dailyReady
		if ready then
			dailyStroke.Transparency = 0.2 + math.abs(math.sin(pulse * 3)) * 0.4
		else
			dailyStroke.Transparency = 0.85
		end
	end

	renderStatus()
end

function HudController.destroy()
	if unsubscribe then
		unsubscribe()
		unsubscribe = nil
	end
	hasPayload = false
	statusKey = ""
	rateText = "No drones online"
	rateValueShown = nil
	rateValueLabel = nil
	if ascendButton then
		ascendButton:Destroy()
		ascendButton = nil
	end
	if dailyButton then
		dailyButton:Destroy()
		dailyButton = nil
	end
	if guideButton then
		guideButton:Destroy()
		guideButton = nil
		guideTextLabel = nil
	end
	if profileHandle then
		profileHandle.destroy()
		profileHandle = nil
	end
	if rateStrip then
		rateStrip:Destroy()
		rateStrip = nil
	end
	if topBar then
		topBar:Destroy()
		topBar = nil
	end
	table.clear(pills)
end

return HudController
