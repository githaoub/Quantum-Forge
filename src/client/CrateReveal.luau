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
--- One claim per copy. Short enough to tap through a ten-pull, long enough that
--- a held mouse cannot skip the blade under it.
local CLAIM_LOCK = 0.3

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

--- The burst behind the blade: eight stretched sparkle needles around a soft
--- disc and one four-point star. Soft sprites instead of flat rectangles,
--- because a hard 2px line reads as a debug drawing no matter how it is tinted.
local BURST_NEEDLES = 8
local NEEDLE_LENGTH = 380
local NEEDLE_SPREAD = 140

--- Proven-present client textures. All three resolve offline with
--- `ContentProvider:PreloadAsync`, so the ceremony never depends on an upload.
--- `whiteCircle.png` is a hard flat disc and is not used: a glow needs a
--- falloff, and `smoke_main` is the only proven-present texture with one.
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SOFT = "rbxasset://textures/particles/smoke_main.dds"

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
local halo: ImageLabel? = nil
local star: ImageLabel? = nil
local beamHost: Frame? = nil
local beamWash: ImageLabel? = nil
local beamCore: ImageLabel? = nil
local beamSource: ImageLabel? = nil
local beamValue: NumberValue? = nil
local beamColor = Theme.Color.white
local floorGlow: ImageLabel? = nil
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
local strikes = 0
local strikeTotal = 6
local lastStrike = 0
local pending: Types.FeedEvent? = nil
local onExit: (() -> ())? = nil
local unsubscribe: (() -> ())? = nil
local resultRank = 1
local resultReadyAt = 0
local rayConnection: RBXScriptConnection? = nil

--- The result is a queue now: every copy gets its own claim. `claimQueue` holds
--- copy indices in claim order (best first), `claimCursor` counts the claimed
--- ones, and the rail is painted in that same order so the gold outline walks
--- left to right instead of jumping to whichever copy happened to roll last.
local resultCopies: { Types.ForgedCopy } = {}
local claimQueue: { number } = {}
local claimCursor = 0
local railChips: { [number]: Frame } = {}
local railClaimed: { [number]: boolean } = {}
local resultEvent: Types.FeedEvent? = nil

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
-- Sprites
-- ---------------------------------------------------------------------------

--- A soft sprite, centred on `position` inside its parent.
---
--- The ceremony used to paint light with bare Frames: hard-edged rectangles
--- with a one-axis gradient. That is why the column read as "a Roblox part" and
--- the ray fan as "random lines". These three textures ship with the client, so
--- they resolve offline and cannot fail the way an unuploaded asset can.
local function sprite(
	parent: Instance,
	name: string,
	image: string,
	size: UDim2,
	position: UDim2,
	transparency: number,
	color: Color3?,
	zIndex: number?
): ImageLabel
	local label = UiKit.create("ImageLabel", {
		Name = name,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = image,
		ImageColor3 = color or Theme.Color.white,
		ImageTransparency = transparency,
		ScaleType = Enum.ScaleType.Stretch,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = size,
		ZIndex = zIndex or 1,
	}) :: ImageLabel
	label.Parent = parent
	return label
end

--- Paints the light column from one 0..1 strength.
---
--- Four sprite layers move together: a wide smoke wash, a tight disc core, a
--- source halo at the top and the pool of light on the floor. One number drives
--- all of them so the wind-up cannot desynchronise into four tweens that land on
--- different frames.
local function paintBeam(color: Color3, strength: number)
	local s = math.clamp(strength, 0, 1)
	local host = beamHost
	if host then
		host.Visible = s > 0.01
	end
	if beamWash then
		beamWash.ImageColor3 = color
		beamWash.ImageTransparency = 1 - s * 0.5
		beamWash.Size = UDim2.fromOffset(160 + s * 260, beamWash.Size.Y.Offset)
	end
	if beamCore then
		beamCore.ImageColor3 = color
		beamCore.ImageTransparency = 1 - s * 1.15
		beamCore.Size = UDim2.fromOffset(10 + s * 34, beamCore.Size.Y.Offset)
	end
	if beamSource then
		local width = 80 + s * 220
		beamSource.ImageColor3 = color
		beamSource.ImageTransparency = 1 - s * 0.9
		beamSource.Size = UDim2.fromOffset(width, width)
	end
	if floorGlow then
		floorGlow.ImageColor3 = color
		floorGlow.ImageTransparency = 1 - s * 0.45
	end
end

--- Tweens the column to a strength. Colour snaps (a hue tween reads as a
--- colour-shifting bug), alpha and width ease.
local function beamTo(color: Color3, strength: number, duration: number, style: Enum.EasingStyle?)
	beamColor = color
	local value = beamValue
	if value == nil then
		return
	end
	if duration <= 0 then
		value.Value = strength
		return
	end
	Theme.tween(value, duration, { Value = strength }, style or Enum.EasingStyle.Quad)
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------

--- Leaves the ceremony. The flash is already at full white when the scrim drops,
--- so the cut from the overlay back to the page is hidden by the same effect that
--- celebrates the claim. A close that is a hard `Visible = false` is the one
--- frame every player notices.
local function claimOut()
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
	Sfx.claimAll()
	Haptics.pulse(1, 0.18)
	local stamp = token
	task.delay(0.14, function()
		if stamp == token and phase == "claiming" then
			CrateReveal.close()
		end
	end)
end

--- Assigned below, once the rail helpers exist. The footer button is built
--- before them, so it needs a stable upvalue rather than a forward local
--- function that would shadow the later definition.
local claimOne: () -> () = function() end

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

	-- The light column. A soft wash, a disc core and a source halo, all driven by
	-- one strength value. Hidden until the rack is empty.
	local column = UiKit.create("Frame", {
		Name = "Beam",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(STAGE_W / 2, 0),
		Size = UDim2.fromOffset(240, VIEW_H + 80),
		Visible = false,
		ZIndex = 1,
	}) :: Frame
	column.Parent = frame
	beamHost = column

	beamWash = sprite(column, "Wash", SOFT, UDim2.fromOffset(140, VIEW_H + 120), UDim2.fromOffset(120, (VIEW_H + 80) / 2), 1)
	beamCore = sprite(column, "Core", SOFT, UDim2.fromOffset(8, VIEW_H + 40), UDim2.fromOffset(120, (VIEW_H + 80) / 2), 1)
	beamCore.ZIndex = 2
	beamSource = sprite(column, "Source", SOFT, UDim2.fromOffset(70, 70), UDim2.fromOffset(120, 6), 1)
	beamSource.ZIndex = 2

	local value = Instance.new("NumberValue")
	value.Name = "BeamStrength"
	value.Value = 0
	value.Parent = button
	beamValue = value
	value:GetPropertyChangedSignal("Value"):Connect(function()
		paintBeam(beamColor, value.Value)
	end)

	-- The pool of light on the floor. It grounds the crate: without it the model
	-- floats in a black rectangle.
	floorGlow = sprite(frame, "FloorGlow", SOFT, UDim2.fromOffset(560, 160), UDim2.fromOffset(STAGE_W / 2, 20 + VIEW_H - 46), 1)

	-- The burst. Eight stretched sparkle needles on zero-size pivots, a soft
	-- halo and one four-point star. The star is the flare; the needles are the
	-- shafts; the halo is the light behind them.
	local burst = UiKit.create("Frame", {
		Name = "Burst",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(STAGE_W / 2, 20 + VIEW_H / 2),
		Size = UDim2.fromOffset(0, 0),
		Visible = false,
		ZIndex = 1,
	}) :: Frame
	burst.Parent = frame
	rayHost = burst

	halo = sprite(burst, "Halo", SOFT, UDim2.fromOffset(520, 520), UDim2.fromOffset(0, 0), 1)
	star = sprite(burst, "Star", SPARKLE, UDim2.fromOffset(760, 760), UDim2.fromOffset(0, 0), 1)
	for index = 1, BURST_NEEDLES do
		local angle = -NEEDLE_SPREAD / 2 + (index - 1) * (NEEDLE_SPREAD / (BURST_NEEDLES - 1))
		-- Each needle hangs from a zero-size pivot. A GuiObject rotates around
		-- its own centre, so rotating the long label directly would swing its
		-- base away from the origin by half its length.
		local pivot = UiKit.create("Frame", {
			Name = "NeedlePivot" .. index,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.fromOffset(0, 0),
			Rotation = angle,
			ZIndex = 1,
		}) :: Frame
		local needle = sprite(pivot, "Needle", SPARKLE, UDim2.fromOffset(30, NEEDLE_LENGTH), UDim2.fromOffset(0, 0), 1)
		needle.AnchorPoint = Vector2.new(0.5, 1)
		pivot.Parent = burst
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
			claimOne()
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
	railChips = {}
	railClaimed = {}
	host.Visible = false
end

local function stopRays()
	if rayConnection then
		rayConnection:Disconnect()
		rayConnection = nil
	end
	local host = rayHost
	if host == nil then
		return
	end
	host.Visible = false
	host.Rotation = 0
	if halo then
		halo.ImageTransparency = 1
	end
	if star then
		star.ImageTransparency = 1
		star.Rotation = 0
	end
	for _, pivot in host:GetChildren() do
		local needle = pivot:FindFirstChild("Needle")
		if needle and needle:IsA("ImageLabel") then
			needle.ImageTransparency = 1
		end
	end
end

local function startRays(color: Color3, rank: number)
	local host = rayHost
	if host == nil then
		return
	end
	host.Visible = true
	host.Rotation = 0

	local bright = rank >= 4
	local needleAlpha = if bright then 0.46 else 0.62
	local index = 0
	for _, pivot in host:GetChildren() do
		local needle = pivot:FindFirstChild("Needle")
		if needle and needle:IsA("ImageLabel") then
			index += 1
			needle.ImageColor3 = if index % 4 == 0 then Theme.Color.white else color
			needle.ImageTransparency = needleAlpha + (index % 3) * 0.05
			-- Different lengths keep the fan from reading as a perfect rake.
			local scale = 0.68 + ((index * 37) % 5) * 0.09
			needle.Size = UDim2.fromOffset(32 + (index % 3) * 9, NEEDLE_LENGTH * scale)
		end
	end
	if halo then
		halo.ImageColor3 = color
		halo.ImageTransparency = if bright then 0.74 else 0.88
		local haloSize = if bright then 640 else 520
		halo.Size = UDim2.fromOffset(haloSize, haloSize)
	end
	if star then
		local starSize = if bright then 880 else 720
		star.ImageColor3 = color
		star.ImageTransparency = if bright then 0.32 else 0.5
		star.Rotation = 0
		star.Size = UDim2.fromOffset(starSize, starSize)
	end
	if rayConnection then
		rayConnection:Disconnect()
	end
	if Theme.reducedMotion() then
		return
	end
	-- The star turns slowly, the halo breathes, and the whole fan sways a few
	-- degrees. A full spin reads as a pinwheel; this reads as light in a room.
	local clock = 0
	local haloBase = if bright then 640 else 520
	rayConnection = RunService.Heartbeat:Connect(function(dt: number)
		if host.Parent == nil or not host.Visible then
			return
		end
		clock += dt
		host.Rotation = math.sin(clock * 0.5) * 2.5
		if star then
			star.Rotation = (clock * 7) % 360
		end
		if halo then
			local size = haloBase * (1 + math.sin(clock * 1.7) * 0.03)
			halo.Size = UDim2.fromOffset(size, size)
		end
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
	if beamHost then
		beamHost.Size = UDim2.fromOffset(240, viewH + 80)
	end
	if beamWash then
		beamWash.Size = UDim2.fromOffset(beamWash.Size.X.Offset, viewH + 120)
		beamWash.Position = UDim2.fromOffset(120, (viewH + 80) / 2)
	end
	if beamCore then
		beamCore.Size = UDim2.fromOffset(beamCore.Size.X.Offset, viewH + 40)
		beamCore.Position = UDim2.fromOffset(120, (viewH + 80) / 2)
	end
	if floorGlow then
		floorGlow.Position = UDim2.fromOffset(STAGE_W / 2, 20 + viewH - 46)
	end
	if action then
		action.Position = UDim2.new(0.5, 0, 0, if multi then viewH + 184 else STAGE_H - 68)
	end
end

--- Lists every copy in claim order: the best first, then the rest in roll
--- order. The rail and the queue are the same list, so the gold outline can walk
--- left to right as copies leave instead of sitting on the last roll. The
--- winning copy keeps a gold tag; the rest carry their rarity.
local function paintRail(copies: { Types.ForgedCopy }, order: { number }, bestIndex: number)
	clearRail()
	local host = railHost
	if host == nil or #order <= 1 then
		return
	end
	host.Visible = true
	local count = #order
	local width = math.min(CHIP_MAX_W, math.floor((RAIL_W - CHIP_GAP * (count - 1)) / count))
	local total = count * width + CHIP_GAP * (count - 1)
	local left = (RAIL_W - total) / 2

	for position, copyIndex in order do
		local copy = copies[copyIndex]
		if copy then
			local copyBlade = bladeOf(copy.blade)
			local isBest = copyIndex == bestIndex
			local color = if isBest then Theme.Color.gold else rarityColorOf(copyBlade)
			local chip = UiKit.create("Frame", {
				Name = "Copy" .. position,
				BackgroundColor3 = if isBest then Theme.Color.panelRaised else Theme.Color.panelSunken,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(left + (position - 1) * (width + CHIP_GAP), 0),
				Size = UDim2.fromOffset(width, CHIP_H),
				ZIndex = 3,
			}) :: Frame
			UiKit.corner(chip, Theme.Radius.sm)
			local edge = UiKit.stroke(chip, color, if isBest then Theme.Stroke.bold else Theme.Stroke.thin, if isBest then 0.1 else 0.5)
			edge.Name = "Edge"

			local bar = UiKit.create("Frame", {
				Name = "Bar",
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
			name.Name = "Blade"
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
			tag.Name = "Tag"
			tag.Position = UDim2.fromOffset(4, 38)
			tag.Size = UDim2.new(1, -8, 0, 14)
			tag.ZIndex = 4

			-- The claim cursor. One chip carries the gold rail at a time, so the
			-- player can see which copy the key will take without reading a counter.
			local cursor = UiKit.create("Frame", {
				Name = "Cursor",
				BackgroundColor3 = Theme.Color.gold,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(6, CHIP_H - 4),
				Size = UDim2.new(1, -12, 0, 3),
				ZIndex = 4,
			}) :: Frame
			UiKit.corner(cursor, 2)
			cursor.Parent = chip

			chip.Parent = host
			railChips[copyIndex] = chip
			local delay = (position - 1) * 0.035
			task.delay(delay, function()
				if chip.Parent == nil then
					return
				end
				UiKit.tween(chip, 0.16, { BackgroundTransparency = if isBest then 0 else 0.1 }, Enum.EasingStyle.Quad)
				UiKit.tween(bar, 0.2, { BackgroundTransparency = 0 }, Enum.EasingStyle.Quad)
			end)
		end
	end
end

--- Moves the gold outline and the bottom rail to the copy the key will take
--- next. Inactive copies fall back to their rarity edge; claimed copies stay
--- grey so the row reads as a receipt.
local function markCursor(index: number?)
	for copyIndex, chip in railChips do
		local edge = chip:FindFirstChild("Edge")
		if edge and edge:IsA("UIStroke") then
			if copyIndex == index then
				edge.Color = Theme.Color.gold
				edge.Thickness = Theme.Stroke.bold
				edge.Transparency = 0
			elseif railClaimed[copyIndex] then
				edge.Color = Theme.Color.textFaint
				edge.Thickness = Theme.Stroke.thin
				edge.Transparency = 0.7
			else
				local bar = chip:FindFirstChild("Bar")
				edge.Color = if bar and bar:IsA("Frame") then bar.BackgroundColor3 else Theme.Color.outline
				edge.Thickness = Theme.Stroke.thin
				edge.Transparency = 0.5
			end
		end
		local cursor = chip:FindFirstChild("Cursor")
		if cursor and cursor:IsA("Frame") then
			cursor.BackgroundColor3 = Theme.Color.gold
			cursor.BackgroundTransparency = if copyIndex == index then 0 else 1
		end
	end
end

--- A claimed chip stays on the rail, greyed, so the player can see what is left
--- without losing what they already took.
local function markClaimed(index: number)
	local chip = railChips[index]
	if chip == nil then
		return
	end
	railClaimed[index] = true
	UiKit.tween(chip, 0.18, { BackgroundTransparency = 0.55 }, Enum.EasingStyle.Quad)
	local bar = chip:FindFirstChild("Bar")
	if bar and bar:IsA("Frame") then
		bar.BackgroundTransparency = 0.6
	end
	local blade = chip:FindFirstChild("Blade")
	if blade and blade:IsA("TextLabel") then
		blade.TextColor3 = Theme.Color.textFaint
	end
	local tag = chip:FindFirstChild("Tag")
	if tag and tag:IsA("TextLabel") then
		tag.Text = "CLAIMED"
		tag.TextColor3 = Theme.Color.textFaint
	end
	local edge = chip:FindFirstChild("Edge")
	if edge and edge:IsA("UIStroke") then
		edge.Color = Theme.Color.textFaint
		edge.Thickness = Theme.Stroke.thin
		edge.Transparency = 0.7
	end
	local cursor = chip:FindFirstChild("Cursor")
	if cursor and cursor:IsA("Frame") then
		cursor.BackgroundTransparency = 1
	end
end

--- The hero copy. Every claim swaps this: name, condition line, rarity wash and
--- the 3D blade. The pick is a queue now, not a summary.
local function showCopy(position: number)
	local result = resultEvent
	local crate = currentCrate
	if result == nil or crate == nil then
		return
	end
	local copyIndex = claimQueue[position]
	local copy = if copyIndex then resultCopies[copyIndex] else nil
	if copy == nil then
		return
	end

	local blade = bladeOf(copy.blade)
	local variant = ForgeConfig.variant(if copy.variant and copy.variant ~= "" then copy.variant else ForgeConfig.StandardVariant)
	local rarity = if blade then blade.rarity else "Scrap"
	local rarityColor = rarityColorOf(blade)
	local rank = math.max(
		VARIANT_RANK[variant.id] or 1,
		if blade then (RARITY_RANK[blade.rarity] or 1) else 1
	)
	resultRank = rank

	if topLabel then
		topLabel.Text = string.format("COPY %d OF %d  ·  %s", position, #claimQueue, string.upper(crate.name))
		topLabel.TextColor3 = if position == 1 then Theme.Color.gold else Theme.Color.textFaint
	end
	if mainLabel then
		local display = if blade
			then ModifierConfig.displayName(blade.name, copy.prefix or "", copy.suffix or "")
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
		if copy.power then
			table.insert(pieces, string.format("%s POWER", NumberUtil.abbreviate(copy.power)))
		end
		if copy.newBlade == true then
			table.insert(pieces, "NEW BLADE")
		elseif copy.newVariant == true then
			table.insert(pieces, "NEW VARIANT")
		end
		if position == 1 and result.equipped == true then
			table.insert(pieces, "EQUIPPED")
		end
		subLabel.Text = table.concat(pieces, "  ·  ")
		subLabel.TextColor3 = Theme.Color.textSecondary
	end
	if actionLabel then
		actionLabel.Text = string.format("CLAIM %d / %d", position, #claimQueue)
	end

	local theme = Theme.tierBackdrop(crate.tier)
	if bloom then
		bloom.setColors(variant.color, theme.cool, rarityColor)
	end

	if bladeCleanup then
		bladeCleanup()
		bladeCleanup = nil
	end
	if viewport then
		for _, child in viewport:GetChildren() do
			if child:IsA("Model") or child:IsA("Camera") then
				child:Destroy()
			end
		end
		if blade then
			bladeCleanup = BladePreview.mount(viewport, blade, variant.color, {
				surface = root,
				frameFill = 0.9,
				aimBias = 0,
				spin = 0,
			})
		end
	end
	markCursor(copyIndex)
end

local function paintCrate(crate: ForgeConfig.Tier, _batch: number)
	clearRail()
	stopRays()
	layoutStage(currentBatch, false)
	-- A faint column and a lit floor from the first frame. The crate should read
	-- as sitting in a room with a light above it, not floating in a black box.
	beamTo(crate.accent, 0.16, 0)
	if topLabel then
		topLabel.Text = string.format("POOL %02d / %02d  ·  %s", crate.tier, #ForgeConfig.Tiers, string.upper(crate.name))
	end
	if mainLabel then
		mainLabel.Text = "BREACHING"
		mainLabel.TextColor3 = Theme.Color.text
	end
	if subLabel then
		subLabel.Text = string.format("0 / %d", strikeTotal)
		subLabel.TextColor3 = Theme.Color.textSecondary
	end
	paintPips(strikeTotal, 0)
end

--- Paints everything around the hero: the kicker, the pips and the rail. The
--- rail is built in claim order, so the best copy is the first chip and the
--- gold outline can walk left to right. Returns the best index and that order.
local function paintResultFrame(
	result: Types.FeedEvent,
	crate: ForgeConfig.Tier,
	copies: { Types.ForgedCopy }
): (number, { number })
	local batch = math.max(1, math.floor(result.batch or 1))
	if topLabel then
		topLabel.Text = if batch > 1
			then string.format("BEST OF %d  ·  %s", batch, string.upper(crate.name))
			else "JUST FORGED"
		topLabel.TextColor3 = if batch > 1 then Theme.Color.gold else Theme.Color.textFaint
	end

	local colors: { Color3 } = {}
	local bestMarked = false
	local bestIndex = 0
	for index, copy in copies do
		local copyBlade = bladeOf(copy.blade)
		local isBest = not bestMarked and copy.blade == result.blade and (result.power == nil or copy.power == result.power)
		if isBest then
			bestMarked = true
			bestIndex = index
		end
		colors[index] = if isBest then Theme.Color.gold else rarityColorOf(copyBlade)
	end
	local order: { number } = {}
	if bestIndex > 0 then
		table.insert(order, bestIndex)
	end
	for index = 1, #copies do
		if index ~= bestIndex then
			table.insert(order, index)
		end
	end
	layoutStage(batch, true)
	paintPips(if #copies > 0 then #copies else batch, batch, colors)
	paintRail(copies, order, bestIndex)
	return bestIndex, order
end

--- One copy per press. The queue starts on the best copy, so the payoff is the
--- first thing the player sees; the rest follow in roll order and the rail is
--- painted in that same order, so the gold cursor walks left to right. Each
--- claim is a small beat (ring, flash, shake) and the last one is the full exit.
claimOne = function()
	if phase ~= "result" then
		return
	end
	if os.clock() < resultReadyAt then
		return
	end
	local position = claimCursor + 1
	local copyIndex = claimQueue[position]
	if copyIndex == nil then
		return
	end
	claimCursor = position
	markClaimed(copyIndex)

	if position >= #claimQueue then
		claimOut()
		return
	end

	local copy = resultCopies[copyIndex]
	local blade = bladeOf(copy and copy.blade)
	local color = if blade then rarityColorOf(blade) else Theme.Color.gold
	if flash then
		flash.BackgroundColor3 = color
		flash.BackgroundTransparency = 0.55
		UiKit.tween(flash, 0.22, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
	end
	if stage then
		Vfx.shake(stage, 1.6, 0.14)
	end
	if viewport then
		Vfx.sparks(viewport, color, 6, 0.7)
	end
	Sfx.claim()
	Haptics.pulse(0.55, 0.07)

	-- Hide the key during the swap. The gate alone is not enough: a held mouse
	-- would claim the next copy the instant the key reappears.
	if action then
		action.Visible = false
	end
	if actionLabel then
		actionLabel.Text = string.format("CLAIMED %d / %d", position, #claimQueue)
	end
	resultReadyAt = os.clock() + CLAIM_LOCK
	local stamp = token
	task.delay(0.14, function()
		if stamp ~= token or phase ~= "result" then
			return
		end
		showCopy(claimCursor + 1)
		if action then
			action.Visible = true
		end
		resultReadyAt = os.clock() + CLAIM_LOCK
	end)
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

	resultEvent = result
	local list = result.results
	if list == nil or #list == 0 then
		local single: Types.ForgedCopy = {
			blade = result.blade or "",
			variant = result.variant or ForgeConfig.StandardVariant,
			power = result.power,
			newBlade = result.newBlade,
			newVariant = result.newVariant,
		}
		if result.element then
			single.element = result.element
		end
		if result.grade then
			single.grade = result.grade
		end
		if result.prefix then
			single.prefix = result.prefix
		end
		if result.suffix then
			single.suffix = result.suffix
		end
		list = { single }
	end
	resultCopies = list
	local _, order = paintResultFrame(result, crate, list)
	claimQueue = order
	claimCursor = 0

	local bestCopy = resultCopies[claimQueue[1]]
	local blade = bladeOf(bestCopy and bestCopy.blade)
	local variant = ForgeConfig.variant(if bestCopy and bestCopy.variant and bestCopy.variant ~= ""
		then bestCopy.variant
		else ForgeConfig.StandardVariant)
	local rarityColor = rarityColorOf(blade)
	local rank = math.max(VARIANT_RANK[variant.id] or 1, if blade then (RARITY_RANK[blade.rarity] or 1) else 1)
	resultRank = rank

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
	end
	showCopy(1)

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
	beamTo(rarityColor, 1, 0.1)
	local beamStamp = token
	task.delay(0.16, function()
		if beamStamp == token and phase == "result" then
			beamTo(rarityColor, 0, 0.55)
		end
	end)
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
	strikes += 1
	-- Six clicks for a single crate, six for a triple (two shakes each), ten for
	-- a ten-pull (one per crate). The click budget is the suspense: a single
	-- press that opens the box is a button, six presses that shake it is a lock.
	local perCrate = math.max(1, math.floor(strikeTotal / currentBatch))
	local crateIndex = math.min(currentBatch, math.ceil(strikes / perCrate))
	local beat = strikes - (crateIndex - 1) * perCrate
	local opensCrate = beat >= perCrate
	local final = strikes >= strikeTotal
	-- Map the beat onto the crate's six-step rattle. A triple's second hit is
	-- already the big one instead of a half-hearted nudge.
	local normalized = if perCrate <= 1 then 6 else 1 + math.floor((beat - 1) * 5 / (perCrate - 1))

	if crateHandle then
		if opensCrate then
			crateHandle.open(crateIndex, crate.accent)
		else
			crateHandle.knock(normalized, crate.accent)
		end
	end
	Sfx.crateBreak(opensCrate)
	Haptics.pulse(if opensCrate then 0.55 else 0.18 + normalized * 0.045, if opensCrate then 0.09 else 0.05)
	-- The room brightens as the seal gives. By the last click the column is
	-- already half-lit, so the held beat has somewhere to go.
	beamTo(crate.accent, 0.16 + math.min(strikes / strikeTotal, 1) * 0.34, 0.18)

	-- The same answer the anvil gives, scaled by how hard the crate was hit.
	if viewport then
		Vfx.shockwave(viewport, crate.accent, {
			size = 40 + normalized * 6,
			spread = 2.0 + normalized * 0.15,
			duration = 0.3,
			thickness = 2 + normalized * 0.3,
			at = Vfx.pointer(root),
		})
		Vfx.sparks(viewport, crate.accent, 6 + normalized, 0.9)
		if opensCrate then
			Vfx.burst(viewport, crate.accent, 0.8)
		end
	end
	if stage then
		Vfx.shake(stage, 1.0 + normalized * 0.22, 0.12)
	end
	Sfx.crateTick(strikes, strikeTotal)

	if subLabel then
		subLabel.Text = string.format("%d / %d", strikes, strikeTotal)
	end
	paintPips(strikeTotal, strikes)

	if not final then
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
	-- The held beat. Everything converges here: the column lights, the room
	-- darkens, the pad builds, and two heartbeats carry the silence. The server
	-- answer is already in hand; this is the pause before the screen admits it.
	beamTo(crate.accent, 0.75, 0.5)
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
	-- Six clicks for one or three crates, ten for a ten-pull. The count lives
	-- here so the label, the pips and the strike ladder can never disagree.
	strikeTotal = if currentBatch >= 10 then 10 else 6
	strikes = 0
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
	strikes = 0
	resultReadyAt = 0
	resultEvent = nil
	resultCopies = {}
	claimQueue = {}
	claimCursor = 0
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
	if beamHost then
		beamHost.Visible = false
	end
	beamTo(beamColor, 0, 0)
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
