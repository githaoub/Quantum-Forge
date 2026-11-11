--!strict
-- Runes tab: blade mastery, the socket rack, and the shard shelf.
--
-- Three things happen here and they happen in order: strike with a blade to
-- raise its mastery, mastery unlocks sockets, sockets hold runes, and runes are
-- bought with Void Shards that only drop from a hot gauge. The panel is laid out
-- in that same order so the causal chain is readable without a tutorial.
--
-- Everything on this screen is derived from the payload. The client never
-- decides what a rune is worth, which slot is legal, or whether a craft can be
-- afforded; it renders the server's answer and sends intents.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BladeRegistry = require(Shared:WaitForChild("BladeRegistry"))
local NumberUtil = require(Shared:WaitForChild("NumberUtil"))
local RuneConfig = require(Shared:WaitForChild("RuneConfig"))
local Types = require(Shared:WaitForChild("Types"))
local AssetManifest = require(Shared:WaitForChild("AssetManifest"))

local Theme = require(script.Parent.Theme)
local UiKit = require(script.Parent.UiKit)
local StateStore = require(script.Parent.StateStore)
local Sfx = require(script.Parent.Sfx)

local RuneView = {}

-- Geometry is driven by the type scale, not the other way round. Every caption
-- here is `Theme.Text.Micro` (14) or `Theme.Text.Tiny` (13), so each block gets
-- a 20px band for a 14px line rather than the 14px band the old 10px labels
-- were given. Nothing on this screen drops below 13.
local MASTERY_H = 178
--- 104, not 78. The 88px rune badge is the point of the shelf now: it is the
--- only art on the row, and at 60px the disc was doing the job of a bullet
--- point. Three text lines plus 8px of air above and below is what the height
--- buys. The list already scrolls, so nothing below loses space to it.
local ROW_H = 104

local rankChip: TextLabel? = nil
local bladeName: TextLabel? = nil
local masteryBar: UiKit.BarParts? = nil
local masteryText: TextLabel? = nil
local socketNote: TextLabel? = nil
local socketButtons: { TextButton } = {}
local socketLabels: { TextLabel } = {}
local shardLabel: TextLabel? = nil
local runeRows: { [string]: { count: TextLabel, handle: UiKit.ActionHandle } } = {}
local unsubscribe: (() -> ())? = nil

local function hasFreeSocket(state: Types.SyncPayload): boolean
	for index = 1, state.socketSlots do
		if (state.equippedSockets[index] or "") == "" then
			return true
		end
	end
	return false
end

--- What the button on a rune row should do right now, and what it should say.
local function decisionFor(state: Types.SyncPayload, runeId: string, cost: number): (string, string, Color3)
	local owned = state.runes[runeId] or 0
	if owned > 0 and hasFreeSocket(state) then
		return "socket", "SOCKET", Theme.Color.quantum
	end
	if state.shards >= cost then
		return "craft", string.format("CRAFT %d", cost), Theme.Color.aether
	end
	return "locked", string.format("NEED %d", cost), Theme.Color.aether
end

local function buildMastery(parent: Instance)
	local card = UiKit.panel(parent, {
		tier = "raised",
		radius = Theme.Radius.card,
	})
	card.Name = "MasteryCard"
	card.Size = UDim2.new(1, -4, 0, MASTERY_H)
	card.LayoutOrder = 1

	bladeName = UiKit.label(card, {
		text = "BLADE",
		size = Theme.Text.Subheading,
		font = Theme.Font.Black,
		color = Theme.Color.starMatter,
	})
	bladeName.Position = UDim2.fromOffset(14, 8)
	bladeName.Size = UDim2.new(1, -134, 0, 26)

	rankChip = UiKit.label(card, {
		text = "RANK 0",
		size = 15,
		font = Theme.Font.Black,
		color = Theme.Color.gold,
		align = Enum.TextXAlignment.Right,
	})
	rankChip.Position = UDim2.new(1, -130, 0, 11)
	rankChip.Size = UDim2.fromOffset(116, 20)

	masteryBar = UiKit.bar(card, {
		height = 12,
		radius = 6,
		gradient = { Theme.Color.starMatterDeep, Theme.Color.starMatter },
	})
	masteryBar.track.Position = UDim2.fromOffset(14, 42)
	masteryBar.track.Size = UDim2.new(1, -28, 0, 12)

	masteryText = UiKit.label(card, {
		text = "",
		size = Theme.Text.Micro,
		font = Theme.Font.Numeric,
		color = Theme.Color.textSecondary,
	})
	masteryText.Position = UDim2.fromOffset(14, 58)
	masteryText.Size = UDim2.new(1, -28, 0, 18)

	socketNote = UiKit.label(card, {
		text = "SOCKETS",
		size = Theme.Text.Micro,
		font = Theme.Font.Black,
		color = Theme.Color.textSecondary,
	})
	socketNote.Position = UDim2.fromOffset(14, 84)
	socketNote.Size = UDim2.new(1, -28, 0, 18)

	local rack = UiKit.create("Frame", {
		Name = "SocketRack",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -28, 0, 52),
		Position = UDim2.fromOffset(14, 108),
	}) :: Frame
	rack.Parent = card

	for index = 1, RuneConfig.MaxSockets do
		local button = UiKit.create("TextButton", {
			Name = string.format("Socket%d", index),
			BackgroundColor3 = Theme.Color.panelSunken,
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			Size = UDim2.new(1 / 3, -8, 1, 0),
			Position = UDim2.new((index - 1) / 3, 4, 0, 0),
		}) :: TextButton
		UiKit.corner(button, Theme.Radius.sm)
		UiKit.stroke(button, Theme.Color.stroke, 2, 0.2)
		button.Parent = rack

		local label = UiKit.label(button, {
			text = "RANK " .. tostring(index),
			size = Theme.Text.Micro,
			font = Theme.Font.Black,
			color = Theme.Color.textSecondary,
			align = Enum.TextXAlignment.Center,
			wrap = true,
		})
		label.Size = UDim2.fromScale(1, 1)
		label.Position = UDim2.fromOffset(0, 0)

		button.Activated:Connect(function()
			StateStore.send("unsocket", { slot = index })
		end)

		socketButtons[index] = button
		socketLabels[index] = label
	end
end

local function buildShelf(parent: Instance)
	local head = UiKit.label(parent, {
		text = "RUNE SHELF",
		size = Theme.Text.Micro,
		font = Theme.Font.Black,
		color = Theme.Color.textSecondary,
	})
	head.Size = UDim2.new(1, -170, 0, 18)
	head.LayoutOrder = 2

	shardLabel = UiKit.label(parent, {
		text = "0 SHARDS",
		size = Theme.Text.Micro,
		font = Theme.Font.Numeric,
		color = Theme.Color.quantum,
		align = Enum.TextXAlignment.Right,
	})
	shardLabel.Size = UDim2.new(1, -4, 0, 18)
	shardLabel.LayoutOrder = 3

	local order = 4
	for _, rune in RuneConfig.list() do
		local row = UiKit.panel(parent, {
			tier = "item",
			radius = Theme.Radius.md,
		})
		row.Name = string.format("Rune_%s", rune.id)
		row.Size = UDim2.new(1, -4, 0, ROW_H)
		row.LayoutOrder = order
		order += 1

		local well = UiKit.badgeWell(row, {
			image = AssetManifest.uiArt(rune.icon),
			size = 88,
			accent = Theme.Color.quantum,
		})
		if well ~= nil then
			well.Position = UDim2.fromOffset(8, 8)
		end

		local name = UiKit.label(row, {
			text = rune.name,
			size = 17,
			font = Theme.Font.Black,
			color = Theme.Color.text,
		})
		name.Position = UDim2.fromOffset(108, 8)
		name.Size = UDim2.new(1, -238, 0, 24)

		local effect = UiKit.label(row, {
			text = rune.description,
			size = Theme.Text.Micro,
			color = Theme.Color.textSecondary,
		})
		effect.Position = UDim2.fromOffset(108, 34)
		effect.Size = UDim2.new(1, -238, 0, 20)

		local count = UiKit.label(row, {
			text = "0 OWNED",
			size = Theme.Text.Micro,
			font = Theme.Font.Numeric,
			color = Theme.Color.quantum,
		})
		count.Position = UDim2.fromOffset(108, 60)
		count.Size = UDim2.fromOffset(140, 18)

		local handle = UiKit.actionButton(row, {
			accent = Theme.Color.quantum,
			height = 36,
			radius = Theme.Radius.sm,
			size = 14,
			label = "CRAFT",
			handler = function()
				local state = StateStore.current
				if state == nil then
					return
				end
				local action = decisionFor(state, rune.id, rune.cost)
				if action == "socket" then
					StateStore.send("socket", { rune = rune.id })
					Sfx.rune()
				elseif action == "craft" then
					StateStore.send("craftRune", { id = rune.id })
					Sfx.rune()
				end
			end,
		})
		handle.button.Name = string.format("RuneAction_%s", rune.id)
		handle.button.Position = UDim2.new(1, -126, 0.5, -18)
		handle.button.Size = UDim2.fromOffset(114, 36)

		runeRows[rune.id] = { count = count, handle = handle }
	end
end

function RuneView.init(parent: Instance)
	buildMastery(parent)
	buildShelf(parent)

	unsubscribe = StateStore.onSync(function(payload: Types.SyncPayload)
		RuneView.render(payload)
	end)

	local current = StateStore.current
	if current then
		RuneView.render(current)
	end
end

function RuneView.render(payload: Types.SyncPayload)
	local blade = BladeRegistry.get(payload.equipped)

	if bladeName then
		bladeName.Text = if blade then string.upper(blade.name) else "UNKNOWN BLADE"
		bladeName.TextColor3 = Theme.rarityColor(if blade then blade.tier else 1)
	end

	if rankChip then
		rankChip.Text = string.format("RANK %d / %d", payload.mastery, #RuneConfig.Thresholds)
		rankChip.TextColor3 = if payload.mastery > 0 then Theme.Color.gold else Theme.Color.textFaint
	end

	if masteryBar and masteryText then
		local rank = payload.mastery
		local floorValue = if rank > 0 then RuneConfig.Thresholds[rank] else 0
		local ceiling = payload.masteryNext
		if ceiling == nil then
			masteryBar.set(1)
			masteryText.Text = string.format("%s STRIKES  ·  MASTERED", NumberUtil.abbreviate(payload.masteryXp))
		else
			local span = math.max(1, ceiling - floorValue)
			masteryBar.set(math.clamp((payload.masteryXp - floorValue) / span, 0, 1))
			masteryText.Text = string.format(
				"%s / %s STRIKES TO RANK %d",
				NumberUtil.abbreviate(payload.masteryXp),
				NumberUtil.abbreviate(ceiling),
				rank + 1
			)
		end
	end

	if socketNote then
		socketNote.Text = string.format("SOCKETS  %d OF %d UNLOCKED", payload.socketSlots, RuneConfig.MaxSockets)
	end

	for index, button in socketButtons do
		local label = socketLabels[index]
		local runeId = payload.equippedSockets[index] or ""
		local unlocked = index <= payload.socketSlots
		local rune = if unlocked and runeId ~= "" then RuneConfig.get(runeId) else nil

		if label then
			if rune then
				label.Text = string.upper(rune.name)
				label.TextColor3 = Theme.Color.white
			elseif unlocked then
				label.Text = "EMPTY\nADD RUNE"
				label.TextColor3 = Theme.Color.textSecondary
			else
				local needed = 0
				for rank = 1, #RuneConfig.Thresholds do
					if RuneConfig.socketsFor(rank) >= index and needed == 0 then
						needed = rank
					end
				end
				label.Text = string.format("RANK %d", needed)
				label.TextColor3 = Theme.Color.locked
			end
		end

		button.BackgroundColor3 = if rune then Theme.Color.quantumDeep else Theme.Color.panelSunken
		button.BackgroundTransparency = if rune then 0.05 else 0.35
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if rune then Theme.Color.quantum else Theme.Color.stroke
			stroke.Transparency = if rune then 0 else 0.4
		end
	end

	if shardLabel then
		shardLabel.Text = string.format("%d VOID SHARDS", payload.shards)
		shardLabel.TextColor3 = if payload.shards > 0 then Theme.Color.quantum else Theme.Color.textFaint
	end

	for _, rune in RuneConfig.list() do
		local row = runeRows[rune.id]
		if row then
			local owned = payload.runes[rune.id] or 0
			row.count.Text = string.format("%d OWNED", owned)
			row.count.TextColor3 = if owned > 0 then Theme.Color.quantum else Theme.Color.textFaint

			local action, text, accent = decisionFor(payload, rune.id, rune.cost)
			row.handle.set(
				if action == "locked" then "locked" else "ready",
				text,
				accent
			)
		end
	end
end

function RuneView.destroy()
	if unsubscribe then
		unsubscribe()
		unsubscribe = nil
	end
	rankChip = nil
	bladeName = nil
	masteryBar = nil
	masteryText = nil
	socketNote = nil
	shardLabel = nil
	table.clear(socketButtons)
	table.clear(socketLabels)
	table.clear(runeRows)
end

return RuneView
