--!strict
-- Prestige tech tree. Costs are Quantum Cores; effects are declarative so the
-- server can authoritatively derive stats and the client can predict them with
-- the same code. No duplicate formulas on either side of the wire.

local Config = require(script.Parent.Config)

local TechTreeConfig = {}

export type EffectKey =
	"clickMult"
	| "sweetSpotMult"
	| "sweetSpotWidth"
	| "droneYield"
	| "offlineYield"
	| "ventYield"
	| "autoClicks"
	| "critChance"
	| "startBlades"

export type Node = {
	id: string,
	name: string,
	description: string,
	maxLevel: number,
	costBase: number,
	costGrowth: number,
	effect: EffectKey,
	perLevel: number,
	--- Parent node id. The node can be bought once the parent reaches
	--- `requiresLevel`; a save that already owns levels here keeps its bonus.
	requires: string?,
	requiresLevel: number?,
	--- Badge art key in `AssetManifest.UiArt`.
	icon: string?,
}

--- Derived stats handed to the forge loop. Produced by TechTreeConfig.compute.
export type Stats = {
	clickMult: number,
	sweetSpotMult: number,
	sweetSpotMin: number,
	sweetSpotMax: number,
	droneYieldMult: number,
	offlineMult: number,
	ventMult: number,
	autoClicksPerSec: number,
	critChance: number,
	critMult: number,
	startBlades: number,
}

local CRIT_MULTIPLIER = 5

-- Ordered roughly by when a fresh prestige should consider them.
local NODES: { Node } = {
	{
		id = "start_might",
		name = "Forged Momentum",
		description = "+25% strike yield per level.",
		maxLevel = 10,
		costBase = 1,
		costGrowth = 1.6,
		effect = "clickMult",
		perLevel = 0.25,
		icon = "tech_momentum",
	},
	{
		id = "crit_forge",
		name = "Critical Forge",
		description = "+4% chance per level for a 5x strike.",
		maxLevel = 5,
		costBase = 4,
		costGrowth = 2.2,
		effect = "critChance",
		perLevel = 0.04,
		requires = "start_might",
		requiresLevel = 3,
		icon = "tech_crit",
	},
	{
		id = "auto_click",
		name = "Phantom Hammer",
		description = "Adds 0.5 strikes per second per level.",
		maxLevel = 10,
		costBase = 5,
		costGrowth = 2,
		effect = "autoClicks",
		perLevel = 0.5,
		requires = "crit_forge",
		requiresLevel = 2,
		icon = "tech_phantom",
	},
	{
		id = "thermal_calibration",
		name = "Thermal Calibration",
		description = "Widens the sweet spot and raises its payout.",
		maxLevel = 5,
		costBase = 2,
		costGrowth = 2,
		effect = "sweetSpotMult",
		perLevel = 0.25,
		requires = "start_might",
		requiresLevel = 2,
		icon = "tech_thermal",
	},
	{
		id = "vent_efficiency",
		name = "Vent Efficiency",
		description = "+25% vent payout per level.",
		maxLevel = 8,
		costBase = 2,
		costGrowth = 1.7,
		effect = "ventYield",
		perLevel = 0.25,
		requires = "thermal_calibration",
		requiresLevel = 2,
		icon = "tech_vent",
	},
	{
		id = "drone_lattice",
		name = "Drone Lattice",
		description = "+12% fleet yield per level.",
		maxLevel = 8,
		costBase = 3,
		costGrowth = 1.85,
		effect = "droneYield",
		perLevel = 0.12,
		requires = "start_might",
		requiresLevel = 2,
		icon = "tech_lattice",
	},
	{
		id = "offline_core",
		name = "Offline Core",
		description = "+25% offline yield per level.",
		maxLevel = 8,
		costBase = 3,
		costGrowth = 1.8,
		effect = "offlineYield",
		perLevel = 0.25,
		requires = "drone_lattice",
		requiresLevel = 2,
		icon = "tech_offline",
	},
	{
		id = "head_start",
		name = "Head Start",
		description = "Begin each run with one more blade already forged.",
		maxLevel = 5,
		costBase = 3,
		costGrowth = 2.5,
		effect = "startBlades",
		perLevel = 1,
		requires = "offline_core",
		requiresLevel = 2,
		icon = "tech_head",
	},
}

local BY_ID: { [string]: Node } = {}
for _, node in NODES do
	BY_ID[node.id] = node
end

TechTreeConfig.CritMultiplier = CRIT_MULTIPLIER

--- All nodes, in display order.
function TechTreeConfig.list(): { Node }
	return NODES
end

function TechTreeConfig.get(id: string): Node?
	return BY_ID[id]
end

--- The parent node and level a node needs before its next level can be bought.
--- Nil means the node is open from the start.
function TechTreeConfig.requirement(node: Node, levels: { [string]: number }): (Node?, number?)
	if node.requires == nil then
		return nil, nil
	end
	local parent = BY_ID[node.requires]
	if parent == nil then
		return nil, nil
	end
	local needed = node.requiresLevel or 1
	if (levels[parent.id] or 0) >= needed then
		return parent, needed
	end
	return parent, needed
end

--- True when the parent requirement is met. Kept separate from `requirement`
--- because the UI needs the parent name when the gate is closed.
function TechTreeConfig.available(node: Node, levels: { [string]: number }): boolean
	local parent, needed = TechTreeConfig.requirement(node, levels)
	return parent == nil or (levels[parent.id] or 0) >= (needed or 1)
end

--- Cost of the next level, given the levels already bought. 0 when maxed.
function TechTreeConfig.cost(node: Node, currentLevel: number): number
	if currentLevel >= node.maxLevel then
		return 0
	end
	return math.floor(node.costBase * (node.costGrowth ^ currentLevel))
end

--- Splits the generic effect enum into the concrete stat fields it touches.
-- sweetSpotMult also widens the band, perLevel degrees on each side.
local BAND_WIDTH_PER_LEVEL = 2

--- Derives the full stat block from a levels table. Missing ids mean level 0.
function TechTreeConfig.compute(levels: { [string]: number }): Stats
	local stats: Stats = {
		clickMult = 1,
		sweetSpotMult = Config.SweetSpotMultiplier,
		sweetSpotMin = Config.SweetSpotMin,
		sweetSpotMax = Config.SweetSpotMax,
		droneYieldMult = 1,
		offlineMult = 1,
		ventMult = 1,
		autoClicksPerSec = 0,
		critChance = Config.BaseCritChance,
		critMult = CRIT_MULTIPLIER,
		startBlades = 0,
	}

	for _, node in NODES do
		local level = math.clamp(levels[node.id] or 0, 0, node.maxLevel)
		if level <= 0 then
			continue
		end

		local scaled = node.perLevel * level
		if node.effect == "clickMult" then
			stats.clickMult += scaled
		elseif node.effect == "sweetSpotMult" then
			stats.sweetSpotMult += scaled
			stats.sweetSpotMin -= BAND_WIDTH_PER_LEVEL * level
			stats.sweetSpotMax += BAND_WIDTH_PER_LEVEL * level
		elseif node.effect == "droneYield" then
			stats.droneYieldMult += scaled
		elseif node.effect == "offlineYield" then
			stats.offlineMult += scaled
		elseif node.effect == "ventYield" then
			stats.ventMult += scaled
		elseif node.effect == "autoClicks" then
			stats.autoClicksPerSec += scaled
		elseif node.effect == "critChance" then
			stats.critChance = math.min(stats.critChance + scaled, 0.95)
		elseif node.effect == "startBlades" then
			stats.startBlades += scaled
		end
	end

	-- A widened band must stop at the lean point, not at the old five-point
	-- gap before overheat. At max Thermal Calibration `OverheatAt - 5` reached
	-- 95 while the penalty started at 90, so the top five points printed a
	-- 2.5x band caption and paid 0.5x. The band can end where the penalty
	-- begins; it cannot overlap it.
	stats.sweetSpotMax = math.min(stats.sweetSpotMax, Config.PenaltyFrom)
	stats.sweetSpotMin = math.max(stats.sweetSpotMin, 10)

	return stats
end

--- The number of blades a prestige start hands the player for free.
function TechTreeConfig.startingBladeIds(levels: { [string]: number }): { string }
	local stats = TechTreeConfig.compute(levels)
	local ids: { string } = {}
	local blades = require(script.Parent.BladeRegistry).list()

	-- Always include the starter, then count upward from index 1.
	table.insert(ids, blades[1].id)
	for index = 2, math.min(1 + stats.startBlades, #blades) do
		table.insert(ids, blades[index].id)
	end
	return ids
end

return TechTreeConfig
