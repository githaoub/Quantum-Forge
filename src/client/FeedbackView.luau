--!strict
-- Player feedback form.
--
-- One modal, four categories, one text box. The post-mortem is blunt about why
-- this exists: friction that is not captured in the session where it happens is
-- reconstructed later from a retention curve, and by then the player is gone.
-- The form is one click from the top bar so it costs nothing to open mid-run.
--
-- The client caps length here only to keep the text box honest about its own
-- limit. The server trims and caps again; a client-side limit is a courtesy,
-- never a rule.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Theme = require(script.Parent.Theme)
local UiKit = require(script.Parent.UiKit)
local StateStore = require(script.Parent.StateStore)
local Notifications = require(script.Parent.Notifications)

local FeedbackView = {}

local CATEGORIES = { "BUG", "BALANCE", "CONFUSING", "OTHER" }

local canvasRoot: Frame? = nil
local activeModal: Frame? = nil
local selected: string = "BUG"

local function close()
	if activeModal then
		local frame = activeModal
		activeModal = nil
		UiKit.dissolve(frame, Theme.Duration.fast)
	end
end

--- Opens the form. Re-opening replaces the previous instance rather than
--- stacking scrims, which is how a modal ends up three scrims deep and dimmer
--- every time the player taps the button twice.
function FeedbackView.open()
	if canvasRoot == nil then
		return
	end
	close()
	selected = "BUG"

	local root = UiKit.create("Frame", {
		Name = "FeedbackModal",
		BackgroundColor3 = Theme.Color.void,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 60,
	}) :: Frame
	root.Parent = canvasRoot
	activeModal = root

	local scrim = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.ink,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 60,
	}) :: Frame
	scrim.Parent = root

	local panel = UiKit.panel(root, {
		tier = "raised",
		radius = Theme.Radius.card,
		stroke = Theme.Color.outline,
		strokeThickness = Theme.Stroke.bold,
	})
	panel.Name = "FeedbackPanel"
	panel.Size = UDim2.fromOffset(488, 344)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.ZIndex = 61
	panel.BackgroundTransparency = 1

	local banner = UiKit.banner(panel, {
		text = "SEND FEEDBACK",
		position = UDim2.fromOffset(14, -22),
		width = UDim2.new(1, -28, 0, 52),
		size = 22,
		accent = Theme.Color.cyan,
		icon = "★",
	})
	banner.ZIndex = 62
	for _, child in banner:GetDescendants() do
		if child:IsA("GuiObject") then
			child.ZIndex += 1
		end
	end

	local closeButton = UiKit.closeButton(panel, close)
	closeButton.Position = UDim2.new(1, -30, 0, -12)
	closeButton.ZIndex = 63

	local prompt = UiKit.label(panel, {
		text = "What got in the way?",
		size = Theme.Text.Body,
		font = Theme.Font.Heading,
		color = Theme.Color.textDim,
	})
	prompt.Position = UDim2.fromOffset(24, 40)
	prompt.Size = UDim2.new(1, -48, 0, 22)

	-- Category chips. One selected at a time; the accent plate is the state, no
	-- checkmark needed, because a checkmark on four equal chips reads as a list
	-- of things already done.
	local chipRow = UiKit.create("Frame", {
		Name = "Categories",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -48, 0, 34),
		Position = UDim2.fromOffset(24, 68),
	}) :: Frame
	chipRow.Parent = panel
	UiKit.hlist(chipRow, 6, Enum.VerticalAlignment.Center)

	local chipButtons: { [string]: TextButton } = {}
	local chipStrokes: { [string]: UIStroke } = {}

	local function paintChips()
		for name, button in chipButtons do
			local on = name == selected
			button.BackgroundColor3 = if on then Theme.Color.cyan else Theme.Color.panelSunken
			button.TextColor3 = if on then Theme.Color.ink else Theme.Color.textDim
			local stroke = chipStrokes[name]
			if stroke then
				stroke.Color = if on then Theme.Color.outline else Theme.Color.stroke
			end
		end
	end

	local chipWidth = (488 - 48 - 3 * 6) / #CATEGORIES
	for index, name in CATEGORIES do
		local chip = UiKit.button(chipRow, {
			text = name,
			fill = Theme.Color.panelSunken,
			stroke = Theme.Color.stroke,
			height = 30,
			radius = Theme.Radius.sm,
			size = Theme.Text.Micro,
			font = Theme.Font.Black,
			textColor = Theme.Color.textDim,
			layoutOrder = index,
			handler = function()
				selected = name
				paintChips()
			end,
		})
		chip.Size = UDim2.fromOffset(chipWidth, 30)
		chip.Name = string.format("Category_%s", name)
		chipButtons[name] = chip
		local stroke = chip:FindFirstChildOfClass("UIStroke")
		if stroke then
			chipStrokes[name] = stroke
		end
	end
	paintChips()

	local box = UiKit.create("TextBox", {
		Name = "FeedbackText",
		BackgroundColor3 = Theme.Color.panelSunken,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Text = "",
		PlaceholderText = string.format("One or two sentences. %d characters max.", Config.FeedbackMaxLength),
		PlaceholderColor3 = Theme.Color.locked,
		TextColor3 = Theme.Color.text,
		TextSize = Theme.Text.Small,
		Font = Theme.Font.Body,
		TextWrapped = true,
		MultiLine = true,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -48, 0, 118),
		Position = UDim2.fromOffset(24, 112),
	}) :: TextBox
	UiKit.corner(box, Theme.Radius.sm)
	UiKit.stroke(box, Theme.Color.stroke, 2, 0)
	UiKit.padding(box, 10)
	box.Parent = panel

	-- Trim as it is typed. Reassigning text inside the changed signal re-enters
	-- the signal, so the guard is the length check itself: once the string is at
	-- the cap it is never reassigned again.
	box:GetPropertyChangedSignal("Text"):Connect(function()
		local text = box.Text
		if #text > Config.FeedbackMaxLength then
			box.Text = string.sub(text, 1, Config.FeedbackMaxLength)
		end
	end)

	local counter = UiKit.label(panel, {
		text = string.format("0 / %d", Config.FeedbackMaxLength),
		size = Theme.Text.Micro,
		font = Theme.Font.Numeric,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Right,
	})
	counter.Position = UDim2.fromOffset(24, 234)
	counter.Size = UDim2.new(1, -48, 0, 16)

	box:GetPropertyChangedSignal("Text"):Connect(function()
		counter.Text = string.format("%d / %d", #box.Text, Config.FeedbackMaxLength)
	end)

	local send = UiKit.actionButton(panel, {
		label = "SEND",
		accent = Theme.Color.cyan,
		height = 46,
		radius = Theme.Radius.md,
		size = Theme.Text.Body,
		handler = function()
			local text = string.gsub(box.Text, "^%s*(.-)%s*$", "%1")
			if #text < 4 then
				Notifications.push("Write a sentence first", "warn")
				return
			end
			StateStore.send("feedback", { category = selected, text = text })
			close()
		end,
	})
	send.button.Name = "SendFeedback"
	send.button.Position = UDim2.new(0.5, 2, 1, -62)
	send.button.Size = UDim2.new(0.5, -26, 0, 46)

	local cancel = UiKit.button(panel, {
		text = "CANCEL",
		fill = Theme.Color.slate,
		stroke = Theme.Color.outline,
		height = 46,
		radius = Theme.Radius.md,
		size = Theme.Text.Body,
		handler = close,
	})
	cancel.Position = UDim2.new(0, 24, 1, -62)
	cancel.Size = UDim2.new(0.5, -26, 0, 46)

	UiKit.tween(scrim, Theme.Duration.fast, { BackgroundTransparency = 0.32 })
	UiKit.tween(panel, Theme.Duration.normal, { BackgroundTransparency = Theme.elevation("raised").transparency })
end

function FeedbackView.init(canvas: Frame)
	canvasRoot = canvas
	activeModal = nil
end

return FeedbackView
