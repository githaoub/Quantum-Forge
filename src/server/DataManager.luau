--!strict
-- Persistence with session locking.
--
-- ProfileService is the usual answer, but it is a Wally dependency we do not
-- have and it brings its own lifecycle model. This implements the part that
-- matters: an atomic UpdateAsync acquire that refuses to hand out a profile
-- another server is actively mutating, retry with backoff, autosave, and a
-- BindToClose flush.
--
-- In Studio without API access the DataStore calls fail; the manager falls back
-- to an in-memory store so the game is playable out of the box. It warns once.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local BladeRegistry = require(Shared:WaitForChild("BladeRegistry"))
local DroneRegistry = require(Shared:WaitForChild("DroneRegistry"))
local ExpeditionConfig = require(Shared:WaitForChild("ExpeditionConfig"))
local RuneConfig = require(Shared:WaitForChild("RuneConfig"))
local SalvageConfig = require(Shared:WaitForChild("SalvageConfig"))
local ForgeConfig = require(Shared:WaitForChild("ForgeConfig"))
local ModifierConfig = require(Shared:WaitForChild("ModifierConfig"))
local Types = require(Shared:WaitForChild("Types"))

local DataManager = {}

local SCHEMA_VERSION = 7
local LOCK_STALE_SECONDS = 60 -- a lock older than this is assumed abandoned
local MAX_ATTEMPTS = 4
local RETRY_BASE = 1.5

local STORE_NAME = "QuantumForge_Profiles_v1"

--- The starter copy's uid. Fixed rather than generated so a fresh profile and a
--- migrated profile both end up with the same key.
local STARTER_UID = "starter"

export type Profile = {
	state: Types.ProfileState,
	dirty: boolean,
	loadedAt: number,
	lastSaveAttempt: number,
}

local jobId = if game.JobId ~= "" then game.JobId else HttpService:GenerateGUID(false)

local store: DataStore? = nil
local mockMode = false
local mockStore: { [string]: any } = {}
local profiles: { [Player]: Profile } = {}
local shuttingDown = false

-- ---------------------------------------------------------------------------
-- Defaults & migration
-- ---------------------------------------------------------------------------

local function defaults(): Types.ProfileState
	return {
		version = SCHEMA_VERSION,

		starMatter = 0,
		runStarMatter = 0,
		lifetimeStarMatter = 0,
		aether = 0,
		quantumCores = 0,

		heat = 0,
		blades = {
			[STARTER_UID] = {
				id = BladeRegistry.StarterBlade,
				variant = ForgeConfig.StandardVariant,
				forgedAt = 0,
			},
		},
		equippedBlade = BladeRegistry.StarterBlade,
		equippedUid = STARTER_UID,
		forgePity = 0,
		scrap = 0,
		invVersion = 1,
		favorites = {},
		forgeRolls = 0,
		forgeRollTier = 0,
		forgeCrate = "",
		fleet = {},
		streak = 0,
		forgeOverdriveUntil = 0,
		voidShards = 0,

		mastery = {},
		runes = {},
		sockets = {},

		expedition = {
			id = "",
			squad = 0,
			startedAt = 0,
			endsAt = 0,
			aether = 0,
			cores = 0,
			shards = 0,
		},

		cacheMeter = 0,
		caches = {},
		sigils = {},

		codex = {},
		codexVersion = 1,
		lifetimeAether = 0,
		lifetimeCores = 0,

		ascensions = 0,
		tech = {},
		passes = {},

		settings = { sfx = true, music = true, vfx = true, shake = true, trades = true },

		boostX2Until = 0,
		overdriveUntil = 0,
		starterBoostAt = 0,

		tutorialCompleted = false,
		guideSeen = false,

		dailyStreak = 0,
		dailyLastClaim = 0,
		claimedMilestones = {},
		lastSeen = os.time(),
		totalPlaytime = 0,
	}
end

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

--- Counters keyed by id: mastery strikes, rune inventory. Anything that is not a
--- positive finite number is dropped rather than coerced, so a corrupted entry
--- disappears instead of becoming a free rune.
local function sanitiseCounts(raw: any): { [string]: number }
	local out: { [string]: number } = {}
	if type(raw) ~= "table" then
		return out
	end
	for key, value in raw do
		if type(key) ~= "string" or not isFiniteNumber(value) then
			continue
		end
		local count = math.floor(value)
		if count > 0 then
			out[key] = count
		end
	end
	return out
end

--- Favorites: a set of uids that still exist. A stale uid is dropped, because a
--- favorite pointing at a melted copy is a permanent phantom in the filter and a
--- permanent protection on nothing.
local function sanitiseFavorites(raw: any, blades: { [string]: Types.BladeInstance }): { [string]: boolean }
	local out: { [string]: boolean } = {}
	if type(raw) ~= "table" then
		return out
	end
	for uid, flag in raw do
		if type(uid) == "string" and flag == true and blades[uid] ~= nil then
			out[uid] = true
		end
	end
	return out
end

--- Socket racks: one array per owned blade, valid rune ids only, no more slots
--- than the mastery cap. Empty strings are padded in so a rack is always dense.
local function sanitiseSockets(raw: any): { [string]: Types.SocketRack }
	local out: { [string]: Types.SocketRack } = {}
	if type(raw) ~= "table" then
		return out
	end
	for bladeId, rack in raw do
		if type(bladeId) ~= "string" or type(rack) ~= "table" or BladeRegistry.get(bladeId) == nil then
			continue
		end
		local clean: Types.SocketRack = {}
		for index = 1, RuneConfig.MaxSockets do
			local id = rack[index]
			clean[index] = if type(id) == "string" and RuneConfig.get(id) ~= nil then id else ""
		end
		out[bladeId] = clean
	end
	return out
end

local function sanitiseExpedition(raw: any): Types.ExpeditionState
	local empty: Types.ExpeditionState = {
		id = "",
		squad = 0,
		startedAt = 0,
		endsAt = 0,
		aether = 0,
		cores = 0,
		shards = 0,
	}
	if type(raw) ~= "table" then
		return empty
	end
	local mission = if type(raw.id) == "string" then ExpeditionConfig.get(raw.id) else nil
	if mission == nil or not isFiniteNumber(raw.endsAt) or raw.endsAt <= 0 then
		return empty
	end
	return {
		id = mission.id,
		squad = math.clamp(math.floor(if isFiniteNumber(raw.squad) then raw.squad else mission.squad), 0, DroneRegistry.SaneMax),
		startedAt = math.max(0, if isFiniteNumber(raw.startedAt) then raw.startedAt else 0),
		endsAt = math.max(0, raw.endsAt),
		aether = math.max(0, if isFiniteNumber(raw.aether) then raw.aether else 0),
		cores = math.max(0, math.floor(if isFiniteNumber(raw.cores) then raw.cores else 0)),
		shards = math.max(0, math.floor(if isFiniteNumber(raw.shards) then raw.shards else 0)),
	}
end

--- Salvage rack: dense array, known rarities only, no more than the rack holds.
--- A cache with a garbage rarity is dropped rather than re-rolled, because a
--- free re-roll on a corrupted save is a free upgrade.
local function sanitiseCaches(raw: any): { Types.CacheState }
	local out: { Types.CacheState } = {}
	if type(raw) ~= "table" then
		return out
	end
	for index = 1, SalvageConfig.MaxCaches do
		local entry = raw[index]
		if type(entry) ~= "table" then
			continue
		end
		local rarity = if type(entry.rarity) == "string" then SalvageConfig.getRarity(entry.rarity) else nil
		if rarity == nil then
			continue
		end
		out[#out + 1] = {
			rarity = rarity.id,
			readyAt = math.max(0, if isFiniteNumber(entry.readyAt) then entry.readyAt else 0),
			droppedAt = math.max(0, if isFiniteNumber(entry.droppedAt) then entry.droppedAt else 0),
		}
	end
	return out
end

--- Owned sigils: a set of known ids. Anything else is dropped.
local function sanitiseSigils(raw: any): { [string]: boolean }
	local out: { [string]: boolean } = {}
	if type(raw) ~= "table" then
		return out
	end
	for key, value in raw do
		if type(key) == "string" and value == true and SalvageConfig.getSigil(key) ~= nil then
			out[key] = true
		end
	end
	return out
end

--- Copies: uid -> { id, variant, forgedAt }. Handles the schema-3 shape, where
--- `blades` was a set of blade ids, by minting one Standard copy per owned id.
--- A boolean is not a copy, so it is translated rather than dropped: a player who
--- owned twenty-five blades keeps all twenty-five.
local function sanitiseBlades(raw: any): { [string]: Types.BladeInstance }
	local out: { [string]: Types.BladeInstance } = {}
	if type(raw) ~= "table" then
		return out
	end
	local minted = 0
	for key, value in raw do
		if type(key) ~= "string" then
			continue
		end
		if type(value) == "boolean" then
			if value and BladeRegistry.get(key) ~= nil then
				minted += 1
				local uid = if key == BladeRegistry.StarterBlade
					then STARTER_UID
					else string.format("legacy_%d_%s", minted, key)
				out[uid] = { id = key, variant = ForgeConfig.StandardVariant, forgedAt = 0 }
			end
		elseif type(value) == "table" and type(value.id) == "string" then
			if BladeRegistry.get(value.id) == nil then
				continue
			end
			local variant = if type(value.variant) == "string" and ForgeConfig.hasVariant(value.variant)
				then value.variant
				else ForgeConfig.StandardVariant
			out[key] = {
				id = value.id,
				variant = variant,
				forgedAt = math.max(0, if isFiniteNumber(value.forgedAt) then value.forgedAt else 0),
				-- Modifier axes are optional by design: a schema-6 copy has none,
				-- and inventing one would silently change its power.
				element = if ModifierConfig.hasElement(value.element) then value.element else nil,
				grade = if ModifierConfig.hasGrade(value.grade) then value.grade else nil,
				prefix = if ModifierConfig.hasPrefix(value.prefix) then value.prefix else "",
				suffix = if ModifierConfig.hasSuffix(value.suffix) then value.suffix else "",
			}
		end
	end
	return out
end

local function sanitiseSettings(raw: any): Types.Settings
	local fallback: Types.Settings = { sfx = true, music = true, vfx = true, shake = true, trades = true }
	if type(raw) ~= "table" then
		return fallback
	end
	return {
		sfx = if type(raw.sfx) == "boolean" then raw.sfx else true,
		-- Music was folded into the SFX switch before it had a row of its own.
		-- An old save with sound effects muted should not come back with the loop
		-- playing, so inherit that value once; after this the two are independent.
		music = if type(raw.music) == "boolean"
			then raw.music
			elseif type(raw.sfx) == "boolean" then raw.sfx
			else true,
		vfx = if type(raw.vfx) == "boolean" then raw.vfx else true,
		shake = if type(raw.shake) == "boolean" then raw.shake else true,
		-- A save written before the toggle existed has no key, and the honest
		-- default for that player is the one the feature shipped with: on.
		trades = if type(raw.trades) == "boolean" then raw.trades else true,
	}
end

--- Discovery index. Keys are namespaced strings, values are true. Unknown
--- namespaces are dropped so a hand-edited save cannot grow the set without a
--- bound; the four known namespaces are validated against their configs.
local function sanitiseCodex(raw: any): { [string]: boolean }
	local out: { [string]: boolean } = {}
	if type(raw) ~= "table" then
		return out
	end
	local count = 0
	for key, flag in raw do
		if flag ~= true or type(key) ~= "string" then
			continue
		end
		local namespace, id = string.match(key, "^(%a+):(.+)$")
		local valid = false
		if namespace == "blade" then
			valid = BladeRegistry.get(id) ~= nil
		elseif namespace == "variant" then
			valid = ForgeConfig.hasVariant(id)
		elseif namespace == "element" then
			valid = ModifierConfig.hasElement(id)
		elseif namespace == "grade" then
			valid = ModifierConfig.hasGrade(id)
		elseif namespace == "prefix" then
			valid = ModifierConfig.hasPrefix(id)
		elseif namespace == "suffix" then
			valid = ModifierConfig.hasSuffix(id)
		elseif namespace == "quality" then
			valid = ModifierConfig.hasQuality(id)
		end
		if valid then
			out[key] = true
			count += 1
			if count >= 400 then
				break
			end
		end
	end
	return out
end

--- Drones owned per tier. Unknown tier ids are dropped, counts are floored and
--- clamped to a finite ceiling, so a hand-edited save cannot mint `inf` drones or
--- a tier the registry has never heard of.
local function sanitiseFleet(raw: any): { [string]: number }
	local out: { [string]: number } = {}
	if type(raw) ~= "table" then
		return out
	end
	for key, value in raw do
		if type(key) ~= "string" or DroneRegistry.get(key) == nil or not isFiniteNumber(value) then
			continue
		end
		local count = math.clamp(math.floor(value), 0, DroneRegistry.SaneMax)
		if count > 0 then
			out[key] = count
		end
	end
	return out
end

--- Deep-fills a saved table against defaults. New fields appear at default
--- values; extra fields are preserved so a rollback does not destroy data a
--- newer schema wrote.
local function reconcile(saved: any): Types.ProfileState
	local base = defaults()
	if type(saved) ~= "table" then
		return base
	end

	for key, default in base do
		if saved[key] == nil then
			continue
		end
		if type(default) == "table" then
			if type(saved[key]) == "table" then
				(base :: any)[key] = saved[key]
			end
		elseif type(default) == "number" then
			if isFiniteNumber(saved[key]) then
				(base :: any)[key] = saved[key]
			end
		elseif type(default) == type(saved[key]) then
			(base :: any)[key] = saved[key]
		end
	end

	-- Copies. A save from schema 3 has booleans here; `sanitiseBlades` mints one
	-- Standard copy per owned id so nothing is lost in the migration.
	base.blades = sanitiseBlades(base.blades)
	if next(base.blades) == nil then
		base.blades[STARTER_UID] = {
			id = BladeRegistry.StarterBlade,
			variant = ForgeConfig.StandardVariant,
			forgedAt = 0,
		}
	end

	-- Equipped pointer repair. The uid must exist and must still point at the
	-- blade id the mastery/socket systems key on; if either half is stale the
	-- strongest owned copy takes over.
	local equipped = if type(base.equippedUid) == "string" then base.blades[base.equippedUid] else nil
	if equipped == nil or equipped.id ~= base.equippedBlade then
		local bestUid: string? = nil
		local bestPower = -1
		for uid, instance in base.blades do
			local power = ForgeConfig.powerCopy(instance)
			if power > bestPower then
				bestPower = power
				bestUid = uid
			end
		end
		equipped = if bestUid then base.blades[bestUid] else nil
		base.equippedUid = bestUid or STARTER_UID
	end
	base.equippedBlade = if equipped then equipped.id else BladeRegistry.StarterBlade

	base.settings = sanitiseSettings(base.settings)
	base.forgePity = math.clamp(
		math.floor(if isFiniteNumber(base.forgePity) then base.forgePity else 0),
		0,
		40
	)
	base.scrap = math.max(0, math.floor(if isFiniteNumber(base.scrap) then base.scrap else 0))
	base.invVersion = math.max(1, math.floor(if isFiniteNumber(base.invVersion) then base.invVersion else 1))

	base.mastery = sanitiseCounts(base.mastery)
	base.favorites = sanitiseFavorites(base.favorites, base.blades)
	base.forgeRolls = math.clamp(
		math.floor(if isFiniteNumber(base.forgeRolls) then base.forgeRolls else 0),
		0,
		1000000
	)
	base.forgeRollTier = math.clamp(
		math.floor(if isFiniteNumber(base.forgeRollTier) then base.forgeRollTier else 0),
		0,
		#ForgeConfig.Tiers
	)
	-- An unknown crate id falls back to whatever lifetime has opened rather than
	-- to a specific tier: a save from before the crate rail has no id at all, and
	-- "the banner you can afford" is the only truthful default.
	base.forgeCrate = if type(base.forgeCrate) == "string" and ForgeConfig.crate(base.forgeCrate)
		then base.forgeCrate
		else ""
	base.starterBoostAt = math.max(0, if isFiniteNumber(base.starterBoostAt) then base.starterBoostAt else 0)
	base.runes = sanitiseCounts(base.runes)
	base.sockets = sanitiseSockets(base.sockets)
	base.expedition = sanitiseExpedition(base.expedition)
	base.caches = sanitiseCaches(base.caches)
	base.sigils = sanitiseSigils(base.sigils)
	base.codex = sanitiseCodex(base.codex)
	base.codexVersion = math.max(1, math.floor(if isFiniteNumber(base.codexVersion) then base.codexVersion else 1))
	base.lifetimeAether = math.max(0, if isFiniteNumber(base.lifetimeAether) then base.lifetimeAether else 0)
	base.lifetimeCores = math.max(0, if isFiniteNumber(base.lifetimeCores) then base.lifetimeCores else 0)
	base.cacheMeter = math.clamp(
		math.floor(if isFiniteNumber(base.cacheMeter) then base.cacheMeter else 0),
		0,
		SalvageConfig.StrikesPerCache
	)
	base.voidShards = math.max(0, math.floor(if isFiniteNumber(base.voidShards) then base.voidShards else 0))
	base.streak = math.clamp(if isFiniteNumber(base.streak) then base.streak else 0, 0, Config.StreakForOverdrive)
	base.forgeOverdriveUntil = math.max(0, if isFiniteNumber(base.forgeOverdriveUntil) then base.forgeOverdriveUntil else 0)

	base.heat = math.clamp(if isFiniteNumber(base.heat) then base.heat else 0, 0, Config.OverheatAt)

	-- Fleet. A pre-ladder save carries one flat `drones` count; those all migrate
	-- into the first rung so an existing player keeps every drone they paid for.
	-- The seed is read from `saved`, not from `base`, because `drones` is no
	-- longer a field on `ProfileState`.
	base.fleet = sanitiseFleet(base.fleet)
	if next(base.fleet) == nil and type(saved.drones) == "number" and isFiniteNumber(saved.drones) then
		local legacy = math.clamp(math.floor(saved.drones), 0, DroneRegistry.SaneMax)
		if legacy > 0 then
			base.fleet[DroneRegistry.DefaultId] = legacy
		end
	end

	base.version = SCHEMA_VERSION
	return base
end

-- ---------------------------------------------------------------------------
-- DataStore plumbing (with mock fallback)
-- ---------------------------------------------------------------------------

local function keyFor(userId: number): string
	return string.format("player_%d", userId)
end

-- Written once per server, never read by the game. It exists purely so the very
-- first DataStore call is a real round-trip instead of a handle allocation.
local PROBE_KEY = "__quantumforge_probe"

local function attempt<T>(fn: () -> T): (boolean, T?)
	local ok, result = pcall(fn)
	if ok then
		return true, result :: T
	end
	warn(string.format("[DataManager] DataStore call failed: %s", tostring(result)))
	return false, nil
end

local function withRetry<T>(label: string, fn: () -> T): T?
	local delay = RETRY_BASE
	for try = 1, MAX_ATTEMPTS do
		local ok, result = attempt(fn)
		if ok then
			return result
		end
		if try < MAX_ATTEMPTS then
			warn(string.format("[DataManager] %s attempt %d/%d failed, retrying in %.1fs", label, try, MAX_ATTEMPTS, delay))
			task.wait(delay)
			delay *= 2
		end
	end
	return nil
end

--- Resolves the store handle, or nil for mock mode.
---
--- The probe is the whole point of this function. `GetDataStore` validates
--- nothing — it hands back a handle even when API access is switched off, and the
--- failure only surfaces on the first real call. This used to mean a Studio
--- playtest without "Enable Studio Access to API Services" spent all four retries
--- and 10.5 seconds of exponential backoff on *every join*, then kicked the
--- player. That window is what `LINKING…` was: a client waiting on a profile the
--- server had not given up on yet.
---
--- Auto-mocking is deliberately Studio-only. In production a throttle looks
--- exactly like a permission failure, and silently falling back to a store that
--- does not persist would destroy real saves. Production keeps its retries and
--- its kick.
local function getStore(): DataStore?
	if mockMode then
		return nil
	end
	if store then
		return store
	end

	-- `GetAsync` has no Luau-side timeout. In Studio an unauthenticated probe can
	-- hang for minutes, and because this runs inside a boot stage it took the
	-- whole server with it: bridge built, then no profile, no payload, no HUD.
	-- Five seconds is enough for a healthy probe and short enough that a dead
	-- one falls back before a player is waiting on it.
	local timeout = if RunService:IsStudio() then 5 else 20
	local finished = false
	local ok = false
	local result: any = nil

	task.spawn(function()
		ok, result = pcall(function()
			local ds = DataStoreService:GetDataStore(STORE_NAME)
			ds:GetAsync(PROBE_KEY)
			return ds
		end)
		finished = true
	end)

	local deadline = os.clock() + timeout
	while not finished and os.clock() < deadline do
		task.wait(0.05)
	end

	if not finished then
		if RunService:IsStudio() then
			mockMode = true
			warn("[DataManager] DataStore probe timed out in Studio: MOCK mode. Progress will NOT persist.")
		else
			warn("[DataManager] DataStore probe timed out; profile load will retry")
		end
		return nil
	end

	if ok and result ~= nil then
		store = result
		return store
	end

	if RunService:IsStudio() then
		mockMode = true
		warn("[DataManager] DataStore unreachable in Studio: MOCK mode. Expected when API services are off; progress will NOT persist.")
		return nil
	end

	warn(string.format("[DataManager] DataStore unreachable: %s", tostring(result)))
	return nil
end

--- Warms the store before the first player joins, so the probe cost is paid at
--- boot instead of on a player's join thread. Safe to call more than once.
function DataManager.init()
	getStore()
end

-- ---------------------------------------------------------------------------
-- Load / release
-- ---------------------------------------------------------------------------

--- Acquires the profile, taking the session lock. Returns nil only if every
--- retry failed, which the caller should treat as "kick the player".
function DataManager.load(player: Player): Types.ProfileState?
	local key = keyFor(player.UserId)
	local ds = getStore()

	if ds == nil then
		local saved = mockStore[key]
		local state = reconcile(saved)
		profiles[player] = { state = state, dirty = false, loadedAt = os.clock(), lastSaveAttempt = 0 }
		return state
	end

	local result = withRetry("load", function()
		return ds:UpdateAsync(key, function(old: any)
			local now = os.time()

			if old == nil then
				return {
					schema = SCHEMA_VERSION,
					data = defaults(),
					lock = { job = jobId, at = now },
				}
			end

			local lock = old.lock
			if type(lock) == "table" and lock.job ~= jobId and isFiniteNumber(lock.at) then
				if now - lock.at < LOCK_STALE_SECONDS then
					-- Abort the write; another server owns this profile right now.
					return nil
				end
			end

			return {
				schema = SCHEMA_VERSION,
				data = reconcile(old.data or old),
				lock = { job = jobId, at = now },
			}
		end)
	end)

	if result == nil then
		warn(string.format("[DataManager] could not acquire profile for %s (%d)", player.Name, player.UserId))
		return nil
	end

	local state = reconcile(result.data)
	profiles[player] = {
		state = state,
		dirty = false,
		loadedAt = os.clock(),
		lastSaveAttempt = 0,
	}
	return state
end

function DataManager.get(player: Player): Types.ProfileState?
	local profile = profiles[player]
	if not profile then
		return nil
	end
	return profile.state
end

--- Marks a profile for the next autosave. Cheap — called freely from services.
function DataManager.markDirty(player: Player)
	local profile = profiles[player]
	if profile then
		profile.dirty = true
	end
end

--- Writes one profile through, honouring the lock. Returns success.
function DataManager.save(player: Player): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	if shuttingDown then
		return false
	end

	profile.lastSaveAttempt = os.clock()
	local key = keyFor(player.UserId)
	local ds = getStore()
	local snapshot = profile.state

	if ds == nil then
		mockStore[key] = { schema = SCHEMA_VERSION, data = snapshot, lock = { job = jobId, at = os.time() } }
		profile.dirty = false
		return true
	end

	local result = withRetry("save", function()
		return ds:UpdateAsync(key, function(old: any)
			if old ~= nil and type(old.lock) == "table" and old.lock.job ~= jobId then
				-- Someone else took the lock while we were away. Do not clobber.
				warn(string.format("[DataManager] lock lost for %s; skipping write", player.Name))
				return nil
			end
			return {
				schema = SCHEMA_VERSION,
				data = snapshot,
				lock = { job = jobId, at = os.time() },
			}
		end)
	end)

	if result ~= nil then
		profile.dirty = false
		return true
	end
	return false
end

--- Writes the profile and drops the session lock.
---
--- Used by `release` on BOTH paths. The old code kept the lock during shutdown
--- "so a crash mid-close still recovers the data", but `UpdateAsync` is atomic:
--- if the server dies mid-call the write either lands whole or not at all, and
--- if it does not land the lock is still set and the staleness rule applies. So
--- keeping the lock bought no safety and cost every rejoin inside
--- `LOCK_STALE_SECONDS` a kick.
local function dropLock(key: string, state: Types.ProfileState)
	local ds = getStore()

	if ds == nil then
		mockStore[key] = { schema = SCHEMA_VERSION, data = state, lock = nil }
		return
	end

	withRetry("release", function()
		return ds:UpdateAsync(key, function(old: any)
			if old ~= nil and type(old.lock) == "table" and old.lock.job ~= jobId then
				-- Another server owns it now; do not clobber their data.
				return nil
			end
			return { schema = SCHEMA_VERSION, data = state, lock = nil }
		end)
	end)
end

--- Saves and drops the session lock so another server can take over instantly.
function DataManager.release(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end

	dropLock(keyFor(player.UserId), profile.state)
	profiles[player] = nil
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

--- Flushes every profile and drops its lock. BindToClose calls this.
---
--- `dropLock` rather than `save` on purpose: `save` writes `lock = { job, at }`,
--- so flushing and leaving the lock behind is what made every rejoin inside
--- `LOCK_STALE_SECONDS` fail. `PlayerRemoving` never runs on shutdown, so the
--- release path could not clean up afterwards either — the lock simply outlived
--- the server that owned it.
---
--- Snapshot first, then write: mutating `profiles` while iterating it is the
--- kind of thing that works until it does not.
function DataManager.shutdown()
	local pending: { [Player]: Types.ProfileState } = {}
	for player, profile in profiles do
		pending[player] = profile.state
	end

	for player, state in pending do
		dropLock(keyFor(player.UserId), state)
		profiles[player] = nil
	end

	shuttingDown = true
end

--- Starts the autosave heartbeat. Returns the connection so Main can stop it.
function DataManager.startAutosave(): RBXScriptConnection
	local accumulator = 0

	local connection = RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < Config.SaveInterval then
			return
		end
		accumulator = 0

		for player, profile in profiles do
			if player.Parent == nil then
				continue
			end
			-- Recently active profiles get written on the normal cadence; idle
			-- ones are skipped to save DataStore budget.
			if profile.dirty then
				DataManager.save(player)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		DataManager.release(player)
	end)

	return connection
end

--- Test seam: replaces the store with an in-memory fake. Only exposed so the
--- smoke test can run without API access.
function DataManager._setMockMode()
	mockMode = true
end

DataManager.SCHEMA_VERSION = SCHEMA_VERSION

return DataManager
