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
local NextGoal = require(script.Parent.NextGoal)

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
HudController.playersHandler = nil :: (() -> ())?
HudController.tradeHandler = nil :: (() -> ())?
HudController.feedbackHandler = nil :: (() -> ())?
HudController.settingsHandler = nil :: (() -> ())?
HudController.dailyHandler = nil :: (() -> ())?
--- Set by Main: the rail-foot NEXT line opens the section it names.
HudController.nextGoalHandler = nil :: ((string) -> ())?

type Pill = {
	root: Frame,
	value: TextLabel,
	sub: TextLabel,
	current: number,
	target: number,
	format: (number) -> string,
}

type MarkPulse = { scale: UIScale, base: number }

local pills: { [string]: Pill } = {}
local topBar: Frame? = nil
local rateStrip: Frame? = nil
local nextGoalLabel: TextLabel? = nil
local nextGoalPercent: TextLabel? = nil
local nextGoalFill: Frame? = nil
local nextGoal: NextGoal.Goal? = nil
local profileHandle: ProfilePlate.Handle? = nil
local ascendButton: TextButton? = nil
local ascendLabel: TextLabel? = nil
local ascendDetail: UiKit.CurrencyRow? = nil
local ascendStroke: UIStroke? = nil
local ascendScale: UIScale? = nil
local ascendGlow: Frame? = nil
local ascendMarkScale: MarkPulse? = nil
local dailyButton: TextButton? = nil
local dailyStroke: UIStroke? = nil
local dailyScale: UIScale? = nil
local dailyGlow: Frame? = nil
local dailyMarkScale: MarkPulse? = nil
local dailyLabel: TextLabel? = nil
local guideButton: TextButton? = nil
local guideTextLabel: TextLabel? = nil
local unsubscribe: (() -> ())? = nil
local pulse = 0

--- Chrome groups and keys. The top bar is built once, but a Studio play window
--- (and a rotating phone) can cross the compact threshold after boot. Keeping
--- the controls here lets `layout` recompute their size and mark positions for
--- the new mode instead of leaving 84px phone keys inside a 76px bar.
local leftGroup: Frame? = nil
local actionGroup: Frame? = nil
local keyButtons: { [string]: TextButton } = {}
local chromeLayout: (() -> ())? = nil

-- Four states for every number on this bar: loading (no payload yet), live,
-- stale (payload exists but the server went quiet), and the populated value.
-- Painting 0 before the first sync is a lie — 0 is a real balance a fresh player
-- can have, so the placeholder is a pair of hyphens instead.
local PLACEHOLDER = "--"
local STALE_AFTER = 3

local hasPayload = false
local rateText = "No drones online"
local rateHighlight = false
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
	value.Name = "Value"
	value.Position = UDim2.fromOffset(48, 8)
	value.Size = UDim2.new(1, -56, 0, 26)

	local sub = UiKit.label(root, {
		text = caption,
		size = Theme.Text.Micro,
		font = Theme.Font.Body,
		color = accent,
	})
	sub.Name = "Sub"
	sub.Position = UDim2.fromOffset(48, 34)
	sub.Size = UDim2.new(1, -56, 0, 16)
	if Layout.COMPACT then
		-- The phone row keeps the icon and the number and drops the caption.
		-- Three 148px capsules beside ten 84px keys do not fit an 800px screen,
		-- and the marks are distinct enough to carry the meaning on their own.
		sub.Visible = false
		value.Position = UDim2.fromOffset(44, 16)
		value.Size = UDim2.new(1, -48, 0, 26)
	end

	return {
		root = root,
		value = value,
		sub = sub,
		current = 0,
		target = 0,
		format = format,
	}
end

--- A wash inside the verb plate and a breathing scale on its mark. The old
--- feedback was a 2px border and a 3% scale, which at the edge of vision reads
--- as a rendering wobble. Colour inside the plate is the part a player cannot
--- mistake for their eyes.
local function buildReadyGlow(button: TextButton, color: Color3, radius: number): Frame
	local glow = UiKit.create("Frame", {
		Name = "ReadyGlow",
		BackgroundColor3 = color,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
	}) :: Frame
	UiKit.corner(glow, radius)
	glow.Parent = button
	return glow
end

--- `Icons.build` already owns a UIScale on the mark: a 24px canvas scaled to
--- `markSize`. A second UIScale on the same object is undefined, so the pulse
--- multiplies the icon's own scale instead of stacking another one. The base is
--- captured once so the mark always settles back to the size the bar was laid
--- out for.
local function buildMarkScale(mark: Frame): MarkPulse?
	local scale = mark:FindFirstChildOfClass("UIScale")
	if scale == nil then
		return nil
	end
	return { scale = scale, base = scale.Scale }
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
	button.LayoutOrder = 9
	button.Name = "AscendButton"

	ascendGlow = buildReadyGlow(button, Theme.Color.gold, Theme.Radius.md)

	-- The mark sits above the word, same grammar as the utility keys beside it, so
	-- the whole right end of the bar reads as one row of icons rather than as two
	-- buttons that happen to be next to a toolbar.
	local markSize = if Layout.COMPACT then 28 else 20
	local mark = Icons.build(button, "ascend", markSize, Theme.Color.gold)
	mark.Name = "Mark"
	mark.Position = UDim2.fromOffset((Layout.VERB_W - markSize) / 2, if Layout.COMPACT then 8 else 5)
	mark.ZIndex = 2
	ascendMarkScale = buildMarkScale(mark)

	local label = UiKit.label(button, {
		text = "ASCEND",
		size = if Layout.COMPACT then Theme.Text.Micro else Theme.Text.Small,
		font = Theme.Font.Black,
		color = Theme.Color.text,
		align = Enum.TextXAlignment.Center,
		stroke = true,
	})
	label.Name = "Verb"
	label.Position = UDim2.fromOffset(0, if Layout.COMPACT then 44 else 26)
	label.Size = UDim2.new(1, 0, 0, 18)
	label.ZIndex = 2

	-- The payout is a core mark and a number; the progress line is the same
	-- number without the mark, because it is a distance to the threshold rather
	-- than a reward. Two elements, one visible at a time.
	ascendDetail = UiKit.currencyRow(button, {
		kind = "cores",
		text = "+0",
		iconSize = 13,
		textSize = Theme.Text.Tiny,
		color = Theme.Color.text,
		height = 14,
		gap = 3,
	})
	ascendDetail.root.Name = "Detail"
	ascendDetail.root.AnchorPoint = Vector2.new(0.5, 0)
	ascendDetail.root.Position = UDim2.new(0.5, 0, 0, if Layout.COMPACT then 64 else 45)
	ascendDetail.root.ZIndex = 2
	ascendDetail.root.Visible = false

	local detail = UiKit.label(button, {
		text = "↓ 0",
		size = Theme.Text.Tiny,
		color = Theme.Color.text,
		align = Enum.TextXAlignment.Center,
		stroke = true,
	})
	detail.Position = UDim2.fromOffset(0, if Layout.COMPACT then 64 else 45)
	detail.Size = UDim2.new(1, 0, 0, 14)
	detail.ZIndex = 2
	detail.Name = "DetailProgress"

	ascendLabel = detail
	ascendStroke = button:FindFirstChildOfClass("UIStroke")
	ascendScale = UiKit.create("UIScale", { Scale = 1 }) :: UIScale
	ascendScale.Parent = button
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
	button.LayoutOrder = 10
	button.Name = "DailyButton"

	dailyGlow = buildReadyGlow(button, Theme.Color.emerald, Theme.Radius.md)

	local markSize = if Layout.COMPACT then 28 else 20
	local mark = Icons.build(button, "daily", markSize, Theme.Color.emerald)
	mark.Name = "Mark"
	mark.Position = UDim2.fromOffset((Layout.DAILY_W - markSize) / 2, if Layout.COMPACT then 8 else 5)
	mark.ZIndex = 2
	dailyMarkScale = buildMarkScale(mark)

	local label = UiKit.label(button, {
		text = "DAILY",
		size = if Layout.COMPACT then Theme.Text.Micro else Theme.Text.Small,
		font = Theme.Font.Black,
		color = Theme.Color.text,
		align = Enum.TextXAlignment.Center,
		stroke = true,
	})
	label.Name = "Verb"
	label.Position = UDim2.fromOffset(0, if Layout.COMPACT then 44 else 26)
	label.Size = UDim2.new(1, 0, 0, 18)
	label.ZIndex = 2

	local detail = UiKit.label(button, {
		text = "not ready",
		size = Theme.Text.Tiny,
		color = Theme.Color.text,
		align = Enum.TextXAlignment.Center,
		stroke = true,
	})
	detail.Position = UDim2.fromOffset(0, if Layout.COMPACT then 64 else 45)
	detail.Size = UDim2.new(1, 0, 0, 14)
	detail.ZIndex = 2

	dailyLabel = detail
	dailyStroke = button:FindFirstChildOfClass("UIStroke")
	dailyScale = UiKit.create("UIScale", { Scale = 1 }) :: UIScale
	dailyScale.Parent = button
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

	local iconSize = if Layout.COMPACT then 30 else 22
	local icon = Icons.build(button, opts.icon, iconSize, opts.tint)
	icon.Name = "Mark"
	icon.Position = UDim2.fromOffset((Layout.KEY_W - iconSize) / 2, if Layout.COMPACT then 13 else 7)
	icon.ZIndex = 2

	local label = UiKit.label(button, {
		text = opts.label,
		size = if Layout.COMPACT then Theme.Text.Micro else Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.textSecondary,
		align = Enum.TextXAlignment.Center,
	})
	label.Name = "Face"
	label.Position = UDim2.fromOffset(0, if Layout.COMPACT then 52 else 34)
	label.Size = UDim2.new(1, 0, 0, if Layout.COMPACT then 20 else 16)
	label.ZIndex = 2

	keyButtons[opts.name] = button
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
		order = 7,
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

--- Re-places one utility key. A key is a mark over a word, so both children
--- move when the key changes width or when the row crosses the compact line.
local function placeKey(button: TextButton, width: number, height: number, compact: boolean)
	button.Size = UDim2.fromOffset(width, height)

	local mark = button:FindFirstChild("Mark")
	if mark and mark:IsA("GuiObject") then
		local iconSize = if compact then 30 else 22
		mark.Position = UDim2.fromOffset((width - iconSize) / 2, if compact then 13 else 7)
	end

	local face = button:FindFirstChild("Face")
	if face and face:IsA("TextLabel") then
		face.TextSize = if compact then Theme.Text.Micro else Theme.Text.Tiny
		face.Position = UDim2.fromOffset(0, if compact then 52 else 34)
		face.Size = UDim2.new(1, 0, 0, if compact then 20 else 16)
	end
end

--- The two verb keys carry a mark, a word and a detail line. The detail line is
--- the cost or the countdown, so it keeps its own row in both modes.
local function placeVerb(button: TextButton, width: number, height: number, compact: boolean)
	button.Size = UDim2.fromOffset(width, height)

	local markSize = if compact then 28 else 20
	local mark = button:FindFirstChild("Mark")
	if mark and mark:IsA("GuiObject") then
		mark.Position = UDim2.fromOffset((width - markSize) / 2, if compact then 8 else 5)
	end

	local verb = button:FindFirstChild("Verb")
	if verb and verb:IsA("TextLabel") then
		verb.TextSize = if compact then Theme.Text.Micro else Theme.Text.Small
		verb.Position = UDim2.fromOffset(0, if compact then 44 else 26)
		verb.Size = UDim2.new(1, 0, 0, 18)
	end

	local detail = button:FindFirstChild("Detail")
	if detail and detail:IsA("TextLabel") then
		detail.Position = UDim2.fromOffset(0, if compact then 64 else 43)
		detail.Size = UDim2.new(1, 0, 0, 14)
	end
end

--- One currency capsule. The compact row drops the caption and keeps the mark
--- and the number, because three 148px capsules beside ten 84px phone keys do
--- not fit an 800px screen.
local function placePill(pill: Pill, width: number, compact: boolean)
	pill.root.Size = UDim2.fromOffset(width, PILL_H)

	local value = pill.root:FindFirstChild("Value")
	local sub = pill.root:FindFirstChild("Sub")
	if sub and sub:IsA("TextLabel") then
		sub.Visible = not compact
	end
	if value and value:IsA("TextLabel") then
		if compact then
			value.Position = UDim2.fromOffset(44, 16)
			value.Size = UDim2.new(1, -48, 0, 26)
		else
			value.Position = UDim2.fromOffset(48, 8)
			value.Size = UDim2.new(1, -56, 0, 26)
		end
	end
end

--- Paints the whole chrome at the current `Layout` values. Runs at boot and on
--- every resize, so a play window that starts phone-sized and grows to a tablet
--- cannot leave the phone row behind.
chromeLayout = function()
	if topBar == nil then
		return
	end
	local compact = Layout.COMPACT

	topBar.Size = UDim2.fromOffset(Layout.BAR_W, Layout.TOPBAR_H)
	topBar.Position = UDim2.fromOffset(Layout.BAR_X, Layout.TOPBAR_Y)

	PLATE_W = if compact then 0 else 240
	PILL_W = if compact then 104 else 148
	LEFT_W = PLATE_W + Theme.Space.sm + PILL_W * 3 + Theme.Space.sm * 2

	if leftGroup then
		leftGroup.Size = UDim2.fromOffset(LEFT_W, Layout.TOPBAR_H)
	end
	if profileHandle then
		profileHandle.root.Visible = not compact
	end

	for _, key in { "starMatter", "aether", "quantum" } do
		local pill = pills[key]
		if pill then
			placePill(pill, PILL_W, compact)
		end
	end

	if actionGroup then
		actionGroup.Size = UDim2.fromOffset(Layout.RIGHT_CLUSTER, Layout.TOPBAR_H)
	end
	for _, button in keyButtons do
		placeKey(button, Layout.KEY_W, Layout.KEY_H, compact)
	end
	if ascendButton then
		placeVerb(ascendButton, Layout.VERB_W, Layout.KEY_H, compact)
	end
	if dailyButton then
		placeVerb(dailyButton, Layout.DAILY_W, Layout.KEY_H, compact)
	end

	if rateStrip then
		-- Parented to the rail foot, which `Sections.layout` owns. Fill it.
		rateStrip.Size = UDim2.fromScale(1, 1)
		rateStrip.Position = UDim2.fromOffset(0, 0)
	end
end

--- Re-places the bar and the rate readout after a window resize.
---
--- The roots are pinned to opposite ends, so a wider canvas only widens the gap
--- between the currencies and ASCEND. The per-key repaint above is what handles
--- the compact switch, which is a change of control size, not just of width.
function HudController.layout()
	if chromeLayout then
		chromeLayout()
	end
end

function HudController.init(canvas: Frame, railFoot: Frame?)
	-- Compact row: the 240px profile plate is the first thing to go, because the
	-- three currency capsules and the ten keys have to fit in one 84px-high row.
	-- The player's name is still in VIEW, and the plate's job on the bar is
	-- identity at a glance, which a 44px phone row cannot carry anyway.
	PLATE_W = if Layout.COMPACT then 0 else 240
	PILL_W = if Layout.COMPACT then 104 else 148
	LEFT_W = PLATE_W + Theme.Space.sm + PILL_W * 3 + Theme.Space.sm * 2

	local bar = UiKit.panel(canvas, {
		tier = "shell",
		radius = Theme.Radius.lg,
	})
	bar.Name = "TopBar"
	bar.Size = UDim2.fromOffset(Layout.BAR_W, Layout.TOPBAR_H)
	bar.Position = UDim2.fromOffset(Layout.BAR_X, Layout.TOPBAR_Y)
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
	leftGroup = left
	UiKit.hlist(left, Theme.Space.sm, Enum.VerticalAlignment.Center)

	profileHandle = ProfilePlate.build(left)
	local plate = profileHandle.root
	plate.LayoutOrder = 0
	plate.Visible = not Layout.COMPACT

	pills.starMatter = buildPill(left, 1, Theme.Color.starMatter, "STAR-MATTER", NumberUtil.abbreviate, "star")
	pills.aether = buildPill(left, 2, Theme.Color.aether, "AETHER", NumberUtil.abbreviate, "crystal")
	pills.quantum = buildPill(left, 3, Theme.Color.quantum, "CORES", NumberUtil.abbreviate, "core")

	-- Right group: the utility bank, then the two verbs. Every control on this
	-- end is the same 62px key with a mark over a word, which is what makes eight
	-- utilities and two verbs read as one toolbar instead of as a pile.
	local right = UiKit.create("Frame", {
		Name = "Actions",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 0),
		Size = UDim2.fromOffset(Layout.RIGHT_CLUSTER, Layout.TOPBAR_H),
	}) :: Frame
	right.Parent = bar
	actionGroup = right
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
		-- RANKS, not BOARDS: six capitals are 52px at this weight, and the key
		-- is 46. The longer word clipped on the first verification pass.
		label = "RANKS",
		tint = Theme.Color.emerald,
		order = 3,
		handler = function()
			if HudController.boardsHandler then
				HudController.boardsHandler()
			end
		end,
	})

	buildKey(right, {
		name = "PlayersButton",
		icon = "players",
		-- VIEW, not CREW: the key opens one player's whole profile, not a
		-- roster of names. Four capitals also measure 34px on a 46px key.
		label = "VIEW",
		tint = Theme.Color.cyan,
		order = 4,
		handler = function()
			if HudController.playersHandler then
				HudController.playersHandler()
			end
		end,
	})

	buildKey(right, {
		name = "TradeButton",
		icon = "trade",
		label = "TRADE",
		tint = Theme.Color.cyan,
		order = 5,
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
		order = 6,
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
		order = 8,
		handler = function()
			if HudController.settingsHandler then
				HudController.settingsHandler()
			end
		end,
	})

	ascendButton = buildAscendButton(right)
	dailyButton = buildDailyButton(right)

	-- Rate readout. It lives at the foot of the rail now: the top bar is verbs and
	-- currency, the rail is navigation and telemetry. Same ownership as before —
	-- this module already runs the stall detector, so the numbers and the honesty
	-- about them stay in one place.
	local strip = UiKit.create("Frame", {
		Name = "RateStrip",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}) :: Frame
	strip.Parent = railFoot or canvas
	rateStrip = strip

	local rateLabel = UiKit.label(strip, {
		text = "LINKING…",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.textFaint,
		wrap = true,
	})
	rateLabel.Position = UDim2.fromOffset(0, 0)
	rateLabel.Size = UDim2.new(1, 0, 0, 30)
	rateLabel.Name = "Rate"

	-- The steady number gets its own field under the status line, in the
	-- currency's colour. It is the value the player is actually watching.
	rateValueLabel = UiKit.label(strip, {
		text = "",
		size = Theme.Text.Subheading,
		font = Theme.Font.Numeric,
		color = Theme.Color.starMatter,
		align = Enum.TextXAlignment.Left,
	})
	rateValueLabel.Position = UDim2.fromOffset(0, 32)
	rateValueLabel.Size = UDim2.new(1, 0, 0, 24)
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

	-- The one answer to "what now?". It sits under the rate because that is the
	-- only block on screen a returning player already reads; putting the goal
	-- anywhere else would make it a seventh thing competing for attention.
	-- Read-only telemetry, except the whole block is a key into its section.
	local nextCaption = UiKit.label(strip, {
		text = "NEXT",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.textFaint,
	})
	nextCaption.Position = UDim2.fromOffset(0, 66)
	nextCaption.Size = UDim2.new(1, 0, 0, 14)
	nextCaption.Name = "NextCaption"

	nextGoalLabel = UiKit.label(strip, {
		text = "",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.text,
	})
	nextGoalLabel.Position = UDim2.fromOffset(0, 82)
	nextGoalLabel.Size = UDim2.new(1, -34, 0, 16)
	nextGoalLabel.Name = "NextGoal"

	nextGoalPercent = UiKit.label(strip, {
		text = "",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.cyan,
		align = Enum.TextXAlignment.Right,
	})
	nextGoalPercent.Position = UDim2.new(1, -32, 0, 82)
	nextGoalPercent.Size = UDim2.fromOffset(32, 16)
	nextGoalPercent.Name = "NextPercent"

	-- A 3px track, not a ring or a gauge: the rail already carries one meter
	-- (heat lives on the forge). This is a plan, so it reads as a line.
	local track = UiKit.create("Frame", {
		Name = "NextTrack",
		BackgroundColor3 = Theme.Color.strokeBright,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 106),
		Size = UDim2.new(1, 0, 0, 4),
	}) :: Frame
	track.Parent = strip

	nextGoalFill = UiKit.create("Frame", {
		Name = "NextFill",
		BackgroundColor3 = Theme.Color.cyan,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
	}) :: Frame
	nextGoalFill.Parent = track

	local nextKey = UiKit.create("TextButton", {
		Name = "NextKey",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Position = UDim2.fromOffset(0, 62),
		Size = UDim2.new(1, 0, 0, 54),
		ZIndex = 3,
	}) :: TextButton
	nextKey.Parent = strip
	UiKit.track(nextKey, nextKey.Activated:Connect(function()
		if nextGoal and HudController.nextGoalHandler then
			HudController.nextGoalHandler(nextGoal.key)
		end
	end))

	if chromeLayout then
		chromeLayout()
	end

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
			-- A boost is the one live state on this strip, so it gets the game's
			-- attention colour. Drone counts and everything else stay dim.
			color = if rateHighlight then Theme.Color.gold else Theme.Color.textDim
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
	-- the Fleet tab. The chip is the only place the boost exists after its modal
	-- was dismissed, so it is not optional decoration.
	--
	-- The two timed boosts stack in `globalMultiplier`, so the chip prints the
	-- product (x6 with the welcome 2x and one charge, x12 after a second charge)
	-- and counts down the paid clock. That is the number the player is actually
	-- earning from the timed tracks.
	local boostMult = 1
	local boostSeconds = 0
	local welcomeLive = state.boostRemaining ~= nil and state.boostRemaining > 0
	local paidLive = state.paidBoostRemaining ~= nil and state.paidBoostRemaining > 0
	if welcomeLive then
		boostMult *= 2
	end
	if paidLive then
		-- The stack count lives on the server, so the chip prints the multiplier
		-- it sent instead of assuming x3. Ten charges read x30 on the same chip.
		boostMult *= math.max(1, math.floor(state.paidBoostMult or 3))
	end
	-- The paid clock owns the countdown when it is live. It is the one the store
	-- sells and the player recharges; counting the minimum of the two made a
	-- fresh one-hour charge look like it had not applied under a welcome 2x.
	if paidLive then
		boostSeconds = state.paidBoostRemaining
	elseif welcomeLive then
		boostSeconds = state.boostRemaining
	end
	rateHighlight = boostMult > 1
	rateText = if rateHighlight
		then string.format("x%d BOOST  %s", boostMult, NumberUtil.abbreviateTime(boostSeconds))
		elseif state.drones > 0 then string.format("%s DRONES", NumberUtil.abbreviate(state.drones))
		else "NO DRONES"

	-- The rail-foot goal. `NextGoal` owns the rule; this only paints it. A goal
	-- at or past its gate is shown as a full bar and no percentage, because a
	-- daily that is ready has no meaningful number to print.
	nextGoal = NextGoal.compute(state)
	if nextGoalLabel and nextGoalPercent and nextGoalFill then
		if nextGoal then
			nextGoalLabel.Text = nextGoal.label
			nextGoalPercent.Text = if nextGoal.fraction >= 1
				then ""
				else string.format("%d%%", math.floor(nextGoal.fraction * 100))
			nextGoalFill.Size = UDim2.fromScale(math.clamp(nextGoal.fraction, 0, 1), 1)
		else
			nextGoalLabel.Text = "MAXED"
			nextGoalPercent.Text = ""
			nextGoalFill.Size = UDim2.fromScale(1, 1)
		end
	end

	-- Ascension: show the payout, not the raw total. The player cares about
	-- what the button will give them.
	--
	-- The detail line is 88px wide at 13px, so it carries one number and nothing
	-- else. The old `(x3)` ascension suffix pushed `+398.33K QC (x3)` over the
	-- key's edge and into the SETUP key beside it.
	if ascendLabel and ascendDetail then
		local thresholdReached = state.sm >= Config.AscendThreshold
		if thresholdReached then
			local cores = math.floor((state.sm / Config.AscendThreshold) ^ Config.AscendExponent)
			ascendDetail.root.Visible = true
			ascendLabel.Visible = false
			ascendDetail.set(string.format("+%s", NumberUtil.abbreviate(cores)))
		else
			local remaining = Config.AscendThreshold - state.sm
			ascendDetail.root.Visible = false
			ascendLabel.Visible = true
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

	-- The verb keys announce themselves when they are actionable. The old pass
	-- only scaled 3% and shifted a 2px border, and the owner read it as a trick of
	-- the eye. A gold or emerald wash inside the plate, a matching 2..5px ring, a
	-- 5% plate scale and a 6% mark scale are four cues on the same beat.
	if ascendButton and ascendStroke then
		local ready = StateStore.current ~= nil and StateStore.current.sm >= Config.AscendThreshold
		if ready then
			local wave = 0.5 + 0.5 * math.sin(pulse * 4.2)
			ascendStroke.Color = Theme.Color.gold
			ascendStroke.Thickness = 2 + wave * 3
			ascendStroke.Transparency = 0.02 + (1 - wave) * 0.35
			if ascendScale then
				ascendScale.Scale = 1 + wave * 0.05
			end
			if ascendGlow then
				ascendGlow.BackgroundTransparency = 0.82 - wave * 0.14
			end
			if ascendMarkScale then
				ascendMarkScale.scale.Scale = ascendMarkScale.base * (1 + wave * 0.06)
			end
		else
			ascendStroke.Color = Theme.Color.outline
			ascendStroke.Thickness = 2
			ascendStroke.Transparency = 0.85
			if ascendScale then
				ascendScale.Scale = 1
			end
			if ascendGlow then
				ascendGlow.BackgroundTransparency = 1
			end
			if ascendMarkScale then
				ascendMarkScale.scale.Scale = ascendMarkScale.base
			end
		end
	end

	if dailyButton and dailyStroke then
		local ready = StateStore.current ~= nil and StateStore.current.dailyReady
		if ready then
			local wave = 0.5 + 0.5 * math.sin(pulse * 3.6)
			dailyStroke.Color = Theme.Color.emerald
			dailyStroke.Thickness = 2 + wave * 3
			dailyStroke.Transparency = 0.02 + (1 - wave) * 0.35
			if dailyScale then
				dailyScale.Scale = 1 + wave * 0.05
			end
			if dailyGlow then
				dailyGlow.BackgroundTransparency = 0.82 - wave * 0.14
			end
			if dailyMarkScale then
				dailyMarkScale.scale.Scale = dailyMarkScale.base * (1 + wave * 0.06)
			end
		else
			dailyStroke.Color = Theme.Color.outline
			dailyStroke.Thickness = 2
			dailyStroke.Transparency = 0.85
			if dailyScale then
				dailyScale.Scale = 1
			end
			if dailyGlow then
				dailyGlow.BackgroundTransparency = 1
			end
			if dailyMarkScale then
				dailyMarkScale.scale.Scale = dailyMarkScale.base
			end
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
	rateHighlight = false
	rateValueShown = nil
	rateValueLabel = nil
	if ascendButton then
		ascendButton:Destroy()
		ascendButton = nil
	end
	ascendScale = nil
	ascendGlow = nil
	ascendMarkScale = nil
	ascendStroke = nil
	ascendLabel = nil
	ascendDetail = nil
	dailyScale = nil
	dailyGlow = nil
	dailyMarkScale = nil
	dailyStroke = nil
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
	table.clear(keyButtons)
	leftGroup = nil
	actionGroup = nil
end

return HudController
