--[[
    Healing Calculator Module for Preservation Evoker

    Sophisticated healing calculations with mastery, versatility, and crit considerations.
    Calculates effective healing needed, estimates spell healing output, and determines
    healing efficiency for optimal spell selection.

    Features:
    - Effective healing need calculation
    - Mastery: Life-Binder bonus calculation
    - Versatility and crit multipliers
    - Empower rank scaling
    - AoE healing efficiency analysis
    - Overheal prediction
]]

local izi = require("common/izi_sdk")
local enums = require("common/enums")
local BUFFS = enums.buff_db

---@class healing_calculator
local healing_calculator = {}

-- Spell healing coefficients (spell power multipliers)
local SPELL_HEALING_COEFFICIENTS = {
    [355941] = 4.5,   -- Dream Breath (base)
    [367364] = 3.8,   -- Spiritbloom (base)
    [361227] = 2.2,   -- Living Flame
    [355913] = 2.8,   -- Emerald Blossom
    [364343] = 1.5,   -- Echo
    [360995] = 3.2,   -- Verdant Embrace
    [366155] = 2.5,   -- Reversion
    [382614] = 3.5,   -- Engulf (Flameshaper)
}

---@class healing_need
---@field missing_hp number HP missing from max
---@field incoming_damage number Predicted incoming damage
---@field hot_healing number Healing from existing HoTs
---@field total_need number Total effective healing needed
---@field percent_need number Percentage of max HP needed

---Calculate effective healing needed for a unit
---@param unit game_object
---@param me game_object
---@return healing_need need Healing need breakdown
function healing_calculator.calculate_healing_needed(unit, me)
    local current_hp = unit:health()
    local max_hp = unit:health_max()
    local missing_hp = max_hp - current_hp

    -- Factor in incoming damage (next 2 seconds)
    local incoming = unit:get_incoming_damage(2.0)

    -- Factor in existing HoTs
    local hot_healing = 0
    local sp = me:get_spell_power()

    -- Reversion HoT estimation
    if unit:has_buff(366155) then
        local remaining = unit:buff_remains_sec(366155)
        hot_healing = hot_healing + (sp * 0.8 * (remaining / 2))  -- Rough estimate
    end

    -- Dream Breath HoT estimation
    if unit:has_buff(355941) then
        local remaining = unit:buff_remains_sec(355941)
        hot_healing = hot_healing + (sp * 1.2 * (remaining / 2))
    end

    local effective_need = missing_hp + incoming - hot_healing

    return {
        missing_hp = missing_hp,
        incoming_damage = incoming,
        hot_healing = hot_healing,
        total_need = math.max(0, effective_need),
        percent_need = (effective_need / max_hp) * 100
    }
end

---Calculate mastery bonus (Life-Binder)
---Increases healing based on healer's health % vs target health %
---@param me game_object
---@param target game_object
---@return number multiplier Mastery multiplier (1.0 = no bonus)
function healing_calculator.calculate_mastery_bonus(me, target)
    local my_health_pct = me:get_health_percentage()
    local target_health_pct = target:get_health_percentage()

    if my_health_pct > target_health_pct then
        local mastery = me:get_mastery_percent()
        local health_diff = my_health_pct - target_health_pct
        local bonus = (health_diff / 100) * mastery
        return 1 + (bonus / 100)
    end

    return 1.0
end

---Estimate spell healing amount
---@param spell_id number Spell ID
---@param me game_object
---@param target game_object
---@param empower_rank number|nil Empower rank (0-4, default: 0)
---@return number healing Estimated healing amount
function healing_calculator.estimate_heal_amount(spell_id, me, target, empower_rank)
    empower_rank = empower_rank or 0

    local base_coeff = SPELL_HEALING_COEFFICIENTS[spell_id] or 1.0
    local sp = me:get_spell_power()
    local vers = me:get_versatility_percent()
    local crit = me:get_crit_percent()

    local base = base_coeff * sp

    -- Empower bonus (25% per rank)
    if empower_rank > 0 then
        base = base * (1 + (empower_rank * 0.25))
    end

    -- Mastery bonus
    local mastery_mult = healing_calculator.calculate_mastery_bonus(me, target)

    -- Versatility multiplier
    local vers_mult = 1 + (vers / 100)

    -- Estimate crit (simplified - assume 50% crit heals for 2x)
    local crit_mult = 1 + ((crit / 100) * 0.5)

    return base * mastery_mult * vers_mult * crit_mult
end

---@class healing_efficiency
---@field total number Total potential healing
---@field effective number Effective healing (no overheal)
---@field efficiency number Efficiency percentage
---@field overheal number Predicted overheal amount

---Calculate AoE healing efficiency
---@param spell_id number
---@param me game_object
---@param targets game_object[]
---@param empower_rank number|nil
---@return healing_efficiency efficiency Efficiency breakdown
function healing_calculator.calculate_aoe_efficiency(spell_id, me, targets, empower_rank)
    local total_healing = 0
    local effective_healing = 0

    for i = 1, #targets do
        local target = targets[i]
        local heal_amount = healing_calculator.estimate_heal_amount(spell_id, me, target, empower_rank)
        local healing_need = healing_calculator.calculate_healing_needed(target, me)

        total_healing = total_healing + heal_amount
        effective_healing = effective_healing + math.min(heal_amount, healing_need.total_need)
    end

    local efficiency = total_healing > 0 and (effective_healing / total_healing) * 100 or 0

    return {
        total = total_healing,
        effective = effective_healing,
        efficiency = efficiency,
        overheal = total_healing - effective_healing
    }
end

---Check if healing would be wasted (overheal check)
---@param spell_id number
---@param me game_object
---@param target game_object
---@param overheal_tolerance number Acceptable overheal % (default: 50)
---@return boolean would_overheal True if significant overheal predicted
function healing_calculator.would_overheal(spell_id, me, target, overheal_tolerance)
    overheal_tolerance = overheal_tolerance or 50

    local heal_amount = healing_calculator.estimate_heal_amount(spell_id, me, target)
    local healing_need = healing_calculator.calculate_healing_needed(target, me)

    if healing_need.total_need <= 0 then
        return true  -- No healing needed
    end

    local overheal_pct = ((heal_amount - healing_need.total_need) / heal_amount) * 100

    return overheal_pct > overheal_tolerance
end

return healing_calculator
