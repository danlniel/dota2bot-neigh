-- VM-independent team focus target (design 2026-08-19 item 3).
-- Every bot recomputes the SAME call from team-shared observables only, so
-- coordination needs no cross-VM state. Determinism rule: NEVER score with
-- the calling bot's own position or state — only inputs every teammate sees
-- identically (ally centroid, enemy stats, who is already being attacked).
local M = {}

-- 3-second buckets: bots recompute on the same schedule, so they agree
-- within a bucket and switch targets simultaneously.
function M.Bucket(t)
	return math.floor(t / 3)
end

-- env (all functions injected; see TeamFocusEnv in jmz_func.lua):
--   vector(x, y), allies(), alliesNear(loc, r), enemiesNear(loc, r),
--   isValidTarget(u), nearEnemyTower(loc, r), distToLoc(u, loc),
--   isLaningPhase()
function M.Compute(env, iq)
	-- no calls during laning: lane fights are served by the local
	-- focus-fire bonuses, and early "hunt" calls waste smokes
	if env.isLaningPhase() then return nil end
	local tAllies = env.allies()
	if #tAllies < 2 then return nil end
	local x, y = 0, 0
	for _, a in ipairs(tAllies) do
		local v = a.GetLocation()
		x = x + v.x
		y = y + v.y
	end
	local vCentroid = env.vector(x / #tAllies, y / #tAllies)

	-- fight mode: enemies already close to the grouped team.
	local tCandidates = env.enemiesNear(vCentroid, 1600)
	if #tCandidates == 0 and iq.Team_Hunt ~= false then
		-- hunt mode: an isolated, reachable enemy away from towers
		-- (same rules the old stored-call ConsiderHuntCall used).
		for _, e in ipairs(env.enemiesNear(vCentroid, 3000)) do
			if #env.enemiesNear(e.GetLocation(), 1600) <= 1
			and #env.alliesNear(e.GetLocation(), 3500) >= 2
			and not env.nearEnemyTower(e.GetLocation(), 900) then
				tCandidates[#tCandidates + 1] = e
			end
		end
	end

	local best, bestScore = nil, math.huge
	for _, e in ipairs(tCandidates) do
		if env.isValidTarget(e) then
			local nAttackers = 0
			for _, a in ipairs(tAllies) do
				-- compare raw engine handles: GetAttackTarget returns a real
				-- handle, e is a wrapper carrying its handle in .handle
				if a.GetAttackTarget() == e.handle then nAttackers = nAttackers + 1 end
			end
			local fArmor = e.GetArmor()
			local fEffHP = e.GetHealth() / (1 - ((0.06 * fArmor) / (1 + 0.06 * math.abs(fArmor))))
			local score = fEffHP
			if e.IsStunned() or e.IsHexed() or e.IsRooted() or e.IsNightmared() then
				score = score - e.GetMaxHealth() * 0.12
			end
			score = score - nAttackers * e.GetMaxHealth() * 0.08
			if e.GetAttackRange() >= 550 then
				score = score - e.GetMaxHealth() * 0.06
			end
			score = score + env.distToLoc(e, vCentroid) * 0.15
			if score < bestScore then
				best, bestScore = e, score
			end
		end
	end
	return best
end

return M
