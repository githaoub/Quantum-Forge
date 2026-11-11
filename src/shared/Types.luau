--!strict
-- Shared state shapes. The single definition of what a profile looks like, so
-- server persistence and client rendering cannot disagree about field names.

local Types = {}

export type TechLevels = { [string]: number }
export type OwnedBlades = { [string]: boolean }
export type MasteryCounts = { [string]: number }
export type RuneCounts = { [string]: number }

--- One forged copy. `uid` is the map key, so two Rusted Cleavers are two entries
--- and a trade can move exactly one of them.
---
--- `element`, `grade`, `prefix` and `suffix` are the collection axes from
--- `ModifierConfig`. They are optional on the wire because schema-6 saves predate
--- them; the server fills defaults at load and stamps every new roll.
export type BladeInstance = {
	id: string,
	variant: string,
	forgedAt: number,
	element: string?,
	grade: string?,
	prefix: string?,
	suffix: string?,
}

--- The wire form of a copy. Only the fields a vault row needs: the inventory is
--- fetched in one shot, not per tick, so it can afford to be readable.
export type InvEntry = {
	uid: string,
	id: string,
	variant: string,
	--- Unix time the copy was forged. Optional because profiles migrated from
	--- schema 3 have no stamp, and the drawer prints "unknown" rather than
	--- "56 years ago" for those.
	forgedAt: number?,
	--- Modifier axes. Missing on a legacy copy, never missing on a fresh roll.
	element: string?,
	grade: string?,
	prefix: string?,
	suffix: string?,
}

--- One rung of the drone ladder, as the client sees it this tick. `cost` is the
--- price of the next copy; `bulk` is the price of the next ten so BUILD 10 can
--- print a real number without duplicating the geometric series client side.
export type FleetEntry = {
	id: string,
	owned: number,
	cost: number,
	bulk: number,
	--- False while the tier is still gated on total drones owned.
	unlocked: boolean,
	--- Total drones needed to open this tier. 0 for the first rung.
	unlockAt: number,
}

--- Client-side preferences. Server-persisted so a mute survives a rejoin.
export type Settings = {
	sfx: boolean,
	vfx: boolean,
	shake: boolean,
	--- Accept trade requests from other players. Off answers `ASK` with
	--- "Unavailable for trade" on the requester's screen and refuses a request
	--- that arrives by any other route.
	trades: boolean,
}


--- One blade's socket rack. Array of rune ids, index = slot. An empty string is
--- an empty slot, so the rack length is the unlocked slot count and serialises
--- without holes.
export type SocketRack = { string }

--- A mission in flight. Flat fields rather than an optional table: the save
--- reconciler deep-fills against defaults, and a nil table is the one shape it
--- cannot reason about. `id == ""` means "no expedition".
export type ExpeditionState = {
	id: string,
	squad: number,
	startedAt: number,
	endsAt: number,
	-- Snapshot of the payout at dispatch, already scaled.
	aether: number,
	cores: number,
	shards: number,
}

--- One cache on the rack. `readyAt == 0` means sealed (not cracking yet);
--- otherwise it is the unix second the crack finishes. A cache is only
--- claimable once `readyAt > 0` and the clock has passed it.
export type CacheState = {
	rarity: string,
	readyAt: number,
	droppedAt: number,
}

--- The per-tick view of a cache. `secondsLeft` is 0 once it is claimable.
export type SyncCache = {
	rarity: string,
	readyAt: number,
	secondsLeft: number,
}

--- Persisted player data. Anything a player would be upset to lose belongs
--- here and must survive a schema migration in DataManager.
export type ProfileState = {
	version: number,

	-- Currency
	starMatter: number,
	runStarMatter: number, -- earned since the last ascension; drives the QC payout
	lifetimeStarMatter: number,
	aether: number,
	quantumCores: number,
	voidShards: number,

	-- Forge
	heat: number,
	lockUntil: number, -- os.clock() domain is local; stored as a timestamp offset
	--- Every forged copy, keyed by uid. Two copies of the same blade coexist.
	blades: { [string]: BladeInstance },
	equippedBlade: string,
	--- uid of the equipped copy. The id above stays the mastery/socket key, so a
	--- Prismatic Rusted Cleaver shares mastery with a Standard one.
	equippedUid: string,
	--- Rolls since the last Void or Quantum. Reset by a pity hit.
	forgePity: number,
	--- Duplicate currency. Melted copies pay it; variant rerolls spend it.
	scrap: number,
	--- Monotonic inventory revision. The per-tick payload carries only this number,
	--- and the client refetches the copy list when it changes.
	invVersion: number,
	--- Copies the player has protected by uid. A favorite is never melted, and the
	--- set survives an ascension because it is a preference, not an asset.
	favorites: { [string]: boolean },
	--- Rolls taken at `forgeRollTier`. Drives the scaling roll price; reset when
	--- the banner changes, because the new banner starts a fresh ramp.
	forgeRolls: number,
	--- Banner index the roll counter belongs to.
	forgeRollTier: number,
	--- Crate id the roll counter belongs to. Empty means "whatever lifetime has
	--- opened", which is what a pre-crate save migrates into.
	forgeCrate: string,
	--- Unix stamp of the one-time welcome boost. Zero means it was never granted.
	starterBoostAt: number,
	--- Drones owned per tier id. A missing key is zero; the ladder is unbounded,
	--- so this is a map rather than a fixed record.
	fleet: { [string]: number },
	streak: number,
	forgeOverdriveUntil: number,

	-- Mastery and runes. Mastery survives an ascension; blades do not, so a
	-- mastered blade comes back mastered when it is re-forged.
	mastery: MasteryCounts,
	runes: RuneCounts,
	sockets: { [string]: SocketRack },

	-- Fleet
	expedition: ExpeditionState,

	-- Salvage. The meter fills on accepted strikes; a full meter drops one cache
	-- of rolled rarity. `sigils` is a set of owned codex pieces, not a count.
	cacheMeter: number,
	caches: { CacheState },
	sigils: { [string]: boolean },

	--- Discovery index. Keys are namespaced (`blade:`, `variant:`, `element:`,
	--- `grade:`, `prefix:`, `suffix:`) and the value is always true. A set rather
	--- than a count because the codex asks "seen or not" per cell, never "how
	--- many". Survives ascension and melting on purpose: the codex is a record of
	--- the account, not of the current vault.
	codex: { [string]: boolean },
	--- Bumped only when a new key lands, so the client refetches the codex on a
	--- discovery instead of on every tick. Same pattern as `invVersion`.
	codexVersion: number,

	-- Lifetime collection counters. `aether` and `quantumCores` are spendable and
	-- reset on ascension; the leaderboards need totals that never go down.
	lifetimeAether: number,
	lifetimeCores: number,

	-- Meta
	ascensions: number,
	tech: TechLevels,
	passes: { [string]: boolean },

	--- Player preferences. Persisted so mute and juice settings survive a rejoin.
	settings: Settings,

	-- Boosts (unix seconds; 0 means inactive)
	boostX2Until: number,
	overdriveUntil: number,

	-- Onboarding
	tutorialCompleted: boolean,
	--- True once the first-join guide has been finished or skipped. Auto-start
	--- reads this, so the guide never force-opens on a later session.
	guideSeen: boolean,

	-- Retention
	dailyStreak: number,
	dailyLastClaim: number,
	claimedMilestones: { [number]: boolean },
	lastSeen: number,
	totalPlaytime: number,
}

--- What the server sends each sync tick. Deliberately flat and small: this goes
--- out at 10Hz, so every field costs bandwidth multiplied by player count.
export type CrateQuote = {
	--- Price of the next single roll on this crate.
	one: number,
	--- Price of the next ten, ramp included.
	ten: number,
}

export type SyncPayload = {
	sm: number,
	as: number,
	qc: number,
	heat: number,
	locked: boolean,
	lockRemaining: number,
	drones: number,
	--- The whole ladder this tick: one entry per tier, ordered, counts and
	--- prices included. Five small tables at 10Hz, which costs less than the
	--- client recomputing a geometric series for each button.
	fleet: { FleetEntry },
	equipped: string,
	--- uid of the equipped copy. Empty on a legacy payload.
	equippedUid: string,
	--- Variant id of the equipped copy. Drives the blade tint and the row chip.
	equippedVariant: string,
	--- Modifier axes of the equipped copy. Drive the blade tint and the forge
	--- banner's condition line; empty strings on a legacy payload.
	equippedElement: string,
	equippedGrade: string,
	equippedPrefix: string,
	equippedSuffix: string,
	--- Distinct blade ids owned. Kept for views that only need "do I own this
	--- pattern"; the per-copy list arrives through `StateStore.inventory`.
	owned: { string },
	--- Inventory revision. The client refetches the list when this changes.
	invVersion: number,
	invCount: number,
	--- Codex revision. Bumped when a new blade, variant, element, grade or affix
	--- is discovered; the client refetches the discovery set when it moves.
	codexVersion: number,
	--- Ceiling on forged copies, so the vault header and the forge agree.
	invMax: number,
	--- Protected uids, as a set. The vault reads it for the FAVORITES filter and
	--- the melt guards; sixty booleans is cheaper than refetching the list.
	favorites: { [string]: boolean },
	--- Rolls taken at the current banner. The roll price ramps with this.
	forgeRolls: number,
	tech: { [string]: number },
	ascensions: number,
	clickYield: number,
	passiveYield: number,
	mult: number,
	bandMin: number,
	bandMax: number,
	bandMult: number,
	inSweetSpot: boolean,
	--- Skill Overdrive (streak reward), seconds remaining. 0 when idle.
	overdriveRemaining: number,
	--- Paid 3x boost, seconds remaining.
	boostRemaining: number,
	--- Consecutive in-band strikes, and how many are needed.
	streak: number,
	streakGoal: number,
	--- Anomaly currency.
	shards: number,
	--- Equipped blade's mastery: rank, strikes banked, strikes for the next rank.
	mastery: number,
	masteryXp: number,
	masteryNext: number?,
	--- Strikes per blade id. The vault's inspector shows mastery for the copy it
	--- is looking at, not only the equipped one; twenty-five small numbers.
	masteryAll: MasteryCounts,
	--- Equipped blade's socket rack and how many slots its rank unlocks.
	equippedSockets: SocketRack,
	socketSlots: number,
	runes: RuneCounts,
	--- Mission in flight. `expId == ""` means idle.
	expId: string,
	expSquad: number,
	expRemaining: number,
	expAether: number,
	expCores: number,
	expShards: number,
	squadAway: number,
	--- Salvage rack. The client renders slot N from entry N; the array is never
	--- longer than `SalvageConfig.MaxCaches`.
	cacheMeter: number,
	cacheGoal: number,
	caches: { SyncCache },
	--- Owned sigil ids and how many of the four sets are complete.
	sigils: { [string]: boolean },
	codexSets: number,
	--- Ascension progress for the objective strip and the final lesson.
	runSm: number,
	ascendAt: number,
	dailyReady: boolean,
	dailyStreak: number,
	--- Unix stamp of the one-time welcome boost. Zero means never granted.
	starterBoostAt: number,
	tutorialCompleted: boolean,
	--- True once the guide has been finished or skipped. The client only
	--- auto-starts the guide when this is false.
	guideSeen: boolean,
	--- Forge banner: current tier and its price. `nextBlade` survives as the
	--- cheapest blade of the tier so the guide can name a target.
	nextBlade: string?,
	nextBladeCost: number?,
	forgeTier: number,
	forgeTierName: string,
	--- Crate the player is rolling. Empty on a fresh payload until the first roll
	--- or the first crate pick.
	forgeCrate: string,
	forgeCost: number,
	--- Price per unlocked crate, keyed by crate id. Absent means locked.
	forgeCosts: { [string]: CrateQuote },
	forgePity: number,
	forgePityGoal: number,
	scrap: number,
	settings: Settings,
	--- Price of the next copy of the selected tier. Kept for the HUD and the
	--- guide, which only care whether a drone is affordable right now.
	droneCost: number,
	--- Tier id that price belongs to, so the guide can name it.
	droneTier: string,
}

export type ActionResult = {
	ok: boolean,
	reason: string?,
}

--- One-shot client feedback. `kind` drives which juice effect the client plays.
export type FeedEvent = {
	kind: string, -- "forge" | "forged" | "crit" | "vent" | "overheat" | "purchase" | "ascend" | "toast" | "offline" | "locked"
	amount: number?,
	crit: boolean?,
	text: string?,
	seconds: number?,
	--- Blade id for `forged`, so the client can showcase the exact model that
	--- was just paid for instead of guessing from the next sync.
	blade: string?,
	--- Variant id for `forged`. Drives the rarity wash and the result chime.
	variant: string?,
	--- Modifier axes for `forged` and `trade`, so the reveal can name the whole
	--- copy without waiting for the inventory refetch.
	element: string?,
	grade: string?,
	prefix: string?,
	suffix: string?,
	--- How many copies the event describes. A ten-pull reports the best copy and
	--- a batch count, so the reveal can say `x10` instead of pretending the other
	--- nine did not happen.
	batch: number?,
	--- Crate id the copies came from. The reveal and the funnel both want to name
	--- the pool, not just the blade.
	crate: string?,
}

return Types
