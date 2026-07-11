-- ML Director (FretBots / addon VM side).
--
-- Periodically posts the full game state to a local model server (ml/server.py)
-- and applies the difficulty it returns, replacing static rubber-band rules with
-- an external policy (heuristic today, trained model later).
--
-- Mirrors Chat.lua's CreateHTTPRequest usage, which is proven to work in this VM.
-- Fail-safe: disables itself after consecutive failures or when turned off in
-- Customize; never touches settings before they are finalized.

require 'bots.FretBots.Timers'
require 'bots.FretBots.Utilities'
require 'bots.FretBots.Flags'

local json = require('bots.ts_libs.utils.json')

local Customize
if GetScriptDirectory ~= nil and GetScriptDirectory() == 'bots' then
	Customize = require('bots.FunLib.custom_loader')
else
	Customize = require(GetScriptDirectory()..'/FunLib/custom_loader')
end

MLDirector = MLDirector or {}

local ML = Customize.ML or {}
local SERVER_URL = ML.Server or 'http://127.0.0.1:5544'
local INTERVAL = ML.Director_Interval or 20
local MAX_FAILURES = 3
local ALLOW_DIFFICULTY_CONTROL = ML.Allow_Difficulty_Control ~= false

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

-- transient faults (snapshot build, encode, request setup) count toward the
-- same retry budget as HTTP failures instead of disabling on first error
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
		request:SetHTTPRequestRawPostBody('application/json', json.encode(BuildSnapshot()))
		request:Send(function(response)
			if response.StatusCode == 200 then
				failureCount = 0
				local success, resObj = pcall(function() return json.decode(response.Body) end)
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
	-- wait until FretBots settings are finalized (difficulty vote done)
	if Flags.isSettingsFinalized and Settings ~= nil and Settings.difficulty ~= nil then
		SendSnapshot()
	end
	return INTERVAL
end

function MLDirector:Initialize()
	if not isEnabled then return end
	Timers:CreateTimer(timerName, {endTime = INTERVAL, callback = function() return MLDirector:Tick() end})
	print('[MLDirector] started, target server: '..SERVER_URL)
end

MLDirector:Initialize()

return MLDirector
