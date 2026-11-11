--!strict
-- Playback for the generated layered sprite sheets in `VfxManifest`.
--
-- `scripts/generate_vfx.py` draws every effect as four pure-white 4x4
-- flipbooks — glow, rim, body, hotcore — so one upload covers every blade
-- tier: the runtime only changes `ImageColor3`. That is the entire reason the
-- sheets are white.
--
-- Every entry point is defensive. `play` returns `false` and `attach` returns
-- `nil` when there is nothing to draw: a build with placeholder IDs has to stay
-- fully playable, so a missing sprite is a drop in fidelity, never a missing
-- effect.
--
-- Why a single shared Heartbeat instead of one connection per effect: clicking
-- is unbounded, and a connection per strike would leak under an autoclicker.
-- There is one connection, created on the first live sprite and dropped when
-- the last one dies.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local VfxManifest = require(Shared:WaitForChild("VfxManifest"))

local Theme = require(script.Parent.Theme)
local UiKit = require(script.Parent.UiKit)

local SpriteFx = {}

-- Above the panels, below `Vfx` (ZIndex 40) so damage numbers stay legible on
-- top of whatever the effect layer is doing.
local LAYER_ZINDEX = 39

-- How many one-shot effects may be alive at once. A 1.33s slash at ten clicks a
-- second is already thirteen; anything past this is either an autoclicker or a
-- burst effect, and the oldest is dropped rather than letting the label count
-- grow without bound. Looping effects are exempt: they are placed by the game,
-- not by the player, and evicting an aura mid-fight would make it blink.
local MAX_ACTIVE = 14

-- Each sheet layer is authored at the same frame size but plays a slightly
-- different role. The glow is drawn past the body and held back in opacity so
-- it reads as bloom rather than as a fatter silhouette.
local LAYER_STYLE: { [string]: { transparency: number, scale: number } } = {
	glow = { transparency = 0.55, scale = 1.34 },
	rim = { transparency = 0.08, scale = 1.0 },
	body = { transparency = 0.05, scale = 1.0 },
	hotcore = { transparency = 0.0, scale = 0.96 },
}

export type Options = {
	--- Edge length in design pixels. Defaults to a size that reads well around
	--- the anvil button without swallowing the panel.
	size: number?,
	--- Playback rate multiplier. 2 plays the sheet at double speed.
	speed: number?,
}

--- Returned by `attach` so the caller can retire a looping effect.
export type Handle = {
	stop: () -> (),
}

type Sprite = {
	container: Frame,
	labels: { ImageLabel },
	elapsed: number,
	frames: number,
	fps: number,
	loop: boolean,
	persistent: boolean,
}

local layer: Frame? = nil
local scaleFactor = 1
local active: { Sprite } = {}
local heartbeat: RBXScriptConnection? = nil
local availability: boolean? = nil

local function available(): boolean
	if availability == nil then
		availability = VfxManifest.isReal()
	end
	return availability :: boolean
end

function SpriteFx.init(canvas: Frame, uiScale: UIScale)
	layer = UiKit.create("Frame", {
		Name = "SpriteFx",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = LAYER_ZINDEX,
		ClipsDescendants = false,
	}) :: Frame
	layer.Parent = canvas
	scaleFactor = uiScale.Scale

	uiScale:GetPropertyChangedSignal("Scale"):Connect(function()
		scaleFactor = uiScale.Scale
	end)
end

--- True once at least one sheet has been uploaded. Cheap enough to call from a
--- render path; the manifest is scanned once.
function SpriteFx.isAvailable(): boolean
	return available()
end

local function centreOf(anchor: GuiObject): Vector2
	if layer == nil then
		return Vector2.zero
	end
	local screen = anchor.AbsolutePosition + anchor.AbsoluteSize * 0.5
	return (screen - layer.AbsolutePosition) / scaleFactor
end

local function applyFrame(sprite: Sprite, frame: number)
	local column = frame % VfxManifest.Columns
	local row = math.floor(frame / VfxManifest.Columns)
	local offset = Vector2.new(column * VfxManifest.FrameSize, row * VfxManifest.FrameSize)
	for _, label in sprite.labels do
		label.ImageRectOffset = offset
	end
end

local function retire(sprite: Sprite)
	for index, candidate in active do
		if candidate == sprite then
			table.remove(active, index)
			break
		end
	end
	-- Idempotent: an already-destroyed container is not an error, so a handle
	-- that outlives `destroy()` can still be called safely.
	sprite.container:Destroy()
end

local function step(dt: number)
	for index = #active, 1, -1 do
		local sprite = active[index]
		sprite.elapsed += dt

		local frame = math.floor(sprite.elapsed * sprite.fps)

		if frame >= sprite.frames then
			if sprite.loop then
				frame %= sprite.frames
			else
				-- The last authored frame has already faded to nothing, so
				-- destroying here is not a visible cut.
				table.remove(active, index)
				sprite.container:Destroy()
				frame = -1
			end
		end

		if frame >= 0 then
			applyFrame(sprite, frame)
		end
	end

	if #active == 0 and heartbeat ~= nil then
		local connection = heartbeat
		heartbeat = nil
		if connection ~= nil then
			connection:Disconnect()
		end
	end
end

local function spawn(
	anchor: GuiObject,
	effect: string,
	color: Color3,
	opts: Options?,
	persistent: boolean
): Sprite?
	if layer == nil or not available() then
		return nil
	end

	-- A flipbook is motion for its own sake. Players who asked for reduced
	-- motion get the procedural fallback, which already honours the setting.
	if Theme.reducedMotion() then
		return nil
	end

	local meta = VfxManifest.Effects[effect]
	if meta == nil then
		return nil
	end

	-- A one-shot effect must not loop, and a persistent one must: the sheet is
	-- authored for one role only, and playing it in the other produces either a
	-- frozen last frame or an effect that never ends.
	if meta.loop ~= persistent then
		return nil
	end

	local ids: { [string]: string } = {}
	local found = 0
	for _, layerName in VfxManifest.LayerOrder do
		local id = VfxManifest.layer(effect, layerName)
		if id ~= nil then
			ids[layerName] = id
			found += 1
		end
	end

	-- Partial uploads happen: if even one layer landed the effect still plays.
	if found == 0 then
		return nil
	end

	local options = opts or {}
	local size = options.size or 340
	local origin = centreOf(anchor)

	if not persistent then
		local live = 0
		for _, candidate in active do
			if not candidate.persistent then
				live += 1
			end
		end
		while live >= MAX_ACTIVE do
			local oldest: Sprite? = nil
			for _, candidate in active do
				if not candidate.persistent then
					oldest = candidate
					break
				end
			end
			if oldest == nil then
				break
			end
			retire(oldest)
			live -= 1
		end
	end

	local container = UiKit.create("Frame", {
		Name = string.format("Fx_%s", effect),
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(origin.X, origin.Y),
		Size = UDim2.fromOffset(size, size),
	}) :: Frame
	container.Parent = layer

	local labels: { ImageLabel } = {}
	local drawOrder = 0
	for _, layerName in VfxManifest.LayerOrder do
		local id = ids[layerName]
		if id ~= nil then
			local style = LAYER_STYLE[layerName]
			local image = UiKit.create("ImageLabel", {
				Name = layerName,
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(style.scale, style.scale),
				Image = id,
				ImageColor3 = color,
				ImageTransparency = style.transparency,
				ScaleType = Enum.ScaleType.Stretch,
				ImageRectSize = Vector2.new(VfxManifest.FrameSize, VfxManifest.FrameSize),
				ImageRectOffset = Vector2.zero,
				ZIndex = drawOrder,
			}) :: ImageLabel
			image.Parent = container
			table.insert(labels, image)
			drawOrder += 1
		end
	end

	local sprite: Sprite = {
		container = container,
		labels = labels,
		elapsed = 0,
		frames = meta.frames,
		fps = meta.fps * (options.speed or 1),
		loop = meta.loop,
		persistent = persistent,
	}

	applyFrame(sprite, 0)
	table.insert(active, sprite)

	if heartbeat == nil then
		heartbeat = RunService.Heartbeat:Connect(step)
	end

	return sprite
end

--- Plays `effect` once, centred on `anchor`, tinted `color`. Returns false when
--- nothing was drawn, so the caller can fall back to `Vfx.burst`.
function SpriteFx.play(anchor: GuiObject, effect: string, color: Color3, opts: Options?): boolean
	return spawn(anchor, effect, color, opts, false) ~= nil
end

--- Places a looping effect (an aura) and returns a handle, or nil when the
--- sheet is unavailable. Looping sprites are never evicted by `play`.
function SpriteFx.attach(anchor: GuiObject, effect: string, color: Color3, opts: Options?): Handle?
	local sprite = spawn(anchor, effect, color, opts, true)
	if sprite == nil then
		return nil
	end

	local handle: Handle = {
		stop = function()
			retire(sprite)
		end,
	}
	return handle
end

--- Tears down the layer and every live sprite. Called on client shutdown.
function SpriteFx.destroy()
	for _, sprite in active do
		sprite.container:Destroy()
	end
	table.clear(active)

	if heartbeat ~= nil then
		local connection = heartbeat
		heartbeat = nil
		connection:Disconnect()
	end

	if layer ~= nil then
		layer:Destroy()
		layer = nil
	end

	availability = nil
end

return SpriteFx
