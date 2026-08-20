-- House-rule per-hero handicap (spec 2026-08-19 item 10). Applies a
-- permanent debuff to every hero named below — human or bot alike, so the
-- rule is symmetric. Tune or empty the table to change/remove the nerf.
require 'bots.FretBots.Utilities'
require 'bots.FretBots.modifiers.modifier_neigh_handicap'

if HeroHandicap == nil then
	HeroHandicap = {}
end

HeroHandicap.settings = {
	-- -12% base attack damage, -100 attack range (max Take Aim 950 -> 850)
	npc_dota_hero_sniper = { damagePct = -12, attackRange = -100 },
}

local announced = {}

function HeroHandicap:Apply(unit)
	if unit == nil or not unit.IsRealHero or not unit:IsRealHero() then return end
	local cfg = HeroHandicap.settings[unit:GetUnitName()]
	if cfg == nil then return end
	if unit:HasModifier('modifier_neigh_handicap') then return end
	unit:AddNewModifier(unit, nil, 'modifier_neigh_handicap',
		{ damagePct = cfg.damagePct, attackRange = cfg.attackRange })
	if not announced[unit:GetUnitName()] then
		announced[unit:GetUnitName()] = true
		Utilities:Print('House rule: '..unit:GetUnitName()..' handicapped ('
			..(cfg.damagePct or 0)..'% dmg, '..(cfg.attackRange or 0)..' range)')
	end
end

function HeroHandicap:Initialize()
	-- LinkLuaModifier path is relative to vscripts/; try both known layouts
	-- (repo copy under bots/, workshop copy at root) — pcall keeps a miss
	-- harmless.
	pcall(LinkLuaModifier, 'modifier_neigh_handicap',
		'bots/FretBots/modifiers/modifier_neigh_handicap', LUA_MODIFIER_MOTION_NONE)
	pcall(LinkLuaModifier, 'modifier_neigh_handicap',
		'FretBots/modifiers/modifier_neigh_handicap', LUA_MODIFIER_MOTION_NONE)
	ListenToGameEvent('npc_spawned', Dynamic_Wrap(HeroHandicap, 'OnNPCSpawned'), HeroHandicap)
end

function HeroHandicap:OnNPCSpawned(event)
	local spawnedUnit = EntIndexToHScript(event.entindex)
	HeroHandicap:Apply(spawnedUnit)
end
