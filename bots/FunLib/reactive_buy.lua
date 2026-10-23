-- Reactive itemization purchase mechanics (A3 hardening, design 2026-08-19).
-- Pure functions only: every engine dependency is injected so this file runs
-- under plain LuaJIT for tests. Glue lives in item_purchase_generic.lua.
local M = {}

-- Flatten a composite item into its basic purchasable parts. Recipes come
-- back from getComponents as items with no components, so they stay leaves.
-- getComponents(itemName) -> component list; returns {itemName} for basics.
function M.FlattenComponents(itemName, getComponents, nDepth, tOut)
	nDepth = nDepth or 0
	tOut = tOut or {}
	if nDepth > 4 then -- no real item nests deeper; guards a cyclic table
		tOut[#tOut + 1] = itemName
		return tOut
	end
	local tComps = getComponents(itemName)
	if #tComps == 0 or (#tComps == 1 and tComps[1] == itemName) then
		tOut[#tOut + 1] = itemName
		return tOut
	end
	for _, comp in ipairs(tComps) do
		M.FlattenComponents(comp, getComponents, nDepth + 1, tOut)
	end
	return tOut
end

-- Every component must be buyable where the bot stands, or the fallback
-- would half-build and stall on a secret-shop part.
function M.CanBuyComponentsNow(tComponents, isSecretShopItem, bAtSecretShop)
	for _, comp in ipairs(tComponents) do
		if isSecretShopItem(comp) and not bAtSecretShop then
			return false
		end
	end
	return true
end

-- Components still missing after subtracting what the bot already holds.
function M.MissingComponents(tComponents, ownedCounts)
	local remaining = {}
	for k, v in pairs(ownedCounts) do remaining[k] = v end
	local missing = {}
	for _, comp in ipairs(tComponents) do
		if (remaining[comp] or 0) > 0 then
			remaining[comp] = remaining[comp] - 1
		else
			missing[#missing + 1] = comp
		end
	end
	return missing
end

-- Which bot cores owe the team a lockdown answer to a right-click carry.
-- Deterministic from team-shared state (positions held by bots), so every
-- bot agrees without cross-VM state: mid first, then offlane, then carry
-- (the carry keeps its farming build unless humans hold mid/offlane).
-- tBotPositions: set of positions played by bots, e.g. { [2] = true }.
local tLockdownOrder = { 2, 3, 1 }
function M.IsLockdownBuyer(nMyPos, tBotPositions, nWanted)
	local nAssigned = 0
	for _, nPos in ipairs(tLockdownOrder) do
		if nAssigned >= nWanted then return false end
		if tBotPositions[nPos] then
			nAssigned = nAssigned + 1
			if nPos == nMyPos then return true end
		end
	end
	return false
end

-- STR cores disarm (Halberd), everyone else silences (Orchid: Battle
-- Trance, Shadow Dance and Phantom Strike can't be cast while silenced).
function M.LockdownItemFor(bStrength)
	return bStrength and 'item_heavens_halberd' or 'item_orchid'
end

-- Make itemName the next buy of a reverse-order purchase list (the LAST
-- entry is bought next). Later copies are removed so a counter that was
-- already planned is moved up, not bought twice. The interrupted target
-- stays directly below and resumes afterwards. Returns true if changed.
function M.QueueFront(tReverseList, itemName)
	if tReverseList[#tReverseList] == itemName then return false end
	for i = #tReverseList, 1, -1 do
		if tReverseList[i] == itemName then table.remove(tReverseList, i) end
	end
	tReverseList[#tReverseList + 1] = itemName
	return true
end

return M
