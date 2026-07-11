-- ML Bridge (bots VM side).
--
-- Periodically sends a compact game-state snapshot to a local model server
-- (see ml/server.py) and receives FightIQ parameter overrides, letting an
-- external trained model tune bot fight behavior live.
--
-- Uses CreateRemoteHTTPRequest — the bots-VM HTTP API this codebase already
-- relies on (see ts_libs/utils/http_utils/http_req.lua). It takes no headers,
-- so authentication travels in the JSON body as `api_key`.
--
-- Fail-safe by design:
--   * If CreateRemoteHTTPRequest is not exposed in this VM, the bridge disables itself.
--   * If the server fails MAX_FAILURES times in a row, it disables itself.
--   * All engine calls are wrapped so a bridge fault can never break bot thinking.
--
-- One designated bot per team (the first valid bot on the roster) does the
-- talking, so the server sees at most one request per team per interval.

local MLBridge = {}

local Customize
if GetScriptDirectory ~= nil and GetScriptDirectory() == 'bots' then
	Customize = require('bots.FunLib.custom_loader')
else
	Customize = require(GetScriptDirectory()..'/FunLib/custom_loader')
end

local json
if GetScriptDirectory ~= nil and GetScriptDirectory() == 'bots' then
	json = require('bots.ts_libs.utils.json')
else
	json = require(GetScriptDirectory()..'/ts_libs/utils/json')
end

local ML = Customize.ML or {}
local SERVER_URL = ML.Server or 'http://127.0.0.1:5544'
local INTERVAL = ML.Snapshot_Interval or 10
local MAX_FAILURES = 3

local isEnabled = ML.Enable ~= false
local failureCount = 0
local lastSendTime = -9999
local hasAnnouncedDisable = false

-- FightIQ overrides received from the server; merged copy is what jmz reads.
local effectiveFightIQ = nil

function MLBridge.GetEffectiveFightIQ()
	return effectiveFightIQ
end

local function Disable(reason)
	isEnabled = false
	effectiveFightIQ = nil
	if not hasAnnouncedDisable then
		hasAnnouncedDisable = true
		print('[MLBridge] disabled: '..tostring(reason)..' (bots fall back to static Customize.FightIQ)')
	end
end

local function CountFailure(what)
	failureCount = failureCount + 1
	if failureCount >= MAX_FAILURES then
		Disable(tostring(what)..' after '..MAX_FAILURES..' consecutive failures')
	end
end

-- Build the merged FightIQ table once per server response (not per query).
local function ApplyOverrides(overrides)
	if type(overrides) ~= 'table' then return end
	local base = Customize.FightIQ or {}
	local merged = {}
	for k, v in pairs(base) do merged[k] = v end
	for k, v in pairs(overrides) do
		if type(v) == 'number' or type(v) == 'boolean' then merged[k] = v end
	end
	merged.Enable = base.Enable ~= false
	effectiveFightIQ = merged
end

-- Per-field fail-safes: one missing engine API must never cost the whole
-- snapshot; unknown values become 0/nil and the trainer treats them as such.
local function SafeNum(fn, ...)
	local ok, v = pcall(fn, ...)
	if ok and type(v) == 'number' then return v end
	return 0
end

local function SafeStr(fn, ...)
	local ok, v = pcall(fn, ...)
	if ok and type(v) == 'string' then return v end
	return nil
end

local TOWER_IDS = {
	TOWER_TOP_1, TOWER_TOP_2, TOWER_TOP_3,
	TOWER_MID_1, TOWER_MID_2, TOWER_MID_3,
	TOWER_BOT_1, TOWER_BOT_2, TOWER_BOT_3,
	TOWER_BASE_1, TOWER_BASE_2,
}

local function CountStandingTowers(nTeam)
	local n = 0
	for _, towerId in pairs(TOWER_IDS) do
		local ok, tower = pcall(GetTower, nTeam, towerId)
		if ok and tower ~= nil and not tower:IsNull() and tower:IsAlive() then
			n = n + 1
		end
	end
	return n
end

local function BuildSnapshot(bot)
	local snapshot = {
		api_key = (ML.Api_Key ~= nil and ML.Api_Key ~= '') and ML.Api_Key or nil,
		time = DotaTime(),
		team = GetTeam(),
		players = {},
		towers = {
			ally = CountStandingTowers(GetTeam()),
			enemy = CountStandingTowers(GetOpposingTeam()),
		},
		roshan_kill_time = SafeNum(GetRoshanKillTime),
	}
	-- allies: full detail (handles available for own team)
	for i, id in pairs(GetTeamPlayers(GetTeam())) do
		local member = GetTeamMember(i)
		table.insert(snapshot.players, {
			team = 'ally',
			hero = SafeStr(GetSelectedHeroName, id),
			kills = GetHeroKills(id) or 0,
			deaths = GetHeroDeaths(id) or 0,
			assists = SafeNum(GetHeroAssists, id),
			level = member ~= nil and SafeNum(member.GetLevel, member) or 0,
			networth = member ~= nil and SafeNum(member.GetNetWorth, member) or 0,
			last_hits = member ~= nil and SafeNum(member.GetLastHits, member) or 0,
		})
	end
	-- enemies: scoreboard facts only (networth/level need handles we may not have)
	for _, id in pairs(GetTeamPlayers(GetOpposingTeam())) do
		table.insert(snapshot.players, {
			team = 'enemy',
			hero = SafeStr(GetSelectedHeroName, id),
			kills = GetHeroKills(id) or 0,
			deaths = GetHeroDeaths(id) or 0,
			assists = SafeNum(GetHeroAssists, id),
		})
	end
	-- current effective params, so the dataset records what policy was active
	local iq = effectiveFightIQ or Customize.FightIQ or {}
	snapshot.fightiq = {
		Commit_Margin = iq.Commit_Margin,
		Ult_Ready_Bonus = iq.Ult_Ready_Bonus,
		Ult_Down_Penalty = iq.Ult_Down_Penalty,
		Disabled_Power_Scale = iq.Disabled_Power_Scale,
	}
	return snapshot
end

local function SendSnapshot(bot)
	local ok, err = pcall(function()
		local request = CreateRemoteHTTPRequest(SERVER_URL..'/policy')
		request:SetHTTPRequestRawPostBody('application/json', json.encode(BuildSnapshot(bot)))
		-- callback receives the raw response body string (nil/empty on failure)
		request:Send(function(result)
			local success, resObj = pcall(function() return json.decode(result) end)
			if success and type(resObj) == 'table' then
				failureCount = 0
				ApplyOverrides(resObj.fightiq)
			else
				CountFailure('server at '..SERVER_URL..' not answering')
			end
		end)
	end)
	if not ok then
		CountFailure('http request failed: '..tostring(err))
	end
end

-- True only for the first valid bot of the team, so a team sends one request per interval.
local function IsTeamCaptain(bot)
	for i = 1, #GetTeamPlayers(GetTeam()) do
		local member = GetTeamMember(i)
		if member ~= nil and member:IsBot() then
			return member == bot
		end
	end
	return false
end

-- Called from mode desire polling; internally gated, cheap when idle.
function MLBridge.Think(bot)
	if not isEnabled then return end
	if CreateRemoteHTTPRequest == nil then
		Disable('CreateRemoteHTTPRequest not available in this VM')
		return
	end
	if DotaTime() - lastSendTime < INTERVAL then return end
	if not IsTeamCaptain(bot) then return end
	lastSendTime = DotaTime()
	SendSnapshot(bot)
end

return MLBridge
