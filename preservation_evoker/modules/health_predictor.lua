--[[
    Health Predictor Module for Preservation Evoker

    Advanced health prediction using damage patterns and incoming damage calculations.
    Tracks damage history to detect burst patterns and predict future health states.

    Features:
    - Health state prediction 2-3 seconds ahead
    - Damage pattern tracking (5-second windows)
    - Burst damage detection
    - Incoming healing estimation from HoTs
    - Death prediction for emergency responses
]]

local izi = require("common/izi_sdk")
local enums = require("common/enums")
local BUFFS = enums.buff_db

---@class health_predictor
local health_predictor = {}

-- Cache for damage history
local damage_history = {}
local HISTORY_DURATION = 5.0  -- Track last 5 seconds

---@class health_prediction
---@field current_hp number Current health points
---@field current_pct number Current health percentage
---@field predicted_hp number Predicted health points
---@field predicted_pct number Predicted health percentage
---@field damage_rate number Damage per second rate
---@field healing_rate number Healing per second rate
---@field will_die boolean True if predicted to die
---@field emergency boolean True if predicted health < 30%

---Predict health in X seconds
---@param unit game_object
---@param me game_object
---@param time_ahead number Time in seconds to predict ahead (default: 2.0)
---@return health_prediction prediction Health prediction data
function health_predictor.predict_health(unit, me, time_ahead)
    time_ahead = time_ahead or 2.0

    local current_hp = unit:health()
    local max_hp = unit:health_max()
    local current_pct = unit:get_health_percentage()

    -- Get incoming damage prediction (izi_sdk function)
    local incoming_dmg = unit:get_incoming_damage(time_ahead)

    -- Get recent damage pattern (for burst detection)
    local recent_dmg = health_predictor.get_recent_damage_rate(unit)

    -- Calculate healing received estimate
    local incoming_healing = health_predictor.estimate_incoming_healing(unit, me)

    -- Predict final health
    local predicted_hp = current_hp - incoming_dmg + incoming_healing
    local predicted_pct = (predicted_hp / max_hp) * 100

    return {
        current_hp = current_hp,
        current_pct = current_pct,
        predicted_hp = math.max(0, predicted_hp),
        predicted_pct = math.max(0, predicted_pct),
        damage_rate = recent_dmg / time_ahead,
        healing_rate = incoming_healing / time_ahead,
        will_die = predicted_hp <= 0,
        emergency = predicted_pct < 30
    }
end

---Track damage patterns (call this every frame)
function health_predictor.update_damage_history()
    local current_time = core.time()
    local units = izi.friendly_units()

    for i = 1, #units do
        local unit = units[i]
        local guid = unit:get_guid()

        if not damage_history[guid] then
            damage_history[guid] = {}
        end

        -- Add current health snapshot
        table.insert(damage_history[guid], {
            time = current_time,
            health = unit:health(),
            health_pct = unit:get_health_percentage()
        })

        -- Clean old entries
        local cutoff = current_time - HISTORY_DURATION
        local history = damage_history[guid]

        -- Remove old entries (from start of table)
        while #history > 0 and history[1].time < cutoff do
            table.remove(history, 1)
        end
    end
end

---Calculate recent damage rate
---@param unit game_object
---@return number damage_rate Damage per second
function health_predictor.get_recent_damage_rate(unit)
    local guid = unit:get_guid()
    local history = damage_history[guid]

    if not history or #history < 2 then
        return 0
    end

    local recent = history[#history]
    local old = history[1]
    local time_diff = recent.time - old.time

    if time_diff <= 0 then
        return 0
    end

    local health_lost = old.health - recent.health
    return math.max(0, health_lost / time_diff)
end

---Estimate incoming healing from other sources (HoTs)
---@param unit game_object
---@param me game_object
---@return number healing Estimated healing amount
function health_predictor.estimate_incoming_healing(unit, me)
    local healing = 0

    -- Preservation Evoker HoTs
    local hots = {
        {id = 366155, mult = 1.0, sp_coeff = 0.8},   -- Reversion
        {id = 355941, mult = 1.5, sp_coeff = 1.2},   -- Dream Breath HoT
        {id = 373267, mult = 0.8, sp_coeff = 0.5},   -- Lifebind echo healing
    }

    local sp = me:get_spell_power()

    for i = 1, #hots do
        local hot = hots[i]
        if unit:has_buff(hot.id) then
            local remaining = unit:buff_remains_sec(hot.id)
            -- Estimate HoT tick healing based on spell power
            -- This is a simplified calculation
            local tick_healing = sp * hot.sp_coeff
            local estimated_ticks = remaining / 2  -- Assume 2-second tick rate
            healing = healing + (tick_healing * estimated_ticks * hot.mult)
        end
    end

    return healing
end

---Detect incoming spike damage
---@param unit game_object
---@param threshold_time number Time window in seconds (default: 1.0)
---@return boolean is_spike True if spike damage detected
function health_predictor.detect_spike_damage(unit, threshold_time)
    threshold_time = threshold_time or 1.0

    local incoming = unit:get_incoming_damage(threshold_time)
    local max_hp = unit:health_max()
    local spike_threshold = max_hp * 0.4  -- 40% health as spike

    return incoming >= spike_threshold
end

---Clear damage history for a specific unit (call when unit dies/leaves)
---@param unit game_object
function health_predictor.clear_unit_history(unit)
    local guid = unit:get_guid()
    damage_history[guid] = nil
end

---Clear all damage history
function health_predictor.clear_all_history()
    damage_history = {}
end

return health_predictor
