--!strict
-- Progression: blades, drones, tech, ascension, and every derived multiplier.
--
-- This is the only place that is allowed to answer "how much does a click pay
-- out". ForgeService asks; the client asks the same question locally for
-- prediction. One formula, no drift.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Config = require(Shared:WaitForChild("Config"))
local BladeRegistry = require(Shared:WaitForChild("BladeRegistry"))
local DroneRegistry = require(Shared:WaitForChild("DroneRegistry"))
local ForgeConfig = require(Shared:WaitForChild("ForgeConfig"))
local ModifierConfig = require(Shared:WaitForChild("ModifierConfig"))
local ExpeditionConfig = require(Shared:WaitForChild("ExpeditionConfig"))
local RuneConfig = require(Shared:WaitForChild("RuneConfig"))
local SalvageConfig = require(Shared:WaitForChild("SalvageConfig"))
local TechTreeConfig = require(Shared:WaitForChild("TechTreeConfig"))
local MonetizationConfig = require(Shared:WaitForChild("MonetizationConfig"))
local NumberUtil = require(Shared:WaitForChild("NumberUtil"))
local Types = require(Shared:WaitForChild("Types"))

local DataManager = require(script.Parent.DataManager)
local Funnel = require(script.Parent.Funnel)
local Net = require(script.Parent.Net)

local ProgressionService = {}

--- Copies currently offered in a trade. A locked uid cannot be melted or
--- rerolled until the trade ends, which is what stops the classic scam: offer a
--- blade, watch the other side accept, then melt it before the commit.
local tradeLocks: { [Player]: { [string]: boolean } } = {}

function ProgressionService.setTradeLocks(player: Player, uids: { string })
	local set: { [string]: boolean } = {}
	for _, uid in uids do
		set[uid] = true
	end
	tradeLocks[player] = set
end

function ProgressionService.clearTradeLocks(player: Player)
	tradeLocks[player] = nil
end

function ProgressionService.isTradeLocked(player: Player, uid: string): boolean
	local set = tradeLocks[player]
	return set ~= nil and set[uid] == true
end

local function now(): number
	return os.time()
end

-- ---------------------------------------------------------------------------
-- Derived values
-- ---------------------------------------------------------------------------

--- Full tech stat block for a profile.
function ProgressionService.stats(state: Types.ProfileState): TechTreeConfig.Stats
	return TechTreeConfig.compute(state.tech)
end

--- Multiplier of the equipped copy: registry multiplier times variant multiplier.
--- Falls back through the copy map rather than trusting the pointer, so a save
--- whose equippedUid was dropped still fights with something.
function ProgressionService.bladeMultiplier(state: Types.ProfileState): number
	local instance = state.blades[state.equippedUid]
	if instance == nil then
		for _, candidate in state.blades do
			instance = candidate
			break
		end
	end
	if instance == nil then
		local starter = BladeRegistry.get(BladeRegistry.StarterBlade)
		return if starter then starter.multiplier else 1
	end
	return ForgeConfig.powerCopy(instance)
end

--- The equipped copy's variant stats. Same additive shape as the rune and codex
--- bonuses so call sites stack them without a second branch.
export type VariantBonus = {
	critChance: number,
	shardMult: number,
	ventMult: number,
	coolMult: number,
}

function ProgressionService.variantBonus(state: Types.ProfileState): VariantBonus
	local instance = state.blades[state.equippedUid]
	local variant = if instance then ForgeConfig.variant(instance.variant) else ForgeConfig.Variants.standard
	local elemental = if instance
		then ModifierConfig.bonus(instance.element or "", instance.prefix or "", instance.suffix or "")
		else { critChance = 0, ventMult = 1, coolMult = 1, shardMult = 1 }
	return {
		critChance = variant.critChance + elemental.critChance,
		shardMult = variant.shardMult * elemental.shardMult,
		ventMult = variant.ventMult * elemental.ventMult,
		coolMult = variant.coolMult * elemental.coolMult,
	}
end

--- Everything that multiplies income regardless of source: passes, boosts.
function ProgressionService.globalMultiplier(state: Types.ProfileState): number
	local mult = 1
	if state.passes.x2StarMatter then
		mult *= 2
	end
	if state.passes.eternalForge then
		mult *= 1.25
	end
	-- Timed 2x from the Starter Forge Pack. Separate field from the paid 3x so
	-- the two boosts stack instead of one silently overwriting the other.
	if now() < state.boostX2Until then
		mult *= 2
	end
	if now() < state.overdriveUntil then
		mult *= MonetizationConfig.OverdriveMultiplier
	end
	return mult
end

--- Whether the skill Overdrive window is open. Separate from the paid boost: this
--- one is earned by ten clean strikes and lasts fifteen seconds.
function ProgressionService.forgeOverdriveActive(state: Types.ProfileState): boolean
	return now() < state.forgeOverdriveUntil
end

-- ---------------------------------------------------------------------------
-- Mastery & runes
-- ---------------------------------------------------------------------------

function ProgressionService.masteryStrikes(state: Types.ProfileState, bladeId: string): number
	return state.mastery[bladeId] or 0
end

function ProgressionService.masteryRank(state: Types.ProfileState, bladeId: string): number
	return RuneConfig.masteryRank(ProgressionService.masteryStrikes(state, bladeId))
end

--- The equipped blade's rack, sliced to the slots its rank actually unlocks.
--- Runes in locked slots stay in the save but contribute nothing.
function ProgressionService.activeSockets(state: Types.ProfileState): { string }
	local rack = state.sockets[state.equippedBlade]
	local unlocked = RuneConfig.socketsFor(ProgressionService.masteryRank(state, state.equippedBlade))
	local out: { string } = {}
	if rack == nil then
		return out
	end
	for index = 1, unlocked do
		out[index] = rack[index] or ""
	end
	return out
end

function ProgressionService.runeBonus(state: Types.ProfileState): RuneConfig.RuneBonus
	return RuneConfig.sum(ProgressionService.activeSockets(state))
end

--- Permanent codex bonuses, in the same shape as a rune bonus so every call site
--- adds them without a second code path. Four completed sets is the long goal.
function ProgressionService.salvageBonus(state: Types.ProfileState): SalvageConfig.Bonus
	return SalvageConfig.bonus(state.sigils)
end

--- Called once per accepted strike. Returns true when the rank changed, which is
--- the moment worth a toast.
function ProgressionService.addMastery(state: Types.ProfileState, bladeId: string): boolean
	local before = RuneConfig.masteryRank(state.mastery[bladeId] or 0)
	local count = (state.mastery[bladeId] or 0) + 1
	state.mastery[bladeId] = count
	return RuneConfig.masteryRank(count) > before
end

function ProgressionService.clickYield(state: Types.ProfileState): number
	local stats = ProgressionService.stats(state)
	local bonus = ProgressionService.runeBonus(state)
	local mult = Config.BaseClickYield
		* ProgressionService.bladeMultiplier(state)
		* stats.clickMult
		* bonus.clickMult
		* ProgressionService.salvageBonus(state).clickMult
		* ProgressionService.globalMultiplier(state)
	if ProgressionService.forgeOverdriveActive(state) then
		mult *= Config.OverdriveMultiplier
	end
	-- Opening flourish: the first strikes of a fresh save pay five times. It is
	-- deliberately not tied to a timer, because the point is the first interaction
	-- the player ever makes, not the first thirty seconds on the clock.
	if state.lifetimeStarMatter < Config.WowMomentCap then
		mult *= Config.WowMomentMultiplier
	end
	return mult
end

function ProgressionService.passiveYield(state: Types.ProfileState): number
	-- Drones on a mission are not at the bench. This is the whole cost of an
	-- expedition and the reason the payout can be generous.
	--
	-- The squad is taken off the *cheapest* tiers first, so a mission always
	-- costs the least income it could. Doing it the other way (proportional)
	-- would make the same mission more expensive for a player who had upgraded,
	-- which is the wrong direction for a cost.
	local away = if state.expedition.id ~= "" then state.expedition.squad else 0
	local total = 0
	for _, tier in DroneRegistry.tiers do
		local owned = state.fleet[tier.id] or 0
		if owned > 0 then
			local take = math.min(owned, away)
			away -= take
			total += (owned - take) * tier.yield
		end
	end
	if total <= 0 then
		return 0
	end
	local stats = ProgressionService.stats(state)
	return total
		* stats.droneYieldMult
		* ProgressionService.bladeMultiplier(state)
		* ProgressionService.globalMultiplier(state)
end

--- Drones owned across every tier. The fleet is a map, so this is the one place
--- that turns it back into a number; expeditions, the HUD and the ladder gates
--- all read it from here.
function ProgressionService.fleetTotal(state: Types.ProfileState): number
	local total = 0
	for _, tier in DroneRegistry.tiers do
		total += state.fleet[tier.id] or 0
	end
	return total
end

--- Account progress multiplier for the Star-Matter sinks. Rolls take it whole.
function ProgressionService.progressScale(state: Types.ProfileState): number
	return Config.progressScale(state.lifetimeStarMatter)
end

--- The banner is a run ladder, not a lifetime ladder. A lifetime-driven banner
--- is what put a 2T price on the first roll after an ascension: the run was
--- reset, the banner was not. Reading `runStarMatter` means the forge reopens at
--- the Scrap banner and climbs with the run, which is the point of a rebirth.
function ProgressionService.bannerTier(state: Types.ProfileState): ForgeConfig.Tier
	return ForgeConfig.tierFor(state.runStarMatter)
end

--- The account tax, blended by how much of the lifetime total this run has
--- re-earned. See `Config.runScale` for the post-ascension bug it fixes.
function ProgressionService.rollScale(state: Types.ProfileState): number
	return Config.runScale(state.runStarMatter, state.lifetimeStarMatter)
end

--- Credits spendable Aether and the lifetime counter the leaderboard reads.
function ProgressionService.addAether(state: Types.ProfileState, amount: number)
	if amount <= 0 then
		return
	end
	state.aether += amount
	state.lifetimeAether += amount
end

--- Credits spendable Quantum Cores and the lifetime counter.
function ProgressionService.addCores(state: Types.ProfileState, amount: number)
	if amount <= 0 then
		return
	end
	state.quantumCores += amount
	state.lifetimeCores += amount
end

-- ---------------------------------------------------------------------------
-- Codex
-- ---------------------------------------------------------------------------

--- Records every axis of one copy in the discovery index. Bumps `codexVersion`
--- only when something new lands, so the client's refetch stays event-shaped.
--- Called on every roll, every starter grant and every completed trade.
function ProgressionService.markCodex(state: Types.ProfileState, instance: Types.BladeInstance)
	local found = false
	local keys = {
		"blade:" .. instance.id,
		"variant:" .. instance.variant,
	}
	if instance.element and instance.element ~= "" then
		table.insert(keys, "element:" .. instance.element)
	end
	if instance.grade and instance.grade ~= "" then
		table.insert(keys, "grade:" .. instance.grade)
	end
	if instance.prefix and instance.prefix ~= "" then
		table.insert(keys, "prefix:" .. instance.prefix)
	end
	if instance.suffix and instance.suffix ~= "" then
		table.insert(keys, "suffix:" .. instance.suffix)
	end
	local qualityId = ModifierConfig.qualityId(
		instance.grade or "",
		instance.element or "",
		instance.prefix or "",
		instance.suffix or ""
	)
	if qualityId ~= "" then
		table.insert(keys, "quality:" .. qualityId)
	end
	for _, key in keys do
		if not state.codex[key] then
			state.codex[key] = true
			found = true
		end
	end
	if found then
		state.codexVersion += 1
	end
end

--- Re-marks every owned copy. Runs once at load so a schema-6 vault populates
--- the codex without needing to re-roll a blade the player already owns.
function ProgressionService.syncCodex(state: Types.ProfileState)
	for _, instance in state.blades do
		ProgressionService.markCodex(state, instance)
	end
end

--- Drones take the square root of the same multiplier: Aether income grows with
--- tech and runes but not with the blade multiplier, so a linear scale would
--- price the ladder out of reach the moment a player rolls a good blade.
function ProgressionService.dronePriceScale(state: Types.ProfileState): number
	return math.sqrt(ProgressionService.progressScale(state))
end

--- Price of the next copy of a tier.
function ProgressionService.droneCostFor(state: Types.ProfileState, tierId: string): number
	local tier = DroneRegistry.get(tierId)
	if tier == nil then
		return math.huge
	end
	return DroneRegistry.cost(tier, state.fleet[tier.id] or 0, ProgressionService.dronePriceScale(state))
end

--- Price of the next copy of the highest tier the player has unlocked. This is
--- the number the HUD and the guide use, and the one the Fleet tab defaults to.
function ProgressionService.droneCost(state: Types.ProfileState): number
	return ProgressionService.droneCostFor(state, DroneRegistry.bestUnlocked(ProgressionService.fleetTotal(state)).id)
end

--- Heat band currently in effect, accounting for tech widening.
function ProgressionService.heatBand(state: Types.ProfileState): { min: number, max: number, mult: number }
	local stats = ProgressionService.stats(state)
	return { min = stats.sweetSpotMin, max = stats.sweetSpotMax, mult = stats.sweetSpotMult }
end

--- Quantum Cores the player would receive if they ascended right now.
function ProgressionService.pendingCores(state: Types.ProfileState): number
	if state.runStarMatter < Config.AscendThreshold then
		return 0
	end
	return math.floor((state.runStarMatter / Config.AscendThreshold) ^ Config.AscendExponent)
end

function ProgressionService.canAscend(state: Types.ProfileState): boolean
	return state.runStarMatter >= Config.AscendThreshold
end

-- ---------------------------------------------------------------------------
-- Blades
-- ---------------------------------------------------------------------------

--- A uid that cannot collide with a legacy one. Time prefix keeps it sortable in
--- a save dump; the counter handles two rolls in the same second.
local forgeSerial = 0
local function mintUid(): string
	forgeSerial += 1
	return string.format("b%d_%d", os.time(), forgeSerial)
end

--- Bumps the inventory revision. Any mutation that can change the copy list must
--- call this, or the client will keep rendering the old list until rejoin.
local function markInventory(state: Types.ProfileState)
	state.invVersion += 1
end

--- Distinct blade ids owned. Views that only need "do I own this pattern" read
--- this instead of walking the copy map.
function ProgressionService.distinctIds(state: Types.ProfileState): { string }
	local seen: { [string]: boolean } = {}
	local out: { string } = {}
	for _, instance in state.blades do
		if not seen[instance.id] then
			seen[instance.id] = true
			table.insert(out, instance.id)
		end
	end
	return out
end

--- Moves the player's ramp to another crate.
---
--- The crate is profile state, not a per-roll argument: `forgeRoll` bills the ramp
--- of whatever crate the profile is on, so the pick has to land before the press.
--- Selecting the crate the profile is already on is a no-op, which keeps a
--- double-tap from resetting the ramp.
function ProgressionService.selectCrate(player: Player, id: string): (boolean, string?)
	local state = DataManager.get(player)
	if not state then
		return false, "Profile not loaded"
	end
	local tier = ForgeConfig.crate(id)
	if tier == nil then
		return false, "Unknown crate"
	end
	if state.runStarMatter < tier.unlock then
		return false,
			string.format("%s unlocks at %s lifetime Star-Matter", tier.name, NumberUtil.abbreviate(tier.unlock))
	end
	if state.forgeCrate == tier.id then
		return true, nil
	end
	state.forgeCrate = tier.id
	state.forgeRollTier = tier.tier
	state.forgeRolls = 0
	DataManager.markDirty(player)
	return true, nil
end

--- Rolls `count` copies from one crate.
---
--- This replaced the hardcoded ladder: the crate is chosen by the player (bounded
--- to what lifetime Star-Matter has opened), the rarity by that crate's own weight
--- column with pity on top, and the variant and modifier axes by their own tables.
--- Every roll creates a copy, so duplicates are inventory items rather than a
--- rejected purchase.
---
--- A ten-pull is one transaction: priced with `bulkRollCost`, charged once,
--- clamped to the free inventory slots, and reported as one event carrying the
--- best copy. Ten separate events would queue ten crate animations, which is the
--- opposite of what a ten-pull is for.
type RollResult = {
	uid: string,
	blade: BladeRegistry.Blade,
	variant: ForgeConfig.Variant,
	mods: ModifierConfig.Roll,
	power: number,
}

function ProgressionService.forgeRoll(player: Player, crateId: string?, count: number?): (boolean, string?)
	local state = DataManager.get(player)
	if not state then
		return false, "Profile not loaded"
	end

	-- The crate is named by the client, not inferred. An id the catalogue does not
	-- contain is a refused order rather than a silent fallback: falling back meant
	-- a bad id quietly moved the player's crate and reset the ramp they had been
	-- paying into.
	local tier = ForgeConfig.crate(crateId)
	if tier == nil and crateId == nil then
		tier = ProgressionService.bannerTier(state)
	end
	if tier == nil then
		return false, "Unknown crate"
	end
	if state.runStarMatter < tier.unlock then
		return false,
			string.format("%s unlocks at %s lifetime Star-Matter", tier.name, NumberUtil.abbreviate(tier.unlock))
	end

	-- A different crate starts a fresh ramp. The counter is per crate because a
	-- pricier crate already costs more; carrying the ramp across would
	-- double-charge for the same progression step.
	if state.forgeCrate ~= tier.id then
		state.forgeCrate = tier.id
		state.forgeRollTier = tier.tier
		state.forgeRolls = 0
	end

	local copiesBefore = 0
	for _ in state.blades do
		copiesBefore += 1
	end
	local free = math.max(0, Config.InventoryMax - copiesBefore)
	if free <= 0 then
		return false, string.format("Vault full: %d / %d. Melt a blade first.", copiesBefore, Config.InventoryMax)
	end

	local wanted = math.clamp(math.floor(count or 1), 1, 10)
	local batch = math.min(wanted, free)

	local cost = ForgeConfig.bulkRollCost(
		tier,
		state.forgeRolls,
		batch,
		ProgressionService.rollScale(state),
		ProgressionService.clickYield(state)
	)
	if state.starMatter < cost then
		return false, string.format("Needs %s Star-Matter", NumberUtil.abbreviate(cost))
	end

	local ownedBefore = #ProgressionService.distinctIds(state)

	-- Clamp at zero: a float balance should never print as `-0.0000001`, and the
	-- guard above is the only path that can spend below zero.
	state.starMatter = math.max(0, state.starMatter - cost)

	local best: RollResult? = nil
	for _ = 1, batch do
		-- Pity: one short of the guarantee forces a pity rarity from this crate's
		-- own pool. The counter resets only on a pity-rarity hit, so a lucky early
		-- Void does not eat the guarantee the player was promised.
		local forcePity = state.forgePity + 1 >= tier.pity
		local rarity = ForgeConfig.rollRarity(forcePity, tier)
		local blade = ForgeConfig.pickBlade(tier.tier, rarity)
		if blade == nil then
			break
		end
		local variant = ForgeConfig.rollVariant()
		local mods = ModifierConfig.roll()

		local uid = mintUid()
		state.blades[uid] = {
			id = blade.id,
			variant = variant.id,
			forgedAt = now(),
			element = mods.element,
			grade = mods.grade,
			prefix = mods.prefix,
			suffix = mods.suffix,
		}
		ProgressionService.markCodex(state, state.blades[uid])

		if ForgeConfig.PityRarities[rarity] then
			state.forgePity = 0
		else
			state.forgePity += 1
		end
		state.forgeRolls += 1

		local power = ForgeConfig.powerCopy(state.blades[uid])
		if best == nil or power > best.power then
			best = { uid = uid, blade = blade, variant = variant, mods = mods, power = power }
		end
	end

	markInventory(state)

	if best == nil then
		return false, "The forge is cold"
	end

	-- First copy of a pattern still sheds Aether, so a new silhouette always pays
	-- something even when the roll is weak.
	if #ProgressionService.distinctIds(state) > ownedBefore then
		local tierIndex = math.clamp(best.blade.tier, 1, #Config.AetherOnForge)
		ProgressionService.addAether(state, Config.AetherOnForge[tierIndex])
	end

	-- Auto-equip only when it is genuinely stronger. A Prismatic mid-tier blade
	-- can beat a Standard two tiers up, which is the whole point of variants;
	-- with modifiers the same is true of a Transcendent one.
	if best.power > ProgressionService.bladeMultiplier(state) then
		state.equippedUid = best.uid
		state.equippedBlade = best.blade.id
	end

	DataManager.markDirty(player)
	Funnel.log(player, string.format("Forge_%s_%s_%s", best.blade.id, best.variant.id, best.mods.grade), cost)
	Net.sendEvent(player, {
		kind = "forged",
		blade = best.blade.id,
		variant = best.variant.id,
		element = best.mods.element,
		grade = best.mods.grade,
		prefix = best.mods.prefix,
		suffix = best.mods.suffix,
		amount = cost,
		batch = batch,
		crate = tier.id,
		crit = best.variant.id ~= ForgeConfig.StandardVariant or best.mods.grade ~= "chipped",
		text = string.format(
			"%s %s",
			ModifierConfig.displayName(best.blade.name, best.mods.prefix, best.mods.suffix),
			ModifierConfig.condition(best.mods.grade, best.mods.element)
		),
	})
	return true, nil
end

--- Equips one copy by uid. Mastery and sockets stay keyed on the blade id, so a
--- Prismatic Rusted Cleaver shares both with a Standard one.
function ProgressionService.equipBlade(player: Player, uid: string): (boolean, string?)
	local state = DataManager.get(player)
	if not state then
		return false, "Profile not loaded"
	end
	local instance = state.blades[uid]
	if instance == nil then
		return false, "Not forged yet"
	end
	state.equippedUid = uid
	state.equippedBlade = instance.id
	DataManager.markDirty(player)
	return true, nil
end

--- Melts one copy into Scrap. The last copy of the equipped blade is protected:
--- a player cannot accidentally end up with nothing to swing.
function ProgressionService.salvageBlade(player: Player, uid: string): (boolean, string?)
	local state = DataManager.get(player)
	if not state then
		return false, "Profile not loaded"
	end
	local instance = state.blades[uid]
	if instance == nil then
		return false, "No such blade"
	end
	if uid == state.equippedUid then
		return false, "Equip another blade first"
	end
	if state.favorites[uid] then
		return false, "Favorited: unlock it first"
	end
	if ProgressionService.isTradeLocked(player, uid) then
		return false, "Offered in a trade"
	end
	local copies = 0
	for _ in state.blades do
		copies += 1
	end
	if copies <= 1 then
		return false, "That is your only blade"
	end

	local value = ForgeConfig.salvageCopy(instance)
	state.scrap += value
	state.blades[uid] = nil
	markInventory(state)

	DataManager.markDirty(player)
	Funnel.log(player, "Blade_Salvage", value)
	Net.sendEvent(player, { kind = "toast", text = string.format("Melted down: +%d Scrap", value) })
	return true, nil
end

--- Rerolls one copy's variant for Scrap. The sink for duplicate blades: a player
--- who keeps rolling Rusted Cleavers is not wasting them, they are buying a
--- second chance at the variant on the blade they actually use.
function ProgressionService.rerollVariant(player: Player, uid: string): (boolean, string?)
	local state = DataManager.get(player)
	if not state then
		return false, "Profile not loaded"
	end
	local instance = state.blades[uid]
	if instance == nil then
		return false, "No such blade"
	end
	local blade = BladeRegistry.get(instance.id)
	if blade == nil then
		return false, "Unknown blade"
	end
	if ProgressionService.isTradeLocked(player, uid) then
		return false, "Offered in a trade"
	end

	local cost = ForgeConfig.rerollCost(blade.tier)
	if state.scrap < cost then
		return false, string.format("Needs %d Scrap", cost)
	end

	state.scrap -= cost
	local variant = ForgeConfig.rollVariant()
	instance.variant = variant.id
	markInventory(state)

	DataManager.markDirty(player)
	Net.sendEvent(player, {
		kind = "toast",
		text = string.format("%s: %s", blade.name, variant.name),
	})
	return true, nil
end

--- Equips whichever owned copy has the highest power. Variant multipliers are
--- part of the score, so a Prismatic Rusted Cleaver can beat a Standard two
--- tiers up. Ties keep the current copy: re-equipping on a coin-flip power
--- match would shuffle the player's blade for no gain.
function ProgressionService.equipBest(player: Player): (boolean, string?)
	local state = DataManager.get(player)
	if not state then
		return false, "Profile not loaded"
	end

	local bestUid: string? = nil
	local bestPower = -1
	for uid, instance in state.blades do
		local power = ForgeConfig.powerCopy(instance)
		if power > bestPower then
			bestPower = power
			bestUid = uid
		end
	end

	if bestUid == nil then
		return false, "No blades owned"
	end
	if bestUid == state.equippedUid then
		return false, "Already equipped"
	end

	local instance = state.blades[bestUid]
	state.equippedUid = bestUid
	state.equippedBlade = instance.id
	local blade = BladeRegistry.get(instance.id)

	DataManager.markDirty(player)
	Net.sendEvent(player, {
		kind = "toast",
		text = string.format("Equipped %s", if blade then blade.name else instance.id),
	})
	return true, nil
end

--- Melts a batch of copies in one action. The single-copy path is
--- `salvageBlade`; this is the same rules applied to a selection, so a batch can
--- never melt the equipped copy or leave the player with nothing to swing.
function ProgressionService.salvageMany(player: Player, uids: { any }): (boolean, string?, number)
	local state = DataManager.get(player)
	if not state then
		return false, "Profile not loaded", 0
	end

	local copies = 0
	for _ in state.blades do
		copies += 1
	end

	local claimed: { [string]: boolean } = {}
	local total = 0
	local melted = 0

	for _, raw in uids do
		if type(raw) ~= "string" or claimed[raw] then
			continue
		end
		claimed[raw] = true
		local instance = state.blades[raw]
		if
			instance == nil
			or raw == state.equippedUid
			or state.favorites[raw]
			or ProgressionService.isTradeLocked(player, raw)
			or copies - melted <= 1
		then
			continue
		end
		total += ForgeConfig.salvageCopy(instance)
		state.blades[raw] = nil
		melted += 1
	end

	if melted == 0 then
		return false, "Nothing to melt", 0
	end

	state.scrap += total
	markInventory(state)
	DataManager.markDirty(player)
	Funnel.log(player, "Blade_Salvage_Batch", total)
	Net.sendEvent(player, {
		kind = "toast",
		text = string.format("Melted %d copies: +%d Scrap", melted, total),
	})
	return true, nil, total
end

--- Persists a client preference. Only the three known keys are accepted; an
--- unknown key is a no-op rather than a new field in the save.
function ProgressionService.setSetting(player: Player, key: string, value: boolean): (boolean, string?)
	local state = DataManager.get(player)
	if not state then
		return false, "Profile not loaded"
	end
	if key == "sfx" then
		state.settings.sfx = value
	elseif key == "vfx" then
		state.settings.vfx = value
	elseif key == "shake" then
		state.settings.shake = value
	elseif key == "trades" then
		state.settings.trades = value
	else
		return false, "Unknown setting"
	end
	DataManager.markDirty(player)
	return true, nil
end

--- Toggles the favorite flag on one copy. A favorite is protected from both melt
--- paths, which is the whole point: the vault batches duplicates, and a variant
--- worth keeping must be able to sit inside a group of three without being swept
--- up by SELECT DUPES.
function ProgressionService.setFavorite(player: Player, uid: unknown): (boolean, string?)
	local state = DataManager.get(player)
	if not state then
		return false, "Profile not loaded"
	end
	if type(uid) ~= "string" or state.blades[uid] == nil then
		return false, "No such blade"
	end
	if state.favorites[uid] then
		state.favorites[uid] = nil
	else
		state.favorites[uid] = true
	end
	DataManager.markDirty(player)
	return true, nil
end

--- Records that the first-join guide has been seen. Called once when the guide is
--- finished or skipped; `TutorialController` only auto-starts while it is false.
function ProgressionService.markGuideSeen(player: Player): (boolean, string?)
	local state = DataManager.get(player)
	if not state then
		return false, "Profile not loaded"
	end
	if state.guideSeen then
		return true, nil
	end
	state.guideSeen = true
	DataManager.markDirty(player)
	return true, nil
end

--- Clears the onboarding flags so QA can replay a first join without wiping the
--- profile. Studio only: `tutorialCompleted` gates the one-time reward, and an
--- action that resets it in a live server is a reward exploit.
function ProgressionService.resetGuide(player: Player): (boolean, string?)
	local state = DataManager.get(player)
	if not state then
		return false, "Profile not loaded"
	end
	state.tutorialCompleted = false
	state.guideSeen = false
	DataManager.markDirty(player)
	return true, nil
end

-- ---------------------------------------------------------------------------
-- Drones
-- ---------------------------------------------------------------------------

--- Buys as many copies of one tier as the Aether allows, up to `requested`.
---
--- Payload is `{ id, count }`. A bare number is accepted and means "the best
--- tier unlocked", because the guide and older callers still send one.
function ProgressionService.buyDrones(player: Player, requested: unknown): (boolean, string?)
	local state = DataManager.get(player)
	if not state then
		return false, "Profile not loaded"
	end

	local tierId = DroneRegistry.bestUnlocked(ProgressionService.fleetTotal(state)).id
	local count = 1
	if type(requested) == "number" then
		count = math.clamp(math.floor(requested), 1, 100)
	elseif type(requested) == "table" then
		local payload = requested :: any
		if type(payload.id) == "string" then
			tierId = payload.id
		end
		if type(payload.count) == "number" then
			count = math.clamp(math.floor(payload.count), 1, 100)
		end
	end

	local tier = DroneRegistry.get(tierId)
	if tier == nil then
		return false, "Unknown drone"
	end
	if not DroneRegistry.unlocked(tier, ProgressionService.fleetTotal(state)) then
		return false, string.format("%s needs %d drones", tier.name, tier.unlockAt)
	end

	local bought = 0
	local scale = ProgressionService.dronePriceScale(state)
	for _ = 1, count do
		local owned = state.fleet[tier.id] or 0
		local cost = DroneRegistry.cost(tier, owned, scale)
		if state.aether < cost then
			break
		end
		state.aether -= cost
		state.fleet[tier.id] = owned + 1
		bought += 1
	end

	if bought == 0 then
		return false, string.format("Needs %s Aether", NumberUtil.abbreviate(DroneRegistry.cost(tier, state.fleet[tier.id] or 0, scale)))
	end

	DataManager.markDirty(player)
	Funnel.log(player, "First_Drone", ProgressionService.fleetTotal(state))
	Net.sendEvent(player, {
		kind = "purchase",
		amount = bought,
		text = string.format("+%d %s", bought, if bought == 1 then tier.name else tier.name .. "s"),
	})
	return true, nil
end

-- ---------------------------------------------------------------------------
-- Expeditions
-- ---------------------------------------------------------------------------

local function emptyExpedition(): Types.ExpeditionState
	return { id = "", squad = 0, startedAt = 0, endsAt = 0, aether = 0, cores = 0, shards = 0 }
end

function ProgressionService.expeditionActive(state: Types.ProfileState): boolean
	return state.expedition.id ~= ""
end

--- Commits a squad. The payout is snapshotted here, not at settlement, so
--- swapping blades mid-flight cannot inflate a run the player already paid for
--- with idle time.
function ProgressionService.dispatch(player: Player, missionId: string): (boolean, string?)
	local state = DataManager.get(player)
	if not state then
		return false, "Profile not loaded"
	end

	local mission = ExpeditionConfig.get(missionId)
	if mission == nil then
		return false, "Unknown mission"
	end
	if ProgressionService.expeditionActive(state) then
		return false, "A mission is already out"
	end

	-- The squad cannot exceed what is parked at the bench, and the drones that
	-- stay home keep earning. No upper fraction beyond the fleet itself: sending
	-- everything is a legal gamble.
	local total = ProgressionService.fleetTotal(state)
	if total < mission.squad then
		return false, string.format("Needs %d drones", mission.squad)
	end

	local mult = ProgressionService.bladeMultiplier(state) * ProgressionService.globalMultiplier(state)
	local startedAt = now()
	state.expedition = {
		id = mission.id,
		squad = mission.squad,
		startedAt = startedAt,
		endsAt = startedAt + mission.seconds,
		aether = math.floor(mission.aether * mult),
		cores = mission.cores,
		shards = mission.shards,
	}

	DataManager.markDirty(player)
	Funnel.log(player, "First_Expedition", mission.squad)
	Net.sendEvent(player, {
		kind = "toast",
		text = string.format("%s launched: %d drones away", mission.name, mission.squad),
	})
	return true, nil
end

--- Pays out a landed mission. Safe to call every tick: it no-ops until the clock
--- passes `endsAt`, which is also how an offline mission settles on rejoin.
function ProgressionService.settleExpedition(state: Types.ProfileState): { id: string, aether: number, cores: number, shards: number }?
	if state.expedition.id == "" then
		return nil
	end
	if now() < state.expedition.endsAt then
		return nil
	end

	local done = state.expedition
	ProgressionService.addAether(state, done.aether)
	ProgressionService.addCores(state, done.cores)
	state.voidShards += done.shards
	state.expedition = emptyExpedition()

	return { id = done.id, aether = done.aether, cores = done.cores, shards = done.shards }
end

-- ---------------------------------------------------------------------------
-- Runes
-- ---------------------------------------------------------------------------

function ProgressionService.craftRune(player: Player, runeId: string): (boolean, string?)
	local state = DataManager.get(player)
	if not state then
		return false, "Profile not loaded"
	end
	local rune = RuneConfig.get(runeId)
	if rune == nil then
		return false, "Unknown rune"
	end
	if state.voidShards < rune.cost then
		return false, string.format("Needs %d Void Shards", rune.cost)
	end

	state.voidShards -= rune.cost
	state.runes[runeId] = (state.runes[runeId] or 0) + 1

	DataManager.markDirty(player)
	Funnel.log(player, "First_Rune", rune.cost)
	Net.sendEvent(player, { kind = "toast", text = string.format("Crafted %s", rune.name) })
	return true, nil
end

--- Puts one rune from the bag into a slot on the equipped blade. `slot` is
--- optional; without it the first free unlocked slot is used.
function ProgressionService.socketRune(player: Player, runeId: string, slot: number?): (boolean, string?)
	local state = DataManager.get(player)
	if not state then
		return false, "Profile not loaded"
	end
	if (state.runes[runeId] or 0) <= 0 then
		return false, "No rune to socket"
	end

	local bladeId = state.equippedBlade
	local unlocked = RuneConfig.socketsFor(ProgressionService.masteryRank(state, bladeId))
	if unlocked <= 0 then
		return false, "Mastery rank 1 unlocks a socket"
	end

	local rack: Types.SocketRack = state.sockets[bladeId] or { "", "", "" }
	for index = 1, RuneConfig.MaxSockets do
		rack[index] = rack[index] or ""
	end

	local target = slot
	if target == nil then
		for index = 1, unlocked do
			if rack[index] == "" then
				target = index
				break
			end
		end
	end
	if target == nil or target < 1 or target > unlocked then
		return false, "No free socket"
	end
	if rack[target] ~= "" then
		return false, "Socket occupied"
	end

	state.runes[runeId] = (state.runes[runeId] or 1) - 1
	if state.runes[runeId] <= 0 then
		state.runes[runeId] = nil
	end
	rack[target] = runeId
	state.sockets[bladeId] = rack

	DataManager.markDirty(player)
	Funnel.log(player, "First_Socket", target)
	Net.sendEvent(player, { kind = "toast", text = string.format("%s socketed", RuneConfig.get(runeId).name) })
	return true, nil
end

function ProgressionService.unsocketRune(player: Player, slot: number): (boolean, string?)
	local state = DataManager.get(player)
	if not state then
		return false, "Profile not loaded"
	end
	local rack = state.sockets[state.equippedBlade]
	local id = if rack then rack[slot] else nil
	if id == nil or id == "" or RuneConfig.get(id) == nil then
		return false, "Socket is empty"
	end

	rack[slot] = ""
	state.runes[id] = (state.runes[id] or 0) + 1

	DataManager.markDirty(player)
	return true, nil
end

-- ---------------------------------------------------------------------------
-- Salvage caches
-- ---------------------------------------------------------------------------

--- One accepted strike is one point of meter. When the meter fills and the rack
--- has room, a cache drops with its rarity already rolled.
---
--- The meter stops while the rack is full rather than overflowing, so hoarding
--- is a visible choice with a visible cost instead of a silent waste.
function ProgressionService.addSalvageMeter(state: Types.ProfileState): SalvageConfig.Rarity?
	if #state.caches >= SalvageConfig.MaxCaches then
		return nil
	end
	state.cacheMeter += 1
	if state.cacheMeter < SalvageConfig.StrikesPerCache then
		return nil
	end
	state.cacheMeter = 0
	local rarity = SalvageConfig.rollRarity()
	table.insert(state.caches, {
		rarity = rarity.id,
		readyAt = 0,
		droppedAt = now(),
	})
	return rarity
end

--- Starts the crack clock. A zero-second cache is claimable on the same tick,
--- which is why the client treats `readyAt > 0 and secondsLeft == 0` as READY.
function ProgressionService.crackCache(player: Player, index: number): (boolean, string?)
	local state = DataManager.get(player)
	if not state then
		return false, "Profile not loaded"
	end
	local cache = state.caches[index]
	if cache == nil then
		return false, "That slot is empty"
	end
	if cache.readyAt > 0 then
		return false, "Already cracking"
	end
	local rarity = SalvageConfig.getRarity(cache.rarity)
	if rarity == nil then
		return false, "Unknown cache"
	end

	cache.readyAt = now() + rarity.crackSeconds
	DataManager.markDirty(player)
	Funnel.log(player, "Cache_Crack", rarity.crackSeconds)

	if rarity.crackSeconds > 0 then
		Net.sendEvent(player, {
			kind = "toast",
			text = string.format("%s cracking: %d seconds", rarity.name, rarity.crackSeconds),
		})
	end
	return true, nil
end

--- Claims a cracked cache. Rewards are scaled by the blade at claim time, so the
--- cache is worth what the player is worth when they open it.
---
--- A sigil roll on a completed codex melts into bonus Cores instead of paying
--- nothing: a 1-in-1 duplicate is the one drop that must never read as a miss.
function ProgressionService.claimCache(player: Player, index: number): (boolean, string?)
	local state = DataManager.get(player)
	if not state then
		return false, "Profile not loaded"
	end
	local cache = state.caches[index]
	if cache == nil then
		return false, "That slot is empty"
	end
	if cache.readyAt <= 0 then
		return false, "Crack it first"
	end
	local remaining = cache.readyAt - now()
	if remaining > 0 then
		return false, string.format("%ds left", remaining)
	end

	local rarity = SalvageConfig.getRarity(cache.rarity)
	if rarity == nil then
		return false, "Unknown cache"
	end

	local mult = ProgressionService.bladeMultiplier(state) * ProgressionService.globalMultiplier(state)
	local aether = math.floor(rarity.aether * mult)
	local cores = rarity.cores
	local shards = rarity.shards

	local setsBefore = SalvageConfig.bonus(state.sigils).sets
	local sigil = nil
	if math.random() < rarity.sigilChance then
		sigil = SalvageConfig.rollSigil(state.sigils)
		if sigil then
			state.sigils[sigil.id] = true
		else
			-- Codex complete: the roll becomes a Core bonus instead of a dud.
			cores += rarity.cores + 4
		end
	end

	ProgressionService.addAether(state, aether)
	ProgressionService.addCores(state, cores)
	state.voidShards += shards
	table.remove(state.caches, index)

	DataManager.markDirty(player)
	Funnel.log(player, "Cache_Open", aether)

	local parts = { string.format("+%s Aether", NumberUtil.abbreviate(aether)) }
	if cores > 0 then
		table.insert(parts, string.format("+%d Cores", cores))
	end
	if shards > 0 then
		table.insert(parts, string.format("+%d Shards", shards))
	end
	if sigil then
		table.insert(parts, sigil.name)
		local setsAfter = SalvageConfig.bonus(state.sigils).sets
		if setsAfter > setsBefore then
			table.insert(parts, string.format("SET COMPLETE (+%d)", setsAfter))
			Funnel.log(player, "Codex_Set", setsAfter)
		end
	end

	Net.sendEvent(player, { kind = "toast", text = table.concat(parts, "  ·  ") })
	return true, nil
end

-- ---------------------------------------------------------------------------
-- Tech tree
-- ---------------------------------------------------------------------------

function ProgressionService.buyTech(player: Player, nodeId: string): (boolean, string?)
	local state = DataManager.get(player)
	if not state then
		return false, "Profile not loaded"
	end

	local node = TechTreeConfig.get(nodeId)
	if node == nil then
		return false, "Unknown node"
	end

	local level = state.tech[nodeId] or 0
	if level >= node.maxLevel then
		return false, "Already mastered"
	end

	local cost = TechTreeConfig.cost(node, level)
	if state.quantumCores < cost then
		return false, "Not enough Quantum Cores"
	end

	state.quantumCores -= cost
	state.tech[nodeId] = level + 1

	DataManager.markDirty(player)
	Net.sendEvent(player, {
		kind = "purchase",
		text = string.format("%s -> Lv%d", node.name, level + 1),
	})
	return true, nil
end

-- ---------------------------------------------------------------------------
-- Ascension
-- ---------------------------------------------------------------------------

function ProgressionService.ascend(player: Player): (boolean, string?)
	local state = DataManager.get(player)
	if not state then
		return false, "Profile not loaded"
	end

	local cores = ProgressionService.pendingCores(state)
	if cores <= 0 then
		return false, "Not enough Star-Matter this run"
	end

	state.quantumCores += cores
	state.lifetimeCores += cores
	state.ascensions += 1

	-- Reset the run, keep the meta.
	state.starMatter = 0
	state.runStarMatter = 0
	state.aether = 0
	state.fleet = {}
	state.heat = 0
	state.lockUntil = 0
	state.streak = 0
	state.forgeOverdriveUntil = 0
	-- A mission in flight is forfeit: the drones it carried are part of the run
	-- being reset. Mastery, runes and sockets are meta and stay.
	state.expedition = emptyExpedition()

	local starterIds = TechTreeConfig.startingBladeIds(state.tech)
	state.blades = {}
	for _, id in starterIds do
		local uid = string.format("ascend_%d_%s", state.ascensions, id)
		local instance: Types.BladeInstance = {
			id = id,
			variant = ForgeConfig.StandardVariant,
			forgedAt = now(),
		}
		state.blades[uid] = instance
		ProgressionService.markCodex(state, instance)
	end

	-- Equip the strongest copy the reset left behind.
	local bestUid: string? = nil
	local bestMult = 0
	for uid, instance in state.blades do
		local power = ForgeConfig.powerCopy(instance)
		if power > bestMult then
			bestMult = power
			bestUid = uid
		end
	end
	if bestUid then
		state.equippedUid = bestUid
		state.equippedBlade = state.blades[bestUid].id
	else
		state.equippedUid = ""
		state.equippedBlade = BladeRegistry.StarterBlade
	end
	state.forgePity = 0
	-- Favorites point at copies that no longer exist, and the roll ramp belongs
	-- to the run that just ended.
	state.favorites = {}
	state.forgeRolls = 0
	state.forgeRollTier = 0
	ProgressionService.clearTradeLocks(player)
	markInventory(state)

	DataManager.markDirty(player)
	Funnel.log(player, "First_Ascension", cores)
	Net.sendEvent(player, {
		kind = "ascend",
		amount = cores,
		text = string.format(
			"Ascended: +%s Quantum Cores. The forge reopens at %s.",
			NumberUtil.abbreviate(cores),
			ProgressionService.bannerTier(state).name
		),
	})
	return true, nil
end

-- ---------------------------------------------------------------------------
-- Sync payload
-- ---------------------------------------------------------------------------

--- Builds the compact per-tick payload. Called by the heartbeat, never by the
--- client.
function ProgressionService.buildPayload(state: Types.ProfileState): Types.SyncPayload
	local band = ProgressionService.heatBand(state)
	local lockRemaining = math.max(0, state.lockUntil - now())
	local tier = ForgeConfig.crate(state.forgeCrate) or ProgressionService.bannerTier(state)
	local distinct = ProgressionService.distinctIds(state)
	local copies = 0
	for _ in state.blades do
		copies += 1
	end

	local equipped = state.equippedBlade
	local rank = ProgressionService.masteryRank(state, equipped)
	local strikes = ProgressionService.masteryStrikes(state, equipped)
	local nextThreshold = RuneConfig.nextThreshold(strikes)

	-- Per-crate prices for the browser. Computed here rather than on the client
	-- because the ramp scale and the income floor are both server facts, and a
	-- button that quotes a price the server will refuse is worse than no button.
	local scale = ProgressionService.rollScale(state)
	local income = ProgressionService.clickYield(state)
	local costs: { [string]: Types.CrateQuote } = {}
	for _, crate in ForgeConfig.Tiers do
		if state.runStarMatter >= crate.unlock then
			local taken = if state.forgeCrate == crate.id then state.forgeRolls else 0
			costs[crate.id] = {
				one = ForgeConfig.bulkRollCost(crate, taken, 1, scale, income),
				ten = ForgeConfig.bulkRollCost(crate, taken, 10, scale, income),
			}
		end
	end

	-- Always three entries so the socket rack can be indexed without nil checks;
	-- `socketSlots` says how many of them the rank actually unlocked.
	local rack: Types.SocketRack = {}
	local stored = state.sockets[equipped]
	for index = 1, RuneConfig.MaxSockets do
		rack[index] = if stored then (stored[index] or "") else ""
	end

	local mission = state.expedition
	local squadAway = if mission.id ~= "" then mission.squad else 0

	local caches: { Types.SyncCache } = {}
	for _, cache in state.caches do
		caches[#caches + 1] = {
			rarity = cache.rarity,
			readyAt = cache.readyAt,
			secondsLeft = if cache.readyAt > 0 then math.max(0, cache.readyAt - now()) else 0,
		}
	end

	-- Fleet. One entry per rung, ordered, with the price of the next copy and the
	-- next ten. Precomputed here because the client repaints both buttons at
	-- 10Hz, and a geometric series per frame per tier is work the server has
	-- already done once.
	local fleetTotal = ProgressionService.fleetTotal(state)
	local fleetEntries: { Types.FleetEntry } = {}
	local droneScale = ProgressionService.dronePriceScale(state)
	for _, rung in DroneRegistry.tiers do
		local owned = state.fleet[rung.id] or 0
		fleetEntries[#fleetEntries + 1] = {
			id = rung.id,
			owned = owned,
			cost = DroneRegistry.cost(rung, owned, droneScale),
			bulk = DroneRegistry.bulkCost(rung, owned, 10, droneScale),
			unlocked = DroneRegistry.unlocked(rung, fleetTotal),
			unlockAt = rung.unlockAt,
		}
	end

	return {
		sm = state.starMatter,
		as = state.aether,
		qc = state.quantumCores,
		heat = state.heat,
		locked = lockRemaining > 0,
		lockRemaining = lockRemaining,
		drones = fleetTotal,
		fleet = fleetEntries,
		equipped = equipped,
		equippedUid = state.equippedUid,
		equippedVariant = if state.blades[state.equippedUid]
			then state.blades[state.equippedUid].variant
			else ForgeConfig.StandardVariant,
		equippedElement = if state.blades[state.equippedUid]
			then (state.blades[state.equippedUid].element or "")
			else "",
		equippedGrade = if state.blades[state.equippedUid]
			then (state.blades[state.equippedUid].grade or "")
			else "",
		equippedPrefix = if state.blades[state.equippedUid]
			then (state.blades[state.equippedUid].prefix or "")
			else "",
		equippedSuffix = if state.blades[state.equippedUid]
			then (state.blades[state.equippedUid].suffix or "")
			else "",
		owned = distinct,
		invVersion = state.invVersion,
		invCount = copies,
		invMax = Config.InventoryMax,
		codexVersion = state.codexVersion,
		favorites = state.favorites,
		forgeRolls = state.forgeRolls,
		--- The crate the player is on. The roll action names a crate, so the UI
		--- and the server have to agree on which one without the client guessing
		--- from lifetime income.
		forgeCrate = state.forgeCrate,
		tech = state.tech,
		ascensions = state.ascensions,
		clickYield = ProgressionService.clickYield(state),
		passiveYield = ProgressionService.passiveYield(state),
		mult = ProgressionService.bladeMultiplier(state),
		bandMin = band.min,
		bandMax = band.max,
		bandMult = band.mult,
		inSweetSpot = state.heat >= band.min and state.heat <= band.max,
		overdriveRemaining = math.max(0, state.forgeOverdriveUntil - now()),
		boostRemaining = math.max(0, state.boostX2Until - now()),
		streak = state.streak,
		streakGoal = Config.StreakForOverdrive,
		shards = state.voidShards,
		mastery = rank,
		masteryXp = strikes,
		masteryNext = nextThreshold,
		masteryAll = state.mastery,
		equippedSockets = rack,
		socketSlots = RuneConfig.socketsFor(rank),
		runes = state.runes,
		expId = mission.id,
		expSquad = squadAway,
		expRemaining = if mission.id ~= "" then math.max(0, mission.endsAt - now()) else 0,
		expAether = mission.aether,
		expCores = mission.cores,
		expShards = mission.shards,
		squadAway = squadAway,
		cacheMeter = state.cacheMeter,
		cacheGoal = SalvageConfig.StrikesPerCache,
		caches = caches,
		sigils = state.sigils,
		codexSets = SalvageConfig.bonus(state.sigils).sets,
		runSm = state.runStarMatter,
		ascendAt = Config.AscendThreshold,
		dailyReady = ProgressionService.dailyReady(state),
		dailyStreak = state.dailyStreak,
		starterBoostAt = state.starterBoostAt,
		tutorialCompleted = state.tutorialCompleted,
		guideSeen = state.guideSeen,
		nextBlade = nil,
		nextBladeCost = nil,
		forgeTier = tier.tier,
		forgeTierName = tier.name,
		forgeCost = ForgeConfig.rollCost(
			tier,
			state.forgeRolls,
			ProgressionService.rollScale(state),
			ProgressionService.clickYield(state)
		),
		--- Priced per unlocked crate, so the crate browser never has to guess the
		--- account scale or the ramp. A crate that is not the current one starts a
		--- fresh ramp by definition, which is why it is priced at zero rolls.
		forgeCosts = costs,
		forgePity = state.forgePity,
		--- Pity belongs to the crate being rolled, not to the banner lifetime has
		--- opened. They were the same number when there was one pool; with five,
		--- printing the Singularity goal over a Standard counter read `15 / 8`.
		forgePityGoal = tier.pity,
		scrap = state.scrap,
		settings = state.settings,
		droneCost = ProgressionService.droneCost(state),
		droneTier = DroneRegistry.bestUnlocked(fleetTotal).id,
	}
end

-- ---------------------------------------------------------------------------
-- Retention helpers
-- ---------------------------------------------------------------------------

function ProgressionService.dailyReady(state: Types.ProfileState): boolean
	local elapsed = now() - state.dailyLastClaim
	return elapsed >= 86400 or state.dailyStreak == 0
end

--- Grants the welcome boost once per profile.
---
--- Called from the join path before the first payload, so the modal and the HUD
--- chip both read the same field the income formula reads. `starterBoostAt` is the
--- idempotency flag: it is written in the same mutation as the boost, so a
--- reconnect cannot stack a second hour, and a replayed join cannot either.
---
--- Every save that predates this feature has no `starterBoostAt`, which reads as
--- zero and therefore grants once. That is deliberate: the drone nerf landed in
--- the same update, and handing existing testers the hour is the honest way to
--- let them re-measure the curve.
function ProgressionService.grantStarterBoost(state: Types.ProfileState): boolean
	if (state.starterBoostAt or 0) > 0 then
		return false
	end
	local stamp = now()
	state.starterBoostAt = stamp
	state.boostX2Until = math.max(state.boostX2Until, stamp + Config.StarterBoostSeconds)
	return true
end

--- Claims the daily streak reward. Streak resets if more than 48h were missed.
function ProgressionService.claimDaily(player: Player): (boolean, string?)
	local state = DataManager.get(player)
	if not state then
		return false, "Profile not loaded"
	end
	if not ProgressionService.dailyReady(state) then
		return false, "Already claimed today"
	end

	local missed = now() - state.dailyLastClaim
	if missed > 48 * 3600 then
		state.dailyStreak = 0
	end

	state.dailyStreak = state.dailyStreak % #Config.DailyTrack + 1
	state.dailyLastClaim = now()

	local reward = Config.DailyTrack[state.dailyStreak]
	ProgressionService.addAether(state, reward.aether or 0)
	if (reward.scrap or 0) > 0 then
		state.scrap += reward.scrap
	end
	if (reward.starMatter or 0) > 0 then
		state.starMatter += reward.starMatter
		state.runStarMatter += reward.starMatter
	end
	if (reward.cores or 0) > 0 then
		state.quantumCores += reward.cores
		state.lifetimeCores += reward.cores
	end

	DataManager.markDirty(player)
	Net.sendEvent(player, {
		kind = "daily",
		amount = reward.aether or 0,
		text = string.format("Day %d: %s", state.dailyStreak, reward.label or "Reward claimed"),
	})
	return true, nil
end

--- One-time onboarding payout. Server-authoritative and idempotent: the flag is
--- set before the grant, so a duplicated or replayed call cannot pay twice.
function ProgressionService.claimTutorial(player: Player): (boolean, string?)
	local state = DataManager.get(player)
	if not state then
		return false, "Profile not loaded"
	end
	if state.tutorialCompleted then
		-- Success, not failure: a rejoin re-fires this once when the client's guide
		-- collapses against an already-finished profile, and that is not an error.
		return true, nil
	end

	state.tutorialCompleted = true
	state.starMatter += Config.TutorialRewardStarMatter
	state.runStarMatter += Config.TutorialRewardStarMatter
	state.lifetimeStarMatter += Config.TutorialRewardStarMatter
	ProgressionService.addAether(state, Config.TutorialRewardAether)

	DataManager.markDirty(player)
	Funnel.log(player, "Tutorial_Done")
	Net.sendEvent(player, {
		kind = "toast",
		text = string.format(
			"Onboarding complete: +%d Star-Matter, +%d Aether",
			Config.TutorialRewardStarMatter,
			Config.TutorialRewardAether
		),
	})
	return true, nil
end

--- Playtime milestone gifts. Idempotent per milestone via claimedMilestones.
function ProgressionService.checkPlaytime(state: Types.ProfileState): number?
	for _, seconds in Config.PlaytimeMilestones do
		if state.totalPlaytime >= seconds and not state.claimedMilestones[seconds] then
			state.claimedMilestones[seconds] = true
			local reward = math.floor(seconds / 60)
			ProgressionService.addAether(state, reward)
			return reward
		end
	end
	return nil
end

return ProgressionService
