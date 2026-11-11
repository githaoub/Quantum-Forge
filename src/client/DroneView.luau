--!strict
-- Fleet panel: the drone ladder, the live rung preview, and the fleet services.
--
-- Drones are the idle half of the economy. The ladder is hard-coded: five rungs,
-- each with its own hull, yield and price curve, and no ceiling. A player buys
-- the rung they can afford, the rung above opens on fleet size, and the numbers
-- climb into the millions. That staircase is the point of the tab.
--
-- The panel is four bands, in reading order:
--
--   hero     the 3D rung preview, its name and count, and the two buy keys
--   strip    FLEET, OUTPUT and PER DRONE, the three numbers a purchase needs
--   ladder   one key per rung, with owned count and unlock progress
--   services expedition, salvage rack, codex
--
-- Fixed-height bands mean nothing below the stage ever moves as numbers change.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local NumberUtil = require(Shared:WaitForChild("NumberUtil"))
local Config = require(Shared:WaitForChild("Config"))
local DroneRegistry = require(Shared:WaitForChild("DroneRegistry"))
local AssetManifest = require(Shared:WaitForChild("AssetManifest"))
local SalvageConfig = require(Shared:WaitForChild("SalvageConfig"))
local Types = require(Shared:WaitForChild("Types"))

local Theme = require(script.Parent.Theme)
local UiKit = require(script.Parent.UiKit)
local StageBackdrop = require(script.Parent.StageBackdrop)
local StateStore = require(script.Parent.StateStore)
local DroneModelBuilder = require(script.Parent.DroneModelBuilder)
local Sfx = require(script.Parent.Sfx)

local DroneView = {}

local ExpeditionConfig = require(Shared:WaitForChild("ExpeditionConfig"))

-- Bands, in design pixels: hero 208, strip 64, ladder 82, then the services.
local HERO_H = 208
local LADDER_H = 82
--- Salvage rack: 28 header/meter + 100 slots + 12 bottom.
local SALVAGE_H = 164
--- Codex: 26 header + four 26px set rows + 8 bottom.
local CODEX_H = 142

local viewport: ViewportFrame? = nil
local tierNameLabel: TextLabel? = nil
local tierOwnedLabel: TextLabel? = nil
local tierIndexLabel: TextLabel? = nil
local fleetLabel: TextLabel? = nil
local outputLabel: TextLabel? = nil
local perDroneLabel: TextLabel? = nil
local ladderCountLabel: TextLabel? = nil
local buyOneHandle: UiKit.ActionHandle? = nil
local buyTenHandle: UiKit.ActionHandle? = nil
local unsubscribe: (() -> ())? = nil
local cleanupModel: (() -> ())? = nil

--- The rung the hero is showing. `nil` until the first payload, then the best
--- unlocked rung. Clicking a ladder key pins it, including a locked rung, which
--- is how the next hull gets advertised before it is affordable.
local selectedTier: string? = nil
local mountedTier: string? = nil
local latest: Types.SyncPayload? = nil

type LadderKey = {
	root: TextButton,
	name: TextLabel,
	count: TextLabel,
	bar: Frame,
	stroke: UIStroke,
}

local ladderKeys: { [string]: LadderKey } = {}
local ladderOrder: { string } = {}

-- Expedition band. Two halves that never coexist: the mission shelf while the
-- fleet is home, and a single flight line while it is out.
local expShelf: Frame? = nil
local expLive: Frame? = nil
local expShardLabel: TextLabel? = nil
local expTitle: TextLabel? = nil
local expTimer: TextLabel? = nil
local expReward: TextLabel? = nil
local expBar: UiKit.BarParts? = nil
local expButtons: { [string]: UiKit.ActionHandle } = {}

-- Salvage rack and codex. Slots are built once and repainted by index; the
-- payload is capped at `SalvageConfig.MaxCaches`, so there is never a fourth.
type CacheSlot = {
	root: TextButton,
	name: TextLabel,
	state: TextLabel,
	hint: TextLabel,
	bar: UiKit.BarParts,
	stroke: UIStroke,
}

local cacheSlots: { CacheSlot } = {}
local cacheMeterBar: UiKit.BarParts? = nil
local cacheMeterText: TextLabel? = nil
local cacheMeterNote: TextLabel? = nil
local codexRows: { [string]: { root: Frame, pips: { Frame }, bonus: TextLabel } } = {}
local codexCount: TextLabel? = nil

local function buy(count: number)
	if selectedTier == nil then
		return
	end
	-- The press is the purchase; the payload confirms it. `Sfx.purchase` is the
	-- same two-note confirmation the store uses, so spending Aether and spending
	-- Robux land in the same register.
	Sfx.purchase()
	StateStore.send("buyDrones", { id = selectedTier, count = count })
end

--- The fleet entry for a rung, from the tick payload. Falls back to a synthesized
--- locked entry so a stale selection cannot nil-error between a reset and a sync.
local function entryFor(payload: Types.SyncPayload, id: string): Types.FleetEntry?
	for _, entry in payload.fleet do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

--- The stage behind the drone: a gradient wash, a faint grid for depth, then
--- the viewport. The wash itself lives in `StageBackdrop`, shared with the forge
--- and the vault.
local function buildStage(parent: Frame)
	local stage = UiKit.create("Frame", {
		Name = "DroneStage",
		BackgroundColor3 = Theme.Color.void,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.fromScale(1, 1),
	}) :: Frame
	UiKit.corner(stage, Theme.Radius.md)
	UiKit.stroke(stage, Theme.Color.outline, Theme.Stroke.thick, 0)
	UiKit.gradient(stage, { Theme.Color.void, Theme.Color.panelSunken }, 90)
	stage.Parent = parent

	-- Gradient floor. The wash is built from aether and quantum, so the hull
	-- reads as lit by its own drive. Painted before the grid so the grid lines
	-- sit on top of it.
	StageBackdrop.paint(stage, {
		warm = Theme.Color.aether,
		cool = Theme.Color.quantum,
		radius = Theme.Radius.md,
		zIndex = 1,
	})

	local grid = UiKit.create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
	}) :: Frame
	grid.Parent = stage
	for index = 1, 6 do
		local line = UiKit.create("Frame", {
			BackgroundColor3 = Theme.Color.aether,
			BackgroundTransparency = 0.92,
			BorderSizePixel = 0,
			Size = UDim2.new(0, 1, 1, 0),
			Position = UDim2.fromScale(index / 7, 0),
			ZIndex = 1,
		}) :: Frame
		line.Parent = grid
	end
	for index = 1, 4 do
		local line = UiKit.create("Frame", {
			BackgroundColor3 = Theme.Color.aether,
			BackgroundTransparency = 0.93,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 1),
			Position = UDim2.fromScale(0, index / 5),
			ZIndex = 1,
		}) :: Frame
		line.Parent = grid
	end

	local frame = UiKit.create("ViewportFrame", {
		Name = "DroneViewport",
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(152, 168, 200),
		LightColor = Color3.fromRGB(228, 242, 255),
		LightDirection = Vector3.new(-0.5, -0.7, -0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
	}) :: ViewportFrame
	frame.Parent = stage
	viewport = frame

	return stage
end

--- One cell of the three-column stat strip.
local function buildStat(parent: Frame, x: number, width: number, caption: string, color: Color3, y: number?): TextLabel
	local head = UiKit.label(parent, {
		text = caption,
		size = Theme.Text.Micro,
		font = Theme.Font.Black,
		color = Theme.Color.textSecondary,
	})
	local top = y or 7
	head.Position = UDim2.fromOffset(x, top)
	head.Size = UDim2.fromOffset(width, 18)

	local value = UiKit.label(parent, {
		text = "0 / sec",
		size = Theme.Text.Subheading,
		font = Theme.Font.Numeric,
		color = color,
	})
	value.Position = UDim2.fromOffset(x, top + 20)
	value.Size = UDim2.fromOffset(width, 28)
	return value
end

--- Expedition band: three mission keys while the fleet is home, one live flight
--- line while it is away.
---
--- The shelf is a stack rather than a picker with a confirm step because the
--- commitment is the interesting decision, not the navigation. Each row states
--- the squad, the duration and the payout before the button is pressed, so a
--- player can compare "five drones for five minutes" against "thirty for an
--- hour" without opening anything.
local function buildExpedition(parent: Instance)
	local band = UiKit.panel(parent, {
		tier = "item",
		radius = Theme.Radius.md,
	})
	band.Name = "ExpeditionBand"
	-- 28 (header) + 228 (shelf) + 10 bottom. Rows are 72 tall now: a 64px badge
	-- needs 4px of air above and below, which is what makes the art read at
	-- arm's length instead of as a decorated bullet point. Band 204 -> 266.
	band.Size = UDim2.new(1, -4, 0, 266)
	band.LayoutOrder = 5

	local head = UiKit.label(band, {
		text = "EXPEDITION",
		size = Theme.Text.Micro,
		font = Theme.Font.Black,
		color = Theme.Color.textSecondary,
	})
	head.Position = UDim2.fromOffset(12, 6)
	head.Size = UDim2.fromOffset(150, 18)

	expShardLabel = UiKit.label(band, {
		text = "0 SHARDS",
		size = Theme.Text.Micro,
		font = Theme.Font.Numeric,
		color = Theme.Color.quantum,
		align = Enum.TextXAlignment.Right,
	})
	expShardLabel.Position = UDim2.new(1, -162, 0, 6)
	expShardLabel.Size = UDim2.fromOffset(150, 18)

	local shelf = UiKit.create("Frame", {
		Name = "ExpeditionShelf",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 228),
		Position = UDim2.fromOffset(0, 28),
	}) :: Frame
	shelf.Parent = band
	expShelf = shelf

	for index, mission in ExpeditionConfig.list() do
		local row = UiKit.create("Frame", {
			Name = string.format("Mission_%s", mission.id),
			BackgroundColor3 = Theme.Color.panelSunken,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -20, 0, 72),
			Position = UDim2.fromOffset(10, (index - 1) * 76),
		}) :: Frame
		UiKit.corner(row, Theme.Radius.sm)
		row.Parent = shelf

		-- 64px badge, the same well the store rows use. It is the mission's
		-- whole identity at a glance: a hull on a cable, a drone on a wave, a
		-- magnet full of junk. Without it the three rows differ only by a name.
		local well = UiKit.badgeWell(row, {
			image = AssetManifest.uiArt(mission.icon),
			size = 64,
			accent = Theme.Color.aether,
		})
		if well ~= nil then
			well.Position = UDim2.fromOffset(8, 4)
		end

		local name = UiKit.label(row, {
			text = mission.name,
			size = Theme.Text.Small,
			font = Theme.Font.Black,
			color = Theme.Color.text,
		})
		name.Position = UDim2.fromOffset(84, 14)
		name.Size = UDim2.new(1, -220, 0, 22)

		local detail = UiKit.label(row, {
			text = string.format(
				"%d DRONES  ·  %s  ·  +%s AETHER",
				mission.squad,
				if mission.seconds >= 3600 then string.format("%dH", mission.seconds // 3600) else string.format("%dM", mission.seconds // 60),
				NumberUtil.abbreviate(mission.aether)
			),
			size = Theme.Text.Micro,
			font = Theme.Font.Numeric,
			color = Theme.Color.textSecondary,
		})
		detail.Position = UDim2.fromOffset(84, 38)
		detail.Size = UDim2.new(1, -220, 0, 18)

		local handle = UiKit.actionButton(row, {
			accent = Theme.Color.quantum,
			height = 34,
			radius = Theme.Radius.sm,
			size = 14,
			label = "SEND",
			handler = function()
				-- Launch sound on the press: the mission is the verb, and the
				-- payload only confirms it. A refused dispatch pushes a toast,
				-- which is the same contract the forge uses for a vent.
				Sfx.dispatch()
				StateStore.send("dispatch", { id = mission.id })
			end,
		})
		handle.button.Name = string.format("Dispatch_%s", mission.id)
		handle.button.Position = UDim2.new(1, -116, 0.5, -17)
		handle.button.Size = UDim2.fromOffset(104, 34)
		handle.set("ready", "SEND", Theme.Color.quantum)
		expButtons[mission.id] = handle
	end

	-- Live block. Same footprint as the shelf so nothing below it moves when a
	-- mission launches.
	local live = UiKit.create("Frame", {
		Name = "ExpeditionLive",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -20, 0, 228),
		Position = UDim2.fromOffset(10, 28),
		Visible = false,
	}) :: Frame
	live.Parent = band
	expLive = live

	expTitle = UiKit.label(live, {
		text = "",
		size = Theme.Text.Subheading,
		font = Theme.Font.Black,
		color = Theme.Color.quantum,
	})
	expTitle.Position = UDim2.fromOffset(2, 8)
	expTitle.Size = UDim2.new(1, -140, 0, 24)

	expTimer = UiKit.label(live, {
		text = "00:00",
		size = Theme.Text.Subheading,
		font = Theme.Font.Numeric,
		color = Theme.Color.starMatter,
		align = Enum.TextXAlignment.Right,
	})
	expTimer.Position = UDim2.new(1, -150, 0, 6)
	expTimer.Size = UDim2.fromOffset(148, 26)

	expBar = UiKit.bar(live, {
		height = 8,
		radius = 4,
		gradient = { Theme.Color.quantumDeep, Theme.Color.quantum },
	})
	expBar.track.Position = UDim2.fromOffset(2, 44)
	expBar.track.Size = UDim2.new(1, -4, 0, 8)

	expReward = UiKit.label(live, {
		text = "",
		size = Theme.Text.Micro,
		font = Theme.Font.Numeric,
		color = Theme.Color.textSecondary,
	})
	expReward.Position = UDim2.fromOffset(2, 62)
	expReward.Size = UDim2.new(1, -4, 0, 20)
end

--- Salvage rack: three slots, one meter, one tap target per slot.
---
--- The rarity is decided at drop and drawn on the sealed slot, so the rack is a
--- row of small anticipations rather than a mystery box with the lid painted on.
--- Cracking runs on the server clock; the slot only renders what the payload says.
local function buildSalvage(parent: Instance)
	local band = UiKit.panel(parent, {
		tier = "item",
		radius = Theme.Radius.md,
	})
	band.Name = "SalvageBand"
	band.Size = UDim2.new(1, -4, 0, SALVAGE_H)
	band.LayoutOrder = 6

	local head = UiKit.label(band, {
		text = "SALVAGE RACK",
		size = Theme.Text.Micro,
		font = Theme.Font.Black,
		color = Theme.Color.textSecondary,
	})
	head.Position = UDim2.fromOffset(12, 6)
	head.Size = UDim2.fromOffset(180, 18)

	cacheMeterNote = UiKit.label(band, {
		text = "0 / 3 CACHES",
		size = Theme.Text.Micro,
		font = Theme.Font.Numeric,
		color = Theme.Color.quantum,
		align = Enum.TextXAlignment.Right,
	})
	cacheMeterNote.Position = UDim2.new(1, -172, 0, 6)
	cacheMeterNote.Size = UDim2.fromOffset(160, 18)

	cacheMeterBar = UiKit.bar(band, {
		height = 6,
		radius = 3,
		gradient = { Theme.Color.quantumDeep, Theme.Color.quantum },
	})
	cacheMeterBar.track.Position = UDim2.fromOffset(12, 27)
	cacheMeterBar.track.Size = UDim2.new(1, -24, 0, 6)

	cacheMeterText = UiKit.label(band, {
		text = "NEXT CACHE  0 / 40 STRIKES",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.textSecondary,
	})
	cacheMeterText.Position = UDim2.fromOffset(12, 36)
	cacheMeterText.Size = UDim2.new(1, -24, 0, 16)

	-- 10 + 132 + 8 + 132 + 8 + 132 = 422 of 432, so the rack is edge to edge
	-- with the shelf above it and never wraps on a narrower canvas.
	local slotWidth = 132
	for index = 1, SalvageConfig.MaxCaches do
		local root = UiKit.create("TextButton", {
			Name = string.format("CacheSlot%d", index),
			BackgroundColor3 = Theme.Color.panelSunken,
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			Size = UDim2.fromOffset(slotWidth, 96),
			Position = UDim2.fromOffset(10 + (index - 1) * (slotWidth + 8), 58),
		}) :: TextButton
		UiKit.corner(root, Theme.Radius.sm)
		local stroke = UiKit.stroke(root, Theme.Color.stroke, 2, 0.25)
		root.Parent = band

		local nameLabel = UiKit.label(root, {
			text = "EMPTY",
			size = Theme.Text.Tiny,
			font = Theme.Font.Black,
			color = Theme.Color.textFaint,
			align = Enum.TextXAlignment.Center,
		})
		nameLabel.Position = UDim2.fromOffset(8, 8)
		nameLabel.Size = UDim2.new(1, -16, 0, 16)

		local stateLabel = UiKit.label(root, {
			text = "",
			size = Theme.Text.Subheading,
			font = Theme.Font.Black,
			color = Theme.Color.text,
			align = Enum.TextXAlignment.Center,
		})
		stateLabel.Position = UDim2.fromOffset(8, 30)
		stateLabel.Size = UDim2.new(1, -16, 0, 28)

		local hint = UiKit.label(root, {
			text = "",
			size = Theme.Text.Tiny,
			font = Theme.Font.Numeric,
			color = Theme.Color.textSecondary,
			align = Enum.TextXAlignment.Center,
		})
		hint.Position = UDim2.fromOffset(6, 62)
		hint.Size = UDim2.new(1, -12, 0, 16)

		local bar = UiKit.bar(root, {
			height = 4,
			radius = 2,
			gradient = { Theme.Color.quantumDeep, Theme.Color.quantum },
		})
		bar.track.Position = UDim2.new(0, 8, 1, -10)
		bar.track.Size = UDim2.new(1, -16, 0, 4)
		bar.set(0)

		root.Activated:Connect(function()
			local state = StateStore.current
			if state == nil then
				return
			end
			local cache = state.caches[index]
			if cache == nil then
				return
			end
			if cache.readyAt <= 0 then
				Sfx.cacheCrack()
				StateStore.send("crackCache", { slot = index })
			elseif cache.secondsLeft <= 0 then
				Sfx.cacheClaim()
				StateStore.send("claimCache", { slot = index })
			end
		end)

		cacheSlots[index] = {
			root = root,
			name = nameLabel,
			state = stateLabel,
			hint = hint,
			bar = bar,
			stroke = stroke,
		}
	end
end

local STAT_LABEL: { [string]: string } = {
	click = "STRIKE",
	cool = "COOLING",
	crit = "CRIT",
	vent = "VENT",
}

--- Sigil codex: four set rows, three pips each, one permanent bonus per set.
---
--- The pips are the whole progress read. A count ("7 / 12") is on the header, but
--- a player chases one set at a time, and three pips fill faster than a fraction.
local function buildCodex(parent: Instance)
	local band = UiKit.panel(parent, {
		tier = "item",
		radius = Theme.Radius.md,
	})
	band.Name = "CodexBand"
	band.Size = UDim2.new(1, -4, 0, CODEX_H)
	band.LayoutOrder = 7

	local head = UiKit.label(band, {
		text = "SIGIL CODEX",
		size = Theme.Text.Micro,
		font = Theme.Font.Black,
		color = Theme.Color.textSecondary,
	})
	head.Position = UDim2.fromOffset(12, 5)
	head.Size = UDim2.fromOffset(180, 18)

	codexCount = UiKit.label(band, {
		text = "0 / 4 SETS",
		size = Theme.Text.Micro,
		font = Theme.Font.Numeric,
		color = Theme.Color.quantum,
		align = Enum.TextXAlignment.Right,
	})
	codexCount.Position = UDim2.new(1, -172, 0, 5)
	codexCount.Size = UDim2.fromOffset(160, 18)

	for index, setId in SalvageConfig.SetOrder do
		local set = SalvageConfig.SigilSets[setId]
		local row = UiKit.create("Frame", {
			Name = string.format("Codex_%s", setId),
			BackgroundColor3 = Theme.Color.panelSunken,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -24, 0, 24),
			Position = UDim2.fromOffset(12, 26 + (index - 1) * 27),
		}) :: Frame
		UiKit.corner(row, 6)
		row.Parent = band

		local name = UiKit.label(row, {
			text = set.name,
			size = Theme.Text.Tiny,
			font = Theme.Font.Black,
			color = Theme.Color.textSecondary,
		})
		name.Position = UDim2.fromOffset(8, 3)
		name.Size = UDim2.fromOffset(92, 18)

		local pips: { Frame } = {}
		for pip = 1, #set.sigils do
			local dot = UiKit.create("Frame", {
				BackgroundColor3 = Theme.Color.panelSunken,
				BorderSizePixel = 0,
				Size = UDim2.fromOffset(10, 10),
				Position = UDim2.fromOffset(104 + (pip - 1) * 16, 7),
			}) :: Frame
			UiKit.corner(dot, 5)
			UiKit.stroke(dot, Theme.Color.stroke, 1, 0.15)
			dot.Parent = row
			pips[pip] = dot
		end

		local bonus = UiKit.label(row, {
			text = string.format("+%d%% %s", math.floor(set.amount * 100 + 0.5), STAT_LABEL[set.stat] or set.stat),
			size = Theme.Text.Tiny,
			font = Theme.Font.Numeric,
			color = Theme.Color.textFaint,
			align = Enum.TextXAlignment.Right,
		})
		bonus.Position = UDim2.new(1, -150, 0, 3)
		bonus.Size = UDim2.fromOffset(142, 18)

		codexRows[setId] = { root = row, pips = pips, bonus = bonus }
	end
end

-- ---------------------------------------------------------------------------
-- Ladder
-- ---------------------------------------------------------------------------

--- One key per rung. Five across, each carrying its short name, its owned count
--- and a meter that fills toward the rung's unlock gate. A locked rung is still
--- clickable: the hero previews the hull before it is affordable, which is the
--- entire sales pitch of the next tier.
local function buildLadder(parent: Instance)
	local band = UiKit.panel(parent, {
		tier = "item",
		radius = Theme.Radius.md,
	})
	band.Name = "DroneLadder"
	band.Size = UDim2.new(1, -4, 0, LADDER_H)
	band.LayoutOrder = 3

	local head = UiKit.label(band, {
		text = "DRONE LADDER",
		size = Theme.Text.Micro,
		font = Theme.Font.Black,
		color = Theme.Color.textSecondary,
	})
	head.Position = UDim2.fromOffset(12, 5)
	head.Size = UDim2.fromOffset(150, 18)

	ladderCountLabel = UiKit.label(band, {
		text = "0/5 RUNGS",
		size = Theme.Text.Micro,
		font = Theme.Font.Numeric,
		color = Theme.Color.aether,
		align = Enum.TextXAlignment.Right,
	})
	ladderCountLabel.Position = UDim2.new(1, -162, 0, 5)
	ladderCountLabel.Size = UDim2.fromOffset(150, 18)

	local row = UiKit.create("Frame", {
		Name = "LadderRow",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -24, 0, 50),
		Position = UDim2.fromOffset(12, 26),
	}) :: Frame
	row.Parent = band
	UiKit.hlist(row, 6, Enum.VerticalAlignment.Center)

	for _, tier in DroneRegistry.tiers do
		local key = UiKit.create("TextButton", {
			Name = string.format("Rung_%s", tier.id),
			BackgroundColor3 = Theme.Color.panelSunken,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			Size = UDim2.new(0.2, -5, 0, 50),
		}) :: TextButton
		UiKit.corner(key, Theme.Radius.sm)
		local stroke = UiKit.stroke(key, Theme.Color.stroke, 1, 0)
		key.Parent = row

		local name = UiKit.label(key, {
			text = string.upper(tier.name),
			size = Theme.Text.Tiny,
			font = Theme.Font.Black,
			color = Theme.Color.locked,
			align = Enum.TextXAlignment.Center,
		})
		name.Size = UDim2.new(1, 0, 0, 18)
		name.Position = UDim2.fromOffset(0, 5)
		name.ZIndex = 2

		local count = UiKit.label(key, {
			text = "0",
			size = 15,
			font = Theme.Font.Numeric,
			color = Theme.Color.textDim,
			align = Enum.TextXAlignment.Center,
		})
		count.Size = UDim2.new(1, 0, 0, 18)
		count.Position = UDim2.fromOffset(0, 22)
		count.ZIndex = 2

		local track = UiKit.create("Frame", {
			BackgroundColor3 = Theme.Color.void,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -16, 0, 3),
			Position = UDim2.new(0, 8, 1, -7),
			ZIndex = 2,
		}) :: Frame
		UiKit.corner(track, 2)
		track.Parent = key

		local bar = UiKit.create("Frame", {
			BackgroundColor3 = Theme.Color.stroke,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(0, 1),
			ZIndex = 3,
		}) :: Frame
		UiKit.corner(bar, 2)
		bar.Parent = track

		ladderKeys[tier.id] = { root = key, name = name, count = count, bar = bar, stroke = stroke }
		ladderOrder[#ladderOrder + 1] = tier.id

		key.Activated:Connect(function()
			selectedTier = tier.id
			if latest then
				DroneView.render(latest)
			end
		end)
	end
end

--- Remounts the viewport at a rung. The camera frames the hull in the 42%-wide
--- stage beside the purchase column.
local function mountTier(id: string)
	if viewport == nil then
		return
	end
	if cleanupModel then
		cleanupModel()
		cleanupModel = nil
	end
	cleanupModel = DroneModelBuilder.mount(viewport, id, {
		-- 6.4 units of stand-off on a 42%-wide stage, aimed just below the hull.
		-- The old 8.8 was measured for a full-width 220px stage; in the smaller stage
		-- it left the drone the size of a postage stamp.
		distance = 6.4,
		centre = Vector3.new(0, -0.15, 0),
	})
	mountedTier = id
end

function DroneView.init(parent: Instance)
	-- Band 1: hero. Two columns instead of one empty hangar band: the drone on the
	-- left, the numbers and the buy keys on the right. The wide stage put the
	-- name plate at the top, the keys at the bottom and the hull in a 34px gap
	-- between them.
	local hero = UiKit.panel(parent, {
		tier = "raised",
		radius = Theme.Radius.card,
	})
	hero.Name = "FleetHero"
	hero.Size = UDim2.new(1, -4, 0, HERO_H)
	hero.LayoutOrder = 1

	local stage = buildStage(hero)
	stage.Position = UDim2.fromOffset(8, 8)
	stage.Size = UDim2.new(0.42, -12, 1, -16)

	local info = UiKit.create("Frame", {
		Name = "FleetInfo",
		BackgroundTransparency = 1,
		Position = UDim2.new(0.42, 6, 0, 12),
		Size = UDim2.new(0.58, -22, 1, -24),
		ZIndex = 3,
	}) :: Frame
	info.Parent = hero

	local eye = UiKit.eyebrow(info, "SELECTED RUNG")
	eye.Position = UDim2.fromOffset(0, 0)

	tierNameLabel = UiKit.label(info, {
		text = "SCRAP DRONE",
		size = Theme.Text.Title - 6,
		font = Theme.Font.Heading,
		color = Theme.Color.aether,
	})
	tierNameLabel.Name = "TierName"
	tierNameLabel.Position = UDim2.fromOffset(0, 16)
	tierNameLabel.Size = UDim2.new(1, -130, 0, 28)

	tierOwnedLabel = UiKit.label(info, {
		text = "0 OWNED",
		size = Theme.Text.Tiny,
		font = Theme.Font.Numeric,
		color = Theme.Color.textSecondary,
	})
	tierOwnedLabel.Name = "TierOwned"
	tierOwnedLabel.Position = UDim2.fromOffset(0, 46)
	tierOwnedLabel.Size = UDim2.fromOffset(180, 14)

	tierIndexLabel = UiKit.label(info, {
		text = "TIER 1/5",
		size = Theme.Text.Tiny,
		font = Theme.Font.Black,
		color = Theme.Color.textFaint,
		align = Enum.TextXAlignment.Right,
	})
	tierIndexLabel.Name = "TierIndex"
	tierIndexLabel.Position = UDim2.new(1, -130, 0, 46)
	tierIndexLabel.Size = UDim2.fromOffset(130, 14)

	UiKit.rule(info, { position = UDim2.fromOffset(0, 70) })

	-- Three figures on one line: how many drones, what they produce, and what the
	-- next one is worth. Same order as the decision the player is making.
	fleetLabel = buildStat(info, 0, 112, "FLEET", Theme.Color.text, 78)
	outputLabel = buildStat(info, 124, 112, "OUTPUT", Theme.Color.starMatter, 78)
	perDroneLabel = buildStat(info, 248, 108, "PER DRONE", Theme.Color.aether, 78)
	for _, x in { 112, 238 } do
		local divider = UiKit.create("Frame", {
			BackgroundColor3 = Theme.Color.stroke,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(1, 38),
			Position = UDim2.fromOffset(x, 78),
			ZIndex = 3,
		}) :: Frame
		divider.Parent = info
	end

	-- Buy keys, bottom of the information column. The single is the primary key;
	-- the ten-pack is a quiet plate beside it, so the column has one verb.
	local dock = UiKit.create("Frame", {
		Name = "FleetDock",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 1, -46),
		Size = UDim2.new(1, 0, 0, 46),
		ZIndex = 4,
	}) :: Frame
	dock.Parent = info
	UiKit.hlist(dock, 8, Enum.VerticalAlignment.Center)

	local oneHandle = UiKit.actionButton(dock, {
		accent = Theme.Color.actionCyan,
		height = 46,
		radius = Theme.Radius.md,
		size = 15,
		solid = true,
		labelColor = Theme.Color.ink,
		labelStroke = false,
		label = "BUILD 1",
		handler = function()
			buy(1)
		end,
	})
	oneHandle.button.Name = "BuyDrone"
	oneHandle.button.Size = UDim2.new(0.44, -4, 0, 46)
	oneHandle.button.ZIndex = 5
	buyOneHandle = oneHandle

	local tenHandle = UiKit.actionButton(dock, {
		accent = Theme.Color.aether,
		height = 46,
		radius = Theme.Radius.md,
		size = 15,
		label = "BUILD 10",
		handler = function()
			buy(10)
		end,
	})
	tenHandle.button.Name = "BuyDroneTen"
	tenHandle.button.Size = UDim2.new(0.56, -4, 0, 46)
	tenHandle.button.ZIndex = 5
	buyTenHandle = tenHandle

	-- Band 3: the ladder.
	buildLadder(parent)

	buildExpedition(parent)
	buildSalvage(parent)
	buildCodex(parent)

	unsubscribe = StateStore.onSync(function(payload: Types.SyncPayload)
		DroneView.render(payload)
	end)

	local current = StateStore.current
	if current then
		DroneView.render(current)
	end
end

local function formatClock(seconds: number): string
	local total = math.max(0, math.ceil(seconds))
	if total >= 3600 then
		return string.format("%d:%02d:%02d", total // 3600, (total % 3600) // 60, total % 60)
	end
	return string.format("%d:%02d", total // 60, total % 60)
end

local expActiveShown: boolean? = nil

--- Expedition band. Repaints the shelf only when the fleet's availability can
--- have changed, and the flight line on the tick.
local function paintExpedition(payload: Types.SyncPayload)
	if expShelf == nil or expLive == nil then
		return
	end

	if expShardLabel then
		expShardLabel.Text = string.format("%d SHARDS", payload.shards)
	end

	local active = payload.expId ~= ""
	if active ~= expActiveShown then
		expActiveShown = active
		expShelf.Visible = not active
		expLive.Visible = active
	end

	local home = payload.drones
	for _, mission in ExpeditionConfig.list() do
		local handle = expButtons[mission.id]
		if handle then
			if active then
				handle.set("locked", "AWAY", Theme.Color.quantum)
			elseif home >= mission.squad then
				handle.set("ready", "SEND", Theme.Color.quantum)
			else
				handle.set("locked", string.format("NEED %d", mission.squad), Theme.Color.quantum)
			end
		end
	end

	if not active then
		return
	end

	local mission = ExpeditionConfig.get(payload.expId)
	if mission == nil then
		return
	end
	if expTitle then
		expTitle.Text = string.upper(mission.name)
	end
	if expTimer then
		expTimer.Text = formatClock(payload.expRemaining)
	end
	if expBar then
		local elapsed = mission.seconds - payload.expRemaining
		expBar.set(math.clamp(elapsed / math.max(1, mission.seconds), 0, 1))
	end
	if expReward then
		local parts = { string.format("+%s AETHER", NumberUtil.abbreviate(payload.expAether)) }
		if payload.expCores > 0 then
			parts[#parts + 1] = string.format("+%d CORES", payload.expCores)
		end
		if payload.expShards > 0 then
			parts[#parts + 1] = string.format("+%d SHARDS", payload.expShards)
		end
		expReward.Text = table.concat(parts, "  ·  ")
	end
end

local function formatShort(seconds: number): string
	local total = math.max(0, math.ceil(seconds))
	if total >= 60 then
		return string.format("%d:%02d", total // 60, total % 60)
	end
	return string.format("0:%02d", total)
end

--- Base payout at the current blade. The rack states what a cache is worth before
--- it is claimed, because a reward the player cannot see is not a decision.
local function rewardHint(rarity: SalvageConfig.Rarity): string
	local parts = { string.format("+%s AE", NumberUtil.abbreviate(rarity.aether)) }
	if rarity.cores > 0 then
		table.insert(parts, string.format("%dC", rarity.cores))
	end
	if rarity.shards > 0 then
		table.insert(parts, string.format("%dS", rarity.shards))
	end
	return table.concat(parts, "  ")
end

local function paintSalvage(payload: Types.SyncPayload)
	for index, slot in cacheSlots do
		local cache = payload.caches[index]
		local rarity = if cache then SalvageConfig.getRarity(cache.rarity) else nil

		if cache == nil or rarity == nil then
			slot.root.BackgroundColor3 = Theme.Color.panelSunken
			slot.root.BackgroundTransparency = 0.35
			slot.name.Text = "EMPTY"
			slot.name.TextColor3 = Theme.Color.textFaint
			slot.state.Text = ""
			slot.hint.Text = ""
			slot.stroke.Color = Theme.Color.stroke
			slot.stroke.Transparency = 0.35
			slot.bar.set(0)
			slot.bar.track.Visible = false
			continue
		end

		slot.name.Text = string.upper(rarity.name)
		slot.name.TextColor3 = rarity.color
		slot.stroke.Color = rarity.color
		slot.bar.track.Visible = true

		local ready = cache.readyAt > 0 and cache.secondsLeft <= 0
		if cache.readyAt <= 0 then
			slot.root.BackgroundColor3 = Theme.Color.panelSunken
			slot.root.BackgroundTransparency = 0
			slot.stroke.Transparency = 0
			slot.state.Text = "CRACK"
			slot.state.TextColor3 = Theme.Color.text
			slot.hint.Text = "TAP TO START"
			slot.bar.set(0)
		elseif not ready then
			local total = math.max(1, rarity.crackSeconds)
			slot.root.BackgroundColor3 = Theme.Color.panelSunken
			slot.root.BackgroundTransparency = 0
			slot.stroke.Transparency = 0.25
			slot.state.Text = formatShort(cache.secondsLeft)
			slot.state.TextColor3 = Theme.Color.text
			slot.hint.Text = "CRACKING"
			slot.bar.set(math.clamp(1 - cache.secondsLeft / total, 0, 1))
		else
			slot.root.BackgroundColor3 = rarity.color:Lerp(Theme.Color.ink, 0.74)
			slot.root.BackgroundTransparency = 0
			slot.stroke.Transparency = 0
			slot.state.Text = "CLAIM"
			slot.state.TextColor3 = rarity.color
			slot.hint.Text = rewardHint(rarity)
			slot.bar.set(1)
		end
	end

	local full = #payload.caches >= SalvageConfig.MaxCaches
	if cacheMeterBar then
		cacheMeterBar.set(math.clamp(payload.cacheMeter / math.max(1, payload.cacheGoal), 0, 1))
	end
	if cacheMeterText then
		cacheMeterText.Text = if full
			then "RACK FULL  ·  OPEN A CACHE TO RESUME DROPS"
			else string.format("NEXT CACHE  %d / %d STRIKES", payload.cacheMeter, payload.cacheGoal)
		cacheMeterText.TextColor3 = if full then Theme.Color.warn else Theme.Color.textSecondary
	end
	if cacheMeterNote then
		cacheMeterNote.Text = string.format("%d / %d CACHES", #payload.caches, SalvageConfig.MaxCaches)
		cacheMeterNote.TextColor3 = if full then Theme.Color.warn else Theme.Color.quantum
	end
end

local function paintCodex(payload: Types.SyncPayload)
	for setId, row in codexRows do
		local set = SalvageConfig.getSet(setId)
		if set == nil then
			continue
		end
		local progress = SalvageConfig.setProgress(setId, payload.sigils)
		local complete = progress >= #set.sigils

		for pip, dot in row.pips do
			local filled = pip <= progress
			dot.BackgroundColor3 = if filled then Theme.Color.quantum else Theme.Color.panelSunken
			local stroke = dot:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if filled then Theme.Color.quantum else Theme.Color.stroke
			end
		end

		row.bonus.TextColor3 = if complete then Theme.Color.quantum else Theme.Color.textFaint
		row.root.BackgroundColor3 = if complete then Theme.Color.quantumDeep else Theme.Color.panelSunken
		row.root.BackgroundTransparency = if complete then 0.72 else 0.35
	end

	if codexCount then
		codexCount.Text = string.format("%d / %d SETS", payload.codexSets, #SalvageConfig.SetOrder)
		codexCount.TextColor3 = if payload.codexSets > 0 then Theme.Color.quantum else Theme.Color.textFaint
	end
end

function DroneView.render(payload: Types.SyncPayload)
	if viewport == nil then
		return
	end
	latest = payload

	-- First payload picks the best rung the fleet has opened. After that the
	-- player's choice sticks, including a locked rung they are previewing.
	if selectedTier == nil or entryFor(payload, selectedTier :: string) == nil then
		selectedTier = DroneRegistry.bestUnlocked(payload.drones).id
	end
	local id = selectedTier :: string
	local entry = entryFor(payload, id)
	local tier = DroneRegistry.get(id)
	if entry == nil or tier == nil then
		return
	end

	if mountedTier ~= id then
		mountTier(id)
	end

	-- Hero.
	if tierNameLabel then
		tierNameLabel.Text = string.upper(tier.name)
		tierNameLabel.TextColor3 = tier.glow
	end
	if tierOwnedLabel then
		tierOwnedLabel.Text = string.format("%s OWNED", NumberUtil.abbreviate(entry.owned))
	end
	if tierIndexLabel then
		tierIndexLabel.Text = string.format("TIER %d/%d", tier.tier, #DroneRegistry.tiers)
	end

	-- Strip.
	if fleetLabel then
		fleetLabel.Text = NumberUtil.abbreviate(payload.drones)
	end
	if outputLabel then
		outputLabel.Text = NumberUtil.abbreviateRate(payload.passiveYield)
	end
	if perDroneLabel then
		local perDrone = if payload.drones > 0
			then payload.passiveYield / payload.drones
			else Config.BaseDroneYield * payload.mult
		perDroneLabel.Text = NumberUtil.abbreviateRate(perDrone)
	end

	-- Buy keys price the selected rung, not the best unlocked one. A locked rung
	-- states its gate; there is no separate legend under the buttons.
	local oneReady = entry.unlocked and payload.as >= entry.cost
	local tenReady = entry.unlocked and payload.as >= entry.bulk
	if buyOneHandle then
		buyOneHandle.set(
			if oneReady then "ready" else "locked",
			if entry.unlocked
				then string.format("BUILD 1  ·  %s", NumberUtil.abbreviate(entry.cost))
				else string.format("LOCKED AT %s", NumberUtil.abbreviate(entry.unlockAt)),
			Theme.Color.actionCyan
		)
	end
	if buyTenHandle then
		buyTenHandle.set(
			if tenReady then "ready" else "locked",
			if entry.unlocked
				then string.format("BUILD 10  ·  %s", NumberUtil.abbreviate(entry.bulk))
				else string.format("LOCKED AT %s", NumberUtil.abbreviate(entry.unlockAt)),
			Theme.Color.deepBlue
		)
	end

	-- Ladder. Every key repaints from the tick payload: owned count, unlock
	-- meter, and the selected border.
	local unlockedCount = 0
	for _, rungId in ladderOrder do
		local key = ladderKeys[rungId]
		local rungTier = DroneRegistry.get(rungId)
		local rung = entryFor(payload, rungId)
		if key ~= nil and rungTier ~= nil and rung ~= nil then
			if rung.unlocked then
				unlockedCount += 1
			end
			key.name.Text = string.upper(rungTier.name)
			key.name.TextColor3 = if rung.unlocked then rungTier.glow else Theme.Color.locked
			key.count.Text = NumberUtil.abbreviate(rung.owned)
			key.count.TextColor3 = if rung.owned > 0 then Theme.Color.text else Theme.Color.textDim
			local progress = if rung.unlocked
				then 1
				else math.clamp(payload.drones / math.max(1, rung.unlockAt), 0, 1)
			key.bar.Size = UDim2.fromScale(progress, 1)
			key.bar.BackgroundColor3 = if rung.unlocked then rungTier.glow else Theme.Color.strokeBright
			local chosen = rungId == id
			key.root.BackgroundColor3 = if chosen then Theme.Color.panelRaised else Theme.Color.panelSunken
			key.stroke.Color = if chosen then rungTier.glow else Theme.Color.stroke
			key.stroke.Thickness = if chosen then 2 else 1
		end
	end
	if ladderCountLabel then
		ladderCountLabel.Text = string.format("%d/%d RUNGS", unlockedCount, #ladderOrder)
	end

	paintExpedition(payload)
	paintSalvage(payload)
	paintCodex(payload)
end

--- Selects a rung and repaints. Public for the Studio seam: a ladder key cannot
--- be clicked from a script, and the five hulls are the whole point of the tab.
function DroneView.select(id: string): boolean
	if DroneRegistry.get(id) == nil then
		return false
	end
	selectedTier = id
	if latest then
		DroneView.render(latest)
	end
	return true
end

--- The rung currently on the hero. Nil before the first payload.
function DroneView.selected(): string?
	return selectedTier
end

function DroneView.destroy()	if unsubscribe then
		unsubscribe()
		unsubscribe = nil
	end
	if cleanupModel then
		cleanupModel()
		cleanupModel = nil
	end
	viewport = nil
	tierNameLabel = nil
	tierOwnedLabel = nil
	tierIndexLabel = nil
	fleetLabel = nil
	outputLabel = nil
	perDroneLabel = nil
	ladderCountLabel = nil
	buyOneHandle = nil
	buyTenHandle = nil
	selectedTier = nil
	mountedTier = nil
	latest = nil
	table.clear(ladderKeys)
	table.clear(ladderOrder)
	expShelf = nil
	expLive = nil
	expShardLabel = nil
	expTitle = nil
	expTimer = nil
	expReward = nil
	expBar = nil
	table.clear(expButtons)
	expActiveShown = nil
	table.clear(cacheSlots)
	cacheMeterBar = nil
	cacheMeterText = nil
	cacheMeterNote = nil
	table.clear(codexRows)
	codexCount = nil
end

return DroneView
