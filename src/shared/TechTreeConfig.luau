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
	requires: string?,
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
		description = "+25% click yield per level.",
		maxLevel = 10,
		costBase = 1,
		costGrowth = 1.6,
		effect = "clickMult",
		perLevel = 0.25,
		icon = "tech_momentum",
	},
	{
		id = "thermal_calibration",
		name = "Thermal Calibration",
		description = "Widens the sweet spot and raises its multiplier.",
		maxLevel = 5,
		costBase = 2,
		costGrowth = 2,
		effect = "sweetSpotMult",
		perLevel = 0.25,
		icon = "tech_thermal",
	},
	{
		id = "drone_lattice",
		name = "Drone Lattice",
		description = "+12% drone yield per level.",
		maxLevel = 8,
		costBase = 3,
		costGrowth = 1.85,
		effect = "droneYield",
		perLevel = 0.12,
		icon = "tech_lattice",
	},
	{
		id = "vent_efficiency",
		name = "Vent Efficiency",
		description = "+25% Aether Shards when venting heat per level.",
		maxLevel = 8,
		costBase = 2,
		costGrowth = 1.7,
		effect = "ventYield",
		perLevel = 0.25,
		icon = "tech_vent",
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
		icon = "tech_offline",
	},
	{
		id = "crit_forge",
		name = "Critical Forge",
		description = "+4% chance per level for a 5x click.",
		maxLevel = 5,
		costBase = 4,
		costGrowth = 2.2,
		effect = "critChance",
		perLevel = 0.04,
		icon = "tech_crit",
	},
	{
		id = "auto_click",
		name = "Phantom Hammer",
		description = "Forge 0.5 extra strikes per second per level.",
		maxLevel = 10,
		costBase = 5,
		costGrowth = 2,
		effect = "autoClicks",
		perLevel = 0.5,
		icon = "tech_phantom",
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
		critChance = 0,
		critMult = CRIT_MULTIPLIER,
		startBlades = 0,
	}

	for _, node in NODES do
		local level = levels[node.id] or 0
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

	-- A widened band must still leave a gap before overheat.
	stats.sweetSpotMax = math.min(stats.sweetSpotMax, Config.OverheatAt - 5)
	stats.sweetSpotMin = math.max(stats.sweetSpotMin, 10)

	return stats
end

--- Thenumber of blades a prestige start hands the player for free.
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
