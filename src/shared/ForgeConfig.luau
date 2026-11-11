--!strict
-- The forge: tiered RNG pools, blade variants, and the duplicate economy.
--
-- The old model was a ladder: every blade had a price and the next one was
-- always the better one. That made every roll of the economy predictable, which
-- is the one thing a forge should never be. This file turns the catalogue into
-- five weighted pools and adds a second axis, the variant, so the same blade can
-- come out of the fire five different ways.
--
-- Everything here is data. `BladeRegistry` still owns the blades themselves; this
-- owns how they are rolled, priced, and what a copy is worth once it is melted.

local BladeRegistry = require(script.Parent.BladeRegistry)
local ModifierConfig = require(script.Parent.ModifierConfig)

local ForgeConfig = {}

--- The shape `power`/`salvageValue` need from a copy. Structural so the server's
--- `BladeInstance` and the client's `InvEntry` both satisfy it without ForgeConfig
--- requiring Types (which would be a cycle through the registry).
export type CopyLike = {
	id: string,
	variant: string,
	element: string?,
	grade: string?,
	prefix: string?,
	suffix: string?,
}

-- ---------------------------------------------------------------------------
-- Variants
-- ---------------------------------------------------------------------------

export type Variant = {
	id: string,
	name: string,
	--- Relative weight out of the sum of every variant weight.
	weight: number,
	--- Multiplies the blade's registry multiplier.
	mult: number,
	--- Extra stats. Additive with rune and codex bonuses.
	critChance: number,
	shardMult: number,
	ventMult: number,
	coolMult: number,
	--- Colour used for the viewport glow and the row chip.
	color: Color3,
	--- One line of copy. The row shows it instead of a stat list.
	text: string,
}

ForgeConfig.Variants = {
	standard = {
		id = "standard",
		name = "Standard",
		weight = 74,
		mult = 1,
		critChance = 0,
		shardMult = 1,
		ventMult = 1,
		coolMult = 1,
		color = Color3.fromRGB(196, 204, 216),
		text = "As it left the anvil.",
	} :: Variant,

	tempered = {
		id = "tempered",
		name = "Tempered",
		weight = 14,
		mult = 1.35,
		critChance = 0,
		shardMult = 1,
		ventMult = 1,
		coolMult = 1.15,
		color = Color3.fromRGB(255, 107, 0),
		text = "Quenched twice. Cools 15% faster.",
	} :: Variant,

	overclocked = {
		id = "overclocked",
		name = "Overclocked",
		weight = 8,
		mult = 1.6,
		critChance = 0.05,
		shardMult = 1,
		ventMult = 1,
		coolMult = 1,
		color = Color3.fromRGB(0, 210, 255),
		text = "Runs hot. +5% crit chance.",
	} :: Variant,

	void = {
		id = "void",
		name = "Void-Touched",
		weight = 3,
		mult = 2.2,
		critChance = 0,
		shardMult = 2,
		ventMult = 1,
		coolMult = 1,
		color = Color3.fromRGB(199, 125, 255),
		text = "The core went somewhere else. 2x Void Shards.",
	} :: Variant,

	prismatic = {
		id = "prismatic",
		name = "Prismatic",
		weight = 1,
		mult = 3.5,
		critChance = 0,
		shardMult = 1,
		ventMult = 1.25,
		coolMult = 1,
		color = Color3.fromRGB(255, 194, 60),
		text = "Every colour at once. +25% Aether on vent.",
	} :: Variant,
}

ForgeConfig.VariantOrder = { "standard", "tempered", "overclocked", "void", "prismatic" }

function ForgeConfig.variant(id: string): Variant
	return (ForgeConfig.Variants :: any)[id] or ForgeConfig.Variants.standard
end

--- True when `id` is a real variant. Save sanitising uses this rather than
--- indexing the map, so a strict-mode build stays happy.
function ForgeConfig.hasVariant(id: string): boolean
	for _, variant in ForgeConfig.Variants do
		if variant.id == id then
			return true
		end
	end
	return false
end

ForgeConfig.StandardVariant = "standard"

-- ---------------------------------------------------------------------------
-- Rarity weights
-- ---------------------------------------------------------------------------

--- Weight per registry rarity. Each tier pool holds exactly one blade of each
--- rarity, so a rarity roll is also a blade roll.
---
--- Balance pass: the top two weights were thinned. At 4 / 1 a player saw a Void
--- or Quantum blade roughly once in eighteen rolls, which filled the codex far
--- ahead of the drone curve and made the forge feel like a formality. At 2.4 /
--- 0.35 that is once in thirty-eight, and the pity counter is what guarantees a
--- player who is genuinely trying still gets there.
ForgeConfig.RarityWeights = {
	Scrap = 55,
	Forged = 29,
	Astral = 13,
	Void = 2.4,
	Quantum = 0.35,
}

ForgeConfig.RarityOrder = { "Scrap", "Forged", "Astral", "Void", "Quantum" }

--- Rarities that satisfy a pity guarantee. "Epic or better" in this catalogue is
--- Void and Quantum.
ForgeConfig.PityRarities = { Void = true, Quantum = true }

-- ---------------------------------------------------------------------------
-- Tiers
-- ---------------------------------------------------------------------------

export type Tier = {
	tier: number,
	--- Stable id. The roll action names a crate, not a number, so a catalogue
	--- reorder can never silently change what a client is buying.
	id: string,
	name: string,
	--- Three or four letters for the crate rail and the drop table header.
	short: string,
	--- One line under the name in the crate browser.
	blurb: string,
	--- Star-Matter per roll.
	cost: number,
	--- Lifetime Star-Matter needed for this crate to come online.
	unlock: number,
	--- Rolls without a Void or Quantum before one is forced.
	pity: number,
	--- Scrap refunded for melting a Standard copy from this tier.
	scrap: number,
	--- Rarity weights for this crate alone. A crate is a pool, not a price.
	weights: { [string]: number },
	--- Crate accent: the rail chip, the viewport rim and the banner.
	accent: Color3,
	--- Model family passed to `CratePreview`, so each crate renders apart.
	shape: string,
}

--- Five crates, one per blade tier.
---
--- The single banner was the wrong shape for a gacha page: the only decision a
--- player had was when to press the button, and the pool changed underneath them
--- by lifetime income rather than by choice. Now the tier is a choice, each crate
--- is a distinct pool with its own odds, and the unlock is still driven by
--- lifetime Star-Matter so a new crate is a milestone rather than a shop item.
---
--- The weight columns are the whole balance. A crate earns its price by moving
--- weight from Scrap and Forged into the top three rarities, not by multiplying
--- the payout: standard is 2.4% Void, singularity is 38%.
---
--- Unlocks were widened with the drone nerf. Lifetime Star-Matter is the shared
--- clock, so stretching these stretches the codex next to it: the last tier used
--- to open at 2e11 and now opens at 4e11, and the fourth at 6e8 instead of 2e8.
ForgeConfig.Tiers = {
	{
		tier = 1,
		id = "standard",
		name = "Standard Forge Crate",
		short = "STD",
		blurb = "The yard crate. Bolted, banded, and honest about the odds.",
		cost = 50,
		unlock = 0,
		pity = 12,
		scrap = 6,
		weights = { Scrap = 55, Forged = 29, Astral = 13, Void = 2.4, Quantum = 0.35 },
		accent = Color3.fromRGB(255, 194, 60),
		shape = "crate",
	} :: Tier,
	{
		tier = 2,
		id = "void",
		name = "Void Capsule",
		short = "VOID",
		blurb = "Sealed in the dark. Something inside is still counting.",
		cost = 1400,
		unlock = 6e4,
		pity = 11,
		scrap = 14,
		weights = { Scrap = 30, Forged = 38, Astral = 22, Void = 8.6, Quantum = 1.4 },
		accent = Color3.fromRGB(199, 125, 255),
		shape = "capsule",
	} :: Tier,
	{
		tier = 3,
		id = "quantum",
		name = "Quantum Relic",
		short = "QNT",
		blurb = "Two states at once. Both of them sharp.",
		cost = 9e4,
		unlock = 8e6,
		pity = 10,
		scrap = 30,
		weights = { Scrap = 14, Forged = 32, Astral = 36, Void = 15, Quantum = 3 },
		accent = Color3.fromRGB(0, 210, 255),
		shape = "relic",
	} :: Tier,
	{
		tier = 4,
		id = "celestial",
		name = "Celestial Core",
		short = "CEL",
		blurb = "Cut from something that was already old when the yard was new.",
		cost = 6e6,
		unlock = 6e8,
		pity = 9,
		scrap = 60,
		weights = { Scrap = 6, Forged = 20, Astral = 40, Void = 26, Quantum = 8 },
		accent = Color3.fromRGB(255, 54, 200),
		shape = "core",
	} :: Tier,
	{
		tier = 5,
		id = "singularity",
		name = "Singularity Vault",
		short = "SNG",
		blurb = "The last box. It does not open so much as remember opening.",
		cost = 4e8,
		unlock = 4e11,
		pity = 8,
		scrap = 120,
		weights = { Scrap = 2, Forged = 10, Astral = 34, Void = 38, Quantum = 16 },
		accent = Color3.fromRGB(255, 236, 180),
		shape = "vault",
	} :: Tier,
}

--- The banner the player is on. Monotonic, driven by lifetime Star-Matter, so it
--- can never deadlock behind an unlucky roll.
function ForgeConfig.tierFor(lifetime: number): Tier
	local best = ForgeConfig.Tiers[1]
	for _, tier in ForgeConfig.Tiers do
		if lifetime >= tier.unlock then
			best = tier
		end
	end
	return best
end

function ForgeConfig.tierAt(index: number): Tier?
	return ForgeConfig.Tiers[index]
end

--- A crate by id, or nil. The roll action uses this rather than a list index.
function ForgeConfig.crate(id: string?): Tier?
	if id == nil then
		return nil
	end
	for _, tier in ForgeConfig.Tiers do
		if tier.id == id then
			return tier
		end
	end
	return nil
end

--- True when `lifetime` has opened this crate.
function ForgeConfig.crateUnlocked(tier: Tier, lifetime: number): boolean
	return lifetime >= tier.unlock
end

--- Normalised drop table for the crate browser, ordered rarest first so the
--- expensive rows sit at the top where a player is looking.
export type Odds = { rarity: string, weight: number, chance: number }

function ForgeConfig.odds(tier: Tier): { Odds }
	local total = 0
	for _, rarity in ForgeConfig.RarityOrder do
		total += tier.weights[rarity] or 0
	end
	local out: { Odds } = {}
	if total <= 0 then
		return out
	end
	for index = #ForgeConfig.RarityOrder, 1, -1 do
		local rarity = ForgeConfig.RarityOrder[index]
		local weight = tier.weights[rarity] or 0
		if weight > 0 then
			table.insert(out, {
				rarity = rarity,
				weight = weight,
				chance = weight / total,
			})
		end
	end
	return out
end

-- ---------------------------------------------------------------------------
-- Roll price ramp
-- ---------------------------------------------------------------------------
-- The banner sets the base price; the ramp makes the next roll cost more than
-- the last one did. Without it the forge is a flat 50 Star-Matter forever and
-- the hundredth roll costs exactly what the first did, which removes the only
-- reason to earn more than one roll ahead.
--
-- Per banner, and capped. An unbounded exponential eventually prices the loop
-- out of existence, and a player who cannot roll has nothing to do; 12x base is
-- the ceiling. The counter resets when the banner changes and on ascension.
ForgeConfig.RollCostGrowth = 1.05
ForgeConfig.RollCostCap = 12

--- Strikes of current income a roll must cost before the banner price applies.
---
--- The bug this exists for: `tier.cost` is a fixed number per banner (2e8 at
--- Cosmic) while the player's per-click yield compounds with blades, variants,
--- modifiers and tech. Live, a 16B-per-click profile was buying rolls for 288M,
--- which is eighteen thousandths of one click. The cost was being deducted; it
--- was simply invisible, so the forge read as free.
---
--- Pricing a roll at this many strikes keeps the purchase legible at every point
--- on the curve: early runs pay the banner price (income is still small), and a
--- late profile pays a fraction of a second of its own output instead of a
--- rounding error. Growth still happens through `RollCostGrowth` on top.
ForgeConfig.RollIncomeStrikes = 18

--- Income floor per crate, in strikes.
---
--- The floor is what makes a roll legible on a late profile, but a flat floor made
--- all five pools cost the same the moment income passed the top banner price:
--- live, Standard and Singularity both quoted 673.40B, so the cheap pools were
--- pure upside and the expensive one had no reason to exist. Multiplying the
--- floor by the crate's own rung keeps the ladder: Standard is 18 strikes,
--- Void 36, Quantum 54, Celestial 72, Singularity 90.
function ForgeConfig.floorStrikes(tier: Tier): number
	return ForgeConfig.RollIncomeStrikes * math.max(1, tier.tier)
end

--- Price of the next roll: base cost for the crate, ramped by the rolls taken
--- on it, scaled by account progress, and floored by current income.
---
--- `scale` and `income` are passed in by the server rather than read here,
--- because this module is shared and the profile is not. `income` is the
--- player's un-critical per-strike yield (`ProgressionService.clickYield`).
function ForgeConfig.rollCost(tier: Tier, rolls: number, scale: number?, income: number?): number
	local safe = math.max(0, math.floor(rolls))
	-- 1.05^safe reaches inf past ~14000 rolls; the clamp keeps the number finite
	-- so the button prints an absurd price instead of `inf`.
	local factor = math.min(ForgeConfig.RollCostGrowth ^ safe, ForgeConfig.RollCostCap)
	local progress = math.max(1, scale or 1)
	local banner = math.max(1, math.floor(tier.cost * factor * progress))
	local floor = math.max(1, math.floor(math.max(0, income or 0) * ForgeConfig.floorStrikes(tier)))
	return math.max(banner, floor)
end

--- How many rolls at this banner it takes to reach the ceiling. The vault and
--- the forge header use it to print how far up the ramp the player is.
function ForgeConfig.rollsToCap(): number
	local steps = math.log(ForgeConfig.RollCostCap) / math.log(ForgeConfig.RollCostGrowth)
	return math.ceil(steps)
end

--- Price of `count` consecutive rolls on one crate, ramp included.
---
--- The multi-roll is not `count * rollCost`. The ramp is the sink: roll ten at
--- the price of roll one and the ten-pull undercuts the single by a wide margin
--- exactly when the player has the income to spam it. This sums the geometric
--- series the ramp actually is, and a ten-pull therefore costs what ten clicks
--- would have.
function ForgeConfig.bulkRollCost(tier: Tier, rolls: number, count: number, scale: number?, income: number?): number
	if count <= 0 then
		return 0
	end
	if count == 1 then
		return ForgeConfig.rollCost(tier, rolls, scale, income)
	end
	local progress = math.max(1, scale or 1)
	local floorCost = math.max(1, math.floor(math.max(0, income or 0) * ForgeConfig.floorStrikes(tier)))
	local ramp = ForgeConfig.RollCostGrowth
	local safe = math.max(0, math.floor(rolls))
	-- Sum of min(growth^r, cap) over r in [rolls, rolls + count). Past the cap
	-- every term is the cap, so the tail is a straight multiply.
	local capped = ForgeConfig.RollCostCap
	local total = 0
	for step = 0, count - 1 do
		local factor = math.min(ramp ^ (safe + step), capped)
		total += math.max(math.floor(tier.cost * factor * progress), floorCost)
	end
	return math.min(math.floor(total), 1e308)
end

-- ---------------------------------------------------------------------------
-- Variant reroll
-- ---------------------------------------------------------------------------

--- Scrap cost to reroll one blade's variant. Two melts at the same tier buys a
--- reroll at tier 1, then the price climbs with the banner.
function ForgeConfig.rerollCost(tier: number): number
	return 12 + (tier - 1) * 10
end

--- Scrap returned when a copy is melted. Variant rarity is part of the value, so
--- melting a Prismatic by accident still pays something back. Modifier axes add a
--- small premium: a Transcendent copy is worth more than a Chipped one even when
--- the blade behind it is the same, which is what makes a spare Mythic worth
--- keeping until the vault fills.
function ForgeConfig.salvageValue(
	bladeId: string,
	variantId: string,
	elementId: string?,
	gradeId: string?,
	prefixId: string?,
	suffixId: string?
): number
	local blade = BladeRegistry.get(bladeId)
	if blade == nil then
		return 0
	end
	local tier = ForgeConfig.Tiers[math.clamp(blade.tier, 1, #ForgeConfig.Tiers)]
	local variantIndex = 0
	for index, id in ForgeConfig.VariantOrder do
		if id == variantId then
			variantIndex = index
			break
		end
	end
	local mods = ModifierConfig.power(gradeId or "", elementId or "", prefixId or "", suffixId or "")
	return math.floor(tier.scrap * (1 + (variantIndex - 1) * 0.6) * (0.85 + mods * 0.15))
end

--- `salvageValue` for a whole copy record.
function ForgeConfig.salvageCopy(copy: CopyLike): number
	return ForgeConfig.salvageValue(copy.id, copy.variant, copy.element, copy.grade, copy.prefix, copy.suffix)
end

-- ---------------------------------------------------------------------------
-- Rolls
-- ---------------------------------------------------------------------------

function ForgeConfig.rollVariant(): Variant
	local total = 0
	for _, variant in ForgeConfig.Variants do
		total += variant.weight
	end
	local pick = math.random() * total
	local running = 0
	for _, id in ForgeConfig.VariantOrder do
		local variant = ForgeConfig.Variants[id]
		running += variant.weight
		if pick <= running then
			return variant
		end
	end
	return ForgeConfig.Variants.standard
end

--- Rolls a rarity from `tier`'s pool. `forcePity` promotes anything below Void
--- to the pity rarities this crate actually carries, so a crate that does not
--- stock Quantum cannot be forced into it.
function ForgeConfig.rollRarity(forcePity: boolean?, tier: Tier?): BladeRegistry.Rarity
	local weights = if tier then tier.weights else ForgeConfig.RarityWeights

	local pool: { string } = {}
	local total = 0
	if forcePity then
		for _, rarity in ForgeConfig.RarityOrder do
			local weight = weights[rarity] or 0
			if ForgeConfig.PityRarities[rarity] and weight > 0 then
				table.insert(pool, rarity)
				total += weight
			end
		end
	end
	if total <= 0 then
		table.clear(pool)
		for _, rarity in ForgeConfig.RarityOrder do
			local weight = weights[rarity] or 0
			if weight > 0 then
				table.insert(pool, rarity)
				total += weight
			end
		end
	end
	if total <= 0 then
		return "Scrap"
	end

	local pick = math.random() * total
	local running = 0
	for _, rarity in pool do
		running += weights[rarity] or 0
		if pick <= running then
			return rarity :: BladeRegistry.Rarity
		end
	end
	return pool[#pool] :: BladeRegistry.Rarity
end

--- The blade in `tier` with `rarity`, falling back to any blade in the tier.
function ForgeConfig.pickBlade(tierIndex: number, rarity: BladeRegistry.Rarity): BladeRegistry.Blade?
	local tierPool: { BladeRegistry.Blade } = {}
	for _, blade in BladeRegistry.list() do
		if blade.tier == tierIndex then
			table.insert(tierPool, blade)
			if blade.rarity == rarity then
				return blade
			end
		end
	end
	if #tierPool == 0 then
		return BladeRegistry.list()[1]
	end
	return tierPool[math.random(1, #tierPool)]
end

--- Registry multiplier times variant multiplier, times every modifier on the
--- copy. The one place that answers "what is this copy actually worth".
function ForgeConfig.power(
	bladeId: string,
	variantId: string,
	elementId: string?,
	gradeId: string?,
	prefixId: string?,
	suffixId: string?
): number
	local blade = BladeRegistry.get(bladeId)
	if blade == nil then
		return 1
	end
	local mods = ModifierConfig.power(gradeId or "", elementId or "", prefixId or "", suffixId or "")
	return blade.multiplier * ForgeConfig.variant(variantId).mult * mods
end

--- `power` for a whole copy record. Server and client both go through this so a
--- card, an equip-best pass and the leaderboard cannot rank the same blade three
--- different ways.
function ForgeConfig.powerCopy(copy: CopyLike): number
	return ForgeConfig.power(copy.id, copy.variant, copy.element, copy.grade, copy.prefix, copy.suffix)
end

return ForgeConfig
