--!strict
-- Forge Feats: the account-wide goal ladder.
--
-- The problem this solves is the one every incremental hits after the first
-- lucky run: the numbers are big, the ladder still has rungs, but the player has
-- nothing to aim at. Feats are thirty-five one-time achievements drawn from
-- counters the profile already keeps, so they need no new save fields and no
-- claim button. Completed feats pay a permanent global multiplier, which makes
-- breadth worth chasing instead of only the next blade.
--
-- Goals are deliberately spread across every system: fortune, prestige, tech,
-- mastery, codex and the fleet. A player who is rich but has never opened a
-- crate still has a next goal, and a player who has finished the tech tree
-- still has ten more.
--
-- The same module scores the profile on the server and the payload on the
-- client. The two can never drift because there is only one table.

local RuneConfig = require(script.Parent.RuneConfig)
local SalvageConfig = require(script.Parent.SalvageConfig)
local Types = require(script.Parent.Types)

local FeatConfig = {}

export type Input = {
	lifetimeSm: number,
	lifetimeCores: number,
	ascensions: number,
	techLevels: number,
	masteryIds: number,
	masteryRank: number,
	codexCount: number,
	codexSets: number,
	drones: number,
}

export type Feat = {
	id: string,
	name: string,
	note: string,
	--- Key into the readers table below.
	stat: string,
	target: number,
}

export type FeatProgress = {
	feat: Feat,
	value: number,
	progress: number,
}

--- Every feat is +1% to all yield. Thirty-five feats is a 35% account bonus,
--- which is meaningful without outrunning the blade ladder it sits beside.
FeatConfig.PerFeatBonus = 0.01

local FEATS: { Feat } = {
	-- Fortune: lifetime Star-Matter. The long number that never goes down.
	{ id = "fortune_1", name = "Pocket Change", note = "Earn 1K lifetime Star-Matter", stat = "lifetimeSm", target = 1e3 },
	{ id = "fortune_2", name = "First Million", note = "Earn 1M lifetime Star-Matter", stat = "lifetimeSm", target = 1e6 },
	{ id = "fortune_3", name = "Serious Fortune", note = "Earn 1B lifetime Star-Matter", stat = "lifetimeSm", target = 1e9 },
	{ id = "fortune_4", name = "Deep Pockets", note = "Earn 1T lifetime Star-Matter", stat = "lifetimeSm", target = 1e12 },
	{ id = "fortune_5", name = "Star Baron", note = "Earn 1Qa lifetime Star-Matter", stat = "lifetimeSm", target = 1e15 },
	{ id = "fortune_6", name = "Cosmic Wealth", note = "Earn 1Qi lifetime Star-Matter", stat = "lifetimeSm", target = 1e18 },

	-- Prestige. Cores are the currency that survives the reset.
	{ id = "cores_1", name = "First Cores", note = "Collect 5 lifetime Quantum Cores", stat = "lifetimeCores", target = 5 },
	{ id = "cores_2", name = "Core Collector", note = "Collect 25 lifetime Quantum Cores", stat = "lifetimeCores", target = 25 },
	{ id = "cores_3", name = "Prestige Engine", note = "Collect 100 lifetime Quantum Cores", stat = "lifetimeCores", target = 100 },
	{ id = "cores_4", name = "Core Tycoon", note = "Collect 500 lifetime Quantum Cores", stat = "lifetimeCores", target = 500 },
	{ id = "cores_5", name = "Quantum Mint", note = "Collect 2.5K lifetime Quantum Cores", stat = "lifetimeCores", target = 2500 },

	-- Ascension count. The reset is the mechanic, so it gets its own ladder.
	{ id = "ascend_1", name = "First Ascension", note = "Ascend once", stat = "ascensions", target = 1 },
	{ id = "ascend_2", name = "Cycle Breaker", note = "Ascend 5 times", stat = "ascensions", target = 5 },
	{ id = "ascend_3", name = "Reborn Smith", note = "Ascend 15 times", stat = "ascensions", target = 15 },
	{ id = "ascend_4", name = "Eternal Return", note = "Ascend 40 times", stat = "ascensions", target = 40 },

	-- Tech. Sixty levels exist, so the last one is the finished tree.
	{ id = "tech_1", name = "Tech Apprentice", note = "Buy 10 tech levels", stat = "techLevels", target = 10 },
	{ id = "tech_2", name = "Tech Adept", note = "Buy 25 tech levels", stat = "techLevels", target = 25 },
	{ id = "tech_3", name = "Tech Master", note = "Buy 40 tech levels", stat = "techLevels", target = 40 },
	{ id = "tech_4", name = "Tree Complete", note = "Buy every tech level", stat = "techLevels", target = 59 },

	-- Mastery. Survives ascension, so this is a true account-wide ladder.
	{ id = "mastery_1", name = "Blade Collector", note = "Land a strike with 5 different blades", stat = "masteryIds", target = 5 },
	{ id = "mastery_2", name = "Armory", note = "Land a strike with 12 different blades", stat = "masteryIds", target = 12 },
	{ id = "mastery_3", name = "Living Index", note = "Land a strike with every blade", stat = "masteryIds", target = 25 },
	{ id = "mastery_4", name = "Rank Three", note = "Reach mastery rank 3 with any blade", stat = "masteryRank", target = 3 },
	{ id = "mastery_5", name = "Master Smith", note = "Reach mastery rank 5 with any blade", stat = "masteryRank", target = 5 },

	-- Codex. One point per distinct blade, variant, element, grade or affix.
	{ id = "codex_1", name = "Codex Opened", note = "Discover 10 codex entries", stat = "codexCount", target = 10 },
	{ id = "codex_2", name = "Archivist", note = "Discover 25 codex entries", stat = "codexCount", target = 25 },
	{ id = "codex_3", name = "Loremaster", note = "Discover 50 codex entries", stat = "codexCount", target = 50 },
	{ id = "codex_4", name = "Living Legend", note = "Discover 75 codex entries", stat = "codexCount", target = 75 },

	-- Salvage sets. Four sets of three sigils is the collection endgame.
	{ id = "set_1", name = "Set One", note = "Complete one sigil set", stat = "codexSets", target = 1 },
	{ id = "set_2", name = "Set Two", note = "Complete two sigil sets", stat = "codexSets", target = 2 },
	{ id = "set_3", name = "Full Salvage", note = "Complete every sigil set", stat = "codexSets", target = 4 },

	-- Fleet. Drones are the passive half of the loop.
	{ id = "fleet_1", name = "Fleet Ten", note = "Own 10 drones", stat = "drones", target = 10 },
	{ id = "fleet_2", name = "Fleet Fifty", note = "Own 50 drones", stat = "drones", target = 50 },
	{ id = "fleet_3", name = "Fleet One Fifty", note = "Own 150 drones", stat = "drones", target = 150 },
	{ id = "fleet_4", name = "Fleet Four Hundred", note = "Own 400 drones", stat = "drones", target = 400 },
}

local READERS: { [string]: (Input) -> number } = {
	lifetimeSm = function(input: Input): number
		return input.lifetimeSm
	end,
	lifetimeCores = function(input: Input): number
		return input.lifetimeCores
	end,
	ascensions = function(input: Input): number
		return input.ascensions
	end,
	techLevels = function(input: Input): number
		return input.techLevels
	end,
	masteryIds = function(input: Input): number
		return input.masteryIds
	end,
	masteryRank = function(input: Input): number
		return input.masteryRank
	end,
	codexCount = function(input: Input): number
		return input.codexCount
	end,
	codexSets = function(input: Input): number
		return input.codexSets
	end,
	drones = function(input: Input): number
		return input.drones
	end,
}

local function countMastery(mastery: { [string]: number }): (number, number)
	local ids = 0
	local rank = 0
	for _, strikes in mastery do
		if strikes > 0 then
			ids += 1
			rank = math.max(rank, RuneConfig.masteryRank(strikes))
		end
	end
	return ids, rank
end

local function countTech(tech: { [string]: number }): number
	local total = 0
	for _, level in tech do
		total += math.max(0, math.floor(level))
	end
	return total
end

--- Snapshot from the persisted profile, used by the server's yield maths.
function FeatConfig.fromState(state: Types.ProfileState): Input
	local masteryIds, masteryRank = countMastery(state.mastery)
	local drones = 0
	for _, count in state.fleet do
		drones += count
	end
	return {
		lifetimeSm = state.lifetimeStarMatter,
		lifetimeCores = state.lifetimeCores,
		ascensions = state.ascensions,
		techLevels = countTech(state.tech),
		masteryIds = masteryIds,
		masteryRank = masteryRank,
		-- codexVersion starts at 1 before any discovery.
		codexCount = math.max(0, state.codexVersion - 1),
		codexSets = SalvageConfig.bonus(state.sigils).sets,
		drones = drones,
	}
end

--- Snapshot from the 10Hz payload, used by the feats panel and NextGoal.
function FeatConfig.fromSync(payload: Types.SyncPayload): Input
	local masteryIds, masteryRank = countMastery(payload.masteryAll)
	return {
		lifetimeSm = payload.lifetimeSm,
		lifetimeCores = payload.lifetimeCores,
		ascensions = payload.ascensions,
		techLevels = countTech(payload.tech),
		masteryIds = masteryIds,
		masteryRank = masteryRank,
		codexCount = math.max(0, payload.codexVersion - 1),
		codexSets = payload.codexSets,
		drones = payload.drones,
	}
end

function FeatConfig.list(): { Feat }
	return FEATS
end

function FeatConfig.total(): number
	return #FEATS
end

function FeatConfig.value(feat: Feat, input: Input): number
	local reader = READERS[feat.stat]
	if reader == nil then
		return 0
	end
	return math.max(0, reader(input))
end

function FeatConfig.progress(feat: Feat, input: Input): number
	if feat.target <= 0 then
		return 1
	end
	return math.clamp(FeatConfig.value(feat, input) / feat.target, 0, 1)
end

function FeatConfig.isComplete(feat: Feat, input: Input): boolean
	return FeatConfig.value(feat, input) >= feat.target
end

--- How many feats are complete, and the account multiplier they pay.
function FeatConfig.completed(input: Input): number
	local count = 0
	for _, feat in FEATS do
		if FeatConfig.isComplete(feat, input) then
			count += 1
		end
	end
	return count
end

function FeatConfig.multiplier(input: Input): number
	return 1 + FeatConfig.PerFeatBonus * FeatConfig.completed(input)
end

--- The nearest incomplete feats, ordered by how close they are. Completed feats
--- are omitted; a goal at 100% is a receipt, not a goal.
function FeatConfig.next(input: Input, limit: number?): { FeatProgress }
	local open: { FeatProgress } = {}
	for _, feat in FEATS do
		local value = FeatConfig.value(feat, input)
		if value < feat.target then
			table.insert(open, {
				feat = feat,
				value = value,
				progress = FeatConfig.progress(feat, input),
			})
		end
	end
	table.sort(open, function(a: FeatProgress, b: FeatProgress): boolean
		if a.progress == b.progress then
			return a.feat.id < b.feat.id
		end
		return a.progress > b.progress
	end)
	local count = math.min(limit or #open, #open)
	local out: { FeatProgress } = {}
	for index = 1, count do
		out[index] = open[index]
	end
	return out
end

return FeatConfig
