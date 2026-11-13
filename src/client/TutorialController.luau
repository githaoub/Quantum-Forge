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
--      cost the heat the note is about. The ring follows the job: the blade
--      while the bar is short, the key once it is full
--   3. earn the first drone's Aether, open Fleet, build the drone
--   4. earn the first crate's Star-Matter, open Crates, roll a blade
--   5. hand the game back: explore, read GUIDE, replay the tour
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
local ModalShell = require(script.Parent.ModalShell)

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
	--- Optional gate. A gated step is skipped when the gate is closed at the
	--- moment the chain arrives, so a note about a cache cannot ask for a cache
	--- that never dropped.
	gate: ((Types.SyncPayload) -> boolean)?,
	--- Informational step: it has no action to watch, so the card carries a NEXT
	--- key. Skipping still ends the whole guide.
	next: boolean?,
	enter: (() -> ())?,
	--- Runs on the 10Hz poll while the step is active. Used by the one step that
	--- changes pages on the player's behalf instead of asking them to read a
	--- navigation instruction.
	tick: ((Types.SyncPayload) -> ())?,
	finish: boolean?,
}

local CARD_W = 344
local CARD_H = 210
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
local nextButton: TextButton? = nil
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
--- The drone step waits one beat after the price is affordable before it takes
--- the player to FLEET. A page that snaps the frame the number turns green
--- reads as a hijack; a 0.9 s beat reads as a hand on the shoulder.
local droneReadyAt = 0
local droneOpened = false
--- The crate lesson mirrors the drone lesson: wait until the standard crate is
--- affordable, then take the player to CRATES once. The step advances on a new
--- vault copy, not on the page opening, so the note cannot be satisfied by a
--- navigation. It counts copies rather than banner rolls because the roll
--- counter resets when the player switches pools.
local copiesAtStart = 0
local crateReadyAt = 0
local crateOpened = false
local pollAccum = 0
local lastCardX = -1
local lastCardY = -1
local pulseClock = 0
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

--- The standard banner's next single roll. The lesson is about the first crate,
--- so it quotes the banner a new account can actually open, not whichever pool
--- the player happens to be browsing.
local function cratePrice(payload: Types.SyncPayload?): number
	if payload == nil then
		return 50
	end
	local quote = payload.forgeCosts["standard"]
	if quote ~= nil and quote.one > 0 then
		return quote.one
	end
	return 50
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
		stepLabel.Text = string.format("STEP %d OF %d", index, #steps)
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
	-- SKIP stays SKIP on every step. The closing card carries a big DONE key
	-- instead of renaming the escape hatch, so a kid never has to work out
	-- whether the small top-right word is the ending or the way out.
	setSkipFace(false)
	if nextButton then
		local showNext = step.next == true or step.finish == true
		nextButton.Visible = showNext
		local face = nextButton:FindFirstChild("Face")
		if face and face:IsA("TextLabel") then
			face.Text = if step.finish == true then "DONE" else "NEXT"
		end
	end
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

--- The "I'LL PLAY" answer. It marks the guide as seen so the next session does
--- not ask again; the GUIDE key stays available for a player who changes their
--- mind.
local function decline()
	local payload = StateStore.current
	if payload ~= nil and not payload.guideSeen then
		StateStore.send("guideSeen")
	end
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
	droneReadyAt = 0
	droneOpened = false
	crateReadyAt = 0
	crateOpened = false
	copiesAtStart = 0
	lastCardX = -1
	lastCardY = -1
	dronesAtStart = if payload ~= nil then payload.drones else 0
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

--- The one consent card. It waits for the starter card to leave first, because
--- two full-screen cards back to back is the exact wall this pass removes. The
--- quiet gap also covers the starter event arriving a beat after the payload.
local function offer()
	task.spawn(function()
		task.wait(1.2)
		while canvas ~= nil and not running and Modals.isOpen() do
			task.wait(0.2)
		end
		if canvas == nil or running then
			return
		end
		-- The starter card fades out for `fast`; `isOpen` flips before the frame
		-- finishes dissolving. The extra beat keeps the two cards from sharing a
		-- frame, which is exactly the pile-up this pass removes.
		task.wait(0.35)
		Modals.guidePrompt(function()
			start()
		end, function()
			decline()
		end)
	end)
end

local function eligible(step: Step?, payload: Types.SyncPayload?): boolean
	if step == nil then
		return false
	end
	if step.gate == nil or payload == nil then
		return true
	end
	return step.gate(payload)
end

--- Steps past the current one. Gated steps are skipped without a frame on
--- screen, so a note about a cache cannot flash when no cache dropped.
local function moveNext(payload: Types.SyncPayload?)
	if index >= #steps then
		finish()
		return
	end
	repeat
		index += 1
	until index >= #steps or eligible(steps[index], payload)
	if index > #steps then
		index = #steps
	end
	renderStep(true)
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
	moveNext(payload)
end

-- ---------------------------------------------------------------------------
-- Steps
-- ---------------------------------------------------------------------------

local function buildSteps()
	steps = {
		{
			key = "strike",
			title = "TAP THE BLADE",
			body = function(): string
				return "Every strike pays Star-Matter. Fill the heat bar."
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
			title = "PURGE THE HEAT",
			body = function(payload: Types.SyncPayload?): string
				local heat = if payload ~= nil then payload.heat else Config.VentThreshold
				if heat < Config.VentThreshold - 0.5 then
					return "Tap the blade until the bar is full."
				end
				return "Press the purge key. Heat becomes Aether."
			end,
			-- The ring follows the job, not the step. A ring on the purge key
			-- while the copy says "tap the blade" is the dead end this step used
			-- to have: the key cannot fire until the bar is full again.
			target = function(): GuiObject?
				if Sections.activeTab() ~= "forge" then
					return targetTab("forge")
				end
				local payload = StateStore.current
				if payload ~= nil and payload.heat < Config.VentThreshold - 0.5 then
					return ForgeView.strikeAnchor()
				end
				return ForgeView.ventAnchor()
			end,
			place = "left",
			-- A vent during step one already taught this key. Asking for a
			-- second full bar would be busywork.
			gate = function(): boolean
				return not sawAnyVent
			end,
			-- A purge is the whole lesson. It used to also demand the drone
			-- price, and one purge at the line pays 6.8 Aether against a 7
			-- Aether drone, so the card sat with its ring on a key that was
			-- locked and no instruction to strike again. Earning the drone is
			-- the next step's job.
			advance = function(): boolean
				return sawVent
			end,
			enter = function()
				sawVent = false
				-- Refresh the deadline: step one can take longer than the hold.
				StateStore.send("tutorialHold", true)
			end,
		},
		{
			key = "drone",
			title = "BUILD A DRONE",
			body = function(payload: Types.SyncPayload?): string
				local price = dronePrice(payload)
				if payload == nil or payload.as < price then
					local head = string.format(
						"The first drone costs %s Aether. You have %s.",
						NumberUtil.abbreviate(price),
						NumberUtil.abbreviate(if payload ~= nil then payload.as else 0)
					)
					if payload ~= nil and payload.heat >= Config.VentThreshold then
						return head .. " Purge the heat."
					end
					return head .. " Strike, then purge."
				end
				return "Press BUILD 1. It earns Star-Matter while you do nothing."
			end,
			-- While the first drone is still out of reach the card points at the
			-- forge, not at a locked BUILD key. A ring around a key the player
			-- cannot press reads as the game demanding money they do not have.
			-- When the bar is full the ring moves to the purge key, so the
			-- lesson is the loop and not just "press the blade forever".
			target = function(): GuiObject?
				local payload = StateStore.current
				if payload == nil or payload.as < dronePrice(payload) then
					if Sections.activeTab() ~= "forge" then
						return targetTab("forge")
					end
					if payload ~= nil and payload.heat >= Config.VentThreshold then
						return ForgeView.ventAnchor()
					end
					return ForgeView.strikeAnchor()
				end
				if Sections.activeTab() ~= "fleet" then
					return targetTab("fleet")
				end
				return findVisible("BuyDrone")
			end,
			place = "right",
			-- A replay already owns drones. Asking a level-65 account to buy a
			-- 300M hull to finish a tour is a purchase demand, not a lesson.
			gate = function(): boolean
				return dronesAtStart == 0
			end,
			advance = function(payload: Types.SyncPayload): boolean
				return payload.drones > dronesAtStart
			end,
			enter = function()
				local payload = StateStore.current
				droneReadyAt = 0
				droneOpened = Sections.activeTab() == "fleet"
				if payload ~= nil and payload.as >= dronePrice(payload) then
					droneReadyAt = os.clock()
				end
			end,
			tick = function(payload: Types.SyncPayload)
				if droneOpened or ModalShell.openCount() > 0 then
					return
				end
				if payload.as < dronePrice(payload) then
					droneReadyAt = 0
					return
				end
				if droneReadyAt == 0 then
					droneReadyAt = os.clock()
					return
				end
				if os.clock() - droneReadyAt < 0.9 then
					return
				end
				droneOpened = true
				Sections.select("fleet")
				Sfx.tab()
			end,
		},
		{
			key = "crate",
			title = "OPEN A CRATE",
			body = function(payload: Types.SyncPayload?): string
				local price = cratePrice(payload)
				local sm = if payload ~= nil then payload.sm else 0
				if sm < price then
					return string.format(
						"The first crate costs %s Star-Matter. You have %s. Every strike earns it. Purge when the bar is full.",
						NumberUtil.abbreviate(price),
						NumberUtil.abbreviate(sm)
					)
				end
				if Sections.activeTab() ~= "crates" then
					return string.format(
						"The first crate costs %s Star-Matter. You have enough. Opening CRATES.",
						NumberUtil.abbreviate(price)
					)
				end
				return "Press ROLL. It forges your first blade."
			end,
			target = function(): GuiObject?
				local payload = StateStore.current
				if payload == nil or payload.sm < cratePrice(payload) then
					if Sections.activeTab() ~= "forge" then
						return targetTab("forge")
					end
					if payload ~= nil and payload.heat >= Config.VentThreshold then
						return ForgeView.ventAnchor()
					end
					return ForgeView.strikeAnchor()
				end
				if Sections.activeTab() ~= "crates" then
					return targetTab("crates")
				end
				return findVisible("RollOne") or targetTab("crates")
			end,
			place = "left",
			-- A replay already forged a blade. The starter blade counts as one
			-- copy, so `<= 1` is "nothing forged yet"; gating on `== 0` would
			-- skip the lesson on every fresh account.
			gate = function(payload: Types.SyncPayload): boolean
				return payload.invCount <= 1 and payload.forgeRolls == 0
			end,
			advance = function(payload: Types.SyncPayload): boolean
				return payload.invCount > copiesAtStart or payload.invCount >= payload.invMax
			end,
			enter = function()
				local payload = StateStore.current
				copiesAtStart = if payload ~= nil then payload.invCount else 0
				crateReadyAt = 0
				crateOpened = Sections.activeTab() == "crates"
			end,
			tick = function(payload: Types.SyncPayload)
				if crateOpened or ModalShell.openCount() > 0 then
					return
				end
				if payload.sm < cratePrice(payload) then
					crateReadyAt = 0
					return
				end
				if crateReadyAt == 0 then
					crateReadyAt = os.clock()
					return
				end
				if os.clock() - crateReadyAt < 0.9 then
					return
				end
				crateOpened = true
				Sections.select("crates")
				Sfx.tab()
			end,
		},
		{
			key = "done",
			title = "THE REST IS YOURS",
			body = function(): string
				return "Tap, purge, build, roll. The rest is yours to figure out. The GUIDE section explains every system, and you can replay this tour any time."
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
	-- Below the modal stack on purpose. The short guide never asks the player to
	-- act inside a panel, so an open vault or roster simply covers the card and
	-- gives it back on close. At 80 the card painted on top of the players list
	-- and hid the row it was sitting over.
	local frame = UiKit.create("Frame", {
		Name = "GuideLayer",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 40,
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
		text = "STEP 1 OF 5",
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
	bodyLabel.Size = UDim2.new(1, -40, 0, 78)
	bodyLabel.ZIndex = CARD_Z + 1

	-- Informational steps have nothing to watch, so they carry a NEXT key. It
	-- sits above the progress rule, which stays visible on every step.
	nextButton = UiKit.create("TextButton", {
		Name = "GuideNext",
		BackgroundColor3 = Theme.Color.gold,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		Position = UDim2.fromOffset(CARD_W - 20 - 112, CARD_H - 54),
		Size = UDim2.fromOffset(112, 34),
		ZIndex = CARD_Z + 2,
	}) :: TextButton
	UiKit.corner(nextButton, Theme.Radius.sm)
	UiKit.stroke(nextButton, Theme.Color.outline, Theme.Stroke.thin, 0)
	nextButton.Parent = panel

	local nextFace = UiKit.label(nextButton, {
		text = "NEXT",
		size = Theme.Text.Micro,
		font = Theme.Font.Black,
		color = Theme.Color.ink,
		align = Enum.TextXAlignment.Center,
	})
	nextFace.Name = "Face"
	nextFace.Size = UDim2.fromScale(1, 1)
	nextFace.ZIndex = CARD_Z + 3

	UiKit.track(nextButton, nextButton.MouseEnter:Connect(function()
		Sfx.hover()
	end))
	UiKit.track(nextButton, nextButton.Activated:Connect(function()
		TutorialController.next()
	end))

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
		Size = UDim2.fromScale(1 / 5, 1),
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
				-- Publish the decision even though no note will draw. The nudge
				-- layer starts muted and waits for this exact signal; a returning
				-- account would otherwise never hear from it.
				publishRun()
				return
			end
			-- The starter boost is a blocking card on the first payload. The
			-- offer waits for it to close instead of drawing a second card on
			-- top of it, which is what the old chain did.
			offer()
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

--- The NEXT key on an informational step. Public so `QF_Dev` can walk the
--- chain without a pointer, and so the key's handler stays one line.
function TutorialController.next()
	if running then
		Sfx.ui()
		moveNext(StateStore.current)
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
		refreshCopy(payload)
		updateTarget()
		if payload ~= nil and step.tick ~= nil then
			step.tick(payload)
		end
	end

	-- An open panel owns the screen, and the card belongs to the forge. Hide it
	-- under a vault or a roster instead of stacking a note over the list; the
	-- next tick after the close paints it again.
	local blocked = ModalShell.openCount() > 0
	if card then
		card.Visible = not blocked
	end
	if blocked then
		if ring then
			ring.Visible = false
		end
		if badge then
			badge.Visible = false
		end
	end

	-- A still ring is a border; a breathing one is a finger. The pulse is only
	-- on the stroke, never on layout, so it cannot move the target it is
	-- pointing at. Bracket steps pulse their corner arms instead.
	pulseClock += POLL
	local wave = 0.5 + 0.5 * math.sin(pulseClock * 4.2)
	if ringStroke then
		ringStroke.Transparency = 0.12 + 0.35 * wave
	end
	for _, part in brackets do
		if part.Visible then
			part.BackgroundTransparency = 0.1 + 0.3 * wave
		end
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
	nextButton = nil
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
