# Empowered Spell Handler Module

Handles the unique Evoker empowered spell mechanics with intelligent rank decisions.

```lua
-- modules/empower_handler.lua
local empower_handler = {}
local me = core.object_manager.get_local_player()

-- Empowered spell configurations
local EMPOWERED_SPELLS = {
    [355941] = { -- Dream Breath
        name = "Dream Breath",
        max_rank = 4,
        cast_times = {1.0, 1.75, 2.5, 3.25}, -- Seconds per rank
        type = "heal",
        coefficients = {1.0, 1.4, 1.8, 2.2}, -- Healing multipliers per rank
        targets = {5, 5, 5, 5}, -- Max targets per rank
        hot_duration = {16, 20, 24, 24}, -- HoT duration per rank
    },
    [367364] = { -- Spiritbloom  
        name = "Spiritbloom",
        max_rank = 4,
        cast_times = {1.0, 1.75, 2.5, 3.25},
        type = "heal",
        coefficients = {1.0, 1.0, 1.0, 1.0}, -- Same healing, more targets
        targets = {1, 2, 3, 4}, -- Targets per rank
    },
    [357208] = { -- Fire Breath
        name = "Fire Breath",
        max_rank = 4,
        cast_times = {1.0, 1.75, 2.5, 3.25},
        type = "damage",
        coefficients = {1.0, 1.5, 2.0, 2.5}, -- Damage multipliers
        dot_duration = {20, 16, 12, 8}, -- DoT duration (inverse with rank)
    },
}

-- Current empower state tracking
local empower_state = {
    spell_id = nil,
    start_time = nil,
    current_rank = 0,
    target_rank = 0,
    release_time = nil,
    target_unit = nil,
}

-- Calculate optimal empower rank based on situation
function empower_handler.calculate_optimal_rank(spell_id, context)
    local spell = EMPOWERED_SPELLS[spell_id]
    if not spell then
        return 1
    end
    
    -- Context includes: targets, urgency, resource availability
    local urgency = context.urgency or "normal" -- "emergency", "high", "normal", "low"
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
            -- More injured = higher rank for stronger HoT
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
                return math.min(injured_count + 1, 4)  -- Hit injured + 1
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

-- Get current empower rank based on channel time
function empower_handler.get_current_rank()
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

-- Should we release the empower early?
function empower_handler.should_release()
    if not empower_state.spell_id then
        return false
    end
    
    local current_rank = empower_handler.get_current_rank()
    local target_rank = empower_state.target_rank
    
    -- Reached target rank
    if current_rank >= target_rank then
        return true
    end
    
    -- Check for emergency situations
    local emergency_target = nil
    local units = core.object_manager.get_party_raid_units()
    for _, unit in ipairs(units) do
        if unit:get_health_percentage() < 25 then
            emergency_target = unit
            break
        end
    end
    
    -- Release at rank 1+ for emergencies
    if emergency_target and current_rank >= 1 then
        core.log("Emergency release at rank " .. current_rank)
        return true
    end
    
    -- Check if we need to move soon
    local ground_effects = evade_helper.get_dangerous_areas()
    if #ground_effects > 0 then
        local my_pos = me:position()
        for _, effect in ipairs(ground_effects) do
            local dist = my_pos:distance_squared(effect.position)
            if dist < 25 and effect.time_until < 0.5 then
                -- Need to move very soon
                if current_rank >= 1 then
                    return true
                end
            end
        end
    end
    
    -- Check if target died or became invalid
    if empower_state.target_unit then
        if not empower_state.target_unit:is_alive() or 
           empower_state.target_unit:get_health_percentage() > 95 then
            return current_rank >= 1
        end
    end
    
    return false
end

-- Start empowered cast
function empower_handler.start_empower(spell_id, target, context)
    local spell = EMPOWERED_SPELLS[spell_id]
    if not spell then
        return false
    end
    
    -- Calculate optimal rank
    local optimal_rank = empower_handler.calculate_optimal_rank(spell_id, context)
    
    -- Use IZI SDK empower cast
    local cast_opts = {
        skip_moving = false,  -- We handle movement
        skip_casting = false,
        empower_rank = optimal_rank,  -- Target rank
    }
    
    -- Store state
    empower_state = {
        spell_id = spell_id,
        start_time = core.time(),
        current_rank = 0,
        target_rank = optimal_rank,
        release_time = core.time() + spell.cast_times[optimal_rank],
        target_unit = target,
    }
    
    -- Start the cast
    if target then
        return izi_spell.cast_unit(spell_id, target, cast_opts)
    else
        return izi_spell.cast(spell_id, cast_opts)
    end
end

-- Update empower state (call each frame while channeling)
function empower_handler.update()
    if not me:is_channeling() then
        -- Clear state if not channeling
        if empower_state.spell_id then
            empower_state = {}
        end
        return
    end
    
    -- Check if we should release
    if empower_handler.should_release() then
        -- Release the spell at current rank
        me:release_empower()  -- Or whatever the IZI function is
        
        local rank = empower_handler.get_current_rank()
        core.log(string.format("Released %s at rank %d", 
            EMPOWERED_SPELLS[empower_state.spell_id].name, rank))
        
        empower_state = {}
    end
end

-- Get time until next rank
function empower_handler.time_to_next_rank()
    if not empower_state.spell_id then
        return 999
    end
    
    local spell = EMPOWERED_SPELLS[empower_state.spell_id]
    local current_rank = empower_handler.get_current_rank()
    
    if current_rank >= spell.max_rank then
        return 0
    end
    
    local elapsed = core.time() - empower_state.start_time
    local next_rank_time = spell.cast_times[current_rank + 1]
    
    return math.max(0, next_rank_time - elapsed)
end

-- Intelligent rank decision helper
function empower_handler.get_rank_decision(spell_id, situation)
    local decisions = {
        -- Dream Breath decisions
        [355941] = {
            raid_damage = function(injured_count, avg_deficit)
                if injured_count >= 10 and avg_deficit > 50 then
                    return 4, "Maximum HoT for raid damage"
                elseif injured_count >= 5 and avg_deficit > 35 then
                    return 3, "Strong HoT for moderate damage"
                elseif injured_count >= 3 then
                    return 2, "Quick HoT application"
                else
                    return 1, "Minimal damage, quick cast"
                end
            end,
            tank_healing = function(tank_hp, incoming_damage)
                if tank_hp < 40 and incoming_damage > 30 then
                    return 1, "Emergency quick heal"
                elseif incoming_damage > 50 then
                    return 4, "Maximum HoT for heavy damage"
                else
                    return 2, "Maintenance HoT"
                end
            end,
        },
        
        -- Spiritbloom decisions
        [367364] = {
            party_burst = function(injured_targets)
                local count = #injured_targets
                if count >= 4 then
                    return 4, "Hit all party members"
                elseif count >= 2 then
                    return count, "Match injured count"
                else
                    return 1, "Single target heal"
                end
            end,
            emergency = function(lowest_hp)
                if lowest_hp < 20 then
                    return 1, "Instant emergency heal"
                elseif lowest_hp < 40 then
                    return 2, "Quick multi-target"
                else
                    return 3, "Moderate group heal"
                end
            end,
        },
        
        -- Fire Breath decisions
        [357208] = {
            aoe_damage = function(enemy_count, priority_target_hp)
                if priority_target_hp < 20 then
                    return 4, "Maximum execute damage"
                elseif enemy_count >= 5 then
                    return 2, "Balanced for spread"
                elseif enemy_count >= 3 then
                    return 3, "Good cleave damage"
                else
                    return 2, "Standard damage"
                end
            end,
            leaping_flames = function()
                -- For Leaping Flames buff generation
                return 3, "Optimal for Leaping Flames"
            end,
        }
    }
    
    local spell_decisions = decisions[spell_id]
    if spell_decisions and spell_decisions[situation] then
        return spell_decisions[situation]
    end
    
    return 2, "Default rank"
end

-- Predictive empower timing
function empower_handler.predict_cast_window(spell_id, desired_rank)
    local spell = EMPOWERED_SPELLS[spell_id]
    if not spell then
        return 0
    end
    
    local cast_time = spell.cast_times[desired_rank]
    
    -- Check if we'll need to move during cast
    local safe_time = evade_helper.get_safe_cast_window()
    
    if safe_time < cast_time then
        -- Need to use lower rank
        for rank = desired_rank - 1, 1, -1 do
            if spell.cast_times[rank] <= safe_time then
                return rank, safe_time
            end
        end
        return 0, 0  -- Can't cast
    end
    
    return desired_rank, cast_time
end

return empower_handler
```
