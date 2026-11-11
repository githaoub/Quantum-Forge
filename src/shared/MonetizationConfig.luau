--!strict
-- Monetization surface.
--
-- Shape follows the post-mortem: no raw Star-Matter or Quantum Core packs. A
-- cash pack that converts directly into the currency being ground is the fastest
-- way to make the grind pointless, and it is the one thing the analysis says
-- kills long-term retention. Everything here either multiplies what the player
-- already earns, removes a chore, or is status.
--
-- Every ID is a placeholder and MUST be replaced with a real Marketplace ID
-- before publishing; MarketplaceService silently fails purchases on 0. Server
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
		id = 0,
		name = "Fast Forge",
		description = "Doubles accepted clicks per second.",
		enabled = true,
		price = 99,
		badge = "FAST",
		icon = "fast_forge",
	} :: PassDef,

	autoVent = {
		id = 0,
		name = "Auto-Vent AI",
		description = "Vents at 85% heat automatically, so the core never runs lean.",
		enabled = true,
		price = 149,
		badge = "AUTO",
		icon = "auto_vent",
	} :: PassDef,

	x2StarMatter = {
		id = 0,
		name = "2x Star-Matter",
		description = "Doubles all Star-Matter income, forever.",
		enabled = true,
		price = 199,
		badge = "2X",
		icon = "x2_star_matter",
	} :: PassDef,

	vipAura = {
		id = 0,
		name = "VIP",
		description = "Every gamepass, forever, plus the VIP badge and aura.",
		enabled = true,
		price = 499,
		badge = "VIP",
		icon = "vip_aura",
	} :: PassDef,

	--- High-ticket permanent. The post-mortem is explicit that a launch with no
	--- high-Robux sink leaves the top of the market unserved; this is the sink,
	--- and it is a multiplier rather than currency so it never skips the ladder.
	eternalForge = {
		id = 0,
		name = "Eternal Forge",
		description = "+25% to all Star-Matter income, forever.",
		enabled = true,
		price = 1499,
		badge = "ETERNAL",
		icon = "eternal_forge",
	} :: PassDef,
}

MonetizationConfig.Products = {
	--- The player-to-payer door. Priced at the floor of the Robux ladder so the
	--- first purchase is a decision nobody has to think about.
	starterForge = {
		id = 0,
		name = "Starter Forge Pack",
		description = "500K Aether and twenty minutes of double income. One-time lift for a fresh forge.",
		enabled = true,
		price = 5,
		badge = "START",
		icon = "starter_forge",
	} :: ProductDef,

	instantOverdrive = {
		id = 0,
		name = "Instant Overdrive",
		description = "Fifteen minutes of triple Star-Matter.",
		enabled = true,
		price = 25,
		badge = "BOOST",
		icon = "instant_overdrive",
	} :: ProductDef,

	instantVent = {
		id = 0,
		name = "Emergency Vent",
		description = "Dumps all heat instantly, wherever the core is.",
		enabled = true,
		price = 15,
		badge = "VENT",
		icon = "instant_vent",
	} :: ProductDef,

	--- Long-horizon utility rather than currency: a mission already paid for, so
	--- it buys time rather than a number.
	expressSalvage = {
		id = 0,
		name = "Express Salvage",
		description = "Instantly completes any expedition in flight.",
		enabled = true,
		price = 35,
		badge = "EXPRESS",
		icon = "express_salvage",
	} :: ProductDef,
}

-- What each developer product actually pays out. Kept here rather than in the
-- service so a designer can rebalance without touching logic.
MonetizationConfig.OverdriveSeconds = 900
MonetizationConfig.OverdriveMultiplier = 3
MonetizationConfig.StarterSeconds = 1200
MonetizationConfig.StarterAether = 500000

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

--- Storefront order. Passes first (permanent), then consumables, because the
--- permanent row is the one a returning player is still deciding about.
MonetizationConfig.PassOrder = { "vipAura", "fastForge", "x2StarMatter", "autoVent", "eternalForge" }
MonetizationConfig.ProductOrder = { "starterForge", "instantOverdrive", "instantVent", "expressSalvage" }

return MonetizationConfig
