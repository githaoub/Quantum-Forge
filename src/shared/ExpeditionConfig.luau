--!strict
-- Fleet expeditions: the one place where drones are spent instead of counted.
--
-- A mission commits a fixed squad for a fixed time. Those drones stop producing
-- passive Star-Matter for the duration, so the decision is honest: steady income
-- now, or a lump sum later. Committing the whole fleet is allowed and is the
-- greedy line.
--
-- Aether is the payout, and it is deliberately absurd. The salvage rack is the
-- steady faucet: a cache every forty strikes, worth a few thousand at the top
-- end. A returning fleet has to beat that in one number or the tab is a chore,
-- so the missions are sized against the drone ladder instead: a sweep buys a
-- rung, a void run buys a top-tier hull. Do not tune these against passive
-- income; tune them against the next drone the player wants.
--
-- Rewards are snapshotted at dispatch time in `ProgressionService.dispatch`, so
-- swapping to a stronger blade mid-flight cannot retroactively multiply a payout
-- the player already committed to.

local ExpeditionConfig = {}

export type Mission = {
	id: string,
	name: string,
	description: string,
	seconds: number,
	--- Drones committed. They produce nothing until the mission lands.
	squad: number,
	--- Base Aether before the equipped blade's multiplier.
	aether: number,
	cores: number,
	shards: number,
	--- Badge art key in `AssetManifest.UiArt`. Nil keeps the row text-only,
	--- which is what a fresh clone with no uploads gets.
	icon: string?,
}

ExpeditionConfig.Missions = {
	sweep = {
		id = "sweep",
		name = "Debris Sweep",
		description = "Short run through the near belt. Safe, cheap, and back before the kettle boils.",
		seconds = 300,
		squad = 5,
		aether = 15000,
		cores = 0,
		shards = 0,
		icon = "fleet_sweep",
	} :: Mission,

	deep = {
		id = "deep",
		name = "Deep Salvage",
		description = "Cut into the wreck field. Half the fleet, most of an afternoon.",
		seconds = 900,
		squad = 15,
		aether = 200000,
		cores = 1,
		shards = 1,
		icon = "fleet_deep",
	} :: Mission,

	void = {
		id = "void",
		name = "Void Run",
		description = "Past the last marker. Thirty drones, one hour, and it always comes back changed.",
		seconds = 3600,
		squad = 30,
		aether = 4000000,
		cores = 6,
		shards = 4,
		icon = "fleet_void",
	} :: Mission,
}

--- Shortest first. The shelf reads as a ladder, and the UI relies on that order.
ExpeditionConfig.Order = { "sweep", "deep", "void" }

local BY_ID: { [string]: Mission } = table.clone(ExpeditionConfig.Missions)

function ExpeditionConfig.get(id: string): Mission?
	return BY_ID[id]
end

function ExpeditionConfig.list(): { Mission }
	local out: { Mission } = {}
	for _, id in ExpeditionConfig.Order do
		out[#out + 1] = ExpeditionConfig.Missions[id]
	end
	return out
end

return ExpeditionConfig
