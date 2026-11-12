--!strict
-- The full-screen overlay every collection panel sits in.
--
-- Three panels now share this shape: the vault, the codex, the leaderboards and
-- the trade desk. Building the dim, the panel, the banner, the close key and the
-- escape binding four times is four chances for one of them to forget the
-- Escape binding, or to sit at the wrong ZIndex, or to leave a click-catcher
-- behind after closing. So it lives once.
--
-- `body` is the interior below the banner. Callers own everything inside it and
-- rebuild it on open; the shell owns nothing that changes per frame.

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local UiKit = require(script.Parent.UiKit)
local Sfx = require(script.Parent.Sfx)

local ModalShell = {}

export type Spec = {
	name: string,
	title: string,
	--- Optional second line under the title, inside the banner.
	subtitle: string?,
	accent: Color3,
	width: number,
	height: number,
	--- Fires after the panel is visible and before `onClose` on the way down.
	onOpen: (() -> ())?,
	onClose: (() -> ())?,
	--- Suppresses the dimmer-click close. Used by the trade desk, where a stray
	--- click in the dark must not abandon a half-built offer.
	lockScrim: boolean?,
}

export type Handle = {
	layer: Frame,
	panel: Frame,
	body: Frame,
	open: () -> (),
	close: () -> (),
	isOpen: () -> boolean,
	setTitle: (string) -> (),
	setSubtitle: (string) -> (),
	destroy: () -> (),
}

local BASE_Z = 44

--- How many collection panels are on screen right now. The guide reads it to
--- stand down while one is open: its card belongs to the forge, not to a panel
--- it is floating over.
local openPanels = 0

function ModalShell.openCount(): number
	return openPanels
end

--- Builds one overlay. Every shell gets a distinct ZIndex band so two panels can
--- never interleave their children if a player finds a way to open both.
function ModalShell.build(canvas: Frame, spec: Spec, zIndex: number?): Handle
	local base = zIndex or BASE_Z

	local layer = UiKit.create("Frame", {
		Name = spec.name,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = base,
	}) :: Frame
	layer.Parent = canvas

	local handle: Handle? = nil

	local dim = UiKit.create("TextButton", {
		Name = "Dim",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Color.void,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = base,
	}) :: TextButton
	dim.Parent = layer

	local panel = UiKit.panel(layer, {
		tier = "raised",
		radius = Theme.Radius.card,
		stroke = Theme.Color.outline,
		strokeThickness = Theme.Stroke.bold,
	})
	panel.Name = spec.name .. "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(spec.width, spec.height)
	panel.ZIndex = base + 1

	-- Full-bleed banner: the close key sits on top of it, so a banner that stops
	-- short leaves a bare strip of plate beside the title.
	local banner = UiKit.banner(panel, {
		text = spec.title,
		width = UDim2.new(1, 0, 0, 54),
		height = 54,
		size = 22,
		accent = spec.accent,
		icon = "★",
	})
	banner.Name = "Banner"
	banner.ZIndex = base + 2

	local titleLabel = banner:FindFirstChild("Title") :: TextLabel?

	local subtitleLabel = UiKit.label(banner, {
		text = spec.subtitle or "",
		size = Theme.Text.Tiny,
		font = Theme.Font.Label,
		color = Theme.Color.textDim,
		align = Enum.TextXAlignment.Right,
	})
	subtitleLabel.Name = "Caption"
	subtitleLabel.AnchorPoint = Vector2.new(1, 0.5)
	subtitleLabel.Position = UDim2.new(1, -58, 0.5, 0)
	subtitleLabel.Size = UDim2.fromOffset(320, 20)
	subtitleLabel.ZIndex = base + 3

	local close = UiKit.button(panel, {
		text = "X",
		fill = Theme.Color.redDeep,
		stroke = Theme.Color.red,
		height = 34,
		radius = Theme.Radius.sm,
		size = Theme.Text.Small,
		font = Theme.Font.Black,
		textColor = Theme.Color.text,
		handler = function()
			if handle then
				handle.close()
			end
		end,
	})
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -14, 0, 10)
	close.Size = UDim2.fromOffset(38, 34)
	close.ZIndex = base + 3

	local body = UiKit.create("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 58),
		Size = UDim2.new(1, 0, 1, -58),
		ZIndex = base + 1,
	}) :: Frame
	body.Parent = panel

	local open = false
	local inputConnection: RBXScriptConnection? = nil

	local function setOpen(next: boolean)
		if open == next then
			return
		end
		open = next
		openPanels += if next then 1 else -1
		if next then
			layer.Visible = true
			layer.BackgroundTransparency = 1
			Sfx.modal()
			if inputConnection == nil then
				-- Escape closes. Bound on open rather than at build, so a panel
				-- that was never opened is not sitting on the input stack.
				inputConnection = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
					if processed then
						return
					end
					if input.KeyCode == Enum.KeyCode.Escape and open and handle then
						handle.close()
					end
				end)
			end
			if spec.onOpen then
				spec.onOpen()
			end
		else
			layer.Visible = false
			Sfx.close()
			if spec.onClose then
				spec.onClose()
			end
		end
	end

	-- A Frame does not sink pointer input, so a click on empty panel space falls
	-- through to the dimmer and used to close the whole sheet. That is the
	-- "clicked the background and lost my place" bug. The dimmer still closes on
	-- the gutters around the panel; a click whose screen point is inside the
	-- panel is ignored here, because the panel itself is what the player was
	-- aiming at.
	UiKit.track(dim, dim.Activated:Connect(function()
		if spec.lockScrim then
			return
		end
		local point = UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
		local origin = panel.AbsolutePosition
		local extent = origin + panel.AbsoluteSize
		if point.X >= origin.X and point.X <= extent.X and point.Y >= origin.Y and point.Y <= extent.Y then
			return
		end
		if handle then
			handle.close()
		end
	end))

	handle = {
		layer = layer,
		panel = panel,
		body = body,
		open = function()
			setOpen(true)
		end,
		close = function()
			setOpen(false)
		end,
		isOpen = function(): boolean
			return open
		end,
		setTitle = function(text: string)
			if titleLabel then
				titleLabel.Text = text
			end
		end,
		setSubtitle = function(text: string)
			subtitleLabel.Text = text
		end,
		destroy = function()
			if inputConnection then
				inputConnection:Disconnect()
				inputConnection = nil
			end
			open = false
			layer:Destroy()
		end,
	}

	return handle :: Handle
end

--- Clears every GuiObject under `parent`. Panels rebuild their body on open and
--- on every data refresh; one helper keeps that from being four copies of the
--- same loop.
function ModalShell.clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") or child:IsA("UIGradient") then
			child:Destroy()
		end
	end
end

return ModalShell
