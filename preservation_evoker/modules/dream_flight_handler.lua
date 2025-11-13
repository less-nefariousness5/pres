--[[
    Dream Flight Positioning Module for Preservation Evoker

    Handles the complex positioning requirements for Dream Flight,
    including safe zone detection and ally path calculation.

    Features:
    - Flight path calculation with ally detection
    - Safe zone verification
    - Cluster detection for raid positioning
    - Path scoring based on healing efficiency
    - Danger zone avoidance
]]

local izi = require("common/izi_sdk")
local vec3 = require("common/geometry/vec3")

---@class dream_flight_handler
local dream_flight_handler = {}

-- Dream Flight specifications
local DREAM_FLIGHT = {
    spell_id = 358267,
    range = 30,          -- Max cast range
    width = 6,           -- Path width for healing
    speed = 30,          -- Flight speed (yards/sec)
    heal_amount = 5.5,   -- SP coefficient
    cooldown = 120,      -- 2 minute CD
}

---@class path_data
---@field start vec3
---@field target vec3
---@field distance number
---@field direction vec3
---@field allies_in_path table[]
---@field heal_count number
---@field total_healing_needed number
---@field is_safe boolean
---@field danger_score number

---Calculate flight path and healing targets
---@param me game_object
---@param start_pos vec3
---@param end_pos vec3
---@return path_data path_data Flight path information
function dream_flight_handler.calculate_flight_path(me, start_pos, end_pos)
    ---@type path_data
    local path_data = {
        start = start_pos,
        target = end_pos,
        distance = start_pos:dist(end_pos),
        direction = (end_pos - start_pos):norm(),
        allies_in_path = {},
        heal_count = 0,
        total_healing_needed = 0,
        is_safe = false,
        danger_score = 0,
    }

    -- Check if path is too long
    if path_data.distance > DREAM_FLIGHT.range then
        return path_data
    end

    -- Get all allies
    local units = izi.friendly_units()

    -- Check each ally's position relative to flight path
    for i = 1, #units do
        local unit = units[i]
        if unit:is_alive() then
            local unit_pos = unit:position()

            -- Calculate perpendicular distance to flight path
            local to_unit = unit_pos - start_pos
            local path_projection = to_unit:dot(path_data.direction)

            -- Check if unit is within path length
            if path_projection >= 0 and path_projection <= path_data.distance then
                -- Calculate perpendicular distance
                local closest_point = start_pos + (path_data.direction * path_projection)
                local perp_distance = unit_pos:dist(closest_point)

                -- Check if within healing width
                if perp_distance <= DREAM_FLIGHT.width / 2 then
                    local health_pct = unit:get_health_percentage()
                    local healing_need = 100 - health_pct

                    table.insert(path_data.allies_in_path, {
                        unit = unit,
                        distance_on_path = path_projection,
                        perpendicular_distance = perp_distance,
                        health_pct = health_pct,
                        healing_need = healing_need,
                        is_tank = unit:is_tank(),
                    })

                    path_data.heal_count = path_data.heal_count + 1
                    path_data.total_healing_needed = path_data.total_healing_needed + healing_need
                end
            end
        end
    end

    -- Sort allies by distance along path
    table.sort(path_data.allies_in_path, function(a, b)
        return a.distance_on_path < b.distance_on_path
    end)

    return path_data
end

---Score a flight path based on healing efficiency
---@param path_data path_data
---@return number score Path score (higher = better)
function dream_flight_handler.score_flight_path(path_data)
    local score = 0

    -- Base score from ally count (heavily weighted)
    score = score + (path_data.heal_count * 100)

    -- Bonus for healing injured allies
    for i = 1, #path_data.allies_in_path do
        local ally = path_data.allies_in_path[i]

        -- More points for lower health
        if ally.health_pct < 30 then
            score = score + 50
        elseif ally.health_pct < 50 then
            score = score + 30
        elseif ally.health_pct < 70 then
            score = score + 15
        end

        -- Tank priority
        if ally.is_tank and ally.health_pct < 60 then
            score = score + 25
        end

        -- Clustering bonus (allies close together)
        if ally.perpendicular_distance < 2 then
            score = score + 10
        end
    end

    -- Total healing efficiency
    score = score + (path_data.total_healing_needed * 2)

    -- Safety penalty
    score = score - (path_data.danger_score * 50)

    -- Distance penalty (prefer shorter flights for reliability)
    score = score - (path_data.distance * 0.5)

    return score
end

---Find safe landing position
---@param me game_object
---@param from_pos vec3
---@param max_range number|nil
---@return table|nil best_path Best flight path or nil if none found
function dream_flight_handler.find_safe_position(me, from_pos, max_range)
    max_range = max_range or DREAM_FLIGHT.range

    -- Generate potential landing spots
    local candidates = {}

    -- Test 16 directions (every 22.5 degrees)
    for angle = 0, 337.5, 22.5 do
        local rad = math.rad(angle)

        -- Test multiple distances
        for distance = 10, max_range, 5 do
            local test_pos = vec3.new(
                from_pos.x + math.cos(rad) * distance,
                from_pos.y + math.sin(rad) * distance,
                from_pos.z
            )

            -- Basic safety check (would integrate with evade_helper in production)
            local is_safe = true
            local danger_score = 0

            -- TODO: Integrate with evade_helper.get_dangerous_areas()
            -- For now, assume safe

            -- Check line of sight
            if not me:has_los(test_pos) then
                is_safe = false
            end

            if is_safe then
                -- Calculate path data
                local path_data = dream_flight_handler.calculate_flight_path(me, from_pos, test_pos)
                path_data.is_safe = true
                path_data.danger_score = danger_score

                -- Score this position
                local score = dream_flight_handler.score_flight_path(path_data)

                table.insert(candidates, {
                    position = test_pos,
                    angle = angle,
                    distance = distance,
                    path_data = path_data,
                    score = score,
                })
            end
        end
    end

    -- Sort by score
    table.sort(candidates, function(a, b) return a.score > b.score end)

    -- Return best candidate
    if #candidates > 0 then
        return candidates[1]
    end

    return nil
end

---Main decision function - should we cast Dream Flight?
---@param me game_object
---@param spell_obj any IZI spell object for Dream Flight
---@return boolean should_cast, table|nil flight_data
function dream_flight_handler.should_cast(me, spell_obj)
    -- Check cooldown
    if not spell_obj:cooldown_up() then
        return false, nil
    end

    -- Check if we need group healing
    local injured_count = 0
    local total_deficit = 0
    local units = izi.friendly_units()

    for i = 1, #units do
        local unit = units[i]
        if unit:is_alive() then
            local hp_pct = unit:get_health_percentage()
            if hp_pct < 80 then
                injured_count = injured_count + 1
                total_deficit = total_deficit + (100 - hp_pct)
            end
        end
    end

    -- Need at least 3 injured or high total deficit
    if injured_count < 3 and total_deficit < 150 then
        return false, nil
    end

    -- Find best flight path
    local my_pos = me:position()
    local best_path = dream_flight_handler.find_safe_position(me, my_pos)

    if not best_path then
        core.log("Dream Flight: No safe path found")
        return false, nil
    end

    -- Check if path is worth it
    if best_path.path_data.heal_count < 3 then
        return false, nil
    end

    -- TODO: Check if we're safe to cast (would integrate with evade_helper)
    -- For now, assume safe

    return true, best_path
end

---Execute Dream Flight cast
---@param me game_object
---@param spell_obj any IZI spell object
---@return boolean success True if cast successful
function dream_flight_handler.cast(me, spell_obj)
    local should_cast, flight_data = dream_flight_handler.should_cast(me, spell_obj)

    if not should_cast or not flight_data then
        return false
    end

    core.log(string.format("Dream Flight: Healing %d allies, Score: %.1f",
        flight_data.path_data.heal_count,
        flight_data.score))

    -- Cast at the target position
    -- The izi_sdk should handle position casting
    return spell_obj:cast_safe(flight_data.position, "Dream Flight")
end

---Get optimal position for raids (cluster detection)
---@param me game_object
---@return vec3|nil position Optimal position or nil
function dream_flight_handler.get_optimal_position_raid(me)
    local clusters = {}
    local units = izi.friendly_units()

    -- Find clusters of players
    for i = 1, #units do
        local unit = units[i]
        if unit:is_alive() then
            local pos = unit:position()
            local found_cluster = false

            for j = 1, #clusters do
                local cluster = clusters[j]
                local dist = pos:dist(cluster.center)
                if dist < 8 then  -- Within 8 yards
                    -- Add to cluster
                    cluster.count = cluster.count + 1
                    cluster.total_deficit = cluster.total_deficit + (100 - unit:get_health_percentage())
                    -- Update center (simple average)
                    cluster.center = cluster.center + ((pos - cluster.center) / cluster.count)
                    found_cluster = true
                    break
                end
            end

            if not found_cluster then
                -- Create new cluster
                table.insert(clusters, {
                    center = pos,
                    count = 1,
                    total_deficit = 100 - unit:get_health_percentage(),
                })
            end
        end
    end

    -- Find best cluster to fly through
    table.sort(clusters, function(a, b)
        return (a.count * 100 + a.total_deficit) > (b.count * 100 + b.total_deficit)
    end)

    if #clusters >= 1 then
        local cluster = clusters[1]
        -- Extend 20 yards from cluster center in best direction
        local my_pos = me:position()
        local direction = (cluster.center - my_pos):norm()
        return cluster.center + (direction * 20)
    end

    return nil
end

---Count injured allies that would be healed by this path
---@param path_data path_data
---@param health_threshold number Health percentage threshold
---@return number count Number of injured allies in path
function dream_flight_handler.count_injured_in_path(path_data, health_threshold)
    local count = 0
    for i = 1, #path_data.allies_in_path do
        if path_data.allies_in_path[i].health_pct < health_threshold then
            count = count + 1
        end
    end
    return count
end

return dream_flight_handler
