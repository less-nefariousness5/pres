--[[
    Preservation Evoker Menu Configuration

    UI configuration for the modular Preservation Evoker rotation.
    Allows users to customize behavior through intuitive settings.

    Categories:
    - Global settings (Plugin enable/disable)
    - Keybinds (Rotation toggle)
    - Cooldowns (TTD validation for major abilities)
    - Defensives (Health thresholds for defensive abilities)
    - Healing (Target selection priorities and thresholds)
    - Empowered Spells (Rank preferences and timing)
]]

---@meta menu
local m = core.menu
local color = require("common/color")
local key_helper = require("common/utility/key_helper")
local control_panel_utility = require("common/utility/control_panel_helper")

-- Constants
local PLUGIN_PREFIX = "pres_evoker"
local WHITE = color.white(150)
local TTD_MIN = 1
local TTD_MAX = 120
local TTD_DEFAULT = 15

---Creates an ID with prefix for our rotation
---@param key string
local function id(key)
    return string.format("%s_%s", PLUGIN_PREFIX, key)
end

---@class pres_evoker_menu
local menu = {
    -- Global
    MAIN_TREE = m.tree_node(),
    GLOBAL_CHECK = m.checkbox(true, id("global_toggle")),

    -- Keybinds
    KEYBIND_TREE = m.tree_node(),
    ROTATION_KEYBIND = m.keybind(999, false, id("rotation_toggle")),

    -- Defensives
    DEFENSIVES_TREE = m.tree_node(),

    -- Obsidian Scales
    OBSIDIAN_SCALES_TREE = m.tree_node(),
    OBSIDIAN_SCALES_CHECK = m.checkbox(true, id("obsidian_scales_toggle")),
    OBSIDIAN_SCALES_MAX_HP = m.slider_int(1, 100, 75, id("obsidian_scales_max_hp")),
    OBSIDIAN_SCALES_FUTURE_HP = m.slider_int(1, 100, 65, id("obsidian_scales_future_hp")),

    -- Renewing Blaze
    RENEWING_BLAZE_TREE = m.tree_node(),
    RENEWING_BLAZE_CHECK = m.checkbox(true, id("renewing_blaze_toggle")),
    RENEWING_BLAZE_MAX_HP = m.slider_int(1, 100, 50, id("renewing_blaze_max_hp")),
    RENEWING_BLAZE_FUTURE_HP = m.slider_int(1, 100, 40, id("renewing_blaze_future_hp")),

    -- Cooldowns
    COOLDOWNS_TREE = m.tree_node(),

    -- Dream Flight
    DREAM_FLIGHT_TREE = m.tree_node(),
    DREAM_FLIGHT_CHECK = m.checkbox(true, id("dream_flight_toggle")),
    DREAM_FLIGHT_MIN_INJURED = m.slider_int(2, 10, 3, id("dream_flight_min_injured")),
    DREAM_FLIGHT_MIN_HEALTH_PCT = m.slider_int(50, 95, 75, id("dream_flight_min_health")),

    -- Rewind
    REWIND_TREE = m.tree_node(),
    REWIND_CHECK = m.checkbox(true, id("rewind_toggle")),
    REWIND_MIN_INJURED = m.slider_int(2, 10, 3, id("rewind_min_injured")),

    -- Temporal Anomaly
    TEMPORAL_ANOMALY_TREE = m.tree_node(),
    TEMPORAL_ANOMALY_CHECK = m.checkbox(true, id("temporal_anomaly_toggle")),
    TEMPORAL_ANOMALY_MIN_INJURED = m.slider_int(2, 10, 2, id("temporal_anomaly_min_injured")),

    -- Healing
    HEALING_TREE = m.tree_node(),
    EMERGENCY_HP = m.slider_int(10, 50, 30, id("emergency_hp")),
    MAINTENANCE_HP = m.slider_int(60, 99, 85, id("maintenance_hp")),

    -- Empowered Spells
    EMPOWER_TREE = m.tree_node(),
    EMPOWER_PREFER_SPEED = m.checkbox(false, id("empower_prefer_speed")),
    EMPOWER_MIN_RANK = m.slider_int(1, 4, 2, id("empower_min_rank")),
}

---@alias menu_validator_fn fun(value: number): boolean

---Creates a new validator function validating a checkbox and relevant slider value
---@param checkbox checkbox
---@param slider slider_int|slider_float
---@param type? "min"|"max"|"equal"
---@return menu_validator_fn
function menu.new_validator_fn(checkbox, slider, type)
    type = type or "min"

    return function(value)
        local is_checked = checkbox:get_state()

        if is_checked then
            local slider_value = slider:get()

            if type == "min" then
                return value >= slider_value
            elseif type == "max" then
                return value <= slider_value
            elseif type == "equal" then
                return value == slider_value
            end
        end

        return false
    end
end

---Returns true if the plugin is enabled
---@return boolean enabled
function menu:is_enabled()
    return self.GLOBAL_CHECK:get_state()
end

---Returns true if the plugin and rotation are enabled
---@return boolean enabled
function menu:is_rotation_enabled()
    return self.GLOBAL_CHECK:get_state() and self.ROTATION_KEYBIND:get_toggle_state()
end

-- Alias our menu to M for rendering
---@class pres_evoker_menu
local M = menu

core.register_on_render_menu_callback(function()
    M.MAIN_TREE:render("Preservation Evoker (Chronowarden)", function()
        M.GLOBAL_CHECK:render("Plugin Enabled", "Global toggle for the plugin")

        if not M.GLOBAL_CHECK:get_state() then
            return
        end

        M.KEYBIND_TREE:render("Keybinds", function()
            M.ROTATION_KEYBIND:render("Rotation Enabled", "Toggles rotation on / off")
        end)

        M.DEFENSIVES_TREE:render("Defensives", function()
            M.OBSIDIAN_SCALES_TREE:render("Obsidian Scales", function()
                M.OBSIDIAN_SCALES_CHECK:render("Enabled", "Toggles Obsidian Scales usage")
                M.OBSIDIAN_SCALES_MAX_HP:render("Max HP", "Maximum HP to use Obsidian Scales")
                M.OBSIDIAN_SCALES_FUTURE_HP:render("Max Future HP", "Maximum predicted HP to use")
            end)

            M.RENEWING_BLAZE_TREE:render("Renewing Blaze", function()
                M.RENEWING_BLAZE_CHECK:render("Enabled", "Toggles Renewing Blaze usage")
                M.RENEWING_BLAZE_MAX_HP:render("Max HP", "Maximum HP to use Renewing Blaze")
                M.RENEWING_BLAZE_FUTURE_HP:render("Max Future HP", "Maximum predicted HP to use")
            end)
        end)

        M.COOLDOWNS_TREE:render("Cooldowns", function()
            M.DREAM_FLIGHT_TREE:render("Dream Flight", function()
                M.DREAM_FLIGHT_CHECK:render("Enabled", "Toggles Dream Flight usage")
                M.DREAM_FLIGHT_MIN_INJURED:render("Min Injured", "Minimum injured allies to cast")
                M.DREAM_FLIGHT_MIN_HEALTH_PCT:render("Min Health %", "Cast when group health below this")
            end)

            M.REWIND_TREE:render("Rewind", function()
                M.REWIND_CHECK:render("Enabled", "Toggles Rewind usage")
                M.REWIND_MIN_INJURED:render("Min Injured", "Minimum injured allies to cast")
            end)

            M.TEMPORAL_ANOMALY_TREE:render("Temporal Anomaly", function()
                M.TEMPORAL_ANOMALY_CHECK:render("Enabled", "Toggles Temporal Anomaly usage")
                M.TEMPORAL_ANOMALY_MIN_INJURED:render("Min Injured", "Minimum injured allies to cast")
            end)
        end)

        M.HEALING_TREE:render("Healing", function()
            M.EMERGENCY_HP:render("Emergency HP %", "Health % to trigger emergency healing")
            M.MAINTENANCE_HP:render("Maintenance HP %", "Health % to start proactive healing")
        end)

        M.EMPOWER_TREE:render("Empowered Spells", function()
            M.EMPOWER_PREFER_SPEED:render("Prefer Speed", "Use lower ranks for faster casts")
            M.EMPOWER_MIN_RANK:render("Minimum Rank", "Minimum empower rank (1-4)")
        end)
    end)
end)

core.register_on_render_control_panel_callback(function()
    local rotation_toggle_key = M.ROTATION_KEYBIND:get_key_code()
    local rotation_toggle = {
        name = string.format("[Preservation] Enabled (%s)", key_helper:get_key_name(rotation_toggle_key)),
        keybind = M.ROTATION_KEYBIND
    }

    local control_panel_elements = {}

    if M:is_enabled() then
        control_panel_utility:insert_toggle_(control_panel_elements, rotation_toggle.name, rotation_toggle.keybind, false)
    end

    return control_panel_elements
end)

-- Validators (extend as needed)
M.validate_dream_flight = M.new_validator_fn(M.DREAM_FLIGHT_CHECK, M.DREAM_FLIGHT_MIN_INJURED)
M.validate_rewind = M.new_validator_fn(M.REWIND_CHECK, M.REWIND_MIN_INJURED)
M.validate_temporal_anomaly = M.new_validator_fn(M.TEMPORAL_ANOMALY_CHECK, M.TEMPORAL_ANOMALY_MIN_INJURED)

return menu
