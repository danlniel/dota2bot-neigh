-- House-rule hero handicap (spec 2026-08-19 item 10). Numbers come from
-- HeroHandicap.settings via AddNewModifier kv params. Visible on purpose:
-- an honest debuff, unpurgable, survives death.
if modifier_neigh_handicap == nil then modifier_neigh_handicap = class({}) end

function modifier_neigh_handicap:IsHidden() return false end
function modifier_neigh_handicap:IsDebuff() return true end
function modifier_neigh_handicap:IsPurgable() return false end
function modifier_neigh_handicap:IsPurgeException() return false end
function modifier_neigh_handicap:IsPermanent() return true end
function modifier_neigh_handicap:RemoveOnDeath() return false end

function modifier_neigh_handicap:GetAttributes()
    return MODIFIER_ATTRIBUTE_PERMANENT + MODIFIER_ATTRIBUTE_IGNORE_INVULNERABLE
end

function modifier_neigh_handicap:OnCreated(kv)
    if not IsServer() then return end
    self.damagePct = kv.damagePct or 0
    self.attackRange = kv.attackRange or 0
end

function modifier_neigh_handicap:DeclareFunctions()
    return {
        MODIFIER_PROPERTY_BASEDAMAGEOUTGOING_PERCENTAGE,
        MODIFIER_PROPERTY_ATTACK_RANGE_BONUS,
    }
end

function modifier_neigh_handicap:GetModifierBaseDamageOutgoing_Percentage()
    return self.damagePct or 0
end

function modifier_neigh_handicap:GetModifierAttackRangeBonus()
    return self.attackRange or 0
end
