--!strict
-- Global leaderboards. Five boards, one page each, refreshed on open and on a
-- slow timer while the panel is up.
--
-- The server owns the ranking and the format strings; this view paints rows. It
-- never sorts a board itself, because a client-side sort of a top-20 page is
-- how a player ends up ranked second in their own game and fortieth on the
-- server.
--
-- Studio without DataStore access serves a seeded local board flagged `mock`.
-- The view says PREVIEW in the header when that flag is set, because a fake
-- global ranking presented as real is the one lie a leaderboard cannot afford.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BladeRegistry = require(Shared:WaitForChild("BladeRegistry"))
local ForgeConfig = require(Shared:WaitForChild("ForgeConfig"))
local ModifierConfig = require(Shared:WaitForChild("ModifierConfig"))
local NumberUtil = require(Shared:WaitForChild("NumberUtil"))

local Theme = require(script.Parent.Theme)
local UiKit = require(script.Parent.UiKit)
local ModalShell = require(script.Parent.ModalShell)
local BladePreview = require(script.Parent.BladePreview)
local StateStore = require(script.Parent.StateStore)
local Sfx = require(script.Parent.Sfx)

local LeaderboardView = {}

local REFRESH_SECONDS = 12

local shell: ModalShell.Handle? = nil
local tabBar: Frame? = nil
local list: ScrollingFrame? = nil
local caption: TextLabel? = nil
local mockBadge: Frame? = nil
local activeBoard = "star"
local refreshClock = 0
local staged = false

local BOARDS = {
	{ id = "star", label = "STAR-MATTER", accent = Theme.Color.starMatter },
	{ id = "playtime", label = "PLAYTIME", accent = Theme.Color.emerald },
	{ id = "aether", label = "AETHER", accent = Theme.Color.cyan },
	{ id = "cores", label = "CORES", accent = Theme.Color.quantum },
	{ id = "blades", label = "BEST BLADE", accent = Theme.Color.gold },
}

local lastSignature = ""

--- Full-width text row for the four currency boards.
local function row(order: number, rank: number, name: string, value: string, you: boolean, accent: Color3)
	local frame = UiKit.panel(list :: ScrollingFrame, {
		tier = if you then "raised" else "well",
		radius = Theme.Radius.sm,
		stroke = if you then accent else Theme.Color.strokeFaint,
		bevel = false,
		lip = false,
	})
	frame.Name = string.format("BoardRow_%d", order)
	frame.Size = UDim2.new(1, -8, 0, 44)
	frame.LayoutOrder = order

	local place = UiKit.label(frame, {
		text = string.format("%d", rank),
		size = Theme.Text.Subheading,
		font = Theme.Font.Black,
		color = if rank <= 3 then accent else Theme.Color.textDim,
		align = Enum.TextXAlignment.Center,
	})
	place.Position = UDim2.fromOffset(0, 0)
	place.Size = UDim2.fromOffset(54, 44)

	local who = UiKit.label(frame, {
		text = name,
		size = Theme.Text.Small,
		font = Theme.Font.Heading,
		color = if you then Theme.Color.text else Theme.Color.textSecondary,
		align = Enum.TextXAlignment.Left,
	})
	who.Position = UDim2.fromOffset(60, 0)
	who.Size = UDim2.new(1, -290, 1, 0)
	who.TextTruncate = Enum.TextTruncate.AtEnd

	if you then
		local tag = UiKit.badge(frame, {
			text = "YOU",
			color = accent,
			width = 54,
			height = 20,
			size = Theme.Text.Tiny,
			textColor = Theme.Color.ink,
		})
		tag.AnchorPoint = Vector2.new(1, 0.5)
		tag.Position = UDim2.new(1, -150, 0.5, 0)
	end

	local score = UiKit.label(frame, {
		text = value,
		size = Theme.Text.Small,
		font = Theme.Font.Numeric,
		color = accent,
		align = Enum.TextXAlignment.Right,
	})
	score.Name = "Score"
	score.Position = UDim2.new(1, -140, 0, 0)
	score.Size = UDim2.fromOffset(124, 44)
end

--- BEST BLADE row: the model, the affixed name, the condition, the variant and
--- the exact multiplier.
---
--- A text-only row was the report's complaint: the board is a collection flex,
--- and a name with a number beside it says nothing about the thing being flexed.
--- The model comes from the same `BladePreview` the vault and the forge use, so
--- the blade on the board is the blade in the hand.
local function bladeRow(order: number, entry: any, accent: Color3, you: boolean)
	local frame = UiKit.panel(list :: ScrollingFrame, {
		tier = if you then "raised" else "well",
		radius = Theme.Radius.sm,
		stroke = if you then accent else Theme.Color.strokeFaint,
		bevel = false,
		lip = false,
	})
	frame.Name = string.format("BoardRow_%d", order)
	frame.Size = UDim2.new(1, -8, 0, 76)
	frame.LayoutOrder = order

	local place = UiKit.label(frame, {
		text = string.format("%d", tonumber(entry.rank) or order),
		size = Theme.Text.Subheading,
		font = Theme.Font.Black,
		color = if (tonumber(entry.rank) or order) <= 3 then accent else Theme.Color.textDim,
		align = Enum.TextXAlignment.Center,
	})
	place.Position = UDim2.fromOffset(0, 0)
	place.Size = UDim2.fromOffset(44, 76)

	local detail = entry.blade
	local bladeDef = if type(detail) == "table" and type(detail.id) == "string"
		then BladeRegistry.get(detail.id)
		else nil

	local stage = UiKit.create("ViewportFrame", {
		Name = "BladeStage",
		BackgroundColor3 = Theme.Color.void,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(44, 6),
		Size = UDim2.fromOffset(64, 64),
	}) :: ViewportFrame
	UiKit.stroke(stage, Theme.Color.strokeFaint, Theme.Stroke.hair, 0)
	stage.Parent = frame
	if bladeDef then
		local tint = ForgeConfig.variant(detail.variant).color
		BladePreview.thumbnail(stage, bladeDef, false, tint)
	else
		-- No recorded copy: an empty slate slot, not a black hole. Rows written
		-- before this board carried detail, or a player who has not submitted
		-- since the change, land here.
		stage.BackgroundColor3 = Theme.Color.slate
	end

	local owner = UiKit.label(frame, {
		text = tostring(entry.name or "?"),
		size = Theme.Text.Small,
		font = Theme.Font.Heading,
		color = Theme.Color.text,
		align = Enum.TextXAlignment.Left,
	})
	owner.Name = "Owner"
	owner.Position = UDim2.fromOffset(116, 6)
	owner.Size = UDim2.new(1, -330, 0, 20)
	owner.TextTruncate = Enum.TextTruncate.AtEnd

	local bladeName = if type(detail) == "table" and type(detail.display) == "string" and detail.display ~= ""
		then detail.display
		else "NO BLADE RECORDED"
	local head = UiKit.label(frame, {
		text = bladeName,
		size = Theme.Text.Tiny,
		font = Theme.Font.Label,
		color = Theme.Color.textSecondary,
		align = Enum.TextXAlignment.Left,
	})
	head.Name = "BladeName"
	head.Position = UDim2.fromOffset(116, 27)
	head.Size = UDim2.new(1, -330, 0, 18)
	head.TextTruncate = Enum.TextTruncate.AtEnd

	if type(detail) == "table" then
		local variant = ForgeConfig.variant(detail.variant)
		local chip = UiKit.badge(frame, {
			text = string.upper(variant.name),
			color = variant.color,
			width = 104,
			height = 19,
			size = Theme.Text.Tiny,
			textColor = Theme.Color.ink,
		})
		chip.Name = "VariantChip"
		chip.Position = UDim2.fromOffset(116, 48)

		local condition = UiKit.label(frame, {
			text = ModifierConfig.condition(detail.grade or "", detail.element or ""),
			size = Theme.Text.Tiny,
			font = Theme.Font.Label,
			color = Theme.Color.textDim,
			align = Enum.TextXAlignment.Left,
		})
		condition.Name = "Condition"
		condition.Position = UDim2.fromOffset(228, 48)
		condition.Size = UDim2.new(1, -430, 0, 19)
		condition.TextTruncate = Enum.TextTruncate.AtEnd
	end

	local scoreText = if type(detail) == "table" and tonumber(detail.mult) ~= nil
		then NumberUtil.abbreviateMultiplier(tonumber(detail.mult) :: number)
		else tostring(entry.text or "x0.00")
	local score = UiKit.label(frame, {
		text = scoreText,
		size = Theme.Text.Subheading,
		font = Theme.Font.Numeric,
		color = accent,
		align = Enum.TextXAlignment.Right,
	})
	score.Name = "Score"
	score.AnchorPoint = Vector2.new(1, 0.5)
	score.Position = UDim2.new(1, -18, 0.5, 0)
	score.Size = UDim2.fromOffset(190, 28)

	if you then
		local tag = UiKit.badge(frame, {
			text = "YOU",
			color = accent,
			width = 54,
			height = 20,
			size = Theme.Text.Tiny,
			textColor = Theme.Color.ink,
		})
		tag.Name = "YouTag"
		tag.AnchorPoint = Vector2.new(1, 0.5)
		tag.Position = UDim2.new(1, -18, 0.5, -26)
	end
end

local function paintTabs()
	local bar = tabBar
	if bar == nil then
		return
	end
	ModalShell.clear(bar)
	for index, board in BOARDS do
		local active = activeBoard == board.id
		local pill = UiKit.button(bar, {
			text = board.label,
			fill = if active then board.accent else Theme.Color.slate,
			stroke = if active then Theme.Color.outline else Theme.Color.stroke,
			height = 36,
			radius = Theme.Radius.sm,
			size = Theme.Text.Tiny,
			font = Theme.Font.Black,
			textColor = if active then Theme.Color.text else Theme.Color.textDim,
			handler = function()
				if activeBoard == board.id then
					return
				end
				activeBoard = board.id
				Sfx.tab()
				paintTabs()
				LeaderboardView.refresh()
			end,
		})
		pill.Name = "BoardTab_" .. board.id
		pill.Position = UDim2.fromOffset((index - 1) * 190, 0)
		pill.Size = UDim2.fromOffset(182, 36)
	end
end

local accentOf = function(boardId: string): Color3
	for _, board in BOARDS do
		if board.id == boardId then
			return board.accent
		end
	end
	return Theme.Color.gold
end

--- Pulls the active board and repaints. Called on open, on tab change, and on
--- the refresh clock while the panel is visible.
function LeaderboardView.refresh()
	local area = list
	if area == nil or shell == nil then
		return
	end

	local payload = StateStore.request("leaderboard", activeBoard)

	if type(payload) ~= "table" then
		ModalShell.clear(area)
		lastSignature = ""
		local empty = UiKit.label(area, {
			text = "RANKINGS UNAVAILABLE",
			size = Theme.Text.Small,
			font = Theme.Font.Black,
			color = Theme.Color.textFaint,
			align = Enum.TextXAlignment.Center,
		})
		empty.Size = UDim2.new(1, 0, 0, 60)
		empty.Position = UDim2.fromOffset(0, 40)
		if caption then
			caption.Text = "The board server did not answer"
		end
		return
	end

	local data = payload :: any
	local mock = data.mock == true
	staged = mock
	if mockBadge then
		mockBadge.Visible = mock
	end
	if caption then
		caption.Text = tostring(data.caption or "")
	end

	local rows = data.rows
	if type(rows) ~= "table" or #rows == 0 then
		ModalShell.clear(area)
		lastSignature = ""
		local empty = UiKit.label(area, {
			text = "NO ENTRIES YET",
			size = Theme.Text.Small,
			font = Theme.Font.Black,
			color = Theme.Color.textFaint,
			align = Enum.TextXAlignment.Center,
		})
		empty.Size = UDim2.new(1, 0, 0, 60)
		empty.Position = UDim2.fromOffset(0, 40)
		return
	end

	-- The panel repaints on a twelve second clock, but a board that has not
	-- moved must not rebuild twenty blade models. The signature covers every
	-- field the row prints, so a rank change, a new multiplier or a different
	-- copy all force a repaint, and an idle server costs one string compare.
	local signature = string.format("%s|%s", activeBoard, tostring(mock))
	for index, entry in rows do
		local blade = entry.blade
		local mark = if type(blade) == "table"
			then string.format("%s/%s/%.6f", tostring(blade.id), tostring(blade.variant), tonumber(blade.mult) or 0)
			else "-"
		signature ..= string.format(
			"|%d:%s:%s:%s:%s",
			tonumber(entry.rank) or index,
			tostring(entry.name),
			tostring(entry.text),
			tostring(entry.you),
			mark
		)
	end
	if signature == lastSignature and #area:GetChildren() > 0 then
		return
	end
	lastSignature = signature
	ModalShell.clear(area)

	local accent = accentOf(activeBoard)
	local blades = activeBoard == "blades"
	for index, entry in rows do
		if blades then
			bladeRow(index, entry, accent, entry.you == true)
		else
			row(
				index,
				tonumber(entry.rank) or index,
				tostring(entry.name or "?"),
				-- `text` is the server's formatted value: the same formatter that
				-- writes the board's caption, so a Star-Matter row reads "9.2T"
				-- rather than an 18-digit integer.
				tostring(entry.text or entry.value or "0"),
				entry.you == true,
				accent
			)
		end
	end
end

function LeaderboardView.open()
	local handle = shell
	if handle == nil or handle.isOpen() then
		return
	end
	handle.open()
	paintTabs()
	LeaderboardView.refresh()
	refreshClock = 0
end

function LeaderboardView.close()
	if shell then
		shell.close()
	end
end

function LeaderboardView.isOpen(): boolean
	return shell ~= nil and shell.isOpen()
end

--- Switches board by id. Same reason as `CodexView.setTab`: verification needs
--- the state change without a pointer.
function LeaderboardView.setBoard(id: string): boolean
	for _, board in BOARDS do
		if board.id == id then
			if activeBoard == id then
				return true
			end
			activeBoard = id
			Sfx.tab()
			paintTabs()
			LeaderboardView.refresh()
			return true
		end
	end
	return false
end

--- Called from the client render loop. Cheap when the panel is shut.
function LeaderboardView.step(dt: number)
	if shell == nil or not shell.isOpen() then
		return
	end
	refreshClock += dt
	if refreshClock < REFRESH_SECONDS then
		return
	end
	refreshClock = 0
	LeaderboardView.refresh()
end

function LeaderboardView.isPreview(): boolean
	return staged
end

function LeaderboardView.init(canvas: Frame)
	if shell then
		return
	end

	local handle = ModalShell.build(canvas, {
		name = "BoardsOverlay",
		title = "LEADERBOARDS",
		icon = "boards",
		accent = Theme.Color.emerald,
		width = 980,
		height = 660,
	}, 48)
	shell = handle

	local title = UiKit.label(handle.body, {
		text = "GLOBAL RANKINGS",
		size = Theme.Text.Small,
		font = Theme.Font.Black,
		color = Theme.Color.emerald,
		align = Enum.TextXAlignment.Left,
	})
	title.Position = UDim2.fromOffset(18, 12)
	title.Size = UDim2.fromOffset(300, 22)

	if mockBadge then
		mockBadge:Destroy()
		mockBadge = nil
	end
	local badge = UiKit.badge(handle.body, {
		text = "PREVIEW",
		color = Theme.Color.gold,
		width = 92,
		height = 20,
		size = Theme.Text.Tiny,
		textColor = Theme.Color.ink,
	})
	badge.Name = "MockBadge"
	badge.Position = UDim2.fromOffset(196, 13)
	badge.Visible = false
	mockBadge = badge

	caption = UiKit.label(handle.body, {
		text = "",
		size = Theme.Text.Tiny,
		font = Theme.Font.Label,
		color = Theme.Color.textDim,
		align = Enum.TextXAlignment.Right,
	})
	caption.Name = "BoardCaption"
	caption.AnchorPoint = Vector2.new(1, 0)
	caption.Position = UDim2.new(1, -18, 0, 14)
	caption.Size = UDim2.fromOffset(420, 20)

	local bar = UiKit.create("Frame", {
		Name = "BoardTabs",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(18, 44),
		Size = UDim2.new(1, -36, 0, 36),
	}) :: Frame
	bar.Parent = handle.body
	tabBar = bar

	local area = UiKit.scroll(handle.body)
	area.Name = "BoardList"
	area.Position = UDim2.fromOffset(18, 92)
	area.Size = UDim2.new(1, -36, 1, -106)
	UiKit.vlist(area, { gap = 6, padding = 6 })

	-- The list is a ScrollingFrame of full-width rows; the vlist gives them
	-- order, the scroll gives them a viewport.
	list = area

	paintTabs()
end

function LeaderboardView.destroy()
	if shell then
		shell.destroy()
		shell = nil
	end
	tabBar = nil
	list = nil
	caption = nil
	mockBadge = nil
	lastSignature = ""
end

return LeaderboardView
