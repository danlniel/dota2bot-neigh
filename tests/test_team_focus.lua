-- Run from repo root: luajit tests/test_team_focus.lua
package.path = package.path .. ';./bots/FunLib/?.lua'
local TF = require('team_focus')

local function unit(name, opts)
	opts = opts or {}
	local u = {}
	u.GetLocation = function() return { x = opts.x or 0, y = opts.y or 0 } end
	u.GetArmor = function() return opts.armor or 0 end
	u.GetHealth = function() return opts.hp or 1000 end
	u.GetMaxHealth = function() return opts.maxhp or 1000 end
	u.GetAttackRange = function() return opts.range or 150 end
	u.GetAttackTarget = function() return opts.attacking end
	u.IsStunned = function() return opts.stunned or false end
	u.IsHexed = function() return false end
	u.IsRooted = function() return false end
	u.IsNightmared = function() return false end
	u.GetUnitName = function() return name end
	u.handle = u -- production wrappers carry the real engine handle here
	return u
end

local function makeEnv(allies, enemies)
	local function near(list, loc, r)
		local t = {}
		for _, u in ipairs(list) do
			local ul = u.GetLocation()
			local dx, dy = ul.x - loc.x, ul.y - loc.y
			if math.sqrt(dx * dx + dy * dy) <= r then t[#t + 1] = u end
		end
		return t
	end
	return {
		vector = function(x, y) return { x = x, y = y } end,
		allies = function() return allies end,
		alliesNear = function(loc, r) return near(allies, loc, r) end,
		enemiesNear = function(loc, r) return near(enemies, loc, r) end,
		isValidTarget = function() return true end,
		nearEnemyTower = function() return false end,
		isLaningPhase = function() return false end,
		distToLoc = function(u, loc)
			local ul = u.GetLocation()
			local dx, dy = ul.x - loc.x, ul.y - loc.y
			return math.sqrt(dx * dx + dy * dy)
		end,
	}
end

-- determinism: identical inputs -> identical target, every call
local a1, a2 = unit('ally1', { x = 0, y = 0 }), unit('ally2', { x = 200, y = 0 })
local e1 = unit('tanky', { x = 500, y = 0, hp = 2000, maxhp = 2000 })
local e2 = unit('squishy', { x = 600, y = 0, hp = 900, maxhp = 900 })
local env = makeEnv({ a1, a2 }, { e1, e2 })
local first = TF.Compute(env, {})
assert(first == e2, 'squishier enemy wins on effective HP')
for i = 1, 5 do
	assert(TF.Compute(env, {}) == first, 'must be deterministic across calls')
end

-- disabled targets are preferred over an otherwise-identical enemy
local d1 = unit('healthy', { x = 500, y = 0 })
local d2 = unit('stunned', { x = 500, y = 100, stunned = true })
assert(TF.Compute(makeEnv({ a1, a2 }, { d1, d2 }), {}) == d2)

-- long-range backliners are preferred over an otherwise-identical melee
local m = unit('melee', { x = 500, y = 0 })
local s = unit('sniper', { x = 500, y = 100, range = 950 })
assert(TF.Compute(makeEnv({ a1, a2 }, { m, s }), {}) == s)

-- hunt mode: no enemy near the group, but an isolated one in reach is called
local far = unit('farmer', { x = 2500, y = 0 })
assert(TF.Compute(makeEnv({ a1, a2 }, { far }), {}) == far)

-- no candidates at all -> nil
assert(TF.Compute(makeEnv({ a1, a2 }, {}), {}) == nil)

-- laning phase -> never any call (guard kept from the old hunt code)
local laneEnv = makeEnv({ a1, a2 }, { e1, e2 })
laneEnv.isLaningPhase = function() return true end
assert(TF.Compute(laneEnv, {}) == nil)

-- buckets: 3-second windows
assert(TF.Bucket(0) == 0 and TF.Bucket(2.9) == 0 and TF.Bucket(3.0) == 1 and TF.Bucket(7.5) == 2)

print('test_team_focus: all assertions passed')
