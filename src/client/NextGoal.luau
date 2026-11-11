--!strict
-- The single next goal, reduced from the whole ladder to one line in the rail.
--
-- Goal smog is the failure mode this exists to prevent: six sections, a daily,
-- a codex and a store all ask for attention, and none of them answers "what
-- now?". The rule is deliberately narrow: a goal is a *permanent unlock* -- a
-- crate tier, a drone rung, a tech node, the daily -- never a repeat purchase.
-- A repeat purchase is already one key away, and its price is printed on the
-- screen that sells it.
--
-- The winner is the nearest goal by its own progress. Progress is always
-- "have / need" in the currency that gates it, so the four candidates stay
-- comparable even though crates spend run Star-Matter, drones spend the same
-- at a different scale, and tech spends Quantum Cores.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local ForgeConfig = require(Shared:WaitForChild("ForgeConfig"))
local TechTreeConfig = require(Shared:WaitForChild("TechTreeConfig"))

local NextGoal = {}

export type Goal = {
	--- Stable id for the handler: "daily" | "crate" | "drone" | "tech".
	key: string,
	--- Three to five characters, because the rail is 92px wide.
	label: string,
	--- Section to open. Nil for the daily, which is an overlay.
	section: string?,
	--- 0..1 progress toward the gate. Never printed as a misleading 100%: a
	--- goal that reaches its gate stops being a candidate.
	fraction: number,
}

--- Nearest of two goals. Ties keep the earlier one, which is why the call order
--- below is the priority order: daily, crate, drone, tech.
local function nearer(a: Goal?, b: Goal): Goal
	if a == nil then
		return b
	end
	return if b.fraction > a.fraction then b else a
end

--- The cheapest un-maxed tech node, or nil when the tree is finished.
local function nextTech(state: Types.SyncPayload): { cost: number }?
	local cheapest: number? = nil
	for _, node in TechTreeConfig.list() do
		local level = state.tech[node.id] or 0
		if level < node.maxLevel then
			local cost = TechTreeConfig.cost(node, level)
			if cheapest == nil or cost < cheapest then
				cheapest = cost
			end
		end
	end
	return if cheapest then { cost = cheapest } else nil
end

--- Picks the goal worth printing. Returns nil when every ladder is finished,
--- which is the only honest time to show nothing.
function NextGoal.compute(state: Types.SyncPayload): Goal?
	local best: Goal? = nil

	-- The daily is the one clock the player did not set. It is free, it expires,
	-- and it is the cheapest possible answer to "what now?", so it wins outright.
	if state.dailyReady then
		best = { key = "daily", label = "DAILY", section = nil, fraction = 1 }
	end

	-- Next crate tier. A tier that is already open is not a goal; its progress
	-- would read 100% forever. `Tiers` is ordered, so the first locked one is
	-- also the cheapest.
	for _, tier in ForgeConfig.Tiers do
		if state.runSm < tier.unlock and tier.unlock > 0 then
			best = nearer(best, {
				key = "crate",
				label = "CRATE",
				section = "crates",
				fraction = state.runSm / tier.unlock,
			})
			break
		end
	end

	-- Next drone rung. Same shape as the crate: the first locked rung is the
	-- cheapest, and the payload already carries every rung's gate.
	for _, entry in state.fleet do
		if not entry.unlocked and entry.unlockAt > 0 then
			best = nearer(best, {
				key = "drone",
				label = "DRONE",
				section = "fleet",
				fraction = state.drones / entry.unlockAt,
			})
			break
		end
	end

	-- Next tech node. Cores are scarce, so this rarely wins before an ascension
	-- -- which is exactly the point: when it does win, the player is close.
	local tech = nextTech(state)
	if tech then
		best = nearer(best, {
			key = "tech",
			label = "TECH",
			section = "tech",
			fraction = state.qc / tech.cost,
		})
	end

	return best
end

return NextGoal
