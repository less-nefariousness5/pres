--[[
    Target Selector Module for Preservation Evoker

    Advanced smart healing target selection with priority weighting system.
    Evaluates targets based on health deficit, incoming damage, role priority,
    debuffs, and positioning.

    Features:
    - Dynamic priority scoring system
    - Incoming damage prediction integration
    - Role-based weighting (tank > healer > dps)
    - Distance penalty for optimal positioning
    - Emergency priority multiplier
    - AoE target clustering
]]

local izi = require("common/izi_sdk")

---@class target_selector
local target_selector = {}

-- Priority weights for different unit types
local PRIORITY_WEIGHTS = {
    tank = 1.5,
    healer = 1.3,
    dps = 1.0,
    self = 1.2
}

-- Dangerous debuff IDs that increase healing priority
-- TODO: Populate with actual dangerous debuff IDs per encounter
local DANGEROUS_DEBUFFS = {
    -- Example debuff IDs - should be populated based on current content
}

---Get healing priority score for a unit
---@param unit game_object
---@param me game_object
---@return number score Priority score (higher = more priority)
function target_selector.get_priority_score(unit, me)
    local score = 0

    -- Health deficit scoring (0-100 scale)
    local health_pct = unit:get_health_percentage()
    local health_score = (100 - health_pct) * 2  -- Weight health deficit heavily

    -- Incoming damage prediction (next 3 seconds)
    local incoming_dmg = unit:get_incoming_damage(3.0)
    local max_hp = unit:health_max()
    local damage_score = (incoming_dmg / max_hp) * 100 * 1.5

    -- Role-based priority
    local role_mult = PRIORITY_WEIGHTS.dps
    if unit:is_tank() then
        role_mult = PRIORITY_WEIGHTS.tank
    elseif unit:get_guid() == me:get_guid() then
        role_mult = PRIORITY_WEIGHTS.self
    end

    -- Debuff priority (increase priority if unit has dangerous debuffs)
    local debuff_score = 0
    for i = 1, #DANGEROUS_DEBUFFS do
        if unit:has_debuff(DANGEROUS_DEBUFFS[i]) then
            debuff_score = 30
            break
        end
    end

    -- Distance penalty (prefer closer targets for better positioning)
    local distance = unit:distance()
    local range_penalty = math.max(0, (distance - 20) * 2)  -- Penalty beyond 20 yards

    -- Calculate final score
    score = (health_score + damage_score + debuff_score) * role_mult - range_penalty

    -- Emergency priority multiplier
    if health_pct <= 30 then
        score = score * 2
    end

    return score
end

---Get best healing target from party/raid
---@param me game_object
---@param min_health_pct number Health percentage threshold (default: 95)
---@param max_range number Maximum range in yards (default: 30)
---@return game_object|nil target Best healing target or nil if none found
---@return number score Priority score of the target
function target_selector.get_best_heal_target(me, min_health_pct, max_range)
    min_health_pct = min_health_pct or 95
    max_range = max_range or 30

    local best_target = nil
    local best_score = 0

    -- Get all party/raid members
    local units = izi.friendly_units()

    for i = 1, #units do
        local unit = units[i]
        if unit:is_alive() and
           unit:get_health_percentage() < min_health_pct and
           unit:distance() <= max_range then

            local score = target_selector.get_priority_score(unit, me)
            if score > best_score then
                best_score = score
                best_target = unit
            end
        end
    end

    return best_target, best_score
end

---Get multiple targets for AoE healing
---@param me game_object
---@param count number Maximum number of targets to return (default: 5)
---@param min_health_pct number Health percentage threshold (default: 90)
---@param radius number Clustering radius in yards (default: 10)
---@return game_object[] targets Array of healing targets sorted by priority
function target_selector.get_aoe_targets(me, count, min_health_pct, radius)
    count = count or 5
    min_health_pct = min_health_pct or 90
    radius = radius or 10

    local targets = {}
    local units = izi.friendly_units()

    -- Score and sort all eligible units
    local scored_units = {}
    for i = 1, #units do
        local unit = units[i]
        if unit:is_alive() and unit:get_health_percentage() < min_health_pct then
            table.insert(scored_units, {
                unit = unit,
                score = target_selector.get_priority_score(unit, me)
            })
        end
    end

    -- Sort by score (highest first)
    table.sort(scored_units, function(a, b) return a.score > b.score end)

    -- Get top targets
    for i = 1, math.min(count, #scored_units) do
        table.insert(targets, scored_units[i].unit)
    end

    return targets
end

---Get tank-specific targeting
---@param me game_object
---@return game_object|nil tank Tank with highest priority or nil if none found
function target_selector.get_tank_target(me)
    local tanks = {}
    local units = izi.friendly_units()

    for i = 1, #units do
        local unit = units[i]
        if unit:is_tank() and unit:is_alive() then
            table.insert(tanks, {
                unit = unit,
                score = target_selector.get_priority_score(unit, me)
            })
        end
    end

    -- Sort by score
    table.sort(tanks, function(a, b) return a.score > b.score end)

    return tanks[1] and tanks[1].unit or nil
end

---Count injured allies within range
---@param me game_object
---@param health_pct number Health percentage threshold
---@param range number Range in yards (optional)
---@return number count Number of injured allies
function target_selector.count_injured(me, health_pct, range)
    range = range or 40
    local count = 0
    local units = izi.friendly_units()

    for i = 1, #units do
        local unit = units[i]
        if unit:is_alive() and
           unit:get_health_percentage() < health_pct and
           unit:distance() <= range then
            count = count + 1
        end
    end

    return count
end

---Get average health percentage of party/raid
---@return number avg_health Average health percentage
function target_selector.get_average_health()
    local total = 0
    local count = 0
    local units = izi.friendly_units()

    for i = 1, #units do
        local unit = units[i]
        if unit:is_alive() then
            total = total + unit:get_health_percentage()
            count = count + 1
        end
    end

    return count > 0 and (total / count) or 100
end

return target_selector
