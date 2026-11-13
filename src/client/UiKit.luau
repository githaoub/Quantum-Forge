--!strict
-- Declarative UI primitives. Every view is built from these; no view ever calls
-- Instance.new directly. Two reasons: consistency (one place to restyle) and
-- hygiene (every connection made here is tied to its instance's lifetime, so a
-- destroyed panel cannot leave a listener behind).
--
-- Nothing in this file knows about the game. It is a widget library.
--
-- House style, cloned from the reference simulator UI:
--   * every surface is opaque and carries a 3px `#0F1117` outline
--   * panels are 12px rounded with a lit top bevel and a dark bottom lip
--   * headers are wood banners with white GothamBlack type and a black stroke
--   * actions are solid gradient plates, never empty wireframes
--   * locked actions are flat slate with a cost badge, never a fainter outline

local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)
local Sfx = require(script.Parent.Sfx)

local UiKit = {}

-- ---------------------------------------------------------------------------
-- Core
-- ---------------------------------------------------------------------------

--- Creates an instance and applies properties. `props` keys are raw instance
--- property names, so this stays untyped by design — a typed per-widget wrapper
--- for every Roblox class would be hundreds of lines of ceremony for nothing.
function UiKit.create(className: string, props: { [string]: any }?): Instance
	local instance = Instance.new(className)
	if props then
		for key, value in props do
			(instance :: any)[key] = value
		end
	end
	return instance
end

--- Attaches a connection that dies with the instance. Without this, a rebuilt
--- panel leaks its old hover listeners on every refresh.
function UiKit.track(instance: Instance, connection: RBXScriptConnection)
	instance.Destroying:Once(function()
		if connection.Connected then
			connection:Disconnect()
		end
	end)
end

--- Bulk-parents children, returning the parent for chaining.
function UiKit.mount(parent: Instance, children: { Instance }): Instance
	for _, child in children do
		child.Parent = parent
	end
	return parent
end

-- ---------------------------------------------------------------------------
-- Modifiers
-- ---------------------------------------------------------------------------

function UiKit.corner(instance: Instance, radius: number): UICorner
	local corner = UiKit.create("UICorner", { CornerRadius = UDim.new(0, radius) }) :: UICorner
	corner.Parent = instance
	return corner
end

--- The house outline. Defaults to the reference's 3px near-black border with no
--- transparency: a UI stroke thinner or fainter than this reads as a wireframe.
function UiKit.stroke(instance: Instance, color: Color3?, thickness: number?, transparency: number?): UIStroke
	local stroke = UiKit.create("UIStroke", {
		Color = color or Theme.Color.outline,
		Thickness = thickness or Theme.Stroke.thick,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}) :: UIStroke
	stroke.Parent = instance
	return stroke
end

--- The only way the UI animates. Delegates to `Theme.tween`, which collapses
--- the duration to zero when the client has reduce-motion enabled — routing
--- every animation through one function is what makes that setting real
--- instead of aspirational.
function UiKit.tween(
	instance: Instance,
	duration: number,
	goal: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	return Theme.tween(instance, duration, goal, style, direction)
end

function UiKit.gradient(instance: Instance, colors: { Color3 }, rotation: number?): UIGradient
	-- A one-stop gradient is a valid fill, not a gradient: `ColorSequence.new`
	-- with a single keypoint throws, and a boot that dies inside a cosmetic call
	-- takes every panel built after it with it. Undefined entries (a colour name
	-- that does not exist in Theme) are dropped for the same reason.
	local valid: { Color3 } = {}
	for _, color in colors do
		if typeof(color) == "Color3" then
			table.insert(valid, color)
		end
	end
	if #valid == 0 then
		valid = { Theme.Color.panelSunken }
	end
	if #valid == 1 then
		table.insert(valid, valid[1])
	end

	local keypoints = {}
	for index, color in valid do
		local alpha = (index - 1) / (#valid - 1)
		table.insert(keypoints, ColorSequenceKeypoint.new(alpha, color))
	end

	local gradient = UiKit.create("UIGradient", {
		Color = ColorSequence.new(keypoints),
		Rotation = rotation or 0,
	}) :: UIGradient
	gradient.Parent = instance
	return gradient
end

function UiKit.padding(instance: Instance, all: number?, horizontal: number?, vertical: number?): UIPadding
	local h = horizontal or all or 0
	local v = vertical or all or 0
	local pad = UiKit.create("UIPadding", {
		PaddingLeft = UDim.new(0, h),
		PaddingRight = UDim.new(0, h),
		PaddingTop = UDim.new(0, v),
		PaddingBottom = UDim.new(0, v),
	}) :: UIPadding
	pad.Parent = instance
	return pad
end

--- Vertical list layout. `align` is "top" | "center" | "bottom".
function UiKit.vlist(parent: Instance, opts: {
	gap: number?,
	align: Enum.HorizontalAlignment?,
	padTop: number?,
	padBottom: number?,
}?): UIListLayout
	local o = opts or {}
	local layout = UiKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = o.align or Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Padding = UDim.new(0, o.gap or Theme.Space.sm),
	}) :: UIListLayout
	layout.Parent = parent

	-- UIListLayout has no concept of outer padding; a UIPadding on the parent
	-- is the only way to inset the first and last child.
	if o.padTop or o.padBottom then
		UiKit.padding(parent, nil, nil, nil)
		local pad = parent:FindFirstChildOfClass("UIPadding")
		if pad then
			pad.PaddingTop = UDim.new(0, o.padTop or 0)
			pad.PaddingBottom = UDim.new(0, o.padBottom or 0)
		end
	end
	return layout
end

function UiKit.hlist(parent: Instance, gap: number?, align: Enum.VerticalAlignment?): UIListLayout
	local layout = UiKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = align or Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, gap or Theme.Space.sm),
	}) :: UIListLayout
	layout.Parent = parent
	return layout
end

function UiKit.grid(parent: Instance, cellSize: UDim2, gap: number?): UIGridLayout
	local layout = UiKit.create("UIGridLayout", {
		CellSize = cellSize,
		CellPadding = UDim2.fromOffset(gap or Theme.Space.sm, gap or Theme.Space.sm),
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirectionMaxCells = 0,
	}) :: UIGridLayout
	layout.Parent = parent
	return layout
end

-- ---------------------------------------------------------------------------
-- Surfaces
-- ---------------------------------------------------------------------------

export type Tier = Theme.Tier

export type PanelOpts = {
	--- Surface tier. Picks fill and border from `Theme.Elevation` so stacked
	--- surfaces separate by depth instead of every panel hand-picking its own
	--- opacity. Explicit `fill` / `transparency` / `strokeTransparency` below
	--- still win when a call site genuinely needs to deviate.
	tier: Tier?,
	radius: number?,
	fill: Color3?,
	stroke: Color3?,
	strokeThickness: number?,
	strokeTransparency: number?,
	gradient: { Color3 }?,
	gradientRotation: number?,
	padding: number?,
	transparency: number?,
	--- Decorative chrome. Both default on: the lit top edge and the dark bottom
	--- lip are what make a flat rectangle read as a moulded plate.
	bevel: boolean?,
	lip: boolean?,
	lipColor: Color3?,
}

--- The standard surface: opaque fill, a 1px `stroke` border, a 6px corner. No
--- bevel and no lip by default: depth is the fill value, and a lit edge on every
--- plate is what made the old build read as a stack of toy blocks. Both are still
--- available for the one element a screen wants to read as a physical plate.
function UiKit.panel(parent: Instance, opts: PanelOpts?): Frame
	local o = opts or {}
	local tier = Theme.elevation(o.tier)
	local radius = o.radius or Theme.Radius.lg
	local panel = UiKit.create("Frame", {
		BackgroundColor3 = o.fill or tier.fill,
		BackgroundTransparency = o.transparency or tier.transparency,
		BorderSizePixel = 0,
	}) :: Frame

	UiKit.corner(panel, radius)
	UiKit.stroke(panel, o.stroke or Theme.Color.stroke, o.strokeThickness or Theme.Stroke.thin, o.strokeTransparency or tier.strokeTransparency)

	if o.bevel == true then
		local bevel = UiKit.create("Frame", {
			BackgroundColor3 = Theme.Color.white,
			BackgroundTransparency = 0.84,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -20, 0, 1),
			Position = UDim2.fromOffset(10, 1),
			ZIndex = 0,
		}) :: Frame
		bevel.Parent = panel
	end

	if o.lip == true then
		local lip = UiKit.create("Frame", {
			BackgroundColor3 = o.lipColor or Theme.Color.ink,
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -20, 0, 3),
			Position = UDim2.new(0, 10, 1, -4),
			ZIndex = 0,
		}) :: Frame
		UiKit.corner(lip, 2)
		lip.Parent = panel
	end

	if o.gradient then
		UiKit.gradient(panel, o.gradient, o.gradientRotation)
	end
	if o.padding then
		UiKit.padding(panel, o.padding)
	end

	panel.Parent = parent
	return panel
end

--- A scrolling column. Returns the ScrollFrame; parent content into it.
function UiKit.scroll(parent: Instance, opts: {
	thickness: number?,
	transparency: number?,
}?): ScrollingFrame
	local o = opts or {}
	local scroll = UiKit.create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		-- Explicit, not inherited: a scrolling container that does not clip lets
		-- its rows paint over whatever sits outside the panel.
		ClipsDescendants = true,
		ScrollBarThickness = o.thickness or 4,
		ScrollBarImageColor3 = Theme.Color.wood,
		ScrollBarImageTransparency = o.transparency or 0.25,
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
	}) :: ScrollingFrame
	scroll.Parent = parent
	return scroll
end

-- ---------------------------------------------------------------------------
-- Text
-- ---------------------------------------------------------------------------

export type LabelOpts = {
	text: string?,
	size: number?,
	font: Enum.Font?,
	color: Color3?,
	align: Enum.TextXAlignment?,
	alignY: Enum.TextYAlignment?,
	scaled: boolean?,
	wrap: boolean?,
	width: UDim?,
	height: UDim?,
	transparency: number?,
	rich: boolean?,
	--- Hard black outline around the glyphs. The reference uses it on every
	--- title and every button face; it is what keeps white type legible on wood.
	stroke: boolean?,
	strokeColor: Color3?,
}

function UiKit.label(parent: Instance, opts: LabelOpts): TextLabel
	local o = opts
	local label = UiKit.create("TextLabel", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = o.text or "",
		TextColor3 = o.color or Theme.Color.text,
		TextSize = o.size or Theme.Text.Body,
		Font = o.font or Theme.Font.Body,
		TextXAlignment = o.align or Enum.TextXAlignment.Left,
		TextYAlignment = o.alignY or Enum.TextYAlignment.Center,
		TextTransparency = o.transparency or 0,
		TextWrapped = o.wrap or false,
		RichText = o.rich or false,
		TextScaled = o.scaled or false,
		TextStrokeColor3 = o.strokeColor or Theme.Color.outline,
		TextStrokeTransparency = if o.stroke then 0 else 1,
		Size = UDim2.fromScale(1, 0),
	}) :: TextLabel

	label.Size = UDim2.new(
		if o.width then o.width.Scale else 1,
		if o.width then o.width.Offset else 0,
		if o.height then o.height.Scale else 0,
		if o.height then o.height.Offset else (o.size or Theme.Text.Body) + 6
	)

	if label.TextScaled then
		label.TextSize = 1
	end

	label.Parent = parent
	return label
end

--- Centred single-line text with a fixed height. The workhorse for buttons.
function UiKit.textIn(parent: Instance, text: string, color: Color3?, size: number?, font: Enum.Font?): TextLabel
	return UiKit.label(parent, {
		text = text,
		color = color or Theme.Color.text,
		size = size or Theme.Text.Body,
		font = font or Theme.Font.Body,
		align = Enum.TextXAlignment.Center,
	})
end

-- ---------------------------------------------------------------------------
-- Chrome: banners, badges, close buttons
-- ---------------------------------------------------------------------------

export type BannerOpts = {
	text: string,
	--- Second line under the title. When set, the title is the upper half of the
	--- lockup instead of a vertically centred single line.
	subtitle: string?,
	width: UDim2?,
	position: UDim2?,
	height: number?,
	--- Left icon plaque tint. Nil hides the plaque.
	accent: Color3?,
	--- Drawn mark inside the plaque, keyed to `Icons`. Preferred over `icon`,
	--- because a text glyph depends on the client's font stack and the house
	--- marks do not.
	iconKind: string?,
	--- Glyph inside the plaque when `iconKind` is nil.
	icon: string?,
	--- Plaque edge in design px. 26 for a modal banner, 40 to match the section
	--- banner on a page card.
	plaqueSize: number?,
	--- Small secondary tab on the right, like the reference's "Daily" plaque.
	right: string?,
	rightAccent: Color3?,
	size: number?,
}

--- A region header: a flat steel plate, one hairline border, a square accent
--- plaque and type flush left. The old wood gradient banner with a centred
--- stroked title was the loudest "template" signal in the build; this one reads as
--- a label on a machine face.
function UiKit.banner(parent: Instance, opts: BannerOpts): Frame
	local o = opts
	local height = o.height or 44

	local banner = UiKit.create("Frame", {
		Name = "Banner",
		BackgroundColor3 = Theme.Color.wood,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Size = o.width or UDim2.new(1, 0, 0, height),
		Position = o.position or UDim2.fromOffset(0, 0),
	}) :: Frame
	UiKit.corner(banner, Theme.Radius.card)
	UiKit.stroke(banner, Theme.Color.stroke, Theme.Stroke.thin, 0)

	local textLeft = 14
	if o.accent then
		local plaqueSize = o.plaqueSize or 26
		local plaque = UiKit.create("Frame", {
			BackgroundColor3 = o.accent,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(plaqueSize, plaqueSize),
			Position = UDim2.new(0, 10, 0.5, -plaqueSize / 2),
			ZIndex = 1,
		}) :: Frame
		UiKit.corner(plaque, Theme.Radius.sm)
		plaque.Parent = banner

		if o.iconKind ~= nil and o.iconKind ~= "" then
			local iconSize = if plaqueSize >= 36 then 24 else 18
			local mark = Icons.build(plaque, o.iconKind :: string, iconSize, Theme.onColor(o.accent))
			mark.Position = UDim2.fromOffset((plaqueSize - 24) / 2, (plaqueSize - 24) / 2)
		else
			local glyph = UiKit.label(plaque, {
				text = o.icon or "◆",
				size = Theme.Text.Tiny,
				font = Theme.Font.Black,
				color = Theme.onColor(o.accent),
				align = Enum.TextXAlignment.Center,
			})
			glyph.Size = UDim2.fromScale(1, 1)
			glyph.Parent = plaque
		end
		textLeft = 10 + plaqueSize + 10
	end

	local title = UiKit.label(banner, {
		text = o.text,
		size = o.size or Theme.Text.Heading,
		font = Theme.Font.Black,
		color = Theme.Color.text,
		align = Enum.TextXAlignment.Left,
	})
	title.Name = "Title"
	if o.subtitle then
		-- Two-line lockup: the name is the heading, the line under it is the one
		-- fact that qualifies it (rarity, class, owner). A single vertically
		-- centred title wastes the middle of a 64px plate.
		local half = math.floor(height / 2)
		title.Size = UDim2.new(1, -(textLeft + 12), 0, (o.size or Theme.Text.Heading) + 4)
		title.Position = UDim2.fromOffset(textLeft, half - (o.size or Theme.Text.Heading) - 4)

		local sub = UiKit.label(banner, {
			text = o.subtitle,
			size = Theme.Text.Tiny,
			font = Theme.Font.Black,
			color = Theme.Color.textFaint,
			align = Enum.TextXAlignment.Left,
		})
		sub.Name = "Subtitle"
		sub.Position = UDim2.fromOffset(textLeft, half + 4)
		sub.Size = UDim2.new(1, -(textLeft + 12), 0, 15)
	else
		title.Size = UDim2.new(1, -(textLeft + 12), 1, 0)
		title.Position = UDim2.fromOffset(textLeft, 0)
	end

	if o.right then
		local accent = o.rightAccent or Theme.Color.gold
		local tab = UiKit.create("Frame", {
			Name = "RightTab",
			BackgroundColor3 = accent,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(76, 22),
			Position = UDim2.new(1, -86, 0.5, -11),
			ZIndex = 1,
		}) :: Frame
		UiKit.corner(tab, Theme.Radius.sm)
		local tabText = UiKit.label(tab, {
			text = o.right,
			size = Theme.Text.Tiny,
			font = Theme.Font.Black,
			color = Theme.onColor(accent),
			align = Enum.TextXAlignment.Center,
		})
		tabText.Size = UDim2.fromScale(1, 1)
		tabText.Parent = tab
		tab.Parent = banner
		title.Size = UDim2.new(1, -(textLeft + 96), 1, 0)
	end

	banner.Parent = parent
	return banner
end

--- A small outlined chip for costs, categories and reward counts.
function UiKit.badge(parent: Instance, opts: {
	text: string,
	color: Color3?,
	width: number?,
	height: number?,
	size: number?,
	textColor: Color3?,
}): Frame
	local height = opts.height or 18
	local chip = UiKit.create("Frame", {
		BackgroundColor3 = opts.color or Theme.Color.gold,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(opts.width or 54, height),
	}) :: Frame
	UiKit.corner(chip, math.floor(height / 2))
	UiKit.stroke(chip, Theme.Color.outline, Theme.Stroke.thin, 0)

	local label = UiKit.label(chip, {
		text = opts.text,
		size = opts.size or Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = opts.textColor or Theme.Color.ink,
		align = Enum.TextXAlignment.Center,
	})
	label.Name = "Face"
	label.Size = UDim2.fromScale(1, 1)
	label.Parent = chip
	chip.Parent = parent
	return chip
end

--- The red X in the corner of a modal. Returns the button; the caller wires it.
function UiKit.closeButton(parent: Instance, onClose: (() -> ())?): TextButton
	local button = UiKit.create("TextButton", {
		Name = "CloseButton",
		BackgroundColor3 = Theme.Color.red,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromOffset(38, 38),
	}) :: TextButton
	UiKit.corner(button, 8)
	UiKit.gradient(button, { Theme.Color.red, Theme.Color.redDeep }, 90)
	UiKit.stroke(button, Theme.Color.outline, Theme.Stroke.thick, 0)

	local face = UiKit.label(button, {
		text = "X",
		size = 20,
		font = Theme.Font.Black,
		color = Theme.Color.text,
		align = Enum.TextXAlignment.Center,
		stroke = true,
	})
	face.Size = UDim2.fromScale(1, 1)
	face.ZIndex = 2

	UiKit.track(button, button.MouseEnter:Connect(function()
		UiKit.tween(button, Theme.Duration.fast, { BackgroundColor3 = Theme.Color.red:Lerp(Theme.Color.white, 0.16) })
	end))
	UiKit.track(button, button.MouseLeave:Connect(function()
		UiKit.tween(button, Theme.Duration.normal, { BackgroundColor3 = Theme.Color.red })
	end))

	if onClose then
		UiKit.track(button, button.Activated:Connect(function()
			Sfx.close()
			onClose()
		end))
	end

	button.Parent = parent
	return button
end

-- ---------------------------------------------------------------------------
-- Buttons
-- ---------------------------------------------------------------------------

export type ButtonOpts = {
	text: string?,
	size: number?,
	font: Enum.Font?,
	color: Color3?,
	textColor: Color3?,
	fill: Color3?,
	stroke: Color3?,
	radius: number?,
	height: number?,
	padding: number?,
	accent: { Color3 }?,
	layoutOrder: number?,
	handler: (() -> ())?,
}

--- Flat key: one fill, one hairline border, a face in whichever of ink or white
--- survives the fill. The old version stacked a gradient plate, a lit bevel and a
--- stroked face on every button; none of that is here, because a control should
--- read as a control and not as a moulded toy.
function UiKit.button(parent: Instance, opts: ButtonOpts): TextButton
	local o = opts
	local baseFill = o.accent and o.accent[1] or o.fill or Theme.Color.panelRaised
	local baseStroke = o.stroke or Theme.Color.stroke
	local radius = o.radius or Theme.Radius.md
	local faceColor = o.textColor or o.color or (if o.accent then Theme.onColor(baseFill) else Theme.Color.text)

	local button = UiKit.create("TextButton", {
		BackgroundColor3 = baseFill,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		ClipsDescendants = true,
		Text = o.text or "",
		TextColor3 = faceColor,
		TextSize = o.size or Theme.Text.Body,
		Font = o.font or Theme.Font.Heading,
		TextStrokeTransparency = 1,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		LayoutOrder = o.layoutOrder or 0,
		Size = UDim2.new(1, 0, 0, o.height or 44),
	}) :: TextButton

	UiKit.corner(button, radius)
	local stroke = UiKit.stroke(button, baseStroke, Theme.Stroke.thin, 0)
	UiKit.focus(button, stroke, baseStroke, 0)

	if o.padding then
		UiKit.padding(button, o.padding)
	end

	UiKit.track(button, button.MouseEnter:Connect(function()
		Sfx.hover()
		UiKit.tween(button, Theme.Duration.fast, { BackgroundColor3 = baseFill:Lerp(Theme.Color.white, 0.07) })
		UiKit.tween(stroke, Theme.Duration.fast, { Color = Theme.Color.strokeBright })
	end))

	UiKit.track(button, button.MouseLeave:Connect(function()
		UiKit.tween(button, Theme.Duration.normal, { BackgroundColor3 = baseFill })
		UiKit.tween(stroke, Theme.Duration.normal, { Color = baseStroke })
	end))

	if o.handler then
		local handler = o.handler
		UiKit.track(button, button.Activated:Connect(function()
			Sfx.ui()
			handler()
		end))
	end

	button.Parent = parent
	return button
end

-- ---------------------------------------------------------------------------
-- Action buttons
-- ---------------------------------------------------------------------------

export type ActionKind = "ready" | "locked" | "equipped"

export type ActionHandle = {
	button: TextButton,
	--- Restyles the control in place. `label` is the full face text, so callers
	--- own the wording ("FORGE", "R$ 199", "✓ EQUIPPED") and this module owns
	--- what each state looks like.
	set: (kind: ActionKind, label: string, accent: Color3?) -> (),
}

--- The three-state action control every panel uses.
---
--- The old views drew one wireframe outline for every state, so an affordable
--- FORGE, a blade the player already owned, and one they could not touch were
--- pixel-identical apart from a line of 11px text. This makes the state the
--- dominant visual, exactly like the reference's Sell / Equip Best plates:
---
---   ready     solid accent gradient, 3px outline, white stroked face, lit bevel
---   locked    flat slate plate, dim face, 3px outline — visibly inert
---   equipped  low-alpha green tint with a matching border — a badge, not a CTA
---
--- The fill is a child frame rather than the button's own background so the
--- gradient never tints the label (a UIGradient on a TextButton multiplies the
--- text as well as the plate).
function UiKit.actionButton(parent: Instance, opts: {
	height: number?,
	radius: number?,
	size: number?,
	font: Enum.Font?,
	accent: Color3,
	kind: ActionKind?,
	label: string?,
	handler: (() -> ())?,
	--- Flat fill instead of the three-stop gradient. Used where the button has to
	--- read as a solid simulator key rather than as a moulded plate.
	solid: boolean?,
	--- Face colour in the ready state. Defaults to white.
	labelColor: Color3?,
	--- Hard black outline behind the face. Turn it off for dark type on a light
	--- fill, where the outline is what makes it mud.
	labelStroke: boolean?,
}): ActionHandle
	local accent = opts.accent
	local radius = opts.radius or Theme.Radius.sm
	local height = opts.height or 32
	local faceStroke = opts.labelStroke == true

	local button = UiKit.create("TextButton", {
		BackgroundColor3 = Theme.Color.slate,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		ClipsDescendants = true,
		Text = "",
		Size = UDim2.new(1, 0, 0, height),
	}) :: TextButton
	UiKit.corner(button, radius)
	local stroke = UiKit.stroke(button, Theme.Color.stroke, Theme.Stroke.thin, 0)

	local label = UiKit.label(button, {
		text = opts.label or "",
		size = opts.size or Theme.Text.Small,
		font = opts.font or Theme.Font.Black,
		color = Theme.Color.text,
		align = Enum.TextXAlignment.Center,
		stroke = faceStroke,
	})
	label.Name = "Face"
	-- Inset the face by 6px on each side. The glyphs then truncate with an
	-- ellipsis inside the plate instead of running into the border, which is what
	-- made a long "BUILD 1  ·  12.4M AETHER" spill on the tablet row.
	label.Position = UDim2.fromOffset(6, 0)
	label.Size = UDim2.new(1, -12, 1, 0)
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.ZIndex = 3

	local function set(kind: ActionKind, text: string, nextAccent: Color3?)
		local tint = nextAccent or accent
		accent = tint
		label.Text = text

		if kind == "ready" then
			button.BackgroundColor3 = tint
			button.BackgroundTransparency = 0
			stroke.Color = Theme.Color.outline
			stroke.Transparency = 0
			label.TextColor3 = opts.labelColor or Theme.onColor(tint)
			label.TextTransparency = 0
			label.TextStrokeTransparency = if faceStroke then 0.25 else 1
			button.Active = true
		elseif kind == "equipped" then
			-- A badge, not a CTA: the fill drops to a tint and the border carries
			-- the state, so an owned item never competes with something buyable.
			button.BackgroundColor3 = Theme.Color.emerald
			button.BackgroundTransparency = 0.86
			stroke.Color = Theme.Color.emerald
			stroke.Transparency = 0
			label.TextColor3 = Theme.Color.emerald
			label.TextTransparency = 0
			label.TextStrokeTransparency = 1
			button.Active = false
		else
			button.BackgroundColor3 = Theme.Color.slate
			button.BackgroundTransparency = 0
			stroke.Color = Theme.Color.stroke
			stroke.Transparency = 0
			label.TextColor3 = Theme.Color.locked
			label.TextTransparency = 0
			label.TextStrokeTransparency = 1
			button.Active = false
		end
	end

	local resting: Color3? = nil
	UiKit.track(button, button.MouseEnter:Connect(function()
		if not button.Active then
			return
		end
		Sfx.hover()
		resting = button.BackgroundColor3
		UiKit.tween(button, Theme.Duration.fast, { BackgroundColor3 = resting:Lerp(Theme.Color.white, 0.09) })
	end))

	UiKit.track(button, button.MouseLeave:Connect(function()
		local back = resting
		resting = nil
		if back == nil or not button.Active then
			return
		end
		UiKit.tween(button, Theme.Duration.normal, { BackgroundColor3 = back })
	end))

	if opts.handler then
		local handler = opts.handler
		UiKit.track(button, button.Activated:Connect(function()
			if button.Active then
				Sfx.ui()
				handler()
			end
		end))
	end

	button.Parent = parent
	local handle: ActionHandle = { button = button, set = set }
	set(opts.kind or "ready", opts.label or "", accent)
	return handle
end

-- ---------------------------------------------------------------------------
-- Category tabs
-- ---------------------------------------------------------------------------

export type TabHandle = {
	button: TextButton,
	setActive: (active: boolean) -> (),
}

--- A category tab. Active: the label goes white and a 2px accent underline sits
--- on the bottom edge. Inactive: no fill, faint label. The old pill-with-gradient
--- shape made every filter row read as a row of buttons; an underline says "this
--- is the current view" without adding another plate to the screen.
function UiKit.tab(parent: Instance, opts: {
	text: string,
	accent: Color3,
	width: number?,
	height: number?,
	onSelect: (() -> ())?,
}): TabHandle
	local radius = Theme.Radius.sm
	local button = UiKit.create("TextButton", {
		BackgroundColor3 = Theme.Color.card,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromOffset(opts.width or 88, opts.height or 34),
	}) :: TextButton
	UiKit.corner(button, radius)

	local underline = UiKit.create("Frame", {
		Name = "Underline",
		BackgroundColor3 = opts.accent,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 1, -2),
		Size = UDim2.new(1, 0, 0, 2),
		Visible = false,
		ZIndex = 2,
	}) :: Frame
	UiKit.corner(underline, 1)
	underline.Parent = button

	local label = UiKit.label(button, {
		text = string.upper(opts.text),
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.locked,
		align = Enum.TextXAlignment.Center,
	})
	label.Name = "Face"
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 2

	local active = false
	local function setActive(nextActive: boolean)
		active = nextActive
		underline.Visible = active
		label.TextColor3 = if active then Theme.Color.text else Theme.Color.locked
		label.TextStrokeTransparency = 1
	end

	UiKit.track(button, button.MouseEnter:Connect(function()
		Sfx.hover()
		if not active then
			label.TextColor3 = Theme.Color.textDim
		end
	end))
	UiKit.track(button, button.MouseLeave:Connect(function()
		if not active then
			label.TextColor3 = Theme.Color.locked
		end
	end))

	if opts.onSelect then
		local onSelect = opts.onSelect
		UiKit.track(button, button.Activated:Connect(function()
			Sfx.tab()
			onSelect()
		end))
	end

	button.Parent = parent
	local handle: TabHandle = { button = button, setActive = setActive }
	return handle
end

--- Makes gamepad and keyboard selection visible. Roblox's default selection box is
--- easy to miss against this palette, so the focused control brightens its own
--- border instead of relying on platform chrome.
---
--- Whatever the border was before the focus arrives is what it returns to. The
--- old version restored a fixed 2px, so a 1px card or a 3px hero kept the thick
--- focus ring after the pointer or the gamepad pad moved on. That read as a
--- highlight escaping the control. `baseColor`/`baseTransparency` are the
--- fallback for a control that has never been focused while its stroke was
--- touched by a render pass.
function UiKit.focus(button: GuiButton, stroke: UIStroke, baseColor: Color3, baseTransparency: number)
	local restColor = baseColor
	local restThickness = stroke.Thickness
	local restTransparency = baseTransparency

	UiKit.track(button, button.SelectionGained:Connect(function()
		restColor = stroke.Color
		restThickness = stroke.Thickness
		restTransparency = stroke.Transparency
		stroke.Color = Theme.Color.white
		stroke.Thickness = Theme.Stroke.bold
		stroke.Transparency = 0
	end))

	UiKit.track(button, button.SelectionLost:Connect(function()
		stroke.Color = restColor
		stroke.Thickness = restThickness
		stroke.Transparency = restTransparency
	end))
end

--- Wraps a button so it dims and refuses activation while `shouldDisable()` is
-- true. Returns a refresh function the caller calls when state changes.
function UiKit.gate(button: TextButton, stroke: UIStroke?, shouldDisable: () -> boolean): () -> ()
	return function()
		local disabled = shouldDisable()
		button.Active = not disabled
		button.AutoButtonColor = false
		button.TextTransparency = if disabled then 0.55 else 0
		button.BackgroundTransparency = if disabled then 0.55 else 0
		if stroke then
			stroke.Transparency = if disabled then 0.75 else 0
		end
	end
end

-- ---------------------------------------------------------------------------
-- Bars
-- ---------------------------------------------------------------------------

export type BarParts = {
	track: Frame,
	fill: Frame,
	set: (fraction: number) -> (),
	--- Present only when `label` was requested. Callers own its text.
	label: TextLabel?,
}

--- A horizontal progress bar. `set` takes 0..1 and snaps, so a 10Hz sync does
--- not fight an animation. The track is a sunken dark well with a 2px outline
--- and an optional centred readout, which is the reference's quest-bar shape.
function UiKit.bar(parent: Instance, opts: {
	height: number?,
	fill: Color3?,
	track: Color3?,
	gradient: { Color3 }?,
	radius: number?,
	heightScale: UDim?,
	label: boolean?,
	size: number?,
}?): BarParts
	local o = opts or {}
	local radius = o.radius or Theme.Radius.sm

	local track = UiKit.create("Frame", {
		BackgroundColor3 = o.track or Theme.Color.panelSunken,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.new(1, 0, 0, o.height or 10),
	}) :: Frame
	UiKit.corner(track, radius)
	UiKit.stroke(track, Theme.Color.strokeFaint, Theme.Stroke.hair, 0)
	track.Parent = parent

	local fill = UiKit.create("Frame", {
		BackgroundColor3 = o.fill or Theme.Color.gold,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
	}) :: Frame
	UiKit.corner(fill, radius)
	if o.gradient then
		UiKit.gradient(fill, o.gradient, 90)
	end
	fill.Parent = track

	local textLabel: TextLabel? = nil
	if o.label then
		textLabel = UiKit.label(track, {
			text = "",
			size = o.size or Theme.Text.Tiny,
			font = Theme.Font.Black,
			color = Theme.Color.text,
			align = Enum.TextXAlignment.Center,
			stroke = true,
		})
		textLabel.Name = "Readout"
		textLabel.Size = UDim2.fromScale(1, 1)
		textLabel.ZIndex = 2
	end

	local function set(fraction: number)
		local clamped = math.clamp(fraction, 0, 1)
		fill.Size = UDim2.fromScale(clamped, 1)
	end

	return { track = track, fill = fill, set = set, label = textLabel }
end

-- ---------------------------------------------------------------------------
-- Badge art
-- ---------------------------------------------------------------------------

--- A "LOADING..." plate for art that has not arrived yet.
---
--- Roblox reports a late asset, never a failed one, so this waits on
--- `ImageLabel.IsLoaded` rather than guessing from a timer. Eight seconds is
--- the give-up point: after that the plate is a permanent "LOADING" on a card
--- the player is already using, which reads as a bug.
function UiKit.artLoading(host: GuiObject, art: ImageLabel, size: number?)
	local label = UiKit.label(host, {
		text = "LOADING...",
		size = size or Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Center,
	})
	label.Name = "ArtLoading"
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 4
	label.Visible = false
	task.spawn(function()
		-- A cached bitmap is loaded within a frame or two. Waiting a beat before
		-- showing the plate keeps "LOADING..." off every card on a warm join.
		task.wait(0.2)
		if label.Parent == nil or art.IsLoaded then
			if label.Parent ~= nil then
				label:Destroy()
			end
			return
		end
		label.Visible = true
		local deadline = os.clock() + 8
		while label.Parent ~= nil and not art.IsLoaded and os.clock() < deadline do
			task.wait(0.1)
		end
		if label.Parent ~= nil then
			label:Destroy()
		end
	end)
end

export type BadgeWellOpts = {
	--- `AssetManifest.uiArt(...)` output. Empty draws nothing and returns nil,
	--- which is the honest "no art yet" path: the row keeps its text layout.
	image: string?,
	size: number,
	--- Optional 1px inner ring in the row's accent colour. Faint, so it reads as
	--- a bevel rather than a second border.
	accent: Color3?,
}

--- Circular art well for a list row.
---
--- Three surfaces, in order: the well plate, the thumbnail cropped to fill the
--- circle, and a 2px ink ring on top. The ring matters at 44px, because a
--- painted disc on a dark panel loses its edge without it.
---
--- `ScaleType.Crop` rather than `Fit`: the source is already a square badge with
--- transparent corners, so filling the circle is exactly right and Fit would
--- leave a letterboxed gap on non-square thumbnails.
function UiKit.badgeWell(parent: Instance, opts: BadgeWellOpts): Frame?
	if opts.image == nil or opts.image == "" then
		return nil
	end

	local size = opts.size
	local radius = math.floor(size * 0.5)

	local well = UiKit.create("Frame", {
		Name = "BadgeArt",
		BackgroundColor3 = Theme.Color.panelSunken,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(size, size),
	}) :: Frame
	UiKit.corner(well, radius)
	UiKit.stroke(well, Theme.Color.outline, 2, 0)
	well.Parent = parent

	local art = UiKit.create("ImageLabel", {
		Name = "Image",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Image = opts.image,
		ScaleType = Enum.ScaleType.Crop,
	}) :: ImageLabel
	UiKit.corner(art, radius)
	art.Parent = well
	UiKit.artLoading(well, art)

	if opts.accent ~= nil then
		local accent = UiKit.create("UIStroke", {
			Color = opts.accent,
			Thickness = 1,
			Transparency = 0.7,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}) :: UIStroke
		accent.Parent = well
	end

	return well
end

-- ---------------------------------------------------------------------------
-- Container
-- ---------------------------------------------------------------------------

--- Creates the root ScreenGui plus the design canvas it scales.
---
--- The canvas is **full-bleed**. Height starts at 720 design px and width is
--- whatever the viewport has room for at that scale. On a 16:9 window that
--- lands near 1280 design px, on a 21:9 near 1680, and the canvas covers the
--- window edge to edge in both cases, no letterbox and no black bars.
---
--- `minWidth` is the floor the chrome can survive at (the nav strip needs room
--- for the tabs, the rate readout and the keys on one row). A viewport that is
--- narrower than that floor used to be letterboxed: a 4:3 tablet got a 720-tall
--- strip in the middle of a 1032px screen with 150px of wallpaper above and
--- below. Now the width is clamped and the **height grows** to fill the screen,
--- so the app uses the whole display and every view reads the real canvas
--- height. On a phone the aspect is wider than the floor, so the height stays
--- 720.
---
--- `onResize` fires whenever the measured design size changes, including the
--- grow that Studio's play window does a second after boot. The caller re-primes
--- `Layout` and repositions its roots; nothing is rebuilt, because every view
--- below the roots is already elastic in X.
---
--- Returns the measured design width and height as the last two values so
--- `Layout.init` can size the content rect against the real canvas.
function UiKit.screen(
	name: string,
	minWidth: number?,
	onResize: ((number, number, number) -> ())?
): (ScreenGui, Frame, UIScale, number, number)
	local gui = UiKit.create("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		-- False means Roblox lays this ScreenGui out *below* the native Topbar
		-- (Menu / Chat / Voice) instead of underneath it. With true the canvas
		-- started at screen y=0 and the top bar row landed exactly behind those
		-- buttons. Letting Roblox own the inset also means the mobile two-row
		-- top bar is handled without any manual GuiService:GetGuiInset()
		-- arithmetic.
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 10,
	}) :: ScreenGui
	gui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

	-- Wallpaper. Full bleed, painted on the ScreenGui rather than the canvas so
	-- it also covers any letterbox left by a mid-session resize. Two stops of
	-- navy plus a soft top lift: a flat fill reads as a screenshot, and a
	-- near-black one reads as a bug on an OLED panel.
	local wallpaper = UiKit.create("Frame", {
		Name = "Wallpaper",
		BackgroundColor3 = Theme.Color.sky,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
	}) :: Frame
	local wash = UiKit.gradient(wallpaper, { Theme.Color.skyLift, Theme.Color.sky, Theme.Color.skyDeep }, 90)
	-- The gradient fades toward the bottom so the eye lands on the top bar and
	-- the content, not on the base of the screen.
	wash.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.45, 0),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	wallpaper.Parent = gui

	local canvas = UiKit.create("Frame", {
		Name = "Canvas",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		-- The canvas is the app frame. A hover fill, a UIStroke or a pulse scale
		-- on a control at the edge must die at this rectangle, never paint into
		-- the wallpaper band beside it.
		ClipsDescendants = true,
		ZIndex = 1,
	}) :: Frame
	canvas.Parent = gui

	local scale = UiKit.create("UIScale") :: UIScale
	scale.Parent = canvas

	-- Available space, in physical pixels, below the native Roblox bar. Read from
	-- the ScreenGui itself: it is already inset-aware, and `GetGuiInset` reports
	-- zero while the topbar is momentarily hidden, which is exactly the moment the
	-- first measurement tends to run. The camera plus inset stays as the fallback
	-- for the frame before the ScreenGui has been laid out.
	local guiService = game:GetService("GuiService")
	local function available(): Vector2
		local size = gui.AbsoluteSize
		if size.X > 1 and size.Y > 1 then
			return size
		end
		local camera = workspace.CurrentCamera
		local viewport = if camera then camera.ViewportSize else Vector2.new(Theme.DesignWidth, Theme.DesignHeight)
		local inset = guiService:GetGuiInset()
		return Vector2.new(math.max(viewport.X, 1), math.max(viewport.Y - inset.Y, 1))
	end

	-- Boot measurement and every later resize go through one path.
	--
	-- The common case is height-driven: 720 design px maps onto the full window
	-- height and the width is the leftover, converted back into design px. A
	-- wider window therefore gets more layout, not black bars.
	--
	-- When the viewport is narrower than the floor's aspect, the width is the
	-- limit and the design height grows instead. A 4:3 tablet then gets a
	-- 975-design-tall canvas at a 1.06 fit, which is the same pixel size the old
	-- 720-tall letterbox used but fills the screen.
	--
	-- `designWidth` starts at zero so the first `apply` takes the resize branch
	-- and sizes the canvas. The callback is guarded by the caller; at that point
	-- no panel exists yet.
	local designWidth = 0
	local designHeight = Theme.DesignHeight

	local function apply()
		local space = available()
		local minSpace = minWidth or Theme.DesignWidth
		local heightScale = space.Y / Theme.DesignHeight
		local width = math.floor(math.max(space.X / heightScale, minSpace) + 0.5)
		local fit = math.min(space.X / width, space.Y / Theme.DesignHeight)
		local height = Theme.DesignHeight

		if space.X / width < space.Y / Theme.DesignHeight then
			fit = space.X / width
			height = math.floor(space.Y / math.max(fit, 0.001) + 0.5)
		end

		scale.Scale = math.clamp(fit, 0.2, 4)

		if width ~= designWidth or height ~= designHeight then
			designWidth = width
			designHeight = height
			canvas.Size = UDim2.fromOffset(width, height)
			if onResize then
				onResize(width, height, scale.Scale)
			end
		end
	end
	apply()

	local camera = workspace.CurrentCamera
	if camera then
		UiKit.track(canvas, camera:GetPropertyChangedSignal("ViewportSize"):Connect(apply))
	end
	-- The ScreenGui is the real source of the measurement, so its own size is
	-- watched too: the inset shifts when the topbar hides, and that is a resize
	-- even when the viewport has not moved.
	UiKit.track(canvas, gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply))

	return gui, canvas, scale, designWidth, designHeight
end

--- Fades an instance out and destroys it. Used by every transient popup.
function UiKit.dissolve(instance: GuiObject, duration: number?)
	-- Collapsed here too, not just inside the tween: the destroy delay has to
	-- track the same duration or a reduce-motion client keeps invisible frames
	-- around long enough to intercept clicks.
	local d = if Theme.reducedMotion() then 0 else (duration or Theme.Duration.normal)
	UiKit.tween(instance, d, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	for _, child in instance:GetDescendants() do
		if child:IsA("TextLabel") or child:IsA("TextButton") then
			UiKit.tween(child, d, { TextTransparency = 1 })
			UiKit.tween(child, d, { BackgroundTransparency = 1 })
		elseif child:IsA("Frame") then
			UiKit.tween(child, d, { BackgroundTransparency = 1 })
		elseif child:IsA("ImageLabel") then
			UiKit.tween(child, d, { ImageTransparency = 1 })
		elseif child:IsA("UIStroke") then
			UiKit.tween(child, d, { Transparency = 1 })
		end
	end

	task.delay(d + 0.05, function()
		instance:Destroy()
	end)
end

--- A 1px divider. The new design separates with a line rather than a nested
--- plate: a fourth surface in a stack is what turns a screen into card soup.
function UiKit.rule(parent: Instance, opts: { color: Color3?, inset: number?, position: UDim2? }?): Frame
	local o = opts or {}
	local inset = o.inset or 0
	local rule = UiKit.create("Frame", {
		Name = "Rule",
		BackgroundColor3 = o.color or Theme.Color.stroke,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -inset * 2, 0, 1),
		Position = o.position or UDim2.fromOffset(inset, 0),
	}) :: Frame
	rule.Parent = parent
	return rule
end

--- The 13px uppercase label that opens a region. Faint by default: it is a
--- signpost, not a heading, and it should never compete with the title under it.
function UiKit.eyebrow(parent: Instance, text: string, opts: {
	color: Color3?,
	width: number?,
	align: Enum.TextXAlignment?,
}?): TextLabel
	local o = opts or {}
	local label = UiKit.label(parent, {
		text = string.upper(text),
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = o.color or Theme.Color.textFaint,
		align = o.align or Enum.TextXAlignment.Left,
	})
	label.Name = "Eyebrow"
	if o.width then
		label.Size = UDim2.fromOffset(o.width, 14)
	else
		label.Size = UDim2.new(1, 0, 0, 14)
	end
	return label
end

--- A large figure with an optional unit, in the numeric face. RichText carries
--- the unit so a caller does not have to measure the number to place it.
function UiKit.figure(parent: Instance, opts: {
	text: string,
	unit: string?,
	size: number?,
	color: Color3?,
	unitColor: Color3?,
	width: number?,
}): TextLabel
	local o = opts
	local unit = ""
	if o.unit and o.unit ~= "" then
		unit = string.format(
			' <font size="%d" color="#%s">%s</font>',
			Theme.Text.Micro,
			(o.unitColor or Theme.Color.textFaint):ToHex(),
			o.unit
		)
	end
	local label = UiKit.label(parent, {
		text = o.text .. unit,
		size = o.size or Theme.Text.Hero,
		font = Theme.Font.Numeric,
		color = o.color or Theme.Color.text,
		align = Enum.TextXAlignment.Left,
		rich = true,
	})
	label.Name = "Figure"
	label.Size = UDim2.fromOffset(o.width or 240, (o.size or Theme.Text.Hero) + 8)
	return label
end

--- A region header with no plate under it: eyebrow, title, and one fact pinned
--- right. This replaces the old full-width banner on every section and modal.
function UiKit.header(parent: Instance, opts: {
	eyebrow: string,
	title: string,
	detail: string?,
	titleColor: Color3?,
	height: number?,
}): Frame
	local height = opts.height or 46
	local box = UiKit.create("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, height),
	}) :: Frame
	box.Parent = parent

	local eyebrow = UiKit.eyebrow(box, opts.eyebrow)
	eyebrow.Position = UDim2.fromOffset(0, 0)
	eyebrow.Size = UDim2.new(1, -160, 0, 14)

	local title = UiKit.label(box, {
		text = opts.title,
		size = Theme.Text.Title,
		font = Theme.Font.Heading,
		color = opts.titleColor or Theme.Color.text,
	})
	title.Name = "Title"
	title.Position = UDim2.fromOffset(0, 14)
	title.Size = UDim2.new(1, -160, 0, Theme.Text.Title + 4)

	if opts.detail then
		local detail = UiKit.label(box, {
			text = opts.detail,
			size = Theme.Text.Micro,
			font = Theme.Font.Numeric,
			color = Theme.Color.textFaint,
			align = Enum.TextXAlignment.Right,
		})
		detail.Name = "Detail"
		detail.Position = UDim2.new(1, -156, 0, 18)
		detail.Size = UDim2.fromOffset(156, 18)
	end

	return box
end

return UiKit
