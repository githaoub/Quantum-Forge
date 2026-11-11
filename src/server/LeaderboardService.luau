--!strict
-- Global leaderboards, backed by one OrderedDataStore per board.
--
-- The numbers that matter for retention are the ones a player cannot see from
-- their own screen: how they compare. Five boards cover the four axes the design
-- asks for (Star-Matter earned, time in game, Aether, Cores) plus the collection
-- flex (best blade owned).
--
-- Storage shape is deliberate: an OrderedDataStore holds `userId -> integer`, so
-- a board read is one page, not a scan. Best-blade power is fractional, so it is
-- stored x1000 and divided on read. Names live in a plain DataStore keyed by
-- userId, written on submit; resolution falls back to the players service and
-- then to a placeholder, because a board must render even when Thumbnails or the
-- name API is unavailable.
--
-- Studio without API access cannot touch DataStores. Rather than an empty panel,
-- the service serves a seeded local board with the requester's real numbers mixed
-- in, flagged `mock = true`, and the client labels it PREVIEW. Same honesty rule
-- as the profile's mock mode: a missing number is said out loud, not faked.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BladeRegistry = require(Shared:WaitForChild("BladeRegistry"))
local ForgeConfig = require(Shared:WaitForChild("ForgeConfig"))
local ModifierConfig = require(Shared:WaitForChild("ModifierConfig"))
local NumberUtil = require(Shared:WaitForChild("NumberUtil"))
local Types = require(Shared:WaitForChild("Types"))

local DataManager = require(script.Parent.DataManager)

export type Board = {
	id: string,
	title: string,
	caption: string,
	--- Human-readable value, produced from the stored integer.
	format: (value: number) -> string,
	--- Raw stat -> stored integer.
	store: (state: Types.ProfileState) -> number,
	--- Stored integer -> displayed number.
	display: (stored: number) -> number,
}

local LeaderboardService = {}

local ROWS = 20
local CACHE_SECONDS = 8
local SUBMIT_SECONDS = 45

--- The blade detail a BEST BLADE row needs to draw the model.
---
--- `powerCopy` is the same ranking the vault and equip-best use, so the blade
--- shown beside a player's number is the copy that actually produced it.
export type BladeDetail = {
	id: string,
	variant: string,
	grade: string,
	element: string,
	prefix: string,
	suffix: string,
	--- Exact multiplier, modifiers included.
	mult: number,
	--- Affixed name, composed server-side so the client does not repeat the rule.
	display: string,
}

local function bestCopyOf(state: Types.ProfileState): (Types.BladeInstance?, number)
	local best: Types.BladeInstance? = nil
	local bestPower = 0
	for _, instance in state.blades do
		local power = ForgeConfig.powerCopy(instance)
		if power > bestPower then
			bestPower = power
			best = instance
		end
	end
	return best, bestPower
end

local function detailOf(instance: Types.BladeInstance, power: number): BladeDetail?
	local blade = BladeRegistry.get(instance.id)
	if blade == nil then
		return nil
	end
	return {
		id = instance.id,
		variant = instance.variant,
		grade = instance.grade or "",
		element = instance.element or "",
		prefix = instance.prefix or "",
		suffix = instance.suffix or "",
		mult = power,
		display = ModifierConfig.displayName(blade.name, instance.prefix or "", instance.suffix or ""),
	}
end

--- Best blade owned, by the same `powerCopy` the vault and equip-best use.
local function bestBlade(state: Types.ProfileState): number
	local _, power = bestCopyOf(state)
	return power
end

local function rounds(value: number): string
	return NumberUtil.abbreviate(math.max(0, math.floor(value)))
end

LeaderboardService.Boards = {
	{ id = "star", title = "STAR-MATTER EARNED", caption = "lifetime, never spent", format = rounds,
		store = function(state: Types.ProfileState): number
			return math.floor(math.min(state.lifetimeStarMatter, 9e18))
		end,
		display = function(stored: number): number
			return stored
		end } :: Board,

	{ id = "playtime", title = "TIME AT THE FORGE", caption = "seconds of play", format = NumberUtil.abbreviateTime,
		store = function(state: Types.ProfileState): number
			return math.floor(math.min(state.totalPlaytime, 9e15))
		end,
		display = function(stored: number): number
			return stored
		end } :: Board,

	{ id = "aether", title = "AETHER COLLECTED", caption = "lifetime, never spent", format = rounds,
		store = function(state: Types.ProfileState): number
			return math.floor(math.min(state.lifetimeAether, 9e15))
		end,
		display = function(stored: number): number
			return stored
		end } :: Board,

	{ id = "cores", title = "CORES COLLECTED", caption = "lifetime Quantum Cores", format = rounds,
		store = function(state: Types.ProfileState): number
			return math.floor(math.min(state.lifetimeCores, 9e15))
		end,
		display = function(stored: number): number
			return stored
		end } :: Board,

	{ id = "blades", title = "BEST BLADE OWNED", caption = "multiplier, modifiers included", format = function(stored: number): string
			return NumberUtil.abbreviateMultiplier(stored / 1000)
		end,
		store = function(state: Types.ProfileState): number
			return math.floor(math.min(bestBlade(state) * 1000, 9e18))
		end,
		display = function(stored: number): number
			return stored / 1000
		end } :: Board,
}

local byId: { [string]: Board } = {}
for _, board in LeaderboardService.Boards do
	byId[board.id] = board
end

local orderedStores: { [string]: OrderedDataStore } = {}
local nameStore: DataStore? = nil
local detailStore: DataStore? = nil
local mockMode = false
local warnedStore = false
local submitClock = 0
local cache: { [string]: { at: number, rows: { any }, mock: boolean } } = {}
local nameCache: { [string]: string } = {}
local detailCache: { [string]: { at: number, detail: BladeDetail? } } = {}
local DETAIL_SECONDS = 60

--- Seeded preview boards. Values are chosen so every formatter has something to
--- chew on (Qa, hours, K, a real multiplier) without implying live players.
local MOCK_ROWS: { [string]: { { any } } } = {
	star = {
		{ "Vantablack", 8.4e17 }, { "RueTheSmith", 6.1e16 }, { "ColdAnvil", 9.3e15 },
		{ "NineTides", 2.2e15 }, { "KilnRat", 7.7e14 }, { "Ozone", 4.4e13 },
		{ "Halfhand", 8.1e12 }, { "Slagborn", 5.5e11 }, { "Mica", 2.9e10 },
	},
	playtime = {
		{ "Vantablack", 412000 }, { "ColdAnvil", 288000 }, { "RueTheSmith", 191000 },
		{ "NineTides", 122000 }, { "KilnRat", 84000 }, { "Mica", 41000 },
	},
	aether = {
		{ "ColdAnvil", 184000 }, { "Vantablack", 151000 }, { "NineTides", 74000 },
		{ "KilnRat", 38000 }, { "Ozone", 21000 }, { "Mica", 9000 },
	},
	cores = {
		{ "Vantablack", 4820 }, { "ColdAnvil", 2140 }, { "NineTides", 880 },
		{ "RueTheSmith", 540 }, { "KilnRat", 210 }, { "Mica", 60 },
	},
	blades = {
		{ "NineTides", 48000000, { id = "gen_5_greatsword", variant = "prismatic", grade = "transcendent",
			element = "void", prefix = "starforged", suffix = "firstforge", mult = 48000,
			display = "Starforged Ash Reaver of the First Forge" } },
		{ "Vantablack", 31000000, { id = "gen_5_scythe", variant = "void", grade = "mythic",
			element = "void", prefix = "cursed", suffix = "acheron", mult = 31000,
			display = "Cursed Zephyr Spike of Acheron" } },
		{ "ColdAnvil", 12000000, { id = "gen_4_glaive", variant = "overclocked", grade = "exalted",
			element = "frost", prefix = "gilded", suffix = "dawn", mult = 12000,
			display = "Gilded Rift Lance of Dawn" } },
		{ "Ozone", 4200000, { id = "gen_3_curved", variant = "tempered", grade = "refined",
			element = "storm", prefix = "runed", suffix = "echoes", mult = 4200,
			display = "Runed Lumen Cleaver of Echoes" } },
		{ "KilnRat", 900000, { id = "gen_2_straight", variant = "tempered", grade = "common",
			element = "ember", prefix = "molten", suffix = "ruin", mult = 900,
			display = "Molten Frost Scythe of Ruin" } },
		{ "Mica", 120000, { id = "gen_1_scythe", variant = "standard", grade = "common",
			element = "terra", prefix = "", suffix = "", mult = 120,
			display = "Dusk Scythe" } },
	},
}

local function storeFor(boardId: string): OrderedDataStore?
	if mockMode then
		return nil
	end
	local existing = orderedStores[boardId]
	if existing then
		return existing
	end
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore(string.format("QF_Leaderboard_%s_v1", boardId))
	end)
	if not ok or store == nil then
		mockMode = true
		if not warnedStore then
			warnedStore = true
			warn("[QuantumForge] leaderboards running in LOCAL PREVIEW (no DataStore access)")
		end
		return nil
	end
	orderedStores[boardId] = store
	return store
end

local function namesStore(): DataStore?
	if mockMode then
		return nil
	end
	if nameStore then
		return nameStore
	end
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore("QF_LeaderboardNames_v1")
	end)
	if ok then
		nameStore = store :: DataStore
	end
	return nameStore
end

--- Parallel store for the blade behind a BEST BLADE row. An OrderedDataStore
--- holds `userId -> integer`, so the model, variant and affixes need somewhere
--- else to live; this is one record per player, written on the same submit.
local function detailsStore(): DataStore?
	if mockMode then
		return nil
	end
	if detailStore then
		return detailStore
	end
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore("QF_BestBlade_v1")
	end)
	if ok then
		detailStore = store :: DataStore
	end
	return detailStore
end

--- Rebuilds a detail record from whatever the store returns. Every field is
--- checked: a hand-edited or half-written record must render as "no art" rather
--- than as a nil index inside the board painter.
local function sanitiseDetail(value: any): BladeDetail?
	if type(value) ~= "table" then
		return nil
	end
	local id = value.id
	if type(id) ~= "string" then
		return nil
	end
	local blade = BladeRegistry.get(id)
	if blade == nil then
		return nil
	end
	local mult = tonumber(value.mult)
	if mult == nil or mult <= 0 then
		return nil
	end

	local variantId = if type(value.variant) == "string" and ForgeConfig.hasVariant(value.variant)
		then value.variant
		else "standard"
	local grade = if ModifierConfig.hasGrade(value.grade) then value.grade else ""
	local element = if ModifierConfig.hasElement(value.element) then value.element else ""
	local prefix = if ModifierConfig.hasPrefix(value.prefix) then value.prefix else ""
	local suffix = if ModifierConfig.hasSuffix(value.suffix) then value.suffix else ""

	return {
		id = id,
		variant = variantId,
		grade = grade,
		element = element,
		prefix = prefix,
		suffix = suffix,
		mult = mult,
		display = ModifierConfig.displayName(blade.name, prefix, suffix),
	}
end

--- Cached per-user detail read. The board is one page of twenty, refreshed every
--- eight seconds; a minute of cache means a row's model does not re-hit storage
--- on every repaint, and a stale record only means an older blade beside a
--- number that has not moved yet.
local function detailFor(userId: number): BladeDetail?
	local key = tostring(userId)
	local cached = detailCache[key]
	local now = os.clock()
	if cached and now - cached.at < DETAIL_SECONDS then
		return cached.detail
	end
	local store = detailsStore()
	if store == nil then
		return nil
	end
	local ok, value = pcall(function()
		return store:GetAsync(key)
	end)
	local detail = if ok then sanitiseDetail(value) else nil
	-- A missing record is cached for less time than a real one: the first submit
	-- after a player starts using the board would otherwise leave them showing
	-- "NO BLADE RECORDED" for a full minute.
	detailCache[key] = { at = now, detail = detail }
	if detail == nil then
		detailCache[key].at = now - DETAIL_SECONDS + 15
	end
	return detail
end

--- Cached name resolution. OrderedDataStore only hands back UserIds; every board
--- read would otherwise pay one name request per row.
local function nameFor(userId: number): string
	local key = tostring(userId)
	local cached = nameCache[key]
	if cached then
		return cached
	end
	local online = Players:GetPlayerByUserId(userId)
	if online then
		nameCache[key] = online.Name
		return online.Name
	end
	local okName, resolved = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local name = if okName and type(resolved) == "string" and resolved ~= ""
		then resolved
		else string.format("FORGER %04d", userId % 10000)
	nameCache[key] = name
	return name
end

--- Writes one player's current numbers to every board. Called on a slow clock and
--- on leave; `SetAsync` is cheap but not free, and a board that trails a live
--- session by a minute is the normal cost of a global ranking.
function LeaderboardService.submit(player: Player)
	local state = DataManager.get(player)
	if state == nil then
		return
	end

	for _, board in LeaderboardService.Boards do
		local store = storeFor(board.id)
		if store then
			local value = board.store(state)
			pcall(function()
				store:SetAsync(tostring(player.UserId), value)
			end)
		end
	end

	local names = namesStore()
	if names then
		pcall(function()
			names:SetAsync(tostring(player.UserId), player.Name)
		end)
	end

	-- The model behind the BEST BLADE row. Written on the same cadence as the
	-- boards so the two cannot disagree for longer than one submit interval.
	local bestInstance, bestPower = bestCopyOf(state)
	local details = detailsStore()
	if details and bestInstance then
		local detail = detailOf(bestInstance, bestPower)
		if detail then
			pcall(function()
				details:SetAsync(tostring(player.UserId), detail)
			end)
		end
	end
end

local function mockRows(board: Board, player: Player, mine: number, myDetail: BladeDetail?): { any }
	local rows = {}
	for _, entry in MOCK_ROWS[board.id] or {} do
		rows[#rows + 1] = {
			name = entry[1],
			value = entry[2],
			text = board.format(entry[2]),
			blade = entry[3],
			you = false,
		}
	end
	rows[#rows + 1] = {
		name = player.Name,
		value = mine,
		text = board.format(board.display(mine)),
		blade = myDetail,
		you = true,
	}
	table.sort(rows, function(a: any, b: any): boolean
		return a.value > b.value
	end)
	for index, row in rows do
		row.rank = index
	end
	return rows
end

--- Reads one board, newest first, cached for a few seconds. `player` is only
--- used for the "YOU" row and the preview board.
function LeaderboardService.fetch(boardId: string, player: Player): { [string]: any }
	local board = byId[boardId]
	if board == nil then
		return { ok = false, rows = {}, mock = mockMode }
	end

	local state = DataManager.get(player)
	local mine = if state then board.store(state) else 0
	local myDetail: BladeDetail? = nil
	if board.id == "blades" and state then
		local instance, power = bestCopyOf(state)
		if instance then
			myDetail = detailOf(instance, power)
		end
	end
	local now = os.clock()
	local cached = cache[boardId]
	if cached and now - cached.at < CACHE_SECONDS then
		return { ok = true, id = board.id, title = board.title, caption = board.caption, rows = cached.rows, mock = cached.mock }
	end

	local store = storeFor(boardId)
	if store == nil then
		local rows = mockRows(board, player, mine, myDetail)
		cache[boardId] = { at = now, rows = rows, mock = true }
		return { ok = true, id = board.id, title = board.title, caption = board.caption, rows = rows, mock = true }
	end

	local rows: { any } = {}
	local okPage, pages = pcall(function()
		return store:GetSortedAsync(false, ROWS)
	end)
	if not okPage or pages == nil then
		-- A DataStore handle can be created in Studio even when storage is not
		-- reachable; the *read* is what fails. Falling through here would return
		-- a board holding only the requester's own line and no PREVIEW flag,
		-- which reads as "you are rank 1 of 1 in the world". Say preview instead.
		mockMode = true
		local fallback = mockRows(board, player, mine, myDetail)
		cache[boardId] = { at = now, rows = fallback, mock = true }
		return {
			ok = true,
			id = board.id,
			title = board.title,
			caption = board.caption,
			rows = fallback,
			mock = true,
		}
	end

	local okCurrent, page = pcall(function()
		return pages:GetCurrentPage()
	end)
	if okCurrent and type(page) == "table" then
		for index, entry in page do
			local userId = tonumber(entry.key)
			if userId then
				local shown = board.display(entry.value)
				local row = {
					name = nameFor(userId),
					userId = userId,
					value = shown,
					text = board.format(shown),
					rank = index,
					you = userId == player.UserId,
				}
				if board.id == "blades" then
					-- One extra read per row, cached for a minute. The board is a
					-- top-20 page and only open while the panel is up, so this is
					-- twenty reads per open, not twenty per player per tick.
					-- Your own row skips the read: `myDetail` is already in hand
					-- and is fresher than the last submit.
					row.blade = if userId == player.UserId and myDetail ~= nil
						then myDetail
						else detailFor(userId)
				end
				rows[#rows + 1] = row
			end
		end
	end

	-- The caller always gets their own line, even when they are rank 40,000.
	local found = false
	for _, row in rows do
		if row.you then
			found = true
			break
		end
	end
	if not found then
		rows[#rows + 1] = {
			name = player.Name,
			userId = player.UserId,
			value = board.display(mine),
			text = board.format(board.display(mine)),
			blade = myDetail,
			rank = #rows + 1,
			you = true,
		}
	end

	cache[boardId] = { at = now, rows = rows, mock = false }
	return { ok = true, id = board.id, title = board.title, caption = board.caption, rows = rows, mock = false }
end

--- One slow clock for every loaded player. Called from the server heartbeat.
function LeaderboardService.step(dt: number)
	submitClock += dt
	if submitClock < SUBMIT_SECONDS then
		return
	end
	submitClock = 0
	for _, player in Players:GetPlayers() do
		if DataManager.get(player) then
			LeaderboardService.submit(player)
		end
	end
end

function LeaderboardService.forget(player: Player)
	_ = player
end

--- Leaves a final submit before the profile is released. Wrapped by the caller so
--- a DataStore outage cannot delay the leave.
function LeaderboardService.onLeave(player: Player)
	pcall(LeaderboardService.submit, player)
end

return LeaderboardService
