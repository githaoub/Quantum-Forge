--!strict
-- The crate ceremony: a black scrim over the whole game, one stage in the
-- middle, and the crates the player just bought.
--
-- The page is the browser. This is the purchase. Every rail, tab and number is
-- dimmed behind a scrim; the models are the only thing on screen.
--
-- A pull of three mounts three crates, a pull of ten mounts ten. One click opens
-- one crate, with the same ring-and-sparks burst the anvil answers a strike
-- with. When the rack is empty the server copy lands in the same stage.
--
-- Text is deliberately sparse: pool above, click prompt below, the copy's name
-- and one stat line after the reveal. The model is the announcement.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local NumberUtil = require(Shared:WaitForChild("NumberUtil"))
local ForgeConfig = require(Shared:WaitForChild("ForgeConfig"))
local BladeRegistry = require(Shared:WaitForChild("BladeRegistry"))
local ModifierConfig = require(Shared:WaitForChild("ModifierConfig"))
local Types = require(Shared:WaitForChild("Types"))

local Theme = require(script.Parent.Theme)
local UiKit = require(script.Parent.UiKit)
local StateStore = require(script.Parent.StateStore)
local Sfx = require(script.Parent.Sfx)
local Vfx = require(script.Parent.Vfx)
local Haptics = require(script.Parent.Haptics)
local CratePreview = require(script.Parent.CratePreview)
local BladePreview = require(script.Parent.BladePreview)
local StageBackdrop = require(script.Parent.StageBackdrop)

local CrateReveal = {}

-- ---------------------------------------------------------------------------
-- Geometry
-- ---------------------------------------------------------------------------

local ANSWER_TIMEOUT = 8
local SEALED_HOLD = 0.62
local RESULT_LOCK = 0.55

local STAGE_W = 1080
local STAGE_H = 596
local STAGE_Y = 0.5306
local VIEW_H = 420
--- A batch result trades 64px of blade viewport for the copy rail. The single
--- result keeps the taller stage because there is nothing to list.
local RESULT_VIEW_H = 356
local PIP_MAX_W = 320

local RAIL_W = 980
local CHIP_H = 58
local CHIP_GAP = 6
local CHIP_MAX_W = 92

local ACTION_W = 260
local ACTION_H = 50

--- Rays behind the blade. Twelve thin frames rotated around one anchor; cheap
--- enough to keep mounted, hidden until a result needs them.
local RAY_COUNT = 9
local RAY_LENGTH = 360
local RAY_SPREAD = 138

local RARITY_COLOR: { [string]: Color3 } = {
	Scrap = Color3.fromRGB(168, 130, 96),
	Forged = Color3.fromRGB(176, 188, 202),
	Astral = Color3.fromRGB(122, 226, 255),
	Void = Color3.fromRGB(198, 132, 255),
	Quantum = Color3.fromRGB(132, 255, 208),
}

local VARIANT_RANK: { [string]: number } = {
	standard = 1,
	tempered = 2,
	overclocked = 3,
	void = 4,
	prismatic = 5,
}

local RARITY_RANK: { [string]: number } = {
	Scrap = 1,
	Forged = 2,
	Astral = 3,
	Void = 4,
	Quantum = 5,
}

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local root: TextButton? = nil
local stage: Frame? = nil
local stageScale: UIScale? = nil
local bloom: StageBackdrop.Handle? = nil
local canvasScale: UIScale? = nil
local viewport: ViewportFrame? = nil
local flash: Frame? = nil
local topLabel: TextLabel? = nil
local mainLabel: TextLabel? = nil
local subLabel: TextLabel? = nil
local pipsHost: Frame? = nil
local action: TextButton? = nil
local actionLabel: TextLabel? = nil
local railHost: Frame? = nil
local rayHost: Frame? = nil
local beam: Frame? = nil
local beamCore: Frame? = nil
local vignetteLeft: Frame? = nil
local vignetteRight: Frame? = nil
local vignetteTop: Frame? = nil
local vignetteBottom: Frame? = nil

local crateHandle: CratePreview.Handle? = nil
local bladeCleanup: (() -> ())? = nil
local dustCleanup: (() -> ())? = nil
local orbit: any = nil

local phase = "closed"
local token = 0
local currentCrate: ForgeConfig.Tier? = nil
local currentBatch = 1
local landed = false
local opened = 0
local lastStrike = 0
local pending: Types.FeedEvent? = nil
local onExit: (() -> ())? = nil
local unsubscribe: (() -> ())? = nil
local resultRank = 1
local resultReadyAt = 0
local rayConnection: RBXScriptConnection? = nil

local function bladeOf(id: string?): BladeRegistry.Blade?
	if id == nil then
		return nil
	end
	return BladeRegistry.get(id)
end

local function rarityColorOf(blade: BladeRegistry.Blade?): Color3
	if blade == nil then
		return Theme.Color.text
	end
	return RARITY_COLOR[blade.rarity] or Theme.Color.text
end

-- ---------------------------------------------------------------------------
-- Stage light
-- ---------------------------------------------------------------------------

--- Paints a full-bleed wash behind the ceremony.
---
--- Every band inside `StageBackdrop` is exactly as large as the frame it is
--- painted on, so the edges of the gradient land on the edge of that frame. In a
--- card that edge is hidden by the border; here the frame is the whole screen,
--- so the edge is off-screen and the wash has no boundary at all. That is the
--- difference between this and the crossed bands the first pass drew, which
--- ended in mid-air and read as brown rectangles.
local function paintBackdrop(parent: Frame): StageBackdrop.Handle
	local wash = UiKit.create("Frame", {
		Name = "Wash",
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
	}) :: Frame
	wash.Parent = parent
	return StageBackdrop.paint(wash, {
		warm = Theme.Color.quantum,
		cool = Theme.Color.slate,
		accent = Theme.Color.quantum,
		radius = 0,
		zIndex = 1,
		depth = 0.87,
	})
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------

--- Leaves the ceremony. The flash is already at full white when the scrim drops,
--- so the cut from the overlay back to the page is hidden by the same effect that
--- celebrates the claim. A close that is a hard `Visible = false` is the one
--- frame every player notices.
local function claim()
	if phase ~= "result" then
		return
	end
	if os.clock() < resultReadyAt then
		return
	end
	local crate = currentCrate
	phase = "claiming"
	if action then
		action.Visible = false
	end
	if stage then
		Vfx.shake(stage, 7, 0.3)
	end
	if viewport then
		local color = if crate then crate.accent else Theme.Color.gold
		Vfx.shockwave(viewport, color, {
			size = 120,
			spread = 4.0,
			duration = 0.45,
			thickness = 4,
		})
		Vfx.sparks(viewport, color, 18, 1.2)
		Vfx.burst(viewport, color, 1.2 + resultRank * 0.06)
	end
	if flash then
		flash.BackgroundColor3 = Theme.Color.white
		flash.BackgroundTransparency = 0.2
		UiKit.tween(flash, 0.3, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
	end
	-- The VFX wash lives above the scrim, so it is still on screen one beat
	-- after `close()` hides the ceremony. That overlap is what hides the cut.
	Vfx.flash(Theme.Color.white, 0.6)
	if stageScale then
		UiKit.tween(stageScale, 0.22, { Scale = 1.05 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end
	Sfx.claim()
	Haptics.pulse(1, 0.18)
	local stamp = token
	task.delay(0.14, function()
		if stamp == token and phase == "claiming" then
			CrateReveal.close()
		end
	end)
end

local function buildStage(canvas: Frame)
	local button = UiKit.create("TextButton", {
		Name = "CrateReveal",
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Modal = true,
		-- Below `Vfx` (40) on purpose: the click ring and sparks are the anvil's
		-- own effect, and the scrim must not swallow them. Above the rail, HUD,
		-- notifications and the section pages.
		ZIndex = 38,
	}) :: TextButton
	button.Parent = canvas
	root = button

	bloom = paintBackdrop(button)

	-- Edge vignette. Four gradient panes on the scrim itself, above the wash and
	-- below the stage, so they darken the light without touching the type. The
	-- panes grow during the sealed hold: the room closes in before the reveal.
	local function edge(name: string, position: UDim2, size: UDim2, rotation: number): Frame
		local pane = UiKit.create("Frame", {
			Name = name,
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BorderSizePixel = 0,
			BackgroundTransparency = 0,
			Position = position,
			Size = size,
			ZIndex = 1,
		}) :: Frame
		local gradient = UiKit.create("UIGradient", {
			Rotation = rotation,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.55),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}) :: UIGradient
		gradient.Parent = pane
		pane.Parent = button
		return pane
	end
	vignetteLeft = edge("VignetteLeft", UDim2.fromOffset(0, 0), UDim2.new(0, 170, 1, 0), 0)
	vignetteRight = edge("VignetteRight", UDim2.new(1, -170, 0, 0), UDim2.fromOffset(170, 0), 180)
	vignetteTop = edge("VignetteTop", UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 110), 90)
	vignetteBottom = edge("VignetteBottom", UDim2.new(0, 0, 1, -110), UDim2.new(1, 0, 0, 110), 270)
	vignetteRight.Size = UDim2.new(0, 170, 1, 0)
	vignetteBottom.Position = UDim2.new(0, 0, 1, -110)

	local frame = UiKit.create("Frame", {
		Name = "Stage",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, STAGE_Y),
		Size = UDim2.fromOffset(STAGE_W, STAGE_H),
		ZIndex = 2,
	}) :: Frame
	frame.Parent = button
	stage = frame

	local scale = UiKit.create("UIScale", { Scale = 1 }) :: UIScale
	scale.Parent = frame
	stageScale = scale

	-- The light column. Hidden until the rack is empty; it is the "something is
	-- about to happen" line that a held beat needs, and it costs one frame.
	local column = UiKit.create("Frame", {
		Name = "Beam",
		BackgroundColor3 = Theme.Color.white,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(STAGE_W / 2, 0),
		Size = UDim2.fromOffset(4, VIEW_H + 80),
		ZIndex = 1,
	}) :: Frame
	local columnGradient = UiKit.create("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(0.72, 0.75),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}) :: UIGradient
	columnGradient.Parent = column
	column.Parent = frame
	beam = column

	local core = UiKit.create("Frame", {
		Name = "BeamCore",
		BackgroundColor3 = Theme.Color.white,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(STAGE_W / 2, 0),
		Size = UDim2.fromOffset(2, VIEW_H + 80),
		ZIndex = 1,
	}) :: Frame
	core.Parent = frame
	beamCore = core

	-- The ray fan. Twelve thin blades of light behind the result, rotated around
	-- one zero-size host so a slow spin is one property write per frame.
	local rays = UiKit.create("Frame", {
		Name = "Rays",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(STAGE_W / 2, 20 + VIEW_H / 2),
		Size = UDim2.fromOffset(0, 0),
		Visible = false,
		ZIndex = 1,
	}) :: Frame
	rays.Parent = frame
	rayHost = rays
	for index = 1, RAY_COUNT do
		local angle = -RAY_SPREAD / 2 + (index - 1) * (RAY_SPREAD / (RAY_COUNT - 1))
		-- Each ray hangs from a zero-size pivot. A GuiObject rotates around its
		-- own centre, so rotating the long frame directly swung its base away
		-- from the origin by half its length; the fan looked like it was lit
		-- from a different room. The pivot's centre *is* the origin.
		local pivot = UiKit.create("Frame", {
			Name = "RayPivot" .. index,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.fromOffset(0, 0),
			Rotation = angle,
			ZIndex = 1,
		}) :: Frame
		local ray = UiKit.create("Frame", {
			Name = "Ray",
			BackgroundColor3 = Theme.Color.white,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.fromOffset(2, RAY_LENGTH),
			ZIndex = 1,
		}) :: Frame
		local fade = UiKit.create("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.75, 0.75),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}) :: UIGradient
		fade.Parent = ray
		ray.Parent = pivot
		pivot.Parent = rays
	end

	local top = UiKit.label(frame, {
		text = "POOL 01 / 05",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Center,
	})
	top.Position = UDim2.fromOffset(0, 0)
	top.Size = UDim2.new(1, 0, 0, 16)
	top.ZIndex = 3
	topLabel = top

	local view = UiKit.create("ViewportFrame", {
		Name = "Preview",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.fromOffset(STAGE_W, VIEW_H),
		ZIndex = 2,
	}) :: ViewportFrame
	view.ClipsDescendants = true
	view.Parent = frame
	viewport = view

	local main = UiKit.label(frame, {
		text = "BREACHING",
		size = Theme.Text.Title,
		font = Theme.Font.Black,
		color = Theme.Color.text,
		align = Enum.TextXAlignment.Center,
	})
	main.Position = UDim2.fromOffset(0, VIEW_H + 30)
	main.Size = UDim2.new(1, -40, 0, 40)
	main.ZIndex = 3
	main.TextTruncate = Enum.TextTruncate.AtEnd
	mainLabel = main

	local sub = UiKit.label(frame, {
		text = "",
		size = Theme.Text.Small,
		font = Theme.Font.Label,
		color = Theme.Color.textSecondary,
		align = Enum.TextXAlignment.Center,
		rich = true,
	})
	sub.Position = UDim2.fromOffset(0, VIEW_H + 70)
	sub.Size = UDim2.new(1, -40, 0, 20)
	sub.ZIndex = 3
	subLabel = sub

	local pips = UiKit.create("Frame", {
		Name = "Pips",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset((STAGE_W - PIP_MAX_W) / 2, VIEW_H + 96),
		Size = UDim2.fromOffset(PIP_MAX_W, 10),
		ZIndex = 3,
	}) :: Frame
	pips.Parent = frame
	pipsHost = pips

	-- Copy rail. A batch result lists every copy the player paid for, not just
	-- the one that won: nine invisible swords is the difference between a
	-- ten-pull and ten singles.
	local rail = UiKit.create("Frame", {
		Name = "CopyRail",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(STAGE_W / 2, VIEW_H + 118),
		Size = UDim2.fromOffset(RAIL_W, CHIP_H),
		Visible = false,
		ZIndex = 3,
	}) :: Frame
	rail.Parent = frame
	railHost = rail

	local wash = UiKit.create("Frame", {
		Name = "Flash",
		BackgroundColor3 = Theme.Color.white,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
	}) :: Frame
	wash.Parent = button
	flash = wash

	local footer = UiKit.create("TextButton", {
		Name = "Collect",
		BackgroundColor3 = Theme.Color.starMatter,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, STAGE_H - 68),
		Size = UDim2.fromOffset(ACTION_W, ACTION_H),
		Visible = false,
		ZIndex = 4,
	}) :: TextButton
	UiKit.corner(footer, Theme.Radius.md)
	UiKit.stroke(footer, Theme.Color.outline, Theme.Stroke.thin, 0)
	footer.Parent = frame
	action = footer

	local label = UiKit.label(footer, {
		text = "COLLECT",
		size = Theme.Text.Subheading,
		font = Theme.Font.Black,
		color = Theme.onColor(Theme.Color.starMatter),
		align = Enum.TextXAlignment.Center,
	})
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 5
	actionLabel = label

	UiKit.track(footer, footer.MouseEnter:Connect(function()
		if footer.Visible then
			Sfx.hover()
		end
	end))
	UiKit.track(footer, footer.Activated:Connect(function()
		if phase == "failed" then
			CrateReveal.close()
		else
			claim()
		end
	end))

	UiKit.track(button, button.Activated:Connect(function()
		if phase ~= "crate" or not landed then
			return
		end
		local handle = orbit
		if handle ~= nil and handle.dragTravel > 8 then
			handle.dragTravel = 0
			return
		end
		CrateReveal.strike()
	end))
end

-- ---------------------------------------------------------------------------
-- Paint
-- ---------------------------------------------------------------------------

local function clearPips()
	local host = pipsHost
	if host == nil then
		return
	end
	for _, child in host:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function paintPips(total: number, filled: number, colors: { Color3 }?)
	local host = pipsHost
	if host == nil then
		return
	end
	clearPips()
	if total <= 0 then
		return
	end
	local gap = 8
	local width = math.min(18, math.floor((PIP_MAX_W - gap * (total - 1)) / total))
	local height = 10
	local totalWidth = total * width + gap * (total - 1)
	local left = (PIP_MAX_W - totalWidth) / 2
	for index = 1, total do
		local pip = UiKit.create("Frame", {
			BackgroundColor3 = if colors and colors[index] then colors[index] elseif index <= filled then Theme.Color.starMatter else Theme.Color.strokeBright,
			BackgroundTransparency = if colors then 0 elseif index <= filled then 0 else 0.5,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(left + (index - 1) * (width + gap), 0),
			Size = UDim2.fromOffset(width, height),
			ZIndex = 4,
		}) :: Frame
		UiKit.corner(pip, 2)
		pip.Parent = host
	end
end

local function clearRail()
	local host = railHost
	if host == nil then
		return
	end
	for _, child in host:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	host.Visible = false
end

local function stopRays()
	if rayConnection then
		rayConnection:Disconnect()
		rayConnection = nil
	end
	if rayHost then
		rayHost.Visible = false
		rayHost.Rotation = 0
	end
end

local function startRays(color: Color3, rank: number)
	local host = rayHost
	if host == nil or Theme.reducedMotion() then
		return
	end
	host.Visible = true
	host.Rotation = 0
	local index = 0
	for _, pivot in host:GetChildren() do
		local ray = pivot:FindFirstChild("Ray")
		if ray and ray:IsA("Frame") then
			index += 1
			ray.BackgroundColor3 = if index % 3 == 1 then color else Theme.Color.white
			ray.BackgroundTransparency = if rank >= 4 then 0.5 else 0.72
		end
	end
	if rayConnection then
		rayConnection:Disconnect()
	end
	-- A fan that turns a full circle is a pinwheel; a few degrees of sway reads
	-- as light through a dusty room.
	local clock = 0
	rayConnection = RunService.Heartbeat:Connect(function(dt: number)
		if host.Parent == nil or not host.Visible then
			return
		end
		clock += dt
		host.Rotation = math.sin(clock * 0.7) * 4
	end)
end

--- The stage has two heights: the crate phase and the single result use the full
--- 420px viewport, a batch result gives 64px of it back to the copy rail.
local function layoutStage(batch: number, isResult: boolean)
	local multi = isResult and batch > 1
	local viewH = if multi then RESULT_VIEW_H else VIEW_H
	if viewport then
		viewport.Size = UDim2.fromOffset(STAGE_W, viewH)
	end
	if mainLabel then
		mainLabel.Position = UDim2.fromOffset(0, viewH + 30)
	end
	if subLabel then
		subLabel.Position = UDim2.fromOffset(0, viewH + 70)
	end
	if pipsHost then
		pipsHost.Position = UDim2.fromOffset((STAGE_W - PIP_MAX_W) / 2, viewH + 96)
	end
	if railHost then
		railHost.Position = UDim2.new(0.5, 0, 0, viewH + 118)
	end
	if rayHost then
		rayHost.Position = UDim2.fromOffset(STAGE_W / 2, 20 + viewH / 2)
	end
	if beam then
		beam.Size = UDim2.fromOffset(beam.Size.X.Offset, viewH + 80)
	end
	if beamCore then
		beamCore.Size = UDim2.fromOffset(beamCore.Size.X.Offset, viewH + 80)
	end
	if action then
		action.Position = UDim2.new(0.5, 0, 0, if multi then viewH + 184 else STAGE_H - 68)
	end
end

--- Lists every copy in a batch result. The winning copy is gold; the rest carry
--- their rarity. Chips stagger in left to right so the row is read, not just
--- seen, and the last one lands with the collect key.
local function paintRail(copies: { Types.ForgedCopy }, bestIndex: number)
	clearRail()
	local host = railHost
	if host == nil or #copies <= 1 then
		return
	end
	host.Visible = true
	local count = #copies
	local width = math.min(CHIP_MAX_W, math.floor((RAIL_W - CHIP_GAP * (count - 1)) / count))
	local total = count * width + CHIP_GAP * (count - 1)
	local left = (RAIL_W - total) / 2

	for index, copy in copies do
		local copyBlade = bladeOf(copy.blade)
		local isBest = index == bestIndex
		local color = if isBest then Theme.Color.gold else rarityColorOf(copyBlade)
		local chip = UiKit.create("Frame", {
			Name = "Copy" .. index,
			BackgroundColor3 = if isBest then Theme.Color.panelRaised else Theme.Color.panelSunken,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(left + (index - 1) * (width + CHIP_GAP), 0),
			Size = UDim2.fromOffset(width, CHIP_H),
			ZIndex = 3,
		}) :: Frame
		UiKit.corner(chip, Theme.Radius.sm)
		UiKit.stroke(chip, color, if isBest then Theme.Stroke.bold else Theme.Stroke.thin, if isBest then 0.1 else 0.5)

		local bar = UiKit.create("Frame", {
			BackgroundColor3 = color,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -8, 0, 3),
			Position = UDim2.fromOffset(4, 4),
			ZIndex = 4,
		}) :: Frame
		UiKit.corner(bar, 2)
		bar.Parent = chip

		local name = UiKit.label(chip, {
			text = string.upper(if copyBlade then copyBlade.name else "A COPY"),
			size = Theme.Text.Tiny,
			font = Theme.Font.Black,
			color = if isBest then Theme.Color.text else Theme.Color.textSecondary,
			align = Enum.TextXAlignment.Center,
			wrap = true,
		})
		name.Position = UDim2.fromOffset(4, 8)
		name.Size = UDim2.new(1, -8, 0, 30)
		name.TextYAlignment = Enum.TextYAlignment.Center
		name.ZIndex = 4

		local tag = UiKit.label(chip, {
			text = if isBest then "BEST" else string.upper(if copyBlade then copyBlade.rarity else "SCRAP"),
			size = Theme.Text.Tiny,
			font = Theme.Font.Numeric,
			color = color,
			align = Enum.TextXAlignment.Center,
		})
		tag.Position = UDim2.fromOffset(4, 38)
		tag.Size = UDim2.new(1, -8, 0, 14)
		tag.ZIndex = 4

		chip.Parent = host
		local delay = (index - 1) * 0.035
		task.delay(delay, function()
			if chip.Parent == nil then
				return
			end
			UiKit.tween(chip, 0.16, { BackgroundTransparency = if isBest then 0 else 0.1 }, Enum.EasingStyle.Quad)
			UiKit.tween(bar, 0.2, { BackgroundTransparency = 0 }, Enum.EasingStyle.Quad)
		end)
	end
end

local function paintCrate(crate: ForgeConfig.Tier, batch: number)
	clearRail()
	stopRays()
	layoutStage(batch, false)
	if beam then
		beam.BackgroundTransparency = 1
		beam.Size = UDim2.fromOffset(4, VIEW_H + 80)
	end
	if beamCore then
		beamCore.BackgroundTransparency = 1
		beamCore.Size = UDim2.fromOffset(2, VIEW_H + 80)
	end
	if topLabel then
		topLabel.Text = string.format("POOL %02d / %02d  ·  %s", crate.tier, #ForgeConfig.Tiers, string.upper(crate.name))
	end
	if mainLabel then
		mainLabel.Text = "BREACHING"
		mainLabel.TextColor3 = Theme.Color.text
	end
	if subLabel then
		subLabel.Text = string.format("0 / %d", batch)
		subLabel.TextColor3 = Theme.Color.textSecondary
	end
	paintPips(batch, 0)
end

local function paintResult(result: Types.FeedEvent, crate: ForgeConfig.Tier)
	local blade = bladeOf(result.blade)
	local variant = ForgeConfig.variant(if result.variant and result.variant ~= "" then result.variant else ForgeConfig.StandardVariant)
	local rarity = if blade then blade.rarity else "Scrap"
	local rarityColor = rarityColorOf(blade)
	local batch = math.max(1, math.floor(result.batch or 1))

	if topLabel then
		topLabel.Text = if batch > 1
			then string.format("BEST OF %d  ·  %s", batch, string.upper(crate.name))
			else "JUST FORGED"
		topLabel.TextColor3 = if batch > 1 then Theme.Color.gold else Theme.Color.textFaint
	end
	if mainLabel then
		local display = if blade
			then ModifierConfig.displayName(blade.name, result.prefix or "", result.suffix or "")
			else "A COPY"
		mainLabel.Text = string.upper(display)
		mainLabel.TextColor3 = Theme.Color.text
		mainLabel.TextSize = if #display > 26 then Theme.Text.Heading else Theme.Text.Title
	end
	if subLabel then
		local pieces = {
			string.format('<font color="#%s">%s</font>', rarityColor:ToHex(), string.upper(rarity)),
			string.upper(variant.name),
		}
		if result.power then
			table.insert(pieces, string.format("%s POWER", NumberUtil.abbreviate(result.power)))
		end
		if result.equipped == true then
			table.insert(pieces, "EQUIPPED")
		end
		subLabel.Text = table.concat(pieces, "  ·  ")
		subLabel.TextColor3 = Theme.Color.textSecondary
	end

	local copies = result.results
	local colors: { Color3 } = {}
	local bestMarked = false
	local bestIndex = 0
	for index, copy in copies or {} do
		local copyBlade = bladeOf(copy.blade)
		local isBest = not bestMarked and copy.blade == result.blade and (result.power == nil or copy.power == result.power)
		if isBest then
			bestMarked = true
			bestIndex = index
		end
		colors[index] = if isBest then Theme.Color.gold else rarityColorOf(copyBlade)
	end
	local list = copies or {}
	layoutStage(batch, true)
	paintPips(if #list > 0 then #list else batch, batch, colors)
	paintRail(list, bestIndex)

	if actionLabel then
		actionLabel.Text = if batch > 1 then string.format("COLLECT %d", batch) else "COLLECT"
	end
end

-- ---------------------------------------------------------------------------
-- Runtime
-- ---------------------------------------------------------------------------

local function clearViewport()
	if dustCleanup then
		dustCleanup()
		dustCleanup = nil
	end
	if bladeCleanup then
		bladeCleanup()
		bladeCleanup = nil
	end
	if crateHandle then
		crateHandle.destroy()
		crateHandle = nil
	end
	if viewport then
		for _, child in viewport:GetChildren() do
			child:Destroy()
		end
	end
	orbit = nil
end

local function reveal(result: Types.FeedEvent)
	if phase == "result" or phase == "closed" or phase == "claiming" then
		return
	end
	phase = "result"
	landed = true
	local crate = currentCrate
	if crate == nil then
		return
	end

	stopRays()
	clearViewport()
	local blade = bladeOf(result.blade)
	local variant = ForgeConfig.variant(if result.variant and result.variant ~= "" then result.variant else ForgeConfig.StandardVariant)
	local rarityColor = rarityColorOf(blade)
	local rank = math.max(VARIANT_RANK[variant.id] or 1, if blade then (RARITY_RANK[blade.rarity] or 1) else 1)
	resultRank = rank
	local theme = Theme.tierBackdrop(crate.tier)

	if bloom then
		bloom.setColors(variant.color, theme.cool, rarityColor)
	end
	paintResult(result, crate)

	-- The collect key arrives after the reveal has been read, not on the same
	-- frame as the flash. A key that is already under the thumb when the screen
	-- changes is how a player skips the thing they paid for.
	if action then
		action.Visible = false
		action.BackgroundColor3 = crate.accent
	end
	if actionLabel then
		actionLabel.TextColor3 = Theme.onColor(crate.accent)
	end
	resultReadyAt = os.clock() + RESULT_LOCK
	local stamp = token
	task.delay(0.22, function()
		if stamp == token and phase == "result" and action then
			action.Visible = true
		end
	end)

	if viewport then
		viewport.Ambient = Color3.fromRGB(214, 216, 228)
		viewport.LightColor = Color3.fromRGB(255, 255, 255)
		viewport.LightDirection = Vector3.new(-0.55, -0.72, -0.42)
		viewport.BackgroundTransparency = 1
		if blade then
			bladeCleanup = BladePreview.mount(viewport, blade, variant.color, {
				surface = root,
				frameFill = 0.9,
				aimBias = 0,
				spin = 0,
			})
		end
	end

	if stageScale then
		stageScale.Scale = 1.08
		UiKit.tween(stageScale, Theme.Duration.slow, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end
	if flash then
		flash.BackgroundColor3 = rarityColor
		flash.BackgroundTransparency = 0.16
		UiKit.tween(flash, 0.5, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		if rank >= 4 and not Theme.reducedMotion() then
			task.delay(0.06, function()
				if flash.Parent then
					flash.BackgroundColor3 = Theme.Color.white
					flash.BackgroundTransparency = 0.22
					UiKit.tween(flash, 0.4, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
				end
			end)
		end
	end
	if stage then
		Vfx.shake(stage, 2.5 + rank * 1.2, 0.34)
	end
	if viewport then
		Vfx.shockwave(viewport, rarityColor, {
			size = 150,
			spread = 3.0,
			duration = 0.5,
			thickness = 5,
		})
		Vfx.sparks(viewport, rarityColor, 12 + rank, 1.2)
	end
	if beam then
		beam.BackgroundColor3 = crate.accent
		beam.BackgroundTransparency = 0.45
		beam.Size = UDim2.fromOffset(46, beam.Size.Y.Offset)
		UiKit.tween(beam, 0.55, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
	end
	if beamCore then
		beamCore.BackgroundColor3 = Theme.Color.white
		beamCore.BackgroundTransparency = 0.2
		beamCore.Size = UDim2.fromOffset(10, beamCore.Size.Y.Offset)
		UiKit.tween(beamCore, 0.4, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
	end
	if vignetteLeft then
		Theme.tween(vignetteLeft, 0.35, { Size = UDim2.new(0, 170, 1, 0) }, Enum.EasingStyle.Quad)
	end
	startRays(rarityColor, rank)

	Sfx.crateShatter()
	Sfx.result(rank)
	Haptics.pulse(0.85, 0.22)
end

local function tryReveal()
	if phase ~= "sealed" then
		return
	end
	if pending == nil then
		if mainLabel then
			mainLabel.Text = "SEALED"
			mainLabel.TextColor3 = Theme.Color.gold
		end
		return
	end
	local result = pending
	pending = nil
	reveal(result)
end

local function strike()
	local crate = currentCrate
	if phase ~= "crate" or crate == nil or not landed then
		return
	end
	-- One press, one crate. `Activated` can arrive twice for a synthetic
	-- press/release pair, and a double strike silently eats two crates out of a
	-- three pull. 120ms is under the fastest human double-tap and far above a
	-- duplicated event.
	local now = os.clock()
	if now - lastStrike < 0.12 then
		return
	end
	lastStrike = now
	opened += 1
	local index = opened
	if crateHandle and not crateHandle.open(index, crate.accent) then
		opened -= 1
		return
	end
	if crateHandle then
		crateHandle.knock(index, crate.accent)
	end
	local final = opened >= currentBatch
	Sfx.crateBreak(final)
	Haptics.pulse(if final then 0.6 else 0.22 + index * 0.05, if final then 0.1 else 0.055)

	-- The same answer the anvil gives: a ring at the cursor, sparks, a burst and
	-- a body check on the stage. The ziggurat of numbers is gone; this is one hit.
	if viewport then
		Vfx.shockwave(viewport, crate.accent, {
			size = 58,
			spread = 2.4,
			duration = 0.34,
			thickness = 3,
			at = Vfx.pointer(root),
		})
		Vfx.sparks(viewport, crate.accent, 10, 1.05)
		Vfx.burst(viewport, crate.accent, 0.8)
	end
	if stage then
		Vfx.shake(stage, 1.2 + index * 0.25, 0.14)
	end
	Sfx.rollTick(index)

	if subLabel then
		subLabel.Text = string.format("%d / %d", opened, currentBatch)
	end
	paintPips(currentBatch, opened)

	if opened < currentBatch then
		return
	end

	phase = "sealed"
	if mainLabel then
		mainLabel.Text = "SEALED"
		mainLabel.TextColor3 = Theme.Color.gold
	end
	if crateHandle then
		crateHandle.hover(crate.accent)
	end
	Sfx.rollTick(8)
	-- The held beat. Everything converges here: the column lights, the room
	-- darkens, the pad builds, and two heartbeats carry the silence. The server
	-- answer is already in hand; this is the pause before the screen admits it.
	if beam then
		beam.BackgroundColor3 = crate.accent
		beam.BackgroundTransparency = 0.7
		beam.Size = UDim2.fromOffset(8, beam.Size.Y.Offset)
		UiKit.tween(beam, 0.5, { BackgroundTransparency = 0.45, Size = UDim2.fromOffset(30, beam.Size.Y.Offset) }, Enum.EasingStyle.Quad)
	end
	if beamCore then
		beamCore.BackgroundColor3 = Theme.Color.white
		beamCore.BackgroundTransparency = 0.55
		beamCore.Size = UDim2.fromOffset(3, beamCore.Size.Y.Offset)
		UiKit.tween(beamCore, 0.5, { BackgroundTransparency = 0.2, Size = UDim2.fromOffset(12, beamCore.Size.Y.Offset) }, Enum.EasingStyle.Quad)
	end
	if vignetteLeft then
		Theme.tween(vignetteLeft, SEALED_HOLD, { Size = UDim2.new(0, 230, 1, 0) }, Enum.EasingStyle.Quad)
	end
	if vignetteRight then
		Theme.tween(vignetteRight, SEALED_HOLD, { Size = UDim2.new(0, 230, 1, 0) }, Enum.EasingStyle.Quad)
	end
	if vignetteTop then
		Theme.tween(vignetteTop, SEALED_HOLD, { Size = UDim2.new(1, 0, 0, 160) }, Enum.EasingStyle.Quad)
	end
	if vignetteBottom then
		Theme.tween(vignetteBottom, SEALED_HOLD, { Size = UDim2.new(1, 0, 0, 160) }, Enum.EasingStyle.Quad)
	end
	Sfx.riser(5)
	Sfx.heartbeat()
	local stamp = token
	task.delay(0.2, function()
		if stamp == token and phase == "sealed" then
			Sfx.heartbeat()
		end
	end)
	Haptics.build(3)
	task.delay(SEALED_HOLD, function()
		if stamp == token and phase == "sealed" then
			tryReveal()
		end
	end)
end

local function open(opts: {
	crate: ForgeConfig.Tier,
	batch: number,
	armed: boolean,
	onExit: (() -> ())?,
}): boolean
	if root == nil or stage == nil then
		return false
	end
	if phase ~= "closed" then
		CrateReveal.close()
	end
	token += 1
	local stamp = token
	phase = "crate"
	currentCrate = opts.crate
	currentBatch = math.clamp(math.floor(opts.batch), 1, 10)
	landed = false
	opened = 0
	pending = nil
	onExit = opts.onExit

	clearViewport()
	paintCrate(opts.crate, currentBatch)
	resultReadyAt = 0
	resultRank = 1
	if vignetteLeft then
		vignetteLeft.Size = UDim2.new(0, 170, 1, 0)
	end
	if vignetteRight then
		vignetteRight.Size = UDim2.new(0, 170, 1, 0)
	end
	if vignetteTop then
		vignetteTop.Size = UDim2.new(1, 0, 0, 110)
	end
	if vignetteBottom then
		vignetteBottom.Size = UDim2.new(1, 0, 0, 110)
	end
	if bloom then
		local theme = Theme.tierBackdrop(opts.crate.tier)
		bloom.setColors(opts.crate.accent, theme.cool, opts.crate.accent)
	end
	if stageScale then
		stageScale.Scale = 0.97
	end
	if flash then
		flash.BackgroundTransparency = 1
	end
	if action then
		action.Visible = false
	end

	root.Visible = true
	root.BackgroundTransparency = 1
	-- Total black. The ceremony is not a dialog over the page; it is the whole
	-- screen for as long as it lasts, and the only way back is to open the crates.
	UiKit.tween(root, 0.16, { BackgroundTransparency = 0 }, Enum.EasingStyle.Quad)
	if stageScale then
		UiKit.tween(stageScale, 0.24, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end

	if viewport then
		crateHandle = CratePreview.mount(viewport, opts.crate.shape, {
			count = currentBatch,
			surface = root,
			spin = 0,
			onOrbit = function(handle)
				orbit = handle
			end,
		})
		if crateHandle then
			crateHandle.play(opts.crate.accent, {
				onLanded = function()
					if stamp ~= token then
						return
					end
					landed = true
					if mainLabel then
						mainLabel.Text = "CLICK TO OPEN"
						mainLabel.TextColor3 = Theme.Color.text
					end
					Sfx.crateLand()
				end,
			}, true)
		end
	end

	Sfx.roll()
	dustCleanup = Vfx.ambientEmbers(viewport, {
		count = 16,
		color = Theme.Color.slate,
		floor = 0,
	})
	task.delay(ANSWER_TIMEOUT, function()
		if stamp == token and pending == nil and phase ~= "closed" and phase ~= "result" then
			CrateReveal.fail("THE VAULT DID NOT ANSWER")
		end
	end)
	return true
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Sizes the scrim to the real viewport, not to the canvas box.
---
--- Two offsets are in play. The canvas is a fixed 1686x720 design sheet, scaled
--- to fit, so it stops short of the window; and GUI space starts at the top bar
--- inset while the viewport starts at the actual top of the screen. The scrim is
--- measured in canvas units from the screen corner instead: it is pushed up by
--- the inset and made tall enough to cover the window plus that inset. Roblox's
--- own top bar is drawn by CoreGui and cannot be covered by a game GUI; this
--- reaches the last pixel a game GUI can reach and stops there.
function CrateReveal.fitScreen()
	local button = root
	if button == nil then
		return
	end
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local scale = if canvasScale and canvasScale.Scale > 0 then canvasScale.Scale else 1
	local size = camera.ViewportSize
	local inset = GuiService:GetGuiInset()
	button.Position = UDim2.fromOffset(-inset.X / scale, -inset.Y / scale)
	button.Size = UDim2.fromOffset(
		math.ceil((size.X + inset.X) / scale),
		math.ceil((size.Y + inset.Y) / scale)
	)
end

function CrateReveal.init(canvas: Frame)
	if root then
		return
	end
	buildStage(canvas)
	canvasScale = canvas:FindFirstChildOfClass("UIScale")
	CrateReveal.fitScreen()
	if canvasScale then
		canvasScale:GetPropertyChangedSignal("Scale"):Connect(function()
			CrateReveal.fitScreen()
		end)
	end
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			CrateReveal.fitScreen()
		end)
	end
	unsubscribe = StateStore.onEvent(function(event: Types.FeedEvent)
		if event.kind ~= "forged" then
			return
		end
		if phase ~= "crate" and phase ~= "sealed" then
			return
		end
		CrateReveal.deliver(event)
	end)
end

function CrateReveal.open(opts: {
	crate: ForgeConfig.Tier,
	batch: number,
	armed: boolean,
	onExit: (() -> ())?,
}): boolean
	return open(opts)
end

--- The server answer. Held until the last crate is opened, so a fast server
--- cannot cut the ceremony short.
function CrateReveal.deliver(event: Types.FeedEvent): boolean
	if phase ~= "crate" and phase ~= "sealed" then
		return false
	end
	local crate = currentCrate
	if crate == nil then
		return false
	end
	if event.crate ~= nil and event.crate ~= crate.id then
		return false
	end
	pending = event
	if phase == "sealed" then
		tryReveal()
	end
	return true
end

function CrateReveal.strike()
	strike()
end

function CrateReveal.fail(message: string)
	if phase == "closed" or phase == "result" then
		return
	end
	phase = "failed"
	if crateHandle then
		crateHandle.stop()
	end
	if topLabel then
		topLabel.Text = "THE VAULT"
		topLabel.TextColor3 = Theme.Color.warn
	end
	if mainLabel then
		mainLabel.Text = message
		mainLabel.TextColor3 = Theme.Color.warn
	end
	if subLabel then
		subLabel.Text = "THE ROLL WAS NOT CHARGED"
		subLabel.TextColor3 = Theme.Color.textFaint
	end
	paintPips(0, 0)
	if action then
		action.Visible = true
		action.BackgroundColor3 = Theme.Color.panelRaised
	end
	if actionLabel then
		actionLabel.Text = "BACK TO POOL"
		actionLabel.TextColor3 = Theme.Color.text
	end
	Sfx.error()
end

function CrateReveal.close()
	if root == nil or phase == "closed" then
		return
	end
	token += 1
	phase = "closed"
	pending = nil
	landed = false
	opened = 0
	resultReadyAt = 0
	stopRays()
	clearRail()
	if vignetteLeft then
		vignetteLeft.Size = UDim2.new(0, 170, 1, 0)
	end
	if vignetteRight then
		vignetteRight.Size = UDim2.new(0, 170, 1, 0)
	end
	if vignetteTop then
		vignetteTop.Size = UDim2.new(1, 0, 0, 110)
	end
	if vignetteBottom then
		vignetteBottom.Size = UDim2.new(1, 0, 0, 110)
	end
	if beam then
		beam.BackgroundTransparency = 1
	end
	if beamCore then
		beamCore.BackgroundTransparency = 1
	end
	root.Visible = false
	clearViewport()
	Haptics.stop()
	local callback = onExit
	onExit = nil
	if callback then
		callback()
	end
end

function CrateReveal.isOpen(): boolean
	return phase ~= "closed"
end

--- Studio seam: show a copy without charging or rolling.
function CrateReveal.preview(crate: ForgeConfig.Tier, event: Types.FeedEvent): boolean
	if root == nil then
		return false
	end
	if phase ~= "closed" then
		CrateReveal.close()
	end
	open({
		crate = crate,
		batch = math.max(1, math.floor(event.batch or 1)),
		armed = false,
	})
	if phase == "closed" then
		return false
	end
	phase = "sealed"
	pending = event
	landed = true
	tryReveal()
	return true
end

function CrateReveal.destroy()
	onExit = nil
	if unsubscribe then
		unsubscribe()
		unsubscribe = nil
	end
	if root then
		CrateReveal.close()
		root:Destroy()
		root = nil
	end
	stage = nil
	stageScale = nil
	bloom = nil
	viewport = nil
	flash = nil
	topLabel = nil
	mainLabel = nil
	subLabel = nil
	pipsHost = nil
	action = nil
	actionLabel = nil
	currentCrate = nil
end

return CrateReveal
