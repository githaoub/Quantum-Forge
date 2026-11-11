--!strict
-- First-join welcome card. One card, one screen, one button: it opens the
-- handbook and gets out of the way.
--
-- The old flow was a threshold machine. Eight lessons, each a card that fired on
-- a heat, vent, forge, fleet, rune, ascension or tech crossing, an objective strip
-- that never left the canvas, and a spotlight ring that re-resolved a control by
-- name four times a second. It interrupted play, and when the ring lost its
-- target (a tab switch destroys the button) it pointed at nothing while the card
-- said to press it.
--
-- This module now owns exactly one thing: the welcome. Everything the old guide
-- tried to teach lives in `HandbookView`, which the player opens on purpose and
-- which reads its numbers from the same config the systems run on.
--
-- `guideSeen` is the latch. It is written the moment the card is dismissed, so
-- the card never force-opens again. The GUIDE key in the top bar always opens
-- the handbook, whether or not this player has seen it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))

local Theme = require(script.Parent.Theme)
local UiKit = require(script.Parent.UiKit)
local StateStore = require(script.Parent.StateStore)
local HandbookView = require(script.Parent.HandbookView)

local TutorialController = {}

local CARD_W = 520
local CARD_H = 304

local scrim: TextButton? = nil
local card: Frame? = nil
local shown = false
local finished = false
local decided = false

local unsubscribe: (() -> ())? = nil

local function publishRun()
	if TutorialController.onRunChanged then
		TutorialController.onRunChanged(shown)
	end
end

local function hideCard()
	if scrim then
		UiKit.tween(scrim, 0.16, { BackgroundTransparency = 1 })
	end
	if card then
		UiKit.tween(card, 0.16, { BackgroundTransparency = 1 })
	end
	task.delay(0.18, function()
		if scrim then
			scrim.Visible = false
		end
		if card then
			card.Visible = false
		end
	end)
	shown = false
	publishRun()
end

--- Claims the completion reward and writes both latches. Idempotent: a card that
--- is closed twice cannot pay twice, because the server also checks
--- `tutorialCompleted`.
local function finish()
	if finished then
		return
	end
	finished = true
	hideCard()
	StateStore.send("tutorialDone")
	StateStore.send("guideSeen")
end

local function openHandbook()
	finish()
	HandbookView.openAt("loop")
end

local function build(canvas: Frame)
	local blocker = UiKit.create("TextButton", {
		Name = "WelcomeScrim",
		BackgroundColor3 = Theme.Color.ink,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 70,
	}) :: TextButton
	blocker.Parent = canvas
	scrim = blocker

	local frame = UiKit.create("Frame", {
		Name = "WelcomeCard",
		BackgroundColor3 = Theme.Color.panel,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = 71,
	}) :: Frame
	UiKit.corner(frame, Theme.Radius.card)
	UiKit.stroke(frame, Theme.Color.gold, Theme.Stroke.bold, 1)
	UiKit.gradient(frame, { Theme.Color.panelRaised, Theme.Color.panel }, 90)
	frame.Parent = canvas
	card = frame

	local banner = UiKit.banner(frame, {
		text = "WELCOME TO QUANTUM FORGE",
		position = UDim2.fromOffset(14, -24),
		width = UDim2.new(1, -28, 0, 54),
		size = 21,
		accent = Theme.Color.gold,
		icon = "★",
	})
	banner.ZIndex = 72
	for _, child in banner:GetDescendants() do
		if child:IsA("GuiObject") then
			child.ZIndex += 2
		end
	end

	local kicker = UiKit.label(frame, {
		text = "THE ORBITAL BRIDGE IS YOURS",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.gold,
		align = Enum.TextXAlignment.Center,
	})
	kicker.Position = UDim2.fromOffset(24, 40)
	kicker.Size = UDim2.new(1, -48, 0, 20)
	kicker.ZIndex = 3

	local copy = UiKit.label(frame, {
		text = "Strike the anvil to forge Star-Matter. Open CRATES to roll a blade; every copy you pull multiplies the next strike.",
		size = Theme.Text.Body,
		font = Theme.Font.Body,
		color = Theme.Color.textSecondary,
		align = Enum.TextXAlignment.Center,
		wrap = true,
	})
	copy.Name = "WelcomeBody"
	copy.Position = UDim2.fromOffset(36, 68)
	copy.Size = UDim2.new(1, -72, 0, 76)
	copy.ZIndex = 3

	local hint = UiKit.label(frame, {
		text = "The handbook explains heat, rolls, variants, the vault, the fleet, runes, ascension and trading. Open it any time from GUIDE.",
		size = Theme.Text.Tiny,
		font = Theme.Font.Label,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Center,
		wrap = true,
	})
	hint.Position = UDim2.fromOffset(36, 150)
	hint.Size = UDim2.new(1, -72, 0, 52)
	hint.ZIndex = 3

	local cta = UiKit.actionButton(frame, {
		label = "OPEN THE HANDBOOK",
		accent = Theme.Color.gold,
		height = 54,
		radius = Theme.Radius.card,
		size = Theme.Text.Body,
		handler = openHandbook,
	})
	cta.button.Name = "WelcomeCta"
	cta.button.Position = UDim2.fromOffset(36, 212)
	cta.button.Size = UDim2.new(1, -72, 0, 54)
	cta.button.ZIndex = 4

	local skip = UiKit.create("TextButton", {
		Name = "WelcomeSkip",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "JUST LET ME PLAY",
		TextColor3 = Theme.Color.textSecondary,
		TextSize = Theme.Text.Tiny,
		Font = Theme.Font.Heading,
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.fromOffset(0, 272),
		ZIndex = 5,
	}) :: TextButton
	skip.MouseEnter:Connect(function()
		skip.TextColor3 = Theme.Color.gold
	end)
	skip.MouseLeave:Connect(function()
		skip.TextColor3 = Theme.Color.textSecondary
	end)
	skip.Parent = frame
	skip.Activated:Connect(finish)

	local close = UiKit.closeButton(frame, finish)
	close.Position = UDim2.new(1, -44, 0, -16)
	close.Size = UDim2.fromOffset(34, 34)
	close.ZIndex = 6
end

local function showCard()
	if scrim == nil or card == nil then
		return
	end
	shown = true
	scrim.Visible = true
	card.Visible = true
	scrim.BackgroundTransparency = 1
	card.BackgroundTransparency = 1
	UiKit.tween(scrim, 0.2, { BackgroundTransparency = 0.42 })
	UiKit.tween(card, 0.22, { BackgroundTransparency = Theme.elevation("raised").transparency })
	publishRun()
end

local function evaluate(state: Types.SyncPayload)
	if not decided then
		decided = true
		finished = state.tutorialCompleted == true or state.guideSeen == true
		if not finished then
			showCard()
		end
	end
end

function TutorialController.init(canvas: Frame, _uiScale: UIScale?)
	build(canvas)
	unsubscribe = StateStore.onSync(evaluate)
end

--- Kept for the boot contract: the old guide counted strikes to collapse a
--- lesson. There is no lesson to collapse now, but `Main` still calls this and a
--- missing export would be a boot error rather than a no-op.
function TutorialController.attachStrikeHook() end

function TutorialController.replay()
	HandbookView.openAt("loop")
end

function TutorialController.skip()
	if shown then
		finish()
	end
end

function TutorialController.isRunning(): boolean
	return shown
end

--- The welcome card has no per-frame state. The ring, the pulse and the target
--- re-resolve are gone with the flow they served.
function TutorialController.step(_dt: number) end

function TutorialController.destroy()
	if unsubscribe then
		unsubscribe()
		unsubscribe = nil
	end
	if scrim then
		scrim:Destroy()
		scrim = nil
	end
	if card then
		card:Destroy()
		card = nil
	end
	shown = false
	finished = false
	decided = false
end

return TutorialController
