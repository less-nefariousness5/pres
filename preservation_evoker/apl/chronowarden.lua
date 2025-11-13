--[[
    Chronowarden APL for Preservation Evoker

    Echo-focused healing rotation with temporal magic synergies.
    Integrates all core modules for intelligent healing decisions.

    Features:
    - Echo setup and consumption
    - Empowered spell integration
    - Dream Flight positioning
    - Emergency response system
    - Cooldown management
]]

local izi = require("common/izi_sdk")
local enums = require("common/enums")

-- Load modules
local target_selector = require("preservation_evoker/modules/target_selector")
local health_predictor = require("preservation_evoker/modules/health_predictor")
local healing_calculator = require("preservation_evoker/modules/healing_calculator")
local essence_manager = require("preservation_evoker/modules/essence_manager")
local stop_cast = require("preservation_evoker/modules/stop_cast")
local empower_handler = require("preservation_evoker/modules/empower_handler")
local dream_flight_handler = require("preservation_evoker/modules/dream_flight_handler")

-- Load spells
local SPELLS = require("preservation_evoker/spells")

---@class chronowarden_apl
local chronowarden = {}

---Main rotation entry point
---@param me game_object
---@return boolean success True if action taken
function chronowarden.rotation(me)
    -- Update systems
    stop_cast.update_cast_info(me)
    health_predictor.update_damage_history()

    -- Update empower handler
    empower_handler.update(me, target_selector)

    -- Check for cast interruption
    if stop_cast.should_stop_cast(me, healing_calculator, target_selector) then
        core.input.cancel_spells()
        return true
    end

    -- If channeling empowered spell, let it continue unless should_release
    if me:is_channeling() then
        if empower_handler.should_release(me, target_selector) then
            core.input.cancel_spells()  -- Release empower
            return true
        end
        return false  -- Continue channeling
    end

    -- Dream Flight opportunity check
    if chronowarden.check_dream_flight(me) then
        return true
    end

    -- Emergency healing
    if chronowarden.handle_emergency(me) then
        return true
    end

    -- Use major cooldowns
    if chronowarden.use_cooldowns(me) then
        return true
    end

    -- Echo setup phase
    if chronowarden.setup_echoes(me) then
        return true
    end

    -- Consume echoes with healing
    if chronowarden.consume_echoes(me) then
        return true
    end

    -- Maintenance healing
    if chronowarden.maintenance_healing(me) then
        return true
    end

    -- DPS when nothing to heal
    chronowarden.dps_rotation(me)

    return false
end

---Check and cast Dream Flight if conditions are met
---@param me game_object
---@return boolean success
function chronowarden.check_dream_flight(me)
    local should_cast, flight_data = dream_flight_handler.should_cast(me, SPELLS.DREAM_FLIGHT)

    if should_cast and flight_data then
        -- Check if it's a good time (not during other important casts)
        local echo_count = chronowarden.count_active_echoes()

        -- Don't interrupt a good echo setup
        if echo_count >= 4 then
            return false
        end

        -- Cast Dream Flight
        if dream_flight_handler.cast(me, SPELLS.DREAM_FLIGHT) then
            core.log(string.format("Dream Flight: Healing %d allies along path",
                flight_data.path_data.heal_count))
            return true
        end
    end

    return false
end

---Handle emergency healing situations
---@param me game_object
---@return boolean success
function chronowarden.handle_emergency(me)
    local emergency_target, score = target_selector.get_best_heal_target(me, 30, 30)

    if not emergency_target then
        return false
    end

    -- Count low health allies
    local low_count = target_selector.count_injured(me, 40)

    -- Rewind for multiple low targets
    if low_count >= 3 and SPELLS.REWIND:cast_safe(nil, "Rewind (Emergency)") then
        return true
    end

    -- Tip the Scales for instant empowered spell
    if SPELLS.TIP_THE_SCALES:cast_safe(nil, "Tip the Scales (Emergency)") then
        return true
    end

    -- If Tip is active, use instant max rank Spiritbloom
    if me:has_buff(SPELLS.BUFFS.TIP_THE_SCALES) then
        local context = {
            urgency = "emergency",
            target_count = low_count,
            avg_health_deficit = 70,
            force_rank = 4,  -- Max rank with Tip
        }

        -- Set cast target for stop cast tracking
        stop_cast.set_cast_target(emergency_target)

        if empower_handler.start_empower(SPELLS.SPIRITBLOOM:id(), me, emergency_target, context, SPELLS.SPIRITBLOOM) then
            return true
        end
    end

    -- Verdant Embrace for instant heal
    if SPELLS.VERDANT_EMBRACE:cast_safe(emergency_target, "Verdant Embrace (Emergency)") then
        return true
    end

    -- Emergency empowered Spiritbloom (rank 1 for speed)
    local context = {
        urgency = "emergency",
        target_count = 1,
        avg_health_deficit = 100 - emergency_target:get_health_percentage(),
    }

    stop_cast.set_cast_target(emergency_target)

    if empower_handler.start_empower(SPELLS.SPIRITBLOOM:id(), me, emergency_target, context, SPELLS.SPIRITBLOOM) then
        return true
    end

    return false
end

---Setup Echo on party members
---@param me game_object
---@return boolean success
function chronowarden.setup_echoes(me)
    local essence = essence_manager.get_essence(me)
    if essence < 2 then
        return false
    end

    -- Cast Temporal Anomaly first for free echoes
    if SPELLS.TEMPORAL_ANOMALY:cast_safe(nil, "Temporal Anomaly (Echo Setup)") then
        return true
    end

    -- Manual echo setup on injured targets
    local units = target_selector.get_aoe_targets(me, 5, 85, 30)
    for i = 1, #units do
        local unit = units[i]
        if not unit:has_buff(SPELLS.BUFFS.ECHO) then
            if SPELLS.ECHO:cast_safe(unit, "Echo Setup") then
                return true
            end
        end
    end

    return false
end

---Consume echoes with healing spells
---@param me game_object
---@return boolean success
function chronowarden.consume_echoes(me)
    local echo_count = chronowarden.count_active_echoes()

    if echo_count < 2 then
        return false
    end

    -- Calculate group status
    local injured_count = target_selector.count_injured(me, 80)
    local avg_health = target_selector.get_average_health()
    local avg_deficit = 100 - avg_health

    -- Verdant Embrace + Emerald Communion combo for big healing
    if injured_count >= 3 and avg_deficit > 40 then
        local target = target_selector.get_best_heal_target(me, 70, 30)
        if target then
            if SPELLS.VERDANT_EMBRACE:cast_safe(target, "Verdant (Echo Consume)") then
                return true
            end

            if me:has_buff(SPELLS.BUFFS.VERDANT_EMBRACE_BUFF) then
                if SPELLS.EMERALD_COMMUNION:cast_safe(nil, "Emerald Communion") then
                    return true
                end
            end
        end
    end

    -- Empowered Spiritbloom for burst healing
    if injured_count >= 2 and avg_health < 70 then
        local context = {
            urgency = avg_health < 50 and "high" or "normal",
            target_count = injured_count,
            avg_health_deficit = avg_deficit,
        }

        stop_cast.set_cast_target(me)

        if empower_handler.start_empower(SPELLS.SPIRITBLOOM:id(), me, me, context, SPELLS.SPIRITBLOOM) then
            return true
        end
    end

    -- Empowered Dream Breath for HoT application
    if injured_count >= 1 then
        local context = {
            urgency = "normal",
            target_count = injured_count,
            avg_health_deficit = avg_deficit,
        }

        if empower_handler.start_empower(SPELLS.DREAM_BREATH:id(), me, nil, context, SPELLS.DREAM_BREATH) then
            return true
        end
    end

    return false
end

---Maintenance healing
---@param me game_object
---@return boolean success
function chronowarden.maintenance_healing(me)
    -- Keep Reversion on tanks
    local tank = target_selector.get_tank_target(me)
    if tank and not tank:has_buff(SPELLS.BUFFS.REVERSION_HOT) then
        if SPELLS.REVERSION:cast_safe(tank, "Reversion (Tank)") then
            return true
        end
    end

    -- Chrono Flame (Living Flame) with Essence Burst
    if essence_manager.has_essence_burst(me) then
        local target = target_selector.get_best_heal_target(me, 90, 30)
        if target then
            if SPELLS.LIVING_FLAME:cast_safe(target, "Living Flame (Essence Burst)") then
                return true
            end
        end
    end

    return false
end

---Cooldown usage
---@param me game_object
---@return boolean success
function chronowarden.use_cooldowns(me)
    -- Time Dilation on tank with predicted damage
    local tank = target_selector.get_tank_target(me)
    if tank then
        local prediction = health_predictor.predict_health(tank, me, 3.0)
        if prediction.predicted_pct < 50 then
            if SPELLS.TIME_DILATION:cast_safe(tank, "Time Dilation (Tank)") then
                return true
            end
        end
    end

    return false
end

---DPS rotation when no healing needed
---@param me game_object
function chronowarden.dps_rotation(me)
    local enemies = me:get_enemies_in_range(30)

    if #enemies > 0 then
        local target = enemies[1]

        -- Fire Breath for Leaping Flames buff
        local context = {
            urgency = "normal",
            enemy_count = #enemies,
            enemy_health = target:get_health_percentage() < 20 and "low" or "high",
        }

        if empower_handler.start_empower(SPELLS.FIRE_BREATH:id(), me, nil, context, SPELLS.FIRE_BREATH) then
            return
        end

        -- Living Flame spam
        if SPELLS.LIVING_FLAME:cast_safe(target, "Living Flame (DPS)") then
            return
        end
    end
end

---Count active echoes
---@return number count Number of active echoes
function chronowarden.count_active_echoes()
    local count = 0
    local units = izi.friendly_units()

    for i = 1, #units do
        local unit = units[i]
        if unit:has_buff(SPELLS.BUFFS.ECHO) then
            count = count + 1
        end
    end

    return count
end

return chronowarden
