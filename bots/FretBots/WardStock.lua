-- Bots never run dry on wards (2026-10-30). Observer and sentry wards are
-- stock-limited per team (7.41: observers max 4, +1 per 135 s; sentries
-- max 8, +1 per 70 s), and the bot buy logic in item_purchase_generic.lua
-- only buys while stock > 1. A human teammate buying wards, or a long game
-- of supports re-buying, drained the stock and the bots stopped warding.
-- This keeps every team that has a bot at a floor of 2 per ward type, so
-- the bots can always buy (they still pay for sentries). Dust of Appearance
-- has no stock limit in 7.41 and needs no top-up.

if WardStock == nil then
	WardStock = {}
end

WardStock.items = { 'item_ward_observer', 'item_ward_sentry' }
WardStock.floor = 2
WardStock.interval = 3
-- team-wide stock; player IDs only matter for "PlayerSpecificCooldown" items
local TEAM_STOCK = -1
local timerName = 'WardStockTimer'

-- Pure: raise every listed item to the floor for each team. `rules` is
-- GameRules (or a test stub). Returns the number of top-ups made.
function WardStock.TopUp(rules, teams, items, floor)
	local count = 0
	for _, team in ipairs(teams) do
		for _, item in ipairs(items) do
			local stock = rules:GetItemStockCount(team, item, TEAM_STOCK)
			if stock ~= nil and stock < floor then
				rules:SetItemStockCount(floor, team, item, TEAM_STOCK)
				count = count + 1
			end
		end
	end
	return count
end

-- Teams with at least one bot (AllBots is built by DataTables)
function WardStock.TeamsWithBots(allBots)
	local teams = {}
	if allBots == nil then return teams end
	for _, team in ipairs({ DOTA_TEAM_GOODGUYS or 2, DOTA_TEAM_BADGUYS or 3 }) do
		if allBots[team] ~= nil and next(allBots[team]) ~= nil then
			table.insert(teams, team)
		end
	end
	return teams
end

function WardStock:Tick()
	local ok, err = pcall(WardStock.TopUp, GameRules, WardStock.TeamsWithBots(AllBots),
		WardStock.items, WardStock.floor)
	if not ok then
		-- an engine without these calls won't grow them mid-game
		print('[WardStock] disabled: '..tostring(err))
		return nil
	end
	return WardStock.interval
end

function WardStock:Initialize()
	Timers:CreateTimer(timerName, { endTime = 1, callback = function() return WardStock:Tick() end })
	print('[WardStock] keeping bot teams at '..WardStock.floor..'+ observer/sentry stock')
end

return WardStock
