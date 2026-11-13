--!strict
-- The player view: everyone in this server, and everything public about the one
-- you pick.
--
-- The list answer is small and refreshed every ten seconds. The card is a second
-- request because one player's vault can be sixty copies and four rune racks;
-- sending that for every row would make a panel that costs more the fuller the
-- server is. The server builds both answers from `DataManager` and never accepts
-- a stat from the client.
--
-- Selection never waits on the network. The row switches, a skeleton paints, and
-- the card fills when the answer lands. The old build re-requested the roster on
-- every click and refused the repaint while that request was in flight, which is
-- why the second player could not be opened.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BladeRegistry = require(Shared:WaitForChild("BladeRegistry"))
local ForgeConfig = require(Shared:WaitForChild("ForgeConfig"))
local ModifierConfig = require(Shared:WaitForChild("ModifierConfig"))
local NumberUtil = require(Shared:WaitForChild("NumberUtil"))
local RuneConfig = require(Shared:WaitForChild("RuneConfig"))
local TechTreeConfig = require(Shared:WaitForChild("TechTreeConfig"))

local Theme = require(script.Parent.Theme)
local UiKit = require(script.Parent.UiKit)
local Icons = require(script.Parent.Icons)
local ModalShell = require(script.Parent.ModalShell)
local BladePreview = require(script.Parent.BladePreview)
local StateStore = require(script.Parent.StateStore)
local Sfx = require(script.Parent.Sfx)

local PlayersView = {}

local REFRESH_SECONDS = 10
local ROW_H = 58
local LIST_W = 250
local DETAIL_X = 282
local BODY_W = 818
local CARD_H = 430
local BLADE_CARD_W = 150
local BLADE_CARD_H = 88

local shell: ModalShell.Handle? = nil
local listHost: ScrollingFrame? = nil
local detailHost: ScrollingFrame? = nil
local selectedUserId = 0
local rosterData: any = nil
local rosterSignature = ""
local detailToken = 0
local detailUserId = 0
local detailLoaded = false
local detailPending = false
local loading = false
local bladeCleanup: (() -> ())? = nil
local cheerUserId = 0
local cheerUntil = 0
local refreshClock = 0

-- ---------------------------------------------------------------------------
-- Small pieces
-- ---------------------------------------------------------------------------

local function clearStage()
	if bladeCleanup then
		bladeCleanup()
		bladeCleanup = nil
	end
end

local function avatar(parent: GuiObject, x: number, y: number, size: number, userId: number, name: string)
	local plate = UiKit.create("Frame", {
		Name = "Avatar",
		BackgroundColor3 = Theme.Color.slate,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(size, size),
		ZIndex = 2,
	}) :: Frame
	UiKit.corner(plate, size / 2)
	UiKit.stroke(plate, Theme.Color.stroke, Theme.Stroke.thin, 0.2)
	plate.Parent = parent

	local initial = string.upper(string.sub(name, 1, 1))
	local fallback = UiKit.label(plate, {
		text = if initial ~= "" then initial else "?",
		size = math.max(Theme.Text.Small, math.floor(size * 0.4)),
		font = Theme.Font.Black,
		color = Theme.Color.textSecondary,
		align = Enum.TextXAlignment.Center,
	})
	fallback.Size = UDim2.fromScale(1, 1)
	fallback.ZIndex = 3

	task.spawn(function()
		local ok, url = pcall(function()
			return Players:GetUserThumbnailAsync(
				userId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size100x100
			)
		end)
		if not ok or type(url) ~= "string" or url == "" or not plate.Parent then
			return
		end
		local image = UiKit.create("ImageLabel", {
			Name = "Head",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			Image = url,
			ScaleType = Enum.ScaleType.Crop,
			ZIndex = 4,
		}) :: ImageLabel
		UiKit.corner(image, size / 2)
		image.Parent = plate
	end)
end

local function sectionTitle(parent: Instance, x: number, y: number, text: string): TextLabel
	local label = UiKit.label(parent, {
		text = text,
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.textDim,
		align = Enum.TextXAlignment.Left,
	})
	label.Position = UDim2.fromOffset(x, y)
	label.Size = UDim2.new(1, -x - 2, 0, 16)
	return label
end

local function statCell(parent: Frame, x: number, y: number, label: string?, value: string, accent: Color3, kind: string?)
	if label ~= nil then
		local caption = UiKit.label(parent, {
			text = label,
			size = Theme.Text.Tiny,
			font = Theme.Font.Black,
			color = Theme.Color.textFaint,
			align = Enum.TextXAlignment.Left,
		})
		caption.Position = UDim2.fromOffset(x, y)
		caption.Size = UDim2.fromOffset(150, 15)
	end
	if kind then
		-- The three wallet cells carry the same mark as the top bar instead of
		-- a caption. The icon sits in a holder so its 24px canvas scales about
		-- the cell's corner rather than overflowing it.
		local holder = UiKit.create("Frame", {
			Name = "Mark",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(16, 16),
		}) :: Frame
		holder.Parent = parent
		local mark = Icons.currency(holder, kind, 16, accent)
		mark.AnchorPoint = Vector2.new(0.5, 0.5)
		mark.Position = UDim2.fromScale(0.5, 0.5)
	end

	local figure = UiKit.label(parent, {
		text = value,
		size = Theme.Text.Subheading,
		font = Theme.Font.Numeric,
		color = accent,
		align = Enum.TextXAlignment.Left,
	})
	figure.Position = UDim2.fromOffset(x, y + 19)
	figure.Size = UDim2.fromOffset(156, 23)
	figure.Name = label or string.format("Currency_%s", kind or "value")
end

--- A quiet chip for a rune or a tech node. The name is the information; the tint
--- is the category.
local function chip(parent: Instance, x: number, y: number, text: string, tint: Color3): Frame
	local frame = UiKit.panel(parent, {
		tier = "well",
		radius = Theme.Radius.sm,
		stroke = tint,
		bevel = false,
		lip = false,
	})
	frame.Size = UDim2.fromOffset(0, 24)
	frame.AutomaticSize = Enum.AutomaticSize.X
	frame.Position = UDim2.fromOffset(x, y)

	local label = UiKit.label(frame, {
		text = text,
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.textSecondary,
		align = Enum.TextXAlignment.Left,
	})
	label.Position = UDim2.fromOffset(8, 0)
	label.Size = UDim2.fromScale(0, 1)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.TextTruncate = Enum.TextTruncate.AtEnd
	return frame
end

-- ---------------------------------------------------------------------------
-- Roster list
-- ---------------------------------------------------------------------------

local function rosterIndex(): (number, number)
	if type(rosterData) ~= "table" or type(rosterData.players) ~= "table" then
		return 0, 0
	end
	for index, entry in rosterData.players do
		if entry.userId == selectedUserId then
			return index, #rosterData.players
		end
	end
	return 0, #rosterData.players
end

local function paintList()
	local host = listHost
	if host == nil then
		return
	end
	ModalShell.clear(host)
	if type(rosterData) ~= "table" or type(rosterData.players) ~= "table" then
		for index = 1, 5 do
			local skeleton = UiKit.create("Frame", {
				Name = string.format("RosterSkeleton_%d", index),
				BackgroundColor3 = Theme.Color.panel,
				BorderSizePixel = 0,
				Size = UDim2.new(1, -8, 0, ROW_H),
				LayoutOrder = index,
				ZIndex = 2,
			}) :: Frame
			UiKit.corner(skeleton, Theme.Radius.sm)
			UiKit.stroke(skeleton, Theme.Color.strokeFaint, Theme.Stroke.thin, 0.4)
			skeleton.Parent = host
		end
		return
	end

	for order, entry in rosterData.players do
		local selected = entry.userId == selectedUserId
		local you = entry.userId == rosterData.you
		local row = UiKit.create("TextButton", {
			Name = string.format("PlayerRow_%d", entry.userId),
			BackgroundColor3 = if selected then Theme.Color.panelRaised else Theme.Color.panel,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			Size = UDim2.new(1, -8, 0, ROW_H),
			LayoutOrder = order,
			ZIndex = 2,
		}) :: TextButton
		UiKit.corner(row, Theme.Radius.sm)
		UiKit.stroke(row, if selected then Theme.Color.cyan else Theme.Color.strokeFaint, Theme.Stroke.thin, if selected then 0 else 0.45)
		row.Parent = host

		avatar(row, 8, 9, 40, entry.userId, tostring(entry.name or "?"))

		local name = UiKit.label(row, {
			text = tostring(entry.name or "?"),
			size = Theme.Text.Small,
			font = Theme.Font.Heading,
			color = if selected then Theme.Color.text else Theme.Color.textSecondary,
			align = Enum.TextXAlignment.Left,
		})
		name.Position = UDim2.fromOffset(56, 8)
		name.Size = UDim2.new(1, -112, 0, 20)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.ZIndex = 3

		local score = UiKit.currencyRow(row, {
			kind = "sm",
			text = NumberUtil.compact(tonumber(entry.lifetimeSm) or 0),
			iconSize = 16,
			textSize = Theme.Text.Tiny,
			color = if selected then Theme.Color.cyan else Theme.Color.textFaint,
			height = 17,
			gap = 3,
		})
		score.root.Position = UDim2.fromOffset(56, 30)
		score.root.ZIndex = 3

		if you then
			local tag = UiKit.badge(row, {
				text = "YOU",
				color = Theme.Color.cyan,
				width = 40,
				height = 18,
				size = Theme.Text.Tiny,
				textColor = Theme.Color.ink,
			})
			tag.Name = "YouTag"
			tag.AnchorPoint = Vector2.new(1, 0)
			tag.Position = UDim2.new(1, -8, 0, 8)
			tag.ZIndex = 3
		end

		local place = UiKit.label(row, {
			text = tostring(order),
			size = Theme.Text.Tiny,
			font = Theme.Font.Black,
			color = if order <= 3 then Theme.Color.gold else Theme.Color.textDim,
			align = Enum.TextXAlignment.Right,
		})
		place.AnchorPoint = Vector2.new(1, 1)
		place.Position = UDim2.new(1, -8, 1, -5)
		place.Size = UDim2.fromOffset(26, 17)
		place.ZIndex = 3

		row.Activated:Connect(function()
			PlayersView.select(entry.userId)
		end)
		row.MouseEnter:Connect(function()
			Sfx.hover()
		end)
	end
end

local function rosterSig(data: any): string
	if type(data) ~= "table" or type(data.players) ~= "table" then
		return "none"
	end
	local parts = {}
	for _, entry in data.players do
		parts[#parts + 1] = string.format(
			"%d:%s:%s",
			entry.userId,
			tostring(entry.name),
			tostring(entry.lifetimeSm)
		)
	end
	return table.concat(parts, "|")
end

-- ---------------------------------------------------------------------------
-- Profile card
-- ---------------------------------------------------------------------------

local function paintLoading()
	local host = detailHost
	if host == nil then
		return
	end
	detailLoaded = false
	clearStage()
	ModalShell.clear(host)

	local header = UiKit.create("Frame", {
		Name = "DetailSkeleton",
		BackgroundColor3 = Theme.Color.panel,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(BODY_W, 80),
		ZIndex = 1,
	}) :: Frame
	UiKit.corner(header, Theme.Radius.md)
	UiKit.stroke(header, Theme.Color.strokeFaint, Theme.Stroke.thin, 0.4)
	header.Parent = host

	for index, spec in { { 0, 14, 220 }, { 0, 42, 140 }, { 0, 64, 90 } } do
		local bar = UiKit.create("Frame", {
			Name = string.format("Bar_%d", index),
			BackgroundColor3 = Theme.Color.panelRaised,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(86, spec[2]),
			Size = UDim2.fromOffset(spec[3], if index == 1 then 20 else 12),
			ZIndex = 2,
		}) :: Frame
		UiKit.corner(bar, 4)
		bar.Parent = header
	end

	for index = 1, 2 do
		local block = UiKit.create("Frame", {
			Name = string.format("Block_%d", index),
			BackgroundColor3 = Theme.Color.panel,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(if index == 1 then 0 else 316, 86),
			Size = UDim2.fromOffset(if index == 1 then 300 else BODY_W - 316, CARD_H),
			ZIndex = 1,
		}) :: Frame
		UiKit.corner(block, Theme.Radius.md)
		UiKit.stroke(block, Theme.Color.strokeFaint, Theme.Stroke.thin, 0.4)
		block.Parent = host
	end
end

local function bladeCard(parent: Instance, blade: any, order: number)
	local uid = tostring(blade.uid or "")
	local variant = ForgeConfig.variant(tostring(blade.variant or ForgeConfig.StandardVariant))
	local bladeData = BladeRegistry.get(tostring(blade.id or ""))
	local grade = tostring(blade.grade or "")
	local element = tostring(blade.element or "")
	local prefix = tostring(blade.prefix or "")
	local suffix = tostring(blade.suffix or "")

	local card = UiKit.panel(parent, {
		tier = if blade.equipped then "raised" else "well",
		radius = Theme.Radius.sm,
		stroke = if blade.equipped then Theme.Color.gold else Theme.Color.strokeFaint,
		bevel = false,
		lip = false,
	})
	card.Name = if blade.equipped then "EquippedBlade" else string.format("Blade_%s_%d", uid, order)
	card.Size = UDim2.fromOffset(BLADE_CARD_W, BLADE_CARD_H)
	card.LayoutOrder = order

	local bar = UiKit.create("Frame", {
		BackgroundColor3 = variant.color,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 4),
		ZIndex = 2,
	}) :: Frame
	UiKit.corner(bar, 2)
	bar.Parent = card

	local nameText = if bladeData
		then ModifierConfig.displayName(bladeData.name, prefix, suffix)
		else tostring(blade.id)
	local name = UiKit.label(card, {
		text = nameText,
		size = Theme.Text.Tiny,
		font = Theme.Font.Heading,
		color = Theme.Color.text,
		align = Enum.TextXAlignment.Left,
	})
	name.Position = UDim2.fromOffset(8, 8)
	name.Size = UDim2.new(1, -16, 0, 17)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.ZIndex = 3

	local power = UiKit.label(card, {
		text = NumberUtil.abbreviateMultiplier(tonumber(blade.power) or 1),
		size = Theme.Text.Subheading,
		font = Theme.Font.Numeric,
		color = variant.color,
		align = Enum.TextXAlignment.Left,
	})
	power.Position = UDim2.fromOffset(8, 27)
	power.Size = UDim2.new(1, -16, 0, 23)
	power.ZIndex = 3

	local condition = UiKit.label(card, {
		text = ModifierConfig.condition(grade, element),
		size = Theme.Text.Tiny,
		font = Theme.Font.Label,
		color = Theme.Color.textSecondary,
		align = Enum.TextXAlignment.Left,
	})
	condition.Position = UDim2.fromOffset(8, 52)
	condition.Size = UDim2.new(1, -16, 0, 15)
	condition.TextTruncate = Enum.TextTruncate.AtEnd
	condition.ZIndex = 3

	local footer = UiKit.label(card, {
		text = string.upper(variant.name),
		size = Theme.Text.Tiny,
		font = Theme.Font.Label,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Left,
	})
	footer.Position = UDim2.fromOffset(8, 68)
	footer.Size = UDim2.new(1, -16, 0, 14)
	footer.TextTruncate = Enum.TextTruncate.AtEnd
	footer.ZIndex = 3

	if blade.equipped then
		local tag = UiKit.badge(card, {
			text = "WORN",
			color = Theme.Color.gold,
			width = 42,
			height = 14,
			size = Theme.Text.Tiny,
			textColor = Theme.Color.ink,
		})
		tag.Name = "WornTag"
		tag.AnchorPoint = Vector2.new(1, 0)
		tag.Position = UDim2.new(1, -6, 0, 8)
		tag.ZIndex = 4
	end
end

local function paintDetail(data: any)
	local host = detailHost
	if host == nil then
		return
	end
	detailLoaded = true
	detailPending = false
	detailUserId = tonumber(data.userId) or 0
	clearStage()
	ModalShell.clear(host)

	local rank, total = rosterIndex()
	local you = type(rosterData) == "table" and data.userId == rosterData.you
	local blades = if type(data.blades) == "table" then data.blades else {}
	local best = blades[1]
	local bestBlade = if best ~= nil then BladeRegistry.get(tostring(best.id)) else nil
	local bestVariant = if best ~= nil then ForgeConfig.variant(tostring(best.variant)) else nil
	local accent = if bestVariant ~= nil then bestVariant.color else Theme.Color.cyan

	-- Header -----------------------------------------------------------------
	local header = UiKit.panel(host, {
		tier = "shell",
		radius = Theme.Radius.md,
		stroke = Theme.Color.strokeFaint,
	})
	header.Name = "ProfileHeader"
	header.Position = UDim2.fromOffset(0, 0)
	header.Size = UDim2.fromOffset(BODY_W, 80)
	header.ZIndex = 1

	avatar(header, 12, 12, 56, data.userId, tostring(data.name or "?"))

	local name = UiKit.label(header, {
		text = tostring(data.name or "?"),
		size = 28,
		font = Theme.Font.Black,
		color = Theme.Color.text,
		align = Enum.TextXAlignment.Left,
	})
	name.Position = UDim2.fromOffset(80, 6)
	name.Size = UDim2.new(1, -420, 0, 34)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.ZIndex = 3

	local handle = UiKit.label(header, {
		text = "@" .. tostring(data.handle or ""),
		size = Theme.Text.Tiny,
		font = Theme.Font.Label,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Left,
	})
	handle.Position = UDim2.fromOffset(80, 40)
	handle.Size = UDim2.fromOffset(240, 16)
	handle.ZIndex = 3

	local rankChip = UiKit.badge(header, {
		text = string.format("#%d OF %d", rank, math.max(1, total)),
		color = if you then Theme.Color.cyan else Theme.Color.gold,
		width = 104,
		height = 20,
		size = Theme.Text.Tiny,
		textColor = Theme.Color.ink,
	})
	rankChip.Position = UDim2.fromOffset(80, 58)
	rankChip.ZIndex = 3

	local playtime = UiKit.label(header, {
		text = string.format("PLAYED %s", NumberUtil.abbreviateTime(tonumber(data.playtime) or 0)),
		size = Theme.Text.Tiny,
		font = Theme.Font.Label,
		color = Theme.Color.textDim,
		align = Enum.TextXAlignment.Right,
	})
	playtime.AnchorPoint = Vector2.new(1, 0)
	playtime.Position = UDim2.new(1, -16, 0, 8)
	playtime.Size = UDim2.fromOffset(220, 16)
	playtime.ZIndex = 3

	if not you then
		local cheer = UiKit.button(header, {
			text = if cheerUserId == data.userId and os.clock() < cheerUntil then "CHEERED" else "CHEER",
			height = 34,
			radius = Theme.Radius.sm,
			size = Theme.Text.Small,
			font = Theme.Font.Black,
			textColor = Theme.Color.ink,
			fill = Theme.Color.cyan,
			stroke = Theme.Color.outline,
			handler = function()
				if cheerUserId == data.userId and os.clock() < cheerUntil then
					return
				end
				cheerUserId = data.userId
				cheerUntil = os.clock() + 3
				StateStore.send("cheer", data.userId)
				Sfx.ui()
				paintDetail(data)
			end,
		})
		cheer.Name = "CheerButton"
		cheer.AnchorPoint = Vector2.new(1, 0)
		cheer.Position = UDim2.new(1, -16, 0, 30)
		cheer.Size = UDim2.fromOffset(140, 34)
		cheer.ZIndex = 3
	end

	-- Best blade -------------------------------------------------------------
	local card = UiKit.panel(host, {
		tier = "well",
		radius = Theme.Radius.md,
		stroke = accent,
	})
	card.Name = "BestBladeCard"
	card.Position = UDim2.fromOffset(0, 86)
	card.Size = UDim2.fromOffset(300, CARD_H)
	card.ZIndex = 1

	local stage = UiKit.create("ViewportFrame", {
		Name = "BestBladeStage",
		BackgroundColor3 = Theme.Color.void,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(284, 240),
		ZIndex = 2,
	}) :: ViewportFrame
	UiKit.corner(stage, Theme.Radius.sm)
	UiKit.stroke(stage, Theme.Color.strokeFaint, Theme.Stroke.thin, 0.3)
	stage.Parent = card

	if bestBlade ~= nil then
		bladeCleanup = BladePreview.mount(stage, bestBlade, accent, {
			frameFill = 0.8,
			aimBias = 0,
			spin = 0.8,
			surface = stage,
		})
	else
		local none = UiKit.label(stage, {
			text = "NO BLADE",
			size = Theme.Text.Tiny,
			font = Theme.Font.Black,
			color = Theme.Color.textFaint,
			align = Enum.TextXAlignment.Center,
		})
		none.Size = UDim2.fromScale(1, 1)
	end

	local bestName = UiKit.label(card, {
		text = if bestBlade ~= nil
			then ModifierConfig.displayName(
				bestBlade.name,
				tostring(best.prefix or ""),
				tostring(best.suffix or "")
			)
			else "NO BLADE",
		size = Theme.Text.Small,
		font = Theme.Font.Black,
		color = Theme.Color.text,
		align = Enum.TextXAlignment.Center,
	})
	bestName.Position = UDim2.fromOffset(8, 254)
	bestName.Size = UDim2.new(1, -16, 0, 18)
	bestName.TextTruncate = Enum.TextTruncate.AtEnd
	bestName.ZIndex = 3

	local condition = UiKit.label(card, {
		text = if bestVariant ~= nil
			then string.format(
				"%s  ·  %s",
				string.upper(bestVariant.name),
				ModifierConfig.condition(tostring(best.grade or ""), tostring(best.element or ""))
			)
			else "",
		size = Theme.Text.Tiny,
		font = Theme.Font.Label,
		color = Theme.Color.textSecondary,
		align = Enum.TextXAlignment.Center,
	})
	condition.Position = UDim2.fromOffset(8, 274)
	condition.Size = UDim2.new(1, -16, 0, 15)
	condition.ZIndex = 3

	local power = UiKit.label(card, {
		text = if best ~= nil then NumberUtil.abbreviateMultiplier(tonumber(best.power) or 1) else "",
		size = 30,
		font = Theme.Font.Numeric,
		color = accent,
		align = Enum.TextXAlignment.Center,
	})
	power.Position = UDim2.fromOffset(8, 292)
	power.Size = UDim2.new(1, -16, 0, 34)
	power.ZIndex = 3

	local mastery = if best ~= nil then RuneConfig.masteryRank(tonumber(best.mastery) or 0) else 0
	local socketCount = if best ~= nil then RuneConfig.socketsFor(mastery) else 0
	local filled = if best ~= nil and type(best.sockets) == "table" then #best.sockets else 0
	local meta = UiKit.label(card, {
		text = string.format("MASTERY %d  ·  SOCKETS %d / %d", mastery, filled, socketCount),
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.textDim,
		align = Enum.TextXAlignment.Center,
	})
	meta.Position = UDim2.fromOffset(8, 332)
	meta.Size = UDim2.new(1, -16, 0, 15)
	meta.ZIndex = 3

	local runeY = 354
	if best ~= nil and type(best.sockets) == "table" and #best.sockets > 0 then
		for index, runeId in best.sockets do
			if runeId ~= "" then
				local rune = RuneConfig.get(tostring(runeId))
				local label = UiKit.label(card, {
					text = if rune ~= nil then string.upper(rune.name) else tostring(runeId),
					size = Theme.Text.Tiny,
					font = Theme.Font.Black,
					color = if rune ~= nil then rune.color else Theme.Color.textSecondary,
					align = Enum.TextXAlignment.Center,
				})
				label.Position = UDim2.fromOffset(8, runeY + (index - 1) * 17)
				label.Size = UDim2.new(1, -16, 0, 15)
				label.ZIndex = 3
			end
		end
	end

	-- Stats ------------------------------------------------------------------
	local stats = UiKit.create("Frame", {
		Name = "StatBlock",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(316, 86),
		Size = UDim2.fromOffset(BODY_W - 316, 279),
		ZIndex = 1,
	}) :: Frame
	stats.Parent = host

	local function cell(column: number, row: number, label: string?, value: string, colour: Color3, kind: string?)
		statCell(stats, column * 164, row * 55, label, value, colour, kind)
	end
	cell(0, 0, nil, NumberUtil.compact(tonumber(data.sm) or 0), Theme.Color.starMatter, "sm")
	cell(1, 0, "LIFETIME", NumberUtil.compact(tonumber(data.lifetimeSm) or 0), Theme.Color.gold)
	cell(2, 0, nil, NumberUtil.compact(tonumber(data.aether) or 0), Theme.Color.aether, "as")
	cell(0, 1, nil, NumberUtil.compact(tonumber(data.cores) or 0), Theme.Color.quantum, "qc")
	cell(1, 1, "SHARDS", NumberUtil.compact(tonumber(data.shards) or 0), Theme.Color.magenta)
	cell(2, 1, "SCRAP", NumberUtil.compact(tonumber(data.scrap) or 0), Theme.Color.textSecondary)
	cell(0, 2, "DRONES", NumberUtil.compact(tonumber(data.drones) or 0), Theme.Color.cyan)
	cell(1, 2, "ASCENSIONS", NumberUtil.compact(tonumber(data.ascensions) or 0), Theme.Color.quantum)
	cell(2, 2, "COPIES", string.format("%d / %d", tonumber(data.copies) or 0, tonumber(data.invMax) or 60), Theme.Color.textSecondary)
	cell(0, 3, "CODEX", tostring(tonumber(data.codexCount) or 0), Theme.Color.emerald)
	cell(1, 3, "RUNES", tostring(#(data.runes or {})), Theme.Color.emerald)
	local techLevels = 0
	for _, level in data.tech or {} do
		techLevels += tonumber(level) or 0
	end
	cell(2, 3, "TECH", tostring(techLevels), Theme.Color.emerald)
	cell(0, 4, "DAILY STREAK", string.format("DAY %d", tonumber(data.dailyStreak) or 0), Theme.Color.gold)
	local expedition = tostring(data.expedition or "")
	cell(1, 4, "EXPEDITION", if expedition ~= "" then "OUT" else "IDLE", Theme.Color.cyan)
	cell(2, 4, "SIGILS", tostring(tonumber(data.sigilCount) or 0), Theme.Color.quantum)

	-- Rune shelf -------------------------------------------------------------
	sectionTitle(host, 316, 375, "RUNES OWNED")
	local runeX = 316
	local runeRow = 0
	for _, runeRowData in data.runes or {} do
		local rune = RuneConfig.get(tostring(runeRowData.id))
		if rune ~= nil then
			local label = string.format("%s  x%d", string.upper(rune.name), tonumber(runeRowData.count) or 0)
			local chipFrame = chip(host, runeX, 395 + runeRow * 28, label, rune.color)
			local width = math.max(70, 8 + string.len(label) * 8)
			chipFrame.Size = UDim2.fromOffset(width, 24)
			runeX += width + 8
			if runeX > BODY_W - 100 then
				runeX = 316
				runeRow += 1
			end
		end
	end
	if #(data.runes or {}) == 0 then
		local none = UiKit.label(host, {
			text = "NONE",
			size = Theme.Text.Tiny,
			font = Theme.Font.Numeric,
			color = Theme.Color.textFaint,
			align = Enum.TextXAlignment.Left,
		})
		none.Position = UDim2.fromOffset(316, 395)
		none.Size = UDim2.fromOffset(200, 20)
	end

	-- Tech ladder ------------------------------------------------------------
	local techTitleY = 407 + (runeRow + 1) * 28
	sectionTitle(host, 316, techTitleY, "TECH")
	local techX = 316
	local techRow = 0
	for _, node in TechTreeConfig.list() do
		local level = tonumber((data.tech or {})[node.id]) or 0
		if level > 0 then
			local label = string.format("%s  %d", string.upper(node.name), level)
			local chipFrame = chip(host, techX, techTitleY + 20 + techRow * 28, label, Theme.Color.emerald)
			local width = math.max(80, 8 + string.len(label) * 8)
			chipFrame.Size = UDim2.fromOffset(width, 24)
			techX += width + 8
			if techX > BODY_W - 100 then
				techX = 316
				techRow += 1
			end
		end
	end
	if techRow == 0 then
		local none = UiKit.label(host, {
			text = "NONE",
			size = Theme.Text.Tiny,
			font = Theme.Font.Numeric,
			color = Theme.Color.textFaint,
			align = Enum.TextXAlignment.Left,
		})
		none.Position = UDim2.fromOffset(316, techTitleY + 20)
		none.Size = UDim2.fromOffset(200, 20)
	end

	-- All blades -------------------------------------------------------------
	-- 150, not 110: the blade card carries a bevel lip and a socket line under
	-- its 430px body, and a title at +110 landed on the card's bottom edge.
	local gridY = math.max(CARD_H + 150, techTitleY + 44 + techRow * 28)
	sectionTitle(host, 0, gridY, string.format("ALL BLADES  ·  %d", #blades))
	local grid = UiKit.create("Frame", {
		Name = "BladeGrid",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, gridY + 22),
		Size = UDim2.fromScale(1, 0),
		ZIndex = 1,
	}) :: Frame
	grid.Parent = host
	UiKit.grid(grid, UDim2.fromOffset(BLADE_CARD_W, BLADE_CARD_H), 8)
	for index, blade in blades do
		bladeCard(grid, blade, index)
	end
	-- The scroll canvas has to know how tall the grid grew. AutomaticSize on the
	-- grid plus the host's AutomaticCanvasSize would need both to be measured in
	-- the same pass; the row count is cheaper and exact.
	local rows = math.ceil(#blades / 5)
	grid.Size = UDim2.new(1, 0, 0, math.max(1, rows) * (BLADE_CARD_H + 8))
	host.CanvasSize = UDim2.fromOffset(0, gridY + 22 + math.max(1, rows) * (BLADE_CARD_H + 8) + 24)
end

-- ---------------------------------------------------------------------------
-- Requests
-- ---------------------------------------------------------------------------

local function refreshRoster()
	if shell == nil or not shell.isOpen() or loading then
		return
	end
	loading = true
	task.spawn(function()
		local data = StateStore.request("roster")
		loading = false
		if shell == nil or not shell.isOpen() then
			return
		end
		if type(data) ~= "table" or type(data.players) ~= "table" or #data.players == 0 then
			return
		end
		local signature = rosterSig(data)
		if signature == rosterSignature then
			return
		end
		rosterSignature = signature
		rosterData = data
		local found = false
		for _, entry in data.players do
			if entry.userId == selectedUserId then
				found = true
				break
			end
		end
		if not found then
			selectedUserId = tonumber(data.you) or data.players[1].userId
		end
		paintList()
		if detailUserId ~= selectedUserId and not detailPending then
			PlayersView.select(selectedUserId)
		end
	end)
end

local function loadDetail(userId: number)
	detailToken += 1
	local token = detailToken
	detailPending = true
	paintLoading()
	task.spawn(function()
		for _ = 1, 4 do
			local data = StateStore.request("playerDetail", userId)
			if token ~= detailToken then
				return
			end
			if type(data) == "table" then
				paintDetail(data)
				return
			end
			task.wait(0.45)
		end
		if token == detailToken then
			detailPending = false
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------

--- Switches the card. The list repaints immediately; the payload is requested in
--- the background so a rate-limited answer can never freeze the panel.
function PlayersView.select(userId: number): boolean
	if selectedUserId == userId and detailUserId == userId and detailLoaded then
		return true
	end
	selectedUserId = userId
	Sfx.tab()
	paintList()
	loadDetail(userId)
	return true
end

function PlayersView.open()
	local handle = shell
	if handle == nil or handle.isOpen() then
		return
	end
	selectedUserId = 0
	detailUserId = 0
	detailLoaded = false
	detailPending = false
	rosterSignature = ""
	rosterData = nil
	detailToken += 1
	clearStage()
	handle.open()
	refreshClock = 0
	refreshRoster()
end

function PlayersView.close()
	if shell then
		shell.close()
	end
end

function PlayersView.isOpen(): boolean
	return shell ~= nil and shell.isOpen()
end

function PlayersView.step(dt: number)
	if shell == nil or not shell.isOpen() then
		return
	end
	refreshClock += dt
	if refreshClock < REFRESH_SECONDS then
		return
	end
	refreshClock = 0
	refreshRoster()
end

function PlayersView.init(canvas: Frame)
	if shell then
		return
	end

	local handle = ModalShell.build(canvas, {
		name = "PlayersOverlay",
		title = "PLAYER VIEW",
		icon = "players",
		accent = Theme.Color.cyan,
		width = 1120,
		height = 680,
		onClose = function()
			clearStage()
			rosterData = nil
			rosterSignature = ""
			detailToken += 1
		end,
	}, 50)
	shell = handle

	local list = UiKit.scroll(handle.body, { thickness = 4 })
	list.Name = "PlayerList"
	list.Position = UDim2.fromOffset(16, 14)
	list.Size = UDim2.fromOffset(LIST_W, 594)
	list.ZIndex = 2
	UiKit.vlist(list, { gap = 6, padTop = 2, padBottom = 2 })
	listHost = list

	local detail = UiKit.scroll(handle.body, { thickness = 5 })
	detail.Name = "PlayerDetail"
	detail.Position = UDim2.fromOffset(DETAIL_X, 14)
	detail.Size = UDim2.fromOffset(BODY_W, 594)
	detail.ZIndex = 1
	detail.AutomaticCanvasSize = Enum.AutomaticSize.Y
	detailHost = detail

	paintLoading()
end

function PlayersView.destroy()
	clearStage()
	if shell then
		shell.destroy()
		shell = nil
	end
	listHost = nil
	detailHost = nil
	rosterData = nil
	rosterSignature = ""
	detailToken += 1
end

return PlayersView
