-- Post-pick counter swap (design 2026-08-31). Bots lock heroes fast; a human
-- who picks late is never answered in the draft. After everyone has spawned,
-- if a bot on the team FACING the human(s) is clearly countered by the human
-- hero(es), replace it with a hero that counters them — using the same
-- matchup table hero_selection uses (matchups[hero][enemy] = enemy's
-- advantage over hero, Dotabuff-style). Conservative: at most maxSwaps,
-- only for a clearly bad matchup, only when humans sit on exactly one team,
-- never into heroes the bot scripts play badly. The bots VM detects the new
-- hero through J.IsStaleARDMHero (ungated for all modes) and reloads builds.
require 'bots.FretBots.Utilities'
require 'bots.FretBots.DataTables'
local Matchups = require 'bots.FretBots.matchups_data'
local HeroNames = require 'bots.FretBots.HeroNames'

if CounterSwap == nil then
	CounterSwap = {}
end

CounterSwap.settings = {
	enabled = true,
	maxSwaps = 1,
	-- summed human advantage over the bot hero required to consider a swap
	minAdvantage = 2.0,
	-- the replacement must improve the matchup by at least this much
	minImprovement = 3.0,
	-- heroes the bot scripts play poorly / buggy (mirrors hero_selection's
	-- weak list) plus micro-heavy heroes that need dedicated logic
	exclude = {
		npc_dota_hero_chen = true, npc_dota_hero_ancient_apparition = true,
		npc_dota_hero_tinker = true, npc_dota_hero_pangolier = true,
		npc_dota_hero_tusk = true, npc_dota_hero_morphling = true,
		npc_dota_hero_visage = true, npc_dota_hero_void_spirit = true,
		npc_dota_hero_ember_spirit = true, npc_dota_hero_rubick = true,
		npc_dota_hero_brewmaster = true, npc_dota_hero_puck = true,
		npc_dota_hero_marci = true, npc_dota_hero_lone_druid = true,
		npc_dota_hero_primal_beast = true, npc_dota_hero_meepo = true,
		npc_dota_hero_invoker = true, npc_dota_hero_arc_warden = true,
		npc_dota_hero_broodmother = true, npc_dota_hero_largo = true,
		npc_dota_hero_ringmaster = true, npc_dota_hero_kez = true,
	},
}

local swapsDone = 0

-- positive = the human heroes beat this hero
local function HumanAdvantageOver(heroName, humanHeroes)
	local row = Matchups[heroName]
	if row == nil then return nil end
	local sum = 0
	for _, h in ipairs(humanHeroes) do
		sum = sum + (row[h] or 0)
	end
	return sum
end

function CounterSwap:Initialize()
	local cfg = CounterSwap.settings
	if not cfg.enabled or swapsDone >= cfg.maxSwaps then return end
	if AllHumanPlayers == nil or #AllHumanPlayers == 0 then return end

	-- humans must all be on one team; the other team's bots adapt
	local humanTeam, humanHeroes = nil, {}
	for _, h in ipairs(AllHumanPlayers) do
		if h.stats ~= nil then
			if humanTeam ~= nil and humanTeam ~= h.stats.team then return end
			humanTeam = h.stats.team
			table.insert(humanHeroes, h.stats.internalName)
		end
	end
	if humanTeam == nil or #humanHeroes == 0 then return end
	local botTeam = (humanTeam == 2) and 3 or 2
	local bots = AllBots[botTeam]
	if bots == nil or #bots == 0 then return end

	local present = {}
	for _, u in ipairs(AllUnits) do
		if u.stats ~= nil then present[u.stats.internalName] = true end
	end

	-- the bot most countered by the human(s)
	local worst, worstAdv, worstIdx = nil, -math.huge, nil
	for i, b in ipairs(bots) do
		local adv = b.stats ~= nil and HumanAdvantageOver(b.stats.internalName, humanHeroes) or nil
		if adv ~= nil and adv > worstAdv then
			worst, worstAdv, worstIdx = b, adv, i
		end
	end
	if worst == nil or worstAdv < cfg.minAdvantage then return end

	-- the best available answer
	local best, bestAdv = nil, math.huge
	for name, _ in pairs(HeroNames.en) do
		if not present[name] and not cfg.exclude[name] then
			local adv = HumanAdvantageOver(name, humanHeroes)
			if adv ~= nil and adv < bestAdv then
				best, bestAdv = name, adv
			end
		end
	end
	if best == nil or (worstAdv - bestAdv) < cfg.minImprovement then return end

	-- swap, refunding whatever the old hero already bought
	local pid = worst.stats.id
	local gold = PlayerResource:GetGold(pid)
	for slot = 0, 8 do
		local item = worst:GetItemInSlot(slot)
		if item ~= nil then gold = gold + item:GetCost() end
	end
	local ok, newHero = pcall(function()
		return PlayerResource:ReplaceHeroWith(pid, best, gold, 0)
	end)
	if not ok or newHero == nil then
		print('[CounterSwap] ReplaceHeroWith failed for '..tostring(best)..': '..tostring(newHero))
		return
	end
	swapsDone = swapsDone + 1

	-- rebind FretBots tables to the new hero, carrying the stats over
	local oldName = worst.stats.internalName
	newHero.stats = worst.stats
	newHero.stats.internalName = best
	newHero.stats.name = Utilities:GetName(best)
	bots[worstIdx] = newHero
	for i, u in ipairs(AllUnits) do
		if u == worst then AllUnits[i] = newHero end
	end

	local humanNames = {}
	for _, h in ipairs(humanHeroes) do table.insert(humanNames, Utilities:GetName(h)) end
	Utilities:Print(string.format('Counter-pick: bot swapped %s -> %s to answer %s (matchup %+.1f -> %+.1f)',
		Utilities:GetName(oldName), Utilities:GetName(best), table.concat(humanNames, ', '),
		-worstAdv, -bestAdv))
end
