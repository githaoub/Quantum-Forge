--!strict
-- Prestige tech tree. The permanent layer: everything bought here survives
-- ascension, which is what makes spending Quantum Cores feel like investment
-- rather than upkeep.
--
-- Costs come from TechTreeConfig on both sides, so the button label and the
-- server's charge can never disagree.
--
-- Each node is a card with three anchors: a violet rarity bar on the left, a pip
-- bar showing level / maxLevel, and a solid purple action plate that turns slate
-- the moment the player cannot afford the next level.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local TechTreeConfig = require(Shared:WaitForChild("TechTreeConfig"))
local NumberUtil = require(Shared:WaitForChild("NumberUtil"))
local Types = require(Shared:WaitForChild("Types"))
local AssetManifest = require(Shared:WaitForChild("AssetManifest"))

local Theme = require(script.Parent.Theme)
local UiKit = require(script.Parent.UiKit)
local StateStore = require(script.Parent.StateStore)
local Sfx = require(script.Parent.Sfx)

local TechTreeView = {}

type NodeCard = {
	node: TechTreeConfig.Node,
	root: Frame,
	level: TextLabel,
	effect: TextLabel,
	handle: UiKit.ActionHandle,
	bar: UiKit.BarParts,
	lastKind: UiKit.ActionKind?,
	lastLabel: string?,
}

local cards: { NodeCard } = {}
local balance: TextLabel? = nil
local unsubscribe: (() -> ())? = nil

local function buildCard(parent: Instance, node: TechTreeConfig.Node, order: number): NodeCard
	local root = UiKit.panel(parent, {
		tier = "item",
		radius = Theme.Radius.md,
		stroke = Theme.Color.quantum,
		strokeTransparency = 0.8,
	})
	root.Size = UDim2.new(1, -4, 0, 132)
	root.LayoutOrder = order

	local stripe = UiKit.create("Frame", {
		BackgroundColor3 = Theme.Color.quantum,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 4, 1, -20),
		Position = UDim2.fromOffset(0, 10),
	}) :: Frame
	UiKit.corner(stripe, 2)
	stripe.Parent = root

	-- 80px badge. The card grew to 132 to hold it without shrinking the copy:
	-- name and description flow beside the art, then the effect line and the
	-- level pips keep their own rows underneath.
	local well = UiKit.badgeWell(root, {
		image = AssetManifest.uiArt(node.icon),
		size = 80,
		accent = Theme.Color.quantum,
	})
	if well ~= nil then
		well.Position = UDim2.fromOffset(12, 10)
	end

	local name = UiKit.label(root, {
		text = node.name,
		size = Theme.Text.Body,
		font = Theme.Font.Heading,
		color = Theme.Color.text,
	})
	name.Position = UDim2.fromOffset(104, 10)
	name.Size = UDim2.new(1, -226, 0, 24)

	local level = UiKit.label(root, {
		text = "Lv 0 / 0",
		size = Theme.Text.Micro,
		font = Theme.Font.Numeric,
		color = Theme.Color.quantum,
		align = Enum.TextXAlignment.Right,
	})
	level.Position = UDim2.new(1, -116, 0, 9)
	level.Size = UDim2.fromOffset(100, 18)

	local desc = UiKit.label(root, {
		text = node.description,
		size = Theme.Text.Micro,
		color = Theme.Color.textSecondary,
		wrap = true,
	})
	desc.Position = UDim2.fromOffset(104, 38)
	desc.Size = UDim2.new(1, -230, 0, 36)

	local effect = UiKit.label(root, {
		text = "",
		size = Theme.Text.Micro,
		font = Theme.Font.Numeric,
		color = Theme.Color.quantum,
	})
	effect.Position = UDim2.fromOffset(104, 76)
	effect.Size = UDim2.new(1, -230, 0, 18)

	-- Level pips. A bar reads faster than "Lv 3 / 10" at a glance, which is the
	-- point: the number is already on the card.
	local bar = UiKit.bar(root, {
		height = 4,
		radius = 2,
		gradient = { Theme.Color.quantumDeep, Theme.Color.quantum },
	})
	bar.track.Position = UDim2.fromOffset(104, 100)
	bar.track.Size = UDim2.new(1, -230, 0, 4)

	local handle = UiKit.actionButton(root, {
		accent = Theme.Color.quantum,
		height = 28,
		radius = Theme.Radius.sm,
		size = Theme.Text.Small,
		label = "BUY",
		handler = function()
			StateStore.send("buyTech", node.id)
			Sfx.tech()
		end,
	})
	local action = handle.button
	action.Name = string.format("TechBuy_%s", node.id)
	action.Position = UDim2.new(1, -114, 1, -44)
	action.Size = UDim2.fromOffset(102, 32)

	return {
		node = node,
		root = root,
		level = level,
		effect = effect,
		handle = handle,
		bar = bar,
		lastKind = nil,
		lastLabel = nil,
	}
end

function TechTreeView.init(parent: Instance)
	cards = {}

	local header = UiKit.panel(parent, {
		tier = "well",
		radius = Theme.Radius.md,
		stroke = Theme.Color.quantum,
		strokeTransparency = 0.6,
	})
	header.Size = UDim2.new(1, -4, 0, 64)
	header.LayoutOrder = 0

	local caption = UiKit.label(header, {
		text = "QUANTUM CORES",
		size = Theme.Text.Micro,
		font = Theme.Font.Heading,
		color = Theme.Color.textFaint,
	})
	caption.Position = UDim2.fromOffset(14, 7)
	caption.Size = UDim2.new(1, -28, 0, 18)

	balance = UiKit.label(header, {
		text = "0",
		size = Theme.Text.Title,
		font = Theme.Font.Display,
		color = Theme.Color.quantum,
	})
	balance.Position = UDim2.fromOffset(14, 24)
	balance.Size = UDim2.new(1, -28, 0, 34)

	for index, node in TechTreeConfig.list() do
		table.insert(cards, buildCard(parent, node, index))
	end

	unsubscribe = StateStore.onSync(function(payload: Types.SyncPayload)
		TechTreeView.render(payload)
	end)

	local current = StateStore.current
	if current then
		TechTreeView.render(current)
	end
end

function TechTreeView.render(payload: Types.SyncPayload)
	if balance then
		balance.Text = NumberUtil.abbreviate(payload.qc)
	end

	for _, card in cards do
		local level = payload.tech[card.node.id] or 0
		local maxed = level >= card.node.maxLevel
		local cost = TechTreeConfig.cost(card.node, level)
		local affordable = payload.qc >= cost and not maxed

		card.level.Text = string.format("Lv %d / %d", level, card.node.maxLevel)
		card.bar.set(level / math.max(1, card.node.maxLevel))

		if level > 0 then
			card.effect.Text = string.format("Current bonus: +%.0f%%", card.node.perLevel * level * 100)
			card.effect.TextColor3 = Theme.Color.quantum
		else
			card.effect.Text = string.format("Per level: +%.0f%%", card.node.perLevel * 100)
			card.effect.TextColor3 = Theme.Color.textFaint
		end

		local kind: UiKit.ActionKind
		local text: string
		if maxed then
			kind = "equipped"
			text = "MAXED"
		elseif affordable then
			kind = "ready"
			text = string.format("BUY  ·  %s", NumberUtil.abbreviate(cost))
		else
			kind = "locked"
			text = string.format("%s QC", NumberUtil.abbreviate(cost))
		end

		if kind ~= card.lastKind or text ~= card.lastLabel then
			card.lastKind = kind
			card.lastLabel = text
			card.handle.set(kind, text, Theme.Color.quantum)
		end

		card.root.BackgroundTransparency = if level > 0 then 0.02 else 0.06
	end
end

function TechTreeView.destroy()
	if unsubscribe then
		unsubscribe()
		unsubscribe = nil
	end
	cards = {}
end

return TechTreeView
