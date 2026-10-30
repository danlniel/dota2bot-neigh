-- Run from repo root: luajit tests/test_ward_stock.lua
package.path = package.path .. ';./bots/FretBots/?.lua'
local WS = require('WardStock')

-- GameRules stub: stock[team][item]
local function Rules(stock)
	local r = { stock = stock, sets = {} }
	function r:GetItemStockCount(team, item, playerId)
		assert(playerId == -1, 'team-wide stock')
		return self.stock[team][item]
	end
	function r:SetItemStockCount(count, team, item, playerId)
		assert(playerId == -1, 'team-wide stock')
		self.stock[team][item] = count
		table.insert(self.sets, team..':'..item)
	end
	return r
end

local items = { 'item_ward_observer', 'item_ward_sentry' }

-- drained stock is raised to the floor, healthy stock is left alone
local r = Rules({
	[2] = { item_ward_observer = 0, item_ward_sentry = 5 },
	[3] = { item_ward_observer = 1, item_ward_sentry = 2 },
})
assert(WS.TopUp(r, { 2, 3 }, items, 2) == 2)
assert(r.stock[2].item_ward_observer == 2)
assert(r.stock[2].item_ward_sentry == 5, 'never lowers stock')
assert(r.stock[3].item_ward_observer == 2)
assert(r.stock[3].item_ward_sentry == 2)

-- floor 2 is what the buy logic needs (it buys while stock > 1)
assert(r.stock[2].item_ward_observer > 1)

-- a team without bots isn't touched
local r2 = Rules({
	[2] = { item_ward_observer = 0, item_ward_sentry = 0 },
	[3] = { item_ward_observer = 0, item_ward_sentry = 0 },
})
assert(WS.TopUp(r2, { 3 }, items, 2) == 2)
assert(r2.stock[2].item_ward_observer == 0, 'human-only team keeps real stock')
assert(r2.stock[3].item_ward_observer == 2)

-- TeamsWithBots: empty and missing bot lists are skipped
local teams = WS.TeamsWithBots({ [2] = {}, [3] = { { name = 'bot' } } })
assert(#teams == 1 and teams[1] == 3)
assert(#WS.TeamsWithBots(nil) == 0)
local both = WS.TeamsWithBots({ [2] = { {} }, [3] = { {} } })
assert(#both == 2)

print('test_ward_stock: ok')
