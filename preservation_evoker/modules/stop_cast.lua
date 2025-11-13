--[[
    Stop Cast Module for Preservation Evoker

    Intelligent spell interruption and recasting decisions.
    Determines when to cancel casts based on changing priorities,
    overheal predictions, and emergency situations.

    Features:
    - Cast tracking (spell ID, target, start time)
    - Overheal prediction for cast cancellation
    - Emergency interruption logic
    - Optimal empower rank calculation
    - Early empower release decision making
]]

local izi = require("common/izi_sdk")
local enums = require("common/enums")

---@class stop_cast
local stop_cast = {}

---@class cast_info
---@field spell_id number
---@field target game_object|nil
---@field start_time number
---@field empower_rank number

-- Cached cast info
---@type cast_info
local current_cast = {
    spell_id = 0,
    target = nil,
    start_time = 0,
    empower_rank = 0
}

-- Empower spell max ranks
local EMPOWER_MAX_RANKS = {
    [355941] = 4,  -- Dream Breath
    [367364] = 4,  -- Spiritbloom
    [357208] = 4,  -- Fire Breath
}

---Update current cast info (call every frame)
---@param me game_object
function stop_cast.update_cast_info(me)
    if me:is_casting() or me:is_channeling() then
        -- Only update if we don't have cast info yet
        if current_cast.spell_id == 0 then
            current_cast.spell_id = me:get_cast_spell_id()
            current_cast.start_time = core.time()
        end
    else
        -- Clear cast info when not casting
        current_cast = {
            spell_id = 0,
            target = nil,
            start_time = 0,
            empower_rank = 0
        }
    end
end

---Should we stop the current cast?
---@param me game_object
---@param healing_calculator any Healing calculator module
---@param target_selector any Target selector module
---@return boolean should_stop True if cast should be interrupted
function stop_cast.should_stop_cast(me, healing_calculator, target_selector)
    if not me:is_casting() and not me:is_channeling() then
        return false
    end

    local spell = current_cast.spell_id
    local target = current_cast.target

    -- Don't interrupt instant casts or casts almost finished
    if me:is_casting() then
        local remaining = me:get_cast_time_remaining()
        if remaining < 0.2 then
            return false
        end
    end

    -- Check if target will be overhealed
    if target and target:is_alive() then
        local heal_amount = healing_calculator.estimate_heal_amount(spell, me, target, current_cast.empower_rank)
        local need = healing_calculator.calculate_healing_needed(target, me)

        -- Stop if we'll overheal by more than 50%
        if heal_amount > need.total_need * 1.5 and need.total_need > 0 then
            -- Check for higher priority emergency target
            local emergency_target = target_selector.get_best_heal_target(me, 40, 30)
            if emergency_target and emergency_target:get_guid() ~= target:get_guid() then
                local emergency_need = healing_calculator.calculate_healing_needed(emergency_target, me)
                if emergency_need.percent_need > 50 then
                    return true  -- Stop for emergency
                end
            end
        end
    end

    -- Check for emergency situations that override current cast
    local emergency_target = target_selector.get_best_heal_target(me, 25, 30)
    if emergency_target and (not target or emergency_target:get_guid() ~= target:get_guid()) then
        -- Stop empowered spells for critical emergencies
        if spell == 355941 or spell == 367364 then  -- Dream Breath / Spiritbloom
            return true
        end
    end

    return false
end

---Get optimal empower rank for a spell based on healing need
---@param spell_id number
---@param target game_object
---@param healing_calculator any
---@return number rank Optimal empower rank (1-4)
function stop_cast.get_optimal_empower_rank(spell_id, target, healing_calculator)
    local max_rank = EMPOWER_MAX_RANKS[spell_id] or 1

    -- For healing spells, calculate based on need
    if spell_id == 355941 or spell_id == 367364 then  -- Dream Breath or Spiritbloom
        if not target then
            return 2  -- Default moderate rank
        end

        local need = healing_calculator.calculate_healing_needed(target, izi.me())

        -- Emergency = quick rank 1
        if need.percent_need > 70 then
            return 1  -- Get healing out ASAP
        end

        -- High need = max rank
        if need.percent_need > 50 then
            return max_rank
        end

        -- Moderate need = rank 2-3
        if need.percent_need > 30 then
            return math.ceil(max_rank * 0.75)
        end

        -- Light damage = rank 1-2
        return math.ceil(max_rank * 0.5)
    end

    -- Fire Breath - always use for damage
    if spell_id == 357208 then
        return max_rank
    end

    return 2  -- Default
end

---Should we release empowered spell early?
---@param me game_object
---@param target_selector any
---@return boolean should_release True if should release now
function stop_cast.should_release_empower(me, target_selector)
    if not me:is_channeling() then
        return false
    end

    local spell = current_cast.spell_id
    local max_rank = EMPOWER_MAX_RANKS[spell]

    if not max_rank then
        return false  -- Not an empower spell
    end

    local channel_time = core.time() - current_cast.start_time

    -- Estimate current rank based on channel time
    -- Each rank takes approximately 0.75-1.0 seconds
    local current_rank = math.floor(channel_time / 0.85) + 1
    current_rank = math.min(current_rank, max_rank)

    -- Store current rank for overheal calculations
    current_cast.empower_rank = current_rank

    -- Check if we've reached a reasonable rank
    if current_rank >= 2 then
        -- Check for emergencies - release early if needed
        local emergency_target = target_selector.get_best_heal_target(me, 25, 30)
        if emergency_target then
            return true  -- Release for emergency
        end

        -- If target is topped off, release early
        if current_cast.target then
            local target_hp = current_cast.target:get_health_percentage()
            if target_hp > 90 then
                return true  -- No need to continue channeling
            end
        end
    end

    -- Check if we've hit max rank
    if current_rank >= max_rank then
        return true
    end

    -- Check if we need to move soon (NYI - would need evade_helper integration)
    -- For now, just return false and continue channeling

    return false
end

---Set the current cast target (for overheal checking)
---@param target game_object|nil
function stop_cast.set_cast_target(target)
    current_cast.target = target
end

---Get current cast information
---@return cast_info info Current cast data
function stop_cast.get_current_cast()
    return current_cast
end

return stop_cast
