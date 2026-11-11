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
local CratePreview = require(script.Parent.CratePreview)
local BladePreview = require(script.Parent.BladePreview)
local StageBackdrop = require(script.Parent.StageBackdrop)

local CrateReveal = {}

-- ---------------------------------------------------------------------------
-- Geometry
-- ---------------------------------------------------------------------------

local ANSWER_TIMEOUT = 8
local SEALED_HOLD = 0.3

local STAGE_W = 1080
local STAGE_H = 596
local STAGE_Y = 0.5306
local VIEW_H = 420
local PIP_MAX_W = 320

local ACTION_W = 260
local ACTION_H = 50

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

local crateHandle: CratePreview.Handle? = nil
local bladeCleanup: (() -> ())? = nil
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
		if phase == "result" or phase == "failed" then
			CrateReveal.close()
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

local function paintCrate(crate: ForgeConfig.Tier, batch: number)
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
	for index, copy in copies or {} do
		local copyBlade = bladeOf(copy.blade)
		local isBest = not bestMarked and copy.blade == result.blade and (result.power == nil or copy.power == result.power)
		if isBest then
			bestMarked = true
		end
		colors[index] = if isBest then Theme.Color.gold else rarityColorOf(copyBlade)
	end
	paintPips(if copies and #copies > 0 then #copies else batch, batch, colors)

	if actionLabel then
		actionLabel.Text = if batch > 1 then string.format("COLLECT %d", batch) else "COLLECT"
	end
end

-- ---------------------------------------------------------------------------
-- Runtime
-- ---------------------------------------------------------------------------

local function clearViewport()
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
	if phase == "result" or phase == "closed" then
		return
	end
	phase = "result"
	landed = true
	local crate = currentCrate
	if crate == nil then
		return
	end

	clearViewport()
	local blade = bladeOf(result.blade)
	local variant = ForgeConfig.variant(if result.variant and result.variant ~= "" then result.variant else ForgeConfig.StandardVariant)
	local rarityColor = rarityColorOf(blade)
	local rank = VARIANT_RANK[variant.id] or 1
	local theme = Theme.tierBackdrop(crate.tier)

	if bloom then
		bloom.setColors(variant.color, theme.cool, rarityColor)
	end
	paintResult(result, crate)

	if action then
		action.Visible = true
		action.BackgroundColor3 = crate.accent
	end
	if actionLabel then
		actionLabel.TextColor3 = Theme.onColor(crate.accent)
	end

	if viewport then
		viewport.Ambient = Color3.fromRGB(214, 216, 228)
		viewport.LightColor = Color3.fromRGB(255, 255, 255)
		viewport.LightDirection = Vector3.new(-0.55, -0.72, -0.42)
		viewport.BackgroundTransparency = 1
		if blade then
			bladeCleanup = BladePreview.mount(viewport, blade, variant.color, {
				surface = root,
				frameFill = 0.9,
				aimBias = 0.06,
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

	Sfx.crateShatter()
	Sfx.result(rank)
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
	local stamp = token
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
	root.Visible = false
	clearViewport()
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
