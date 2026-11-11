--!strict
-- Owns the network boundary: remote creation, action routing, ping budgets, and
-- the single batched state push.
--
-- Why batched: an incremental fires state changes dozens of times a second. One
-- remote call per change is the classic way to make a Roblox server fall over at
-- 40 players. Everything coalesces into one payload per player per tick.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Types = require(ReplicatedStorage.Shared:WaitForChild("Types"))

local Net = {}

-- Handlers receive the client's payload, never the verb. The dispatcher already
-- routed on the verb; passing it on again meant every handler read the action
-- name as its argument — `forge` looked up a blade called "forge", found nothing,
-- and rejected with "Unknown blade". Forging and equipping were both dead, and
-- the onboarding step that asks for a blade could never complete.
type ActionHandler = (player: Player, payload: any) -> boolean
type RequestHandler = (player: Player, argument: any) -> any

local remotesFolder: Folder
local actionRemote: RemoteEvent
local syncRemote: RemoteEvent
local eventRemote: RemoteEvent
local requestRemote: RemoteFunction

local actionHandlers: { [string]: ActionHandler } = {}
local requestHandlers: { [string]: RequestHandler } = {}

local pending: { [Player]: Types.SyncPayload } = {}
local lastSync: { [Player]: number } = {}

-- Preferred path: the service layer exposes a builder and Net pulls fresh state
-- only on ticks that actually send. Building a payload every frame just to throw
-- 90% of them away is wasted work at scale.
local payloadProvider: ((Player) -> Types.SyncPayload)? = nil

local syncAccumulator = 0
local syncInterval = 1 / Config.SyncHz
local initialised = false

--- Creates the Remotes folder and every declared remote. Runs before any player
--- joins, so remotes exist by the time clients boot. Idempotent: the server
--- entry point calls it as early as possible and the boot stage asks again.
function Net.init()
	if initialised then
		return
	end

	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing then
		existing:Destroy()
	end

	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "Remotes"

	for name, className in Config.Remotes do
		local remote: Instance
		if className == "RemoteFunction" then
			remote = Instance.new("RemoteFunction")
		else
			remote = Instance.new("RemoteEvent")
		end
		remote.Name = name
		remote.Parent = remotesFolder
	end

	remotesFolder.Parent = ReplicatedStorage

	actionRemote = remotesFolder:WaitForChild("Action") :: RemoteEvent
	syncRemote = remotesFolder:WaitForChild("StateSync") :: RemoteEvent
	eventRemote = remotesFolder:WaitForChild("Event") :: RemoteEvent
	requestRemote = remotesFolder:WaitForChild("RequestState") :: RemoteFunction

	actionRemote.OnServerEvent:Connect(function(player: Player, action: unknown, payload: unknown)
		if type(action) ~= "string" then
			return
		end
		local handler = actionHandlers[action]
		if handler then
			-- Handlers return false when the action was rejected; we never trust
			-- anything the client sends beyond "please try this". The pcall is
			-- here rather than in every handler: one bad request must not
			-- disconnect the remote for everyone in the server.
			local ok, err = pcall(handler, player, payload)
			if not ok then
				warn(string.format("[Net] action '%s' errored for %s: %s", action, player.Name, tostring(err)))
			end
		end
	end)

	requestRemote.OnServerInvoke = function(player: Player, verb: unknown, argument: unknown): any
		local key = if type(verb) == "string" then verb else "state"
		local handler = requestHandlers[key]
		if handler == nil then
			return nil
		end
		local ok, result = pcall(handler, player, argument)
		if ok then
			return result
		end
		warn(string.format("[Net] request '%s' errored for %s: %s", key, player.Name, tostring(result)))
		return nil
	end

	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
		lastSync[player] = nil
	end)

	initialised = true
end

--- Whether the remotes exist. The entry point reports this in its boot log so a
--- client waiting on a folder that was never made is visible immediately.
function Net.isInitialised(): boolean
	return initialised
end

--- Registers a handler for a client action verb, e.g. "click" or "buyBlade".
function Net.onAction(verb: string, handler: ActionHandler)
	actionHandlers[verb] = handler
end

--- Registers a handler for a RemoteFunction request, e.g. the boot handshake.
function Net.onRequest(verb: string, handler: RequestHandler)
	requestHandlers[verb] = handler
end

--- Registers the state builder pulled on every sync tick. Returning nil skips
--- the player for that tick, which is how a profile mid-load stays silent.
function Net.setPayloadProvider(provider: (Player) -> Types.SyncPayload?)
	payloadProvider = provider
end

--- Sends a payload now, then lets the tick take over.
---
--- This used to only queue, which meant the opening payload could sit for up to
--- one sync interval — the client's first frames were blank numbers for no
--- reason. An explicit payload is by definition the one the caller wants seen
--- immediately (join, ascension, purchase), so it goes out on this frame.
function Net.setPayload(player: Player, payload: Types.SyncPayload)
	if not player.Parent then
		return
	end
	syncRemote:FireClient(player, payload)
	lastSync[player] = os.clock()
	pending[player] = nil
end

--- One-shot feedback. Not batched: these are discrete events the client reacts
--- to (floating numbers, screen shake) and dropping duplicates would be worse
--- than the extra packet.
function Net.sendEvent(player: Player, event: Types.FeedEvent)
	eventRemote:FireClient(player, event)
end

function Net.broadcast(event: Types.FeedEvent)
	eventRemote:FireAllClients(event)
end

--- Flushes state at a fixed cadence. Call from Heartbeat.
function Net.step(dt: number)
	syncAccumulator += dt
	if syncAccumulator < syncInterval then
		return
	end
	syncAccumulator = 0

	-- Provider-built payloads first: they are always fresher than a queued one.
	if payloadProvider then
		for _, player in Players:GetPlayers() do
			local payload = payloadProvider(player)
			if payload then
				syncRemote:FireClient(player, payload)
				lastSync[player] = os.clock()
			end
		end
	end

	for player, payload in pending do
		if player.Parent then
			syncRemote:FireClient(player, payload)
			lastSync[player] = os.clock()
		else
			pending[player] = nil
		end
	end
end

--- Drops a player's buffer without waiting for PlayerRemoving. Used by
--- DataManager when it releases a profile.
function Net.forget(player: Player)
	pending[player] = nil
	lastSync[player] = nil
end

--- Milliseconds since this player last received a sync. DataManager uses it to
--- avoid saving a profile that is mid-flush.
function Net.sinceSync(player: Player): number
	local last = lastSync[player]
	if not last then
		return math.huge
	end
	return (os.clock() - last) * 1000
end

return Net
