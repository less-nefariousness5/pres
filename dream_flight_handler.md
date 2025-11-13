# Dream Flight Positioning Module

Handles the complex positioning requirements for Dream Flight, including safe zone detection and ally path calculation.

```lua
-- modules/dream_flight_handler.lua
local dream_flight_handler = {}
local me = core.object_manager.get_local_player()

-- Dream Flight specifications
local DREAM_FLIGHT = {
    spell_id = 358267,
    range = 30,          -- Max cast range
    width = 6,           -- Path width for healing
    speed = 30,          -- Flight speed (yards/sec)
    heal_amount = 5.5,   -- SP coefficient
    cooldown = 120,      -- 2 minute CD
}

-- Calculate flight path and healing targets
function dream_flight_handler.calculate_flight_path(start_pos, end_pos)
    local path_data = {
        start = start_pos,
        target = end_pos,
        distance = start_pos:distance(end_pos),
        direction = (end_pos - start_pos):normalize(),
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
    local units = core.object_manager.get_party_raid_units()
    
    -- Check each ally's position relative to flight path
    for _, unit in ipairs(units) do
        if unit:is_alive() then
            local unit_pos = unit:position()
            
            -- Calculate perpendicular distance to flight path
            local to_unit = unit_pos - start_pos
            local path_projection = to_unit:dot(path_data.direction)
            
            -- Check if unit is within path length
            if path_projection >= 0 and path_projection <= path_data.distance then
                -- Calculate perpendicular distance
                local closest_point = start_pos + (path_data.direction * path_projection)
                local perp_distance = unit_pos:distance(closest_point)
                
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

-- Find safe landing position
function dream_flight_handler.find_safe_position(from_pos, preferred_direction, max_range)
    max_range = max_range or DREAM_FLIGHT.range
    
    -- Get dangerous areas from evade helper
    local danger_zones = evade_helper.get_dangerous_areas()
    
    -- Generate potential landing spots
    local candidates = {}
    
    -- Test 16 directions (every 22.5 degrees)
    for angle = 0, 360, 22.5 do
        local rad = math.rad(angle)
        
        -- Test multiple distances
        for distance = 10, max_range, 5 do
            local test_pos = vec3(
                from_pos.x + math.cos(rad) * distance,
                from_pos.y + math.sin(rad) * distance,
                from_pos.z
            )
            
            -- Check if position is safe
            local is_safe = true
            local danger_score = 0
            
            for _, zone in ipairs(danger_zones) do
                local dist_to_danger = test_pos:distance(zone.position)
                
                if dist_to_danger < zone.radius then
                    is_safe = false
                    break
                elseif dist_to_danger < zone.radius * 2 then
                    -- Close to danger, increase score
                    danger_score = danger_score + (1 / dist_to_danger) * zone.damage
                end
            end
            
            -- Check line of sight
            if is_safe and not me:has_los(test_pos) then
                is_safe = false
            end
            
            if is_safe then
                -- Calculate path data
                local path_data = dream_flight_handler.calculate_flight_path(from_pos, test_pos)
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

-- Score a flight path based on healing efficiency
function dream_flight_handler.score_flight_path(path_data)
    local score = 0
    
    -- Base score from ally count (heavily weighted)
    score = score + (path_data.heal_count * 100)
    
    -- Bonus for healing injured allies
    for _, ally in ipairs(path_data.allies_in_path) do
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

-- Main decision function
function dream_flight_handler.should_cast()
    -- Check cooldown
    if not izi_spell.is_ready(DREAM_FLIGHT.spell_id) then
        return false, nil
    end
    
    -- Check if we need group healing
    local injured_count = 0
    local total_deficit = 0
    local units = core.object_manager.get_party_raid_units()
    
    for _, unit in ipairs(units) do
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
    local best_path = dream_flight_handler.find_safe_position(my_pos)
    
    if not best_path then
        core.log("Dream Flight: No safe path found")
        return false, nil
    end
    
    -- Check if path is worth it
    if best_path.path_data.heal_count < 3 then
        return false, nil
    end
    
    -- Check if we're safe to cast
    local cast_time = 0.5  -- Approximate cast time
    local safe_window = evade_helper.get_safe_cast_window()
    
    if safe_window < cast_time then
        return false, nil
    end
    
    return true, best_path
end

-- Execute Dream Flight
function dream_flight_handler.cast()
    local should_cast, flight_data = dream_flight_handler.should_cast()
    
    if not should_cast or not flight_data then
        return false
    end
    
    core.log(string.format("Dream Flight: Healing %d allies, Score: %.1f", 
        flight_data.path_data.heal_count, 
        flight_data.score))
    
    -- Cast at the target position
    return izi_spell.cast_position(DREAM_FLIGHT.spell_id, flight_data.position)
end

-- Visualization helper for debugging
function dream_flight_handler.draw_flight_path(path_data)
    if not path_data then return end
    
    -- Draw line from start to end
    graphics.line_3d(
        path_data.start,
        path_data.target,
        color.green,
        2.0
    )
    
    -- Draw width boundaries
    local perpendicular = path_data.direction:cross(vec3(0, 0, 1)):normalize()
    local half_width = DREAM_FLIGHT.width / 2
    
    local left_start = path_data.start + (perpendicular * half_width)
    local left_end = path_data.target + (perpendicular * half_width)
    local right_start = path_data.start - (perpendicular * half_width)
    local right_end = path_data.target - (perpendicular * half_width)
    
    graphics.line_3d(left_start, left_end, color.yellow, 1.0)
    graphics.line_3d(right_start, right_end, color.yellow, 1.0)
    
    -- Draw circles at ally positions
    for _, ally in ipairs(path_data.allies_in_path) do
        local ally_color = ally.health_pct < 50 and color.red or color.green
        graphics.circle_3d(
            ally.unit:position(),
            1.0,
            ally_color,
            1.0
        )
    end
end

-- Alternative positioning for raids vs M+
function dream_flight_handler.get_optimal_position_raid()
    -- In raids, look for stacked groups
    local clusters = {}
    local units = core.object_manager.get_party_raid_units()
    
    -- Find clusters of players
    for _, unit in ipairs(units) do
        if unit:is_alive() then
            local pos = unit:position()
            local found_cluster = false
            
            for _, cluster in ipairs(clusters) do
                local dist = pos:distance(cluster.center)
                if dist < 8 then  -- Within 8 yards
                    -- Add to cluster
                    cluster.count = cluster.count + 1
                    cluster.total_deficit = cluster.total_deficit + (100 - unit:get_health_percentage())
                    -- Update center (simple average)
                    cluster.center = cluster.center + (pos - cluster.center) / cluster.count
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
    
    if #clusters >= 2 then
        -- Try to connect two clusters
        local start_cluster = clusters[1]
        local end_cluster = clusters[2]
        
        -- Find safe position beyond end cluster
        local direction = (end_cluster.center - start_cluster.center):normalize()
        local target_pos = end_cluster.center + (direction * 10)
        
        return target_pos
    elseif #clusters >= 1 then
        -- Fly through single cluster
        local cluster = clusters[1]
        
        -- Find direction with most allies
        local best_dir = vec3(1, 0, 0)
        local max_allies = 0
        
        for angle = 0, 360, 45 do
            local rad = math.rad(angle)
            local dir = vec3(math.cos(rad), math.sin(rad), 0)
            local test_end = cluster.center + (dir * 20)
            
            local path = dream_flight_handler.calculate_flight_path(me:position(), test_end)
            if path.heal_count > max_allies then
                max_allies = path.heal_count
                best_dir = dir
            end
        end
        
        return cluster.center + (best_dir * 20)
    end
    
    return nil
end

-- M+ specific positioning (usually tighter groups)
function dream_flight_handler.get_optimal_position_mythic_plus()
    -- In M+, party is usually more mobile and spread
    local party_center = vec3(0, 0, 0)
    local count = 0
    local units = core.object_manager.get_party_raid_units()
    
    -- Calculate party center
    for _, unit in ipairs(units) do
        if unit:is_alive() and unit:distance() < 40 then
            party_center = party_center + unit:position()
            count = count + 1
        end
    end
    
    if count > 0 then
        party_center = party_center / count
        
        -- Find safest direction from center
        local my_pos = me:position()
        local to_center = (party_center - my_pos):normalize()
        
        -- Extend beyond center
        local target = party_center + (to_center * 15)
        
        -- Verify safety
        if evade_helper.is_position_safe(target, 2.0) then
            return target
        end
    end
    
    return nil
end

-- Integration with evade helper
function dream_flight_handler.get_movement_required_time()
    -- Check if we need to move soon
    local danger_zones = evade_helper.get_dangerous_areas()
    local my_pos = me:position()
    local min_time = 999
    
    for _, zone in ipairs(danger_zones) do
        local dist = my_pos:distance(zone.position)
        if dist < zone.radius + 5 then  -- 5 yard buffer
            min_time = math.min(min_time, zone.time_until)
        end
    end
    
    return min_time
end

return dream_flight_handler
```
