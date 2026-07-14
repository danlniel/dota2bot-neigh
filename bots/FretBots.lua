if not GameRules or GameRules:State_Get() < DOTA_GAMERULES_STATE_HERO_SELECTION then
	print('Start a lobby game and try to enable Fretbots after entering the Hero Selection phase.')
	return
end
-- LinkLuaModifier("modifier_fret_damage_increase", "FretBots/modifiers/modifier_seasonal_party_hat.lua", LUA_MODIFIER_MOTION_NONE)
if GetScriptDirectory == nil then GetScriptDirectory = function() return "bots" end end
-- Version information
local Version = require 'bots.FunLib.version'
-- Print version to console. The [neigh fork] marker proves THIS file is the
-- one loading (and not a subscribed workshop copy resolving instead).
print('Open Hyper AI (OHA). Starting Fretbots mode: ' .. Version.number .. ' [neigh fork]')
-- Dependencies
-- global debug flag
require 'bots.FretBots.Debug'
-- Other Flags
require 'bots.FretBots.Flags'
-- DataTables has helper functions for generating data structures we consume, and querying/acting on that data
require 'bots.FretBots.DataTables'
-- Entity Killed monitors kills and provides bonuses (if settings dictate)
require 'bots.FretBots.OnEntityKilled'
-- Entity hurt monitors damage and updates stat tables accordingly
require 'bots.FretBots.OnEntityHurt'
-- Timers for periodic bonuses
require 'bots.FretBots.BonusTimers'
-- Utilities
require 'bots.FretBots.Utilities'
-- Dynamic Difficulty Adjustor
require 'bots.FretBots.DynamicDifficulty'
-- Settings
require 'bots.FretBots.Settings'
-- Timers
require 'bots.FretBots.Timers'
-- Hero Specifc Extensions
require 'bots.FretBots.HeroLoneDruid'
-- Role Determination
require 'bots.FretBots.RoleDetermination'
-- Neutral items
require 'bots.FretBots.NeutralItems'
require 'bots.FretBots.modifiers.Modifier'

-- =====================================================================
-- ML Director (adaptive difficulty via model server, see ml/README.md)
-- Inlined here on purpose: a `require` for a file that does not exist in
-- the subscribed workshop copy can be silently skipped when the workshop
-- item is mounted. Inline code cannot be skipped: if this file runs, the
-- director runs.
-- =====================================================================
do
	print('[MLDirector] inline block executing...')
	local mlJson = require('bots.ts_libs.utils.json')
	local mlCustomize
	if GetScriptDirectory() == 'bots' then
		mlCustomize = require('bots.FunLib.custom_loader')
	else
		mlCustomize = require(GetScriptDirectory()..'/FunLib/custom_loader')
	end

	local ML = mlCustomize.ML or {}
	print('[MLDirector] config: ML='..tostring(mlCustomize.ML ~= nil)
		..' Enable='..tostring(ML.Enable)..' Server='..tostring(ML.Server))

	local SERVER_URL = ML.Server or 'http://127.0.0.1:5544'
	local INTERVAL = ML.Director_Interval or 10
	local MAX_FAILURES = 3
	local ALLOW_DIFFICULTY_CONTROL = ML.Allow_Difficulty_Control ~= false

	MLDirector = MLDirector or {}
	local isEnabled = ML.Enable ~= false
	local failureCount = 0
	local timerName = 'MLDirectorTimer'
	local hasAnnouncedDisable = false

	local function Disable(reason)
		isEnabled = false
		if not hasAnnouncedDisable then
			hasAnnouncedDisable = true
			print('[MLDirector] disabled: '..tostring(reason)..' (static FretBots difficulty rules apply)')
		end
		Timers:RemoveTimer(timerName)
	end

	local function CountFailure(what)
		failureCount = failureCount + 1
		if failureCount >= MAX_FAILURES then
			Disable(tostring(what)..' after '..MAX_FAILURES..' consecutive failures')
		end
	end

	local function BuildSnapshot()
		return {
			game_time = Utilities:GetTime(),
			difficulty = Settings.difficulty,
			difficulty_scale = Settings.difficultyScale,
			ally_scale = Settings.allyScale,
			heroes = Utilities:HeroStatsInGame(AllUnits),
		}
	end

	local function ApplyDirective(resObj)
		if type(resObj) ~= 'table' then return end
		if ALLOW_DIFFICULTY_CONTROL and type(resObj.difficulty) == 'number' then
			local newDifficulty = math.max(0, math.min(10, resObj.difficulty))
			if newDifficulty ~= Settings.difficulty then
				Settings.difficulty = newDifficulty
				Settings.difficultyScale = Settings:CalculateDifficultyScale(newDifficulty)
				if resObj.announce then
					Utilities:Print(string.format('ML Director adjusted bot difficulty to %.1f', newDifficulty), MSG_WARNING)
				end
			end
		end
	end

	local function SendSnapshot()
		local ok, err = pcall(function()
			local request = CreateHTTPRequest('POST', SERVER_URL..'/director')
			request:SetHTTPRequestHeaderValue('Content-Type', 'application/json')
			if ML.Api_Key ~= nil and ML.Api_Key ~= '' then
				request:SetHTTPRequestHeaderValue('Authorization', ML.Api_Key)
			end
			request:SetHTTPRequestRawPostBody('application/json', mlJson.encode(BuildSnapshot()))
			request:Send(function(response)
				if response.StatusCode == 200 then
					failureCount = 0
					local success, resObj = pcall(function() return mlJson.decode(response.Body) end)
					if success then ApplyDirective(resObj) end
				else
					CountFailure('server unreachable at '..SERVER_URL)
				end
			end)
		end)
		if not ok then
			CountFailure('request construction failed: '..tostring(err))
		end
	end

	function MLDirector:Tick()
		if not isEnabled then return nil end
		if CreateHTTPRequest == nil then
			Disable('CreateHTTPRequest not available in this VM')
			return nil
		end
		if Flags.isSettingsFinalized and Settings ~= nil and Settings.difficulty ~= nil then
			SendSnapshot()
		end
		return INTERVAL
	end

	if isEnabled then
		local ok, err = pcall(function()
			Timers:CreateTimer(timerName, {endTime = INTERVAL, callback = function() return MLDirector:Tick() end})
		end)
		if ok then
			print('[MLDirector] started, target server: '..SERVER_URL)
		else
			print('[MLDirector] Timers:CreateTimer FAILED: '..tostring(err))
		end
	else
		print('[MLDirector] NOT starting: Customize.ML.Enable is false')
	end
end

-- Instantiate ourself
if FretBots == nil then
	FretBots = {}
end

-- other local vars
local playersLoadedTimerName = 'playersLoadedTimerName'
local isAllPlayersSpawned = false
local isDataTablesInitialized = false
local isFretbotsBeingInitialized = false
local playerSpawnCount = 0
local playerLoadFailSafeDelta = 15  -- 15 retries (~15 seconds) to find all heroes

-- Starting this script is largely handled by the requires, as separate pieces start
-- themselves. DataTables cannot be initialized until all players have loaded, so
-- this function (which gets called at the beginning of pre game) in turn starts a
-- timer method to monitor for all players being loaded, which will in turn
-- initialize the data tables
function FretBots:Initialize()
	if not isFretbotsBeingInitialized then
		Debug:Print('Initializing FretBots')
		-- Randomize!
		FretBots:SetRandomSeed()
		-- Register the listener that will check for all players spawning and then init datatables
		ListenToGameEvent('dota_on_hero_finish_spawn', Dynamic_Wrap(FretBots, 'OnPlayerSpawned'), FretBots)
		Timers:CreateTimer(playersLoadedTimerName, {endTime = 1, callback = FretBots['PlayersLoadedTimer']} )
		isFretbotsBeingInitialized = true
	else
		Debug:Print('FretBots is being initialized')
	end
end

-- Runs until all players are loaded in and then initializes the DataTables
function FretBots:PlayersLoadedTimer()
    if Utilities:IsTurboMode() == nil then return 1 end

	Debug:Print('Initializing PlayersLoadedTimer')
	if not isAllPlayersSpawned then FretBots:CheckBots() end

	-- if all players are loaded, initialize datatables and stop timer
	if isAllPlayersSpawned then
		if not isDataTablesInitialized then
			local ok, err = pcall(DataTables.Initialize, DataTables)
			if ok then
				isDataTablesInitialized = true
			else
				print('[FretBots] DataTables:Initialize FAILED: '..tostring(err))
				print('[FretBots] Retrying next tick...')
				return 1
			end
		end
		if not Flags.isSettingsFinalized then
			Debug:Print('Settings not finalized yet! Waiting.')
			return 1
		end
		-- Register EntityKilled Listener
		EntityKilled:RegisterEvents()
		-- Set all bots to find tier 1 neutrals
		NeutralItems:InitializeFindTimings()
		-- Start bonus timers (they require DataTables to exist)
		BonusTimers:Initialize()
		-- Start bot role determination timer
		RoleDetermination:Initialize()
		-- Register EntityHurt Listener
		EntityHurt:RegisterEvents()
		Modifier:Initialize()
		-- Hero Specific extensions - these will stop themselves if they
		-- determine that they are not enabled
		-- Disabled until this works
		-- HeroLoneDruid:Initialize()
		-- Remove this timer
		Timers:RemoveTimer(playersLoadedTimerName)
		return nil
	end
	return 1
end

function FretBots:OnPlayerSpawned(event)
	playerSpawnCount = playerSpawnCount + 1
end

function FretBots:CheckBots()
	-- Count players with assigned heroes
	local nReady = 0
	for nTeam = DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS do
		local pNum = PlayerResource:GetPlayerCountForTeam(nTeam)
		for i = 0, pNum - 1 do
			local playerID = PlayerResource:GetNthPlayerIDOnTeam(nTeam, i)
			if playerID and playerID >= 0 then
				local player = PlayerResource:GetPlayer(playerID)
				if player and player:GetAssignedHero() then
					nReady = nReady + 1
				end
			end
		end
	end

	-- A standard 5v5 game has 10 players. With humans, GetPlayer/GetAssignedHero
	-- may not work for human slots from the server side. Accept 8+ as ready
	-- (at least 8 bots in a game with 1-2 humans is normal).
	local MIN_READY = 8
	if nReady >= MIN_READY then
		Debug:Print('Found '..nReady..' heroes ready (>= '..MIN_READY..'). Proceeding.')
		isAllPlayersSpawned = true
	else
		playerLoadFailSafeDelta = playerLoadFailSafeDelta - 1
		if playerLoadFailSafeDelta <= 0 then
			if nReady >= 4 then
				-- At least 4 heroes found — enough to start
				Debug:Print('Failsafe: '..nReady..' heroes found. Proceeding.')
				isAllPlayersSpawned = true
			else
				-- Reset and keep trying — something is seriously wrong
				Debug:Print('Only '..nReady..' heroes found. Resetting failsafe.')
				playerLoadFailSafeDelta = 5
			end
		else
			Debug:Print('Waiting for heroes: '..nReady..' ready, retries left: '..playerLoadFailSafeDelta)
		end
	end
end

-- Sets the random seed for the game, and burns off the initial bad random number
function FretBots:SetRandomSeed()
	local timeString = GetSystemTime()
	timeString = string.gsub(timeString,':','')
	local serverTime = Time()
	serverTime = serverTime - math.floor(serverTime)
	local seed = tonumber(timeString) + serverTime
	seed = math.floor(seed * 100000)
	math.randomseed(seed)
	local temp = math.random()
end

-- Start things up (only once)
if not Flags.isFretBotsInitialized then
	local teamNames = require 'bots.FunLib.aba_team_names'
	if teamNames.maxTeamSize ~= 12 then return end
	-- Welcome Message
	Utilities:Print('Welcome to Open Hyper AI (OHA)! FretBots enabled: ' .. Version.number, MSG_GOOD, MATCH_READY)
	-- Register the listener that will run Initialize() once the game starts
	Utilities:RegsiterGameStateListener(FretBots, 'Initialize', DOTA_GAMERULES_STATE_PRE_GAME )
	Flags.isFretBotsInitialized = true
else
	print("Fretbots mode has already been enabled for this game.")
end
