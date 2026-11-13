--!strict
-- Drawn HUD icons. Geometry, not glyphs.
--
-- A glyph is at the mercy of the client's font stack, and mixing a glyph with a
-- drawn currency badge makes two icon systems sit side by side. Every icon here
-- is a 24x24 canvas of frames, scaled by one `UIScale`, so it cannot tofu.
--
-- The grammar matches the rest of the house: one solid silhouette in `color`,
-- and the detail cut out in ink. There is no per-shape outline any more. At
-- 18-22px a 2px ring around a 4px bar leaves one pixel of fill, which is why
-- the first set read as dark blobs beside the chunky surfaces it sat on. A cut
-- is cheaper than a ring and stays legible at the smallest size the HUD uses.
--
-- Every mark is one shape plus one or two notches. Detail below 3px is a smudge
-- at canvas scale, so nothing here is drawn thinner than that.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ContentProvider = game:GetService("ContentProvider")

local Theme = require(script.Parent.Theme)
local AssetManifest = require(Shared:WaitForChild("AssetManifest"))

local Icons = {}

local CANVAS = 24

local function canvas(parent: GuiObject, size: number): Frame
	local root = Instance.new("Frame")
	root.Name = "Icon"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = UDim2.fromOffset(CANVAS, CANVAS)
	root.Parent = parent

	local scale = Instance.new("UIScale")
	scale.Scale = size / CANVAS
	scale.Parent = root
	return root
end

local function plate(parent: GuiObject, x: number, y: number, w: number, h: number, color: Color3): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.Position = UDim2.fromOffset(x, y)
	frame.Size = UDim2.fromOffset(w, h)
	frame.Parent = parent
	return frame
end

local function round(frame: Frame, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = frame
end

--- A cut: a piece of the mark removed, filled with the ink colour. Reads as
--- negative space on any backing because every icon sits on a dark surface or a
--- dark plaque.
local function cut(parent: GuiObject, x: number, y: number, w: number, h: number, radius: number?): Frame
	local frame = plate(parent, x, y, w, h, Theme.Color.outline)
	if radius ~= nil then
		round(frame, radius)
	end
	return frame
end

--- Same as `cut`, but in a named colour. Used where a second material has to
--- read on top of the silhouette instead of punching through it.
local function inset(parent: GuiObject, x: number, y: number, w: number, h: number, color: Color3, radius: number?): Frame
	local frame = plate(parent, x, y, w, h, color)
	if radius ~= nil then
		round(frame, radius)
	end
	return frame
end

local function guide(root: Frame, color: Color3)
	-- A pennant on a pole. The first set used a question mark in a ring, which
	-- was a glyph doing an icon's job and read as "unknown" rather than "tour".
	local pole = plate(root, 5, 3, 3, 18, color)
	round(pole, 1)
	local flag = plate(root, 8, 4, 12, 9, color)
	round(flag, 2)
	cut(flag, 9, 0, 4, 9)
end

local function feedback(root: Frame, color: Color3)
	local bubble = plate(root, 2, 4, 20, 14, color)
	round(bubble, 4)
	local tail = plate(root, 6, 15, 6, 6, color)
	tail.Rotation = 45
	round(tail, 1)
	for index = 0, 2 do
		cut(bubble, 6 + index * 5, 10, 2, 2, 1)
	end
end

local function codex(root: Frame, color: Color3)
	-- Open book: two page blocks and a dark gutter. A closed book with two
	-- rules read as the letters "IE" at 22px, which is a worse failure than an
	-- abstract mark.
	local left = plate(root, 3, 5, 9, 15, color)
	round(left, 2)
	local right = plate(root, 13, 5, 9, 15, color)
	round(right, 2)
	cut(root, 11, 5, 2, 15)
	cut(left, 2, 3, 5, 2, 1)
	cut(left, 2, 7, 5, 2, 1)
	cut(right, 2, 3, 5, 2, 1)
	cut(right, 2, 7, 5, 2, 1)
end

local function boards(root: Frame, color: Color3)
	local heights = { 7, 11, 15 }
	for index, height in heights do
		local bar = plate(root, 3 + (index - 1) * 7, 20 - height, 5, height, color)
		round(bar, 2)
	end
end

--- Backpack. The vault key: a body, a lit flap and a zip, the silhouette a
--- player already reads as "the stuff I am carrying".
local function vault(root: Frame, color: Color3)
	local body = plate(root, 4, 8, 16, 13, color)
	round(body, 3)
	local flap = inset(root, 6, 5, 12, 5, color:Lerp(Theme.Color.outline, 0.3), 2)
	cut(flap, 5, 1, 2, 4, 1)
	cut(body, 7, 13, 10, 2, 1)
end

--- Gear. Four teeth on the diagonals and a hollow centre: eight teeth turn to
--- mush at this size, so the count is cut, not the geometry.
local function settings(root: Frame, color: Color3)
	local ring = plate(root, 5, 5, 14, 14, color)
	round(ring, 7)
	cut(ring, 5, 5, 4, 4, 2)
	for _, offset in { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } } do
		local tooth = plate(root, 10 + offset[1] * 8, 10 + offset[2] * 8, 4, 4, color)
		tooth.Rotation = 45
		round(tooth, 1)
	end
end

--- Ascend. A double chevron over a floor: the one gesture in the game that
--- means "everything resets upward".
local function ascend(root: Frame, color: Color3)
	for _, y in { 5, 11 } do
		local left = plate(root, 5, y, 8, 3, color)
		left.Rotation = -45
		round(left, 1)
		local right = plate(root, 12, y, 8, 3, color)
		right.Rotation = 45
		round(right, 1)
	end
	local floor = plate(root, 5, 19, 14, 2, color)
	round(floor, 1)
end

--- Daily. A calendar with a lit stamp: the day you have not claimed.
local function daily(root: Frame, color: Color3)
	local body = plate(root, 4, 6, 16, 15, color)
	round(body, 2)
	local head = inset(body, 0, 0, 16, 4, color:Lerp(Theme.Color.outline, 0.35))
	round(head, 2)
	cut(head, 0, 3, 16, 1)
	for _, x in { 8, 15 } do
		local pin = plate(root, x, 3, 2, 5, color)
		round(pin, 1)
	end
	cut(body, 4, 9, 8, 2, 1)
	cut(body, 4, 13, 5, 2, 1)
end

--- Trade. Two arrows crossing: out and back, which is what a trade is.
local function trade(root: Frame, color: Color3)
	local top = plate(root, 4, 8, 14, 3, color)
	round(top, 1)
	local topHead = plate(root, 15, 5, 6, 9, color)
	topHead.Rotation = 45
	round(topHead, 1)
	local bottom = plate(root, 6, 14, 14, 3, color)
	round(bottom, 1)
	local bottomHead = plate(root, 3, 11, 6, 9, color)
	bottomHead.Rotation = 45
	round(bottomHead, 1)
end

-- ---------------------------------------------------------------------------
-- Section marks
-- ---------------------------------------------------------------------------
--
-- The rail used to render section names as text glyphs, and half of them were
-- tofu boxes on this client. These are drawn silhouettes instead: at 22px a
-- mark has to be one shape with one notch, not an illustration.

--- Forge: an anvil. Wide face, narrow waist, wide foot. The horn is the notch
--- that separates it from "a stack of bars".
local function forgeMark(root: Frame, color: Color3)
	local face = plate(root, 3, 6, 18, 5, color)
	round(face, 1)
	local horn = plate(root, 0, 7, 4, 3, color)
	round(horn, 1)
	plate(root, 9, 11, 6, 5, color)
	local base = plate(root, 5, 16, 14, 4, color)
	round(base, 1)
end

--- Crates: a box with one band across and one down, and a lid lip so the top
--- edge reads as a lid rather than as a second rectangle.
local function crateMark(root: Frame, color: Color3)
	local body = plate(root, 3, 6, 18, 15, color)
	round(body, 1)
	cut(body, 0, 5, 18, 3)
	cut(body, 7, 0, 4, 15)
	local lid = plate(root, 2, 3, 20, 4, color)
	round(lid, 1)
end

--- Fleet: a drone. A diamond hull, two rotor bars, one skid.
local function fleetMark(root: Frame, color: Color3)
	local hull = plate(root, 8, 8, 8, 8, color)
	hull.Rotation = 45
	round(hull, 2)
	cut(hull, 2, 2, 4, 4, 2)
	local left = plate(root, 1, 4, 8, 3, color)
	round(left, 1)
	local right = plate(root, 15, 4, 8, 3, color)
	round(right, 1)
	local skid = plate(root, 7, 18, 10, 3, color)
	round(skid, 1)
end

--- Runes: a gem. A solid diamond with an inner diamond cut out, so the shape
--- reads as a faceted stone instead of a wireframe.
local function runeMark(root: Frame, color: Color3)
	local gem = plate(root, 5, 5, 14, 14, color)
	gem.Rotation = 45
	round(gem, 2)
	cut(gem, 5, 5, 4, 4, 1)
end

--- Tech: three nodes on a trunk and a branch.
local function techMark(root: Frame, color: Color3)
	local trunk = plate(root, 10, 4, 4, 14, color)
	local branch = plate(root, 4, 11, 16, 3, color)
	round(trunk, 1)
	round(branch, 1)
	for _, node in { { 8, 1 }, { 2, 13 }, { 16, 13 } } do
		local cell = plate(root, node[1], node[2], 7, 7, color)
		round(cell, 2)
	end
end

--- Store: a cart. Basket, angled handle, two wheels.
local function storeMark(root: Frame, color: Color3)
	local basket = plate(root, 5, 8, 13, 8, color)
	round(basket, 1)
	cut(basket, 3, 2, 7, 2)
	local handle = plate(root, 2, 6, 8, 3, color)
	handle.Rotation = -32
	round(handle, 1)
	for _, x in { 6, 14 } do
		local wheel = plate(root, x, 17, 5, 5, color)
		round(wheel, 2)
	end
end

--- Players. Two heads and two shoulders: the silhouette a player already reads
--- as "people", cut down to four shapes so it survives 22px.
local function players(root: Frame, color: Color3)
	local back = color:Lerp(Theme.Color.outline, 0.42)
	local backHead = plate(root, 13, 3, 8, 8, back)
	round(backHead, 4)
	local backBody = plate(root, 11, 12, 12, 8, back)
	round(backBody, 3)

	local frontHead = plate(root, 3, 5, 10, 10, color)
	round(frontHead, 5)
	local frontBody = plate(root, 1, 16, 16, 7, color)
	round(frontBody, 3)
end

--- The three currencies, drawn at 24px so one canvas covers every size the HUD
--- asks for. They mirror the top-bar badges: a star for Star-Matter, a faceted
--- crystal for Aether, a cold ring for Cores.
local function starMark(root: Frame, color: Color3)
	local glyph = Instance.new("TextLabel")
	glyph.Name = "Glyph"
	glyph.BackgroundTransparency = 1
	glyph.BorderSizePixel = 0
	glyph.Size = UDim2.fromScale(1, 1)
	glyph.Font = Theme.Font.Black
	glyph.Text = "★"
	glyph.TextSize = 23
	glyph.TextColor3 = color
	glyph.TextStrokeColor3 = Theme.Color.outline
	glyph.TextStrokeTransparency = 0.5
	glyph.Parent = root
end

local function aetherMark(root: Frame, color: Color3)
	local outer = plate(root, 4, 4, 16, 16, color)
	outer.Rotation = 45
	round(outer, 3)
	local facet = plate(outer, 5, 5, 6, 6, Theme.Color.white)
	round(facet, 1)
end

local function coreMark(root: Frame, color: Color3)
	local ring = plate(root, 3, 3, 18, 18, color)
	round(ring, 9)
	cut(ring, 3, 3, 12, 12, 6)
	local disc = plate(ring, 6, 6, 6, 6, color)
	round(disc, 3)
end

--- A vent: a low tray with three plumes rising out of it. Deliberately not the
--- anvil, and not a thermometer: the key dumps heat, it does not measure it.
local function ventMark(root: Frame, color: Color3)
	local tray = plate(root, 3, 18, 18, 3, color)
	round(tray, 1)
	local left = plate(root, 5, 11, 3, 6, color)
	round(left, 1)
	local middle = plate(root, 10, 6, 4, 11, color)
	round(middle, 2)
	local right = plate(root, 16, 11, 3, 6, color)
	round(right, 1)
	local puff = plate(root, 9, 2, 6, 3, color)
	round(puff, 1)
end

--- Builds one icon onto `parent` and returns the scaled canvas. Caller positions
--- it; the canvas is 24x24 in its own space and `size` after the UIScale.
function Icons.build(parent: GuiObject, kind: string, size: number, color: Color3): Frame
	local root = canvas(parent, size)
	if kind == "aether" then
		aetherMark(root, color)
	elseif kind == "star" then
		starMark(root, color)
	elseif kind == "core" then
		coreMark(root, color)
	elseif kind == "vent" then
		ventMark(root, color)
	elseif kind == "guide" then
		guide(root, color)
	elseif kind == "feedback" then
		feedback(root, color)
	elseif kind == "codex" then
		codex(root, color)
	elseif kind == "boards" then
		boards(root, color)
	elseif kind == "players" then
		players(root, color)
	elseif kind == "vault" then
		vault(root, color)
	elseif kind == "settings" then
		settings(root, color)
	elseif kind == "ascend" then
		ascend(root, color)
	elseif kind == "daily" then
		daily(root, color)
	elseif kind == "trade" then
		trade(root, color)
	elseif kind == "forge" then
		forgeMark(root, color)
	elseif kind == "crates" then
		crateMark(root, color)
	elseif kind == "fleet" then
		fleetMark(root, color)
	elseif kind == "runes" then
		runeMark(root, color)
	elseif kind == "tech" then
		techMark(root, color)
	elseif kind == "store" then
		storeMark(root, color)
	end
	return root
end

local CURRENCY: { [string]: { kind: string, color: Color3 } } = {
	as = { kind = "aether", color = Theme.Color.aether },
	aether = { kind = "aether", color = Theme.Color.aether },
	sm = { kind = "star", color = Theme.Color.starMatter },
	star = { kind = "star", color = Theme.Color.starMatter },
	starMatter = { kind = "star", color = Theme.Color.starMatter },
	qc = { kind = "core", color = Theme.Color.quantum },
	core = { kind = "core", color = Theme.Color.quantum },
	cores = { kind = "core", color = Theme.Color.quantum },
}

-- Uploaded currency art. The top bar lays these PNGs over its vector badges and
-- retires the drawing once the thumbnail resolves. Inline marks do the same, so
-- a price row and the bar show one icon, not two designs. State is per asset:
-- one preload, then every later row swaps to the art in the same frame.
local artState: { [string]: string } = {}
local artWaiters: { [string]: { ImageLabel } } = {}

local function showArt(image: ImageLabel, root: Frame)
	Theme.fade(image, 0.16, { ImageTransparency = 0 })
	for _, child in root:GetChildren() do
		if child ~= image then
			if child:IsA("Frame") then
				Theme.fade(child, 0.16, { BackgroundTransparency = 1 })
			elseif child:IsA("TextLabel") then
				Theme.fade(child, 0.16, { TextTransparency = 1, TextStrokeTransparency = 1 })
			end
		end
	end
end

local function attachArt(root: Frame, key: string)
	local source = AssetManifest.currencyArt(key)
	if source == "" then
		return
	end

	local image = Instance.new("ImageLabel")
	image.Name = "CurrencyArt"
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.Size = UDim2.fromScale(1, 1)
	image.ScaleType = Enum.ScaleType.Fit
	image.Image = source
	image.ImageTransparency = 1
	image.ZIndex = 4
	image.Parent = root

	local state = artState[key]
	if state == "ready" then
		image.ImageTransparency = 0
		for _, child in root:GetChildren() do
			if child ~= image then
				if child:IsA("Frame") then
					child.BackgroundTransparency = 1
				elseif child:IsA("TextLabel") then
					child.TextTransparency = 1
					child.TextStrokeTransparency = 1
				end
			end
		end
		return
	end
	if state == "loading" then
		local waiters = artWaiters[key]
		if waiters then
			table.insert(waiters, image)
		end
		return
	end
	if state == "failed" then
		return
	end

	artState[key] = "loading"
	artWaiters[key] = { image }
	task.spawn(function()
		local ok = pcall(function()
			ContentProvider:PreloadAsync({ image })
		end)
		artState[key] = if ok then "ready" else "failed"
		local waiters = artWaiters[key] or {}
		artWaiters[key] = nil
		if not ok then
			return
		end
		for _, waiter in waiters do
			local holder = waiter.Parent
			if holder and holder:IsA("Frame") then
				showArt(waiter, holder)
			end
		end
	end)
end

--- One currency mark in the colour the top bar uses. `key` accepts the short
--- payload names (`as`, `sm`, `qc`) and the long ones. The vector is the first
--- frame; when the uploaded art is resident it is laid on top, exactly as the
--- top bar does, so every inline price matches the bar instead of merely
--- resembling it.
function Icons.currency(parent: GuiObject, key: string, size: number, color: Color3?): Frame
	local entry = CURRENCY[key]
	local root = Icons.build(
		parent,
		if entry then entry.kind else "star",
		size,
		color or (if entry then entry.color else Theme.Color.starMatter)
	)
	local artKey = if entry == nil or entry.kind == "star"
		then "sm"
		elseif entry.kind == "aether" then "as"
		else "qc"
	attachArt(root, artKey)
	return root
end

return Icons
