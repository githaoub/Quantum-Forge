--!strict
-- The player plate in the top-left of the bar: face, name, rank and the run to
-- the next ascension.
--
-- Why a plate at all: the screen is a full-width app now, and the one thing it
-- had no room for was the player. A commercial-simulator top bar opens with an
-- identity block — the reference does exactly this — because every number to its
-- right is *this* player's number, and without the block the bar reads as a
-- dashboard rather than as a save file.
--
-- The avatar is the account thumbnail, fetched once. `GetUserThumbnailAsync`
-- returns an `rbxthumb://` content id, which is not an upload, needs no
-- moderation and cannot fail the way a hand-uploaded asset does. It does yield,
-- so the whole fetch is a spawned task behind a pcall; the plate paints with the
-- player's initial and replaces it when the image lands. A player with a private
-- thumbnail keeps the initial forever, which is a correct-looking fallback
-- rather than a grey hole.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))
local NumberUtil = require(Shared:WaitForChild("NumberUtil"))

local Theme = require(script.Parent.Theme)
local UiKit = require(script.Parent.UiKit)

local ProfilePlate = {}

export type Handle = {
	root: Frame,
	apply: (payload: Types.SyncPayload) -> (),
	destroy: () -> (),
}

local WIDTH = 240
local HEIGHT = 58
local FACE = 42

--- The account's head shot, as an ImageLabel inside a rounded well.
---
--- `ClipsDescendants` on the well is what rounds the image: a UICorner on an
--- ImageLabel rounds its background, not its bitmap, so the clip has to happen
--- one level up. The initial sits underneath and shows through if the fetch
--- never returns.
local function buildFace(parent: Frame, player: Player): (Frame, TextLabel, ImageLabel)
	local well = UiKit.create("Frame", {
		Name = "Face",
		BackgroundColor3 = Theme.Color.panelSunken,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(FACE, FACE),
		ClipsDescendants = true,
		ZIndex = 2,
	}) :: Frame
	UiKit.corner(well, 10)
	UiKit.stroke(well, Theme.Color.outline, 2, 0)
	well.Parent = parent

	local initial = UiKit.label(well, {
		text = string.sub(player.DisplayName, 1, 1),
		size = 22,
		font = Theme.Font.Black,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Center,
	})
	initial.Name = "Initial"
	initial.Size = UDim2.fromScale(1, 1)
	initial.ZIndex = 2

	local image = UiKit.create("ImageLabel", {
		Name = "Thumbnail",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ImageTransparency = 1,
		ZIndex = 3,
	}) :: ImageLabel
	image.Parent = well

	return well, initial, image
end

--- Rank chip: the number of ascensions plus one, sitting on the corner of the
--- face the way a level badge does on a profile card.
local function buildRankChip(parent: Frame): TextLabel
	local chip = UiKit.create("Frame", {
		Name = "RankChip",
		BackgroundColor3 = Theme.Color.skyDeep,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(36, 37),
		Size = UDim2.fromOffset(20, 18),
		ZIndex = 4,
	}) :: Frame
	UiKit.corner(chip, 6)
	UiKit.stroke(chip, Theme.Color.gold, 2, 0)
	chip.Parent = parent

	local label = UiKit.label(chip, {
		text = "1",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.gold,
		align = Enum.TextXAlignment.Center,
	})
	label.Name = "Rank"
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 5
	return label
end

function ProfilePlate.build(parent: Instance): Handle
	local player = Players.LocalPlayer

	-- Same shell as a currency capsule: navy, lit at the top, hard 2.5px
	-- outline. The plate is an instrument on the bar, not a wood panel.
	local root = UiKit.create("Frame", {
		Name = "ProfilePlate",
		BackgroundColor3 = Theme.Color.slate,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(WIDTH, HEIGHT),
	}) :: Frame
	UiKit.corner(root, Theme.Radius.lg)
	UiKit.gradient(root, { Theme.Color.slateLift, Theme.Color.slate }, 90)
	UiKit.stroke(root, Theme.Color.outline, 2.5, 0)
	root.Parent = parent

	local _, initial, image = buildFace(root, player)
	local rank = buildRankChip(root)

	local name = UiKit.label(root, {
		text = player.DisplayName,
		size = 16,
		font = Theme.Font.Black,
		color = Theme.Color.text,
		stroke = true,
	})
	name.Name = "DisplayName"
	name.Position = UDim2.fromOffset(58, 5)
	name.Size = UDim2.fromOffset(174, 18)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.ZIndex = 3

	local handle = UiKit.label(root, {
		text = "@" .. string.lower(player.Name),
		size = Theme.Text.Tiny,
		font = Theme.Font.Body,
		color = Theme.Color.textSecondary,
	})
	handle.Name = "Handle"
	handle.Position = UDim2.fromOffset(58, 23)
	handle.Size = UDim2.fromOffset(174, 14)
	handle.TextTruncate = Enum.TextTruncate.AtEnd
	handle.ZIndex = 3

	-- Run to the next ascension. The same threshold the ASCEND button reads, so
	-- the bar and the button can never disagree about how close the player is.
	local track = UiKit.create("Frame", {
		Name = "ProgressTrack",
		BackgroundColor3 = Theme.Color.skyDeep,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(58, 42),
		Size = UDim2.fromOffset(172, 7),
		ZIndex = 3,
	}) :: Frame
	UiKit.corner(track, 4)
	track.Parent = root

	local fill = UiKit.create("Frame", {
		Name = "ProgressFill",
		BackgroundColor3 = Theme.Color.gold,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		ZIndex = 4,
	}) :: Frame
	UiKit.corner(fill, 4)
	UiKit.gradient(fill, { Theme.Color.goldDeep, Theme.Color.gold }, 90)
	fill.Parent = track

	-- Thumbnail fetch. One call, one attempt: a failed fetch is not worth a
	-- retry loop against the thumbnail service, and the initial already reads
	-- as a deliberate fallback.
	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		if not ok or type(content) ~= "string" or content == "" or root.Parent == nil then
			return
		end
		image.Image = content
		initial.Visible = false
		-- Fade rather than pop: the plate is already on screen by the time the
		-- CDN answers, and a hard swap reads as a layout shift.
		UiKit.tween(image, Theme.Duration.normal, { ImageTransparency = 0 })
	end)

	local api: Handle

	local function apply(payload: Types.SyncPayload)
		local rankNumber = math.max(1, payload.ascensions + 1)
		rank.Text = tostring(rankNumber)

		local threshold = math.max(Config.AscendThreshold, 1)
		local progress = math.clamp(payload.sm / threshold, 0, 1)
		fill.Size = UDim2.fromScale(progress, 1)

		-- Two attributes, read by the Studio seam and by reviews that need the
		-- exact figure. Cheaper than a tooltip system nobody asked for.
		root:SetAttribute("Rank", rankNumber)
		root:SetAttribute("AscendProgress", progress)
		root:SetAttribute(
			"Summary",
			string.format("%s of %s to ascend", NumberUtil.abbreviate(payload.sm), NumberUtil.abbreviate(threshold))
		)
	end

	api = {
		root = root,
		apply = apply,
		destroy = function()
			root:Destroy()
		end,
	}

	return api
end

return ProfilePlate
