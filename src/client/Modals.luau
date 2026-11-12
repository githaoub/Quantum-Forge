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
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local NumberUtil = require(Shared:WaitForChild("NumberUtil"))
local AssetManifest = require(Shared:WaitForChild("AssetManifest"))

local Theme = require(script.Parent.Theme)
local UiKit = require(script.Parent.UiKit)
local Sfx = require(script.Parent.Sfx)

local Modals = {}

local canvasRoot: Frame? = nil
local activeModal: Frame? = nil
--- Runs when a blocking card leaves for any reason: its own key, the X, the
--- Studio seam, or another card replacing it. The guide prompt uses it so an X
--- means the same thing as "I'LL PLAY" instead of leaving the run waiting.
local dismissHook: (() -> ())? = nil

local function close()
	if activeModal then
		local frame = activeModal
		local hook = dismissHook
		activeModal = nil
		dismissHook = nil
		Sfx.close()
		UiKit.dissolve(frame, Theme.Duration.fast)
		if hook then
			task.defer(hook)
		end
	end
end

--- True while a blocking card owns the screen. The coach notes wait for the
--- starter gift to be dismissed instead of pointing at controls behind it.
function Modals.isOpen(): boolean
	return activeModal ~= nil
end

--- Dismisses whatever blocking card is up. The welcome card has no close key by
--- design, so the Studio seam needs a way to stand in for its START FORGING
--- press without reaching into the module's private close.
function Modals.dismiss()
	close()
end

local function shell(
	title: string,
	subtitle: string?,
	accent: Color3,
	height: number?,
	locked: boolean?,
	onDismiss: (() -> ())?
): (Frame, Frame)
	-- Replacing one card with another is not a dismissal. Without this, a
	-- welcome card that lands a beat late would close the tour prompt and the
	-- prompt's dismiss hook would record "I'll play" for a player who never
	-- answered.
	dismissHook = nil
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
		-- The key hangs on the banner's corner but stays inside the card. At
		-- `-30` the 38px key ended 8px past the right edge, so it read as a red
		-- square floating beside the panel instead of a corner tab.
		closeButton.Position = UDim2.new(1, -44, 0, -12)
		closeButton.ZIndex = 63
	end

	activeModal = root
	dismissHook = onDismiss

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
	local minutes = math.max(1, math.floor(seconds / 60))
	local panel = shell(
		"2X STAR-MATTER",
		string.format("FOR YOUR FIRST %d MINUTES", minutes),
		Theme.Color.gold,
		396,
		true
	)

	-- The boost plate. The crystal is the Star-Matter icon the owner picked, so
	-- the card shows the currency being doubled rather than the pass art. The
	-- old x2 badge is the fallback, and the drawn bolt is the fallback under
	-- that, so a cold cache still shows a card instead of an empty ring.
	local plate = UiKit.create("Frame", {
		Name = "BoostPlate",
		BackgroundColor3 = Theme.Color.panelSunken,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 60),
		Size = UDim2.fromOffset(104, 104),
		ZIndex = 62,
	}) :: Frame
	UiKit.corner(plate, 52)
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

	local art = AssetManifest.uiArt("star_matter_crystal")
	if art == "" then
		art = AssetManifest.UiArt.x2_star_matter
	end
	if art and art ~= "" then
		-- The image has to be opaque enough to load. A Roblox ImageLabel at
		-- `ImageTransparency = 1` stays unloaded, which is why the first version
		-- kept the bolt forever. It sits under the bolt instead: when the bitmap
		-- arrives it draws, and the fallback fades away on top of it.
		local image = UiKit.create("ImageLabel", {
			Name = "Art",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			Image = art,
			ScaleType = Enum.ScaleType.Fit,
			ImageTransparency = 0,
			ZIndex = 62,
		}) :: ImageLabel
		UiKit.corner(image, 52)
		image.Parent = plate
		task.spawn(function()
			for _ = 1, 80 do
				if image.IsLoaded or not image.Parent then
					break
				end
				task.wait(0.1)
			end
			if image.IsLoaded then
				UiKit.tween(bolt, Theme.Duration.normal, { BackgroundTransparency = 1 })
				UiKit.tween(notch, Theme.Duration.normal, { BackgroundTransparency = 1 })
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
	multiplier.Position = UDim2.fromOffset(0, 176)
	multiplier.Size = UDim2.new(1, 0, 0, 62)

	local note = UiKit.label(panel, {
		text = "Strikes and drones pay double. The clock is already running.",
		size = Theme.Text.Small,
		font = Theme.Font.Body,
		color = Theme.Color.textSecondary,
		align = Enum.TextXAlignment.Center,
	})
	note.Position = UDim2.fromOffset(28, 250)
	note.Size = UDim2.new(1, -56, 0, 40)
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

--- Asked once, after the welcome card, never at the same time as it. The two
--- loading cards used to land together and the player had to dismiss a wall of
--- text before the anvil existed. This one is a yes/no, not a lesson: the guide
--- itself is the next thing, and the quiet key is a real answer.
function Modals.guidePrompt(onYes: () -> (), onNo: () -> ())
	local answered = false
	local function finish(yes: boolean)
		if answered then
			return
		end
		answered = true
		close()
		if yes then
			onYes()
		else
			onNo()
		end
	end

	local panel = shell("WANT A QUICK TOUR?", "NO READING · ABOUT THIRTY SECONDS", Theme.Color.cyan, 294, false, function()
		finish(false)
	end)

	local pitch = UiKit.label(panel, {
		text = "I point. You tap. That's it.",
		size = Theme.Text.Body,
		font = Theme.Font.Body,
		color = Theme.Color.textSecondary,
		align = Enum.TextXAlignment.Center,
	})
	pitch.Position = UDim2.fromOffset(28, 62)
	pitch.Size = UDim2.new(1, -56, 0, 24)

	local show = UiKit.actionButton(panel, {
		label = "SHOW ME",
		accent = Theme.Color.cyan,
		height = 56,
		radius = Theme.Radius.card,
		size = Theme.Text.Heading,
		handler = function()
			finish(true)
		end,
	})
	show.button.Position = UDim2.fromOffset(36, 112)
	show.button.Size = UDim2.new(1, -72, 0, 56)

	local play = UiKit.button(panel, {
		text = "I'LL PLAY",
		height = 46,
		radius = Theme.Radius.card,
		size = Theme.Text.Small,
		font = Theme.Font.Black,
		textColor = Theme.Color.textDim,
		fill = Theme.Color.slate,
		stroke = Theme.Color.stroke,
		handler = function()
			finish(false)
		end,
	})
	play.Position = UDim2.fromOffset(36, 178)
	play.Size = UDim2.new(1, -72, 0, 46)

	local hint = UiKit.label(panel, {
		text = "You can replay it any time from GUIDE.",
		size = Theme.Text.Tiny,
		font = Theme.Font.Label,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Center,
	})
	hint.Position = UDim2.fromOffset(28, 236)
	hint.Size = UDim2.new(1, -56, 0, 18)
end

--- Generic confirm. `onConfirm` fires only on the affirmative path. When
--- `lockedReason` is set the affirmative key is painted as a locked plate and
--- the handler never runs; the caller still gets the same panel so a player can
--- read what the action would need.
function Modals.confirm(
	title: string,
	body: string,
	confirmText: string,
	accent: Color3,
	onConfirm: () -> (),
	lockedReason: string?
)
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
		handler = if lockedReason == nil
			then function()
				close()
				onConfirm()
			end
			else nil,
	})
	if lockedReason ~= nil then
		confirm.set("locked", lockedReason)
	end
	confirm.button.Position = UDim2.new(0.5, 8, 1, -82)
	confirm.button.Size = UDim2.new(0.5, -42, 0, 50)
end

--- Settings sheet. Audio is a level, not a switch: a player asking for "quieter"
--- has no use for a control that only offers silence. The two audio rows carry
--- a 0..100 slider; 0 is the mute. The remaining rows keep an explicit ON/OFF
--- face, because a toggle that only changes colour is unreadable to a
--- colour-blind player and invisible at a glance.
---
--- `onChange` fires after the local face has already moved, so the UI never
--- waits on a server round trip to feel alive.
export type PreferenceKey = "sfxVolume" | "musicVolume" | "vfx" | "shake" | "trades"

function Modals.settings(
	values: { sfxVolume: number, musicVolume: number, vfx: boolean, shake: boolean, trades: boolean },
	onChange: (key: PreferenceKey, value: boolean | number) -> ()
)
	-- 500 rather than 462: two audio rows are 72 tall to hold the slider track.
	-- Five 58px rows plus the DONE plate left the old sheet two pixels short.
	local panel = shell("SETTINGS", "Saved to your profile.", Theme.Color.cyan, 500)

	local rows: { { key: PreferenceKey, label: string, note: string, volume: boolean } } = {
		{ key = "sfxVolume", label = "SOUND EFFECTS", note = "Strikes, crate ceremony, UI ticks", volume = true },
		{ key = "musicVolume", label = "MUSIC", note = "The looped room tone under the forge", volume = true },
		{ key = "vfx", label = "SCREEN EFFECTS", note = "Sparks, rings, embers, flashes", volume = false },
		{ key = "shake", label = "SCREEN SHAKE", note = "Anvil and forge impact shake", volume = false },
		{ key = "trades", label = "ALLOW TRADE REQUESTS", note = "Off means other forgers cannot ask", volume = false },
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

	local y = 38
	for _, row in rows do
		local height = if row.volume then 72 else 54
		local on = row.key == "vfx" and values.vfx
			or row.key == "shake" and values.shake
			or row.key == "trades" and values.trades
			or false

		local button = UiKit.button(panel, {
			text = "",
			fill = Theme.Color.panelSunken,
			stroke = Theme.Color.stroke,
			height = height,
			radius = Theme.Radius.sm,
			handler = function()
				if row.volume then
					return
				end
				on = not on
				paint(row.key, on)
				onChange(row.key, on)
			end,
		})
		button.Name = string.format("Setting_%s", row.key)
		button.Position = UDim2.fromOffset(34, y)
		button.Size = UDim2.new(1, -68, 0, height)

		local title = UiKit.label(button, {
			text = row.label,
			size = Theme.Text.Body,
			font = Theme.Font.Heading,
			color = Theme.Color.text,
		})
		title.Position = UDim2.fromOffset(14, if row.volume then 6 else 7)
		title.Size = UDim2.new(1, -108, 0, 22)
		title.ZIndex = 2

		local note = UiKit.label(button, {
			text = row.note,
			size = Theme.Text.Tiny,
			color = Theme.Color.textSecondary,
		})
		note.Position = UDim2.fromOffset(14, if row.volume then 26 else 29)
		note.Size = UDim2.new(1, -108, 0, 16)
		note.ZIndex = 2

		if row.volume then
			local initial = if row.key == "sfxVolume" then values.sfxVolume else values.musicVolume

			local percent = UiKit.label(button, {
				text = "0%",
				size = Theme.Text.Small,
				font = Theme.Font.Numeric,
				color = Theme.Color.cyan,
				align = Enum.TextXAlignment.Right,
			})
			percent.Name = "Volume"
			percent.Position = UDim2.new(1, -78, 0, 7)
			percent.Size = UDim2.fromOffset(58, 20)
			percent.ZIndex = 2

			local track = UiKit.create("Frame", {
				Name = "Track",
				BackgroundColor3 = Theme.Color.slate,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(14, 50),
				Size = UDim2.new(1, -28, 0, 6),
				ZIndex = 2,
			}) :: Frame
			UiKit.corner(track, 3)
			track.Parent = button

			local fill = UiKit.create("Frame", {
				Name = "Fill",
				BackgroundColor3 = Theme.Color.cyan,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(0, 1),
				ZIndex = 3,
			}) :: Frame
			UiKit.corner(fill, 3)
			fill.Parent = track

			local knob = UiKit.create("Frame", {
				Name = "Knob",
				BackgroundColor3 = Theme.Color.text,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0, 0.5),
				Size = UDim2.fromOffset(14, 14),
				ZIndex = 4,
			}) :: Frame
			UiKit.corner(knob, 7)
			UiKit.stroke(knob, Theme.Color.outline, 2, 0)
			knob.Parent = track

			-- The hit area is taller than the 6px track: a thumb needs 24px, and
			-- the rail still draws as a thin line.
			local hit = UiKit.create("TextButton", {
				Name = "Slider",
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Text = "",
				Position = UDim2.fromOffset(14, 38),
				Size = UDim2.new(1, -28, 0, 26),
				ZIndex = 5,
			}) :: TextButton
			hit.Parent = button

			local function paintLevel(level: number, notify: boolean)
				local snapped = math.clamp(math.floor(level * 20 + 0.5) / 20, 0, 1)
				fill.Size = UDim2.fromScale(snapped, 1)
				knob.Position = UDim2.fromScale(snapped, 0.5)
				percent.Text = string.format("%d%%", math.floor(snapped * 100 + 0.5))
				if notify then
					onChange(row.key, snapped)
				end
			end

			local dragging = false
			local dragChanged: RBXScriptConnection? = nil
			local dragEnded: RBXScriptConnection? = nil

			local function stopDrag()
				dragging = false
				if dragChanged then
					dragChanged:Disconnect()
					dragChanged = nil
				end
				if dragEnded then
					dragEnded:Disconnect()
					dragEnded = nil
				end
			end

			local function applyAtX(x: number)
				local width = track.AbsoluteSize.X
				if width <= 0 then
					return
				end
				paintLevel((x - track.AbsolutePosition.X) / width, true)
			end

			hit.InputBegan:Connect(function(input: InputObject)
				if input.UserInputType ~= Enum.UserInputType.MouseButton1
					and input.UserInputType ~= Enum.UserInputType.Touch
				then
					return
				end
				dragging = true
				applyAtX(input.Position.X)
				stopDrag()
				dragging = true
				dragChanged = UserInputService.InputChanged:Connect(function(move: InputObject)
					if dragging
						and (move.UserInputType == Enum.UserInputType.MouseMovement
							or move.UserInputType == Enum.UserInputType.Touch)
					then
						applyAtX(move.Position.X)
					end
				end)
				dragEnded = UserInputService.InputEnded:Connect(function(stopped: InputObject)
					if stopped.UserInputType == Enum.UserInputType.MouseButton1
						or stopped.UserInputType == Enum.UserInputType.Touch
					then
						stopDrag()
						Sfx.ui()
					end
				end)
			end)
			hit.Destroying:Connect(stopDrag)

			paintLevel(initial, false)
		else
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

		y += height + 6
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
