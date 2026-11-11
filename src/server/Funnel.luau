--!strict
-- Progression funnel telemetry.
--
-- The video analysis is blunt about this: a game that cannot say where players
-- stop cannot fix it. Every milestone a player can fail to reach is one event,
-- logged once per session to `AnalyticsService`.
--
-- Why the server: `AnalyticsService:LogCustomEvent` refuses to run from a client
-- datamodel ("can only be executed on the game server"), so the event is logged
-- here, at the moment the economy actually changed. No remote hop, no second
-- dedupe table on the client.
--
-- Dedupe is per session. Persistent firsts already exist in the save (`blades`,
-- `drones`, `ascensions`); this table only stops a 10Hz tick from repeating the
-- same event inside one server lifetime.

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")

local Funnel = {}

local sent: { [Player]: { [string]: boolean } } = {}

--- Records a milestone. `value` rides along as the event's numeric payload, which
--- is what makes "Wave 2 reached at 4:12" readable in the dashboard.
function Funnel.log(player: Player, name: string, value: number?)
	if player == nil or player.Parent == nil then
		return
	end

	local set = sent[player]
	if set == nil then
		set = {}
		sent[player] = set
	end
	if set[name] then
		return
	end
	set[name] = true

	-- Studio playtests without a published place can refuse analytics; a funnel
	-- event is never allowed to break the action that produced it.
	pcall(function()
		AnalyticsService:LogCustomEvent(player, name, value or 1)
	end)
end

function Funnel.forget(player: Player)
	sent[player] = nil
end

--- Re-arms the session set. Called by the feedback form's "replay guide" path so
--- a tester can re-run onboarding and still see the funnel fire.
function Funnel.reset(player: Player)
	sent[player] = nil
end

Players.PlayerRemoving:Connect(function(player: Player)
	sent[player] = nil
end)

return Funnel
