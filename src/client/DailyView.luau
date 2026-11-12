--!strict
-- The daily ritual.
--
-- Replaces a one-line toast. The old claim fired straight off the DAILY button and
-- announced itself in the notification column, which meant the player never saw
-- the track they were five days into, and day seven's Cores were a rumour. This is
-- the page that shows the whole week, what is already banked, what today pays, and
-- the one key that collects it.
--
-- The card reads `Config.DailyTrack` rather than its own copy of the numbers, so a
-- reward change is one edit in the shared config and the page follows.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Config = require(Shared:WaitForChild("Config"))
local NumberUtil = require(Shared:WaitForChild("NumberUtil"))
local Types = require(Shared:WaitForChild("Types"))

local Theme = require(script.Parent.Theme)
local Layout = require(script.Parent.Layout)
local UiKit = require(script.Parent.UiKit)
local ModalShell = require(script.Parent.ModalShell)
local StateStore = require(script.Parent.StateStore)
local Sfx = require(script.Parent.Sfx)

local DailyView = {}

local PANEL_W = math.min(1020, Layout.CONTENT_W - 32)
--- Panel height is the card, the claim key and the note under it, with 12px of
--- air. `ModalShell` keeps 58px for the banner, so the body is this minus 58.
local PANEL_H = math.min(470, Theme.DesignHeight - 80)

local PAD = 18
local CARD_GAP = 8

local handle: ModalShell.Handle? = nil
local open = false

local cards: { Frame } = {}
local claimKey: UiKit.ActionHandle? = nil
local streakLabel: TextLabel? = nil
local noteLabel: TextLabel? = nil

--- The day the player is on. `dailyStreak` is the last day claimed, so the next
--- one is a rollover; a fresh profile has 0 and starts at day one.
local function currentDay(state: Types.SyncPayload?): number
	if state == nil then
		return 1
	end
	return state.dailyStreak % #Config.DailyTrack + 1
end

-- ---------------------------------------------------------------------------
-- Painting
-- ---------------------------------------------------------------------------

local function rewardLines(reward: Config.DailyReward): { { text: string, color: Color3 } }
	-- The Aether figure is already the headline under the day number, so the row
	-- list starts at the toppings. Repeating the Aether figure under the headline
	-- was the same fact three times in 60 pixels.
	local lines = {}
	if (reward.scrap or 0) > 0 then
		table.insert(lines, { text = string.format("+%s SCRAP", NumberUtil.compact(reward.scrap)), color = Theme.Color.textSecondary })
	end
	if (reward.starMatter or 0) > 0 then
		table.insert(lines, { text = string.format("+%s SM", NumberUtil.compact(reward.starMatter)), color = Theme.Color.starMatter })
	end
	if (reward.cores or 0) > 0 then
		table.insert(lines, { text = string.format("+%d CORES", reward.cores), color = Theme.Color.quantum })
	end
	return lines
end

local function paint()
	local state = StateStore.current
	local today = currentDay(state)
	local ready = state ~= nil and state.dailyReady

	for index, card in cards do
		local face = card:FindFirstChild("State")
		local accent = card:FindFirstChild("Accent")
		-- `dailyStreak` is the last day claimed, so `today` is the next one:
		-- everything below it is banked, everything above it has not arrived.
		-- The card for `today` is only "claimed" once the clock has run out,
		-- which is what `ready` being false means.
		local claimed = state ~= nil and index < today
		local isToday = index == today

		if accent and accent:IsA("Frame") then
			accent.BackgroundColor3 = if claimed
				then Theme.Color.emerald
				elseif isToday then Theme.Color.gold
				else Theme.Color.locked
		end

		if face and face:IsA("TextLabel") then
			if claimed then
				face.Text = "CLAIMED"
				face.TextColor3 = Theme.Color.emerald
			elseif isToday and ready then
				face.Text = "TODAY"
				face.TextColor3 = Theme.Color.gold
			elseif isToday then
				face.Text = "NEXT UP"
				face.TextColor3 = Theme.Color.textFaint
			else
				face.Text = "LOCKED"
				face.TextColor3 = Theme.Color.locked
			end
		end

		card.BackgroundTransparency = if claimed then 0.35 elseif isToday then 0 else 0.15
		-- The plate fades for a claimed day, but the numbers inside it are separate
		-- GuiObjects and stayed at full contrast: banked days read as available.
		for _, child in card:GetDescendants() do
			if child:IsA("TextLabel") and child.Name ~= "State" then
				child.TextTransparency = if claimed then 0.45 else 0
			end
		end
	end

	if streakLabel then
		streakLabel.Text = if state
			then string.format("STREAK %d / %d", state.dailyStreak, #Config.DailyTrack)
			else "LINKING"
	end

	if claimKey then
		if ready then
			claimKey.set("ready", "COLLECT DAY " .. tostring(today), Theme.Color.gold)
		elseif state then
			claimKey.set("locked", "ALREADY COLLECTED TODAY", Theme.Color.locked)
		else
			claimKey.set("locked", "LINKING", Theme.Color.locked)
		end
	end

	if noteLabel then
		if ready then
			noteLabel.Text = "The clock resets 24 hours after your last claim. Miss 48 and the streak starts over."
			noteLabel.TextColor3 = Theme.Color.textSecondary
		elseif state then
			noteLabel.Text = "Back tomorrow for the next card. Day seven pays Quantum Cores."
			noteLabel.TextColor3 = Theme.Color.textFaint
		end
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function DailyView.init(canvas: Frame)
	if handle then
		return
	end

	local shell = ModalShell.build(canvas, {
		name = "DailyOverlay",
		title = "DAILY RITUAL",
		icon = "daily",
		accent = Theme.Color.emerald,
		width = PANEL_W,
		height = PANEL_H,
		onOpen = function()
			open = true
			paint()
		end,
		onClose = function()
			open = false
		end,
	}, 33)
	handle = shell

	local body = shell.body

	local head = UiKit.label(body, {
		text = "STREAK 0 / 7",
		size = Theme.Text.Tiny,
		font = Theme.Font.Heading,
		color = Theme.Color.textFaint,
	})
	head.Name = "StreakLabel"
	head.Position = UDim2.fromOffset(PAD, 10)
	head.Size = UDim2.fromOffset(300, 16)
	streakLabel = head

	-- Seven cards across the body. The width is measured once from the panel, not
	-- from the body at paint time: the strip has to line up with the claim key
	-- under it, and that key is sized from the same number.
	local bodyW = PANEL_W - PAD * 2
	local cardW = math.floor((bodyW - CARD_GAP * (#Config.DailyTrack - 1)) / #Config.DailyTrack)
	-- Tall enough for the deepest day (four reward lines) plus the state tag under
	-- it. Filling the panel instead left a dead band in the middle of every card.
	local cardH = 252

	for index, reward in Config.DailyTrack do
		local card = UiKit.create("Frame", {
			Name = string.format("Day%d", index),
			BackgroundColor3 = Theme.Color.panelRaised,
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(PAD + (index - 1) * (cardW + CARD_GAP), 34),
			Size = UDim2.fromOffset(cardW, cardH),
		}) :: Frame
		UiKit.corner(card, Theme.Radius.md)
		UiKit.stroke(card, Theme.Color.strokeFaint, Theme.Stroke.hair, 0.2)
		card.Parent = body

		local accent = UiKit.create("Frame", {
			Name = "Accent",
			BackgroundColor3 = Theme.Color.locked,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 5),
		}) :: Frame
		UiKit.corner(accent, 2)
		accent.ZIndex = 2
		accent.Parent = card

		local day = UiKit.label(card, {
			text = string.format("DAY %d", index),
			size = Theme.Text.Small,
			font = Theme.Font.Black,
			color = Theme.Color.textFaint,
			align = Enum.TextXAlignment.Center,
		})
		day.Position = UDim2.fromOffset(0, 14)
		day.Size = UDim2.new(1, 0, 0, 20)

		local aether = UiKit.label(card, {
			text = string.format("+%s", NumberUtil.compact(reward.aether or 0)),
			size = 40,
			font = Theme.Font.Black,
			color = Theme.Color.aether,
			align = Enum.TextXAlignment.Center,
			stroke = true,
			-- A seven-figure day has to fit the same 40px headline as a four-figure
			-- one; scaling down is what keeps "2.5M" inside the card instead of
			-- clipping it at the edge.
			scaled = true,
		})
		aether.Position = UDim2.fromOffset(0, 40)
		aether.Size = UDim2.new(1, 0, 0, 48)

		local unit = UiKit.label(card, {
			text = "AETHER",
			size = Theme.Text.Tiny,
			font = Theme.Font.Heading,
			color = Theme.Color.textFaint,
			align = Enum.TextXAlignment.Center,
		})
		unit.Position = UDim2.fromOffset(0, 86)
		unit.Size = UDim2.new(1, 0, 0, 16)

		local rule = UiKit.create("Frame", {
			BackgroundColor3 = Theme.Color.strokeFaint,
			BorderSizePixel = 0,
			BackgroundTransparency = 0.4,
			Position = UDim2.fromOffset(14, 110),
			Size = UDim2.new(1, -28, 0, 2),
		}) :: Frame
		rule.Parent = card

		local lines = rewardLines(reward)
		for lineIndex, line in lines do
			local extra = UiKit.label(card, {
				text = line.text,
				size = Theme.Text.Tiny,
				font = Theme.Font.Numeric,
				color = line.color,
				align = Enum.TextXAlignment.Center,
			})
			extra.Position = UDim2.fromOffset(0, 120 + (lineIndex - 1) * 22)
			extra.Size = UDim2.new(1, 0, 0, 18)
		end

		local state = UiKit.label(card, {
			text = "LOCKED",
			size = Theme.Text.Tiny,
			font = Theme.Font.Black,
			color = Theme.Color.locked,
			align = Enum.TextXAlignment.Center,
		})
		state.Name = "State"
		state.AnchorPoint = Vector2.new(0.5, 1)
		state.Position = UDim2.new(0.5, 0, 1, -14)
		state.Size = UDim2.fromOffset(cardW - 16, 18)

		cards[index] = card
	end

	claimKey = UiKit.actionButton(body, {
		label = "COLLECT",
		accent = Theme.Color.emerald,
		height = 58,
		radius = Theme.Radius.card,
		size = Theme.Text.Heading,
		handler = function()
			local state = StateStore.current
			if state == nil or not state.dailyReady then
				Sfx.error()
				return
			end
			StateStore.send("claimDaily")
			Sfx.coin()
			-- The button locks immediately instead of waiting for the payload, so a
			-- double press cannot fire two claims. The server is idempotent anyway;
			-- this just stops the second press from feeling broken.
			if claimKey then
				claimKey.set("locked", "COLLECTING...", Theme.Color.locked)
			end
		end,
	})
	claimKey.button.Position = UDim2.fromOffset(PAD, 34 + cardH + 16)
	claimKey.button.Size = UDim2.fromOffset(bodyW, 58)

	noteLabel = UiKit.label(body, {
		text = "",
		size = Theme.Text.Tiny,
		font = Theme.Font.Body,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Center,
	})
	noteLabel.Position = UDim2.fromOffset(PAD, 34 + cardH + 82)
	noteLabel.Size = UDim2.fromOffset(bodyW, 32)
	noteLabel.TextWrapped = true

	-- Repaint on every payload: the claim round-trips through the server, and the
	-- card should flip to CLAIMED from the authoritative streak, not from the tap.
	StateStore.onSync(function(_payload: Types.SyncPayload)
		if open then
			paint()
		end
	end)
end

function DailyView.open()
	if handle == nil then
		return
	end
	paint()
	handle.open()
end

function DailyView.close()
	if handle then
		handle.close()
	end
end

function DailyView.isOpen(): boolean
	return open
end

function DailyView.destroy()
	if handle then
		handle.destroy()
		handle = nil
	end
	table.clear(cards)
	claimKey = nil
	streakLabel = nil
	noteLabel = nil
	open = false
end

return DailyView
