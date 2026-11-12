--!strict
-- Global tuning surface. Everything a designer might touch lives here or in
-- BladeRegistry / TechTreeConfig / MonetizationConfig. Services read, never own.

local Config = {}

Config.GameName = "Quantum Forge"
Config.Version = "0.1.0"
-- Off for anything that ships. Turns on the boot/handshake/tutorial traces.
Config.Debug = false

-- Network & persistence cadence
Config.SyncHz = 10 -- server -> client state pushes per second
Config.SaveInterval = 30 -- seconds between autosaves
Config.ClickRateLimit = 25 -- max accepted clicks per second, per player

-- ---------------------------------------------------------------------------
-- Forge / heat
-- ---------------------------------------------------------------------------

-- A click adds heat; heat decays every frame. Sustained clicking climbs the
-- gauge, letting go drops it. That tension IS the active loop.
Config.HeatPerClick = 2.5
Config.HeatDecayPerSec = 5

-- Sweet spot: the band you are trying to hold.
Config.SweetSpotMin = 65
Config.SweetSpotMax = 85
Config.SweetSpotMultiplier = 2.5

-- Above this the gauge turns hostile and venting becomes legal. The core caps
-- here; it never locks the anvil. A clicker that stops accepting clicks is the
-- fastest way to lose a player who was enjoying the loop.
Config.VentThreshold = 85
Config.OverheatAt = 100

-- The lean point. Past this the core runs hot and every strike pays half until
-- the player purges. A yield penalty keeps heat relevant without ever taking the
-- anvil away, which is what a lockout did.
Config.PenaltyFrom = 90
Config.PenaltyMult = 0.5

-- Aether Shards paid out when venting, per point of heat released.
Config.AetherPerHeat = 0.08

-- ---------------------------------------------------------------------------
-- Forge Overdrive
-- ---------------------------------------------------------------------------
-- Ten clean strikes in the band, in a row, open a short window where every hit
-- pays double. A miss or a burn-out breaks the streak: the reward is for
-- precision, not for holding the mouse down. This is separate from the paid
-- `overdriveUntil` boost, which is a stacking paid multiplier capped at an hour.
Config.StreakForOverdrive = 10
Config.OverdriveSeconds = 15
Config.OverdriveMultiplier = 2

-- ---------------------------------------------------------------------------
-- Critical strikes
-- ---------------------------------------------------------------------------
-- Every blade can crit without a tech node. The base chance sits in line with
-- the anomaly rate: rare enough to stay a surprise, common enough that the gold
-- ring reads as part of the loop instead of a once-a-session event.
Config.BaseCritChance = 0.05

-- ---------------------------------------------------------------------------
-- Anomalies
-- ---------------------------------------------------------------------------
-- Void Shards are the only currency earned from risk. They only drop when the
-- gauge is genuinely hot, and Overdrive doubles the odds: the mechanic rewards
-- living in the top of the band instead of bouncing off it.
Config.AnomalyChance = 0.06
Config.AnomalyChanceOverdrive = 0.18
Config.AnomalyHeatFloor = 55
Config.AnomalyShards = 2

-- ---------------------------------------------------------------------------
-- Economy
-- ---------------------------------------------------------------------------

Config.BaseClickYield = 1

--- Hard ceiling on forged copies. The vault is a room, not a warehouse: at the
--- ceiling the forge refuses the roll instead of letting the grid grow without a
--- bound, and the counter in the vault header says why.
Config.InventoryMax = 60

-- ---------------------------------------------------------------------------
-- Progress pricing
-- ---------------------------------------------------------------------------
-- Prices have to scale with the account, not only with the run. A player holding
-- a 500M blade multiplier earns in seconds what the old fixed table was built to
-- cost in hours, so a flat price is a free purchase and the ladder stops being a
-- ladder.
--
-- The reference is lifetime Star-Matter: monotonic, survives ascension, and it is
-- the number that actually grew. The square root keeps the first ten million
-- almost free and stops the curve from running away from a fresh account.
Config.ProgressReference = 1e9
Config.ProgressExponent = 0.5
Config.ProgressCap = 1e4

--- Multiplier applied to the Star-Matter sinks (crate rolls). 1 below the
--- reference, then `(lifetime / reference) ^ 0.5` up to the cap.
function Config.progressScale(lifetimeStarMatter: number): number
	local safe = math.max(0, lifetimeStarMatter or 0)
	local ratio = safe / Config.ProgressReference
	if ratio <= 1 then
		return 1
	end
	return math.min(ratio ^ Config.ProgressExponent, Config.ProgressCap)
end

--- The crate price, blended by how much of the account's lifetime total this run
--- has actually re-earned.
---
--- The bug this exists for: after an ascension `runStarMatter` is 0 while lifetime
--- stays at 1e18, so the top crate priced a roll at 4e8 x 1e4 = 4e12 (4T) the
--- instant the player was reset to zero. That is not a difficulty curve, it is a
--- locked door with the key on the other side. Blending the progress multiplier by
--- the run's share keeps the first rolls of a fresh run at base price and brings
--- the account tax back only as the run genuinely earns its way back.
function Config.runScale(runStarMatter: number, lifetimeStarMatter: number): number
	local lifetime = math.max(0, lifetimeStarMatter or 0)
	if lifetime <= 0 then
		return 1
	end
	local progress = Config.progressScale(lifetime)
	if progress <= 1 then
		return 1
	end
	local share = math.clamp(math.max(0, runStarMatter or 0) / lifetime, 0, 1)
	return 1 + (progress - 1) * share
end

-- ---------------------------------------------------------------------------
-- First-minute flourish
-- ---------------------------------------------------------------------------
-- The first handful of strikes pay a multiple. A new player's first click has
-- to feel like the game is already impressed with them; 1 Star-Matter does not.
-- The gate is lifetime Star-Matter, not a timer, so it lands inside the first
-- minute of actual play and never returns after an ascension.
Config.WowMomentCap = 60
Config.WowMomentMultiplier = 5

-- Fallback per-drone yield, before blade and tech multipliers. The live number
-- lives on each rung in `DroneRegistry`; this is only what the Fleet strip prints
-- before the first drone exists.
Config.BaseDroneYield = 0.6

-- Aether granted the first time a blade is forged, by rarity index.
Config.AetherOnForge = { 1, 2, 4, 8, 16 }

Config.AscendThreshold = 1e9
Config.AscendExponent = 0.5

Config.OfflineCapSeconds = 8 * 3600
Config.OfflineEfficiency = 0.5

-- ---------------------------------------------------------------------------
-- Expeditions
-- ---------------------------------------------------------------------------
-- Drones committed to a mission stop producing passive income while they are
-- away. See `ExpeditionConfig` for the mission table.
Config.ExpeditionSettleOnJoin = true
Config.FeedbackStore = "QuantumForge_Feedback"
Config.FeedbackMaxLength = 240

-- ---------------------------------------------------------------------------
-- Retention
-- ---------------------------------------------------------------------------
-- Playtime milestone gifts, in seconds -> reward table.
Config.PlaytimeMilestones = { 300, 900, 1800, 3600, 7200 }

-- Starter boost. Every brand-new profile gets one hour of double Star-Matter the
-- first time it loads, and a modal that says so. The multiplier itself is the
-- existing `boostX2Until` field, so this stacks with the passes exactly like the
-- paid Starter Forge Pack does instead of inventing a second boost path.
Config.StarterBoostSeconds = 3600

--- One day of the daily track.
export type DailyReward = {
	--- Always paid. Aether survives nothing, but it is the currency the run spends.
	aether: number,
	scrap: number?,
	starMatter: number?,
	--- Prestige currency. Only day seven carries it.
	cores: number?,
	--- One line naming the payout, used in the claim toast.
	label: string,
}

--- Seven-day daily track. A day is a record rather than one number because the
--- card has to show what it is paying: a day of Aether and a day of Aether plus
--- Star-Matter are the same slot in a flat table and different promises on
--- screen.
---
--- The numbers are deliberately absurd. Aether and Star-Matter are the two
--- currencies the run prints fastest, so a daily that pays a handful of either
--- reads as an insult next to a salvage cache or a single click. A daily should
--- be a reason to come back, not a rounding error: day one pays what a short
--- expedition used to, and day seven pays a top-tier drone.
---
--- Day 7 pays Cores, which is the only reward in the track that survives a
--- prestige. That is deliberate: the last card has to be worth waiting a week
--- for, and a week of Aether is not.
Config.DailyTrack = {
	{ aether = 10000, scrap = 250, label = "Aether and Scrap" },
	{ aether = 25000, scrap = 500, label = "Aether and Scrap" },
	{ aether = 60000, scrap = 750, label = "Aether and Scrap" },
	{ aether = 150000, scrap = 1000, starMatter = 250000, label = "Aether, Scrap and Star-Matter" },
	{ aether = 350000, scrap = 1500, starMatter = 1000000, label = "Aether, Scrap and Star-Matter" },
	{ aether = 800000, scrap = 2000, starMatter = 5000000, label = "Aether, Scrap and Star-Matter" },
	{ aether = 2500000, scrap = 3000, starMatter = 25000000, cores = 3, label = "The week: Cores, Aether, Scrap and Star-Matter" },
} :: { DailyReward }

-- Granted once, the first time a player finishes the guided onboarding. Sized to
-- be felt (a couple of blades and two drones) without skipping the first hour.
Config.TutorialRewardStarMatter = 250
Config.TutorialRewardAether = 10

-- ---------------------------------------------------------------------------
-- Uploaded blade meshes. The server loads them into this folder at boot; the
-- client clones them into its viewport. Absent folder or absent child = build
-- the blade from primitives instead, which is why the game runs with zero
-- uploads.
-- ---------------------------------------------------------------------------
Config.MeshFolder = "BladeModels"

-- ---------------------------------------------------------------------------
-- LihFolk sky. Off by default, and not because of taste.
--
-- The six faces are staged, uploaded and mapped in `AssetManifest.LihFolkSky`,
-- and `LobbyService.applySky` will frame them the moment this flips. What has
-- not been proven is that a `Sky` draws them: with Image ids the faces preload
-- with `Enum.AssetFetchStatus.Success` and the renderer draws a black dome;
-- with Decal ids the engine logs "Asset type does not match requested type" and
-- falls back to the default sky. Until a face renders, the procedural night
-- lighting above stays and the bridge looks the way it did before the pack.
-- ---------------------------------------------------------------------------
Config.UseLihFolkSky = false

-- ---------------------------------------------------------------------------
-- Remotes. Server creates these at boot; clients wait, never assume order.
-- ---------------------------------------------------------------------------
Config.Remotes = {
	Action = "RemoteEvent", -- client -> server intents
	StateSync = "RemoteEvent", -- server -> client batched state
	Event = "RemoteEvent", -- server -> client one-shot feedback (juice, toasts)
	RequestState = "RemoteFunction", -- client boot handshake
}

return Config
