# Updated Chronowarden APL with Empower & Dream Flight Integration

```lua
-- apl/chronowarden_v2.lua
local chronowarden = {}
local me = core.object_manager.get_local_player()

-- Load handler modules
local empower_handler = require("modules.empower_handler")
local dream_flight_handler = require("modules.dream_flight_handler")
local target_selector = require("modules.target_selector")
local health_predictor = require("modules.health_predictor")

-- Spell IDs
local SPELLS = {
    -- Core Heals
    ECHO = 364343,
    SPIRITBLOOM = 367364,
    DREAM_BREATH = 355941,
    DREAM_FLIGHT = 358267,
    REVERSION = 366155,
    LIVING_FLAME = 361469,
    VERDANT_EMBRACE = 360995,
    
    -- Cooldowns
    TEMPORAL_ANOMALY = 373861,
    TIP_THE_SCALES = 370553,
    STASIS = 370537,
    REWIND = 363534,
    TIME_DILATION = 357170,
    EMERALD_COMMUNION = 370960,
    
    -- Damage
    FIRE_BREATH = 357208,
    DISINTEGRATE = 356995,
    
    -- Buffs
    ESSENCE_BURST = 369256,
    TEMPORAL_COMPRESSION = 431462,
    CHRONO_FLAME = 431442,
}

-- Main rotation
function chronowarden.rotation()
    -- Update systems
    health_predictor.update_damage_history()
    empower_handler.update()  -- Update empower state
    
    -- If we're channeling an empowered spell, handle it
    if me:is_channeling() then
        if empower_handler.should_release() then
            me:release_empower()
            return
        end
        -- Continue channeling
        return
    end
    
    -- Dream Flight opportunity check
    if chronowarden.check_dream_flight() then
        return
    end
    
    -- Emergency healing
    if chronowarden.handle_emergency() then
        return
    end
    
    -- Use major cooldowns
    if chronowarden.use_cooldowns() then
        return
    end
    
    -- Echo setup phase
    if chronowarden.setup_echoes() then
        return
    end
    
    -- Consume echoes with healing
    if chronowarden.consume_echoes() then
        return
    end
    
    -- Maintenance healing
    if chronowarden.maintenance_healing() then
        return
    end
    
    -- DPS when nothing to heal
    chronowarden.dps_rotation()
end

-- Dream Flight integration
function chronowarden.check_dream_flight()
    local should_cast, flight_data = dream_flight_handler.should_cast()
    
    if should_cast and flight_data then
        -- Check if it's a good time (not during other important casts)
        local echo_count = chronowarden.count_active_echoes()
        
        -- Don't interrupt a good echo setup
        if echo_count >= 4 then
            return false
        end
        
        -- Cast Dream Flight
        if dream_flight_handler.cast() then
            core.log(string.format("Dream Flight: Healing %d allies along path", 
                flight_data.path_data.heal_count))
            return true
        end
    end
    
    return false
end

-- Emergency healing with empowered spells
function chronowarden.handle_emergency()
    local emergency_target = target_selector.get_best_heal_target(30, 30)
    
    if emergency_target then
        -- Count low health allies
        local low_count = 0
        local units = core.object_manager.get_party_raid_units()
        for _, unit in ipairs(units) do
            if unit:get_health_percentage() < 40 then
                low_count = low_count + 1
            end
        end
        
        -- Rewind for multiple low targets
        if low_count >= 3 and izi_spell.cast(SPELLS.REWIND) then
            return true
        end
        
        -- Tip the Scales for instant empowered spell
        if izi_spell.cast(SPELLS.TIP_THE_SCALES) then
            return true
        end
        
        -- If Tip is active, use instant max rank Spiritbloom
        if me:has_buff(SPELLS.TIP_THE_SCALES) then
            local context = {
                urgency = "emergency",
                target_count = low_count,
                avg_health_deficit = 70,
            }
            
            -- This will cast at max rank instantly due to Tip
            if empower_handler.start_empower(SPELLS.SPIRITBLOOM, me, context) then
                return true
            end
        end
        
        -- Regular empowered Spiritbloom
        local context = {
            urgency = "emergency",
            target_count = 1,
            avg_health_deficit = 100 - emergency_target:get_health_percentage(),
            time_available = evade_helper.get_safe_cast_window(),
        }
        
        if empower_handler.start_empower(SPELLS.SPIRITBLOOM, me, context) then
            return true
        end
        
        -- Verdant Embrace for instant heal
        if izi_spell.cast_unit(SPELLS.VERDANT_EMBRACE, emergency_target) then
            return true
        end
    end
    
    return false
end

-- Consume echoes with empowered spells
function chronowarden.consume_echoes()
    local echo_count = chronowarden.count_active_echoes()
    
    if echo_count < 2 then
        return false
    end
    
    -- Calculate group status
    local units = core.object_manager.get_party_raid_units()
    local total_deficit = 0
    local injured_count = 0
    local lowest_hp = 100
    
    for _, unit in ipairs(units) do
        local hp_pct = unit:get_health_percentage()
        if hp_pct < 80 then
            injured_count = injured_count + 1
            total_deficit = total_deficit + (100 - hp_pct)
            lowest_hp = math.min(lowest_hp, hp_pct)
        end
    end
    
    local avg_deficit = injured_count > 0 and (total_deficit / injured_count) or 0
    
    -- Verdant Embrace + Emerald Communion combo for big healing
    if injured_count >= 3 and avg_deficit > 40 then
        local target = target_selector.get_best_heal_target(70, 30)
        if target then
            if izi_spell.cast_unit(SPELLS.VERDANT_EMBRACE, target) then
                return true
            end
            if me:has_buff(SPELLS.VERDANT_EMBRACE) then
                if izi_spell.cast(SPELLS.EMERALD_COMMUNION) then
                    return true
                end
            end
        end
    end
    
    -- Empowered Spiritbloom for burst healing
    if injured_count >= 2 and lowest_hp < 60 then
        local context = {
            urgency = lowest_hp < 40 and "high" or "normal",
            target_count = injured_count,
            avg_health_deficit = avg_deficit,
            time_available = evade_helper.get_safe_cast_window(),
        }
        
        if empower_handler.start_empower(SPELLS.SPIRITBLOOM, me, context) then
            return true
        end
    end
    
    -- Empowered Dream Breath for HoT application
    if injured_count >= 1 then
        local context = {
            urgency = "normal",
            target_count = injured_count,
            avg_health_deficit = avg_deficit,
            time_available = evade_helper.get_safe_cast_window(),
        }
        
        if empower_handler.start_empower(SPELLS.DREAM_BREATH, nil, context) then
            return true
        end
    end
    
    return false
end

-- Count active echoes
function chronowarden.count_active_echoes()
    local count = 0
    local units = core.object_manager.get_party_raid_units()
    
    for _, unit in ipairs(units) do
        if unit:has_buff(SPELLS.ECHO) then
            count = count + 1
        end
    end
    
    return count
end

-- DPS rotation with empowered Fire Breath
function chronowarden.dps_rotation()
    local enemies = core.object_manager.get_enemies(30)
    
    if #enemies > 0 then
        -- Calculate Fire Breath context
        local context = {
            urgency = "normal",
            enemy_count = #enemies,
            enemy_health = enemies[1]:get_health_percentage() < 20 and "low" or "high",
            time_available = evade_helper.get_safe_cast_window(),
        }
        
        -- Use empowered Fire Breath
        if empower_handler.start_empower(SPELLS.FIRE_BREATH, nil, context) then
            return true
        end
        
        -- Living Flame spam
        if izi_spell.cast_unit(SPELLS.LIVING_FLAME, enemies[1]) then
            return true
        end
    end
end

-- Stasis management with empowered spells
function chronowarden.use_stasis()
    if me:has_buff(SPELLS.STASIS) then
        -- We're collecting spells
        local stasis_count = me:get_buff_stacks(SPELLS.STASIS) or 0
        
        if stasis_count < 3 then
            -- Fill stasis with powerful spells
            
            -- Try Dream Breath first
            local context = {
                urgency = "normal",
                target_count = 5,
                avg_health_deficit = 30,
                time_available = 5.0,  -- We have time in stasis
            }
            
            if empower_handler.start_empower(SPELLS.DREAM_BREATH, nil, context) then
                return true
            end
            
            -- Then Spiritbloom
            context.target_count = 3
            if empower_handler.start_empower(SPELLS.SPIRITBLOOM, me, context) then
                return true
            end
            
            -- Finally Temporal Anomaly
            if izi_spell.cast(SPELLS.TEMPORAL_ANOMALY) then
                return true
            end
        end
    else
        -- Check if we should activate stasis
        local avg_health = chronowarden.get_average_health()
        
        if avg_health < 70 and izi_spell.is_ready(SPELLS.STASIS) then
            if izi_spell.cast(SPELLS.STASIS) then
                core.log("Stasis activated - collecting spells")
                return true
            end
        end
    end
    
    return false
end

-- Helper: Get average party/raid health
function chronowarden.get_average_health()
    local total = 0
    local count = 0
    local units = core.object_manager.get_party_raid_units()
    
    for _, unit in ipairs(units) do
        if unit:is_alive() then
            total = total + unit:get_health_percentage()
            count = count + 1
        end
    end
    
    return count > 0 and (total / count) or 100
end

return chronowarden
```
