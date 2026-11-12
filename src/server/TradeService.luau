--!strict
-- Player-to-player trading: blades and Aether, both sides confirmed.
--
-- The security model is the whole feature, because a trade UI that trusts either
-- client is a dupe. Rules:
--
--   * a request is an *invite*, not a session: nothing exists until the target
--     answers ACCEPT, and an invite that times out leaves no state behind;
--   * a session names exactly two online players;
--   * each side's offer is submitted by that side only, validated against that
--     player's own profile, and re-validated at commit;
--   * offered uids are locked out of melting and rerolling for the duration
--     (`ProgressionService.setTradeLocks`), so the classic "offer then melt"
--     scam has nothing to land on;
--   * every copy is offerable, including the equipped one and favorites, but a
--     trade cannot empty a vault: at least one blade has to remain;
--   * any change to either offer clears both accept flags;
--   * commit is atomic within one server tick: remove both sides, mint both
--     sides, transfer the Aether delta, bump both inventory revisions.
--
-- Bounded on purpose: eight copies per side, one Aether amount, twenty seconds
-- to answer a request, four minutes before an idle session expires. A trade is a
-- conversation, not a bank.

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BladeRegistry = require(Shared:WaitForChild("BladeRegistry"))
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))

local DataManager = require(script.Parent.DataManager)
local Net = require(script.Parent.Net)
local ProgressionService = require(script.Parent.ProgressionService)

local TradeService = {}

local MAX_BLADES = 8
local SESSION_SECONDS = 240
local INVITE_SECONDS = 20

type Offer = {
	blades: { string },
	aether: number,
	accepted: boolean,
}

type Session = {
	a: Player,
	b: Player,
	offerA: Offer,
	offerB: Offer,
	startedAt: number,
}

type Invite = {
	from: Player,
	to: Player,
	startedAt: number,
}

local sessions: { [string]: Session } = {}
local byPlayer: { [Player]: string } = {}
-- One incoming invite per player and one outgoing invite per player. Keyed by
-- the person being asked and the person asking respectively, so a lookup on
-- either side is O(1) and neither map can hold a duplicate.
local invites: { [Player]: Invite } = {}
local inviting: { [Player]: Invite } = {}
local mintSerial = 0

local function pairKey(a: Player, b: Player): string
	local left = math.min(a.UserId, b.UserId)
	local right = math.max(a.UserId, b.UserId)
	return string.format("%d:%d", left, right)
end

local function emptyOffer(): Offer
	return { blades = {}, aether = 0, accepted = false }
end

local function sessionOf(player: Player): Session?
	local key = byPlayer[player]
	if key == nil then
		return nil
	end
	return sessions[key]
end

local function otherIn(session: Session, player: Player): Player
	return if session.a == player then session.b else session.a
end

local function offerOf(session: Session, player: Player): Offer
	return if session.a == player then session.offerA else session.offerB
end

local function tell(player: Player, text: string)
	Net.sendEvent(player, { kind = "toast", text = text })
end

local function clearLocks(session: Session)
	ProgressionService.clearTradeLocks(session.a)
	ProgressionService.clearTradeLocks(session.b)
end

local function cancel(session: Session, reason: string?)
	local key = pairKey(session.a, session.b)
	sessions[key] = nil
	byPlayer[session.a] = nil
	byPlayer[session.b] = nil
	clearLocks(session)
	if reason then
		tell(session.a, reason)
		tell(session.b, reason)
	end
end

-- ---------------------------------------------------------------------------
-- Invites
-- ---------------------------------------------------------------------------

local function clearInvite(invite: Invite)
	if invites[invite.to] == invite then
		invites[invite.to] = nil
	end
	if inviting[invite.from] == invite then
		inviting[invite.from] = nil
	end
end

local function dropInvitesFor(player: Player)
	local incoming = invites[player]
	if incoming then
		clearInvite(incoming)
	end
	local outgoing = inviting[player]
	if outgoing then
		clearInvite(outgoing)
	end
end

local function beginSession(a: Player, b: Player)
	dropInvitesFor(a)
	dropInvitesFor(b)

	local session: Session = {
		a = a,
		b = b,
		offerA = emptyOffer(),
		offerB = emptyOffer(),
		startedAt = os.clock(),
	}
	local key = pairKey(a, b)
	sessions[key] = session
	byPlayer[a] = key
	byPlayer[b] = key

	-- The event opens the desk on both clients. A toast alone would leave the
	-- trader hunting for the panel after the other side said yes.
	Net.sendEvent(a, { kind = "tradeStarted", name = b.Name })
	Net.sendEvent(b, { kind = "tradeStarted", name = a.Name })
end

--- Every copy a player owns, equipped and favorites included. The picker must
--- show the whole vault; the equipped or favorited state is a warning chip, not
--- a reason to hide a copy. `commit` re-equips the best remaining blade when the
--- equipped one leaves.
function TradeService.tradeable(player: Player): { Types.InvEntry }
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
	table.sort(entries, function(a: Types.InvEntry, b: Types.InvEntry): boolean
		return (a.forgedAt or 0) > (b.forgedAt or 0)
	end)
	return entries
end

--- Online players a request can target. `trades` is the target's privacy flag
--- mirrored to the requester so the ASK key can read OFF before the press
--- round-trips, and `busy` hides a partner who is already in a session.
function TradeService.playersFor(player: Player): { any }
	local rows = {}
	for _, candidate in Players:GetPlayers() do
		if candidate == player then
			continue
		end
		local state = DataManager.get(candidate)
		if state == nil then
			continue
		end
		local copies = 0
		for _ in state.blades do
			copies += 1
		end
		rows[#rows + 1] = {
			id = candidate.UserId,
			name = candidate.Name,
			blades = copies,
			trades = state.settings.trades ~= false,
			busy = sessionOf(candidate) ~= nil,
			pending = invites[candidate] ~= nil,
		}
	end
	table.sort(rows, function(a: any, b: any): boolean
		return a.name < b.name
	end)
	return rows
end

--- Sends an invite. No session is created here: the target's ACCEPT is the
--- thing that opens the desk, which is why an ignored request costs nothing.
function TradeService.request(player: Player, targetUserId: unknown): (boolean, string?)
	if type(targetUserId) ~= "number" then
		return false, "Pick a player"
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if target == nil then
		return false, "That player is not here"
	end
	if target == player then
		return false, "You cannot trade with yourself"
	end
	local state = DataManager.get(player)
	local targetState = DataManager.get(target)
	if state == nil or targetState == nil then
		return false, "Profiles still loading"
	end
	if targetState.settings.trades == false then
		return false, "Unavailable for trade."
	end
	if sessionOf(player) then
		return false, "You are already in a trade"
	end
	if sessionOf(target) then
		return false, "They are already in a trade"
	end

	local existing = invites[target]
	if existing then
		if existing.from == player then
			-- Pressing ASK twice is impatience, not an error: the request is
			-- already on their screen and the clock is already running.
			return true, nil
		end
		return false, "They already have a trade request open"
	end
	if inviting[player] then
		return false, "Wait for your open request"
	end

	local invite: Invite = { from = player, to = target, startedAt = os.clock() }
	invites[target] = invite
	inviting[player] = invite

	Net.sendEvent(target, {
		kind = "tradeInvite",
		id = player.UserId,
		name = player.Name,
		seconds = INVITE_SECONDS,
	})
	tell(player, string.format("Trade request sent to %s.", target.Name))
	return true, nil
end

--- The target's answer. `accept == true` opens the session; anything else is a
--- decline, and both paths clear the invite so it cannot be replayed.
function TradeService.respond(player: Player, fromUserId: unknown, accept: unknown): (boolean, string?)
	if type(fromUserId) ~= "number" then
		return false, "Bad request"
	end
	local invite = invites[player]
	if invite == nil or invite.from.UserId ~= fromUserId then
		return false, "That request is no longer open"
	end
	local from = invite.from
	clearInvite(invite)

	if accept ~= true then
		tell(from, string.format("%s declined your trade request.", player.Name))
		return true, nil
	end

	if from.Parent == nil then
		return false, "They left"
	end
	if DataManager.get(from) == nil or DataManager.get(player) == nil then
		return false, "Profiles still loading"
	end
	if sessionOf(from) or sessionOf(player) then
		return false, "One of you is already trading"
	end

	beginSession(from, player)
	return true, nil
end

function TradeService.setOffer(player: Player, uids: unknown, aether: unknown): (boolean, string?)
	local session = sessionOf(player)
	if session == nil then
		return false, "No trade open"
	end
	local state = DataManager.get(player)
	if state == nil then
		return false, "Profile not loaded"
	end
	if type(uids) ~= "table" then
		return false, "Bad offer"
	end

	local requested: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, raw in uids :: { any } do
		if type(raw) ~= "string" or seen[raw] then
			continue
		end
		seen[raw] = true
		table.insert(requested, raw)
		if #requested >= MAX_BLADES then
			break
		end
	end

	for _, uid in requested do
		if state.blades[uid] == nil then
			return false, "You no longer own that blade"
		end
	end

	local requestedAether = 0
	if type(aether) == "number" and aether == aether and aether > 0 then
		requestedAether = math.min(math.floor(aether), math.floor(state.aether))
	end

	local offer = offerOf(session, player)
	offer.blades = requested
	offer.aether = requestedAether
	offer.accepted = false
	session.offerA.accepted = false
	session.offerB.accepted = false
	ProgressionService.setTradeLocks(player, requested)

	local target = otherIn(session, player)
	tell(target, string.format("%s changed their side of the trade.", player.Name))
	return true, nil
end

local function copyInto(player: Player, incoming: { string }, source: { [string]: Types.BladeInstance }): number
	local state = DataManager.get(player)
	if state == nil then
		return 0
	end
	local count = 0
	for _, uid in incoming do
		local instance = source[uid]
		if instance == nil then
			continue
		end
		count += 1
		mintSerial += 1
		local minted = string.format("trade_%d_%d_%d", os.time(), player.UserId, mintSerial)
		state.blades[minted] = {
			id = instance.id,
			variant = instance.variant,
			forgedAt = os.time(),
			element = instance.element,
			grade = instance.grade,
			prefix = instance.prefix,
			suffix = instance.suffix,
		}
		ProgressionService.markCodex(state, state.blades[minted])
	end
	return count
end

--- Atomically exchanges both offers. Every check runs before the first mutation:
--- a failed trade must leave both profiles exactly as they were.
local function commit(session: Session): (boolean, string?)
	local a = session.a
	local b = session.b
	local stateA = DataManager.get(a)
	local stateB = DataManager.get(b)
	if stateA == nil or stateB == nil then
		return false, "One side left"
	end

	local offerA = session.offerA
	local offerB = session.offerB
	local aetherA = math.min(offerA.aether, math.floor(stateA.aether))
	local aetherB = math.min(offerB.aether, math.floor(stateB.aether))

	for _, uid in offerA.blades do
		if stateA.blades[uid] == nil then
			return false, "Your offer is no longer valid"
		end
	end
	for _, uid in offerB.blades do
		if stateB.blades[uid] == nil then
			return false, "Their offer is no longer valid"
		end
	end
	if #offerA.blades == 0 and #offerB.blades == 0 and aetherA == 0 and aetherB == 0 then
		return false, "Both sides are empty"
	end

	-- Receiving more than you give can overflow the vault. Check the post-trade
	-- count on both sides before touching anything.
	local function copiesOf(state: Types.ProfileState): number
		local total = 0
		for _ in state.blades do
			total += 1
		end
		return total
	end
	local afterA = copiesOf(stateA) - #offerA.blades + #offerB.blades
	local afterB = copiesOf(stateB) - #offerB.blades + #offerA.blades
	if afterA > Config.InventoryMax or afterB > Config.InventoryMax then
		return false, "Vault space: melt a blade first"
	end
	if afterA < 1 or afterB < 1 then
		return false, "Keep at least one blade"
	end

	local movingA = table.clone(offerA.blades)
	local movingB = table.clone(offerB.blades)
	local equippedA = stateA.equippedUid
	local equippedB = stateB.equippedUid
	local lostEquippedA = false
	local lostEquippedB = false
	for _, uid in movingA do
		if uid == equippedA then
			lostEquippedA = true
		end
	end
	for _, uid in movingB do
		if uid == equippedB then
			lostEquippedB = true
		end
	end

	-- Copy first, from the source maps, then remove. Doing it the other way loses
	-- the record before it has been read.
	copyInto(b, movingA, stateA.blades)
	copyInto(a, movingB, stateB.blades)

	for _, uid in movingA do
		stateA.blades[uid] = nil
		stateA.favorites[uid] = nil
	end
	for _, uid in movingB do
		stateB.blades[uid] = nil
		stateB.favorites[uid] = nil
	end

	stateA.aether = math.max(0, stateA.aether - aetherA + aetherB)
	stateB.aether = math.max(0, stateB.aether - aetherB + aetherA)

	stateA.invVersion += 1
	stateB.invVersion += 1

	-- The equipped copy can be part of the offer now. Put the best remaining
	-- blade in the hand rather than leaving a uid that no longer exists.
	if lostEquippedA then
		ProgressionService.equipBest(a)
	end
	if lostEquippedB then
		ProgressionService.equipBest(b)
	end

	DataManager.markDirty(a)
	DataManager.markDirty(b)

	Net.sendEvent(a, {
		kind = "trade",
		amount = aetherB,
		text = string.format("Trade complete: %d blades in, %d out, %+d Aether", #movingB, #movingA, aetherB - aetherA),
	})
	Net.sendEvent(b, {
		kind = "trade",
		amount = aetherA,
		text = string.format("Trade complete: %d blades in, %d out, %+d Aether", #movingA, #movingB, aetherA - aetherB),
	})
	return true, nil
end

function TradeService.accept(player: Player): (boolean, string?)
	local session = sessionOf(player)
	if session == nil then
		return false, "No trade open"
	end
	local offer = offerOf(session, player)
	offer.accepted = true
	local target = otherIn(session, player)
	local theirs = offerOf(session, target)
	if not theirs.accepted then
		tell(target, string.format("%s accepted. Your move.", player.Name))
		return true, nil
	end

	local ok, reason = commit(session)
	if not ok then
		cancel(session, reason)
		return false, reason
	end
	cancel(session, nil)
	return true, reason
end

function TradeService.decline(player: Player): boolean
	local session = sessionOf(player)
	if session == nil then
		return false
	end
	cancel(session, string.format("%s closed the trade.", player.Name))
	return true
end

--- Wire summary for the trade panel. `nil` when the player is not trading.
function TradeService.stateFor(player: Player): { [string]: any }?
	local session = sessionOf(player)
	if session == nil then
		return nil
	end
	local state = DataManager.get(player)
	if state == nil then
		return nil
	end
	local target = otherIn(session, player)
	local mine = offerOf(session, player)
	local theirs = offerOf(session, target)
	local theirsState = DataManager.get(target)

	local function summarize(uids: { string }, source: Types.ProfileState?): { any }
		local rows = {}
		for _, uid in uids do
			local instance = if source then source.blades[uid] else nil
			if instance then
				local blade = BladeRegistry.get(instance.id)
				rows[#rows + 1] = {
					uid = uid,
					id = instance.id,
					name = if blade then blade.name else instance.id,
					variant = instance.variant,
					element = instance.element or "",
					grade = instance.grade or "",
					prefix = instance.prefix or "",
					suffix = instance.suffix or "",
				}
			end
		end
		return rows
	end

	return {
		target = target.Name,
		targetId = target.UserId,
		myBlades = summarize(mine.blades, state),
		theirBlades = summarize(theirs.blades, theirsState),
		myAether = mine.aether,
		theirAether = theirs.aether,
		myAccepted = mine.accepted,
		theirAccepted = theirs.accepted,
		aetherOwned = math.floor(state.aether),
		expiresIn = math.max(0, math.floor(SESSION_SECONDS - (os.clock() - session.startedAt))),
	}
end

function TradeService.onLeave(player: Player)
	dropInvitesFor(player)

	local session = sessionOf(player)
	if session then
		cancel(session, string.format("%s left. Trade cancelled.", player.Name))
	end
end

--- Expires invites nobody answered and sessions nobody is using. A trade that
--- sits open for four minutes is a stale offer, and a stale offer is a trap for
--- the other player.
function TradeService.step()
	local now = os.clock()

	local expired: { Invite } = {}
	for _, invite in invites do
		if now - invite.startedAt > INVITE_SECONDS then
			table.insert(expired, invite)
		end
	end
	for _, invite in expired do
		clearInvite(invite)
		tell(invite.from, string.format("%s did not answer.", invite.to.Name))
	end

	for _, session in sessions do
		if now - session.startedAt > SESSION_SECONDS then
			cancel(session, "Trade expired.")
		end
	end
end

return TradeService
