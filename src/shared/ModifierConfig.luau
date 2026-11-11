--!strict
-- The second and third axes of a roll: element, grade, and two affixes.
--
-- Variants gave the forge five outcomes. That is not a collection: a player who
-- has seen every variant of their favourite blade has seen everything it can be.
-- This module adds the layers that make a top roll worth screenshotting:
--
--   element   13 typed primaries, each with its own stat line and colour
--   grade     8 quality bands, weighted hard toward the bottom
--   prefix    a rolled adjective, 30% chance, small power and a stat
--   suffix    "of ..." tail, 22% chance, rarer and stronger
--
-- The catalogue is 25 blades x 5 variants x 13 elements x 8 grades x 21 prefixes
-- (none included) x 21 suffixes = 5,733,000 possible copies. Everything below is
-- data plus pure functions, so the client and the server cannot disagree about
-- what a roll is worth.

local ModifierConfig = {}

-- ---------------------------------------------------------------------------
-- Elements
-- ---------------------------------------------------------------------------

export type Element = {
	id: string,
	name: string,
	weight: number,
	--- Multiplies the blade-variant-grade product.
	mult: number,
	critChance: number,
	ventMult: number,
	coolMult: number,
	shardMult: number,
	color: Color3,
	text: string,
}

ModifierConfig.Elements = {
	ember = {
		id = "ember",
		name = "Ember",
		weight = 26,
		mult = 1.06,
		critChance = 0.02,
		ventMult = 1,
		coolMult = 1,
		shardMult = 1,
		color = Color3.fromRGB(255, 120, 60),
		text = "+2% crit. The edge stays warm.",
	} :: Element,
	frost = {
		id = "frost",
		name = "Frost",
		weight = 20,
		mult = 1.06,
		critChance = 0,
		ventMult = 1,
		coolMult = 1.08,
		shardMult = 1,
		color = Color3.fromRGB(120, 200, 255),
		text = "Cools 8% faster.",
	} :: Element,
	storm = {
		id = "storm",
		name = "Storm",
		weight = 16,
		mult = 1.08,
		critChance = 0.03,
		ventMult = 1,
		coolMult = 1,
		shardMult = 1,
		color = Color3.fromRGB(150, 180, 255),
		text = "+3% crit. It hums before it lands.",
	} :: Element,
	venom = {
		id = "venom",
		name = "Venom",
		weight = 13,
		mult = 1.08,
		critChance = 0,
		ventMult = 1.06,
		coolMult = 1,
		shardMult = 1,
		color = Color3.fromRGB(140, 230, 90),
		text = "+6% Aether on vent.",
	} :: Element,
	terra = {
		id = "terra",
		name = "Terra",
		weight = 11,
		mult = 1.1,
		critChance = 0,
		ventMult = 1,
		coolMult = 1,
		shardMult = 1.1,
		color = Color3.fromRGB(210, 166, 96),
		text = "+10% Void Shard odds.",
	} :: Element,
	radiant = {
		id = "radiant",
		name = "Radiant",
		weight = 7,
		mult = 1.14,
		critChance = 0.04,
		ventMult = 1,
		coolMult = 1,
		shardMult = 1,
		color = Color3.fromRGB(255, 230, 140),
		text = "+4% crit. Daylight, folded into steel.",
	} :: Element,
	void = {
		id = "void",
		name = "Void",
		weight = 5,
		mult = 1.18,
		critChance = 0,
		ventMult = 1,
		coolMult = 1,
		shardMult = 1.5,
		color = Color3.fromRGB(170, 110, 255),
		text = "+50% Void Shard odds.",
	} :: Element,
	chrono = {
		id = "chrono",
		name = "Chrono",
		weight = 2,
		mult = 1.25,
		critChance = 0,
		ventMult = 1,
		coolMult = 1.15,
		shardMult = 1,
		color = Color3.fromRGB(120, 255, 220),
		text = "Cools 15% faster. It was already cool.",
	} :: Element,
	--- Expansion wave. Five more primaries, each owning an axis pair the first
	--- eight left half-covered: crit plus cooling, vent plus shard, a flat
	--- multiplier with no riders, and two high-weight rares that pull the whole
	--- ladder up when they land.
	gale = {
		id = "gale",
		name = "Gale",
		weight = 9,
		mult = 1.07,
		critChance = 0.025,
		ventMult = 1,
		coolMult = 1.05,
		shardMult = 1,
		color = Color3.fromRGB(178, 232, 255),
		text = "+2.5% crit, cooling 5%.",
	} :: Element,
	cinder = {
		id = "cinder",
		name = "Cinder",
		weight = 8,
		mult = 1.09,
		critChance = 0,
		ventMult = 1.11,
		coolMult = 1,
		shardMult = 1,
		color = Color3.fromRGB(255, 96, 62),
		text = "+11% Aether on vent. Still burning.",
	} :: Element,
	abyss = {
		id = "abyss",
		name = "Abyss",
		weight = 4,
		mult = 1.12,
		critChance = 0,
		ventMult = 1,
		coolMult = 1,
		shardMult = 1.7,
		color = Color3.fromRGB(92, 84, 190),
		text = "+70% Void Shard odds.",
	} :: Element,
	aureate = {
		id = "aureate",
		name = "Aureate",
		weight = 2.5,
		mult = 1.22,
		critChance = 0.01,
		ventMult = 1.02,
		coolMult = 1.02,
		shardMult = 1.05,
		color = Color3.fromRGB(255, 220, 120),
		text = "+22% power. Everything gold, nothing wasteful.",
	} :: Element,
	prism = {
		id = "prism",
		name = "Prism",
		weight = 1.2,
		mult = 1.3,
		critChance = 0.03,
		ventMult = 1.06,
		coolMult = 1.06,
		shardMult = 1.2,
		color = Color3.fromRGB(190, 255, 250),
		text = "+30% power, every rider lit.",
	} :: Element,
}

ModifierConfig.ElementOrder = {
	"ember", "frost", "storm", "venom", "terra", "radiant", "void", "chrono",
	"gale", "cinder", "abyss", "aureate", "prism",
}

-- ---------------------------------------------------------------------------
-- Grades
-- ---------------------------------------------------------------------------

export type Grade = {
	id: string,
	name: string,
	short: string,
	weight: number,
	mult: number,
	color: Color3,
}

ModifierConfig.Grades = {
	chipped = {
		id = "chipped",
		name = "Chipped",
		short = "CHP",
		weight = 44,
		mult = 1,
		color = Color3.fromRGB(150, 158, 172),
	} :: Grade,
	common = {
		id = "common",
		name = "Common",
		short = "CMN",
		weight = 28,
		mult = 1.12,
		color = Color3.fromRGB(196, 204, 216),
	} :: Grade,
	refined = {
		id = "refined",
		name = "Refined",
		short = "REF",
		weight = 16,
		mult = 1.3,
		color = Color3.fromRGB(96, 214, 246),
	} :: Grade,
	exalted = {
		id = "exalted",
		name = "Exalted",
		short = "EXA",
		weight = 8,
		mult = 1.6,
		color = Color3.fromRGB(206, 138, 255),
	} :: Grade,
	mythic = {
		id = "mythic",
		name = "Mythic",
		short = "MYT",
		weight = 3.2,
		mult = 2.1,
		color = Color3.fromRGB(255, 194, 60),
	} :: Grade,
	transcendent = {
		id = "transcendent",
		name = "Transcendent",
		short = "TRN",
		weight = 0.8,
		mult = 2.8,
		color = Color3.fromRGB(122, 255, 196),
	} :: Grade,
	--- Expansion wave. Two rungs above Transcendent, both deliberately under 1%
	--- combined. The ladder needed a ceiling a player can chase past the point
	--- where every roll already reads Transcendent.
	sublime = {
		id = "sublime",
		name = "Sublime",
		short = "SBL",
		weight = 0.35,
		mult = 3.4,
		color = Color3.fromRGB(255, 138, 214),
	} :: Grade,
	primordial = {
		id = "primordial",
		name = "Primordial",
		short = "PRM",
		weight = 0.08,
		mult = 4.2,
		color = Color3.fromRGB(255, 246, 200),
	} :: Grade,
}

ModifierConfig.GradeOrder = {
	"chipped", "common", "refined", "exalted", "mythic", "transcendent", "sublime", "primordial",
}

-- ---------------------------------------------------------------------------
-- Affixes
-- ---------------------------------------------------------------------------

export type Affix = {
	id: string,
	name: string,
	weight: number,
	mult: number,
	critChance: number,
	ventMult: number,
	coolMult: number,
	shardMult: number,
	text: string,
}

ModifierConfig.Prefixes = {
	molten = {
		id = "molten",
		name = "Molten",
		weight = 18,
		mult = 1.05,
		critChance = 0.01,
		ventMult = 1,
		coolMult = 1,
		shardMult = 1,
		text = "+2% Aether on vent.",
	} :: Affix,
	frozen = {
		id = "frozen",
		name = "Frozen",
		weight = 16,
		mult = 1.04,
		critChance = 0,
		ventMult = 1,
		coolMult = 1.05,
		shardMult = 1,
		text = "Cools 5% faster.",
	} :: Affix,
	runed = {
		id = "runed",
		name = "Runed",
		weight = 14,
		mult = 1.06,
		critChance = 0.01,
		ventMult = 1,
		coolMult = 1,
		shardMult = 1,
		text = "+1% crit.",
	} :: Affix,
	gilded = {
		id = "gilded",
		name = "Gilded",
		weight = 12,
		mult = 1.08,
		critChance = 0,
		ventMult = 1.03,
		coolMult = 1,
		shardMult = 1,
		text = "+3% Aether on vent.",
	} :: Affix,
	gleaming = {
		id = "gleaming",
		name = "Gleaming",
		weight = 10,
		mult = 1.05,
		critChance = 0.02,
		ventMult = 1,
		coolMult = 1,
		shardMult = 1,
		text = "+2% crit.",
	} :: Affix,
	voltaic = {
		id = "voltaic",
		name = "Voltaic",
		weight = 8,
		mult = 1.07,
		critChance = 0.02,
		ventMult = 1,
		coolMult = 1.03,
		shardMult = 1,
		text = "+2% crit, cooling 3%.",
	} :: Affix,
	ancient = {
		id = "ancient",
		name = "Ancient",
		weight = 6,
		mult = 1.12,
		critChance = 0,
		ventMult = 1,
		coolMult = 1,
		shardMult = 1,
		text = "Older than the Forge. +12% power.",
	} :: Affix,
	venomous = {
		id = "venomous",
		name = "Venomous",
		weight = 5,
		mult = 1.04,
		critChance = 0,
		ventMult = 1.05,
		coolMult = 1,
		shardMult = 1,
		text = "+5% Aether on vent.",
	} :: Affix,
	hollow = {
		id = "hollow",
		name = "Hollow",
		weight = 4,
		mult = 1.1,
		critChance = 0,
		ventMult = 1,
		coolMult = 1,
		shardMult = 1.15,
		text = "+15% Void Shard odds.",
	} :: Affix,
	sunless = {
		id = "sunless",
		name = "Sunless",
		weight = 3,
		mult = 1.15,
		critChance = 0.03,
		ventMult = 1,
		coolMult = 1,
		shardMult = 1,
		text = "+3% crit. It eats the light.",
	} :: Affix,
	cursed = {
		id = "cursed",
		name = "Cursed",
		weight = 2.5,
		mult = 1.22,
		critChance = 0.04,
		ventMult = 1,
		coolMult = 0.97,
		shardMult = 1.25,
		text = "+22% power, cooling 3%.",
	} :: Affix,
	starforged = {
		id = "starforged",
		name = "Starforged",
		weight = 1.5,
		mult = 1.3,
		critChance = 0.05,
		ventMult = 1.1,
		coolMult = 1.05,
		shardMult = 1.2,
		text = "Everything at once. +30% power.",
	} :: Affix,
	--- Expansion wave: eight more adjectives. They fill the gap between the
	--- 1.05 commons and the 1.3 jackpot so a mid roll is no longer all-or-nothing
	--- on the same six entries.
	tempered = {
		id = "tempered",
		name = "Tempered",
		weight = 13,
		mult = 1.05,
		critChance = 0,
		ventMult = 1.02,
		coolMult = 1.02,
		shardMult = 1,
		text = "+2% vent and cooling.",
	} :: Affix,
	ashen = {
		id = "ashen",
		name = "Ashen",
		weight = 11,
		mult = 1.03,
		critChance = 0.015,
		ventMult = 1,
		coolMult = 1.04,
		shardMult = 1,
		text = "+1.5% crit, cooling 4%.",
	} :: Affix,
	stormwrought = {
		id = "stormwrought",
		name = "Stormwrought",
		weight = 9,
		mult = 1.07,
		critChance = 0.025,
		ventMult = 1,
		coolMult = 1.02,
		shardMult = 1,
		text = "+2.5% crit. It answers thunder.",
	} :: Affix,
	hoarfrost = {
		id = "hoarfrost",
		name = "Hoarfrost",
		weight = 8,
		mult = 1.05,
		critChance = 0,
		ventMult = 1,
		coolMult = 1.09,
		shardMult = 1,
		text = "Cools 9% faster.",
	} :: Affix,
	obsidian = {
		id = "obsidian",
		name = "Obsidian",
		weight = 7,
		mult = 1.09,
		critChance = 0.01,
		ventMult = 1,
		coolMult = 1,
		shardMult = 1.08,
		text = "+9% power, +8% Void Shard odds.",
	} :: Affix,
	lucent = {
		id = "lucent",
		name = "Lucent",
		weight = 5.5,
		mult = 1.1,
		critChance = 0.02,
		ventMult = 1.04,
		coolMult = 1,
		shardMult = 1,
		text = "+10% power, +4% vent.",
	} :: Affix,
	writhing = {
		id = "writhing",
		name = "Writhing",
		weight = 3.5,
		mult = 1.06,
		critChance = 0,
		ventMult = 1.08,
		coolMult = 1,
		shardMult = 1.16,
		text = "+8% vent, +16% Void Shard odds.",
	} :: Affix,
	godsteel = {
		id = "godsteel",
		name = "Godsteel",
		weight = 1.1,
		mult = 1.34,
		critChance = 0.045,
		ventMult = 1.07,
		coolMult = 1.07,
		shardMult = 1.25,
		text = "+34% power. The yard never made this.",
	} :: Affix,
}

ModifierConfig.PrefixOrder = {
	"molten", "frozen", "runed", "gilded", "gleaming", "voltaic",
	"ancient", "venomous", "hollow", "sunless", "cursed", "starforged",
	"tempered", "ashen", "stormwrought", "hoarfrost", "obsidian", "lucent",
	"writhing", "godsteel",
}

ModifierConfig.Suffixes = {
	ruin = {
		id = "ruin",
		name = "of Ruin",
		weight = 18,
		mult = 1.06,
		critChance = 0.01,
		ventMult = 1,
		coolMult = 1,
		shardMult = 1,
		text = "+1% crit.",
	} :: Affix,
	ember = {
		id = "ember",
		name = "of the Ember",
		weight = 15,
		mult = 1.05,
		critChance = 0,
		ventMult = 1.04,
		coolMult = 1,
		shardMult = 1,
		text = "+4% Aether on vent.",
	} :: Affix,
	tides = {
		id = "tides",
		name = "of Nine Tides",
		weight = 13,
		mult = 1.06,
		critChance = 0,
		ventMult = 1,
		coolMult = 1.06,
		shardMult = 1,
		text = "Cools 6% faster.",
	} :: Affix,
	dawn = {
		id = "dawn",
		name = "of Dawn",
		weight = 11,
		mult = 1.07,
		critChance = 0.02,
		ventMult = 1,
		coolMult = 1,
		shardMult = 1,
		text = "+2% crit.",
	} :: Affix,
	echoes = {
		id = "echoes",
		name = "of Echoes",
		weight = 9,
		mult = 1.08,
		critChance = 0,
		ventMult = 1.03,
		coolMult = 1.03,
		shardMult = 1,
		text = "+3% vent and cooling.",
	} :: Affix,
	rust = {
		id = "rust",
		name = "of Rust",
		weight = 8,
		mult = 1.04,
		critChance = 0.02,
		ventMult = 1,
		coolMult = 1,
		shardMult = 0.99,
		text = "+2% crit. It remembers the yard.",
	} :: Affix,
	whispers = {
		id = "whispers",
		name = "of Whispers",
		weight = 6,
		mult = 1.09,
		critChance = 0,
		ventMult = 1,
		coolMult = 1,
		shardMult = 1.1,
		text = "+10% Void Shard odds.",
	} :: Affix,
	colossus = {
		id = "colossus",
		name = "of the Colossus",
		weight = 5,
		mult = 1.12,
		critChance = 0,
		ventMult = 1.02,
		coolMult = 0.98,
		shardMult = 1,
		text = "+12% power. Heavy in the hand.",
	} :: Affix,
	thorns = {
		id = "thorns",
		name = "of Thorns",
		weight = 4,
		mult = 1.07,
		critChance = 0.03,
		ventMult = 1,
		coolMult = 1,
		shardMult = 1,
		text = "+3% crit.",
	} :: Affix,
	lastlight = {
		id = "lastlight",
		name = "of the Last Light",
		weight = 3,
		mult = 1.14,
		critChance = 0.03,
		ventMult = 1.05,
		coolMult = 1,
		shardMult = 1,
		text = "+14% power, +3% crit.",
	} :: Affix,
	acheron = {
		id = "acheron",
		name = "of Acheron",
		weight = 2,
		mult = 1.18,
		critChance = 0,
		ventMult = 1,
		coolMult = 1,
		shardMult = 1.35,
		text = "+35% Void Shard odds.",
	} :: Affix,
	firstforge = {
		id = "firstforge",
		name = "of the First Forge",
		weight = 1,
		mult = 1.35,
		critChance = 0.05,
		ventMult = 1.08,
		coolMult = 1.08,
		shardMult = 1.2,
		text = "The original heat. +35% power.",
	} :: Affix,
	--- Expansion wave: eight more tails. The suffix register is where the lore
	--- lives, so these are places and hours rather than adjectives.
	deep = {
		id = "deep",
		name = "of the Deep",
		weight = 12,
		mult = 1.05,
		critChance = 0,
		ventMult = 1,
		coolMult = 1.03,
		shardMult = 1.09,
		text = "+9% Void Shard odds, cooling 3%.",
	} :: Affix,
	longdark = {
		id = "longdark",
		name = "of the Long Dark",
		weight = 10,
		mult = 1.08,
		critChance = 0.015,
		ventMult = 1,
		coolMult = 1,
		shardMult = 1.06,
		text = "+8% power, +1.5% crit.",
	} :: Affix,
	ninthhour = {
		id = "ninthhour",
		name = "of the Ninth Hour",
		weight = 8,
		mult = 1.07,
		critChance = 0.02,
		ventMult = 1.03,
		coolMult = 1,
		shardMult = 1,
		text = "+2% crit, +3% vent.",
	} :: Affix,
	glass = {
		id = "glass",
		name = "of Glass",
		weight = 7,
		mult = 1.06,
		critChance = 0.03,
		ventMult = 1,
		coolMult = 0.99,
		shardMult = 1,
		text = "+3% crit. Cracks beautifully.",
	} :: Affix,
	hunger = {
		id = "hunger",
		name = "of Hunger",
		weight = 5,
		mult = 1.11,
		critChance = 0,
		ventMult = 1.09,
		coolMult = 1,
		shardMult = 1,
		text = "+11% power, +9% vent.",
	} :: Affix,
	quiet = {
		id = "quiet",
		name = "of the Quiet",
		weight = 4,
		mult = 1.09,
		critChance = 0.015,
		ventMult = 1,
		coolMult = 1.08,
		shardMult = 1,
		text = "+9% power, cooling 8%.",
	} :: Affix,
	sun = {
		id = "sun",
		name = "of the Sun",
		weight = 2.5,
		mult = 1.17,
		critChance = 0.035,
		ventMult = 1.04,
		coolMult = 1,
		shardMult = 1,
		text = "+17% power, +3.5% crit.",
	} :: Affix,
	makers = {
		id = "makers",
		name = "of the Makers",
		weight = 1.2,
		mult = 1.32,
		critChance = 0.04,
		ventMult = 1.09,
		coolMult = 1.09,
		shardMult = 1.3,
		text = "Their mark is still on it. +32% power.",
	} :: Affix,
}

ModifierConfig.SuffixOrder = {
	"ruin", "ember", "tides", "dawn", "echoes", "rust",
	"whispers", "colossus", "thorns", "lastlight", "acheron", "firstforge",
	"deep", "longdark", "ninthhour", "glass", "hunger", "quiet", "sun", "makers",
}

ModifierConfig.PrefixChance = 0.3
ModifierConfig.SuffixChance = 0.22

-- ---------------------------------------------------------------------------
-- Lookups
-- ---------------------------------------------------------------------------

local function inOrder(order: { string }, id: string): boolean
	for _, candidate in order do
		if candidate == id then
			return true
		end
	end
	return false
end

function ModifierConfig.element(id: string): Element
	return (ModifierConfig.Elements :: any)[id] or ModifierConfig.Elements.ember
end

function ModifierConfig.grade(id: string): Grade
	return (ModifierConfig.Grades :: any)[id] or ModifierConfig.Grades.chipped
end

function ModifierConfig.prefix(id: string): Affix?
	if id == "" then
		return nil
	end
	return (ModifierConfig.Prefixes :: any)[id]
end

function ModifierConfig.suffix(id: string): Affix?
	if id == "" then
		return nil
	end
	return (ModifierConfig.Suffixes :: any)[id]
end

function ModifierConfig.hasElement(id: unknown): boolean
	return type(id) == "string" and inOrder(ModifierConfig.ElementOrder, id)
end

function ModifierConfig.hasGrade(id: unknown): boolean
	return type(id) == "string" and inOrder(ModifierConfig.GradeOrder, id)
end

function ModifierConfig.hasPrefix(id: unknown): boolean
	return type(id) == "string" and inOrder(ModifierConfig.PrefixOrder, id)
end

function ModifierConfig.hasSuffix(id: unknown): boolean
	return type(id) == "string" and inOrder(ModifierConfig.SuffixOrder, id)
end

--- Every legal copy shape, for the codex header. A roll of the forge, not a
--- promise that every one of them is reachable in one lifetime.
function ModifierConfig.combinations(bladeCount: number, variantCount: number): number
	return bladeCount * variantCount * #ModifierConfig.ElementOrder * #ModifierConfig.GradeOrder
		* (#ModifierConfig.PrefixOrder + 1) * (#ModifierConfig.SuffixOrder + 1)
end

-- ---------------------------------------------------------------------------
-- Rolling
-- ---------------------------------------------------------------------------

local function weightedPick(entries: { any }, order: { string }, total: number): any
	local pick = math.random() * total
	local running = 0
	for _, id in order do
		local entry = entries[id]
		running += entry.weight
		if pick <= running then
			return entry
		end
	end
	return entries[order[#order]]
end

local function weightOf(entries: { any }, order: { string }): number
	local total = 0
	for _, id in order do
		total += entries[id].weight
	end
	return total
end

local ELEMENT_TOTAL = weightOf(ModifierConfig.Elements, ModifierConfig.ElementOrder)
local GRADE_TOTAL = weightOf(ModifierConfig.Grades, ModifierConfig.GradeOrder)
local PREFIX_TOTAL = weightOf(ModifierConfig.Prefixes, ModifierConfig.PrefixOrder)
local SUFFIX_TOTAL = weightOf(ModifierConfig.Suffixes, ModifierConfig.SuffixOrder)

export type Roll = {
	element: string,
	grade: string,
	prefix: string,
	suffix: string,
}

--- One full modifier roll. Affixes are independent coin flips, so a clean copy
--- stays the common case and a double-affix copy is the story.
function ModifierConfig.roll(): Roll
	local element = weightedPick(ModifierConfig.Elements, ModifierConfig.ElementOrder, ELEMENT_TOTAL) :: Element
	local grade = weightedPick(ModifierConfig.Grades, ModifierConfig.GradeOrder, GRADE_TOTAL) :: Grade
	local prefix = ""
	local suffix = ""
	if math.random() < ModifierConfig.PrefixChance then
		prefix = (weightedPick(ModifierConfig.Prefixes, ModifierConfig.PrefixOrder, PREFIX_TOTAL) :: Affix).id
	end
	if math.random() < ModifierConfig.SuffixChance then
		suffix = (weightedPick(ModifierConfig.Suffixes, ModifierConfig.SuffixOrder, SUFFIX_TOTAL) :: Affix).id
	end
	return { element = element.id, grade = grade.id, prefix = prefix, suffix = suffix }
end

-- ---------------------------------------------------------------------------
-- Derived values
-- ---------------------------------------------------------------------------

export type Bonus = {
	critChance: number,
	ventMult: number,
	coolMult: number,
	shardMult: number,
}

--- The modifier half of a copy's stat line. Variant stats are added on top by
--- the caller, because the variant is a different axis and already existed.
function ModifierConfig.bonus(elementId: string, prefixId: string, suffixId: string): Bonus
	local bonus: Bonus = { critChance = 0, ventMult = 1, coolMult = 1, shardMult = 1 }
	if elementId ~= "" then
		local element = ModifierConfig.element(elementId)
		bonus.critChance = element.critChance
		bonus.ventMult = element.ventMult
		bonus.coolMult = element.coolMult
		bonus.shardMult = element.shardMult
	end
	local prefix = ModifierConfig.prefix(prefixId)
	if prefix then
		bonus.critChance += prefix.critChance
		bonus.ventMult *= prefix.ventMult
		bonus.coolMult *= prefix.coolMult
		bonus.shardMult *= prefix.shardMult
	end
	local suffix = ModifierConfig.suffix(suffixId)
	if suffix then
		bonus.critChance += suffix.critChance
		bonus.ventMult *= suffix.ventMult
		bonus.coolMult *= suffix.coolMult
		bonus.shardMult *= suffix.shardMult
	end
	return bonus
end

--- Product of every modifier multiplier on a copy. An empty axis is 1, not a
--- fallback: a schema-6 copy has no element, and silently giving it Ember would
--- make every old blade 6% stronger overnight.
function ModifierConfig.power(gradeId: string, elementId: string, prefixId: string, suffixId: string): number
	local mult = 1
	if gradeId ~= "" then
		mult *= ModifierConfig.grade(gradeId).mult
	end
	if elementId ~= "" then
		mult *= ModifierConfig.element(elementId).mult
	end
	local prefix = ModifierConfig.prefix(prefixId)
	if prefix then
		mult *= prefix.mult
	end
	local suffix = ModifierConfig.suffix(suffixId)
	if suffix then
		mult *= suffix.mult
	end
	return mult
end

--- Full display name: "Molten Rusted Cleaver of Ruin".
function ModifierConfig.displayName(bladeName: string, prefixId: string, suffixId: string): string
	local prefix = ModifierConfig.prefix(prefixId)
	local suffix = ModifierConfig.suffix(suffixId)
	local head = if prefix then prefix.name .. " " else ""
	local tail = if suffix then " " .. suffix.name else ""
	return head .. bladeName .. tail
end

--- The condition word for a copy: the grade, tinted by the element. Used by the
--- card row, the inspector and the reveal banner. An axis that was never rolled
--- is simply absent, so a legacy copy reads "Unmarked" instead of borrowing
--- Chipped Ember and lying about its power.
function ModifierConfig.condition(gradeId: string, elementId: string): string
	local grade = if gradeId ~= "" then ModifierConfig.grade(gradeId).name else nil
	local element = if elementId ~= "" then ModifierConfig.element(elementId).name else nil
	if grade and element then
		return string.format("%s %s", grade, element)
	end
	if grade then
		return grade
	end
	if element then
		return element
	end
	return "Unmarked"
end

--- Condition word for a whole copy. Kept for callers that only want the line.
function ModifierConfig.conditionOf(gradeId: string, elementId: string): string
	return ModifierConfig.condition(gradeId, elementId)
end

-- ---------------------------------------------------------------------------
-- Quality ladder
-- ---------------------------------------------------------------------------
--
-- A named tier for every band a copy can land in: eight grade families times four
-- steps, thirty-two in total, `Chipped-` through `Primordial++`.
--
-- The multiplier is NOT a new axis. It is the product the copy already carries,
-- grade x element x prefix x suffix, displayed as one number and banded into a
-- step. Inventing a second multiplier on top would double-count every grade in
-- the game and quietly inflate the economy by the size of the ladder. The point
-- of this ladder is legibility: one word and one number that say where a copy
-- sits, in the codex and on the reveal.

export type Quality = {
	id: string,
	name: string,
	--- Grade family the tier belongs to.
	family: string,
	--- 1..4, where 1 is the minus step and 4 is the double-plus.
	step: number,
	--- True product of every modifier on the copy.
	mult: number,
	color: Color3,
}

--- Step thresholds on the within-family score (element x prefix x suffix).
--- 1.00 is a bare element, 1.72 is a double-affix high element.
ModifierConfig.QualityStepSuffix = { "-", "", "+", "++" }
local QUALITY_THRESHOLDS = { 1.0, 1.2, 1.45, 1.72 }

local function withinFamilyScore(elementId: string, prefixId: string, suffixId: string): number
	local score = 1
	if elementId ~= "" then
		score *= ModifierConfig.element(elementId).mult
	end
	local prefix = ModifierConfig.prefix(prefixId)
	if prefix then
		score *= prefix.mult
	end
	local suffix = ModifierConfig.suffix(suffixId)
	if suffix then
		score *= suffix.mult
	end
	return score
end

local function stepFor(score: number): number
	local step = 1
	for index, threshold in QUALITY_THRESHOLDS do
		if score >= threshold then
			step = index
		end
	end
	return step
end

function ModifierConfig.qualityId(gradeId: string, elementId: string, prefixId: string, suffixId: string): string
	local grade = if gradeId ~= "" then gradeId else ""
	if grade == "" then
		return ""
	end
	local step = stepFor(withinFamilyScore(elementId, prefixId, suffixId))
	return grade .. ModifierConfig.QualityStepSuffix[step]
end

--- Parses a quality id back into a display record. Nil for an unknown or empty
--- id, which is what a legacy copy produces.
function ModifierConfig.quality(id: string): Quality?
	if id == "" then
		return nil
	end
	for _, gradeId in ModifierConfig.GradeOrder do
		for step = 1, #ModifierConfig.QualityStepSuffix do
			if id == gradeId .. ModifierConfig.QualityStepSuffix[step] then
				local grade = ModifierConfig.grade(gradeId)
				return {
					id = id,
					name = grade.name .. (if step == 1 then "-" elseif step == 2 then "" elseif step == 3 then "+" else "++"),
					family = gradeId,
					step = step,
					mult = grade.mult,
					color = grade.color:Lerp(Color3.new(1, 1, 1), (step - 1) * 0.12),
				}
			end
		end
	end
	return nil
end

--- The quality band a copy lands in, with the copy's true multiplier.
function ModifierConfig.qualityOf(
	gradeId: string,
	elementId: string,
	prefixId: string,
	suffixId: string
): Quality?
	local id = ModifierConfig.qualityId(gradeId, elementId, prefixId, suffixId)
	local base = ModifierConfig.quality(id)
	if base == nil then
		return nil
	end
	base.mult = ModifierConfig.power(gradeId, elementId, prefixId, suffixId)
	return base
end

function ModifierConfig.hasQuality(id: unknown): boolean
	return type(id) == "string" and ModifierConfig.quality(id) ~= nil
end

--- Every legal quality tier, in ladder order. The codex paints this list.
function ModifierConfig.qualityLadder(): { Quality }
	local out: { Quality } = {}
	for _, gradeId in ModifierConfig.GradeOrder do
		for step = 1, #ModifierConfig.QualityStepSuffix do
			local entry = ModifierConfig.quality(gradeId .. ModifierConfig.QualityStepSuffix[step])
			if entry then
				table.insert(out, entry)
			end
		end
	end
	return out
end

--- Where the copy sits on the collection ladder, 0..1. Drives the reveal shake--- and the codex "best found" line: grade first, then element, then affixes.
function ModifierConfig.rank(gradeId: string, elementId: string, prefixId: string, suffixId: string): number
	local gradeIndex = 1
	for index, id in ModifierConfig.GradeOrder do
		if id == gradeId then
			gradeIndex = index
			break
		end
	end
	local elementIndex = 1
	for index, id in ModifierConfig.ElementOrder do
		if id == elementId then
			elementIndex = index
			break
		end
	end
	local affixes = (if prefixId ~= "" then 1 else 0) + (if suffixId ~= "" then 1 else 0)
	local raw = (gradeIndex - 1) / (#ModifierConfig.GradeOrder - 1) * 0.6
		+ (elementIndex - 1) / (#ModifierConfig.ElementOrder - 1) * 0.25
		+ affixes * 0.075
	return math.clamp(raw, 0, 1)
end

return ModifierConfig
