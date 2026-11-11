--!strict
-- The trade desk: a live offer board, a copy picker, and both sides confirmed.
--
-- This panel is a mirror, never an authority. Everything it shows — who is
-- online, what is on the table, whether the other side has accepted — comes
-- back from the server, and every button sends an intent that the server
-- re-validates against both profiles. The one local draft is the offer being
-- assembled, because a selection has to survive a repaint at 1Hz.
--
-- The security rules live in `TradeService`; the parts that matter here:
--   * offered copies are locked against melting and rerolling while the offer
--     stands, so the "offer then melt" scam has nothing to land on;
--   * any change to either offer clears both accept flags, which is why ACCEPT
--     re-disables the moment the other side touches their side;
--   * the equipped copy and favorites are not offerable, so the picker filters
--     them out and never has to explain a refusal;
--   * a request is an invite, not a session. `ASK` only puts a popup on the
--     other player's screen.
--
-- Three 3D stages exist in this panel and they are deliberately different:
--   offer cards     `BladePreview.mount`   turntable, variant glow
--   picker cards    `BladePreview.thumbnail`  static, because twenty spinners
--   none            the rail is text only
--
-- Cleanups are tracked. A repaint destroys the frames, and an orbit controller
-- left holding a global input connection would keep dragging a model that no
-- longer exists.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BladeRegistry = require(Shared:WaitForChild("BladeRegistry"))
local ForgeConfig = require(Shared:WaitForChild("ForgeConfig"))
local ModifierConfig = require(Shared:WaitForChild("ModifierConfig"))
local NumberUtil = require(Shared:WaitForChild("NumberUtil"))
local Types = require(Shared:WaitForChild("Types"))

local Theme = require(script.Parent.Theme)
local UiKit = require(script.Parent.UiKit)
local BladePreview = require(script.Parent.BladePreview)
local ModalShell = require(script.Parent.ModalShell)
local StateStore = require(script.Parent.StateStore)
local Sfx = require(script.Parent.Sfx)
local Notifications = require(script.Parent.Notifications)

local TradeView = {}

local POLL_SECONDS = 0.35
local PARTNER_SECONDS = 5
local MAX_BLADES = 8
local SHARD_STEP = 100

-- Design-space geometry. The panel is 1120 wide with a 236px rail, and every
-- number below is measured off that: the two offer columns have to be equal, and
-- the picker has to fit five cards in the same width without a horizontal
-- scrollbar.
local RAIL_W = 236
local DIVIDER_X = 264
local DESK_X = 280
local DESK_W = 824
local COL_GAP = 14
local COL_W = math.floor((DESK_W - COL_GAP) / 2)
-- Offer rows are full-column width. A card wide enough to hold a name, a
-- variant chip and a multiplier on one plate is the only way eight offers stay
-- readable; a 60px thumbnail square beside a 100px name truncates every title.
-- Three rows fit the column exactly, which matters: a clipped fourth row reads
-- as a layout bug, and an offer board you have to scroll after three copies is
-- a board that hides the thing being traded.
local OFFER_CARD_W = COL_W - 24
local OFFER_CARD_H = 64
local PICK_CARD_W = 154
local PICK_CARD_H = 100

local shell: ModalShell.Handle? = nil
local partnerList: ScrollingFrame? = nil
local partnerHeader: TextLabel? = nil
local deskArea: Frame? = nil
local statusLine: TextLabel? = nil
local footer: Frame? = nil

local offerUids: { [string]: boolean } = {}
local offerOrder: { string } = {}
local offerShards = 0
local pollClock = 0
local partnerClock = 0
local lastSignature = ""
local lastTheirSignature = ""
local lastPartnerSignature = ""
local lastInventorySignature = ""
local acceptArmed = false
local acceptAt = 0

-- Live 3D stages and their teardown, one bucket per column so a repaint of one
-- side cannot tear down a model the other side still owns. Rebuilt often; never
-- leaked.
local myStages: { () -> () } = {}
local theirStages: { () -> () } = {}

type Desk = {
	sessionKey: string,
	head: TextLabel,
	myCount: TextLabel,
	theirCount: TextLabel,
	myGrid: ScrollingFrame,
	theirGrid: ScrollingFrame,
	picker: ScrollingFrame,
	countLabel: TextLabel,
	myShards: TextLabel,
	theirShards: TextLabel,
	myStepper: Frame,
	timer: TextLabel,
	cards: { [string]: Frame },
}

local desk: Desk? = nil
local lastState: any = nil

local function releaseBucket(bucket: { () -> () })
	for _, cleanup in bucket do
		cleanup()
	end
	table.clear(bucket)
end

local function releaseStages()
	releaseBucket(myStages)
	releaseBucket(theirStages)
end

local function signatureOf(state: any): string
	if state == nil then
		return "none"
	end
	local parts = {
		tostring(state.target),
		tostring(state.myShards),
		tostring(state.theirShards),
		tostring(state.myAccepted),
		tostring(state.theirAccepted),
	}
	for _, row in state.myBlades or {} do
		parts[#parts + 1] = "m" .. tostring(row.uid)
	end
	for _, row in state.theirBlades or {} do
		parts[#parts + 1] = "t" .. tostring(row.uid)
	end
	return table.concat(parts, "|")
end

local function theirSignatureOf(state: any): string
	if state == nil then
		return "none"
	end
	local parts = { tostring(state.theirShards), tostring(state.theirAccepted) }
	for _, row in state.theirBlades or {} do
		parts[#parts + 1] = "t" .. tostring(row.uid)
	end
	return table.concat(parts, "|")
end

local function inventorySignature(): string
	local parts = {}
	local equipped = StateStore.current and StateStore.current.equippedUid or ""
	parts[#parts + 1] = equipped
	for _, entry in StateStore.inventory do
		parts[#parts + 1] = tostring(entry.uid)
	end
	local favorites = StateStore.current and StateStore.current.favorites or {}
	for uid, flag in favorites do
		if flag then
			parts[#parts + 1] = "f" .. uid
		end
	end
	return table.concat(parts, "|")
end

--- Copies the picker may show. The equipped copy and favorites are excluded by
--- the server too; filtering here means the grid never offers a copy the server
--- would refuse.
local function tradeableCopies(): { Types.InvEntry }
	local equipped = StateStore.current and StateStore.current.equippedUid or ""
	local favorites = StateStore.current and StateStore.current.favorites or {}
	local out: { Types.InvEntry } = {}
	for _, entry in StateStore.inventory do
		if entry.uid ~= equipped and not favorites[entry.uid] then
			table.insert(out, entry)
		end
	end
	table.sort(out, function(a: Types.InvEntry, b: Types.InvEntry): boolean
		return ForgeConfig.powerCopy(a) > ForgeConfig.powerCopy(b)
	end)
	return out
end

local function copyOf(uid: string): Types.InvEntry?
	for _, entry in StateStore.inventory do
		if entry.uid == uid then
			return entry
		end
	end
	return nil
end

local function copyLabel(entry: any): (string, string, Color3)
	local blade = BladeRegistry.get(tostring(entry.id or ""))
	local grade = tostring(entry.grade or "")
	local element = tostring(entry.element or "")
	local prefix = tostring(entry.prefix or "")
	local suffix = tostring(entry.suffix or "")
	local tint = if element ~= "" then ModifierConfig.element(element).color else Theme.Color.textDim
	local name = if blade then ModifierConfig.displayName(blade.name, prefix, suffix) else tostring(entry.id)
	return name, ModifierConfig.condition(grade, element), tint
end

local function variantTint(entry: any): Color3
	return ForgeConfig.variant(tostring(entry.variant or ForgeConfig.StandardVariant)).color
end

local function offerCount(): number
	local count = 0
	for _ in offerUids do
		count += 1
	end
	return count
end

local function syncedFrom(state: any)
	offerUids = {}
	table.clear(offerOrder)
	for _, row in state.myBlades or {} do
		local uid = tostring(row.uid)
		if not offerUids[uid] then
			offerUids[uid] = true
			table.insert(offerOrder, uid)
		end
	end
	offerShards = tonumber(state.myShards) or 0
end

--- Sends the assembled draft. Called on every toggle and every shard change:
--- the server is the one that decides whether an offer is legal, so the client
--- never holds a state the server has not seen.
local function pushOffer()
	StateStore.send("tradeOffer", { uids = table.clone(offerOrder), shards = offerShards })
end

-- ---------------------------------------------------------------------------
-- Offer and picker cards
-- ---------------------------------------------------------------------------

--- Selection tick. `width` is the card width, because the offer card and the
--- picker card are different sizes and the box has to sit on the top-right
--- corner of whichever it is on.
local function tickBox(parent: Frame, selected: boolean, width: number): Frame
	local box = UiKit.create("Frame", {
		Name = "Tick",
		BackgroundColor3 = if selected then Theme.Color.emeraldDeep else Theme.Color.panelSunken,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(width - 26, 8),
		Size = UDim2.fromOffset(18, 18),
		ZIndex = 6,
	}) :: Frame
	UiKit.corner(box, 4)
	UiKit.stroke(box, if selected then Theme.Color.emerald else Theme.Color.stroke, 2, 0)
	local mark = UiKit.label(box, {
		text = "✓",
		size = 15,
		font = Theme.Font.Black,
		color = Theme.Color.ink,
		align = Enum.TextXAlignment.Center,
	})
	mark.Name = "Mark"
	mark.Size = UDim2.fromScale(1, 1)
	mark.TextTransparency = if selected then 0 else 1
	mark.ZIndex = 7
	box.Parent = parent
	return box
end

--- One card in either offer column. `mine` cards carry a tick and are the
--- click target for removing a copy; theirs are read-only.
local function offerCard(
	parent: Instance,
	entry: any,
	mine: boolean,
	order: number,
	accent: Color3,
	onToggle: (() -> ())?,
	bucket: { () -> () }
)
	local chosen = mine and offerUids[tostring(entry.uid)] == true
	local card = UiKit.panel(parent, {
		tier = if chosen then "raised" else "well",
		radius = Theme.Radius.sm,
		stroke = if chosen then accent else Theme.Color.strokeFaint,
		bevel = false,
		lip = false,
	})
	card.Name = string.format("%s_%s_%d", if mine then "MyOffer" else "TheirOffer", tostring(entry.uid), order)
	card.Size = UDim2.fromOffset(OFFER_CARD_W, OFFER_CARD_H)
	card.LayoutOrder = order

	local stage = UiKit.create("ViewportFrame", {
		Name = "Stage",
		BackgroundColor3 = Theme.Color.void,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(48, 48),
		ZIndex = 3,
	}) :: ViewportFrame
	UiKit.corner(stage, 6)
	UiKit.stroke(stage, Theme.Color.strokeFaint, 1, 0)
	stage.Parent = card

	local blade = BladeRegistry.get(tostring(entry.id or ""))
	if blade then
		-- Spinning models here, not thumbnails: the offer board is the place
		-- where the copy is being handed over, and a turntable reads as an
		-- object rather than as an inventory listing.
		table.insert(bucket, BladePreview.mount(stage, blade, variantTint(entry)))
	else
		stage.BackgroundColor3 = Theme.Color.slate
	end

	if mine then
		tickBox(card, chosen, OFFER_CARD_W)
	end

	local name = UiKit.label(card, {
		text = select(1, copyLabel(entry)),
		size = Theme.Text.Tiny,
		font = Theme.Font.Heading,
		color = Theme.Color.text,
		align = Enum.TextXAlignment.Left,
	})
	name.Position = UDim2.fromOffset(64, 4)
	name.Size = UDim2.fromOffset(OFFER_CARD_W - 98, 18)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.ZIndex = 4

	local variant = ForgeConfig.variant(tostring(entry.variant or ForgeConfig.StandardVariant))
	local chip = UiKit.badge(card, {
		text = string.upper(variant.name),
		color = variant.color,
		width = 92,
		height = 17,
		size = Theme.Text.Tiny,
		textColor = Theme.Color.ink,
	})
	chip.Name = "VariantChip"
	chip.Position = UDim2.fromOffset(64, 23)
	chip.ZIndex = 4

	local mult = UiKit.label(card, {
		-- `abbreviateMultiplier` already carries its own "x"; prefixing it was
		-- printing "xx45.11K" on both offer strips.
		text = NumberUtil.abbreviateMultiplier(ForgeConfig.powerCopy(entry)),
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = accent,
		align = Enum.TextXAlignment.Left,
	})
	mult.Position = UDim2.fromOffset(164, 23)
	mult.Size = UDim2.fromOffset(OFFER_CARD_W - 204, 17)
	mult.ZIndex = 4

	local condition = UiKit.label(card, {
		text = select(2, copyLabel(entry)),
		size = Theme.Text.Tiny,
		font = Theme.Font.Label,
		color = Theme.Color.textSecondary,
		align = Enum.TextXAlignment.Left,
	})
	condition.Position = UDim2.fromOffset(64, 43)
	condition.Size = UDim2.fromOffset(OFFER_CARD_W - 72, 16)
	condition.TextTruncate = Enum.TextTruncate.AtEnd
	condition.ZIndex = 4

	if mine and onToggle then
		local hit = UiKit.create("TextButton", {
			Name = "Remove",
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 5,
		}) :: TextButton
		hit.Parent = card
		UiKit.track(hit, hit.Activated:Connect(onToggle))
	end
end

--- One card in the picker grid. Static model, because this grid can hold the
--- whole vault and twenty-five turntables is a framerate crime.
local function pickerCard(parent: Instance, entry: Types.InvEntry, order: number, onToggle: () -> ())
	local uid = tostring(entry.uid)
	local chosen = offerUids[uid] == true
	local variant = ForgeConfig.variant(tostring(entry.variant or ForgeConfig.StandardVariant))

	local card = UiKit.panel(parent, {
		tier = if chosen then "raised" else "well",
		radius = Theme.Radius.sm,
		stroke = if chosen then Theme.Color.emerald else Theme.Color.strokeFaint,
		bevel = false,
		lip = false,
	})
	card.Name = string.format("Pick_%s_%d", uid, order)
	card:SetAttribute("Uid", uid)
	card.Size = UDim2.fromOffset(PICK_CARD_W, PICK_CARD_H)
	card.LayoutOrder = order

	-- A 4px variant bar. Cheaper than a chip at this size, and it makes a
	-- prismatic copy visible from across the grid.
	local bar = UiKit.create("Frame", {
		BackgroundColor3 = variant.color,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 4),
		ZIndex = 2,
	}) :: Frame
	UiKit.corner(bar, 2)
	bar.Parent = card

	local stage = UiKit.create("ViewportFrame", {
		Name = "Stage",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset((PICK_CARD_W - 40) / 2, 6),
		Size = UDim2.fromOffset(40, 40),
		ZIndex = 3,
	}) :: ViewportFrame
	stage.Parent = card

	local blade = BladeRegistry.get(tostring(entry.id or ""))
	if blade then
		BladePreview.thumbnail(stage, blade, false, variant.color)
	else
		stage.BackgroundColor3 = Theme.Color.slate
	end

	tickBox(card, chosen, PICK_CARD_W)

	local name = UiKit.label(card, {
		text = select(1, copyLabel(entry)),
		size = Theme.Text.Tiny,
		font = Theme.Font.Heading,
		color = Theme.Color.text,
		align = Enum.TextXAlignment.Center,
	})
	name.Name = "Name"
	name.Position = UDim2.fromOffset(6, 48)
	name.Size = UDim2.fromOffset(PICK_CARD_W - 12, 16)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.ZIndex = 4

	local mult = UiKit.label(card, {
		-- `abbreviateMultiplier` already carries its own "x"; prefixing it was
		-- printing "xx45.11K" on both offer strips.
		text = NumberUtil.abbreviateMultiplier(ForgeConfig.powerCopy(entry)),
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.gold,
		align = Enum.TextXAlignment.Center,
	})
	mult.Name = "Mult"
	mult.Position = UDim2.fromOffset(6, 64)
	mult.Size = UDim2.fromOffset(PICK_CARD_W - 12, 15)
	mult.ZIndex = 4

	local condition = UiKit.label(card, {
		text = ModifierConfig.condition(tostring(entry.grade or ""), tostring(entry.element or "")),
		size = Theme.Text.Tiny,
		font = Theme.Font.Label,
		color = Theme.Color.textSecondary,
		align = Enum.TextXAlignment.Center,
	})
	condition.Name = "Condition"
	condition.Position = UDim2.fromOffset(6, 79)
	condition.Size = UDim2.fromOffset(PICK_CARD_W - 12, 15)
	condition.TextTruncate = Enum.TextTruncate.AtEnd
	condition.ZIndex = 4

	local hit = UiKit.create("TextButton", {
		Name = "Hit",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
	}) :: TextButton
	hit.Parent = card
	UiKit.track(hit, hit.Activated:Connect(onToggle))
end

-- ---------------------------------------------------------------------------
-- Desk
-- ---------------------------------------------------------------------------

local paintMyOffer: () -> ()
local paintTheirOffer: (any) -> ()
local paintSelection: () -> ()
local paintFooter: (any) -> ()
local buildPicker: () -> ()

local function toggleOffer(uid: string)
	if offerUids[uid] then
		offerUids[uid] = nil
		for index, candidate in offerOrder do
			if candidate == uid then
				table.remove(offerOrder, index)
				break
			end
		end
	else
		if offerCount() >= MAX_BLADES then
			Notifications.push(string.format("Up to %d blades per side", MAX_BLADES), "warn")
			return
		end
		offerUids[uid] = true
		table.insert(offerOrder, uid)
	end
	Sfx.tab()
	pushOffer()
	paintMyOffer()
	paintSelection()
	if lastState then
		paintFooter(lastState)
	end
end

local function columnFrame(parent: Instance, x: number, title: string, tint: Color3, name: string): (Frame, TextLabel)
	local frame = UiKit.panel(parent, {
		tier = "well",
		radius = Theme.Radius.sm,
		stroke = Theme.Color.strokeFaint,
		bevel = false,
		lip = false,
	})
	frame.Name = name
	frame.Position = UDim2.fromOffset(x, 32)
	frame.Size = UDim2.fromOffset(COL_W, 248)

	local label = UiKit.label(frame, {
		text = title,
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = tint,
		align = Enum.TextXAlignment.Left,
	})
	label.Name = "Heading"
	label.Position = UDim2.fromOffset(10, 8)
	label.Size = UDim2.fromOffset(COL_W - 20, 18)

	local count = UiKit.label(frame, {
		text = "0 / 8",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Right,
	})
	count.Name = "Count"
	count.AnchorPoint = Vector2.new(1, 0)
	count.Position = UDim2.new(1, -10, 0, 8)
	count.Size = UDim2.fromOffset(90, 18)

	return frame, count
end

local function gridIn(frame: Frame, name: string): ScrollingFrame
	local area = UiKit.scroll(frame, { thickness = 3 })
	area.Name = name
	area.Position = UDim2.fromOffset(8, 32)
	area.Size = UDim2.new(1, -16, 1, -40)
	UiKit.grid(area, UDim2.fromOffset(OFFER_CARD_W, OFFER_CARD_H), 8)
	UiKit.padding(area, 0, 4, 4)
	return area
end

local function buildDesk(state: any)
	local area = deskArea
	if area == nil then
		return
	end
	releaseStages()
	ModalShell.clear(area)
	acceptArmed = false

	local accent = Theme.Color.emerald
	local sessionKey = tostring(state.targetId or state.target or "")

	local head = UiKit.label(area, {
		text = string.format("TRADING WITH %s", string.upper(tostring(state.target or "?"))),
		size = Theme.Text.Subheading,
		font = Theme.Font.Black,
		color = accent,
		align = Enum.TextXAlignment.Left,
	})
	head.Name = "TradeHead"
	head.Position = UDim2.fromOffset(0, 0)
	head.Size = UDim2.fromOffset(DESK_W - 220, 28)
	head.TextTruncate = Enum.TextTruncate.AtEnd

	local timer = UiKit.label(area, {
		text = "",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Right,
	})
	timer.Name = "TradeTimer"
	timer.AnchorPoint = Vector2.new(1, 0)
	timer.Position = UDim2.new(1, 0, 0, 4)
	timer.Size = UDim2.fromOffset(180, 20)

	local mineFrame, myCount = columnFrame(area, 0, "YOUR OFFER", accent, "YourSide")
	local theirsFrame, theirCount = columnFrame(area, COL_W + COL_GAP, "THEIR OFFER", Theme.Color.cyan, "TheirSide")

	local myGrid = gridIn(mineFrame, "MyOfferGrid")
	local theirGrid = gridIn(theirsFrame, "TheirOfferGrid")

	-- Shard row. The stepper is bounded by what the player owns locally; the
	-- server clamps again on the way in and again at commit.
	local shardRow = UiKit.create("Frame", {
		Name = "ShardRow",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 284),
		Size = UDim2.fromOffset(COL_W, 36),
	}) :: Frame
	shardRow.Parent = area

	local myShards = UiKit.label(shardRow, {
		text = "SHARDS  0",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.quantum,
		align = Enum.TextXAlignment.Left,
	})
	myShards.Name = "MyShards"
	myShards.Position = UDim2.fromOffset(10, 0)
	myShards.Size = UDim2.fromOffset(COL_W - 190, 36)

	local stepper = UiKit.create("Frame", {
		Name = "ShardStepper",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 2),
		Size = UDim2.fromOffset(160, 32),
	}) :: Frame
	stepper.Parent = shardRow

	local function stepShards(delta: number)
		local stateNow = lastState
		local owned = if stateNow then tonumber(stateNow.shardsOwned) or 0 else 0
		local next = math.clamp(offerShards + delta, 0, math.floor(owned))
		if next == offerShards then
			return
		end
		offerShards = next
		pushOffer()
		Sfx.tab()
		if desk then
			desk.myShards.Text = string.format("SHARDS  %d", offerShards)
		end
		if lastState then
			paintFooter(lastState)
		end
	end

	local minus = UiKit.button(stepper, {
		text = "-" .. SHARD_STEP,
		fill = Theme.Color.slate,
		stroke = Theme.Color.stroke,
		height = 30,
		radius = Theme.Radius.sm,
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		textColor = Theme.Color.text,
		handler = function()
			stepShards(-SHARD_STEP)
		end,
	})
	minus.Name = "ShardsMinus"
	minus.Position = UDim2.fromOffset(0, 1)
	minus.Size = UDim2.fromOffset(74, 30)

	local plus = UiKit.button(stepper, {
		text = "+" .. SHARD_STEP,
		fill = Theme.Color.quantumDeep,
		stroke = Theme.Color.quantum,
		height = 30,
		radius = Theme.Radius.sm,
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		textColor = Theme.Color.text,
		handler = function()
			stepShards(SHARD_STEP)
		end,
	})
	plus.Name = "ShardsPlus"
	plus.Position = UDim2.fromOffset(82, 1)
	plus.Size = UDim2.fromOffset(74, 30)

	local theirShards = UiKit.label(area, {
		text = "THEY OFFER  0 SHARDS",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.cyan,
		align = Enum.TextXAlignment.Left,
	})
	theirShards.Name = "TheirShards"
	theirShards.Position = UDim2.fromOffset(COL_W + COL_GAP + 12, 284)
	theirShards.Size = UDim2.fromOffset(COL_W - 24, 36)

	local countLabel = UiKit.label(area, {
		text = "YOUR COPIES",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.textDim,
		align = Enum.TextXAlignment.Left,
	})
	countLabel.Name = "PickerHeading"
	countLabel.Position = UDim2.fromOffset(0, 324)
	countLabel.Size = UDim2.fromOffset(360, 18)

	local hint = UiKit.label(area, {
		text = "CLICK A CARD TO PUT IT ON THE TABLE",
		size = Theme.Text.Tiny,
		font = Theme.Font.Label,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Right,
	})
	hint.Name = "PickerHint"
	hint.AnchorPoint = Vector2.new(1, 0)
	hint.Position = UDim2.new(1, 0, 0, 324)
	hint.Size = UDim2.fromOffset(420, 18)

	local picker = UiKit.scroll(area, { thickness = 4 })
	picker.Name = "Picker"
	picker.Position = UDim2.fromOffset(0, 346)
	picker.Size = UDim2.new(1, 0, 0, 208)
	UiKit.grid(picker, UDim2.fromOffset(PICK_CARD_W, PICK_CARD_H), 8)
	-- No vertical padding: two 100px rows plus the 8px gap are exactly 208,
	-- and 4px of padding would clip the bottom row by a hairline.
	UiKit.padding(picker, 0, 4, 0)

	desk = {
		sessionKey = sessionKey,
		head = head,
		myCount = myCount,
		theirCount = theirCount,
		myGrid = myGrid,
		theirGrid = theirGrid,
		picker = picker,
		countLabel = countLabel,
		myShards = myShards,
		theirShards = theirShards,
		myStepper = stepper,
		timer = timer,
		cards = {},
	}
	lastInventorySignature = ""

	paintMyOffer()
	paintTheirOffer(state.theirBlades or {})
	lastTheirSignature = theirSignatureOf(state)
	buildPicker()
	paintSelection()
end

paintMyOffer = function()
	local d = desk
	if d == nil then
		return
	end
	ModalShell.clear(d.myGrid)
	releaseBucket(myStages)
	local rows: { any } = {}
	for _, uid in offerOrder do
		local entry = copyOf(uid)
		if entry then
			table.insert(rows, entry)
		end
	end
	for index, entry in rows do
		offerCard(d.myGrid, entry, true, index, Theme.Color.emerald, function()
			toggleOffer(tostring(entry.uid))
		end, myStages)
	end
	d.myCount.Text = string.format("%d / %d", #rows, MAX_BLADES)
end

paintTheirOffer = function(rows: { any })
	local d = desk
	if d == nil then
		return
	end
	ModalShell.clear(d.theirGrid)
	releaseBucket(theirStages)
	for index, entry in rows do
		offerCard(d.theirGrid, entry, false, index, Theme.Color.cyan, nil, theirStages)
	end
	d.theirCount.Text = string.format("%d / %d", #rows, MAX_BLADES)
	if #rows == 0 then
		local empty = UiKit.label(d.theirGrid, {
			text = "Nothing on the table yet.",
			size = Theme.Text.Tiny,
			font = Theme.Font.Label,
			color = Theme.Color.textFaint,
			align = Enum.TextXAlignment.Center,
		})
		empty.Size = UDim2.new(1, 0, 0, 40)
		empty.LayoutOrder = 1
	end
end

buildPicker = function()
	local d = desk
	if d == nil then
		return
	end
	local signature = inventorySignature()
	lastInventorySignature = signature
	ModalShell.clear(d.picker)

	local copies = tradeableCopies()
	if #copies == 0 then
		local empty = UiKit.label(d.picker, {
			text = "Every copy you own is equipped or favorited. Melt or forge something new.",
			size = Theme.Text.Tiny,
			font = Theme.Font.Label,
			color = Theme.Color.textFaint,
			align = Enum.TextXAlignment.Center,
			wrap = true,
		})
		empty.Size = UDim2.new(1, -20, 0, 54)
		empty.LayoutOrder = 1
		return
	end
	for index, entry in copies do
		pickerCard(d.picker, entry, index, function()
			toggleOffer(tostring(entry.uid))
		end)
	end
end

paintSelection = function()
	local d = desk
	if d == nil then
		return
	end
	local count = offerCount()

	for _, card in d.picker:GetChildren() do
		if card:IsA("GuiObject") and card:GetAttribute("Uid") ~= nil then
			local uid = tostring(card:GetAttribute("Uid"))
			local selected = offerUids[uid] == true
			for _, child in card:GetChildren() do
				if child.Name == "Tick" and child:IsA("GuiObject") then
					local mark = child:FindFirstChild("Mark")
					if mark and mark:IsA("TextLabel") then
						mark.TextTransparency = if selected then 0 else 1
					end
					child.BackgroundColor3 = if selected then Theme.Color.emeraldDeep else Theme.Color.panelSunken
					local stroke = child:FindFirstChildOfClass("UIStroke")
					if stroke then
						stroke.Color = if selected then Theme.Color.emerald else Theme.Color.stroke
					end
				end
			end
			local stroke = card:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if selected then Theme.Color.emerald else Theme.Color.strokeFaint
			end
		end
	end

	d.countLabel.Text = string.format("YOUR COPIES  (%d SELECTED)", count)
end

paintFooter = function(state: any)
	local bar = footer
	if bar == nil then
		return
	end
	ModalShell.clear(bar)

	local myAccepted = (acceptArmed and os.clock() - acceptAt < 3) or state.myAccepted == true
	local theirAccepted = state.theirAccepted == true
	local theirRows = state.theirBlades or {}
	local empty = offerCount() == 0
		and offerShards == 0
		and #theirRows == 0
		and (tonumber(state.theirShards) or 0) == 0

	local accept = UiKit.button(bar, {
		text = if myAccepted
			then "ACCEPTED"
			else if theirAccepted then "ACCEPT THE TRADE"
			else "ACCEPT",
		fill = if myAccepted or empty then Theme.Color.slate else Theme.Color.emeraldDeep,
		stroke = if myAccepted or empty then Theme.Color.outline else Theme.Color.emerald,
		height = 44,
		radius = Theme.Radius.sm,
		size = Theme.Text.Small,
		font = Theme.Font.Black,
		textColor = if myAccepted or empty then Theme.Color.locked else Theme.Color.text,
		handler = function()
			if myAccepted or empty then
				return
			end
			acceptArmed = true
			acceptAt = os.clock()
			Sfx.equip()
			StateStore.send("tradeAccept")
			if lastState then
				paintFooter(lastState)
			end
		end,
	})
	accept.Name = "TradeAccept"
	accept.Position = UDim2.fromOffset(0, 0)
	accept.Size = UDim2.fromOffset(320, 44)

	local withdraw = UiKit.button(bar, {
		text = "WITHDRAW",
		fill = Theme.Color.redDeep,
		stroke = Theme.Color.red,
		height = 44,
		radius = Theme.Radius.sm,
		size = Theme.Text.Small,
		font = Theme.Font.Black,
		textColor = Theme.Color.text,
		handler = function()
			StateStore.send("tradeDecline")
			offerUids = {}
			table.clear(offerOrder)
			offerShards = 0
			Sfx.close()
			lastState = nil
			TradeView.refresh()
		end,
	})
	withdraw.Name = "TradeWithdraw"
	withdraw.AnchorPoint = Vector2.new(1, 0)
	withdraw.Position = UDim2.fromScale(1, 0)
	withdraw.Size = UDim2.fromOffset(200, 44)

	if statusLine then
		statusLine.Text = if myAccepted
			then string.format("Locked in. Waiting on %s.", tostring(state.target))
			else if theirAccepted then string.format("%s has accepted. Your move.", tostring(state.target)) else "Both sides must accept. Any change resets both."
		statusLine.TextColor3 = if theirAccepted then Theme.Color.emerald else Theme.Color.textDim
	end
end

local function paintIdle()
	local area = deskArea
	if area == nil then
		return
	end
	if desk ~= nil then
		releaseStages()
		desk = nil
	end
	ModalShell.clear(area)

	local title = UiKit.label(area, {
		text = "NO TRADE OPEN",
		size = Theme.Text.Heading,
		font = Theme.Font.Black,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Center,
	})
	title.Position = UDim2.fromOffset(0, 72)
	title.Size = UDim2.new(1, 0, 0, 34)

	local hint = UiKit.label(area, {
		text = "Pick a forger on the left and press ASK. They have twenty seconds to accept.",
		size = Theme.Text.Small,
		font = Theme.Font.Body,
		color = Theme.Color.textDim,
		align = Enum.TextXAlignment.Center,
		wrap = true,
	})
	hint.Position = UDim2.fromOffset(40, 112)
	hint.Size = UDim2.new(1, -80, 0, 44)

	-- Three steps, drawn rather than listed. A player who has never traded needs
	-- the shape of the exchange before they need a paragraph about it.
	local steps = {
		{ "1", "ASK A FORGER", "A request lands on their screen. Nothing is on the table yet." },
		{ "2", "BUILD YOUR OFFER", "Tick copies below. Their screen updates as you do." },
		{ "3", "BOTH ACCEPT", "Any change clears both keys. Then the swap is atomic." },
	}
	for index, step in steps do
		local card = UiKit.panel(area, {
			tier = "well",
			radius = Theme.Radius.sm,
			stroke = Theme.Color.strokeFaint,
			bevel = false,
			lip = false,
		})
		card.Name = string.format("TradeStep_%d", index)
		card.Position = UDim2.fromOffset((index - 1) * 268, 190)
		card.Size = UDim2.fromOffset(256, 116)

		local dot = UiKit.create("Frame", {
			BackgroundColor3 = Theme.Color.emeraldDeep,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(12, 12),
			Size = UDim2.fromOffset(28, 28),
			ZIndex = 3,
		}) :: Frame
		UiKit.corner(dot, 14)
		UiKit.stroke(dot, Theme.Color.emerald, 2, 0)
		dot.Parent = card
		local number = UiKit.label(dot, {
			text = step[1],
			size = Theme.Text.Small,
			font = Theme.Font.Black,
			color = Theme.Color.text,
			align = Enum.TextXAlignment.Center,
			stroke = true,
		})
		number.Size = UDim2.fromScale(1, 1)
		number.ZIndex = 4

		local head = UiKit.label(card, {
			text = step[2],
			size = Theme.Text.Tiny,
			font = Theme.Font.Black,
			color = Theme.Color.emerald,
			align = Enum.TextXAlignment.Left,
		})
		head.Position = UDim2.fromOffset(48, 14)
		head.Size = UDim2.fromOffset(196, 20)

		local body = UiKit.label(card, {
			text = step[3],
			size = Theme.Text.Tiny,
			font = Theme.Font.Body,
			color = Theme.Color.textSecondary,
			align = Enum.TextXAlignment.Left,
			wrap = true,
		})
		body.Position = UDim2.fromOffset(12, 46)
		body.Size = UDim2.fromOffset(232, 58)
	end
end

-- ---------------------------------------------------------------------------
-- Partner rail
-- ---------------------------------------------------------------------------

local function partnerSignature(players: any): string
	if type(players) ~= "table" then
		return "none"
	end
	local parts = {}
	for _, row in players do
		parts[#parts + 1] = string.format(
			"%s:%s:%s:%s",
			tostring(row.id),
			tostring(row.name),
			tostring(row.trades),
			tostring(row.busy or row.pending)
		)
	end
	return table.concat(parts, "|")
end

local function playerRow(order: number, rowData: any)
	local id = tonumber(rowData.id) or 0
	local name = tostring(rowData.name or "?")
	local blades = tonumber(rowData.blades) or 0
	local open = rowData.trades ~= false
	local busy = rowData.busy == true or rowData.pending == true

	local row = UiKit.panel(partnerList :: ScrollingFrame, {
		tier = "well",
		radius = Theme.Radius.sm,
		stroke = Theme.Color.strokeFaint,
		bevel = false,
		lip = false,
	})
	row.Name = string.format("Partner_%d", id)
	row.Size = UDim2.new(1, -8, 0, 48)
	row.LayoutOrder = order

	local who = UiKit.label(row, {
		text = name,
		size = Theme.Text.Small,
		font = Theme.Font.Heading,
		color = if open then Theme.Color.text else Theme.Color.textFaint,
		align = Enum.TextXAlignment.Left,
	})
	who.Position = UDim2.fromOffset(10, 4)
	who.Size = UDim2.new(1, -96, 0, 20)
	who.TextTruncate = Enum.TextTruncate.AtEnd

	local sub = UiKit.label(row, {
		text = if not open then "TRADE REQUESTS OFF" else if busy then "BUSY" else string.format("%d BLADES", blades),
		size = Theme.Text.Tiny,
		font = Theme.Font.Label,
		color = if not open then Theme.Color.danger else if busy then Theme.Color.warn else Theme.Color.textFaint,
		align = Enum.TextXAlignment.Left,
	})
	sub.Name = "Sub"
	sub.Position = UDim2.fromOffset(10, 24)
	sub.Size = UDim2.new(1, -96, 0, 16)

	local ask = UiKit.button(row, {
		text = if not open then "OFF" else if busy then "WAIT" else "ASK",
		fill = if open and not busy then Theme.Color.emeraldDeep else Theme.Color.slate,
		stroke = if open and not busy then Theme.Color.emerald else Theme.Color.stroke,
		height = 30,
		radius = Theme.Radius.sm,
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		textColor = if open and not busy then Theme.Color.text else Theme.Color.locked,
		handler = function()
			if not open then
				Notifications.push(string.format("%s is unavailable for trade.", name), "warn")
				Sfx.error()
				return
			end
			if busy then
				Notifications.push(string.format("%s is already trading.", name), "warn")
				Sfx.error()
				return
			end
			StateStore.send("tradeRequest", { target = id })
			Notifications.push(string.format("Trade request sent to %s.", name), "info")
			Sfx.ui()
		end,
	})
	ask.Name = "Ask"
	ask.AnchorPoint = Vector2.new(1, 0.5)
	ask.Position = UDim2.new(1, -8, 0.5, 0)
	ask.Size = UDim2.fromOffset(70, 30)
end

local function paintPartners(players: any)
	local area = partnerList
	if area == nil then
		return
	end
	ModalShell.clear(area)
	if type(players) ~= "table" or #players == 0 then
		local empty = UiKit.label(area, {
			text = "Nobody else is at the forge.",
			size = Theme.Text.Tiny,
			font = Theme.Font.Label,
			color = Theme.Color.textFaint,
			align = Enum.TextXAlignment.Center,
			wrap = true,
		})
		empty.Size = UDim2.new(1, -8, 0, 60)
		empty.LayoutOrder = 1
		return
	end
	for index, rowData in players do
		playerRow(index, rowData)
	end
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------

function TradeView.paintState(state: any)
	if state == nil then
		paintIdle()
		if statusLine then
			statusLine.Text = ""
		end
		if footer then
			ModalShell.clear(footer)
		end
		return
	end

	if desk == nil or desk.sessionKey ~= tostring(state.targetId or state.target or "") then
		syncedFrom(state)
		buildDesk(state)
	elseif inventorySignature() ~= lastInventorySignature then
		buildPicker()
		paintSelection()
	end

	local d = desk
	if d ~= nil then
		d.myShards.Text = string.format("SHARDS  %d", offerShards)
		d.theirShards.Text = string.format("THEY OFFER  %d SHARDS", tonumber(state.theirShards) or 0)
		d.timer.Text = string.format("EXPIRES IN %ds", math.max(0, tonumber(state.expiresIn) or 0))
	end

	-- Their side repaints only when their side actually moved. Mine changes on
	-- every tick of a card, and rebuilding four turntables because I ticked a
	-- checkbox is exactly the kind of waste that shows up as a stutter.
	local theirSig = theirSignatureOf(state)
	if theirSig ~= lastTheirSignature then
		lastTheirSignature = theirSig
		paintTheirOffer(state.theirBlades or {})
	end
	paintFooter(state)
end

function TradeView.refresh()
	local handle = shell
	if handle == nil then
		return
	end

	local players = StateStore.request("players")
	paintPartners(players)
	lastPartnerSignature = partnerSignature(players)

	local state = StateStore.request("trade")
	lastState = state
	TradeView.paintState(state)
	lastSignature = signatureOf(state)
end

function TradeView.open()
	local handle = shell
	if handle == nil or handle.isOpen() then
		return
	end
	offerUids = {}
	table.clear(offerOrder)
	offerShards = 0
	acceptArmed = false
	lastState = nil
	lastSignature = ""
	lastTheirSignature = ""
	lastPartnerSignature = ""
	lastInventorySignature = ""
	handle.open()
	TradeView.refresh()
	pollClock = 0
	partnerClock = 0
end

function TradeView.close()
	if shell then
		shell.close()
	end
end

function TradeView.isOpen(): boolean
	return shell ~= nil and shell.isOpen()
end

--- Polls at 1Hz while open. The partner rail is slower: it is a player list, not
--- a live feed, and a RemoteFunction per second to redraw five names is waste.
function TradeView.step(dt: number)
	if shell == nil or not shell.isOpen() then
		return
	end
	pollClock += dt
	partnerClock += dt
	if partnerClock >= PARTNER_SECONDS then
		partnerClock = 0
		local players = StateStore.request("players")
		local signature = partnerSignature(players)
		if signature ~= lastPartnerSignature then
			lastPartnerSignature = signature
			paintPartners(players)
		end
	end
	if pollClock < POLL_SECONDS then
		return
	end
	pollClock = 0

	local state = StateStore.request("trade")
	lastState = state
	local signature = signatureOf(state)
	if signature ~= lastSignature then
		lastSignature = signature
		TradeView.paintState(state)
	end
end

--- Studio seam: paints a synthetic state from the real inventory so the desk can
--- be inspected without a second player. Never called outside the `QF_Dev`
--- handler, and it does not send a single verb.
function TradeView.preview()
	local inventory = StateStore.inventory
	if #inventory == 0 then
		return false
	end
	local rows = {}
	for index = 1, math.min(3, #inventory) do
		local entry = inventory[index]
		rows[#rows + 1] = {
			uid = tostring(entry.uid),
			id = tostring(entry.id),
			variant = tostring(entry.variant),
			element = tostring(entry.element or ""),
			grade = tostring(entry.grade or ""),
			prefix = tostring(entry.prefix or ""),
			suffix = tostring(entry.suffix or ""),
		}
	end
	local state = {
		target = "PREVIEW",
		targetId = 1,
		myBlades = rows,
		theirBlades = rows,
		myShards = 400,
		theirShards = 250,
		myAccepted = false,
		theirAccepted = true,
		shardsOwned = 2400,
		expiresIn = 187,
	}
	lastState = state
	TradeView.paintState(state)
	return true
end

function TradeView.init(canvas: Frame)
	if shell then
		return
	end

	local handle = ModalShell.build(canvas, {
		name = "TradeOverlay",
		title = "TRADE DESK",
		subtitle = "BLADES AND SHARDS, BOTH SIDES CONFIRMED",
		accent = Theme.Color.emerald,
		width = 1120,
		height = 700,
		-- A stray click in the dark must not cancel a half-built offer.
		lockScrim = true,
	}, 52)
	shell = handle

	partnerHeader = UiKit.label(handle.body, {
		text = "FORGERS ONLINE",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.emerald,
		align = Enum.TextXAlignment.Left,
	})
	partnerHeader.Name = "PartnerHeader"
	partnerHeader.Position = UDim2.fromOffset(16, 12)
	partnerHeader.Size = UDim2.fromOffset(RAIL_W - 8, 20)

	local area = UiKit.scroll(handle.body)
	area.Name = "PartnerList"
	area.Position = UDim2.fromOffset(16, 38)
	area.Size = UDim2.fromOffset(RAIL_W, 600)
	UiKit.vlist(area, { gap = 6, padding = 4 })
	partnerList = area

	local divider = UiKit.create("Frame", {
		Name = "Divider",
		BackgroundColor3 = Theme.Color.stroke,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(DIVIDER_X, 14),
		Size = UDim2.fromOffset(2, 636),
	}) :: Frame
	divider.Parent = handle.body

	local deskFrame = UiKit.create("Frame", {
		Name = "TradeDesk",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(DESK_X, 14),
		Size = UDim2.fromOffset(DESK_W, 620),
	}) :: Frame
	deskFrame.Parent = handle.body
	deskArea = deskFrame

	footer = UiKit.create("Frame", {
		Name = "TradeFooter",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -6),
		Size = UDim2.new(1, 0, 0, 44),
	}) :: Frame
	footer.Parent = handle.body

	statusLine = UiKit.label(handle.body, {
		text = "",
		size = Theme.Text.Tiny,
		font = Theme.Font.Label,
		color = Theme.Color.textDim,
		align = Enum.TextXAlignment.Left,
	})
	statusLine.Name = "TradeStatus"
	statusLine.AnchorPoint = Vector2.new(0, 1)
	statusLine.Position = UDim2.new(0, 16, 1, -68)
	statusLine.Size = UDim2.fromOffset(640, 16)

	paintIdle()
end

function TradeView.destroy()
	releaseStages()
	if shell then
		shell.destroy()
		shell = nil
	end
	partnerList = nil
	partnerHeader = nil
	deskArea = nil
	statusLine = nil
	footer = nil
	desk = nil
	lastState = nil
	offerUids = {}
	table.clear(offerOrder)
	offerShards = 0
end

return TradeView
