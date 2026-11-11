--!strict
-- Server bootstrap. Boot order is deliberate:
--   1. Net.init      — remotes must exist before any client boots or any
--                      service tries to fire.
--   2. Monetization  — connects ProcessReceipt and pass listeners.
--   3. DataManager   — starts autosave, attaches PlayerRemoving release.
--   4. PlayerAdded   — load profile, offline payout, register handlers.
--   5. Heartbeat     — the single clock driving forge physics and sync.
--
-- Services never talk to each other through globals; they each pull the profile
-- from DataManager. That keeps ordering bugs out of the economy.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))

local Net = require(script.Parent.Net)

-- Remotes before the heavy service modules are evaluated. The client boots in
-- parallel with this script, and every millisecond before the folder replicates
-- is a millisecond the HUD has no state to draw. Wrapped in pcall because this
-- now runs outside the staged boot: a throw here must not kill the script, and
-- the "remotes" stage below retries it.
local earlyOk, earlyErr = pcall(Net.init)
if not earlyOk then
	warn(string.format("[QuantumForge] early remote creation failed: %s", tostring(earlyErr)))
end

local DataManager = require(script.Parent.DataManager)
local ProgressionService = require(script.Parent.ProgressionService)
local ForgeService = require(script.Parent.ForgeService)
local FeedbackStore = require(script.Parent.FeedbackStore)
local Funnel = require(script.Parent.Funnel)
local MonetizationService = require(script.Parent.MonetizationService)
local LobbyService = require(script.Parent.LobbyService)
local MeshService = require(script.Parent.MeshService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local TradeService = require(script.Parent.TradeService)

local bootClock = os.clock()
local heartbeatConnection: RBXScriptConnection? = nil
local autosaveConnection: RBXScriptConnection? = nil
local shuttingDown = false

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function log(message: string)
	if Config.Debug then
		print(string.format("[QuantumForge] %s", message))
	end
end

--- Sends a rejection reason back to the client as a toast so a blocked purchase
--- is never silent.
local function reject(player: Player, reason: string?)
	if reason then
		Net.sendEvent(player, { kind = "toast", text = reason })
	end
end

-- ---------------------------------------------------------------------------
-- Player lifecycle
-- ---------------------------------------------------------------------------

local function onPlayerReady(player: Player)
	local state = DataManager.load(player)
	if state == nil then
		-- DataStore refused to hand over the profile after every retry. Letting
		-- them play would mean writing over someone else's session on save.
		player:Kick("Could not load your forge data. Please rejoin in a moment.")
		return
	end

	-- A mission that landed while they were away pays out before anything else
	-- reads the profile, so the first payload already shows the reward.
	if Config.ExpeditionSettleOnJoin then
		local landed = ProgressionService.settleExpedition(state)
		if landed then
			Net.sendEvent(player, {
				kind = "expedition",
				amount = landed.aether,
				text = string.format(
					"%s returned while you were away: +%s Aether",
					landed.id,
					tostring(math.floor(landed.aether))
				),
			})
		end
	end

	-- Offline earnings accrue before the first sync, so the modal has data.
	local offline = ForgeService.applyOffline(state)
	if offline.amount > 0 then
		log(string.format("%s returned after %ds: +%.0f SM offline", player.Name, offline.seconds, offline.amount))
		Net.sendEvent(player, {
			kind = "offline",
			amount = offline.amount,
			seconds = offline.seconds,
		})
	end

	-- Welcome boost. Before the first payload, so the HUD chip and the modal read
	-- the same remaining seconds the income formula is using.
	if ProgressionService.grantStarterBoost(state) then
		Net.sendEvent(player, {
			kind = "starter",
			seconds = Config.StarterBoostSeconds,
			text = string.format(
				"%s of double Star-Matter is live",
				if Config.StarterBoostSeconds >= 3600
					then string.format("%d hours", math.floor(Config.StarterBoostSeconds / 3600))
					else string.format("%d minutes", math.floor(Config.StarterBoostSeconds / 60))
			),
		})
	end

	DataManager.markDirty(player)

	-- A schema-6 vault predates the collection axes. Re-marking every owned copy
	-- fills the codex without asking the player to re-roll anything.
	ProgressionService.syncCodex(state)

	-- Hand the client its opening state immediately rather than waiting up to
	-- 100ms for the first tick. The HUD should never flash empty numbers.
	Net.setPayload(player, ProgressionService.buildPayload(state))
	Funnel.log(player, "Session_Start")
end

-- ---------------------------------------------------------------------------
-- Action registration
-- ---------------------------------------------------------------------------

local function registerActions()
	Net.onAction("click", function(player: Player): boolean
		local ok = ForgeService.click(player)
		return ok
	end)

	Net.onAction("vent", function(player: Player): boolean
		local ok, reason = ForgeService.vent(player, false)
		if not ok then
			reject(player, reason)
		end
		return ok
	end)

	Net.onAction("crate", function(player: Player, payload: unknown): boolean
		local id = if type(payload) == "string" then payload elseif type(payload) == "table" then (payload :: any).id else nil
		if type(id) ~= "string" then
			return false
		end
		local ok, reason = ProgressionService.selectCrate(player, id)
		if not ok then
			reject(player, reason)
			return false
		end
		local state = DataManager.get(player)
		if state then
			Net.setPayload(player, ProgressionService.buildPayload(state))
		end
		return true
	end)

	Net.onAction("forge", function(player: Player, payload: unknown): boolean
		-- The crate is named, not indexed: a catalogue reorder must never change
		-- what a client is buying. `count` is the ten-pull, clamped server-side.
		local crate: string? = nil
		local count = 1
		if type(payload) == "table" then
			local data = payload :: any
			if type(data.crate) == "string" then
				crate = data.crate
			end
			if type(data.count) == "number" then
				count = data.count
			end
		end
		local ok, reason = ProgressionService.forgeRoll(player, crate, count)
		if not ok then
			reject(player, reason)
			return false
		end
		-- Push the new balance on the same frame. The tick would land within a
		-- fifth of a second, but a roll that visibly does not move the counter
		-- is exactly the economy report, and "it syncs eventually" is not an
		-- answer to a player watching the number.
		local state = DataManager.get(player)
		if state then
			Net.setPayload(player, ProgressionService.buildPayload(state))
		end
		return true
	end)

	Net.onAction("equip", function(player: Player, payload: unknown): boolean
		local uid = if type(payload) == "table" then (payload :: any).uid else payload
		if type(uid) ~= "string" then
			return false
		end
		local ok, reason = ProgressionService.equipBlade(player, uid)
		if not ok then
			reject(player, reason)
		end
		return ok
	end)

	Net.onAction("salvage", function(player: Player, payload: unknown): boolean
		local uid = if type(payload) == "table" then (payload :: any).uid else payload
		if type(uid) ~= "string" then
			return false
		end
		local ok, reason = ProgressionService.salvageBlade(player, uid)
		if not ok then
			reject(player, reason)
		end
		return ok
	end)

	Net.onAction("salvageMany", function(player: Player, payload: unknown): boolean
		if type(payload) ~= "table" then
			return false
		end
		local uids = (payload :: any).uids
		if type(uids) ~= "table" then
			return false
		end
		local ok, reason = ProgressionService.salvageMany(player, uids)
		if not ok then
			reject(player, reason)
		end
		return ok
	end)

	Net.onAction("equipBest", function(player: Player): boolean
		local ok, reason = ProgressionService.equipBest(player)
		if not ok then
			reject(player, reason)
		end
		return ok
	end)

	Net.onAction("reroll", function(player: Player, payload: unknown): boolean
		local uid = if type(payload) == "table" then (payload :: any).uid else payload
		if type(uid) ~= "string" then
			return false
		end
		local ok, reason = ProgressionService.rerollVariant(player, uid)
		if not ok then
			reject(player, reason)
		end
		return ok
	end)

	Net.onAction("setting", function(player: Player, payload: unknown): boolean
		if type(payload) ~= "table" then
			return false
		end
		local data = payload :: any
		if type(data.key) ~= "string" or type(data.value) ~= "boolean" then
			return false
		end
		local ok, reason = ProgressionService.setSetting(player, data.key, data.value)
		if not ok then
			reject(player, reason)
		end
		return ok
	end)

	-- Protected copies. Takes the uid directly or as `{ uid = ... }`, because the
	-- vault sends the table shape and the guide seam sends the bare string.
	Net.onAction("favorite", function(player: Player, payload: unknown): boolean
		local uid = if type(payload) == "table" then (payload :: any).uid else payload
		if type(uid) ~= "string" then
			return false
		end
		local ok, reason = ProgressionService.setFavorite(player, uid)
		if not ok then
			reject(player, reason)
		end
		return ok
	end)

	Net.onAction("guideSeen", function(player: Player): boolean
		local ok, reason = ProgressionService.markGuideSeen(player)
		if not ok then
			reject(player, reason)
		end
		return ok
	end)

	-- Studio-only replay of the first join. Refuses in a live server so the
	-- tutorial reward cannot be farmed.
	Net.onAction("guideReset", function(player: Player): boolean
		if not RunService:IsStudio() then
			reject(player, "Studio only")
			return false
		end
		local ok, reason = ProgressionService.resetGuide(player)
		if not ok then
			reject(player, reason)
		end
		return ok
	end)

	Net.onAction("buyDrones", function(player: Player, payload: unknown): boolean
		-- The whole payload goes through: `{ id, count }` names a tier, a bare
		-- number means "the best unlocked tier". The service validates both,
		-- because a remote is a stranger.
		local ok, reason = ProgressionService.buyDrones(player, payload)
		if not ok then
			reject(player, reason)
		end
		return ok
	end)

	Net.onAction("buyTech", function(player: Player, payload: unknown): boolean
		local nodeId = if type(payload) == "table" then (payload :: any).id else payload
		if type(nodeId) ~= "string" then
			return false
		end
		local ok, reason = ProgressionService.buyTech(player, nodeId)
		if not ok then
			reject(player, reason)
		end
		return ok
	end)

	-- Expeditions
	Net.onAction("dispatch", function(player: Player, payload: unknown): boolean
		local missionId = if type(payload) == "table" then (payload :: any).id else payload
		if type(missionId) ~= "string" then
			return false
		end
		local ok, reason = ProgressionService.dispatch(player, missionId)
		if not ok then
			reject(player, reason)
		end
		return ok
	end)

	-- Runes
	Net.onAction("craftRune", function(player: Player, payload: unknown): boolean
		local runeId = if type(payload) == "table" then (payload :: any).id else payload
		if type(runeId) ~= "string" then
			return false
		end
		local ok, reason = ProgressionService.craftRune(player, runeId)
		if not ok then
			reject(player, reason)
		end
		return ok
	end)

	Net.onAction("socket", function(player: Player, payload: unknown): boolean
		if type(payload) ~= "table" then
			return false
		end
		local data = payload :: any
		if type(data.rune) ~= "string" then
			return false
		end
		local slot = if type(data.slot) == "number" then data.slot else nil
		local ok, reason = ProgressionService.socketRune(player, data.rune, slot)
		if not ok then
			reject(player, reason)
		end
		return ok
	end)

	Net.onAction("unsocket", function(player: Player, payload: unknown): boolean
		local slot = if type(payload) == "table" then (payload :: any).slot else payload
		if type(slot) ~= "number" then
			return false
		end
		local ok, reason = ProgressionService.unsocketRune(player, slot)
		if not ok then
			reject(player, reason)
		end
		return ok
	end)

	-- Salvage caches
	Net.onAction("crackCache", function(player: Player, payload: unknown): boolean
		local index = if type(payload) == "table" then (payload :: any).slot else payload
		if type(index) ~= "number" then
			return false
		end
		local ok, reason = ProgressionService.crackCache(player, index)
		if not ok then
			reject(player, reason)
		end
		return ok
	end)

	Net.onAction("claimCache", function(player: Player, payload: unknown): boolean
		local index = if type(payload) == "table" then (payload :: any).slot else payload
		if type(index) ~= "number" then
			return false
		end
		local ok, reason = ProgressionService.claimCache(player, index)
		if not ok then
			reject(player, reason)
		end
		return ok
	end)

	-- Feedback. Length is capped here as well as client-side: the client is not
	-- a place to enforce anything.
	Net.onAction("feedback", function(player: Player, payload: unknown): boolean
		if type(payload) ~= "table" then
			return false
		end
		local data = payload :: any
		if type(data.text) ~= "string" then
			return false
		end
		local text = string.gsub(data.text, "^%s*(.-)%s*$", "%1")
		if #text < 4 then
			reject(player, "Write a sentence first")
			return false
		end
		local category = if type(data.category) == "string" then data.category else "OTHER"
		FeedbackStore.submit(player, category, text)
		Net.sendEvent(player, { kind = "toast", text = "Feedback sent. Thank you." })
		Funnel.log(player, "Feedback_Sent")
		return true
	end)

	Net.onAction("ascend", function(player: Player): boolean
		local ok, reason = ProgressionService.ascend(player)
		if not ok then
			reject(player, reason)
		end
		return ok
	end)

	-- Trading. A request is an invite that the target answers; only ACCEPT opens
	-- a session. Offers are sent by the side that owns them and re-validated
	-- against that profile, never against the other player's payload.
	Net.onAction("tradeRequest", function(player: Player, payload: unknown): boolean
		local target = if type(payload) == "table" then (payload :: any).target else payload
		local ok, reason = TradeService.request(player, target)
		if not ok then
			reject(player, reason)
		end
		return ok
	end)

	Net.onAction("tradeRespond", function(player: Player, payload: unknown): boolean
		if type(payload) ~= "table" then
			return false
		end
		local data = payload :: any
		local ok, reason = TradeService.respond(player, data.from, data.accept)
		if not ok then
			reject(player, reason)
		end
		return ok
	end)

	Net.onAction("tradeOffer", function(player: Player, payload: unknown): boolean
		if type(payload) ~= "table" then
			return false
		end
		local data = payload :: any
		local ok, reason = TradeService.setOffer(player, data.uids, data.shards)
		if not ok then
			reject(player, reason)
		end
		return ok
	end)

	Net.onAction("tradeAccept", function(player: Player): boolean
		local ok, reason = TradeService.accept(player)
		if not ok then
			reject(player, reason)
		end
		return ok
	end)

	Net.onAction("tradeDecline", function(player: Player): boolean
		return TradeService.decline(player)
	end)

	Net.onAction("claimDaily", function(player: Player): boolean
		local ok, reason = ProgressionService.claimDaily(player)
		if not ok then
			reject(player, reason)
		end
		return ok
	end)

	Net.onAction("tutorialDone", function(player: Player): boolean
		local ok, reason = ProgressionService.claimTutorial(player)
		if not ok then
			reject(player, reason)
		end
		return ok
	end)

	Net.onAction("prompt", function(player: Player, payload: unknown): boolean
		if type(payload) ~= "table" then
			return false
		end
		local data = payload :: any
		if type(data.kind) ~= "string" or type(data.key) ~= "string" then
			return false
		end
		return MonetizationService.requestPrompt(player, data.kind, data.key)
	end)
end

-- ---------------------------------------------------------------------------
-- Boot
-- ---------------------------------------------------------------------------

--- Runs one boot stage in isolation. A service that throws must cost only its
--- own features: the first playtest died because a bad event subscription in
--- stage 5 aborted stages 6 and 7, so remotes existed but no player was ever
--- loaded and the entire client stayed dead. One stage, one blast radius.
local function stage(name: string, fn: () -> ())
	local ok, err = xpcall(fn, function(message: any): string
		return tostring(message) .. "\n" .. debug.traceback("", 2)
	end)
	if ok then
		return true
	end
	warn(string.format("[QuantumForge] boot stage '%s' failed: %s", name, err))
	return false
end

local function boot()
	-- Remotes before anything else: the client is already running by the time a
	-- server script boots, and it waits on these names.
	local remotesReady = stage("remotes", function()
		Net.init()
	end)
	if not remotesReady then
		-- Without the action remote every player request is lost, so say so in a
		-- way that survives Debug = false.
		warn("[QuantumForge] FATAL: remotes failed to initialise; the game will not be playable")
	end
	log(string.format("remotes %s", if Net.isInitialised() then "ready" else "MISSING"))

	stage("monetization", function()
		MonetizationService.init()
	end)
	log("monetization connected")

	stage("autosave", function()
		autosaveConnection = DataManager.startAutosave()
	end)
	log("autosave started")

	stage("payload", function()
		local function build(player: Player): Types.SyncPayload?
			local state = DataManager.get(player)
			if state == nil then
				return nil
			end
			return ProgressionService.buildPayload(state)
		end

		Net.setPayloadProvider(build)

		-- The boot handshake. The client fires this the moment it links, so its
		-- first frame has real numbers instead of waiting up to one sync
		-- interval. This handler was never registered, which made the handshake
		-- a no-op that cost every join one tick of empty HUD.
		Net.onRequest("state", build)

		-- The copy list. Sent on demand rather than every tick: sixty blades at
		-- 10Hz would be most of the bandwidth budget for one screen. The client
		-- watches `invVersion` and refetches only when it moves.
		Net.onRequest("inventory", function(player: Player)
			local state = DataManager.get(player)
			if state == nil then
				return {}
			end
			local entries: { Types.InvEntry } = {}
			for uid, instance in state.blades do
				entries[#entries + 1] = {
					uid = uid,
					id = instance.id,
					variant = instance.variant,
					forgedAt = instance.forgedAt,
					element = instance.element or "",
					grade = instance.grade or "",
					prefix = instance.prefix or "",
					suffix = instance.suffix or "",
				}
			end
			return entries
		end)

		-- Discovery index. One small set, fetched only when `codexVersion` moves.
		Net.onRequest("codex", function(player: Player)
			local state = DataManager.get(player)
			if state == nil then
				return { set = {}, version = 0 }
			end
			return { set = state.codex, version = state.codexVersion }
		end)

		Net.onRequest("leaderboard", function(player: Player, argument: unknown)
			local boardId = if type(argument) == "string" then argument else "star"
			return LeaderboardService.fetch(boardId, player)
		end)

		Net.onRequest("players", function(player: Player)
			return TradeService.playersFor(player)
		end)

		Net.onRequest("trade", function(player: Player)
			return TradeService.stateFor(player)
		end)
	end)

	stage("actions", function()
		registerActions()
	end)
	log("actions registered")

	-- Cosmetic only. If the bridge fails to build, the game is still playable.
	stage("lobby", function()
		LobbyService.init()
	end)
	log("lobby constructed")

	-- Blade meshes are cosmetic too, and `MeshService.init` only spawns the load:
	-- the 25 asset downloads must not sit between boot and the first player.
	-- Blades draw from primitives until they land.
	stage("meshes", function()
		MeshService.init()
	end)

	-- Pay the DataStore access probe at boot, not on the first join. This is the
	-- difference between "LINKING…" lasting one frame and lasting ten seconds:
	-- the probe is a real network round-trip, and when API access is off it is
	-- the call that fails. Doing it here means the fallback decision is already
	-- made before a player is waiting on a profile.
	stage("datastore", function()
		DataManager.init()
	end)

	-- Loading the player is what makes the game work, so it runs regardless of
	-- what happened above.
	stage("player-lifecycle", function()
		Players.PlayerAdded:Connect(function(player: Player)
			local ok, err = pcall(onPlayerReady, player)
			if not ok then
				warn(string.format("[QuantumForge] failed to initialise %s: %s", player.Name, tostring(err)))
				player:Kick("Your forge failed to initialise. Please rejoin.")
			end
		end)

		-- Players already present when the server finished booting (Studio play
		-- test, or a hot restart) never fire PlayerAdded for us.
		for _, player in Players:GetPlayers() do
			task.spawn(function()
				local ok, err = pcall(onPlayerReady, player)
				if not ok then
					warn(string.format("[QuantumForge] failed to initialise %s: %s", player.Name, tostring(err)))
				end
			end)
		end
	end)

	stage("heartbeat", function()
		heartbeatConnection = RunService.Heartbeat:Connect(function(dt: number)
			if shuttingDown then
				return
			end
			-- Clamp dt: a server hitch should not hand out a minute of drone income.
			local stepDt = math.min(dt, 0.25)

			ForgeService.step(stepDt)
			LeaderboardService.step(stepDt)
			TradeService.step()
			Net.step(stepDt)
		end)
	end)

	log(string.format("booted in %.0fms", (os.clock() - bootClock) * 1000))
end

Players.PlayerRemoving:Connect(function(player: Player)
	TradeService.onLeave(player)
	LeaderboardService.onLeave(player)
	ProgressionService.clearTradeLocks(player)
	ForgeService.forget(player)
	Funnel.forget(player)
	Net.forget(player)
end)

game:BindToClose(function()
	shuttingDown = true
	log("shutting down, flushing profiles")

	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
	if autosaveConnection then
		autosaveConnection:Disconnect()
		autosaveConnection = nil
	end

	DataManager.shutdown()
end)

boot()
