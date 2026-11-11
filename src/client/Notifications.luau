--!strict
-- Toast stack. Server rejections, purchases, milestones and streaks all land
-- here, because a silent failure is the worst possible feedback in a clicker.
--
-- Fixed slot pool: toasts are positioned by index, so a burst of six does not
-- produce six overlapping panels.

local Theme = require(script.Parent.Theme)
local UiKit = require(script.Parent.UiKit)

local Notifications = {}

local MAX_VISIBLE = 2
local HOLD_SECONDS = 2.6
local FADE_SECONDS = 0.3

-- Bottom-left strip of the forge panel, in the band under the strike plate.
--
-- Measured live before choosing this: the strike plate ends at design y 669 and
-- the canvas is 720 tall, so the free band is 669..706. Three corners were
-- unusable — bottom-right sits on the side panel's action dock, top-centre sits
-- on the onboarding strip (y 94..138) and the forge banner, top-left sits on the
-- currency pads. The stack therefore runs *sideways* in that 37px band rather
-- than upward into the anvil: two 34px pills fit across 734px of panel width,
-- and neither can ever cover a tap target.
local TOAST_W = 360
local TOAST_H = 34
local TOAST_GAP = 8
local EDGE_X = 20
local EDGE_Y = 8

type Toast = {
	frame: Frame,
	closeAt: number,
}

local container: Frame? = nil
local toasts: { Toast } = {}

--- Slot x for the nth toast. Runs left to right, so a new toast never covers the
--- one the player is currently reading.
local function slotX(index: number): number
	return EDGE_X + (index - 1) * (TOAST_W + TOAST_GAP)
end

local function slotY(): number
	return Theme.DesignHeight - EDGE_Y - TOAST_H
end

local function layout()
	for index, toast in toasts do
		UiKit.tween(toast.frame, Theme.Duration.fast, { Position = UDim2.fromOffset(slotX(index), slotY()) })
	end
end

local function remove(toast: Toast)
	for index, entry in toasts do
		if entry == toast then
			table.remove(toasts, index)
			break
		end
	end
	if toast.frame.Parent then
		UiKit.dissolve(toast.frame, FADE_SECONDS)
	end
	layout()
end

--- kind: "info" | "good" | "warn" | "bad"
function Notifications.push(text: string, kind: string?)
	if container == nil then
		return
	end

	local accent = Theme.Color.aether
	if kind == "good" then
		accent = Theme.Color.good
	elseif kind == "warn" then
		accent = Theme.Color.warn
	elseif kind == "bad" then
		accent = Theme.Color.danger
	elseif kind == "currency" then
		accent = Theme.Color.starMatter
	end

	local frame = UiKit.panel(container, {
		tier = "raised",
		radius = Theme.Radius.md,
		stroke = accent,
		strokeTransparency = 0.55,
	})
	frame.Size = UDim2.fromOffset(TOAST_W, TOAST_H)
	frame.AnchorPoint = Vector2.new(0, 0)
	-- Starts one full toast-width past the left edge, so the slide-in travels.
	frame.Position = UDim2.fromOffset(-(TOAST_W + EDGE_X), slotY())
	frame.BackgroundTransparency = 1
	frame.ZIndex = 30

	-- Accent bar down the left edge: reads as a category at a glance without
	-- needing an icon.
	local bar = UiKit.create("Frame", {
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 4, 1, -14),
		Position = UDim2.fromOffset(10, 7),
	}) :: Frame
	UiKit.corner(bar, 2)
	bar.Parent = frame

	local label = UiKit.label(frame, {
		text = text,
		size = Theme.Text.Small,
		font = Theme.Font.Body,
		color = Theme.Color.text,
		wrap = false,
		align = Enum.TextXAlignment.Left,
	})
	-- One line, hard stop. The pill is 34px tall because that is the whole band
	-- under the strike plate; a wrapped second line would be clipped instead of
	-- read, so overflow is truncated with the meaning already in the first 40
	-- characters of every message this game pushes.
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Position = UDim2.fromOffset(24, 0)
	label.Size = UDim2.new(1, -34, 1, 0)

	local toast: Toast = { frame = frame, closeAt = os.clock() + HOLD_SECONDS }

	table.insert(toasts, toast)
	while #toasts > MAX_VISIBLE do
		remove(toasts[1])
	end

	-- Slide into place. The endpoint is the tier's own opacity so the toast settles
	-- exactly on the elevation ladder rather than a nearby hand-picked number.
	UiKit.tween(frame, Theme.Duration.normal, {
		BackgroundTransparency = Theme.elevation("raised").transparency,
		Position = UDim2.fromOffset(slotX(#toasts), slotY()),
	}, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	layout()

	task.delay(HOLD_SECONDS + FADE_SECONDS, function()
		if toast.frame.Parent and os.clock() >= toast.closeAt - 0.01 then
			remove(toast)
		end
	end)
end

--- Builds the stack container. Called once by Main after the canvas exists.
function Notifications.init(canvas: Frame)
	if container and container.Parent then
		return
	end
	container = UiKit.create("Frame", {
		Name = "Notifications",
		BackgroundTransparency = 1,
		-- Full canvas width, zero height: toast positions are absolute canvas
		-- coordinates with the anchor at their own right edge.
		Size = UDim2.fromScale(1, 0),
		Position = UDim2.fromOffset(0, 0),
		ClipsDescendants = false,
		-- Above every panel and the side-panel action dock. A toast is a
		-- notification, not a decoration: it has to win the draw order.
		ZIndex = 30,
	}) :: Frame
	container.Parent = canvas
end

function Notifications.clear()
	for _, toast in table.clone(toasts) do
		remove(toast)
	end
end

return Notifications
