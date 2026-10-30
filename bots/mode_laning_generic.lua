local Utils = require( GetScriptDirectory()..'/FunLib/utils')
local J = require( GetScriptDirectory()..'/FunLib/jmz_func')
local Customize = require( GetScriptDirectory()..'/FunLib/custom_loader')

local Version      = require(GetScriptDirectory()..'/FunLib/version')
local Localization = require(GetScriptDirectory()..'/FunLib/localization')


local bot = GetBot()
local botName = bot:GetUnitName()
if bot == nil or bot:IsInvulnerable() or not bot:IsHero() or not bot:IsAlive() or not string.find(botName, "hero") or bot:IsIllusion() then return end

local local_mode_laning_generic = nil
local nAllyCreeps = nil
local nEnemyCreeps = nil
local nFurthestEnemyAttackRange = 0
local nInRangeEnemy = nil
local botAssignedLane = nil
local botAttackRange = bot:GetAttackRange()
local attackDamage = bot:GetAttackDamage()
local nH, enemyBots = J.Utils.NumHumanBotPlayersInTeam(GetOpposingTeam())
local teamHumans, teamBots = J.Utils.NumHumanBotPlayersInTeam(GetTeam())

-- LaneIQ support farm: pos 4/5 deny instead of competing with their core for
-- last hits (adapted from upstream PR #174). Think() can only be replaced at
-- load (there's no way to call Valve's default from Lua), so the role is read
-- once here; Think re-checks it every frame.
local laneIQ = Customize.LaneIQ
local bSupportDenyFocus = (laneIQ == nil or laneIQ.Support_Deny_Focus ~= false)
local nCoreClaimRadius = laneIQ and laneIQ.Support_Core_Claim_Radius or 800
local bLoadedAsSupport = bSupportDenyFocus and J.GetPosition(bot) >= 4

local function IsSupportDenyRole()
	return bSupportDenyFocus and J.GetPosition(bot) >= 4
end

-- Announcer state
local hasPickedOneAnnouncer      = false
local lastAnnouncePrintedTime    = 0
local numberAnnouncePrinted      = 1
local announcementGapSeconds     = 6
local isChangePosMessageDone     = false

if Utils.BuggyHeroesDueToValveTooLazy[botName] then local_mode_laning_generic = dofile( GetScriptDirectory().."/FunLib/override_generic/mode_laning_generic" ) end

function GetDesire()
	PickOneAnnouncer()
	AnnounceMessages()

	if bot:IsInvulnerable() or not bot:IsHero() or not bot:IsAlive() or not string.find(botName, "hero") or bot:IsIllusion() then return BOT_MODE_DESIRE_NONE end
	local botLV = bot:GetLevel()
	local currentTime = DotaTime()

	botAttackRange = bot:GetAttackRange()
	nAllyCreeps = bot:GetNearbyLaneCreeps(1200, false)
	nEnemyCreeps = bot:GetNearbyLaneCreeps(800, true)
	nInRangeEnemy = bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)
	nFurthestEnemyAttackRange = GetFurthestEnemyAttackRange(nInRangeEnemy)
	if local_mode_laning_generic then
		botAssignedLane = local_mode_laning_generic.GetBotTargetLane()
	else
		botAssignedLane = bot:GetAssignedLane()
	end
	attackDamage = bot:GetAttackDamage()
	if bot:GetItemSlotType(bot:FindItemSlot("item_quelling_blade")) == ITEM_SLOT_TYPE_MAIN then
		if bot:GetAttackRange() > 310 or bot:GetUnitName() == "npc_dota_hero_templar_assassin" then
			attackDamage = attackDamage + 4
		else
			attackDamage = attackDamage + 8
		end
	end

	if GetGameMode() == 23 then currentTime = currentTime * 1.65 end
	if currentTime < 0 then return BOT_ACTION_DESIRE_NONE end

	-- if DotaTime() > 20 and DotaTime() - skipLaningState.lastCheckTime < skipLaningState.checkGap then
	-- 	if skipLaningState.count > 6 then
	-- 		print('[WARN] Bot ' ..botName.. ' switching modes too often, now stop it for laning to avoid conflicts.')
	-- 		return 0
	-- 	end
	-- else
	-- 	skipLaningState.lastCheckTime = DotaTime()
	-- 	skipLaningState.count = 0
	-- end

	if J.GetEnemiesAroundAncient(bot, 3200) > 0 then
		return BOT_MODE_DESIRE_NONE
	end

	-- if J.GetDistanceFromAncient( bot, true ) < 6900 then
	-- 	return BOT_MODE_DESIRE_NONE
	-- end

	if bot:WasRecentlyDamagedByAnyHero(5)
	and #J.Utils.GetLastSeenEnemyIdsNearLocation(bot:GetLocation(), 800) > 0 then
		local nLaneFrontLocation = GetLaneFrontLocation(GetTeam(), bot:GetAssignedLane(), 0)
		local nDistFromLane = GetUnitToLocationDistance(bot, nLaneFrontLocation)
		if not J.WeAreStronger(bot, 1200) or (nDistFromLane > 700 and J.GetHP(bot) < 0.7) then
			return BOT_MODE_DESIRE_NONE
		end
	end

	-- 如果在打高地 就别撤退去干别的
	if J.Utils.IsTeamPushingSecondTierOrHighGround(bot) then
		return BOT_MODE_DESIRE_NONE
	end
	-- if J.ShouldGoFarmDuringLaning(bot) then
	-- 	return 0.2
	-- end

	-- A4: weakened and being kited by a longer-range attacker — stop
	-- contesting last hits; yield the mode auction to retreat/attack.
	if J.GetHP(bot) < 0.55 and J.IsBeingKitedByLongerRange(bot) then
		return BOT_MODE_DESIRE_NONE
	end

	if local_mode_laning_generic or (J.GetPosition(bot) == 1 and J.IsPosxHuman(5)) then
		-- last hit
		if J.IsInLaningPhase() then
			local hitCreep, _ = GetBestLastHitCreep(nEnemyCreeps)
			if J.IsValid(hitCreep) then
				if J.GetPosition(bot) <= 2 or not J.IsThereNonSelfCoreNearby(700) -- this is for e.g lone druid bear as pos1-2 with core LD nearby to do last hit.
				then
					return 0.9
				end
			end
		end
	end
	if local_mode_laning_generic and local_mode_laning_generic.GetDesire ~= nil then return local_mode_laning_generic.GetDesire() end

	if GetGameMode() == GAMEMODE_1V1MID or GetGameMode() == GAMEMODE_MO then
		return 1
	end

	if currentTime <= 10 then return 0.268 end
	if currentTime <= 9 * 60 and botLV <= 7 then return 0.446 end
	if currentTime <= 12 * 60 and botLV <= 11 then return 0.369 end
	if botLV <= 14 and J.GetCoresAverageNetworth() < 7000 then return 0.2 end

	J.Utils.GameStates.passiveLaningTime = true
	return 0.01
end

function GetFurthestEnemyAttackRange(enemyList)
	local attackRange = 0
	for _, enemy in pairs(enemyList) do
		if J.IsValidHero(enemy) and not J.IsSuspiciousIllusion(enemy) then
			local enemyAttackRange = enemy:GetAttackRange()
			if enemyAttackRange > attackRange then
				attackRange = enemyAttackRange
			end
		end
	end

	return attackRange
end

function GetBestLastHitCreep(hCreepList)
	local dmgDelta = attackDamage * 0.7

	local moveToCreep = nil
	for _, creep in pairs(hCreepList) do
		if J.IsValid(creep) and J.CanBeAttacked(creep) then
			local nDelay = J.GetAttackProDelayTime(bot, creep)
			if J.WillKillTarget(creep, attackDamage, DAMAGE_TYPE_PHYSICAL, nDelay) then
				return creep, false
			end
			if J.WillKillTarget(creep, attackDamage + dmgDelta, DAMAGE_TYPE_PHYSICAL, nDelay) then
				moveToCreep = creep
			end
		end
	end
	if moveToCreep then
		return moveToCreep, true
	end

	return nil
end

function GetBestDenyCreep(hCreepList)
	-- in reach first; a creep a few steps away is still worth walking to
	local fallbackCreep = nil
	for _, creep in pairs(hCreepList)
	do
		if J.IsValid(creep)
		and J.GetHP(creep) < 0.49
		and J.CanBeAttacked(creep)
		and J.IsDeniableLaneCreep(creep)
		and (creep:GetHealth() <= attackDamage
			or J.WillKillTarget(creep, attackDamage, DAMAGE_TYPE_PHYSICAL, J.GetAttackProDelayTime(bot, creep)))
		then
			if GetUnitToUnitDistance(bot, creep) <= botAttackRange + 100 then
				return creep
			end
			if fallbackCreep == nil then fallbackCreep = creep end
		end
	end

	return fallbackCreep
end

-- Alive allied cores (humans included) other than this bot, i.e. whoever
-- a support should leave the last hits to.
local function GetOtherAllyCores()
	local cores = {}
	for _, ally in pairs(GetUnitList(UNIT_LIST_ALLIED_HEROES)) do
		if J.IsValidHero(ally)
		and ally ~= bot
		and not ally:IsIllusion()
		and J.IsCore(ally)
		then
			table.insert(cores, ally)
		end
	end
	return cores
end

-- Last hit a support may take without stealing: no core is close enough to
-- the creep to take it. Keeps support GPM up when the core is dead, backing
-- or on the far side of the wave, and the creep would be wasted otherwise.
local function GetSupportLastHitCreep(hCreepList)
	local cores = GetOtherAllyCores()
	local free = {}
	for _, creep in pairs(hCreepList) do
		if J.IsValid(creep) then
			local bClaimed = false
			for _, core in pairs(cores) do
				if GetUnitToUnitDistance(core, creep) <= nCoreClaimRadius then
					bClaimed = true
					break
				end
			end
			if not bClaimed then table.insert(free, creep) end
		end
	end
	return GetBestLastHitCreep(free)
end

-- Right-click the enemy laner when it's cheap: healthy, at most one enemy
-- creep close enough to pull aggro, and nowhere near an enemy tower.
local function GetSupportHarassTarget()
	if J.GetHP(bot) <= 0.5 then return nil end
	if #bot:GetNearbyLaneCreeps(600, true) > 1 then return nil end
	if #bot:GetNearbyTowers(900, true) > 0 then return nil end
	for _, enemy in pairs(nInRangeEnemy) do
		if J.IsValidHero(enemy)
		and J.CanBeAttacked(enemy)
		and not J.IsSuspiciousIllusion(enemy)
		and J.IsInRange(bot, enemy, botAttackRange + 100)
		then
			return enemy
		end
	end
	return nil
end

if local_mode_laning_generic or (J.GetPosition(bot) == 1 and J.IsPosxHuman(5)) or bLoadedAsSupport then
	function Think()
		if IsSupportDenyRole() then
			-- Supports: deny first (XP + gold the enemy core loses), then
			-- only the last hits no core can take, then cheap harass.
			local denyCreep = GetBestDenyCreep(nAllyCreeps)
			if J.IsValid(denyCreep) then
				bot:SetTarget(denyCreep)
				bot:Action_AttackUnit(denyCreep, true)
				return
			end

			local freeCreep, moveToFree = GetSupportLastHitCreep(nEnemyCreeps)
			if J.IsValid(freeCreep) then
				if GetUnitToUnitDistance(bot, freeCreep) > botAttackRange
				or (moveToFree and GetUnitToUnitDistance(bot, freeCreep) > botAttackRange * 0.8) then
					bot:Action_MoveToUnit(freeCreep)
				else
					bot:SetTarget(freeCreep)
					bot:Action_AttackUnit(freeCreep, true)
				end
				return
			end

			local harassTarget = GetSupportHarassTarget()
			if harassTarget ~= nil then
				bot:Action_AttackUnit(harassTarget, true)
				return
			end
		end

		local hitCreep, moveToCreep = GetBestLastHitCreep(nEnemyCreeps)
		if J.IsValid(hitCreep) and not IsSupportDenyRole() then
			if J.GetPosition(bot) <= 2 or not J.IsThereNonSelfCoreNearby(700)
			then
				if GetUnitToUnitDistance(bot, hitCreep) > botAttackRange
				or (moveToCreep and GetUnitToUnitDistance(bot, hitCreep) > botAttackRange * 0.8) then
					bot:Action_MoveToUnit(hitCreep)
					return
				else
					bot:SetTarget(hitCreep)
					bot:Action_AttackUnit(hitCreep, true)
					return
				end
			end
		end

		local denyCreep = GetBestDenyCreep(nAllyCreeps)
		if J.IsValid(denyCreep) then
			bot:SetTarget(denyCreep)
			bot:Action_AttackUnit(denyCreep, true)
			return
		end

		if local_mode_laning_generic then
			local_mode_laning_generic.Think()
		end

		local fLaneFrontAmount = GetLaneFrontAmount(GetTeam(), botAssignedLane, false)
		local fLaneFrontAmount_enemy = GetLaneFrontAmount(GetOpposingTeam(), botAssignedLane, false)

		local nLongestAttackRange = math.max(botAttackRange, 250, nFurthestEnemyAttackRange)

		-- B3 freeze / anti-overpush: when we're the side pushing the wave and the
		-- bot is healthy, hang back an extra margin so the lane freezes on our
		-- side instead of shoving under the enemy tower (which denies our own
		-- pulls/ganks and exposes us). Only biases the IDLE position — last-hit
		-- and deny already returned above, so this never costs creeps.
		local nFreezeBias = 0
		local laneIQ = Customize.LaneIQ
		if (laneIQ == nil or laneIQ.Freeze_When_Ahead ~= false)
		and J.GetHP(bot) > 0.6
		and fLaneFrontAmount_enemy < fLaneFrontAmount   -- our wave is ahead = we're pushing
		then
			nFreezeBias = laneIQ and laneIQ.Freeze_Pullback or 250
		end

		local target_loc = GetLaneFrontLocation(GetTeam(), botAssignedLane, -nLongestAttackRange - nFreezeBias)
		if fLaneFrontAmount_enemy < fLaneFrontAmount then
			target_loc = GetLaneFrontLocation(GetOpposingTeam(), botAssignedLane, -nLongestAttackRange - nFreezeBias)
		end

		bot:Action_MoveToLocation(target_loc + RandomVector(50))
	end
end


function PickOneAnnouncer()
	if not hasPickedOneAnnouncer then
		for i, _ in pairs(GetTeamPlayers(GetTeam())) do
			local member = GetTeamMember(i)
			if member ~= nil and member.isAnnouncer then return end
		end
		bot.isAnnouncer = true
		hasPickedOneAnnouncer = true
	end
end

function AnnounceMessages()
	-- Only pre-game chatter
	if DotaTime() > 60 then return end

	local welcomeMessages = Localization.Get('welcome_msgs')
	local inTurbo         = J.IsModeTurbo()

	-- Staggered lines during negative DotaTime pre-game
	if ((inTurbo and DotaTime() > -50 + GetTeam() * 2) or (not inTurbo and DotaTime() > -75 + GetTeam() * 2))
	   and numberAnnouncePrinted < #welcomeMessages + 1
	   and bot.isAnnouncer
	   and DotaTime() < 0
	then
		if GameTime() - lastAnnouncePrintedTime >= announcementGapSeconds then
			local message      = welcomeMessages[numberAnnouncePrinted]
			local isFirstLine  = (numberAnnouncePrinted == 1)
			if message then
				-- Match original behavior: first line (or if no enemy bots) can be global
				bot:ActionImmediate_Chat(isFirstLine and (message .. Version.number .. ' [neigh build ' .. tostring(J.FORK_BUILD) .. ']') or message, enemyBots == 0 or isFirstLine)
			end
			numberAnnouncePrinted   = numberAnnouncePrinted + 1
			lastAnnouncePrintedTime = GameTime()
		end
	end

	-- Announce role during pre-game
	if GetGameMode() ~= GAMEMODE_1V1MID
	   and GetGameState() == GAME_STATE_PRE_GAME
	   and (bot.announcedRole == nil or bot.announcedRole ~= J.GetPosition(bot))
	then
		bot.announcedRole = J.GetPosition(bot)
		bot:ActionImmediate_Chat(Localization.Get('say_play_pos') .. J.GetPosition(bot), false)
	end

	-- Close position selection after horn if humans and bots mixed
	if GetGameMode() ~= GAMEMODE_1V1MID and not isChangePosMessageDone then
		if DotaTime() >= 0 and teamHumans > 0 and teamBots > 0 then
			bot:ActionImmediate_Chat(Localization.Get('pos_select_closed'), true)
			isChangePosMessageDone = true
		end
	end
end
