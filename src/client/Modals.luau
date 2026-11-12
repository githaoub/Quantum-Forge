--!strict
-- Blocking modals: offline earnings, and a generic confirm for destructive
-- actions.
--
-- Ascension wipes SM, Aether, drones and every blade the player has forged. That
-- is exactly the kind of button that needs a one-tap confirmation — an
-- incremental where a misclick erases an hour is an incremental people quit.
--
-- The frame is the reference's: a chunky card with a wood banner overhanging the
-- top edge, a 3px near-black outline, a scrim that actually dims the game, and a
-- red X in the corner. A modal you can mistake for a toast is not a modal.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local NumberUtil = require(Shared:WaitForChild("NumberUtil"))
local AssetManifest = require(Shared:WaitForChild("AssetManifest"))

local Theme = require(script.Parent.Theme)
local UiKit = require(script.Parent.UiKit)
local Sfx = require(script.Parent.Sfx)

local Modals = {}

local canvasRoot: Frame? = nil
local activeModal: Frame? = nil

local function close()
	if activeModal then
		local frame = activeModal
		activeModal = nil
		Sfx.close()
		UiKit.dissolve(frame, Theme.Duration.fast)
	end
end

local function shell(
	title: string,
	subtitle: string?,
	accent: Color3,
	height: number?,
	locked: boolean?
): (Frame, Frame)
	close()
	Sfx.modal()

	local root = UiKit.create("Frame", {
		Name = "ModalRoot",
		BackgroundColor3 = Theme.Color.void,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 60,
	}) :: Frame
	root.Parent = canvasRoot

	-- A scrim, not a tint. 0.28 leaves the game visible but unmistakably suppressed.
	local dim = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.ink,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 60,
	}) :: Frame
	dim.Parent = root

	local panel = UiKit.panel(root, {
		tier = "raised",
		radius = Theme.Radius.card,
		stroke = Theme.Color.outline,
		strokeThickness = Theme.Stroke.bold,
	})
	panel.Size = UDim2.fromOffset(470, height or 330)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.ZIndex = 61
	panel.BackgroundTransparency = 1

	-- Overhangs the card by 22px, exactly like the reference's Quest / Inventory
	-- headers. Children are not clipped, so this reads as a plaque bolted on top.
	local banner = UiKit.banner(panel, {
		text = title,
		position = UDim2.fromOffset(14, -22),
		width = UDim2.new(1, -28, 0, 52),
		size = 24,
		accent = accent,
		icon = "★",
	})
	banner.ZIndex = 62
	for _, child in banner:GetDescendants() do
		if child:IsA("GuiObject") then
			child.ZIndex += 1
		end
	end

	if subtitle then
		local sub = UiKit.label(panel, {
			text = subtitle,
			size = Theme.Text.Micro,
			font = Theme.Font.Heading,
			color = Theme.Color.textFaint,
			align = Enum.TextXAlignment.Center,
		})
		sub.Position = UDim2.fromOffset(0, 38)
		sub.Size = UDim2.new(1, 0, 0, 16)
	end

	-- A locked shell has no close key. Only the welcome boost uses it: it is the
	-- one message in the game that has to be read before play, and a card the
	-- player can dismiss without reading it is a card they will dismiss.
	if not locked then
		local closeButton = UiKit.closeButton(panel, close)
		closeButton.Position = UDim2.new(1, -30, 0, -12)
		closeButton.ZIndex = 63
	end

	activeModal = root

	-- The panel animates in from invisible to its own fill, so a future change to
	-- the elevation ladder moves the endpoint with it.
	UiKit.tween(dim, Theme.Duration.fast, { BackgroundTransparency = 0.28 })
	UiKit.tween(panel, Theme.Duration.normal, { BackgroundTransparency = Theme.elevation("raised").transparency })

	return panel, root
end

--- Shows the offline earnings summary. Auto-dismisses only via the button so
--- the player actually sees the number.
function Modals.offline(seconds: number, amount: number)
	local panel = shell("WELCOME BACK", "YOUR FLEET KEPT WORKING", Theme.Color.gold)

	local duration = UiKit.label(panel, {
		text = string.format("Away for %s", NumberUtil.abbreviateTime(seconds)),
		size = Theme.Text.Body,
		font = Theme.Font.Heading,
		color = Theme.Color.textDim,
		align = Enum.TextXAlignment.Center,
	})
	duration.Position = UDim2.fromOffset(0, 62)
	duration.Size = UDim2.new(1, 0, 0, 22)

	local big = UiKit.label(panel, {
		text = "+" .. NumberUtil.abbreviate(amount),
		size = 54,
		font = Theme.Font.Black,
		color = Theme.Color.gold,
		align = Enum.TextXAlignment.Center,
		stroke = true,
	})
	big.Position = UDim2.fromOffset(0, 90)
	big.Size = UDim2.new(1, 0, 0, 64)

	local caption = UiKit.label(panel, {
		text = "DRONE FLEET OUTPUT",
		size = Theme.Text.Micro,
		font = Theme.Font.Heading,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Center,
	})
	caption.Position = UDim2.fromOffset(0, 156)
	caption.Size = UDim2.new(1, 0, 0, 16)

	local collect = UiKit.actionButton(panel, {
		label = "COLLECT",
		accent = Theme.Color.gold,
		height = 56,
		radius = Theme.Radius.card,
		size = Theme.Text.Heading,
		handler = close,
	})
	collect.button.Position = UDim2.new(0, 36, 1, -86)
	collect.button.Size = UDim2.new(1, -72, 0, 56)
end

--- The welcome boost. The only un-skippable card in the game.
---
--- It exists because the boost is invisible in play: a player who joins, plays for
--- ten minutes and leaves has no way to know their income was doubled, and a stat
--- they cannot see is a stat that never happened. So the first load stops, shows
--- the multiplier, the duration and the clock, and waits for one press.
function Modals.starter(seconds: number)
	local panel = shell("WELCOME TO THE FORGE", "ONE HOUR OF DOUBLE STAR-MATTER", Theme.Color.gold, 396, true)

	-- Boost plate. The art is the same `x2_star_matter` badge the game-pass shelf
	-- uses, so the icon means one thing everywhere. The drawn bolt underneath is
	-- the fallback while the CDN answers, and it stays if the image never loads.
	local plate = UiKit.create("Frame", {
		Name = "BoostPlate",
		BackgroundColor3 = Theme.Color.panelSunken,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 62),
		Size = UDim2.fromOffset(96, 96),
		ZIndex = 62,
	}) :: Frame
	UiKit.corner(plate, 48)
	UiKit.stroke(plate, Theme.Color.gold, Theme.Stroke.bold, 0)
	plate.Parent = panel

	local bolt = UiKit.create("Frame", {
		Name = "Bolt",
		BackgroundColor3 = Theme.Color.gold,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(20, 46),
		ZIndex = 63,
	}) :: Frame
	bolt.Rotation = 14
	UiKit.corner(bolt, 4)
	bolt.Parent = plate
	local notch = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.panelSunken,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(-8, 18),
		Size = UDim2.fromOffset(40, 12),
		ZIndex = 64,
	}) :: Frame
	notch.Rotation = -14
	notch.Parent = bolt

	local art = AssetManifest.UiArt.x2_star_matter
	if art and art ~= "" then
		local image = UiKit.create("ImageLabel", {
			Name = "Art",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			Image = art,
			ScaleType = Enum.ScaleType.Fit,
			ImageTransparency = 1,
			ZIndex = 65,
		}) :: ImageLabel
		UiKit.corner(image, 48)
		image.Parent = plate
		-- Only fade the fallback out once the bitmap is actually resident: a
		-- failed fetch leaves the drawn bolt rather than an empty ring.
		task.spawn(function()
			local ok = pcall(function()
				ContentProvider:PreloadAsync({ image })
			end)
			if ok and image.IsLoaded then
				UiKit.tween(bolt, Theme.Duration.normal, { BackgroundTransparency = 1 })
				UiKit.tween(image, Theme.Duration.normal, { ImageTransparency = 0 })
			end
		end)
	end

	local multiplier = UiKit.label(panel, {
		text = "x2",
		size = 58,
		font = Theme.Font.Black,
		color = Theme.Color.gold,
		align = Enum.TextXAlignment.Center,
		stroke = true,
	})
	multiplier.Name = "Multiplier"
	multiplier.Position = UDim2.fromOffset(0, 168)
	multiplier.Size = UDim2.new(1, 0, 0, 62)

	local duration = UiKit.label(panel, {
		text = string.format("%d MINUTES", math.floor(seconds / 60)),
		size = Theme.Text.Subheading,
		font = Theme.Font.Heading,
		color = Theme.Color.text,
		align = Enum.TextXAlignment.Center,
	})
	duration.Position = UDim2.fromOffset(0, 228)
	duration.Size = UDim2.new(1, 0, 0, 24)
	duration.Name = "Duration"

	local note = UiKit.label(panel, {
		text = "Every strike, every drone, every expedition. The clock starts now and runs down whether you are swinging or not.",
		size = Theme.Text.Small,
		font = Theme.Font.Body,
		color = Theme.Color.textSecondary,
		align = Enum.TextXAlignment.Center,
	})
	note.Position = UDim2.fromOffset(28, 258)
	note.Size = UDim2.new(1, -56, 0, 44)
	note.TextWrapped = true
	note.TextYAlignment = Enum.TextYAlignment.Top

	local claim = UiKit.actionButton(panel, {
		label = "START FORGING",
		accent = Theme.Color.gold,
		height = 56,
		radius = Theme.Radius.card,
		size = Theme.Text.Heading,
		handler = close,
	})
	claim.button.Position = UDim2.new(0, 36, 1, -78)
	claim.button.Size = UDim2.new(1, -72, 0, 56)
end

--- Generic confirm. `onConfirm` fires only on the affirmative path.
function Modals.confirm(title: string, body: string, confirmText: string, accent: Color3, onConfirm: () -> ())
	local panel = shell(title, nil, accent)

	local text = UiKit.label(panel, {
		text = body,
		size = Theme.Text.Body,
		font = Theme.Font.Body,
		color = Theme.Color.textDim,
		align = Enum.TextXAlignment.Center,
		wrap = true,
	})
	text.Position = UDim2.fromOffset(34, 52)
	text.Size = UDim2.new(1, -68, 0, 108)

	local cancel = UiKit.button(panel, {
		text = "CANCEL",
		fill = Theme.Color.slate,
		stroke = Theme.Color.outline,
		height = 50,
		radius = Theme.Radius.card,
		size = Theme.Text.Body,
		handler = close,
	})
	cancel.Position = UDim2.new(0, 34, 1, -82)
	cancel.Size = UDim2.new(0.5, -42, 0, 50)

	local confirm = UiKit.actionButton(panel, {
		label = confirmText,
		accent = accent,
		height = 50,
		radius = Theme.Radius.card,
		size = Theme.Text.Body,
		handler = function()
			close()
			onConfirm()
		end,
	})
	confirm.button.Position = UDim2.new(0.5, 8, 1, -82)
	confirm.button.Size = UDim2.new(0.5, -42, 0, 50)
end

--- Settings sheet. Five persisted preferences, each with an explicit ON/OFF
--- face: a toggle that only changes colour is unreadable to a colour-blind
--- player and invisible at a glance. `onChange` fires after the local face has
--- already flipped, so the UI never waits on a server round trip to feel alive.
export type PreferenceKey = "sfx" | "music" | "vfx" | "shake" | "trades"

function Modals.settings(
	values: { sfx: boolean, music: boolean, vfx: boolean, shake: boolean, trades: boolean },
	onChange: (key: PreferenceKey, value: boolean) -> ()
)
	-- 462 rather than 400: the fifth row would otherwise leave the DONE plate
	-- sitting two pixels under it.
	local panel = shell("SETTINGS", "Saved to your profile.", Theme.Color.cyan, 462)

	local rows: { { key: PreferenceKey, label: string, note: string } } = {
		{ key = "sfx", label = "SOUND EFFECTS", note = "Strikes, forge results, UI ticks" },
		{ key = "music", label = "MUSIC", note = "The looped room tone under the forge" },
		{ key = "vfx", label = "SCREEN EFFECTS", note = "Sparks, rings, embers, flashes" },
		{ key = "shake", label = "SCREEN SHAKE", note = "Anvil and forge impact shake" },
		{ key = "trades", label = "ALLOW TRADE REQUESTS", note = "Off means other forgers cannot ask" },
	}

	-- The whole row is the switch. A 108px plaque at the far right is a target a
	-- thumb misses and an eye does not read as part of the row it sits on, which
	-- is what "I cannot click anything in settings" actually looked like.
	local chips: { [PreferenceKey]: Frame } = {}
	local faces: { [PreferenceKey]: TextLabel } = {}

	local function paint(key: PreferenceKey, on: boolean)
		local chip = chips[key]
		if chip then
			chip.BackgroundColor3 = if on then Theme.Color.emeraldDeep else Theme.Color.slate
		end
		local face = faces[key]
		if face then
			face.Text = if on then "ON" else "OFF"
			face.TextColor3 = if on then Theme.Color.emerald else Theme.Color.locked
		end
	end

	for index, row in rows do
		local y = 38 + (index - 1) * 58
		local on = values[row.key]

		local button = UiKit.button(panel, {
			text = "",
			fill = Theme.Color.panelSunken,
			stroke = Theme.Color.stroke,
			height = 54,
			radius = Theme.Radius.sm,
			handler = function()
				on = not on
				paint(row.key, on)
				onChange(row.key, on)
			end,
		})
		button.Name = string.format("Setting_%s", row.key)
		button.Position = UDim2.fromOffset(34, y)
		button.Size = UDim2.new(1, -68, 0, 54)

		local title = UiKit.label(button, {
			text = row.label,
			size = Theme.Text.Body,
			font = Theme.Font.Heading,
			color = Theme.Color.text,
		})
		title.Position = UDim2.fromOffset(14, 7)
		title.Size = UDim2.new(1, -108, 0, 22)
		title.ZIndex = 2

		local note = UiKit.label(button, {
			text = row.note,
			size = Theme.Text.Tiny,
			color = Theme.Color.textSecondary,
		})
		note.Position = UDim2.fromOffset(14, 29)
		note.Size = UDim2.new(1, -108, 0, 16)
		note.ZIndex = 2

		local chip = UiKit.create("Frame", {
			Name = "Chip",
			BackgroundColor3 = Theme.Color.slate,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(64, 28),
			ZIndex = 2,
		}) :: Frame
		UiKit.corner(chip, Theme.Radius.sm)
		UiKit.stroke(chip, Theme.Color.outline, 2, 0)
		chip.Parent = button

		local face = UiKit.label(chip, {
			text = "OFF",
			size = Theme.Text.Small,
			font = Theme.Font.Black,
			color = Theme.Color.locked,
			align = Enum.TextXAlignment.Center,
		})
		face.Name = "Face"
		face.Size = UDim2.fromScale(1, 1)
		face.ZIndex = 3

		chips[row.key] = chip
		faces[row.key] = face
		paint(row.key, on)
	end

	local done = UiKit.actionButton(panel, {
		label = "DONE",
		accent = Theme.Color.cyan,
		height = 46,
		radius = Theme.Radius.card,
		size = Theme.Text.Body,
		handler = close,
	})
	done.button.Name = "SettingsDone"
	done.button.Position = UDim2.new(0, 34, 1, -74)
	done.button.Size = UDim2.new(1, -68, 0, 46)
end

--- Blocking trade invite. Nothing exists on the server until ACCEPT is pressed:
--- `onAccept` sends the response verb and the session is created there, so a
--- declined or ignored invite leaves no half-open trade behind.
---
--- The countdown is local and the server owns the real deadline. It exists so
--- the target can see the offer is perishable; the server refusing a late
--- response is the authority.
function Modals.tradeRequest(
	name: string,
	seconds: number,
	onAccept: () -> (),
	onDecline: (() -> ())?)
	local panel, root = shell("TRADE REQUEST", "A FORGER IS AT YOUR DOOR", Theme.Color.emerald, 304)

	local plaque = UiKit.panel(panel, {
		tier = "well",
		radius = Theme.Radius.sm,
		stroke = Theme.Color.emerald,
		bevel = false,
		lip = false,
	})
	plaque.Name = "TradeRequestName"
	plaque.Position = UDim2.fromOffset(34, 46)
	plaque.Size = UDim2.new(1, -68, 0, 78)

	local who = UiKit.label(plaque, {
		text = name,
		size = 28,
		font = Theme.Font.Black,
		color = Theme.Color.emerald,
		align = Enum.TextXAlignment.Center,
		stroke = true,
	})
	who.Name = "Face"
	who.Size = UDim2.fromScale(1, 1)
	who.TextTruncate = Enum.TextTruncate.AtEnd

	local body = UiKit.label(panel, {
		text = "wants to trade blades and Void Shards with you.",
		size = Theme.Text.Body,
		color = Theme.Color.textDim,
		align = Enum.TextXAlignment.Center,
		wrap = true,
	})
	body.Position = UDim2.fromOffset(38, 132)
	body.Size = UDim2.new(1, -76, 0, 46)

	local countdown = UiKit.label(panel, {
		text = string.format("EXPIRES IN %d", seconds),
		size = Theme.Text.Tiny,
		font = Theme.Font.Label,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Center,
	})
	countdown.Name = "TradeRequestClock"
	countdown.Position = UDim2.fromOffset(0, 186)
	countdown.Size = UDim2.new(1, 0, 0, 18)

	local function answered(callback: (() -> ())?)
		if activeModal ~= root then
			return
		end
		close()
		if callback then
			callback()
		end
	end

	local decline = UiKit.button(panel, {
		text = "DECLINE",
		fill = Theme.Color.slate,
		stroke = Theme.Color.outline,
		height = 50,
		radius = Theme.Radius.card,
		size = Theme.Text.Body,
		handler = function()
			answered(onDecline)
		end,
	})
	decline.Name = "TradeRequestDecline"
	decline.Position = UDim2.new(0, 34, 1, -74)
	decline.Size = UDim2.new(0.5, -42, 0, 50)

	local accept = UiKit.actionButton(panel, {
		label = "ACCEPT",
		accent = Theme.Color.emerald,
		height = 50,
		radius = Theme.Radius.card,
		size = Theme.Text.Body,
		handler = function()
			answered(onAccept)
		end,
	})
	accept.button.Name = "TradeRequestAccept"
	accept.button.Position = UDim2.new(0.5, 8, 1, -74)
	accept.button.Size = UDim2.new(0.5, -42, 0, 50)

	task.spawn(function()
		local deadline = os.clock() + seconds
		while activeModal == root do
			local left = math.max(0, math.ceil(deadline - os.clock()))
			countdown.Text = if left > 0 then string.format("EXPIRES IN %d", left) else "EXPIRED"
			if left <= 0 then
				countdown.TextColor3 = Theme.Color.danger
				-- The invite is gone server-side by the time this fires. Closing
				-- here only removes a button that would be refused anyway.
				if activeModal == root then
					close()
				end
				return
			end
			task.wait(0.25)
		end
	end)
end

function Modals.init(canvas: Frame)
	canvasRoot = canvas
	-- A previous session's modal is gone with the old ScreenGui; keeping the
	-- reference would make the next `close()` animate a destroyed frame.
	activeModal = nil
end

return Modals
