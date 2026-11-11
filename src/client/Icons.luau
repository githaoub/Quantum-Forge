--!strict
-- Drawn HUD icons. Geometry, not glyphs.
--
-- The old header used a literal "?" for the guide and a bare word for feedback.
-- A glyph is at the mercy of the client's font stack, and mixing a glyph with a
-- drawn currency badge makes two icon systems sit side by side. Every icon here
-- is a 24x24 canvas of frames and strokes, scaled by one `UIScale`, so it obeys
-- the same 3px-outline house style as everything else and cannot tofu.
--
-- Four marks: guide, feedback, codex, boards. They are intentionally simple at
-- 18-20px, because detail below 2px is a smudge at the canvas scale.

local Theme = require(script.Parent.Theme)

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

local function outline(frame: GuiObject, color: Color3, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
end

local function guide(root: Frame, color: Color3)
	local ring = plate(root, 3, 3, 18, 18, color)
	round(ring, 9)
	outline(ring, Theme.Color.outline, 2)

	local ink = Theme.Color.outline
	local top = plate(ring, 6, 5, 7, 2, ink)
	local right = plate(ring, 13, 7, 2, 5, ink)
	local mid = plate(ring, 9, 11, 6, 2, ink)
	local stem = plate(ring, 9, 13, 2, 3, ink)
	local dot = plate(ring, 9, 18, 2, 2, ink)
	round(top, 1)
	round(right, 1)
	round(mid, 1)
	round(stem, 1)
	round(dot, 1)
end

local function feedback(root: Frame, color: Color3)
	local bubble = plate(root, 2, 4, 20, 14, color)
	round(bubble, 4)
	outline(bubble, Theme.Color.outline, 2)

	local tail = plate(root, 6, 15, 6, 6, color)
	tail.Rotation = 45
	round(tail, 1)
	outline(tail, Theme.Color.outline, 2)

	for index = 0, 2 do
		local dot = plate(bubble, if index == 0 then 6 elseif index == 1 then 11 else 16, 10, 2, 2, Theme.Color.outline)
		round(dot, 1)
	end
end

local function codex(root: Frame, color: Color3)
	local left = plate(root, 2, 5, 9, 14, color)
	round(left, 2)
	outline(left, Theme.Color.outline, 2)

	local right = plate(root, 13, 5, 9, 14, color)
	round(right, 2)
	outline(right, Theme.Color.outline, 2)

	local spine = plate(root, 11, 5, 2, 14, Theme.Color.outline)
	round(spine, 1)

	for index = 0, 2 do
		local ink = plate(left, 4, 8 + index * 3, 5, 1, Theme.Color.outline)
		round(ink, 0)
		local inkRight = plate(right, 15, 8 + index * 3, 5, 1, Theme.Color.outline)
		round(inkRight, 0)
	end
end

local function boards(root: Frame, color: Color3)
	local heights = { 7, 11, 15 }
	for index, height in heights do
		local x = 3 + (index - 1) * 7
		local bar = plate(root, x, 20 - height, 5, height, color)
		round(bar, 2)
		outline(bar, Theme.Color.outline, 1.5)
	end
end

--- Backpack. The vault key: a body, a flap and two shoulder straps, which is the
--- only silhouette that reads as "the stuff I am carrying" at 22px.
local function vault(root: Frame, color: Color3)
	local body = plate(root, 4, 8, 16, 13, color)
	round(body, 3)
	outline(body, Theme.Color.outline, 2)

	local flap = plate(root, 6, 5, 12, 5, color:Lerp(Theme.Color.outline, 0.35))
	round(flap, 2)
	outline(flap, Theme.Color.outline, 1.5)

	local pocket = plate(root, 8, 13, 8, 6, color:Lerp(Theme.Color.outline, 0.22))
	round(pocket, 1)
	outline(pocket, Theme.Color.outline, 1.5)

	local strap = plate(root, 11, 4, 2, 5, Theme.Color.outline)
	round(strap, 1)
end

--- Gear. Four teeth on the diagonals and a hollow centre: a cog drawn with eight
--- teeth turns to mush at this size, so the count is cut, not the geometry.
local function settings(root: Frame, color: Color3)
	local ring = plate(root, 5, 5, 14, 14, color)
	round(ring, 7)
	outline(ring, Theme.Color.outline, 2)

	local hole = plate(root, 10, 10, 4, 4, Theme.Color.outline)
	round(hole, 2)

	for _, offset in { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } } do
		local tooth = plate(root, 11 + offset[1] * 8, 11 + offset[2] * 8, 3, 3, color)
		round(tooth, 1)
		outline(tooth, Theme.Color.outline, 1)
	end
end

--- Ascend. A chevron over a floor: the one gesture in the game that means
--- "everything resets upward".
local function ascend(root: Frame, color: Color3)
	for index, y in { 6, 12 } do
		local left = plate(root, 5, y, 8, 3, color)
		left.Rotation = -45
		round(left, 1)
		outline(left, Theme.Color.outline, 1.5)
		local right = plate(root, 12, y, 8, 3, color)
		right.Rotation = 45
		round(right, 1)
		outline(right, Theme.Color.outline, 1.5)
		_ = index
	end
	local floor = plate(root, 5, 20, 14, 2, color)
	round(floor, 1)
end

--- Daily. A calendar with a lit stamp: the day you have not claimed.
local function daily(root: Frame, color: Color3)
	local body = plate(root, 4, 6, 16, 15, color)
	round(body, 2)
	outline(body, Theme.Color.outline, 2)

	local head = plate(root, 4, 6, 16, 5, color:Lerp(Theme.Color.outline, 0.4))
	round(head, 2)
	outline(head, Theme.Color.outline, 1.5)

	for _, x in { 8, 16 } do
		local ring = plate(root, x, 3, 2, 5, Theme.Color.outline)
		round(ring, 1)
	end

	local stamp = plate(root, 9, 13, 6, 5, Theme.Color.ink)
	round(stamp, 1)
end

--- Trade. Two arrows crossing: out and back, which is what a trade is.
local function trade(root: Frame, color: Color3)
	local top = plate(root, 4, 8, 14, 3, color)
	round(top, 1)
	outline(top, Theme.Color.outline, 1.5)
	local topHead = plate(root, 15, 5, 6, 9, color)
	topHead.Rotation = 45
	round(topHead, 1)
	outline(topHead, Theme.Color.outline, 1.5)

	local bottom = plate(root, 6, 14, 14, 3, color)
	round(bottom, 1)
	outline(bottom, Theme.Color.outline, 1.5)
	local bottomHead = plate(root, 3, 11, 6, 9, color)
	bottomHead.Rotation = 45
	round(bottomHead, 1)
	outline(bottomHead, Theme.Color.outline, 1.5)
end

--- Builds one icon onto `parent` and returns the scaled canvas. Caller positions
--- it; the canvas is 24x24 in its own space and `size` after the UIScale.
function Icons.build(parent: GuiObject, kind: string, size: number, color: Color3): Frame
	local root = canvas(parent, size)
	if kind == "guide" then
		guide(root, color)
	elseif kind == "feedback" then
		feedback(root, color)
	elseif kind == "codex" then
		codex(root, color)
	elseif kind == "boards" then
		boards(root, color)
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
	end
	return root
end

return Icons
