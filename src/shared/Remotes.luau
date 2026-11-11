--!strict
-- Thin typed access layer over the Remotes folder.
--
-- The server creates every remote at boot (see server/Net.luau). Clients wait
-- with a timeout so a missing remote degrades to a readable warning instead of
-- an infinite yield inside a UI callback.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

local WAIT_TIMEOUT = 10

local function folder(): Instance
	return ReplicatedStorage:WaitForChild("Remotes")
end

--- Server-side: returns the existing remote, asserting rather than creating so
--- a typo fails loudly at boot instead of silently making a new remote.
function Remotes.get(name: string): Instance
	local found = folder():FindFirstChild(name)
	assert(found, string.format("Remote '%s' was never created by the server", name))
	return found
end

--- True when the folder has already replicated, so a caller that must not yield
--- (the UI boot path) can branch instead of blocking on a WaitForChild.
function Remotes.ready(): boolean
	return ReplicatedStorage:FindFirstChild("Remotes") ~= nil
end

--- The remote if it is already there, without yielding. Used to decide whether a
--- caller can connect inline or has to defer to a background thread.
function Remotes.peek(name: string): Instance?
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes == nil then
		return nil
	end
	return remotes:FindFirstChild(name)
end

--- Client-side: yields until the remote exists or the timeout expires.
function Remotes.wait(name: string): Instance?
	local remotes = ReplicatedStorage:WaitForChild("Remotes", WAIT_TIMEOUT)
	if not remotes then
		warn(string.format("[Remotes] folder never appeared; '%s' unavailable", name))
		return nil
	end
	local found = remotes:WaitForChild(name, WAIT_TIMEOUT)
	if not found then
		warn(string.format("[Remotes] '%s' never appeared", name))
		return nil
	end
	return found
end

--- Convenience casts. Strict typing makes the raw Instance return annoying at
--- every call site; these keep the casts in one place.
function Remotes.event(name: string): RemoteEvent?
	return Remotes.wait(name) :: RemoteEvent?
end

function Remotes.func(name: string): RemoteFunction?
	return Remotes.wait(name) :: RemoteFunction?
end

return Remotes
