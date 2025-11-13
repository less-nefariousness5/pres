# Preservation Evoker Advanced Healing Rotation Implementation Plan

## Overview
This implementation leverages the IZI SDK to create a sophisticated, modular healing rotation for Preservation Evoker. The system features intelligent target selection, predictive healing algorithms, health deficit calculations, and adaptive decision-making for both hero specializations (Chronowarden & Flameshaper).

## Core Architecture

### Module Structure
```
preservation_evoker/
├── main.lua                    -- Entry point & rotation controller
├── core/
│   ├── init.lua                -- Core initialization & SDK setup
│   ├── constants.lua           -- Spell IDs, buffs, settings
│   └── cache.lua               -- Performance-optimized caching system
├── modules/
│   ├── target_selector.lua     -- Smart healing target selection
│   ├── health_predictor.lua    -- Incoming damage & health prediction
│   ├── healing_calculator.lua  -- Healing need calculations
│   ├── essence_manager.lua     -- Essence resource management
│   ├── cooldown_tracker.lua    -- CD management & planning
│   ├── positioning.lua         -- Range & positioning logic
│   └── stop_cast.lua          -- Intelligent cast cancellation
├── apl/
│   ├── chronowarden.lua       -- Chronowarden hero talent APL
│   ├── flameshaper.lua        -- Flameshaper hero talent APL
│   └── leveling.lua           -- 10-70 leveling APL
├── rotations/
│   ├── raid_healing.lua       -- Raid healing priorities
│   ├── mythic_plus.lua        -- M+ healing priorities
│   └── pvp_healing.lua        -- PvP healing priorities
└── ui/
    ├── menu.lua               -- Configuration menu
    └── graphics.lua           -- Visual feedback system
```

## Module Implementations

### 1. Target Selector Module
Advanced smart healing target selection with priority weighting system.

```lua
-- target_selector.lua
local target_selector = {}
local me = core.object_manager.get_local_player()

-- Priority weights for different unit types
local PRIORITY_WEIGHTS = {
    tank = 1.5,
    healer = 1.3,
    dps = 1.0,
    self = 1.2
}

-- Get healing priority score for a unit
function target_selector.get_priority_score(unit)
    local score = 0
    
    -- Health deficit scoring (0-100 scale)
    local health_pct = unit:get_health_percentage()
    local health_score = (100 - health_pct) * 2  -- Weight health deficit heavily
    
    -- Incoming damage prediction (next 3 seconds)
    local incoming_dmg = unit:get_incoming_damage(3.0)
    local max_hp = unit:health_max()
    local damage_score = (incoming_dmg / max_hp) * 100 * 1.5
    
    -- Role-based priority
    local role_mult = 1.0
    if unit:is_tank() then
        role_mult = PRIORITY_WEIGHTS.tank
    elseif unit:get_guid() == me:get_guid() then
        role_mult = PRIORITY_WEIGHTS.self
    end
    
    -- Debuff priority (increase priority if unit has dangerous debuffs)
    local debuff_score = 0
    if unit:has_debuff({240443, 240447}) then  -- Example dangerous debuff IDs
        debuff_score = 30
    end
    
    -- Distance penalty (prefer closer targets for better positioning)
    local distance = unit:distance()
    local range_penalty = math.max(0, (distance - 20) * 2)  -- Penalty beyond 20 yards
    
    -- Calculate final score
    score = (health_score + damage_score + debuff_score) * role_mult - range_penalty
    
    -- Special cases
    if health_pct <= 30 then
        score = score * 2  -- Emergency priority
    end
    
    return score
end

-- Get best healing target from party/raid
function target_selector.get_best_heal_target(min_health_pct, max_range)
    min_health_pct = min_health_pct or 95
    max_range = max_range or 30
    
    local best_target = nil
    local best_score = 0
    
    -- Check all party/raid members
    local units = core.object_manager.get_party_raid_units()
    
    for _, unit in ipairs(units) do
        if unit:is_alive() and 
           unit:get_health_percentage() < min_health_pct and
           unit:distance() <= max_range then
            
            local score = target_selector.get_priority_score(unit)
            if score > best_score then
                best_score = score
                best_target = unit
            end
        end
    end
    
    return best_target, best_score
end

-- Get multiple targets for AoE healing
function target_selector.get_aoe_targets(count, min_health_pct, radius)
    count = count or 5
    min_health_pct = min_health_pct or 90
    radius = radius or 10
    
    local targets = {}
    local units = core.object_manager.get_party_raid_units()
    
    -- Score and sort all eligible units
    local scored_units = {}
    for _, unit in ipairs(units) do
        if unit:is_alive() and unit:get_health_percentage() < min_health_pct then
            table.insert(scored_units, {
                unit = unit,
                score = target_selector.get_priority_score(unit)
            })
        end
    end
    
    -- Sort by score
    table.sort(scored_units, function(a, b) return a.score > b.score end)
    
    -- Get top targets that are clustered
    for i = 1, math.min(count, #scored_units) do
        table.insert(targets, scored_units[i].unit)
    end
    
    return targets
end

-- Tank-specific targeting
function target_selector.get_tank_target()
    local tanks = {}
    local units = core.object_manager.get_party_raid_units()
    
    for _, unit in ipairs(units) do
        if unit:is_tank() and unit:is_alive() then
            table.insert(tanks, {
                unit = unit,
                score = target_selector.get_priority_score(unit)
            })
        end
    end
    
    table.sort(tanks, function(a, b) return a.score > b.score end)
    
    return tanks[1] and tanks[1].unit or nil
end

return target_selector
```

### 2. Health Predictor Module
Advanced health prediction using damage patterns and incoming damage calculations.

```lua
-- health_predictor.lua
local health_predictor = {}

-- Cache for damage history
local damage_history = {}
local HISTORY_DURATION = 5.0  -- Track last 5 seconds

-- Predict health in X seconds
function health_predictor.predict_health(unit, time_ahead)
    time_ahead = time_ahead or 2.0
    
    local current_hp = unit:health()
    local max_hp = unit:health_max()
    local current_pct = unit:get_health_percentage()
    
    -- Get incoming damage prediction
    local incoming_dmg = unit:get_incoming_damage(time_ahead)
    
    -- Get recent damage pattern (for burst detection)
    local recent_dmg = health_predictor.get_recent_damage_rate(unit)
    
    -- Calculate healing received estimate
    local incoming_healing = health_predictor.estimate_incoming_healing(unit)
    
    -- Predict final health
    local predicted_hp = current_hp - incoming_dmg + incoming_healing
    local predicted_pct = (predicted_hp / max_hp) * 100
    
    return {
        current_hp = current_hp,
        current_pct = current_pct,
        predicted_hp = math.max(0, predicted_hp),
        predicted_pct = math.max(0, predicted_pct),
        damage_rate = recent_dmg,
        healing_rate = incoming_healing / time_ahead,
        will_die = predicted_hp <= 0,
        emergency = predicted_pct < 30
    }
end

-- Track damage patterns
function health_predictor.update_damage_history()
    local current_time = core.time()
    local units = core.object_manager.get_party_raid_units()
    
    for _, unit in ipairs(units) do
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
        for i = #damage_history[guid], 1, -1 do
            if damage_history[guid][i].time < cutoff then
                table.remove(damage_history[guid], i)
            end
        end
    end
end

-- Calculate recent damage rate
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

-- Estimate incoming healing from other sources
function health_predictor.estimate_incoming_healing(unit)
    local healing = 0
    
    -- Check for HoT effects
    local hots = {
        -- Preservation Evoker HoTs
        {id = 366155, mult = 1.0},  -- Reversion
        {id = 355941, mult = 1.5},  -- Dream Breath HoT
        {id = 373267, mult = 0.8},  -- Lifebind echo healing
    }
    
    for _, hot in ipairs(hots) do
        if unit:has_buff(hot.id) then
            local remaining = unit:buff_remains(hot.id)
            -- Estimate HoT tick healing based on spell power
            local sp = me:get_spell_power()
            healing = healing + (sp * 0.3 * hot.mult * remaining)
        end
    end
    
    return healing
end

-- Detect incoming spike damage
function health_predictor.detect_spike_damage(unit, threshold_time)
    threshold_time = threshold_time or 1.0
    
    local incoming = unit:get_incoming_damage(threshold_time)
    local max_hp = unit:health_max()
    local spike_threshold = max_hp * 0.4  -- 40% health as spike
    
    return incoming >= spike_threshold
end

return health_predictor
```

### 3. Healing Calculator Module
Sophisticated healing calculations with mastery, versatility, and crit considerations.

```lua
-- healing_calculator.lua
local healing_calculator = {}
local me = core.object_manager.get_local_player()

-- Calculate effective healing needed
function healing_calculator.calculate_healing_needed(unit)
    local current_hp = unit:health()
    local max_hp = unit:health_max()
    local missing_hp = max_hp - current_hp
    
    -- Factor in incoming damage
    local incoming = unit:get_incoming_damage(2.0)
    
    -- Factor in existing HoTs
    local hot_healing = 0
    if unit:has_buff(366155) then  -- Reversion
        hot_healing = hot_healing + (me:get_spell_power() * 0.8)
    end
    
    local effective_need = missing_hp + incoming - hot_healing
    
    return {
        missing_hp = missing_hp,
        incoming_damage = incoming,
        hot_healing = hot_healing,
        total_need = math.max(0, effective_need),
        percent_need = (effective_need / max_hp) * 100
    }
end

-- Calculate mastery bonus
function healing_calculator.calculate_mastery_bonus(target)
    -- Preservation Mastery: Life-Binder
    -- Increases healing based on your health % vs target health %
    local my_health_pct = me:get_health_percentage()
    local target_health_pct = target:get_health_percentage()
    
    if my_health_pct > target_health_pct then
        local mastery = me:get_mastery_percent()
        local health_diff = my_health_pct - target_health_pct
        local bonus = (health_diff / 100) * mastery
        return 1 + (bonus / 100)
    end
    
    return 1.0
end

-- Estimate spell healing
function healing_calculator.estimate_heal_amount(spell_id, target, empower_rank)
    empower_rank = empower_rank or 0
    
    local base_healing = {
        [355941] = 4.5,   -- Dream Breath (per target)
        [367364] = 3.8,   -- Spiritbloom (base)
        [361227] = 2.2,   -- Living Flame
        [355913] = 2.8,   -- Emerald Blossom
        [364343] = 1.5,   -- Echo
        [382614] = 3.5,   -- Engulf (Flameshaper)
    }
    
    local sp = me:get_spell_power()
    local vers = me:get_versatility_percent()
    local crit = me:get_crit_percent()
    
    local base = (base_healing[spell_id] or 1.0) * sp
    
    -- Empower bonus
    if empower_rank > 0 then
        base = base * (1 + (empower_rank * 0.25))
    end
    
    -- Mastery bonus
    local mastery_mult = healing_calculator.calculate_mastery_bonus(target)
    
    -- Versatility
    local vers_mult = 1 + (vers / 100)
    
    -- Estimate crit (simplified)
    local crit_mult = 1 + ((crit / 100) * 0.5)
    
    return base * mastery_mult * vers_mult * crit_mult
end

-- Group healing efficiency calculation
function healing_calculator.calculate_aoe_efficiency(spell_id, targets)
    local total_healing = 0
    local effective_healing = 0
    
    for _, target in ipairs(targets) do
        local heal_amount = healing_calculator.estimate_heal_amount(spell_id, target)
        local healing_need = healing_calculator.calculate_healing_needed(target)
        
        total_healing = total_healing + heal_amount
        effective_healing = effective_healing + math.min(heal_amount, healing_need.total_need)
    end
    
    local efficiency = (effective_healing / total_healing) * 100
    
    return {
        total = total_healing,
        effective = effective_healing,
        efficiency = efficiency,
        overheal = total_healing - effective_healing
    }
end

return healing_calculator
```

### 4. Essence Manager Module
Intelligent essence resource management and optimization.

```lua
-- essence_manager.lua
local essence_manager = {}
local me = core.object_manager.get_local_player()

-- Essence costs
local ESSENCE_COSTS = {
    [364343] = 2,  -- Echo
    [355913] = 3,  -- Emerald Blossom  
    [356995] = 3,  -- Disintegrate
}

-- Get current essence
function essence_manager.get_essence()
    return me:power(19)  -- Essence power type
end

-- Get max essence
function essence_manager.get_max_essence()
    return me:max_power(19)
end

-- Check if we have enough essence
function essence_manager.can_cast(spell_id)
    local cost = ESSENCE_COSTS[spell_id] or 0
    return essence_manager.get_essence() >= cost
end

-- Predict essence in X seconds
function essence_manager.predict_essence(seconds)
    local current = essence_manager.get_essence()
    local regen_rate = 0.2  -- Base 1 essence per 5 seconds
    
    -- Check for essence burst procs
    if me:has_buff(369256) then  -- Essence Burst
        current = current + 1
    end
    
    local predicted = current + (regen_rate * seconds)
    return math.min(predicted, essence_manager.get_max_essence())
end

-- Essence spending priority
function essence_manager.get_spend_priority()
    local essence = essence_manager.get_essence()
    local targets = target_selector.get_aoe_targets(5, 90, 10)
    
    -- Priority: Echo for setup > Emerald Blossom for AoE > Disintegrate for damage
    if essence >= 2 then
        -- Check if Echo setup is needed
        local echo_targets = 0
        for _, target in ipairs(targets) do
            if not target:has_buff(364343) then  -- No Echo
                echo_targets = echo_targets + 1
            end
        end
        
        if echo_targets >= 2 and essence >= 4 then
            return "echo_setup"
        end
    end
    
    if essence >= 3 then
        -- Check for AoE healing need
        if #targets >= 3 then
            return "emerald_blossom"
        end
    end
    
    if essence >= 5 then  -- Near cap
        return "spend_any"
    end
    
    return "conserve"
end

-- Should we hold essence for upcoming damage
function essence_manager.should_pool(time_to_damage)
    time_to_damage = time_to_damage or 5.0
    
    local current = essence_manager.get_essence()
    local max = essence_manager.get_max_essence()
    
    -- Don't pool if near cap
    if current >= max - 1 then
        return false
    end
    
    -- Pool if big damage coming soon
    if time_to_damage <= 3.0 and current < 4 then
        return true
    end
    
    return false
end

return essence_manager
```

### 5. Stop Cast Logic Module
Intelligent spell interruption and recasting decisions.

```lua
-- stop_cast.lua
local stop_cast = {}
local me = core.object_manager.get_local_player()

-- Cached cast info
local current_cast = {
    spell_id = 0,
    target = nil,
    start_time = 0,
    empower_rank = 0
}

-- Update current cast info
function stop_cast.update_cast_info()
    if me:is_casting() or me:is_channeling() then
        current_cast.spell_id = me:get_active_cast_or_channel_id()
        current_cast.start_time = current_cast.start_time or core.time()
    else
        current_cast = {spell_id = 0, target = nil, start_time = 0, empower_rank = 0}
    end
end

-- Should we stop current cast?
function stop_cast.should_stop_cast()
    if not me:is_casting() and not me:is_channeling() then
        return false
    end
    
    local spell = current_cast.spell_id
    local target = current_cast.target
    
    -- Don't interrupt instant casts
    if me:get_cast_time_remaining() < 0.2 then
        return false
    end
    
    -- Check if target will be overhealed
    if target and target:is_alive() then
        local heal_amount = healing_calculator.estimate_heal_amount(spell, target, current_cast.empower_rank)
        local need = healing_calculator.calculate_healing_needed(target)
        
        -- Stop if we'll overheal by more than 50%
        if heal_amount > need.total_need * 1.5 then
            -- Check for higher priority target
            local best_target = target_selector.get_best_heal_target(70, 30)
            if best_target and best_target ~= target then
                local best_need = healing_calculator.calculate_healing_needed(best_target)
                if best_need.percent_need > 40 then
                    return true  -- Stop for emergency
                end
            end
        end
    end
    
    -- Check for emergency situations
    local emergency_target = target_selector.get_best_heal_target(30, 30)
    if emergency_target and emergency_target ~= target then
        -- Stop channeled spells for emergencies
        if spell == 355941 or spell == 367364 then  -- Dream Breath / Spiritbloom
            return true
        end
    end
    
    return false
end

-- Get optimal empower rank
function stop_cast.get_optimal_empower_rank(spell_id, target)
    local ranks = {
        [355941] = 4,  -- Dream Breath max rank
        [367364] = 4,  -- Spiritbloom max rank  
        [357208] = 3,  -- Fire Breath max rank
    }
    
    local max_rank = ranks[spell_id] or 1
    
    -- For healing spells, calculate based on need
    if spell_id == 355941 or spell_id == 367364 then
        local need = healing_calculator.calculate_healing_needed(target)
        
        -- Emergency = max rank
        if need.percent_need > 60 then
            return max_rank
        end
        
        -- Moderate = rank 2-3
        if need.percent_need > 30 then
            return math.ceil(max_rank * 0.75)
        end
        
        -- Light = rank 1
        return 1
    end
    
    -- Fire Breath - always max for damage
    return max_rank
end

-- Should we release empower early?
function stop_cast.should_release_empower()
    if not me:is_channeling() then
        return false
    end
    
    local spell = current_cast.spell_id
    local channel_time = core.time() - current_cast.start_time
    
    -- Get current empower rank based on channel time
    local rank = math.floor(channel_time / 0.75) + 1  -- Roughly 0.75s per rank
    
    -- Check if we've reached desired rank
    local optimal_rank = stop_cast.get_optimal_empower_rank(spell, current_cast.target)
    
    if rank >= optimal_rank then
        return true
    end
    
    -- Release early for emergencies
    local emergency_target = target_selector.get_best_heal_target(25, 30)
    if emergency_target and rank >= 1 then
        return true
    end
    
    return false
end

return stop_cast
```

### 6. APL - Chronowarden Hero Spec
Echo-focused healing with temporal magic synergies.

```lua
-- apl/chronowarden.lua
local chronowarden = {}
local me = core.object_manager.get_local_player()

-- Spell IDs
local SPELLS = {
    -- Core Heals
    ECHO = 364343,
    SPIRITBLOOM = 367364,
    DREAM_BREATH = 355941,
    REVERSION = 366155,
    LIVING_FLAME = 361469,
    VERDANT_EMBRACE = 360995,
    
    -- Cooldowns
    TEMPORAL_ANOMALY = 373861,
    TIP_THE_SCALES = 370553,
    STASIS = 370537,
    REWIND = 363534,
    TIME_DILATION = 357170,
    
    -- Damage
    FIRE_BREATH = 357208,
    DISINTEGRATE = 356995,
    
    -- Buffs
    ESSENCE_BURST = 369256,
    TEMPORAL_COMPRESSION = 431462,  -- Chronowarden specific
    CHRONO_FLAME = 431442,         -- Chronowarden Living Flame
}

-- Main rotation
function chronowarden.rotation()
    -- Update systems
    stop_cast.update_cast_info()
    health_predictor.update_damage_history()
    
    -- Check for cast interruption
    if stop_cast.should_stop_cast() then
        me:stop_casting()
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

-- Emergency healing
function chronowarden.handle_emergency()
    local emergency_target = target_selector.get_best_heal_target(30, 30)
    
    if emergency_target then
        -- Rewind for multiple low targets
        local low_count = 0
        local units = core.object_manager.get_party_raid_units()
        for _, unit in ipairs(units) do
            if unit:get_health_percentage() < 40 then
                low_count = low_count + 1
            end
        end
        
        if low_count >= 3 and izi_spell.cast(SPELLS.REWIND) then
            return true
        end
        
        -- Tip the Scales + Spiritbloom
        if izi_spell.cast(SPELLS.TIP_THE_SCALES) then
            return true
        end
        
        if me:has_buff(370553) then  -- Tip the Scales active
            if izi_spell.cast_unit(SPELLS.SPIRITBLOOM, emergency_target, {empower_rank = 4}) then
                current_cast.target = emergency_target
                return true
            end
        end
        
        -- Verdant Embrace for instant heal
        if izi_spell.cast_unit(SPELLS.VERDANT_EMBRACE, emergency_target) then
            return true
        end
    end
    
    return false
end

-- Setup Echo on party
function chronowarden.setup_echoes()
    local essence = essence_manager.get_essence()
    if essence < 2 then
        return false
    end
    
    -- Cast Temporal Anomaly first for free echoes
    if izi_spell.cast(SPELLS.TEMPORAL_ANOMALY) then
        return true
    end
    
    -- Manual echo setup
    local units = target_selector.get_aoe_targets(5, 85, 30)
    for _, unit in ipairs(units) do
        if not unit:has_buff(SPELLS.ECHO) then
            if izi_spell.cast_unit(SPELLS.ECHO, unit) then
                return true
            end
        end
    end
    
    return false
end

-- Consume echoes with healing spells
function chronowarden.consume_echoes()
    local echo_count = 0
    local units = core.object_manager.get_party_raid_units()
    
    -- Count active echoes
    for _, unit in ipairs(units) do
        if unit:has_buff(SPELLS.ECHO) then
            echo_count = echo_count + 1
        end
    end
    
    if echo_count < 2 then
        return false
    end
    
    -- Determine best echo consumer
    local avg_health = 0
    local injured_count = 0
    
    for _, unit in ipairs(units) do
        local hp_pct = unit:get_health_percentage()
        avg_health = avg_health + hp_pct
        if hp_pct < 80 then
            injured_count = injured_count + 1
        end
    end
    avg_health = avg_health / #units
    
    -- Verdant Embrace + Emerald Communion combo
    if injured_count >= 3 and avg_health < 60 then
        local target = target_selector.get_best_heal_target(70, 30)
        if target then
            if izi_spell.cast_unit(SPELLS.VERDANT_EMBRACE, target) then
                return true
            end
            if me:has_buff(360995) then  -- Verdant active
                if izi_spell.cast(370960) then  -- Emerald Communion
                    return true
                end
            end
        end
    end
    
    -- Spiritbloom for burst healing
    if injured_count >= 2 and avg_health < 70 then
        local target = me  -- Cast on self for smart healing
        if izi_spell.cast_unit(SPELLS.SPIRITBLOOM, target, {empower_rank = 3}) then
            current_cast.target = target
            return true
        end
    end
    
    -- Dream Breath for HoT application
    if injured_count >= 1 then
        if izi_spell.cast(SPELLS.DREAM_BREATH, {empower_rank = 2}) then
            return true
        end
    end
    
    -- Reversion for single target
    local tank = target_selector.get_tank_target()
    if tank and not tank:has_buff(SPELLS.REVERSION) then
        if izi_spell.cast_unit(SPELLS.REVERSION, tank) then
            return true
        end
    end
    
    return false
end

-- Maintenance healing
function chronowarden.maintenance_healing()
    -- Keep Reversion on tanks
    local tank = target_selector.get_tank_target()
    if tank and not tank:has_buff(SPELLS.REVERSION) then
        if izi_spell.cast_unit(SPELLS.REVERSION, tank) then
            return true
        end
    end
    
    -- Chrono Flame (Living Flame) for Essence Burst
    if me:has_buff(SPELLS.ESSENCE_BURST) then
        local target = target_selector.get_best_heal_target(90, 30)
        if target then
            if izi_spell.cast_unit(SPELLS.LIVING_FLAME, target) then
                return true
            end
        end
    end
    
    return false
end

-- Cooldown usage
function chronowarden.use_cooldowns()
    -- Stasis management
    if not me:has_buff(SPELLS.STASIS) then
        -- Check if we should prepare stasis
        local avg_health = 0
        local units = core.object_manager.get_party_raid_units()
        for _, unit in ipairs(units) do
            avg_health = avg_health + unit:get_health_percentage()
        end
        avg_health = avg_health / #units
        
        if avg_health < 75 then
            if izi_spell.cast(SPELLS.STASIS) then
                -- Queue up abilities in stasis
                return true
            end
        end
    end
    
    -- Time Dilation on tank
    local tank = target_selector.get_tank_target()
    if tank then
        local prediction = health_predictor.predict_health(tank, 3.0)
        if prediction.predicted_pct < 50 then
            if izi_spell.cast_unit(SPELLS.TIME_DILATION, tank) then
                return true
            end
        end
    end
    
    return false
end

-- DPS rotation
function chronowarden.dps_rotation()
    -- Fire Breath for Leaping Flames
    local enemies = core.object_manager.get_enemies(30)
    if #enemies > 0 then
        if izi_spell.cast(SPELLS.FIRE_BREATH, {empower_rank = 3}) then
            return true
        end
        
        -- Living Flame spam
        local target = enemies[1]
        if izi_spell.cast_unit(SPELLS.LIVING_FLAME, target) then
            return true
        end
    end
end

return chronowarden
```

### 7. APL - Flameshaper Hero Spec
Engulf-focused burst healing with fire synergies.

```lua
-- apl/flameshaper.lua
local flameshaper = {}
local me = core.object_manager.get_local_player()

-- Spell IDs
local SPELLS = {
    -- Core Heals
    ENGULF = 382614,
    DREAM_BREATH = 355941,
    SPIRITBLOOM = 367364,
    EMERALD_BLOSSOM = 355913,
    LIVING_FLAME = 361469,
    VERDANT_EMBRACE = 360995,
    
    -- Cooldowns
    RENEWING_BLAZE = 374348,  -- Becomes Lifecinders
    STASIS = 370537,
    REWIND = 363534,
    
    -- Buffs
    CONSUME_FLAME = 431869,  -- Flameshaper mechanic
    INNER_FLAME = 431872,    -- Tier set bonus
}

-- Main rotation
function flameshaper.rotation()
    -- Update systems
    stop_cast.update_cast_info()
    health_predictor.update_damage_history()
    
    -- Emergency healing
    if flameshaper.handle_emergency() then
        return
    end
    
    -- Engulf burst windows
    if flameshaper.engulf_rotation() then
        return
    end
    
    -- Dream Breath spreading
    if flameshaper.spread_dream_breath() then
        return
    end
    
    -- Maintenance healing
    if flameshaper.maintenance_healing() then
        return
    end
    
    -- DPS rotation
    flameshaper.dps_rotation()
end

-- Engulf burst healing combo
function flameshaper.engulf_rotation()
    local targets = target_selector.get_aoe_targets(5, 75, 10)
    
    if #targets < 2 then
        return false
    end
    
    -- Setup: Verdant Embrace + Dream Breath
    local best_target = targets[1]
    
    -- Apply Dream Breath first
    if not best_target:has_buff(355941) then  -- Dream Breath HoT
        if izi_spell.cast_unit(SPELLS.VERDANT_EMBRACE, best_target) then
            return true
        end
        
        if me:has_buff(360995) then  -- Verdant active
            if izi_spell.cast(SPELLS.DREAM_BREATH, {empower_rank = 2}) then
                return true
            end
        end
    end
    
    -- Engulf on Dream Breath target for Consume Flame
    if best_target:has_buff(355941) then
        if izi_spell.cast_unit(SPELLS.ENGULF, best_target) then
            return true
        end
    end
    
    return false
end

-- Spread Dream Breath for Engulf synergy
function flameshaper.spread_dream_breath()
    local units = target_selector.get_aoe_targets(5, 85, 10)
    local needs_dream = {}
    
    for _, unit in ipairs(units) do
        if not unit:has_buff(355941) then
            table.insert(needs_dream, unit)
        end
    end
    
    if #needs_dream >= 3 then
        -- Use Verdant for Call of Ysera
        local target = needs_dream[1]
        if izi_spell.cast_unit(SPELLS.VERDANT_EMBRACE, target) then
            return true
        end
        
        if izi_spell.cast(SPELLS.DREAM_BREATH, {empower_rank = 1}) then
            return true
        end
    end
    
    return false
end

-- Emergency handling with Lifecinders
function flameshaper.handle_emergency()
    local emergency_target = target_selector.get_best_heal_target(30, 30)
    
    if emergency_target then
        -- Lifecinders (external Renewing Blaze)
        if izi_spell.cast_unit(SPELLS.RENEWING_BLAZE, emergency_target) then
            return true
        end
        
        -- Engulf burst
        if emergency_target:has_buff(355941) then
            if izi_spell.cast_unit(SPELLS.ENGULF, emergency_target) then
                return true
            end
        end
        
        -- Verdant + Spiritbloom
        if izi_spell.cast_unit(SPELLS.VERDANT_EMBRACE, emergency_target) then
            return true
        end
        
        if izi_spell.cast_unit(SPELLS.SPIRITBLOOM, me, {empower_rank = 4}) then
            current_cast.target = me
            return true
        end
    end
    
    return false
end

-- Maintenance with tier set synergy
function flameshaper.maintenance_healing()
    -- Consume Inner Flame buff with Essence Burst
    if me:has_buff(SPELLS.INNER_FLAME) and me:has_buff(369256) then
        -- Cast Emerald Blossom for Essence Bomb
        local targets = target_selector.get_aoe_targets(3, 80, 10)
        if #targets >= 2 then
            local target = targets[1]
            if izi_spell.cast_unit(SPELLS.EMERALD_BLOSSOM, target) then
                return true
            end
        end
    end
    
    -- Living Flame with Leaping Flames
    if me:has_buff(370901) then  -- Leaping Flames
        local target = target_selector.get_best_heal_target(85, 30)
        if target then
            if izi_spell.cast_unit(SPELLS.LIVING_FLAME, target) then
                return true
            end
        end
    end
    
    return false
end

-- DPS rotation
function flameshaper.dps_rotation()
    local enemies = core.object_manager.get_enemies(30)
    
    if #enemies > 0 then
        -- Fire Breath for Leaping Flames and damage
        if izi_spell.cast(SPELLS.FIRE_BREATH, {empower_rank = 3}) then
            return true
        end
        
        -- Living Flame
        if izi_spell.cast_unit(SPELLS.LIVING_FLAME, enemies[1]) then
            return true
        end
    end
end

return flameshaper
```

### 8. Empowered Spell Handler
Intelligent empowered spell rank management with dynamic decision making.

*See empower_handler.md for full implementation*

Key features:
- Dynamic rank calculation based on urgency and health deficits
- Movement prediction integration for early releases
- Emergency interruption for critical healing needs
- Rank-specific optimization for each empowered spell

### 9. Dream Flight Positioning Handler  
Complex positioning calculations for optimal Dream Flight usage.

*See dream_flight_handler.md for full implementation*

Key features:
- Flight path calculation with ally detection
- Safe zone verification using evade_helper
- Cluster detection for raid positioning
- Path scoring based on healing efficiency
- Visual debugging with path rendering

### 10. Main Rotation Controller
Central controller that manages spec selection and rotation execution.

```lua
-- main.lua
local main = {}

-- Load modules
local target_selector = require("modules.target_selector")
local health_predictor = require("modules.health_predictor")
local healing_calculator = require("modules.healing_calculator")
local essence_manager = require("modules.essence_manager")
local stop_cast = require("modules.stop_cast")

-- Load APLs
local chronowarden = require("apl.chronowarden")
local flameshaper = require("apl.flameshaper")
local leveling = require("apl.leveling")

-- Configuration
local config = {
    hero_spec = "chronowarden",  -- chronowarden / flameshaper
    content_type = "mythic_plus", -- raid / mythic_plus / pvp
    debug_mode = false,
}

-- Initialize
function main.initialize()
    core.log("Preservation Evoker rotation initialized")
    core.log("Hero Spec: " .. config.hero_spec)
    core.log("Content Type: " .. config.content_type)
end

-- Main pulse/tick function
function main.pulse()
    local me = core.object_manager.get_local_player()
    
    -- Basic checks
    if not me or me:is_dead_or_ghost() then
        return
    end
    
    if me:is_mounted() then
        return
    end
    
    -- Check level for spec selection
    local level = me:level()
    
    if level < 71 then
        -- Use leveling rotation
        leveling.rotation()
    elseif config.hero_spec == "flameshaper" then
        flameshaper.rotation()
    else
        -- Default to Chronowarden
        chronowarden.rotation()
    end
    
    -- Debug output
    if config.debug_mode then
        main.debug_output()
    end
end

-- Debug information
function main.debug_output()
    local me = core.object_manager.get_local_player()
    local essence = essence_manager.get_essence()
    local best_target = target_selector.get_best_heal_target(95, 30)
    
    if best_target then
        local score = target_selector.get_priority_score(best_target)
        local prediction = health_predictor.predict_health(best_target, 2.0)
        
        core.log(string.format(
            "Target: %s | Score: %.1f | HP: %.1f%% | Predicted: %.1f%% | Essence: %d",
            best_target:name(),
            score,
            best_target:get_health_percentage(),
            prediction.predicted_pct,
            essence
        ))
    end
end

-- Menu configuration
function main.create_menu()
    local menu = {}
    
    menu.hero_spec = {
        type = "dropdown",
        text = "Hero Specialization",
        options = {"chronowarden", "flameshaper"},
        default = "chronowarden",
        callback = function(value)
            config.hero_spec = value
            core.log("Hero spec changed to: " .. value)
        end
    }
    
    menu.content_type = {
        type = "dropdown",
        text = "Content Type",
        options = {"raid", "mythic_plus", "pvp"},
        default = "mythic_plus",
        callback = function(value)
            config.content_type = value
            core.log("Content type changed to: " .. value)
        end
    }
    
    menu.debug_mode = {
        type = "checkbox",
        text = "Debug Mode",
        default = false,
        callback = function(value)
            config.debug_mode = value
        end
    }
    
    return menu
end

-- Register with IZI
izi_module.register({
    name = "Preservation Evoker",
    author = "Advanced Healing System",
    version = "1.0.0",
    initialize = main.initialize,
    pulse = main.pulse,
    menu = main.create_menu(),
})

return main
```

## Advanced Features

### Predictive Healing AI
- Analyzes damage patterns over 5-second windows
- Predicts health states 2-3 seconds in advance
- Identifies burst damage windows and pre-positions healing
- Tracks damage types (physical/magical) for mitigation decisions

### Smart Target Prioritization
- Dynamic scoring system weighing:
  - Health deficit (current and predicted)
  - Role importance (tank > healer > dps)
  - Debuff severity
  - Positioning efficiency
  - Incoming damage rate
- Automatic triage during high damage phases

### Cooldown Optimization
- Tracks all major and minor cooldowns
- Plans cooldown usage based on encounter timers
- Automatic cooldown chaining for maximum throughput
- Emergency reservation system

### Movement Prediction
- Tracks player movement patterns
- Predicts positioning for optimal spell placement
- Hover/movement ability integration
- Range optimization for 25-yard healing range

### Performance Optimizations
- Buff/debuff caching with 100ms update intervals
- Squared distance calculations to avoid sqrt operations
- Lazy evaluation of non-critical calculations
- Memory pooling for frequently created objects

## Configuration Options

### Menu Settings
- Hero Specialization selection
- Content type optimization (Raid/M+/PvP)
- Healing aggressiveness slider
- Mana conservation mode
- Visual feedback toggles
- Debug output options

### Customizable Thresholds
- Emergency healing (default: 30% HP)
- Tank priority (default: 1.5x multiplier)
- Overheal tolerance (default: 50%)
- Essence pooling (default: 4 essence)
- Empower rank decisions

## Integration Points

### IZI SDK Functions Used
- `game_object:get_health_percentage()`
- `game_object:get_incoming_damage(deadline_time)`
- `game_object:is_tank()` / `is_healer()` / `is_dps()`
- `game_object:has_buff()` / `buff_remains()`
- `game_object:distance()`
- `game_object:is_casting()` / `is_channeling()`
- `game_object:get_enemies_in_splash_range()`
- `izi_spell.cast()` / `cast_unit()`
- `core.object_manager.get_party_raid_units()`

## Testing Checklist

### Unit Tests
- [ ] Target selection accuracy
- [ ] Health prediction validation
- [ ] Healing calculation formulas
- [ ] Essence management logic
- [ ] Stop cast decision tree

### Integration Tests
- [ ] Full rotation execution
- [ ] Hero spec switching
- [ ] Emergency response time
- [ ] Cooldown usage patterns
- [ ] Performance benchmarks

### Scenario Tests
- [ ] Raid-wide damage
- [ ] Tank spike damage
- [ ] Spread healing requirements
- [ ] Movement-heavy encounters
- [ ] Mana conservation phases

## Future Enhancements

1. **Machine Learning Integration**
   - Pattern recognition for encounter-specific optimizations
   - Adaptive threshold tuning based on group composition

2. **Advanced Positioning**
   - Predictive movement for preemptive positioning
   - Rescue coordination with tank movement

3. **Group Synergy**
   - Coordinate with other healers' cooldowns
   - Damage reduction timing with tank defensives

4. **Encounter Database**
   - Pre-programmed timers for known encounters
   - Automatic strategy adjustments

5. **PvP Specialization**
   - Enemy cooldown tracking
   - CC chain predictions
   - Dampening adjustments
