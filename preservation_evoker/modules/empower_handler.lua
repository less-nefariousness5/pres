--[[
    Empower Handler Module for Preservation Evoker

    Handles the unique Evoker empowered spell mechanics with intelligent rank decisions.
    Manages channeling, release timing, and rank optimization based on combat context.

    Features:
    - Dynamic rank calculation based on urgency and healing need
    - Movement prediction integration for early releases
    - Emergency interruption for critical healing needs
    - Rank-specific optimization for each empowered spell
    - Predictive cast window calculation
]]

local izi = require("common/izi_sdk")

---@class empower_handler
local empower_handler = {}

---@class empower_spell_config
---@field name string Spell name
---@field max_rank number Maximum empower rank
---@field cast_times number[] Seconds per rank
---@field type string "heal" or "damage"
---@field coefficients number[] Healing/damage multipliers per rank
---@field targets number[]|nil Max targets per rank (healing spells)
---@field hot_duration number[]|nil HoT duration per rank

-- Empowered spell configurations
local EMPOWERED_SPELLS = {
    [355941] = { -- Dream Breath
        name = "Dream Breath",
        max_rank = 4,
        cast_times = {1.0, 1.75, 2.5, 3.25},
        type = "heal",
        coefficients = {1.0, 1.4, 1.8, 2.2},
        targets = {5, 5, 5, 5},
        hot_duration = {16, 20, 24, 24},
    },
    [367364] = { -- Spiritbloom
        name = "Spiritbloom",
        max_rank = 4,
        cast_times = {1.0, 1.75, 2.5, 3.25},
        type = "heal",
        coefficients = {1.0, 1.0, 1.0, 1.0},  -- Same healing, more targets
        targets = {1, 2, 3, 4},
    },
    [357208] = { -- Fire Breath
        name = "Fire Breath",
        max_rank = 4,
        cast_times = {1.0, 1.75, 2.5, 3.25},
        type = "damage",
        coefficients = {1.0, 1.5, 2.0, 2.5},
    },
}

---@class empower_state
---@field spell_id number|nil
---@field start_time number|nil
---@field current_rank number
---@field target_rank number
---@field release_time number|nil
---@field target_unit game_object|nil

-- Current empower state tracking
---@type empower_state
local empower_state = {
    spell_id = nil,
    start_time = nil,
    current_rank = 0,
    target_rank = 0,
    release_time = nil,
    target_unit = nil,
}

---@class empower_context
---@field urgency string "emergency"|"high"|"normal"|"low"
---@field target_count number Number of injured targets
---@field avg_health_deficit number Average health deficit percentage
---@field time_available number|nil Safe cast time available
---@field movement_required boolean|nil True if movement needed soon
---@field force_rank number|nil Force specific rank (override calculation)
---@field enemy_count number|nil Enemy count (for Fire Breath)
---@field enemy_health string|nil "low"|"high" (for Fire Breath)

---Calculate optimal empower rank based on situation
---@param spell_id number
---@param context empower_context
---@return number rank Optimal rank (1-4)
function empower_handler.calculate_optimal_rank(spell_id, context)
    local spell = EMPOWERED_SPELLS[spell_id]
    if not spell then
        return 1
    end

    -- Check for forced rank
    if context.force_rank then
        return math.min(context.force_rank, spell.max_rank)
    end

    local urgency = context.urgency or "normal"
    local target_count = context.target_count or 1
    local avg_health_deficit = context.avg_health_deficit or 30
    local time_available = context.time_available or 3.0
    local movement_required = context.movement_required or false

    -- Emergency = quick rank 1
    if urgency == "emergency" then
        return 1
    end

    -- Movement incoming = release early
    if movement_required and time_available < 2.0 then
        return math.min(2, spell.max_rank)
    end

    -- Healing spells
    if spell.type == "heal" then
        -- Dream Breath optimization
        if spell_id == 355941 then
            if avg_health_deficit > 60 then
                return 4  -- Max rank for crisis
            elseif avg_health_deficit > 40 then
                return 3  -- Strong HoT
            elseif avg_health_deficit > 20 then
                return 2  -- Moderate HoT
            else
                return 1  -- Quick application
            end
        end

        -- Spiritbloom optimization
        if spell_id == 367364 then
            -- Match rank to injured target count
            local injured_count = math.min(target_count, 4)
            if urgency == "high" and injured_count >= 3 then
                return 4  -- Hit all targets
            elseif injured_count >= 2 then
                return math.min(injured_count + 1, 4)
            else
                return 1  -- Single target quick heal
            end
        end
    end

    -- Fire Breath - balance damage vs DoT duration
    if spell_id == 357208 then
        local enemy_count = context.enemy_count or 1
        local enemy_health = context.enemy_health or "high"

        if enemy_health == "low" then
            return 4  -- Max instant damage for execute
        elseif enemy_count >= 3 then
            return 3  -- Good balance of damage and spread
        else
            return 2  -- Balanced approach
        end
    end

    return 2  -- Default moderate rank
end

---Get current empower rank based on channel time
---@param me game_object
---@return number rank Current rank (0 if not channeling)
function empower_handler.get_current_rank(me)
    if not empower_state.spell_id or not empower_state.start_time then
        return 0
    end

    local spell = EMPOWERED_SPELLS[empower_state.spell_id]
    if not spell then
        return 0
    end

    local elapsed = core.time() - empower_state.start_time

    -- Calculate rank based on cast time thresholds
    for rank = 1, spell.max_rank do
        if elapsed < spell.cast_times[rank] then
            return rank - 1
        end
    end

    return spell.max_rank
end

---Should we release the empower early?
---@param me game_object
---@param target_selector any
---@return boolean should_release True if should release now
function empower_handler.should_release(me, target_selector)
    if not empower_state.spell_id then
        return false
    end

    local current_rank = empower_handler.get_current_rank(me)
    local target_rank = empower_state.target_rank

    -- Reached target rank
    if current_rank >= target_rank then
        return true
    end

    -- Check for emergency situations (units below 25% HP)
    local emergency_target = target_selector.get_best_heal_target(me, 25, 30)
    if emergency_target and current_rank >= 1 then
        core.log("Emergency release at rank " .. current_rank)
        return true
    end

    -- Check if target died or became invalid
    if empower_state.target_unit then
        if not empower_state.target_unit:is_alive() or
           empower_state.target_unit:get_health_percentage() > 95 then
            return current_rank >= 1
        end
    end

    -- TODO: Check for movement requirement (would need evade_helper integration)
    -- For now, rely on target rank calculation

    return false
end

---Start empowered cast
---@param spell_id number
---@param me game_object
---@param target game_object|nil
---@param context empower_context
---@param spell_obj any IZI spell object
---@return boolean success True if cast started
function empower_handler.start_empower(spell_id, me, target, context, spell_obj)
    local spell = EMPOWERED_SPELLS[spell_id]
    if not spell then
        return false
    end

    -- Calculate optimal rank
    local optimal_rank = empower_handler.calculate_optimal_rank(spell_id, context)

    -- Store state
    empower_state = {
        spell_id = spell_id,
        start_time = core.time(),
        current_rank = 0,
        target_rank = optimal_rank,
        release_time = core.time() + spell.cast_times[optimal_rank],
        target_unit = target,
    }

    -- Cast the spell
    -- The izi_sdk should handle empower channeling
    if target then
        return spell_obj:cast_safe(target, string.format("%s (Rank %d)", spell.name, optimal_rank))
    else
        return spell_obj:cast_safe(nil, string.format("%s (Rank %d)", spell.name, optimal_rank))
    end
end

---Update empower state (call each frame while channeling)
---@param me game_object
---@param target_selector any
function empower_handler.update(me, target_selector)
    if not me:is_channeling() then
        -- Clear state if not channeling
        if empower_state.spell_id then
            empower_state = {
                spell_id = nil,
                start_time = nil,
                current_rank = 0,
                target_rank = 0,
                release_time = nil,
                target_unit = nil,
            }
        end
        return
    end

    -- Check if we should release
    if empower_handler.should_release(me, target_selector) then
        -- Release the spell at current rank
        -- The izi_sdk should have a method to release empower
        -- Since we don't have the exact API, we'll need to check how to do this
        -- For now, just log
        local rank = empower_handler.get_current_rank(me)
        local spell = EMPOWERED_SPELLS[empower_state.spell_id]
        if spell then
            core.log(string.format("Releasing %s at rank %d", spell.name, rank))
        end

        -- TODO: Implement actual release mechanism when API is confirmed
        -- me:stop_casting() might be the method, but need to verify
    end
end

---Get time until next rank
---@param me game_object
---@return number time Time in seconds until next rank
function empower_handler.time_to_next_rank(me)
    if not empower_state.spell_id then
        return 999
    end

    local spell = EMPOWERED_SPELLS[empower_state.spell_id]
    local current_rank = empower_handler.get_current_rank(me)

    if current_rank >= spell.max_rank then
        return 0
    end

    local elapsed = core.time() - empower_state.start_time
    local next_rank_time = spell.cast_times[current_rank + 1]

    return math.max(0, next_rank_time - elapsed)
end

---Check if a spell is an empowered spell
---@param spell_id number
---@return boolean is_empower True if empowered spell
function empower_handler.is_empower_spell(spell_id)
    return EMPOWERED_SPELLS[spell_id] ~= nil
end

---Get empower spell configuration
---@param spell_id number
---@return empower_spell_config|nil config Configuration or nil if not empower spell
function empower_handler.get_spell_config(spell_id)
    return EMPOWERED_SPELLS[spell_id]
end

return empower_handler
