--!strict
-- Copy grouping for the blade vault.
--
-- The server stores one entry per forged copy, because duplicates are real
-- inventory (they are the Scrap economy's fuel and the trade stock). The UI
-- groups them: a player who owns four Standard Rusted Cleavers owns one
-- *thing* with four copies, and painting four identical cards would bury every
-- other blade they own.
--
-- The key includes the modifier axes. It has to: a Transcendent Ember Cleaver
-- and a Chipped one are different objects with different multipliers, and the
-- old `id|variant` key would fold them into one card and report whichever copy
-- happened to be first. With modifiers a "blade" is a five-axis identity, and
-- the vault shows exactly that.
--
-- Grouping lives here rather than inside the view so the vault grid, the detail
-- drawer and the roll stage all agree on what "the same blade" means.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local BladeRegistry = require(Shared:WaitForChild("BladeRegistry"))
local ForgeConfig = require(Shared:WaitForChild("ForgeConfig"))
local ModifierConfig = require(Shared:WaitForChild("ModifierConfig"))
local Types = require(Shared:WaitForChild("Types"))

local Theme = require(script.Parent.Theme)

local InventoryModel = {}

export type Group = {
	key: string,
	id: string,
	variant: string,
	--- Modifier axes. Empty string means "no axis", which is what a schema-6
	--- copy and a clean roll both look like.
	element: string,
	grade: string,
	prefix: string,
	suffix: string,
	--- "Molten Rusted Cleaver of Ruin", recomputed once per group.
	displayName: string,
	--- "Transcendent Ember", or "Unmarked" when no axis is set.
	condition: string,
	elementColor: Color3,
	--- Every copy uid in the group, sorted. `repUid` is the copy the actions use:
	--- the equipped one when the group holds it, otherwise the first.
	uids: { string },
	count: number,
	repUid: string,
	--- Newest copy's forge stamp, for the drawer's "forged" line.
	forgedAt: number,
	power: number,
	blade: BladeRegistry.Blade,
	variantInfo: ForgeConfig.Variant,
}

--- Position of a variant in the rarity ladder, 1 = Standard. Used as the
--- tie-breaker when two groups have identical power.
function InventoryModel.variantRank(variantId: string): number
	for index, id in ForgeConfig.VariantOrder do
		if id == variantId then
			return index
		end
	end
	return 1
end

--- Identity of one copy across all five axes. Every consumer that needs a
--- stable grouping key calls this rather than rebuilding the format string.
function InventoryModel.keyOf(entry: Types.InvEntry): string
	return string.format(
		"%s|%s|%s|%s|%s|%s",
		entry.id,
		entry.variant,
		entry.grade or "",
		entry.element or "",
		entry.prefix or "",
		entry.suffix or ""
	)
end

--- Groups a flat copy list into display rows, strongest first.
function InventoryModel.group(entries: { Types.InvEntry }, equippedUid: string): { Group }
	local map: { [string]: Group } = {}
	local order: { string } = {}

	for _, entry in entries do
		local blade = BladeRegistry.get(entry.id)
		if blade == nil then
			continue
		end
		local key = InventoryModel.keyOf(entry)
		local group = map[key]
		if group == nil then
			local grade = entry.grade or ""
			local element = entry.element or ""
			local prefix = entry.prefix or ""
			local suffix = entry.suffix or ""
			group = {
				key = key,
				id = entry.id,
				variant = entry.variant,
				element = element,
				grade = grade,
				prefix = prefix,
				suffix = suffix,
				displayName = ModifierConfig.displayName(blade.name, prefix, suffix),
				condition = ModifierConfig.condition(grade, element),
				elementColor = if element ~= ""
					then ModifierConfig.element(element).color
					else Theme.Color.textDim,
				uids = {},
				count = 0,
				repUid = entry.uid,
				power = ForgeConfig.powerCopy(entry),
				forgedAt = entry.forgedAt or 0,
				blade = blade,
				variantInfo = ForgeConfig.variant(entry.variant),
			}
			map[key] = group
			table.insert(order, key)
		end
		table.insert(group.uids, entry.uid)
		group.count += 1
		group.forgedAt = math.max(group.forgedAt, entry.forgedAt or 0)
	end

	local out: { Group } = {}
	for _, key in order do
		local group = map[key]
		if group == nil then
			continue
		end
		table.sort(group.uids)
		group.repUid = group.uids[1]
		for _, uid in group.uids do
			if uid == equippedUid then
				group.repUid = uid
				break
			end
		end
		table.insert(out, group)
	end

	table.sort(out, function(a: Group, b: Group): boolean
		if a.power ~= b.power then
			return a.power > b.power
		end
		local rankA = InventoryModel.variantRank(a.variant)
		local rankB = InventoryModel.variantRank(b.variant)
		if rankA ~= rankB then
			return rankA > rankB
		end
		if a.displayName ~= b.displayName then
			return a.displayName < b.displayName
		end
		return a.key < b.key
	end)

	return out
end

--- Every uid in `groups` that may legally be melted: not the equipped copy, not
--- a favorite, and never the player's last copy. Mirrors the server rule so the
--- footer count matches what the server will actually accept.
function InventoryModel.meltable(
	groups: { Group },
	selected: { [string]: boolean },
	equippedUid: string,
	totalCopies: number,
	favorites: { [string]: boolean }?
): { string }
	local uids: { string } = {}
	local reserved = math.max(totalCopies, 1)
	for _, group in groups do
		if not selected[group.key] then
			continue
		end
		for _, uid in group.uids do
			if uid == equippedUid or reserved <= 1 then
				continue
			end
			if favorites and favorites[uid] then
				continue
			end
			table.insert(uids, uid)
			reserved -= 1
		end
	end
	return uids
end

--- Scrap a selection is worth, using the same table the server pays from.
function InventoryModel.meltValue(
	groups: { Group },
	selected: { [string]: boolean },
	equippedUid: string,
	totalCopies: number,
	favorites: { [string]: boolean }?
): number
	local total = 0
	local uids = InventoryModel.meltable(groups, selected, equippedUid, totalCopies, favorites)
	local byUid: { [string]: Group } = {}
	for _, group in groups do
		for _, uid in group.uids do
			byUid[uid] = group
		end
	end
	for _, uid in uids do
		local group = byUid[uid]
		if group then
			total += ForgeConfig.salvageValue(
				group.id,
				group.variant,
				group.element,
				group.grade,
				group.prefix,
				group.suffix
			)
		end
	end
	return total
end

return InventoryModel
