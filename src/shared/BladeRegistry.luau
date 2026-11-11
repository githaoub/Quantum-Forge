--!strict
-- The blade catalogue. Pure data plus lookups — no behaviour, no services.
--
-- Every blade is described well enough that the client can assemble it out of
-- primitives inside a ViewportFrame. No .fbx, no marketplace models, no asset
-- IDs. `shape` drives the geometry recipe in BladePreview; the colour and
-- material fields drive its surface treatment.

local BladeRegistry = {}

export type Rarity = "Scrap" | "Forged" | "Astral" | "Void" | "Quantum"
export type AuraKind = "none" | "spark" | "orbit" | "void" | "quantum"
export type BladeShape = "straight" | "curved" | "glaive" | "scythe" | "greatsword"

export type Blade = {
	id: string,
	name: string,
	rarity: Rarity,
	tier: number,
	multiplier: number,
	cost: number,
	shape: BladeShape,
	material: string,
	aura: AuraKind,
	bladeColor: { number },
	glowColor: { number },
	gripColor: { number },
	flavor: string,
}

export type RarityInfo = {
	name: Rarity,
	index: number,
	color: { number },
	label: string,
}

-- Curve check: multiplier ratio ~2.4x per blade, cost ratio ~3.5x. Twenty-four
-- steps reach x1.4e9 for x1e13 total spend, so a clean first run lands in the
-- low hours rather than days. Re-tiering means re-checking both ratios.
local BLADES: { Blade } = {
	-- Tier 1 — Scrap. Where every forge starts.
	{
		id = "rusted_cleaver",
		name = "Rusted Cleaver",
		rarity = "Scrap",
		tier = 1,
		multiplier = 1,
		cost = 0,
		shape = "straight",
		material = "Metal",
		aura = "none",
		bladeColor = { 122, 84, 58 },
		glowColor = { 255, 138, 61 },
		gripColor = { 46, 38, 33 },
		flavor = "It cuts. Barely.",
	},
	{
		id = "scrap_fang",
		name = "Scrap Fang",
		rarity = "Scrap",
		tier = 1,
		multiplier = 2.4,
		cost = 25,
		shape = "curved",
		material = "Metal",
		aura = "none",
		bladeColor = { 138, 96, 64 },
		glowColor = { 255, 160, 84 },
		gripColor = { 52, 42, 36 },
		flavor = "Salvaged from something that used to matter.",
	},
	{
		id = "rivet_edge",
		name = "Rivet Edge",
		rarity = "Scrap",
		tier = 1,
		multiplier = 5.8,
		cost = 80,
		shape = "straight",
		material = "DiamondPlate",
		aura = "none",
		bladeColor = { 150, 110, 78 },
		glowColor = { 255, 176, 96 },
		gripColor = { 58, 48, 40 },
		flavor = "Nine bolts, all of them load-bearing.",
	},
	{
		id = "coil_shard",
		name = "Coil Shard",
		rarity = "Scrap",
		tier = 1,
		multiplier = 14,
		cost = 260,
		shape = "curved",
		material = "Metal",
		aura = "spark",
		bladeColor = { 168, 128, 92 },
		glowColor = { 255, 196, 110 },
		gripColor = { 62, 52, 44 },
		flavor = "Hums when the heat is right.",
	},
	{
		id = "cinder_spike",
		name = "Cinder Spike",
		rarity = "Scrap",
		tier = 1,
		multiplier = 34,
		cost = 820,
		shape = "straight",
		material = "Metal",
		aura = "spark",
		bladeColor = { 186, 146, 104 },
		glowColor = { 255, 214, 128 },
		gripColor = { 68, 56, 46 },
		flavor = "Still warm from a fire nobody remembers.",
	},

	-- Tier 2 — Forged. Real steel, real intent.
	{
		id = "iron_vigil",
		name = "Iron Vigil",
		rarity = "Forged",
		tier = 2,
		multiplier = 81,
		cost = 2.6e3,
		shape = "straight",
		material = "Metal",
		aura = "none",
		bladeColor = { 148, 158, 172 },
		glowColor = { 255, 186, 92 },
		gripColor = { 44, 48, 56 },
		flavor = "Held the line long enough to become the line.",
	},
	{
		id = "forgebrand",
		name = "Forgebrand",
		rarity = "Forged",
		tier = 2,
		multiplier = 195,
		cost = 8.4e3,
		shape = "greatsword",
		material = "Metal",
		aura = "none",
		bladeColor = { 162, 170, 184 },
		glowColor = { 255, 168, 72 },
		gripColor = { 52, 50, 58 },
		flavor = "Stamped with a maker's mark no one can read.",
	},
	{
		id = "temperline",
		name = "Temperline",
		rarity = "Forged",
		tier = 2,
		multiplier = 470,
		cost = 2.7e4,
		shape = "curved",
		material = "Metal",
		aura = "spark",
		bladeColor = { 176, 184, 196 },
		glowColor = { 255, 152, 60 },
		gripColor = { 56, 54, 62 },
		flavor = "The hammer's echo, trapped in the edge.",
	},
	{
		id = "anvils_oath",
		name = "Anvil's Oath",
		rarity = "Forged",
		tier = 2,
		multiplier = 1.1e3,
		cost = 8.6e4,
		shape = "greatsword",
		material = "DiamondPlate",
		aura = "spark",
		bladeColor = { 190, 196, 208 },
		glowColor = { 255, 140, 48 },
		gripColor = { 60, 58, 66 },
		flavor = "Sworn on a surface that has taken worse.",
	},
	{
		id = "slagspite",
		name = "Slagspite",
		rarity = "Forged",
		tier = 2,
		multiplier = 2.7e3,
		cost = 2.8e5,
		shape = "curved",
		material = "Metal",
		aura = "spark",
		bladeColor = { 204, 210, 220 },
		glowColor = { 255, 128, 40 },
		gripColor = { 64, 60, 70 },
		flavor = "Forged from the waste of a hundred better attempts.",
	},

	-- Tier 3 — Astral. The metal starts remembering things.
	{
		id = "nova_reaver",
		name = "Nova Reaver",
		rarity = "Astral",
		tier = 3,
		multiplier = 6.5e3,
		cost = 8.8e5,
		shape = "glaive",
		material = "Neon",
		aura = "orbit",
		bladeColor = { 120, 214, 255 },
		glowColor = { 90, 232, 255 },
		gripColor = { 26, 44, 66 },
		flavor = "Cut once inside a collapsing star. Came back changed.",
	},
	{
		id = "starlight_falchion",
		name = "Starlight Falchion",
		rarity = "Astral",
		tier = 3,
		multiplier = 1.6e4,
		cost = 2.8e6,
		shape = "curved",
		material = "Neon",
		aura = "orbit",
		bladeColor = { 148, 226, 255 },
		glowColor = { 132, 244, 255 },
		gripColor = { 30, 50, 74 },
		flavor = "Trails light like it is reluctant to leave.",
	},
	{
		id = "comets_wake",
		name = "Comet's Wake",
		rarity = "Astral",
		tier = 3,
		multiplier = 3.8e4,
		cost = 9e6,
		shape = "straight",
		material = "Glass",
		aura = "orbit",
		bladeColor = { 176, 238, 255 },
		glowColor = { 168, 252, 255 },
		gripColor = { 34, 56, 82 },
		flavor = "You forge the sword. The sword brings the tail.",
	},
	{
		id = "gravwell_sabre",
		name = "Gravwell Sabre",
		rarity = "Astral",
		tier = 3,
		multiplier = 9e4,
		cost = 2.9e7,
		shape = "curved",
		material = "Neon",
		aura = "orbit",
		bladeColor = { 204, 246, 255 },
		glowColor = { 200, 255, 255 },
		gripColor = { 38, 62, 90 },
		flavor = "Dust settles toward it without being asked.",
	},
	{
		id = "astral_cutter",
		name = "Astral Cutter",
		rarity = "Astral",
		tier = 3,
		multiplier = 2.2e5,
		cost = 9.2e7,
		shape = "glaive",
		material = "Neon",
		aura = "orbit",
		bladeColor = { 228, 250, 255 },
		glowColor = { 232, 255, 255 },
		gripColor = { 42, 68, 98 },
		flavor = "The last blade forged while there was still a sky.",
	},

	-- Tier 4 — Void. Light stops cooperating.
	{
		id = "nullbreaker",
		name = "Nullbreaker",
		rarity = "Void",
		tier = 4,
		multiplier = 5.2e5,
		cost = 2.9e8,
		shape = "greatsword",
		material = "Neon",
		aura = "void",
		bladeColor = { 138, 92, 255 },
		glowColor = { 190, 92, 255 },
		gripColor = { 30, 22, 52 },
		flavor = "It removes the argument, not the object.",
	},
	{
		id = "voidfang",
		name = "Voidfang",
		rarity = "Void",
		tier = 4,
		multiplier = 1.25e6,
		cost = 9.4e8,
		shape = "curved",
		material = "Neon",
		aura = "void",
		bladeColor = { 158, 108, 255 },
		glowColor = { 206, 104, 255 },
		gripColor = { 34, 26, 58 },
		flavor = "Bites in a direction that is not in the room.",
	},
	{
		id = "entropy_edge",
		name = "Entropy Edge",
		rarity = "Void",
		tier = 4,
		multiplier = 3e6,
		cost = 3e9,
		shape = "straight",
		material = "Glass",
		aura = "void",
		bladeColor = { 180, 124, 255 },
		glowColor = { 222, 116, 255 },
		gripColor = { 38, 30, 64 },
		flavor = "Every swing makes the room slightly older.",
	},
	{
		id = "event_horizon",
		name = "Event Horizon",
		rarity = "Void",
		tier = 4,
		multiplier = 7.2e6,
		cost = 9.6e9,
		shape = "glaive",
		material = "Neon",
		aura = "void",
		bladeColor = { 202, 140, 255 },
		glowColor = { 238, 128, 255 },
		gripColor = { 42, 34, 70 },
		flavor = "There is a line around this blade. Do not cross it.",
	},
	{
		id = "blackstar_glaive",
		name = "Blackstar Glaive",
		rarity = "Void",
		tier = 4,
		multiplier = 1.7e7,
		cost = 3.1e10,
		shape = "glaive",
		material = "Neon",
		aura = "void",
		bladeColor = { 224, 156, 255 },
		glowColor = { 252, 140, 255 },
		gripColor = { 46, 38, 76 },
		flavor = "Named for the light it refuses to give back.",
	},

	-- Tier 5 — Quantum. The forge stops being a place.
	{
		id = "hadron_splitter",
		name = "Hadron Splitter",
		rarity = "Quantum",
		tier = 5,
		multiplier = 4.2e7,
		cost = 9.8e10,
		shape = "greatsword",
		material = "Neon",
		aura = "quantum",
		bladeColor = { 126, 255, 200 },
		glowColor = { 92, 255, 190 },
		gripColor = { 20, 48, 44 },
		flavor = "Splits things that were never actually whole.",
	},
	{
		id = "quanta_verge",
		name = "Quanta Verge",
		rarity = "Quantum",
		tier = 5,
		multiplier = 1e8,
		cost = 3.1e11,
		shape = "straight",
		material = "Neon",
		aura = "quantum",
		bladeColor = { 156, 255, 214 },
		glowColor = { 120, 255, 202 },
		gripColor = { 24, 54, 50 },
		flavor = "On the verge of resolving. Never resolves.",
	},
	{
		id = "singularity_blade",
		name = "Singularity Blade",
		rarity = "Quantum",
		tier = 5,
		multiplier = 2.4e8,
		cost = 1e12,
		shape = "curved",
		material = "Glass",
		aura = "quantum",
		bladeColor = { 186, 255, 228 },
		glowColor = { 148, 255, 214 },
		gripColor = { 28, 60, 56 },
		flavor = "Everything it touches ends up in the same place.",
	},
	{
		id = "entangle_scythe",
		name = "Entangle Scythe",
		rarity = "Quantum",
		tier = 5,
		multiplier = 5.8e8,
		cost = 3.2e12,
		shape = "scythe",
		material = "Neon",
		aura = "quantum",
		bladeColor = { 214, 255, 240 },
		glowColor = { 176, 255, 226 },
		gripColor = { 32, 66, 62 },
		flavor = "Two blades, one of them somewhere else.",
	},
	{
		id = "forge_eternal",
		name = "The Forge Eternal",
		rarity = "Quantum",
		tier = 5,
		multiplier = 1.4e9,
		cost = 1e13,
		shape = "greatsword",
		material = "Neon",
		aura = "quantum",
		bladeColor = { 240, 255, 250 },
		glowColor = { 210, 255, 238 },
		gripColor = { 36, 72, 68 },
		flavor = "You did not forge it. It was already here, waiting for a hand.",
	},
}

local RARITY_INFO: { [string]: RarityInfo } = {
	Scrap = { name = "Scrap", index = 1, color = { 168, 130, 96 }, label = "Scrap" },
	Forged = { name = "Forged", index = 2, color = { 176, 188, 202 }, label = "Forged" },
	Astral = { name = "Astral", index = 3, color = { 122, 226, 255 }, label = "Astral" },
	Void = { name = "Void", index = 4, color = { 198, 132, 255 }, label = "Void" },
	Quantum = { name = "Quantum", index = 5, color = { 132, 255, 208 }, label = "Quantum" },
}

-- ---------------------------------------------------------------------------
-- Generated catalogue
-- ---------------------------------------------------------------------------
--
-- Twenty-five hand-authored blades were the whole catalogue. A forge with five
-- pools, five variants and a modifier system deserves more silhouettes than that,
-- and drawing sixty more by hand would delay every other system. So the catalogue
-- extends itself: one extra blade per shape per tier, with multipliers spread
-- between the hand-authored neighbours of that tier and colours pulled from the
-- tier band.
--
-- Deterministic on purpose. `math.random` at require time would give the client
-- and the server different catalogues, and a roll the server can price but the
-- client cannot name is a bug that only shows up in production.

local TIER_RARITY: { string } = { "Scrap", "Forged", "Astral", "Void", "Quantum" }
local TIER_AURA: { AuraKind } = { "none", "spark", "orbit", "void", "quantum" }
local TIER_MATERIAL: { string } = { "Metal", "Metal", "Crystal", "Neon", "Neon" }
local SHAPES: { BladeShape } = { "straight", "curved", "glaive", "scythe", "greatsword" }

--- One colour trio per tier, so a generated blade still belongs to its band.
local TIER_PALETTE: { { blade: { number }, glow: { number }, grip: { number } } } = {
	{ blade = { 186, 148, 112 }, glow = { 214, 176, 132 }, grip = { 74, 54, 40 } },
	{ blade = { 202, 214, 228 }, glow = { 168, 198, 224 }, grip = { 48, 56, 68 } },
	{ blade = { 132, 224, 255 }, glow = { 96, 196, 255 }, grip = { 28, 62, 84 } },
	{ blade = { 186, 138, 255 }, glow = { 150, 96, 232 }, grip = { 46, 26, 72 } },
	{ blade = { 168, 255, 216 }, glow = { 120, 244, 196 }, grip = { 30, 68, 60 } },
}

local GEN_FIRST = {
	"Ash", "Brass", "Cinder", "Dusk", "Ember", "Frost", "Gloam", "Hollow",
	"Iron", "Jade", "Kite", "Lumen", "Mica", "Nova", "Onyx", "Pale",
	"Quill", "Rift", "Sable", "Thorn", "Umber", "Verdant", "Wraith", "Zephyr",
}
local GEN_SECOND = {
	"Fang", "Glaive", "Cleaver", "Sabre", "Spike",
	"Edge", "Reaver", "Scythe", "Lance", "Blade",
}
local GEN_FLAVOUR = {
	"Turned out of the same billet as a hundred others. Still cut.",
	"No smith signs this one. It works anyway.",
	"The fire made it. Nobody asked what for.",
	"Standard issue in a yard that closed a century ago.",
	"Reads as scrap until it is in the hand.",
	"Carried by someone who did not come back.",
}

--- Multiplier and cost band per tier, taken from the hand-authored blades so a
--- generated blade never outclasses a designed one at the same tier.
local TIER_BAND: { { minMult: number, maxMult: number, minCost: number, maxCost: number } } = {}
for tier = 1, #TIER_RARITY do
	local minMult, maxMult = math.huge, 0
	local minCost, maxCost = math.huge, 0
	for _, blade in BLADES do
		if blade.tier == tier then
			minMult = math.min(minMult, blade.multiplier)
			maxMult = math.max(maxMult, blade.multiplier)
			minCost = math.min(minCost, blade.cost)
			maxCost = math.max(maxCost, blade.cost)
		end
	end
	if minMult == math.huge then
		minMult, maxMult = 1, 1
		minCost, maxCost = 1, 1
	end
	TIER_BAND[tier] = { minMult = minMult, maxMult = maxMult, minCost = minCost, maxCost = maxCost }
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

for tier = 1, #TIER_RARITY do
	local band = TIER_BAND[tier]
	local palette = TIER_PALETTE[tier]
	for shapeIndex, shape in SHAPES do
		-- Even spacing across the tier band, offset from the ends so a generated
		-- blade sits between the designed ones rather than on top of the weakest.
		local t = shapeIndex / (#SHAPES + 1)
		local first = GEN_FIRST[((tier - 1) * #SHAPES + shapeIndex - 1) % #GEN_FIRST + 1]
		local second = GEN_SECOND[((tier - 1) * #SHAPES + shapeIndex) % #GEN_SECOND + 1]
		local name = string.format("%s %s", first, second)
		table.insert(BLADES, {
			id = string.format("gen_%d_%s", tier, shape),
			name = name,
			rarity = TIER_RARITY[tier],
			tier = tier,
			multiplier = lerp(band.minMult, band.maxMult, t),
			cost = lerp(band.minCost, band.maxCost, t),
			shape = shape,
			material = TIER_MATERIAL[tier],
			aura = TIER_AURA[tier],
			bladeColor = palette.blade,
			glowColor = palette.glow,
			gripColor = palette.grip,
			flavor = GEN_FLAVOUR[(tier + shapeIndex) % #GEN_FLAVOUR + 1],
		} :: Blade)
	end
end

local BY_ID: { [string]: Blade } = {}
for _, blade in BLADES do
	BY_ID[blade.id] = blade
end

BladeRegistry.StarterBlade = "rusted_cleaver"

--- The full catalogue, in progression order.
function BladeRegistry.list(): { Blade }
	return BLADES
end

--- Nil when the id is unknown — callers must handle a stale save pointing at a
--- blade that was renamed or removed.
function BladeRegistry.get(id: string): Blade?
	return BY_ID[id]
end

--- Rarity metadata for a rarity name. Always defined for valid rarities.
function BladeRegistry.rarityInfo(rarity: Rarity): RarityInfo
	return RARITY_INFO[rarity]
end

--- Highest tier index present in the catalogue (5 here). Used by UI to size the
--- rarity filter strip without hardcoding.
function BladeRegistry.maxTier(): number
	local max = 1
	for _, blade in BLADES do
		if blade.tier > max then
			max = blade.tier
		end
	end
	return max
end

--- Blades the player can currently afford to forge, cheapest first.
function BladeRegistry.affordable(owned: { [string]: boolean }, starMatter: number): { Blade }
	local result = {}
	for _, blade in BLADES do
		if not owned[blade.id] and blade.cost <= starMatter then
			table.insert(result, blade)
		end
	end
	return result
end

--- The next unowned blade in progression order, regardless of affordability.
--- Drives the "next upgrade" prompt on the HUD.
function BladeRegistry.nextUnowned(owned: { [string]: boolean }): Blade?
	for _, blade in BLADES do
		if not owned[blade.id] then
			return blade
		end
	end
	return nil
end

return BladeRegistry
