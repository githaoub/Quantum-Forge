--!strict
-- Monetization. Every grant is server-verified and idempotent.
--
-- Placeholder IDs are 0, and MarketplaceService does not accept 0. Each entry
-- point checks `enabled` and a non-zero ID so shipping with placeholders is
-- safe: prompts no-op instead of throwing.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MonetizationConfig = require(Shared:WaitForChild("MonetizationConfig"))
local Types = require(Shared:WaitForChild("Types"))

local DataManager = require(script.Parent.DataManager)
local Net = require(script.Parent.Net)
local ProgressionService = require(script.Parent.ProgressionService)

local MonetizationService = {}

-- Receipts already granted this session. Roblox can re-deliver a receipt
-- during a retry; granting twice is a real money bug, not a theoretical one.
local grantedReceipts: { [string]: boolean } = {}

-- Structural mirror of MarketplaceService's ProcessReceipt argument. Declared
-- locally rather than reaching for the engine struct: Luau only resolves one
-- level of module type export, so a dotted path does not parse.
export type Receipt = {
	PlayerId: number,
	ProductId: number,
	PurchaseId: string,
	CurrencySpent: number,
	PlaceIdWherePurchased: number,
}

local function isConfiguredPass(def: MonetizationConfig.PassDef): boolean
	return def.enabled and def.id ~= 0
end

local function isConfiguredProduct(def: MonetizationConfig.ProductDef): boolean
	return def.enabled and def.id ~= 0
end

-- ---------------------------------------------------------------------------
-- Game passes
-- ---------------------------------------------------------------------------

local function grantPass(state: Types.ProfileState, key: string)
	state.passes[key] = true
end

--- VIP is a bundle, not a badge. Every path that grants it runs this, so a
--- player who buys VIP mid-session gets the other passes immediately instead of
--- waiting for the next join.
local function grantVipBundle(state: Types.ProfileState)
	for key, def in MonetizationConfig.Passes do
		if key ~= "vipAura" and isConfiguredPass(def) and not state.passes[key] then
			grantPass(state, key)
		end
	end
end

--- Re-checks pass ownership on join. This is the authority — a client claiming a
--- pass it does not own is ignored entirely.
---
--- VIP is a bundle, not a badge: owning it grants every other configured pass.
--- That has to happen here rather than as five separate ownership checks,
--- because a player who buys VIP later must not be asked to buy Fast Forge on
--- top of it. The expansion runs after the individual checks so a revoked pass
--- still grants through VIP while VIP itself is owned.
local function refreshPasses(player: Player)
	local state = DataManager.get(player)
	if not state then
		return
	end

	for key, def in MonetizationConfig.Passes do
		if not isConfiguredPass(def) then
			continue
		end
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, def.id)
		end)
		if ok and owns then
			if not state.passes[key] then
				grantPass(state, key)
				DataManager.markDirty(player)
			end
		end
	end

	if state.passes.vipAura then
		grantVipBundle(state)
		DataManager.markDirty(player)
	end
end

-- ---------------------------------------------------------------------------
-- Developer products
-- ---------------------------------------------------------------------------

local function grantProduct(player: Player, key: string): boolean
	local state = DataManager.get(player)
	if not state then
		return false
	end

	local now = os.time()

	if key == "instantOverdrive" then
		-- Stacks on an active boost rather than replacing it.
		local base = math.max(now, state.overdriveUntil)
		state.overdriveUntil = base + MonetizationConfig.OverdriveSeconds
	elseif key == "starterForge" then
		ProgressionService.addAether(state, MonetizationConfig.StarterAether)
		local base = math.max(now, state.boostX2Until)
		state.boostX2Until = base + MonetizationConfig.StarterSeconds
	elseif key == "instantVent" then
		-- Retired from the storefront, kept for receipts already in flight.
		state.heat = 0
		state.streak = 0
	elseif key == "expressSalvage" then
		-- Only meaningful with a mission out; the clock is moved, not the payout,
		-- so the ordinary settle path still pays it.
		if state.expedition.id == "" then
			return false
		end
		state.expedition.endsAt = now
	else
		return false
	end

	DataManager.markDirty(player)
	Net.sendEvent(player, { kind = "toast", text = "Purchase applied" })
	return true
end

--- Retired products still need a receipt path: Roblox retries an unconsumed
--- receipt forever, and a delisted item would otherwise land on the unknown-id
--- branch and never settle. The effect is honoured; only the shop row is gone.
local RETIRED_PRODUCTS: { [number]: string } = {
	[3730425432] = "instantVent",
}

local function onProcessReceipt(receipt: Receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		-- Player left mid-purchase: do not consume the receipt, let Roblox retry
		-- into a session where we can grant it.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local key = MonetizationConfig.productById(receipt.ProductId)
	if key == nil then
		key = RETIRED_PRODUCTS[receipt.ProductId]
	end
	if key == nil then
		warn(string.format("[Monetization] unknown product id %d", receipt.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if grantedReceipts[receipt.PurchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	if not grantProduct(player, key) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	grantedReceipts[receipt.PurchaseId] = true
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function MonetizationService.init()
	MarketplaceService.ProcessReceipt = onProcessReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
		if not wasPurchased then
			return
		end
		local key, def = MonetizationConfig.passByid(passId)
		if key == nil or def == nil then
			return
		end
		local state = DataManager.get(player)
		if not state then
			return
		end
		grantPass(state, key)
		if key == "vipAura" then
			grantVipBundle(state)
		end
		DataManager.markDirty(player)
		Net.sendEvent(player, { kind = "toast", text = string.format("%s unlocked", def.name) })
	end)

	Players.PlayerAdded:Connect(function(player)
		-- Small delay so the profile is loaded before we touch it.
		task.delay(3, function()
			if player.Parent then
				refreshPasses(player)
			end
		end)
	end)

	-- The first player may already be in before this module initialises.
	for _, player in Players:GetPlayers() do
		task.spawn(refreshPasses, player)
	end
end

--- Client asks to open a purchase prompt. Validated here so the client cannot
--- prompt for arbitrary IDs.
function MonetizationService.requestPrompt(player: Player, kind: string, key: string): boolean
	if kind == "pass" then
		local def = MonetizationConfig.Passes[key]
		if def == nil or not isConfiguredPass(def) then
			return false
		end
		MarketplaceService:PromptGamePassPurchase(player, def.id)
		return true
	elseif kind == "product" then
		local def = MonetizationConfig.Products[key]
		if def == nil or not isConfiguredProduct(def) then
			return false
		end
		MarketplaceService:PromptProductPurchase(player, def.id)
		return true
	end
	return false
end

return MonetizationService
