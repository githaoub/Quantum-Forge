--!strict
-- Salvage caches: the RNG acquisition layer.
--
-- Three retention levers from the session-time notes sit in one loop here:
--
--   * pre-acquisition RNG   the rarity is rolled the moment a cache drops and
--                           is visible on the rack, so a Void cache is something
--                           the player can see and want before they open it
--   * a real time hurdle    cracking runs on the unix clock, so a Prime or Void
--                           cache keeps the session open and is still cracking
--                           (or already done) when the player rejoins
--   * a collection goal     twelve sigils in four sets; completing a set is a
--                           permanent multiplier, which is the D7 reason
--
-- Rewards are computed at claim, not at drop. A cache parked overnight is worth
-- what the player's blade is worth when they open it, not what it was worth when
-- they were small.

local SalvageConfig = {}

export type RarityId = "common" | "rare" | "prime" | "void"

export type Rarity = {
	id: RarityId,
	name: string,
	--- Relative weight out of the sum of every weight.
	weight: number,
	--- Seconds between CRACK and CLAIM. Zero means it opens on the same tick.
	crackSeconds: number,
	--- Base Aether before the blade and global multipliers.
	aether: number,
	cores: number,
	shards: number,
	--- Chance the claim also rolls a sigil. 1 means always.
	sigilChance: number,
	color: Color3,
}

--- How many accepted strikes fill the meter, and how many caches the rack holds.
--- The cap is what makes the rack a decision: a full rack stops the meter, so a
--- player who hoards is choosing to stop earning drops.
SalvageConfig.StrikesPerCache = 40
SalvageConfig.MaxCaches = 3

SalvageConfig.Rarities = {
	common = {
		id = "common",
		name = "Scrap Cache",
		weight = 58,
		crackSeconds = 0,
		aether = 60,
		cores = 0,
		shards = 0,
		sigilChance = 0.08,
		color = Color3.fromRGB(181, 190, 203),
	} :: Rarity,

	rare = {
		id = "rare",
		name = "Alloy Cache",
		weight = 28,
		crackSeconds = 45,
		aether = 260,
		cores = 1,
		shards = 1,
		sigilChance = 0.30,
		color = Color3.fromRGB(96, 214, 246),
	} :: Rarity,

	prime = {
		id = "prime",
		name = "Prime Cache",
		weight = 10,
		crackSeconds = 180,
		aether = 1200,
		cores = 5,
		shards = 4,
		sigilChance = 0.70,
		color = Color3.fromRGB(255, 194, 60),
	} :: Rarity,

	void = {
		id = "void",
		name = "Void Cache",
		weight = 4,
		crackSeconds = 600,
		aether = 7000,
		cores = 22,
		shards = 14,
		sigilChance = 1,
		color = Color3.fromRGB(199, 125, 255),
	} :: Rarity,
}

--- Display order, cheapest first. Fixed so the codex and the rack never shuffle.
SalvageConfig.Order = { "common", "rare", "prime", "void" }

export type SetStat = "click" | "cool" | "crit" | "vent"

export type Sigil = {
	id: string,
	name: string,
	set: string,
}

export type SigilSet = {
	id: string,
	name: string,
	stat: SetStat,
	--- Flat multiplier added to the rune-style bonus when the set completes.
	amount: number,
	sigils: { string },
}

SalvageConfig.SigilSets = {
	ember = {
		id = "ember",
		name = "EMBER SET",
		stat = "click",
		amount = 0.06,
		sigils = { "ember_i", "ember_ii", "ember_iii" },
	} :: SigilSet,

	tempo = {
		id = "tempo",
		name = "TEMPO SET",
		stat = "cool",
		amount = 0.08,
		sigils = { "tempo_i", "tempo_ii", "tempo_iii" },
	} :: SigilSet,

	edge = {
		id = "edge",
		name = "EDGE SET",
		stat = "crit",
		amount = 0.03,
		sigils = { "edge_i", "edge_ii", "edge_iii" },
	} :: SigilSet,

	prism = {
		id = "prism",
		name = "PRISM SET",
		stat = "vent",
		amount = 0.12,
		sigils = { "prism_i", "prism_ii", "prism_iii" },
	} :: SigilSet,
}

SalvageConfig.SetOrder = { "ember", "tempo", "edge", "prism" }

SalvageConfig.Sigils = {
	ember_i = { id = "ember_i", name = "Cinder Sigil", set = "ember" } :: Sigil,
	ember_ii = { id = "ember_ii", name = "Bellows Sigil", set = "ember" } :: Sigil,
	ember_iii = { id = "ember_iii", name = "Crucible Sigil", set = "ember" } :: Sigil,

	tempo_i = { id = "tempo_i", name = "Quench Sigil", set = "tempo" } :: Sigil,
	tempo_ii = { id = "tempo_ii", name = "Temper Sigil", set = "tempo" } :: Sigil,
	tempo_iii = { id = "tempo_iii", name = "Pulse Sigil", set = "tempo" } :: Sigil,

	edge_i = { id = "edge_i", name = "Hone Sigil", set = "edge" } :: Sigil,
	edge_ii = { id = "edge_ii", name = "Keening Sigil", set = "edge" } :: Sigil,
	edge_iii = { id = "edge_iii", name = "Bite Sigil", set = "edge" } :: Sigil,

	prism_i = { id = "prism_i", name = "Spectrum Sigil", set = "prism" } :: Sigil,
	prism_ii = { id = "prism_ii", name = "Facet Sigil", set = "prism" } :: Sigil,
	prism_iii = { id = "prism_iii", name = "Aurora Sigil", set = "prism" } :: Sigil,
}

--- Sequential ids in display order, so the codex grid is stable.
SalvageConfig.SigilOrder = {
	"ember_i",
	"ember_ii",
	"ember_iii",
	"tempo_i",
	"tempo_ii",
	"tempo_iii",
	"edge_i",
	"edge_ii",
	"edge_iii",
	"prism_i",
	"prism_ii",
	"prism_iii",
}

export type Bonus = {
	clickMult: number,
	coolMult: number,
	critChance: number,
	ventMult: number,
	sets: number,
}

--- Rolls a rarity. Weights are summed rather than assumed to be 100, so tuning a
--- single weight cannot silently bias the table.
function SalvageConfig.rollRarity(): Rarity
	local total = 0
	for _, rarity in SalvageConfig.Rarities do
		total += rarity.weight
	end
	local pick = math.random() * total
	local running = 0
	for _, id in SalvageConfig.Order do
		local rarity = SalvageConfig.Rarities[id]
		running += rarity.weight
		if pick <= running then
			return rarity
		end
	end
	return SalvageConfig.Rarities.common
end

function SalvageConfig.getRarity(id: string): Rarity?
	return (SalvageConfig.Rarities :: any)[id]
end

function SalvageConfig.getSigil(id: string): Sigil?
	return (SalvageConfig.Sigils :: any)[id]
end

function SalvageConfig.getSet(id: string): SigilSet?
	return (SalvageConfig.SigilSets :: any)[id]
end

--- Picks an unowned sigil uniformly, or nil once the codex is complete.
function SalvageConfig.rollSigil(owned: { [string]: boolean }): Sigil?
	local pool: { Sigil } = {}
	for _, id in SalvageConfig.SigilOrder do
		if not owned[id] then
			table.insert(pool, SalvageConfig.Sigils[id])
		end
	end
	if #pool == 0 then
		return nil
	end
	return pool[math.random(1, #pool)]
end

--- Set bonuses for an owned-sigil map. Unknown keys are ignored, so a save
--- written against an older codex cannot error on boot.
function SalvageConfig.bonus(owned: { [string]: boolean }): Bonus
	local bonus: Bonus = { clickMult = 1, coolMult = 1, critChance = 0, ventMult = 1, sets = 0 }
	for _, setId in SalvageConfig.SetOrder do
		local set = SalvageConfig.SigilSets[setId]
		local complete = true
		for _, sigilId in set.sigils do
			if not owned[sigilId] then
				complete = false
				break
			end
		end
		if not complete then
			continue
		end
		bonus.sets += 1
		if set.stat == "click" then
			bonus.clickMult += set.amount
		elseif set.stat == "cool" then
			bonus.coolMult += set.amount
		elseif set.stat == "crit" then
			bonus.critChance += set.amount
		elseif set.stat == "vent" then
			bonus.ventMult += set.amount
		end
	end
	return bonus
end

--- How many of a set's sigils are owned, for the codex pips.
function SalvageConfig.setProgress(setId: string, owned: { [string]: boolean }): number
	local set = (SalvageConfig.SigilSets :: any)[setId]
	if set == nil then
		return 0
	end
	local count = 0
	for _, sigilId in set.sigils do
		if owned[sigilId] then
			count += 1
		end
	end
	return count
end

return SalvageConfig
