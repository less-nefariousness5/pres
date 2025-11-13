--[[
    Preservation Evoker Main Controller

    Modular healing rotation for Preservation Evoker with Chronowarden specialization.
    Integrates all modules for intelligent healing decisions.

    Features:
    - Module-based architecture
    - Intelligent target selection
    - Health prediction system
    - Smart cooldown management
    - Empowered spell optimization
    - Dream Flight positioning
    - Echo-focused rotation

    Author: Modular Healing System
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

-- Load APL
local chronowarden = require("preservation_evoker/apl/chronowarden")

-- Load menu
local menu = require("preservation_evoker/menu")

-- Load spells
local SPELLS = require("preservation_evoker/spells")

-- Constants
local DISMOUNT_DELAY_MS = 1000

-- Local variables for caching
local ping_ms = 0
local ping_sec = 0
local game_time_ms = 0
local gcd = 0
local essence = 0
local last_movement_time_ms = 0
local last_mounted_time_ms = 0

---Returns the time in milliseconds since the last movement
---@return number time_since_last_movement_ms
local function time_since_last_movement_ms()
    return game_time_ms - last_movement_time_ms
end

---Returns the time in seconds since the last movement
---@return number time_since_last_movement_sec
local function time_since_last_movement_sec()
    return time_since_last_movement_ms() / 1000
end

---Returns the time in milliseconds since the last dismount
---@return number time_since_last_dismount_ms
local function time_since_last_dismount_ms()
    return game_time_ms - last_mounted_time_ms
end

---Returns the time in seconds since the last dismount
---@return number time_since_last_dismount_sec
local function time_since_last_dismount_sec()
    return time_since_last_dismount_ms() / 1000
end

---Handle utility and out-of-combat actions
---@param me game_object
---@return boolean success
local function utility(me)
    -- Add utility logic here (e.g., buff maintenance, movement abilities)
    return false
end

---Handle defensive abilities
---@param me game_object
---@return boolean success
local function defensives(me)
    ---@type unit_cast_opts
    local def_opts = { skip_gcd = true }

    -- Obsidian Scales
    ---@type defensive_filters
    local obsidian_filters = {
        health_percentage_threshold_raw = menu.OBSIDIAN_SCALES_MAX_HP:get(),
        health_percentage_threshold_incoming = menu.OBSIDIAN_SCALES_FUTURE_HP:get(),
    }

    if SPELLS.OBSIDIAN_SCALES:cast_defensive(me, obsidian_filters, "Obsidian Scales", def_opts) then
        return true
    end

    -- Renewing Blaze
    ---@type defensive_filters
    local renewing_blaze_filters = {
        health_percentage_threshold_raw = menu.RENEWING_BLAZE_MAX_HP:get(),
        health_percentage_threshold_incoming = menu.RENEWING_BLAZE_FUTURE_HP:get(),
    }

    if SPELLS.RENEWING_BLAZE_SELF:cast_defensive(me, renewing_blaze_filters, "Renewing Blaze", def_opts) then
        return true
    end

    return false
end

-- Register update callback
core.register_on_update_callback(function()
    -- Check if the rotation is enabled
    if not menu:is_enabled() then
        return
    end

    -- Get the local player
    local me = izi.me()

    -- Check if the local player exists and is valid
    if not (me and me.is_valid and me:is_valid()) then
        return
    end

    -- Update commonly used values
    ping_ms = core.get_ping()
    ping_sec = ping_ms / 1000
    game_time_ms = izi.now_game_time_ms()
    gcd = me:gcd()
    essence = essence_manager.get_essence(me)

    -- Update the local player's last movement time
    if me:is_moving() then
        last_movement_time_ms = game_time_ms
    end

    -- Update the local player's last mounted time
    if me:is_mounted() then
        last_mounted_time_ms = game_time_ms
        return
    end

    -- Delay actions after dismounting
    local time_dismounted_ms = time_since_last_dismount_ms()

    if time_dismounted_ms < DISMOUNT_DELAY_MS then
        return
    end

    -- If the rotation is paused let's return early
    if not menu:is_rotation_enabled() then
        return
    end

    -- Execute utility
    if utility(me) then
        return
    end

    -- Execute defensives
    if defensives(me) then
        return
    end

    -- Execute main rotation
    chronowarden.rotation(me)
end)

core.log("Preservation Evoker (Chronowarden) - Modular Rotation Loaded")
