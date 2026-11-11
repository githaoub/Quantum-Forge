--!strict
-- The forge loop: heat physics, click validation, venting, the lean point,
-- and passive drone income.
--
-- Everything here is server-authoritative. The client renders what it is told
-- and predicts for responsiveness, but a click only counts because this module
-- says so. Click rate is capped per player per second, which is the only
-- anti-autoclicker measure that matters for an incremental.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local NumberUtil = require(Shared:WaitForChild("NumberUtil"))
local Types = require(Shared:WaitForChild("Types"))

local DataManager = require(script.Parent.DataManager)
local Funnel = require(script.Parent.Funnel)
local Net = require(script.Parent.Net)
local ProgressionService = require(script.Parent.ProgressionService)

local ForgeService = {}

local clickWindows: { [Player]: { count: number, startedAt: number } } = {}
local autoClickAccumulators: { [Player]: number } = {}
local playtimeAccumulators: { [Player]: number } = {}

-- ---------------------------------------------------------------------------
-- Heat helpers
-- ---------------------------------------------------------------------------


local function clickBudget(state: Types.ProfileState): number
	local budget = Config.ClickRateLimit
	if state.passes.fastForge then
		budget *= 2
	end
	return budget
end

-- ---------------------------------------------------------------------------
-- Clicking
-- ---------------------------------------------------------------------------

local function creditStarMatter(state: Types.ProfileState, amount: number)
	state.starMatter = NumberUtil.add(state.starMatter, amount)
	state.runStarMatter = NumberUtil.add(state.runStarMatter, amount)
	state.lifetimeStarMatter = NumberUtil.add(state.lifetimeStarMatter, amount)
end

--- Applies one strike.
---
--- Returns earned amount, crit, anomaly shards, whether this strike opened
--- Overdrive, whether it levelled the equipped blade's mastery, whether it landed
--- in the sweet spot, and the name of a cache if this strike filled the meter.
--- Every one of them is a client-facing event and reconstructing them afterwards
--- would mean a second copy of the rules.
local function strike(state: Types.ProfileState): (number, boolean, number, boolean, boolean, boolean, string?)
	local stats = ProgressionService.stats(state)
	local bonus = ProgressionService.runeBonus(state)
	local salvage = ProgressionService.salvageBonus(state)
	local variant = ProgressionService.variantBonus(state)
	local inSweetSpot = state.heat >= stats.sweetSpotMin and state.heat <= stats.sweetSpotMax
	local overdriveWasActive = ProgressionService.forgeOverdriveActive(state)

	local amount = ProgressionService.clickYield(state)
	if inSweetSpot then
		amount *= stats.sweetSpotMult
	end

	local critChance = math.min(0.95, stats.critChance + bonus.critChance + salvage.critChance + variant.critChance)
	local crit = critChance > 0 and math.random() < critChance
	if crit then
		amount *= stats.critMult
	end

	creditStarMatter(state, amount)
	local masteryUp = ProgressionService.addMastery(state, state.equippedBlade)

	-- Streak. Ten clean strikes open the window; a miss or a burn-out closes it.
	-- The triggering strike is deliberately not doubled: `clickYield` was read
	-- before the window was set.
	local overdriveStarted = false
	if inSweetSpot then
		state.streak += 1
		if state.streak >= Config.StreakForOverdrive then
			state.streak = 0
			state.forgeOverdriveUntil = os.time() + Config.OverdriveSeconds
			overdriveStarted = true
		end
	else
		state.streak = 0
	end

	-- Anomaly. Only on a hot gauge, and Overdrive more than doubles the odds, so
	-- the shard line rewards living in the top of the band.
	local shards = 0
	local chance = Config.AnomalyChance
	if overdriveWasActive then
		chance += Config.AnomalyChanceOverdrive
	end
	chance *= variant.shardMult
	if state.heat >= Config.AnomalyHeatFloor and math.random() < chance then
		shards = Config.AnomalyShards
		state.voidShards += shards
	end

	state.heat = math.min(state.heat + Config.HeatPerClick, Config.OverheatAt)

	-- Salvage meter last, so the strike that drops a cache is also the strike
	-- that paid out. One cache per strike at most by construction.
	local dropped = nil
	local cache = ProgressionService.addSalvageMeter(state)
	if cache then
		dropped = cache.name
	end

	return amount, crit, shards, overdriveStarted, masteryUp, inSweetSpot, dropped
end

--- Handles a manual click. Returns false if it was rejected outright.
function ForgeService.click(player: Player): boolean
	local state = DataManager.get(player)
	if not state then
		return false
	end

	-- Sliding one-second window. A player cannot spend budget they do not have,
	-- which caps both honest fast clicking and macro abuse at the same ceiling.
	local now = os.clock()
	local window = clickWindows[player]
	if window == nil or now - window.startedAt >= 1 then
		window = { count = 0, startedAt = now }
		clickWindows[player] = window
	end
	if window.count >= clickBudget(state) then
		return false
	end
	window.count += 1

	local amount, crit, shards, overdriveStarted, masteryUp, inSweetSpot, dropped = strike(state)

	Net.sendEvent(player, { kind = if crit then "crit" else "forge", amount = amount, crit = crit })

	if overdriveStarted then
		Net.sendEvent(player, {
			kind = "overdrive",
			seconds = Config.OverdriveSeconds,
			text = "FORGE OVERDRIVE",
		})
	end

	if shards > 0 then
		Net.sendEvent(player, {
			kind = "anomaly",
			amount = shards,
			text = string.format("+%d VOID SHARDS", shards),
		})
	end

	if dropped then
		Net.sendEvent(player, {
			kind = "toast",
			text = string.format("%s dropped. Open the Fleet rack.", dropped),
		})
		Funnel.log(player, "Cache_Drop")
	end

	Funnel.log(player, "First_Strike")
	if inSweetSpot then
		Funnel.log(player, "First_SweetSpot")
	end
	if overdriveStarted then
		Funnel.log(player, "First_Overdrive")
	end
	if masteryUp then
		local rank = ProgressionService.masteryRank(state, state.equippedBlade)
		Net.sendEvent(player, {
			kind = "mastery",
			amount = rank,
			text = string.format("Mastery rank %d", rank),
		})
	end

	-- Auto-Vent pass: release the heat before it becomes a problem.
	if state.passes.autoVent and state.heat >= Config.VentThreshold then
		ForgeService.vent(player, true)
	end

	DataManager.markDirty(player)
	return true
end

-- ---------------------------------------------------------------------------
-- Venting
-- ---------------------------------------------------------------------------

--- Dumps heat for Aether. `automatic` suppresses the toast so a pass holder does
--- not get a notification storm.
function ForgeService.vent(player: Player, automatic: boolean?): (boolean, string?)
	local state = DataManager.get(player)
	if not state then
		return false, "Profile not loaded"
	end

	if state.heat < Config.VentThreshold then
		return false, "Heat too low to vent"
	end

	local stats = ProgressionService.stats(state)
	local bonus = ProgressionService.runeBonus(state)
	local salvage = ProgressionService.salvageBonus(state)
	local variant = ProgressionService.variantBonus(state)
	local gained = math.floor(
		state.heat
			* Config.AetherPerHeat
			* stats.ventMult
			* bonus.ventMult
			* salvage.ventMult
			* variant.ventMult
	)

	ProgressionService.addAether(state, gained)
	state.heat = 0

	if not automatic then
		Net.sendEvent(player, {
			kind = "vent",
			amount = gained,
			text = string.format("+%s Aether", NumberUtil.abbreviate(gained)),
		})
		Funnel.log(player, "First_Vent", gained)
	end

	DataManager.markDirty(player)
	return true, nil
end

-- ---------------------------------------------------------------------------
-- Heartbeat
-- ---------------------------------------------------------------------------

--- Advances every loaded profile. Passive income, heat decay, auto-clicks, and
--- playtime all land here so there is exactly one clock for the economy.
function ForgeService.step(dt: number)
	local now = os.time()

	for _, player in Players:GetPlayers() do
		local state = DataManager.get(player)
		if state == nil then
			continue
		end

		-- Heat always decays, so the gauge settles between bursts. Tempo runes
		-- speed the cooling, which is what makes them worth a socket.
		if state.heat > 0 then
			local bonus = ProgressionService.runeBonus(state)
			local salvage = ProgressionService.salvageBonus(state)
			local variant = ProgressionService.variantBonus(state)
			state.heat = math.max(
				0,
				state.heat
					- Config.HeatDecayPerSec * bonus.coolMult * salvage.coolMult * variant.coolMult * dt
			)
		end

		-- Landed expeditions pay out before passive income is measured, so the
		-- committed squad is back at the bench on the same tick it returns.
		local landed = ProgressionService.settleExpedition(state)
		if landed then
			Net.sendEvent(player, {
				kind = "expedition",
				amount = landed.aether,
				text = string.format(
					"%s returned: +%s Aether, +%d Cores, +%d Shards",
					landed.id,
					NumberUtil.abbreviate(landed.aether),
					landed.cores,
					landed.shards
				),
			})
			DataManager.markDirty(player)
		end

		-- Passive drone income.
		local passive = ProgressionService.passiveYield(state)
		if passive > 0 then
			creditStarMatter(state, passive * dt)
			DataManager.markDirty(player)
		end

		-- Tech-granted auto-clicks, accumulated fractionally so 0.5/s works.
		local stats = ProgressionService.stats(state)
		if stats.autoClicksPerSec > 0 then
			local acc = (autoClickAccumulators[player] or 0) + stats.autoClicksPerSec * dt
			local whole = math.floor(acc)
			autoClickAccumulators[player] = acc - whole
			for _ = 1, math.min(whole, 20) do
				strike(state)
			end
			if whole > 0 then
				DataManager.markDirty(player)
			end
		end

		-- Playtime, and the milestone check that rides on it.
		state.totalPlaytime += dt
		local acc = (playtimeAccumulators[player] or 0) + dt
		if acc >= 5 then
			playtimeAccumulators[player] = 0
			local reward = ProgressionService.checkPlaytime(state)
			if reward then
				Net.sendEvent(player, {
					kind = "toast",
					amount = reward,
					text = string.format("Playtime reward: +%d Aether", reward),
				})
				DataManager.markDirty(player)
			end
		else
			playtimeAccumulators[player] = acc
		end

		state.lastSeen = now
	end
end

--- Clears per-player scratch tables on leave.
function ForgeService.forget(player: Player)
	clickWindows[player] = nil
	autoClickAccumulators[player] = nil
	playtimeAccumulators[player] = nil
end

-- ---------------------------------------------------------------------------
-- Offline earnings
-- ---------------------------------------------------------------------------

--- Computes what accrued while the player was away, applies it, and returns the
--- result for the modal. Capped so a year away is not a win button.
function ForgeService.applyOffline(state: Types.ProfileState): { seconds: number, amount: number }
	local elapsed = math.max(0, os.time() - state.lastSeen)
	if elapsed < 60 then
		return { seconds = 0, amount = 0 }
	end

	local stats = ProgressionService.stats(state)
	local capped = math.min(elapsed, Config.OfflineCapSeconds)
	local rate = ProgressionService.passiveYield(state) * Config.OfflineEfficiency * stats.offlineMult
	local amount = rate * capped

	if amount > 0 then
		creditStarMatter(state, amount)
	end

	return { seconds = capped, amount = amount }
end

return ForgeService
