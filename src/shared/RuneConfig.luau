--!strict
-- Blade mastery, sockets, and the rune catalogue.
--
-- Mastery is earned by striking with a blade equipped: one strike, one point.
-- Ranks unlock sockets, sockets hold runes, and runes move the strike maths.
-- Everything here is integers and flat percentages so the client can predict a
-- number from the payload without asking the server for an opinion.
--
-- The ladder is deliberately long. Rank 1 arrives inside the first minute so the
-- system announces itself, and rank 5 is a multi-hour goal for a blade the
-- player actually likes rather than one they happened to hold.

local Config = require(script.Parent.Config)

local RuneConfig = {}

export type Rune = {
	id: string,
	name: string,
	description: string,
	--- Which stat this rune moves.
	effect: "click" | "cool" | "crit" | "vent",
	--- Amount per socketed rune. 0.08 is +8%.
	perRune: number,
	--- Void Shards to craft one.
	cost: number,
	--- Badge art key in `AssetManifest.UiArt`.
	icon: string?,
}

export type RuneBonus = {
	clickMult: number,
	coolMult: number,
	critChance: number,
	ventMult: number,
}

--- Strikes on a blade required to reach each rank. Length is the max rank.
RuneConfig.Thresholds = { 100, 400, 1200, 3000, 8000 }

--- Sockets unlocked at each rank. Index is the rank, so a fresh blade holds
--- none until its first rank and a mastered one holds three.
RuneConfig.SocketsByRank = { 0, 1, 1, 2, 3, 3 }

RuneConfig.MaxSockets = 3

--- Base anomaly drop. Void Shards are the only currency in the game that comes
--- from risk rather than time, which is what makes a hot gauge worth holding.
RuneConfig.ShardsPerDrop = 2

RuneConfig.Runes = {
	ember = {
		id = "ember",
		name = "Ember Rune",
		description = "+8% strike yield.",
		effect = "click",
		perRune = 0.08,
		cost = 6,
		icon = "rune_ember",
	} :: Rune,

	tempo = {
		id = "tempo",
		name = "Tempo Rune",
		description = "+6% heat cooling.",
		effect = "cool",
		perRune = 0.06,
		cost = 6,
		icon = "rune_tempo",
	} :: Rune,

	edge = {
		id = "edge",
		name = "Edge Rune",
		description = "+3% crit chance.",
		effect = "crit",
		perRune = 0.03,
		cost = 9,
		icon = "rune_edge",
	} :: Rune,

	prism = {
		id = "prism",
		name = "Prism Rune",
		description = "+10% Aether from venting.",
		effect = "vent",
		perRune = 0.10,
		cost = 12,
		icon = "rune_prism",
	} :: Rune,
}

--- Display order for the rune shelf. Fixed rather than `pairs`, which has no
--- order and would shuffle the shelf on every rebuild.
RuneConfig.Order = { "ember", "tempo", "edge", "prism" }

local BY_ID: { [string]: Rune } = {}
for _, rune in RuneConfig.Runes do
	BY_ID[rune.id] = rune
end

function RuneConfig.get(id: string): Rune?
	return BY_ID[id]
end

function RuneConfig.list(): { Rune }
	local out: { Rune } = {}
	for _, id in RuneConfig.Order do
		out[#out + 1] = RuneConfig.Runes[id]
	end
	return out
end

--- Rank 0..5 for a strike count.
function RuneConfig.masteryRank(strikes: number): number
	local rank = 0
	for index, threshold in RuneConfig.Thresholds do
		if strikes >= threshold then
			rank = index
		else
			break
		end
	end
	return rank
end

--- Strikes needed for the next rank, or nil at max. The UI shows the distance to
--- the next socket rather than an absolute total, because that is the decision.
function RuneConfig.nextThreshold(strikes: number): number?
	local rank = RuneConfig.masteryRank(strikes)
	local nextValue = RuneConfig.Thresholds[rank + 1]
	return nextValue
end

function RuneConfig.socketsFor(rank: number): number
	local index = math.clamp(rank + 1, 1, #RuneConfig.SocketsByRank)
	return RuneConfig.SocketsByRank[index]
end

--- Sums every rune socketed into `slots`. Unknown ids are ignored so a save
--- written against an older catalogue cannot error on boot.
function RuneConfig.sum(slots: { string }): RuneBonus
	local bonus: RuneBonus = { clickMult = 1, coolMult = 1, critChance = 0, ventMult = 1 }
	for _, id in slots do
		local rune = BY_ID[id]
		if rune == nil then
			continue
		end
		if rune.effect == "click" then
			bonus.clickMult += rune.perRune
		elseif rune.effect == "cool" then
			bonus.coolMult += rune.perRune
		elseif rune.effect == "crit" then
			bonus.critChance += rune.perRune
		elseif rune.effect == "vent" then
			bonus.ventMult += rune.perRune
		end
	end
	return bonus
end

--- Strikes counted at most once per frame; guards against a profile that somehow
--- recorded a fractional count.
function RuneConfig.sanitiseCount(value: unknown): number
	if type(value) ~= "number" or value ~= value then
		return 0
	end
	return math.max(0, math.floor(value))
end

RuneConfig.AnomalyHeatFloor = Config.AnomalyHeatFloor

return RuneConfig
