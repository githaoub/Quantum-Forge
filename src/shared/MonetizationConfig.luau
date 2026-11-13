--!strict
-- Monetization surface.
--
-- Shape follows the post-mortem: no raw Star-Matter or Quantum Core packs. A
-- cash pack that converts directly into the currency being ground is the fastest
-- way to make the grind pointless, and it is the one thing the analysis says
-- kills long-term retention. Everything here either multiplies what the player
-- already earns, removes a chore, or is status.
--
-- The ids below are live Marketplace listings created through
-- `scripts/create_store_items.py` (Open Cloud). That script is idempotent: it
-- looks entries up by name, creates only what is missing, and patches the ids
-- back here. A new listing is free; only a purchase charges Robux. Server
-- validates ownership for passes and grants for products — the client never
-- decides what a purchase is worth.
--
-- `price` is display-only: Roblox renders the real price in the purchase prompt
-- from the Marketplace item itself. It lives here so the storefront can show the
-- intended price instead of a generic "GET" on every row.

local MonetizationConfig = {}

export type PassDef = {
	id: number,
	name: string,
	description: string,
	enabled: boolean,
	--- Shown on the storefront price pill. Display only.
	price: number,
	--- Two-to-four character category tag rendered beside the title.
	badge: string,
	--- Optional store-badge art: a key in `AssetManifest.GamepassIcons`, which is
	--- keyed by these same snake_case names. Nil keeps the text pill. A key with
	--- no uploaded id also keeps the text pill, so a fresh clone never draws an
	--- empty ImageLabel.
	icon: string?,
}

export type ProductDef = {
	id: number,
	name: string,
	description: string,
	enabled: boolean,
	price: number,
	badge: string,
	--- Optional store-badge art, same contract as `PassDef.icon`: a key in
	--- `AssetManifest.GamepassIcons`. Nil, or a key whose id has not been pasted
	--- in yet, keeps the text pill.
	icon: string?,
}

MonetizationConfig.Passes = {
	fastForge = {
		id = 2078144425,
		name = "Fast Forge",
		description = "Doubles accepted clicks per second.",
		enabled = true,
		price = 59,
		badge = "FAST",
		icon = "fast_forge",
	} :: PassDef,

	autoVent = {
		id = 2080202442,
		name = "Auto-Vent AI",
		description = "Vents at 85% heat automatically, so the core never runs lean.",
		enabled = true,
		price = 59,
		badge = "AUTO",
		icon = "auto_vent",
	} :: PassDef,

	x2StarMatter = {
		id = 2079002443,
		name = "2x Income",
		description = "Doubles all forge income, forever.",
		enabled = true,
		price = 59,
		badge = "2X",
		icon = "x2_star_matter",
	} :: PassDef,

	vipAura = {
		id = 2079290439,
		name = "VIP",
		description = "Every gamepass, forever, plus the VIP badge, aura and gold strike trail. Cheaper than buying them one by one.",
		enabled = true,
		price = 119,
		badge = "VIP",
		icon = "vip_aura",
	} :: PassDef,

	--- Every pass sits at the impulse price. The shop is for a small game:
	--- four passes at 59 and the bundle at 119 is a decision a player can make
	--- without thinking about it. The multiplier is not the product; the
	--- convenience is.
	eternalForge = {
		id = 2078156449,
		name = "Eternal Forge",
		description = "+25% to all forge income, forever.",
		enabled = true,
		price = 59,
		badge = "ETERNAL",
		icon = "eternal_forge",
	} :: PassDef,
}

MonetizationConfig.Products = {
	--- The player-to-payer door. Twenty minutes of 2x is a boost the player can
	--- feel without skipping the first drone rungs; the permanent +5% is the
	--- reason a first purchase still matters after the clock runs out.
	starterForge = {
		id = 3730425410,
		name = "Starter Forge Pack",
		description = "Twenty minutes of 2x income. The first purchase also adds +5% income, permanently.",
		enabled = true,
		price = 9,
		badge = "START",
		icon = "starter_forge",
	} :: ProductDef,

	instantOverdrive = {
		id = 3730425423,
		name = "Instant Overdrive",
		description = "One hour of 2x income. Each extra charge adds +1x. The clock resets to one hour.",
		enabled = true,
		price = 25,
		badge = "STACK",
		icon = "instant_overdrive",
	} :: ProductDef,

	--- Durable utility, not a timer skip. One purchase changes every future
	--- expedition, so the value does not depend on a mission being in flight.
	expressSalvage = {
		id = 3730425441,
		name = "Express Salvage",
		description = "Permanently cuts every expedition's clock by 25%.",
		enabled = true,
		price = 35,
		badge = "CHARTER",
		icon = "express_salvage",
	} :: ProductDef,
}

-- What each developer product actually pays out. Kept here rather than in the
-- service so a designer can rebalance without touching logic.
--
-- `OverdriveSeconds` is both the length of one charge and the hard ceiling on
-- the paid boost: every Instant Overdrive resets the timer to an hour instead of
-- extending it, so the multiplier can climb forever while the clock cannot.
MonetizationConfig.OverdriveSeconds = 3600
MonetizationConfig.OverdriveMaxSeconds = 3600
--- The first charge doubles income. Every extra charge adds one more x, so ten
--- charges are x11 instead of x59,049. Stacking stays uncapped, but it grows
--- linearly: the paid multiplier can no longer run away from the economy.
MonetizationConfig.OverdriveMultiplier = 2
MonetizationConfig.OverdriveStackBonus = 1
MonetizationConfig.StarterSeconds = 1200
--- One-time permanent income from the first Starter Forge Pack. Stored under
--- `passes.starterForge`; repeated packs only extend the 2x clock.
MonetizationConfig.StarterPermanentIncome = 0.05
--- Express Salvage is a permanent 25% cut to every expedition clock.
MonetizationConfig.ExpeditionTimeScale = 0.75

--- Looks up a pass by its Marketplace ID. Nil when the ID is still 0.
function MonetizationConfig.passByid(id: number): (string?, PassDef?)
	for key, def in MonetizationConfig.Passes do
		if def.id ~= 0 and def.id == id then
			return key, def
		end
	end
	return nil, nil
end

function MonetizationConfig.productById(id: number): (string?, ProductDef?)
	for key, def in MonetizationConfig.Products do
		if def.id ~= 0 and def.id == id then
			return key, def
		end
	end
	return nil, nil
end

--- The live paid multiplier for a charge count. One helper so the server, the
--- storefront and the HUD cannot disagree about what a stack is worth.
function MonetizationConfig.overdriveMult(stacks: number): number
	if stacks <= 0 then
		return 1
	end
	return MonetizationConfig.OverdriveMultiplier + MonetizationConfig.OverdriveStackBonus * (stacks - 1)
end

--- Storefront order. Passes first (permanent), then consumables, because the
--- permanent row is the one a returning player is still deciding about.
MonetizationConfig.PassOrder = { "vipAura", "x2StarMatter", "fastForge", "autoVent", "eternalForge" }
MonetizationConfig.ProductOrder = { "starterForge", "instantOverdrive", "expressSalvage" }

return MonetizationConfig
