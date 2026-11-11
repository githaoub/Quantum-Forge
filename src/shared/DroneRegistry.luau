--!strict
-- The drone ladder.
--
-- Blades roll; drones are bought. That difference is what makes a hard-coded
-- ladder the right shape here: a player needs to see the next rung, know what it
-- costs, and be able to buy it forever without waiting for a roll.
--
-- Five tiers, ordered. Within a tier the price grows geometrically and the
-- count is unbounded. Across tiers the *price per unit of yield* falls, which is
-- the only reason buying up a tier is ever worth doing.
--
-- Balance pass: the ladder used to be far too generous. A tester who bought
-- drones finished the entire blade codex in one sitting, because fleet income
-- compounded faster than the forge could price rolls against it. Three levers
-- were moved, all of them conservative on the early game:
--
--   yield    cut roughly 45% across every tier
--   growth   +0.035 per copy inside every tier, applied one copy at a time
--   gate     every tier above the first needs 2-2.7x the fleet to open
--
-- Price per SM/s at the first copy, and the price per SM/s of the marginal copy
-- the gate replaces, so the jump is legible without running the game:
--
--   scrap       7 / 0.34      = 20.6
--   at 32: scrap #33  2 093 AE / 0.34 = 6 156   -> molten #1   900 / 9.5   = 95
--   at 110: molten #78  3.6e9 AE / 9.5 = 3.8e8  -> quantum #1  42k / 260   = 162
--   at 320: quantum #211  ~1e17 / 260          -> celestial #1 2.6M / 7.8k = 333
--
-- The cliff is the gate. What changed is how long the climb to the gate takes:
-- 32 / 110 / 320 / 800 drones is a long-run ladder instead of an afternoon.
--
-- A tier unlocks on *total drones owned*, not on currency, so the gate is a
-- fleet size rather than a second wallet. `unlockAt` is what the Fleet tab
-- prints while a tier is still locked.

local DroneRegistry = {}

export type DroneTier = {
	id: string,
	name: string,
	--- Two or three letters for the ladder key.
	short: string,
	tier: number,
	--- Aether for the first copy of this tier.
	baseCost: number,
	--- Per-copy multiplier on the price inside this tier.
	growth: number,
	--- Star-Matter per second per copy, before blade and tech multipliers.
	yield: number,
	--- Total drones owned (all tiers) needed before this tier can be bought.
	unlockAt: number,
	--- Hull and glow, fed to `DroneModelBuilder` so each tier renders apart.
	hull: Color3,
	glow: Color3,
	--- One line, used in the Fleet tab header. Not a tutorial.
	flavor: string,
}

--- Ordered weakest to strongest. `DroneRegistry.tiers[1]` is what every save
--- that predates the ladder is migrated into.
DroneRegistry.tiers = {
	{
		id = "scrap",
		name = "Scrap Drone",
		short = "SCR",
		tier = 1,
		baseCost = 7,
		growth = 1.195,
		yield = 0.34,
		unlockAt = 0,
		hull = Color3.fromRGB(96, 104, 122),
		glow = Color3.fromRGB(0, 210, 255),
		flavor = "Bolted together in the yard. It still flies.",
	},
	{
		id = "molten",
		name = "Molten Core",
		short = "MLT",
		tier = 2,
		baseCost = 900,
		growth = 1.215,
		yield = 9.5,
		unlockAt = 32,
		hull = Color3.fromRGB(74, 52, 46),
		glow = Color3.fromRGB(255, 107, 0),
		flavor = "A furnace with fins. Cools on the way up.",
	},
	{
		id = "quantum",
		name = "Quantum Vector",
		short = "QNT",
		tier = 3,
		baseCost = 42000,
		growth = 1.23,
		yield = 260,
		unlockAt = 110,
		hull = Color3.fromRGB(46, 78, 116),
		glow = Color3.fromRGB(0, 210, 255),
		flavor = "Arrives before it leaves. Billed for both.",
	},
	{
		id = "celestial",
		name = "Celestial Swarm",
		short = "CEL",
		tier = 4,
		baseCost = 2600000,
		growth = 1.24,
		yield = 7800,
		unlockAt = 320,
		hull = Color3.fromRGB(82, 58, 128),
		glow = Color3.fromRGB(255, 54, 200),
		flavor = "One hull, many shadows. All of them working.",
	},
	{
		id = "cosmic",
		name = "Cosmic Dreadnought",
		short = "CSM",
		tier = 5,
		baseCost = 320000000,
		growth = 1.25,
		yield = 260000,
		unlockAt = 800,
		hull = Color3.fromRGB(62, 52, 88),
		glow = Color3.fromRGB(255, 194, 60),
		flavor = "Parked in orbit because the yard is too small.",
	},
} :: { DroneTier }

local byId: { [string]: DroneTier } = {}
for _, tier in DroneRegistry.tiers do
	byId[tier.id] = tier
end

--- The tier every legacy save migrates into.
DroneRegistry.DefaultId = "scrap"

--- Total drones above which the ladder stops being the gate. Used to clamp an
--- expedition squad and a hostile payload, not to cap the fleet.
DroneRegistry.SaneMax = 1e9

function DroneRegistry.get(id: string?): DroneTier?
	if id == nil then
		return nil
	end
	return byId[id]
end

--- Position in the ladder, 1 based. Unknown ids return 0.
function DroneRegistry.index(id: string?): number
	local tier = DroneRegistry.get(id)
	return if tier then tier.tier else 0
end

--- Price of the next copy inside a tier.
---
--- `scale` is the account's progress multiplier, passed by the caller: the
--- registry has no profile. It is applied last so the within-tier growth and the
--- account growth multiply instead of one swallowing the other.
function DroneRegistry.cost(tier: DroneTier, owned: number, scale: number?): number
	local safe = math.max(0, math.floor(owned))
	-- `growth ^ owned` overflows to inf around owned = 4000 at 1.16; the clamp
	-- keeps the number finite so the button can print *something* absurd rather
	-- than `inf`.
	local progress = math.max(1, scale or 1)
	return math.min(math.floor(tier.baseCost * (tier.growth ^ safe) * progress), 1e308)
end

--- Price of the next `count` copies, the geometric series the BUILD 10 face
--- has to show. Printing ten times the single price understates the bill by an
--- order of magnitude once the growth has run for a while.
function DroneRegistry.bulkCost(tier: DroneTier, owned: number, count: number, scale: number?): number
	if count <= 0 then
		return 0
	end
	local first = DroneRegistry.cost(tier, owned, scale)
	if tier.growth == 1 then
		return math.min(first * count, 1e308)
	end
	local total = first * (tier.growth ^ count - 1) / (tier.growth - 1)
	return math.min(math.floor(total), 1e308)
end

--- True when `total` (drones owned across every tier) meets this tier's gate.
function DroneRegistry.unlocked(tier: DroneTier, total: number): boolean
	return total >= tier.unlockAt
end

--- The next tier up, or nil on the last rung.
function DroneRegistry.next(id: string): DroneTier?
	local tier = byId[id]
	if tier == nil then
		return nil
	end
	return DroneRegistry.tiers[tier.tier + 1]
end

--- Highest tier this fleet size has opened. Used to pick the Fleet tab's
--- default selection without walking the ladder twice.
function DroneRegistry.bestUnlocked(total: number): DroneTier
	local best = DroneRegistry.tiers[1]
	for _, tier in DroneRegistry.tiers do
		if total >= tier.unlockAt then
			best = tier
		end
	end
	return best
end

return DroneRegistry
