--!strict
-- Client-side mirror of server state, plus optimistic click prediction.
--
-- Why prediction: state arrives at 10Hz. If the HUD only moved when a packet
-- landed, every click would feel 50-100ms late and the game would feel dead.
-- So a click immediately credits a *predicted* amount to the displayed total,
-- and each sync reconciles: whatever the server confirmed is subtracted from
-- the pending buffer. The number never drifts and never double-counts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local StateStore = {}

export type Listener = (state: Types.SyncPayload) -> ()

StateStore.current = nil :: Types.SyncPayload?
StateStore.connected = false
-- True once the remote objects are actually resolved. `send` is a silent no-op
-- before that, which is correct during the first few frames of boot.
StateStore.linked = false

--- Every forged copy, fetched on demand rather than every tick. `invVersion`
--- mirrors the payload field; when they disagree the list is stale and refetched.
StateStore.inventory = {} :: { Types.InvEntry }
StateStore.inventoryVersion = -1

--- Discovery index, same event-shaped contract as the inventory: the server
--- bumps `codexVersion` when a new key lands, and only then is the set refetched.
StateStore.codex = {} :: { [string]: boolean }
StateStore.codexVersion = -1

-- Predicted Star-Matter not yet confirmed by a sync.
local pendingCredit = 0
local lastServerSm = 0
local lastSyncAt = 0

local syncListeners: { [number]: Listener } = {}
local eventListeners: { [number]: (Types.FeedEvent) -> () } = {}
local inventoryListeners: { [number]: ({ Types.InvEntry }) -> () } = {}
local codexListeners: { [number]: ({ [string]: boolean }) -> () } = {}
local nextListenerId = 0

local actionRemote: RemoteEvent? = nil
local syncRemote: RemoteEvent? = nil
local eventRemote: RemoteEvent? = nil
local requestRemote: RemoteFunction? = nil

-- ---------------------------------------------------------------------------
-- Listener registry
-- ---------------------------------------------------------------------------

local function subscribe<T>(registry: { [number]: T }, listener: T): () -> ()
	nextListenerId += 1
	local id = nextListenerId
	registry[id] = listener
	return function()
		registry[id] = nil
	end
end

local function emit<T>(registry: { [number]: T }, ...: any)
	-- Snapshot first: a listener that unsubscribes itself mid-iteration would
	-- otherwise mutate the table being walked.
	local snapshot = {}
	for _, listener in registry do
		table.insert(snapshot, listener)
	end
	for _, listener in snapshot do
		local ok, err = pcall(listener, ...)
		if not ok then
			warn(string.format("[StateStore] listener error: %s", tostring(err)))
		end
	end
end

-- ---------------------------------------------------------------------------
-- Derived view of the current state
-- ---------------------------------------------------------------------------

--- Server truth plus unconfirmed clicks. This is what the HUD should render.
function StateStore.displayStarMatter(): number
	local state = StateStore.current
	if state == nil then
		return pendingCredit
	end
	return state.sm + pendingCredit
end

--- Seconds since the last sync landed. The HUD uses it to dim itself when the
-- server stops talking, which is the honest signal that something is wrong.
function StateStore.staleness(): number
	if lastSyncAt == 0 then
		return math.huge
	end
	return os.clock() - lastSyncAt
end

-- ---------------------------------------------------------------------------
-- Outbound
-- ---------------------------------------------------------------------------

--- Fire an intent. Unknown verbs are the server's problem to reject; we do not
-- maintain a client-side allowlist that could drift out of sync.
function StateStore.send(verb: string, payload: any?)
	if actionRemote == nil then
		return
	end
	actionRemote:FireServer(verb, payload)
end

--- Optimistically credits a click. The caller passes the yield it believes it
-- earned; reconciliation handles any over-prediction.
function StateStore.predictClick(amount: number, crit: boolean)
	pendingCredit += amount
	local state = StateStore.current
	if state then
		local projected: Types.SyncPayload = table.clone(state)
		projected.sm = state.sm + pendingCredit
		emit(syncListeners, projected)
	end
	_ = crit
end

-- ---------------------------------------------------------------------------
-- Inbound
-- ---------------------------------------------------------------------------

local fetchingInventory = false
local fetchingCodex = false

--- Generic request seam. Every panel that needs data the tick payload does not
--- carry (inventory, codex, boards, trade state) goes through this, so the remote
--- name lives in one place and a missing remote fails as nil rather than an error.
function StateStore.request(verb: string, argument: any?): any
	if requestRemote == nil then
		return nil
	end
	local ok, result = pcall(function()
		return requestRemote:InvokeServer(verb, argument)
	end)
	if ok then
		return result
	end
	return nil
end

--- Pulls the full copy list. Called from `reconcile` when the revision moves and
--- from `init` on the first payload. Failure is non-fatal: the previous list
--- stays on screen and the next tick retries.
local function fetchInventory(version: number)
	if fetchingInventory then
		return
	end
	fetchingInventory = true
	task.spawn(function()
		local ok, list = pcall(function()
			if requestRemote == nil then
				return nil
			end
			return requestRemote:InvokeServer("inventory")
		end)
		fetchingInventory = false
		if ok and type(list) == "table" then
			StateStore.inventory = list :: { Types.InvEntry }
			StateStore.inventoryVersion = version
			emit(inventoryListeners, StateStore.inventory)
		end
	end)
end

local function fetchCodex(version: number)
	if fetchingCodex then
		return
	end
	fetchingCodex = true
	task.spawn(function()
		local result = StateStore.request("codex")
		fetchingCodex = false
		if type(result) == "table" and type((result :: any).set) == "table" then
			StateStore.codex = (result :: any).set
			StateStore.codexVersion = version
			emit(codexListeners, StateStore.codex)
		end
	end)
end

local function reconcile(payload: Types.SyncPayload)
	-- Anything the server added since the last sync covers that much of our
	-- pending buffer. Overshoot clamps to zero: the client simply cannot be
	-- credited for more than it predicted.
	local confirmed = payload.sm - lastServerSm
	if confirmed > 0 then
		pendingCredit = math.max(0, pendingCredit - confirmed)
	end
	lastServerSm = payload.sm
	lastSyncAt = os.clock()

	StateStore.current = payload
	emit(syncListeners, payload)

	-- Inventory is event-shaped, not tick-shaped. Fetch it only when the server
	-- says the revision moved, and never two fetches at once.
	if payload.invVersion ~= StateStore.inventoryVersion and not fetchingInventory then
		fetchInventory(payload.invVersion)
	end

	if payload.codexVersion ~= StateStore.codexVersion and not fetchingCodex then
		fetchCodex(payload.codexVersion)
	end
end

--- Resolves the remotes and starts listening. Yields if the folder has not
--- replicated yet, which is exactly why `init` does not call it inline.
local function connect()
	if syncRemote ~= nil then
		return
	end

	-- `Config.Remotes` maps a key to its *class*; `Net.init` names each instance
	-- after the key (`for name, className in Config.Remotes`). The key is
	-- therefore also the instance name. Passing `Config.Remotes.StateSync` here
	-- passed the class name, so `Connect` waited ten seconds for a child
	-- literally called "RemoteEvent" and gave up — which is why the HUD sat on
	-- LINKING… with every StateSync dropped.
	syncRemote = Remotes.event("StateSync")
	actionRemote = Remotes.event("Action")
	eventRemote = Remotes.event("Event")
	requestRemote = Remotes.func("RequestState")

	if syncRemote then
		syncRemote.OnClientEvent:Connect(function(payload: unknown)
			if type(payload) ~= "table" then
				return
			end
			reconcile(payload :: Types.SyncPayload)
		end)
	end

	if eventRemote then
		eventRemote.OnClientEvent:Connect(function(event: unknown)
			if type(event) ~= "table" then
				return
			end
			emit(eventListeners, event :: Types.FeedEvent)
		end)
	end

	-- Handshake: ask for state right now instead of waiting for the first tick.
	-- Wrapped in a task so a dead request cannot block the caller's boot path.
	if requestRemote then
		task.spawn(function()
			local ok, payload = pcall(function()
				return requestRemote:InvokeServer("state")
			end)
			if ok and type(payload) == "table" then
				reconcile(payload :: Types.SyncPayload)
			end
		end)
	end

	-- A missing sync remote means no payload will ever arrive. Reporting `linked`
	-- regardless would paint a live-looking HUD over a dead connection, which is
	-- a worse failure than saying nothing.
	StateStore.linked = syncRemote ~= nil
end

--- Every remote the store needs is already replicated. Checked with FindFirstChild
--- rather than WaitForChild so the answer costs nothing and cannot yield.
local function resolved(): boolean
	return Remotes.peek("StateSync") ~= nil
		and Remotes.peek("Action") ~= nil
		and Remotes.peek("Event") ~= nil
		and Remotes.peek("RequestState") ~= nil
end

--- Boots the store. Idempotent so a re-run in Studio playtests is harmless.
---
--- Deliberately non-blocking: the UI is built before this is called, and the
--- HUD must paint even when the server has not finished booting. When every
--- remote is already here we connect on this thread, otherwise the wait moves to
--- a background task and the screen fills in when the payload lands.
function StateStore.init()
	if StateStore.connected then
		return
	end
	StateStore.connected = true

	if resolved() then
		connect()
		return
	end

	task.spawn(function()
		local ok, err = pcall(connect)
		if not ok then
			warn(string.format("[StateStore] connect failed: %s", tostring(err)))
		end
	end)
end

--- Called when the server pushes its opening payload explicitly.
function StateStore.onSync(listener: Listener): () -> ()
	return subscribe(syncListeners, listener)
end

function StateStore.onEvent(listener: (Types.FeedEvent) -> ()): () -> ()
	return subscribe(eventListeners, listener)
end

--- Fires whenever the copy list is refetched. The inventory view rebuilds from
--- the list, not from the payload, so a trade or a salvage updates it directly.
function StateStore.onInventory(listener: ({ Types.InvEntry }) -> ()): () -> ()
	return subscribe(inventoryListeners, listener)
end

--- Blocks until the copy list has arrived. Used once by the inventory view on
--- its first build so the list does not flash empty on a cold join.
function StateStore.awaitInventory(timeout: number?): { Types.InvEntry }
	local deadline = os.clock() + (timeout or 6)
	while StateStore.inventoryVersion < 0 and os.clock() < deadline do
		task.wait(0.05)
	end
	return StateStore.inventory
end

--- Fires whenever a new discovery lands. The codex paints from this, not from
--- the tick, for the same reason the vault does.
function StateStore.onCodex(listener: ({ [string]: boolean }) -> ()): () -> ()
	return subscribe(codexListeners, listener)
end

--- Blocks until the discovery set has arrived, then returns it.
function StateStore.awaitCodex(timeout: number?): { [string]: boolean }
	local deadline = os.clock() + (timeout or 6)
	while StateStore.codexVersion < 0 and os.clock() < deadline do
		task.wait(0.05)
	end
	return StateStore.codex
end

--- Current preference value, defaulting on when no payload has landed.
function StateStore.setting(key: string): boolean
	local state = StateStore.current
	if state == nil then
		return true
	end
	local settings = state.settings
	if key == "sfx" then
		return settings.sfx
	elseif key == "vfx" then
		return settings.vfx
	elseif key == "shake" then
		return settings.shake
	elseif key == "trades" then
		return settings.trades
	end
	return true
end

--- Blocks until a first payload exists or the timeout expires. Controllers use
-- it to build their initial render from real numbers instead of zeros.
function StateStore.awaitFirstState(timeout: number?): Types.SyncPayload?
	local deadline = os.clock() + (timeout or 8)
	while StateStore.current == nil and os.clock() < deadline do
		task.wait(0.05)
	end
	return StateStore.current
end

return StateStore
