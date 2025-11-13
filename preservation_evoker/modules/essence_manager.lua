--[[
    Essence Manager Module for Preservation Evoker

    Intelligent essence resource management and optimization.
    Tracks essence generation, predicts future essence, and determines
    optimal spending priorities based on combat situation.

    Features:
    - Essence tracking and prediction
    - Spend priority determination
    - Resource pooling logic
    - Essence Burst proc tracking
    - Cost validation for abilities
]]

local izi = require("common/izi_sdk")
local enums = require("common/enums")

---@class essence_manager
local essence_manager = {}

-- Essence costs for abilities
local ESSENCE_COSTS = {
    [364343] = 2,  -- Echo
    [355913] = 3,  -- Emerald Blossom
    [356995] = 3,  -- Disintegrate
}

-- Essence Burst buff ID
local ESSENCE_BURST_BUFF = 369256

---Get current essence
---@param me game_object
---@return number essence Current essence amount
function essence_manager.get_essence(me)
    return me:power(enums.power_type.ESSENCE)
end

---Get max essence
---@param me game_object
---@return number max_essence Maximum essence capacity
function essence_manager.get_max_essence(me)
    return me:max_power(enums.power_type.ESSENCE)
end

---Check if we have enough essence for a spell
---@param me game_object
---@param spell_id number
---@return boolean can_cast True if enough essence
function essence_manager.can_cast(me, spell_id)
    local cost = ESSENCE_COSTS[spell_id] or 0
    return essence_manager.get_essence(me) >= cost
end

---Predict essence in X seconds
---@param me game_object
---@param seconds number Time in seconds to predict ahead
---@return number predicted_essence Predicted essence amount
function essence_manager.predict_essence(me, seconds)
    local current = essence_manager.get_essence(me)
    local regen_rate = 0.2  -- Base: 1 essence per 5 seconds

    -- Check for Essence Burst proc (grants 1 essence immediately on next cast)
    if me:has_buff(ESSENCE_BURST_BUFF) then
        current = current + 1
    end

    local predicted = current + (regen_rate * seconds)
    return math.min(predicted, essence_manager.get_max_essence(me))
end

---@alias spend_priority "echo_setup"|"emerald_blossom"|"spend_any"|"conserve"

---Determine essence spending priority based on situation
---@param me game_object
---@param injured_count number Number of injured allies
---@param avg_health_pct number Average health percentage
---@return spend_priority priority Spending recommendation
function essence_manager.get_spend_priority(me, injured_count, avg_health_pct)
    local essence = essence_manager.get_essence(me)
    local max_essence = essence_manager.get_max_essence(me)

    -- Near cap - spend anything to avoid waste
    if essence >= max_essence - 1 then
        return "spend_any"
    end

    -- Check if Echo setup is needed (for Chronowarden)
    if essence >= 2 then
        -- This would require checking active echoes on party
        -- Simplified version: recommend echo if we have 4+ essence and multiple injured
        if essence >= 4 and injured_count >= 2 then
            return "echo_setup"
        end
    end

    -- Check for AoE healing need
    if essence >= 3 and injured_count >= 3 then
        return "emerald_blossom"
    end

    -- Conserve essence if low
    return "conserve"
end

---Should we pool essence for upcoming damage?
---@param me game_object
---@param time_to_damage number Time until major damage (in seconds)
---@return boolean should_pool True if we should conserve essence
function essence_manager.should_pool(me, time_to_damage)
    time_to_damage = time_to_damage or 5.0

    local current = essence_manager.get_essence(me)
    local max = essence_manager.get_max_essence(me)

    -- Don't pool if near cap (would waste regen)
    if current >= max - 1 then
        return false
    end

    -- Pool if big damage coming soon and we're low on essence
    if time_to_damage <= 3.0 and current < 4 then
        return true
    end

    return false
end

---Check if we have Essence Burst proc active
---@param me game_object
---@return boolean has_proc True if Essence Burst is active
function essence_manager.has_essence_burst(me)
    return me:has_buff(ESSENCE_BURST_BUFF)
end

---Get essence deficit (how much essence we need to cap)
---@param me game_object
---@return number deficit Essence needed to reach cap
function essence_manager.get_essence_deficit(me)
    local current = essence_manager.get_essence(me)
    local max = essence_manager.get_max_essence(me)
    return max - current
end

---Calculate time until essence cap (assuming no spending)
---@param me game_object
---@return number time_to_cap Time in seconds until capped
function essence_manager.time_to_cap(me)
    local deficit = essence_manager.get_essence_deficit(me)
    if deficit <= 0 then
        return 0
    end

    local regen_rate = 0.2  -- 1 essence per 5 seconds
    return deficit / regen_rate
end

return essence_manager
