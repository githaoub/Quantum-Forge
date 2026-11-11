--!strict
-- Loads the uploaded blade meshes into ReplicatedStorage so clients can clone
-- them into viewports.
--
-- Why the server and not the client: `InsertService:LoadAsset` is server-only,
-- and it is also the only way to get an *uploaded Model* (`.fbx` -> MeshPart).
-- A MeshPart cannot be built from a manifest alone: the asset id in
-- `AssetManifest.Meshes` points at a Model, and the MeshId sits one level
-- deeper, inside it. Loading on the server means twenty-five assets are fetched
-- once per server and replicated, instead of once per client.
--
-- Everything here is best-effort. If the folder is empty, or a single asset
-- fails to load, `BladePreview` falls back to building the blade from
-- primitives — which is exactly what happens today with zero uploads. A mesh is
-- an upgrade, never a dependency.

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local AssetManifest = require(Shared:WaitForChild("AssetManifest"))

local MeshService = {}

local folder: Folder? = nil

local function log(message: string)
	if Config.Debug then
		print(string.format("[mesh] %s", message))
	end
end

--- `rbxassetid://135997993212983` -> 135997993212983. Returns nil for the
--- placeholder, so an un-uploaded manifest is a no-op rather than a bad request.
local function assetNumber(id: string): number?
	local digits = string.match(id, "(%d+)$")
	if digits == nil then
		return nil
	end
	local number = tonumber(digits)
	if number == nil or number == 0 then
		return nil
	end
	return number
end

local function ensureFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild(Config.MeshFolder)
	if existing ~= nil and existing:IsA("Folder") then
		folder = existing
		return existing
	end

	local created = Instance.new("Folder")
	created.Name = Config.MeshFolder
	created.Parent = ReplicatedStorage
	folder = created
	return created
end

--- Anchors and detaches every part. A loaded Model arrives with physics
--- properties set for the workspace; inside a ViewportFrame it must not fall,
--- collide, or be raycast against.
local function sanitise(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CastShadow = false
			-- Imported plastic reads as flat grey. The registry colour is what the
			-- contact sheet used and what the primitive blades use, so the mesh
			-- path should not grey out the catalogue.
			if descendant:IsA("MeshPart") then
				descendant.Material = Enum.Material.SmoothPlastic
			end
		end
	end
end

local function loadOne(target: Folder, bladeId: string): boolean
	local entry = AssetManifest.mesh(bladeId)
	if entry == nil then
		return false
	end

	local number = assetNumber(entry.id)
	if number == nil then
		return false
	end

	-- `InsertService:LoadAsset` yields on a network round-trip, so the folder
	-- check has to happen before the call and again after it: two servers never
	-- race here, but one server can finish while another load for the same id is
	-- still in flight if a retry is added later.
	if target:FindFirstChild(bladeId) ~= nil then
		return true
	end

	local ok, result = pcall(InsertService.LoadAsset, InsertService, number)
	if not ok then
		warn(string.format("[mesh] %s failed to load: %s", bladeId, tostring(result)))
		return false
	end
	if not result:IsA("Model") then
		result:Destroy()
		warn(string.format("[mesh] %s returned %s, not a Model", bladeId, result.ClassName))
		return false
	end

	-- The uploaded wrapper is named after the asset. The client looks meshes up
	-- by registry id, so the name has to be the key, not the display name.
	result.Name = bladeId
	sanitise(result)
	if target:FindFirstChild(bladeId) ~= nil then
		result:Destroy()
		return true
	end
	result.Parent = target
	return true
end

--- Blade ids in the manifest that actually have an uploaded asset.
local function pendingIds(): { string }
	local ids: { string } = {}
	for bladeId in AssetManifest.Meshes do
		if AssetManifest.mesh(bladeId) ~= nil then
			table.insert(ids, bladeId)
		end
	end
	table.sort(ids)
	return ids
end

--- Starts the background load. Returns immediately: boot must not wait on
--- twenty-five asset downloads, and the viewport renders primitives in the
--- meantime.
---
--- Four at a time. `LoadAsset` is a web round-trip (~1.4s measured, sequential
--- total was ~35s), so a serial loop means most of the first minute of play runs
--- on primitive blades. Four workers bring it under ten seconds without turning
--- a server boot into twenty-five simultaneous requests.
local CONCURRENCY = 4

function MeshService.init()
	if RunService:IsClient() then
		return
	end

	local target = ensureFolder()
	local ids = pendingIds()
	if #ids == 0 then
		log("no uploaded meshes; blades stay primitive-built")
		return
	end

	task.spawn(function()
		local started = os.clock()
		local loaded = 0
		local nextIndex = 0
		local remaining = math.min(CONCURRENCY, #ids)

		local function worker()
			while true do
				nextIndex += 1
				local bladeId = ids[nextIndex]
				if bladeId == nil then
					break
				end
				if loadOne(target, bladeId) then
					loaded += 1
				end
			end
			remaining -= 1
		end

		for _ = 1, math.min(CONCURRENCY, #ids) do
			task.spawn(worker)
		end

		-- The last worker out reports, so the log is one line instead of a race.
		while remaining > 0 do
			task.wait(0.2)
		end

		if loaded < #ids then
			warn(string.format("[mesh] %d/%d blade models loaded; the rest stay primitive-built", loaded, #ids))
		end
		log(string.format("%d/%d blade models ready in %.1fs", loaded, #ids, os.clock() - started))
	end)
end

--- The folder, creating it if the load has not started. Clients never call
--- this; exported for tests and for a future editor-time preview.
function MeshService.getFolder(): Folder
	if folder ~= nil then
		return folder
	end
	return ensureFolder()
end

return MeshService
