--!strict
-- First-join coach notes. A small work-order slip sits beside the control the
-- player needs next, and a gold ring marks that control. There is no scrim, no
-- dim and no centred modal: the guide never takes the screen away, because the
-- old spotlight chain did exactly that and players closed it to get back to the
-- game.
--
-- The sequence follows the first real decisions:
--   1. strike until the core can vent
--   2. purge, with the gauge held at the threshold so reading the note cannot
--      cost the heat the note is about
--   3. earn the first drone's Aether
--   4. open Fleet
--   5. build a drone
--   6. open Crates
--   7. roll a blade
--   8. hand the game back
--
-- It is advice, not a lock: the card has a SKIP key on every step, the top-bar
-- GUIDE key becomes SKIP while the notes run, and no input is blocked. The only
-- state the server touches is the heat hold armed for the first two steps, and
-- that releases on vent, skip, leave or a two-minute timeout.
--
-- The handbook's replay key is the second entrance. It closes the book first so
-- the notes are not trying to point through a full-screen overlay, and it is
-- disabled while a run is already active.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local NumberUtil = require(Shared:WaitForChild("NumberUtil"))
local Types = require(Shared:WaitForChild("Types"))

local Theme = require(script.Parent.Theme)
local UiKit = require(script.Parent.UiKit)
local Sfx = require(script.Parent.Sfx)
local StateStore = require(script.Parent.StateStore)
local Sections = require(script.Parent.Sections)
local ForgeView = require(script.Parent.ForgeView)
local Modals = require(script.Parent.Modals)

local TutorialController = {}

TutorialController.onRunChanged = nil :: ((running: boolean) -> ())?

type Rect = {
	x: number,
	y: number,
	w: number,
	h: number,
}

type Step = {
	key: string,
	title: string,
	body: (Types.SyncPayload?) -> string,
	target: (() -> GuiObject?)?,
	place: string?,
	--- Positive grows the ring outside the control, negative insets it.
	grow: number?,
	--- Four corner brackets instead of a full outline. Used on target regions
	--- that already have a border, where a second rounded frame reads as a
	--- double border rather than as a highlight.
	brackets: boolean?,
	advance: ((Types.SyncPayload) -> boolean)?,
	enter: (() -> ())?,
	finish: boolean?,
}

local CARD_W = 360
local CARD_H = 176
local RING_Z = 21
local CARD_Z = 22
local BADGE_Z = 23
local POLL = 0.1

local canvas: Frame? = nil
local uiScale: UIScale? = nil
local layer: Frame? = nil
local card: Frame? = nil
local stepLabel: TextLabel? = nil
local titleLabel: TextLabel? = nil
local bodyLabel: TextLabel? = nil
local skipButton: TextButton? = nil
local skipLabel: TextLabel? = nil
local progressFill: Frame? = nil
local ring: Frame? = nil
local ringStroke: UIStroke? = nil
local brackets: { Frame } = {}
local badge: Frame? = nil
local badgeLabel: TextLabel? = nil

local steps: { Step } = {}
local index = 1
local running = false
local decided = false
local sawVent = false
--- True once any purge lands. A vent on step one means the player has already
--- done the lesson, so the chain hands over instead of demanding a second full
--- bar for the same key.
local sawAnyVent = false
local dronesAtStart = 0
local invAtStart = 0
local lastHoldRequest = 0
local pollAccum = 0
local lastCardX = -1
local lastCardY = -1
local unsubscribeSync: (() -> ())? = nil
local unsubscribeEvent: (() -> ())? = nil

-- ---------------------------------------------------------------------------
-- Copy
-- ---------------------------------------------------------------------------

local function dronePrice(payload: Types.SyncPayload?): number
	if payload == nil then
		return 7
	end
	-- The first rung is the lesson's drone. The spell's `droneCost` follows the
	-- selected rung, which on a replay can be a tier that costs millions.
	local first = payload.fleet[1]
	if first ~= nil and first.cost > 0 then
		return first.cost
	end
	return math.max(1, payload.droneCost)
end

local function rollPrice(payload: Types.SyncPayload?): number
	if payload == nil then
		return 50
	end
	local quote = payload.forgeCosts[payload.forgeCrate]
	if quote ~= nil then
		return quote.one
	end
	return math.max(1, payload.forgeCost)
end

local function canAffordRoll(payload: Types.SyncPayload?): boolean
	if payload == nil then
		return false
	end
	return payload.sm >= rollPrice(payload)
end

-- ---------------------------------------------------------------------------
-- Targets
-- ---------------------------------------------------------------------------

--- True only when the control is genuinely on screen. A hidden section keeps
--- its children at full size, so `Visible` has to be checked up the chain; a
--- tab that is behind a modal still counts as visible because the modal is
--- handled by the layer's ZIndex, not by this check.
local function isShown(target: GuiObject): boolean
	local host = canvas
	if host == nil then
		return false
	end
	if target.AbsoluteSize.X < 1 or target.AbsoluteSize.Y < 1 then
		return false
	end
	local node: Instance? = target
	while node ~= nil and node ~= host do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		node = node.Parent
	end
	return true
end

local function findVisible(name: string): GuiObject?
	local host = canvas
	if host == nil then
		return nil
	end
	local found = host:FindFirstChild(name, true)
	if found ~= nil and found:IsA("GuiObject") and isShown(found) then
		return found
	end
	return nil
end

local function targetTab(key: string): GuiObject?
	local button = Sections.tabButton(key)
	if button ~= nil and isShown(button) then
		return button
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Placement
-- ---------------------------------------------------------------------------

local function screenRect(target: GuiObject): Rect?
	local host = canvas
	if host == nil then
		return nil
	end
	local scale = if uiScale ~= nil then uiScale.Scale else 1
	if scale <= 0 then
		scale = 1
	end
	local origin = host.AbsolutePosition
	return {
		x = (target.AbsolutePosition.X - origin.X) / scale,
		y = (target.AbsolutePosition.Y - origin.Y) / scale,
		w = target.AbsoluteSize.X / scale,
		h = target.AbsoluteSize.Y / scale,
	}
end

local function placeCard(rect: Rect?, step: Step?)
	local host = canvas
	local panel = card
	if host == nil or panel == nil then
		return
	end
	local scale = if uiScale ~= nil then uiScale.Scale else 1
	if scale <= 0 then
		scale = 1
	end
	local areaW = host.AbsoluteSize.X / scale
	local areaH = host.AbsoluteSize.Y / scale
	local margin = 20
	local gap = 14
	local x: number
	local y: number

	if rect == nil then
		if step ~= nil and step.place == "stay" then
			-- The closing note replaces the last note in place instead of
			-- hopping somewhere else on a page that is full of live controls.
			return
		elseif step ~= nil and step.place == "bottomCenter" then
			x = (areaW - CARD_W) * 0.5
			y = areaH - CARD_H - margin
		elseif step ~= nil and step.place == "bottomLeft" then
			x = margin
			y = areaH - CARD_H - margin
		else
			x = areaW - CARD_W - margin
			y = 92
		end
	else
		local prefer = if step ~= nil and step.place ~= nil then step.place :: string else "right"
		if prefer == "left" then
			x = rect.x - CARD_W - gap
			y = rect.y
		elseif prefer == "above" then
			x = rect.x + rect.w * 0.5 - CARD_W * 0.5
			y = rect.y - CARD_H - gap
		elseif prefer == "below" then
			x = rect.x + rect.w * 0.5 - CARD_W * 0.5
			y = rect.y + rect.h + gap
		elseif prefer == "insideTopLeft" then
			x = rect.x + 16
			y = rect.y + 16
		elseif prefer == "insideTopRight" then
			x = rect.x + rect.w - CARD_W - 16
			y = rect.y + 16
		else
			x = rect.x + rect.w + gap
			y = rect.y
		end

		-- Fall back to the other side before clamping. A tab at the left edge
		-- has no room on its left, and a button at the bottom has no room below.
		if x < margin then
			x = rect.x + rect.w + gap
		elseif x + CARD_W > areaW - margin then
			x = rect.x - CARD_W - gap
		end
		if y < margin then
			y = rect.y + rect.h + gap
		elseif y + CARD_H > areaH - margin then
			y = rect.y - CARD_H - gap
		end
	end

	x = math.clamp(x, margin, math.max(margin, areaW - CARD_W - margin))
	y = math.clamp(y, margin, math.max(margin, areaH - CARD_H - margin))

	if math.abs(x - lastCardX) > 0.5 or math.abs(y - lastCardY) > 0.5 then
		lastCardX = x
		lastCardY = y
		panel.Position = UDim2.fromOffset(x, y)
	end
end

local function updateTarget()
	local step = steps[index]
	local target = if step ~= nil and step.target ~= nil then step.target() else nil
	-- A target on a section the player has navigated away from keeps its old
	-- absolute position. Pointing a ring at that empty stretch of panel is worse
	-- than dropping the ring and leaving the text.
	if target ~= nil and not isShown(target) then
		target = nil
	end
	if target == nil then
		if ring then
			ring.Visible = false
		end
		if badge then
			badge.Visible = false
		end
		placeCard(nil, step)
		return
	end

	local rect = screenRect(target)
	if rect == nil then
		return
	end
	local grow = if step ~= nil and step.grow ~= nil then step.grow :: number else 6
	local rx = rect.x - grow
	local ry = rect.y - grow
	local rw = math.max(8, rect.w + grow * 2)
	local rh = math.max(8, rect.h + grow * 2)

	local bracketMode = step ~= nil and step.brackets == true
	if ring then
		ring.Position = UDim2.fromOffset(rx, ry)
		ring.Size = UDim2.fromOffset(rw, rh)
		ring.Visible = true
	end
	if ringStroke then
		ringStroke.Enabled = not bracketMode
	end
	for _, part in brackets do
		part.Visible = bracketMode
	end
	if badge then
		-- The badge sits on the ring's corner, which the bracket already owns.
		badge.Position = UDim2.fromOffset(math.max(2, rx - 10), math.max(2, ry - 10))
		badge.Visible = not bracketMode
	end
	if badgeLabel then
		badgeLabel.Text = tostring(index)
	end
	placeCard(rect, step)
end

-- ---------------------------------------------------------------------------
-- Paint
-- ---------------------------------------------------------------------------

local function setSkipFace(finish: boolean)
	if skipLabel then
		skipLabel.Text = if finish then "FINISH" else "SKIP"
	end
end

local function renderStep(enter: boolean)
	local step = steps[index]
	if step == nil or card == nil then
		return
	end
	if stepLabel then
		stepLabel.Text = string.format("GUIDE %02d / %02d", index, #steps)
	end
	if titleLabel then
		titleLabel.Text = step.title
	end
	if bodyLabel then
		bodyLabel.Text = step.body(StateStore.current)
	end
	if progressFill then
		progressFill.Size = UDim2.fromScale(index / math.max(1, #steps), 1)
	end
	setSkipFace(step.finish == true)
	-- The gauge is frozen for the two lessons about heat. Every other step
	-- hands the bar back.
	ForgeView.setHeatHold(step.key == "strike" or step.key == "purge")
	if enter and step.enter ~= nil then
		step.enter()
	end
	updateTarget()
end

local function refreshCopy(payload: Types.SyncPayload?)
	local step = steps[index]
	local label = bodyLabel
	if step == nil or label == nil then
		return
	end
	local nextText = step.body(payload)
	if label.Text ~= nextText then
		label.Text = nextText
	end
end

-- ---------------------------------------------------------------------------
-- Run
-- ---------------------------------------------------------------------------

local function publishRun()
	if TutorialController.onRunChanged then
		TutorialController.onRunChanged(running)
	end
end

local function hideChrome()
	if card then
		card.Visible = false
	end
	if ring then
		ring.Visible = false
	end
	if badge then
		badge.Visible = false
	end
end

local function finish()
	if not running then
		return
	end
	running = false
	StateStore.send("tutorialHold", false)
	ForgeView.setHeatHold(false)
	local payload = StateStore.current
	if payload ~= nil then
		-- Replay on a finished account must not ask the server to pay the
		-- tutorial reward a second time.
		if not payload.tutorialCompleted then
			StateStore.send("tutorialDone")
		end
		if not payload.guideSeen then
			StateStore.send("guideSeen")
		end
	end
	hideChrome()
	publishRun()
end

local function start()
	if running then
		return
	end
	if card == nil or layer == nil then
		return
	end
	local payload = StateStore.current
	index = 1
	sawVent = false
	sawAnyVent = false
	lastHoldRequest = 0
	lastCardX = -1
	lastCardY = -1
	dronesAtStart = if payload ~= nil then payload.drones else 0
	invAtStart = if payload ~= nil then payload.invCount else 0
	running = true
	layer.Visible = true
	card.Visible = true
	-- Arm the server hold before the first strike. It costs nothing while the
	-- gauge is cold (decay still runs), and it means the purge lesson owns the
	-- gauge the moment it reaches the line instead of racing the auto-vent pass.
	StateStore.send("tutorialHold", true)
	-- The notes always begin at the anvil. On a replay from the handbook the
	-- player may be on any page, and a marker pointing at a hidden stage is
	-- worse than one navigation step.
	Sections.select("forge")
	renderStep(true)
	publishRun()
end

local function pump(payload: Types.SyncPayload)
	if not running then
		return
	end
	local step = steps[index]
	if step == nil or step.advance == nil then
		return
	end
	if not step.advance(payload) then
		return
	end
	if index >= #steps then
		finish()
		return
	end
	local function shouldSkip(nextStep: Step?): boolean
		return nextStep ~= nil and nextStep.key == "purge" and sawAnyVent
	end

	index += 1
	if shouldSkip(steps[index]) then
		-- Auto-vent already spent the heat. Asking for a manual purge now would
		-- demand a second full bar for a lesson the player has just performed.
		index += 1
	end
	sawVent = false
	renderStep(true)
end

-- ---------------------------------------------------------------------------
-- Steps
-- ---------------------------------------------------------------------------

local function buildSteps()
	steps = {
		{
			key = "strike",
			title = "STRIKE THE BLADE",
			body = function(): string
				return string.format(
					"Click the blade. Keep striking until core heat reaches %d%%.",
					Config.VentThreshold
				)
			end,
			target = function(): GuiObject?
				return ForgeView.strikeAnchor()
			end,
			place = "insideTopLeft",
			grow = 0,
			-- The stage already has a gold border. Four corner brackets say
			-- "this whole region" without drawing a second frame around it.
			brackets = true,
			advance = function(payload: Types.SyncPayload): boolean
				return payload.heat >= Config.VentThreshold or sawAnyVent
			end,
		},
		{
			key = "purge",
			title = "PURGE THE CORE",
			body = function(payload: Types.SyncPayload?): string
				local heat = if payload ~= nil then payload.heat else Config.VentThreshold
				if heat >= Config.VentThreshold - 0.5 then
					return string.format(
						"The gauge is holding at %d%%. Press PURGE to turn that heat into Aether.",
						Config.VentThreshold
					)
				end
				return string.format(
					"Strike a few more times to bring the core back to %d%%, then press PURGE.",
					Config.VentThreshold
				)
			end,
			target = function(): GuiObject?
				return ForgeView.ventAnchor()
			end,
			place = "left",
			advance = function(): boolean
				return sawVent
			end,
			enter = function()
				sawVent = false
				lastHoldRequest = os.clock()
				-- Refresh the deadline: step one can take longer than the hold.
				StateStore.send("tutorialHold", true)
			end,
		},
		{
			key = "aether",
			title = "SAVE FOR A DRONE",
			body = function(payload: Types.SyncPayload?): string
				return string.format(
					"A drone costs %s Aether. Strike, then purge at %d. Repeat until you can afford one.",
					NumberUtil.abbreviate(dronePrice(payload)),
					Config.VentThreshold
				)
			end,
			target = function(): GuiObject?
				return ForgeView.heatAnchor()
			end,
			place = "left",
			advance = function(payload: Types.SyncPayload): boolean
				return payload.as >= dronePrice(payload)
			end,
		},
		{
			key = "fleet",
			title = "OPEN THE FLEET",
			body = function(): string
				return "You can afford a drone. Open FLEET from the rail."
			end,
			target = function(): GuiObject?
				return targetTab("fleet")
			end,
			place = "right",
			advance = function(): boolean
				return Sections.activeTab() == "fleet"
			end,
		},
		{
			key = "drone",
			title = "BUILD A DRONE",
			body = function(): string
				return "Press BUILD 1. Drones earn Star-Matter while you do nothing."
			end,
			target = function(): GuiObject?
				return findVisible("BuyDrone")
			end,
			place = "left",
			advance = function(payload: Types.SyncPayload): boolean
				return payload.drones > dronesAtStart
			end,
		},
		{
			key = "crates",
			title = "OPEN THE CRATES",
			body = function(payload: Types.SyncPayload?): string
				return string.format(
					"A single roll costs %s SM. Open CRATES when you can afford it.",
					NumberUtil.abbreviate(rollPrice(payload))
				)
			end,
			target = function(): GuiObject?
				return targetTab("crates")
			end,
			place = "right",
			advance = function(): boolean
				return Sections.activeTab() == "crates"
			end,
		},
		{
			key = "roll",
			title = "ROLL A BLADE",
			body = function(payload: Types.SyncPayload?): string
				if canAffordRoll(payload) then
					return "Press ROLL. Every blade you forge multiplies every strike after it."
				end
				return string.format(
					"This roll costs %s SM. Strike until you can afford it.",
					NumberUtil.abbreviate(rollPrice(payload))
				)
			end,
			target = function(): GuiObject?
				return findVisible("RollOne")
			end,
			place = "above",
			advance = function(payload: Types.SyncPayload): boolean
				return payload.invCount > invAtStart
			end,
		},
		{
			key = "done",
			title = "THE LOOP IS YOURS",
			body = function(): string
				return "Strike, purge, build drones, roll better blades. The handbook has the rest. Go build something strange."
			end,
			target = nil,
			place = "stay",
			finish = true,
		},
	}
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------

local function buildUi(host: Frame)
	local frame = UiKit.create("Frame", {
		Name = "GuideLayer",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 20,
		Active = false,
	}) :: Frame
	frame.Parent = host
	layer = frame

	local panel = UiKit.panel(frame, {
		tier = "raised",
		radius = Theme.Radius.md,
		stroke = Theme.Color.outline,
		strokeThickness = Theme.Stroke.thin,
	})
	panel.Name = "GuideCard"
	panel.Size = UDim2.fromOffset(CARD_W, CARD_H)
	panel.Position = UDim2.fromOffset(20, 92)
	panel.Visible = false
	panel.Active = false
	panel.ZIndex = CARD_Z
	card = panel

	-- A work-order stripe, not a second border. The card already has the house
	-- outline; the stripe is the only gold on the surface, and it lines up with
	-- the ring around the control.
	local stripe = UiKit.create("Frame", {
		Name = "Stripe",
		BackgroundColor3 = Theme.Color.gold,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(1, 14),
		Size = UDim2.fromOffset(4, CARD_H - 28),
		ZIndex = CARD_Z + 1,
	}) :: Frame
	UiKit.corner(stripe, 2)
	stripe.Parent = panel

	stepLabel = UiKit.label(panel, {
		text = "GUIDE 01 / 08",
		size = Theme.Text.Micro,
		font = Theme.Font.Numeric,
		color = Theme.Color.gold,
	})
	stepLabel.Name = "GuideStep"
	stepLabel.Position = UDim2.fromOffset(20, 11)
	stepLabel.Size = UDim2.fromOffset(170, 18)
	stepLabel.ZIndex = CARD_Z + 1

	skipButton = UiKit.create("TextButton", {
		Name = "GuideSkip",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Position = UDim2.new(1, -94, 0, 4),
		Size = UDim2.fromOffset(80, 30),
		ZIndex = CARD_Z + 2,
	}) :: TextButton
	skipButton.Parent = panel

	skipLabel = UiKit.label(skipButton, {
		text = "SKIP",
		size = Theme.Text.Micro,
		font = Theme.Font.Heading,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Center,
	})
	skipLabel.Size = UDim2.fromScale(1, 1)
	skipLabel.ZIndex = CARD_Z + 3

	UiKit.track(skipButton, skipButton.MouseEnter:Connect(function()
		Sfx.hover()
		if skipLabel then
			skipLabel.TextColor3 = Theme.Color.gold
		end
	end))
	UiKit.track(skipButton, skipButton.MouseLeave:Connect(function()
		if skipLabel then
			skipLabel.TextColor3 = Theme.Color.textFaint
		end
	end))
	UiKit.track(skipButton, skipButton.Activated:Connect(function()
		Sfx.ui()
		finish()
	end))

	titleLabel = UiKit.label(panel, {
		text = "",
		size = 22,
		font = Theme.Font.Heading,
		color = Theme.Color.text,
	})
	titleLabel.Name = "GuideTitle"
	titleLabel.Position = UDim2.fromOffset(20, 32)
	titleLabel.Size = UDim2.new(1, -40, 0, 26)
	titleLabel.ZIndex = CARD_Z + 1

	bodyLabel = UiKit.label(panel, {
		text = "",
		size = Theme.Text.Body,
		font = Theme.Font.Body,
		color = Theme.Color.textDim,
		wrap = true,
		alignY = Enum.TextYAlignment.Top,
	})
	bodyLabel.Name = "GuideBody"
	bodyLabel.Position = UDim2.fromOffset(20, 64)
	bodyLabel.Size = UDim2.new(1, -40, 0, 80)
	bodyLabel.ZIndex = CARD_Z + 1

	local track = UiKit.create("Frame", {
		Name = "GuideProgress",
		BackgroundColor3 = Theme.Color.void,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(20, CARD_H - 15),
		Size = UDim2.new(1, -40, 0, 3),
		ZIndex = CARD_Z + 1,
	}) :: Frame
	UiKit.corner(track, 2)
	track.Parent = panel

	progressFill = UiKit.create("Frame", {
		Name = "Fill",
		BackgroundColor3 = Theme.Color.gold,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1 / 8, 1),
		ZIndex = CARD_Z + 2,
	}) :: Frame
	UiKit.corner(progressFill, 2)
	progressFill.Parent = track

	ring = UiKit.create("Frame", {
		Name = "GuideRing",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(0, 0),
		Visible = false,
		Active = false,
		ZIndex = RING_Z,
	}) :: Frame
	UiKit.corner(ring, 12)
	ringStroke = UiKit.stroke(ring, Theme.Color.gold, 2, 0.04)
	ring.Parent = frame

	-- Corner brackets, hidden unless a step asks for them. Two bars per corner:
	-- a 26px arm along each edge of the target region. Anchoring both bars on
	-- the corner means the arms grow inward for free at all four corners.
	local corners = { Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) }
	for _, corner in corners do
		for axis = 1, 2 do
			local bar = UiKit.create("Frame", {
				Name = if axis == 1 then "BracketX" else "BracketY",
				BackgroundColor3 = Theme.Color.gold,
				BorderSizePixel = 0,
				AnchorPoint = corner,
				Position = UDim2.fromScale(corner.X, corner.Y),
				Size = if axis == 1 then UDim2.fromOffset(26, 3) else UDim2.fromOffset(3, 26),
				Visible = false,
				Active = false,
				ZIndex = RING_Z + 1,
			}) :: Frame
			bar.Parent = ring
			table.insert(brackets, bar)
		end
	end

	badge = UiKit.create("Frame", {
		Name = "GuideBadge",
		BackgroundColor3 = Theme.Color.gold,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(24, 24),
		Visible = false,
		Active = false,
		ZIndex = BADGE_Z,
	}) :: Frame
	UiKit.corner(badge, 12)
	badge.Parent = frame

	badgeLabel = UiKit.label(badge, {
		text = "1",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.ink,
		align = Enum.TextXAlignment.Center,
	})
	badgeLabel.Size = UDim2.fromScale(1, 1)
	badgeLabel.ZIndex = BADGE_Z + 1
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------

function TutorialController.init(target: Frame, scale: UIScale?)
	canvas = target
	uiScale = scale
	buildSteps()
	buildUi(target)

	unsubscribeSync = StateStore.onSync(function(payload: Types.SyncPayload)
		if not decided then
			decided = true
			if payload.tutorialCompleted or payload.guideSeen then
				return
			end
			-- The starter boost is a blocking card on the first payload. Wait for
			-- it to be dismissed rather than drawing the first note behind it.
			task.spawn(function()
				-- Two seconds covers the starter event arriving just after the
				-- first payload on a cold join.
				task.wait(2)
				while canvas ~= nil and not running and Modals.isOpen() do
					task.wait(0.2)
				end
				if canvas ~= nil and not running then
					start()
				end
			end)
		end
		if running then
			pump(payload)
		end
	end)

	unsubscribeEvent = StateStore.onEvent(function(event: Types.FeedEvent)
		if not running then
			return
		end
		local step = steps[index]
		if step == nil then
			return
		end
		if event.kind == "vent" then
			sawAnyVent = true
			if step.key == "purge" then
				sawVent = true
			end
		end
	end)
end

--- Kept for the boot contract: `Main` calls it once the strike chain exists.
--- The guide no longer counts strikes itself, so there is nothing to attach.
function TutorialController.attachStrikeHook() end

--- Re-runs the notes from the anvil. Called by the handbook after it closes.
function TutorialController.replay()
	if running then
		return
	end
	start()
end

function TutorialController.skip()
	if running then
		finish()
	end
end

function TutorialController.isRunning(): boolean
	return running
end

--- Which note is on screen, for the Studio seam and the replay key.
function TutorialController.currentStep(): string?
	local step = steps[index]
	return if running and step ~= nil then step.key else nil
end

--- Keeps the ring on its control and refreshes copy that names a live price.
--- Called from the frame loop; the step logic itself runs on the 10Hz payload.
function TutorialController.step(dt: number)
	if not running then
		return
	end
	pollAccum += dt
	if pollAccum < POLL then
		return
	end
	pollAccum = 0
	local payload = StateStore.current
	local step = steps[index]
	if step ~= nil then
		-- Step 2 holds the gauge so reading the note cannot cost the vent. The
		-- server clamps and expires the hold on its own; this is only a refresh
		-- while the step is still open and the heat is still near the line.
		if step.key == "purge" and payload ~= nil then
			if payload.heat >= Config.VentThreshold - 5 and os.clock() - lastHoldRequest > 2 then
				lastHoldRequest = os.clock()
				StateStore.send("tutorialHold", true)
			end
		end
		refreshCopy(payload)
		updateTarget()
	end
end

function TutorialController.destroy()
	if unsubscribeSync then
		unsubscribeSync()
		unsubscribeSync = nil
	end
	if unsubscribeEvent then
		unsubscribeEvent()
		unsubscribeEvent = nil
	end
	if running then
		StateStore.send("tutorialHold", false)
	end
	if layer then
		layer:Destroy()
		layer = nil
	end
	card = nil
	stepLabel = nil
	titleLabel = nil
	bodyLabel = nil
	skipButton = nil
	skipLabel = nil
	progressFill = nil
	ring = nil
	ringStroke = nil
	brackets = {}
	badge = nil
	badgeLabel = nil
	steps = {}
	running = false
	decided = false
	pollAccum = 0
end

return TutorialController
