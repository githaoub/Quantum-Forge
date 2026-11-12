--!strict
-- Contextual nudges. The first-run guide teaches the loop once; this module
-- watches the live payload after that and says something when a decision opens
-- up: an ascent, a daily, a cache, a rune socket, a new drone rung.
--
-- Every nudge is edge-triggered. A ready state fires once and stays quiet until
-- it clears and comes back, so a player who ignores the toast does not get it
-- again every ten seconds. Tab glows are not here: `Sections.refreshTabBadges`
-- owns those because they have to re-evaluate with the layout.
--
-- Nudges pause while the first-run guide is on screen. That guide is already
-- pointing at the same controls, and two voices saying "look here" is worse
-- than one.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local DroneRegistry = require(Shared:WaitForChild("DroneRegistry"))
local Types = require(Shared:WaitForChild("Types"))

local Notifications = require(script.Parent.Notifications)
local Sfx = require(script.Parent.Sfx)
local StateStore = require(script.Parent.StateStore)

local Nudges = {}

type Gate = {
	--- True while the thing is worth announcing.
	open: (payload: Types.SyncPayload) -> boolean,
	--- Fires on the closed -> open edge.
	say: () -> (),
	--- Latched, so one open state only says one line.
	fired: boolean,
}

-- Nudges start muted. The first-run guide owns the screen until it either
-- starts or decides the account has already seen it, and the guide publishes
-- that decision through `onRunChanged`. Until then a toast about a ready daily
-- would compete with the starter card.
local paused = true
local gates: { Gate } = {}
--- Which rungs have already had their line. The first payload marks every
--- rung the account can already buy, so a join with saved Aether is not greeted
--- by a toast about a ladder the player already knows.
local tierAnnounced: { [string]: boolean } = {}
local tiersPrimed = false
--- One contextual line at a time, and only onto an empty stack. The toast rail
--- holds two; firing three nudges in one payload evicts the first before it can
--- be read. Three seconds covers a toast's 2.6s hold plus its fade.
local NUDGE_GAP = 3.0
local nextSpeakAt = 0
local unsubscribe: (() -> ())? = nil

local function canSpeak(): boolean
	return not paused and os.clock() >= nextSpeakAt and Notifications.count() == 0
end

--- Returns false when the line has to wait for the rail. The caller keeps its
--- latch open so the same edge is retried on the next payload.
local function speak(say: () -> ()): boolean
	if not canSpeak() then
		return false
	end
	nextSpeakAt = os.clock() + NUDGE_GAP
	say()
	return true
end

local function hasFreeSocket(payload: Types.SyncPayload): boolean
	for index = 1, payload.socketSlots do
		if (payload.equippedSockets[index] or "") == "" then
			return true
		end
	end
	return false
end

local function ownsRune(payload: Types.SyncPayload): boolean
	for _, count in payload.runes do
		if count > 0 then
			return true
		end
	end
	return false
end

local function claimableCache(payload: Types.SyncPayload): boolean
	for _, cache in payload.caches do
		if cache.readyAt > 0 and cache.secondsLeft <= 0 then
			return true
		end
	end
	return false
end

local function buildGates()
	gates = {
		{
			open = function(payload: Types.SyncPayload): boolean
				return payload.ascendAt > 0 and payload.sm >= payload.ascendAt
			end,
			say = function(): ()
				Notifications.push("ASCEND is ready. Open it from the top bar.", "good")
				Sfx.ui()
			end,
			fired = false,
		},
		{
			open = function(payload: Types.SyncPayload): boolean
				return payload.dailyReady
			end,
			say = function(): ()
				Notifications.push("Your daily reward is ready.", "currency")
				Sfx.coin()
			end,
			fired = false,
		},
		{
			open = claimableCache,
			say = function(): ()
				Notifications.push("A salvage cache is claimable in FLEET.", "good")
				Sfx.coin()
			end,
			fired = false,
		},
		{
			open = function(payload: Types.SyncPayload): boolean
				return payload.socketSlots > 0 and ownsRune(payload) and hasFreeSocket(payload)
			end,
			say = function(): ()
				Notifications.push("A rune socket is open in RUNES.", "good")
				Sfx.ui()
			end,
			fired = false,
		},
	}
end

local function evaluate(payload: Types.SyncPayload)
	for _, gate in gates do
		local open = gate.open(payload)
		if open then
			if not gate.fired and speak(gate.say) then
				gate.fired = true
			end
		else
			gate.fired = false
		end
	end

	-- A drone rung is worth a line when the player can buy a rung they do not
	-- own. The ladder is ordered, so the last match is the best tier in reach;
	-- one line names it and the rest are marked as covered.
	local best: string? = nil
	for _, entry in payload.fleet do
		local can = entry.unlocked and entry.owned == 0 and payload.as >= entry.cost
		if can and not tierAnnounced[entry.id] then
			best = entry.id
		end
	end
	if not tiersPrimed then
		for _, entry in payload.fleet do
			if entry.unlocked and entry.owned == 0 and payload.as >= entry.cost then
				tierAnnounced[entry.id] = true
			end
		end
		tiersPrimed = true
	elseif best ~= nil then
		local tier = DroneRegistry.get(best)
		local spoke = speak(function()
			Notifications.push(
				if tier ~= nil
					then string.format("%s is affordable in FLEET.", tier.name)
					else "A new drone type is affordable in FLEET.",
				"good"
			)
			Sfx.coin()
		end)
		if spoke then
			for _, entry in payload.fleet do
				if entry.unlocked and entry.owned == 0 and payload.as >= entry.cost then
					tierAnnounced[entry.id] = true
				end
			end
		end
	end
end

function Nudges.init()
	buildGates()
	tierAnnounced = {}
	tiersPrimed = false
	nextSpeakAt = 0
	unsubscribe = StateStore.onSync(evaluate)
end

--- Called by the guide's run state. The guide is already pointing at the same
--- controls, so a nudge would be a second voice. Unpausing leaves a beat for
--- the guide's completion receipt before the first hint looks for the rail.
function Nudges.setPaused(value: boolean)
	paused = value
	if not value then
		nextSpeakAt = math.max(nextSpeakAt, os.clock() + 1.2)
	end
end

function Nudges.isPaused(): boolean
	return paused
end

function Nudges.destroy()
	if unsubscribe then
		unsubscribe()
		unsubscribe = nil
	end
	gates = {}
	tierAnnounced = {}
	tiersPrimed = false
	nextSpeakAt = 0
	paused = true
end

return Nudges
