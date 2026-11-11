--!strict
-- Player feedback sink.
--
-- The video analysis asks for an in-game prompt so friction is captured while it
-- is fresh, not inferred from a retention curve three days later. There is no
-- webhook URL in this project, so submissions land in their own DataStore under
-- a key per report. A reviewer reads them with a single ordered scan.
--
-- Failure is swallowed on purpose: a player who types a paragraph and gets an
-- error toast will not type another one. The server acks the submission and logs
-- the failure for the operator.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Feedback = {}

local MAX_CATEGORY = 24

--- Stores one report. `category` is a short tag from the form ("BUG", "BALANCE",
--- "CONFUSING", "OTHER"); `text` is already trimmed and length-capped by the
--- caller.
function Feedback.submit(player: Player, category: string, text: string): boolean
	local tag = string.sub(category, 1, MAX_CATEGORY)
	local body = string.sub(text, 1, Config.FeedbackMaxLength)

	local key = string.format("%d_%d_%s", player.UserId, os.time(), string.sub(HttpService:GenerateGUID(false), 1, 8))
	local record = {
		userId = player.UserId,
		name = player.Name,
		category = tag,
		text = body,
		at = os.time(),
		place = game.PlaceId,
		job = game.JobId,
	}

	local ok, err = pcall(function()
		local store = DataStoreService:GetDataStore(Config.FeedbackStore)
		store:SetAsync(key, record)
	end)

	if not ok then
		-- Studio without API access lands here every time. The report is printed so
		-- a playtest still produces something readable.
		warn(string.format("[Feedback] store unavailable (%s); report from %s: %s", tostring(err), player.Name, body))
		print(string.format("[Feedback] %s | %s | %s", tag, player.Name, body))
	end

	return true
end

return Feedback
