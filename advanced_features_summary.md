# Preservation Evoker - Advanced Features Update

## New Modules Added

### 1. Empowered Spell Handler (`empower_handler.lua`)

This module provides intelligent management of Evoker's unique empowered spell mechanic, where spells can be charged through multiple ranks for increased effect.

#### Key Features:

**Dynamic Rank Calculation**
- Analyzes combat situation to determine optimal empower rank
- Factors in: urgency level, target count, health deficits, available cast time
- Different logic for each spell (Dream Breath, Spiritbloom, Fire Breath)

**Intelligent Release Timing**
- Monitors channel progress and releases at optimal rank
- Emergency release for critical healing situations
- Movement prediction to release before forced movement
- Target validation (stops if target dies/full health)

**Rank Decision Examples:**
- **Dream Breath**: Rank 4 for raid damage (>60% deficit), Rank 1 for quick HoT application
- **Spiritbloom**: Matches rank to injured target count (Rank 4 for 4+ injured)
- **Fire Breath**: Rank 4 for execute, Rank 2-3 for cleave/spread

### 2. Dream Flight Positioning Handler (`dream_flight_handler.lua`)

Handles the complex positioning requirements for Dream Flight, a skill-shot healing ability that requires flying through allies.

#### Key Features:

**Flight Path Calculation**
- Calculates which allies are in the 6-yard wide healing path
- Measures perpendicular distance from flight line
- Sorts allies by distance along path for healing order

**Safe Zone Detection**
- Integration with `evade_helper` for danger zone avoidance
- Tests 16 directions at multiple distances (360-degree coverage)
- Line of sight validation for landing positions
- Safety scoring based on proximity to danger

**Path Scoring Algorithm**
```
Score = (Ally Count × 100) + (Health Deficit Bonuses) + (Tank Priority) 
        - (Danger Score × 50) - (Distance × 0.5)
```

**Raid vs M+ Positioning**
- **Raid**: Identifies player clusters, attempts to connect multiple groups
- **M+**: Calculates party center, finds safest extension path

### 3. Updated Chronowarden APL (`chronowarden_v2.lua`)

Integrates both new handlers into the rotation logic.

#### Integration Points:

**Empower Handler Integration:**
```lua
-- Check if channeling empowered spell
if me:is_channeling() then
    if empower_handler.should_release() then
        me:release_empower()
    end
    return
end

-- Start empowered cast with context
local context = {
    urgency = "emergency",
    target_count = injured_count,
    avg_health_deficit = deficit,
    time_available = safe_window
}
empower_handler.start_empower(spell_id, target, context)
```

**Dream Flight Integration:**
```lua
-- Checks for opportunity (3+ injured, safe path exists)
-- Scores all possible flight paths
-- Executes highest scoring safe path
-- Integrates with echo setup (won't interrupt good setup)
```

## Usage Patterns

### Emergency Situations
1. Tip the Scales → Instant max rank Spiritbloom
2. Quick Rank 1 empowers for immediate healing
3. Dream Flight through stacked injured allies

### Raid Damage Patterns
1. Setup echoes with Temporal Anomaly
2. Rank 3-4 Dream Breath for strong HoTs
3. Dream Flight through player clusters
4. Consume echoes with Verdant Embrace combos

### Movement-Heavy Fights
1. Predictive rank reduction before movement
2. Early release of empowered spells
3. Pre-positioned Dream Flight paths
4. Quick Rank 1 casts between movements

## Configuration Options

### Empower Settings
- `emergency_release_threshold`: Health % to force early release (default: 25%)
- `movement_buffer`: Time before movement to release (default: 0.5s)
- `overheal_tolerance`: Maximum acceptable overheal % (default: 50%)

### Dream Flight Settings
- `min_targets_required`: Minimum allies in path (default: 3)
- `min_total_deficit`: Minimum combined health deficit (default: 150)
- `danger_zone_buffer`: Safety distance from dangers (default: 5 yards)

## Performance Impact

### Optimizations Included:
- Path calculations cached for 100ms
- Squared distance calculations where possible
- Early exit conditions in scoring algorithms
- Lazy evaluation of non-critical paths

### Expected Performance:
- Empower decisions: <1ms per frame
- Dream Flight path calculation: ~5-10ms (only when available)
- Overall FPS impact: Negligible (<0.5% CPU usage)

## Testing Recommendations

### Empower Testing:
1. Test rank decisions at various health thresholds
2. Verify emergency release behavior
3. Check movement prediction accuracy
4. Validate Tip the Scales interaction

### Dream Flight Testing:
1. Test in various raid positioning scenarios
2. Verify danger zone avoidance
3. Check path scoring accuracy
4. Validate cluster detection in raids

## Integration with Existing Modules

The new modules seamlessly integrate with:
- **Target Selector**: Provides injured target data for empowered decisions
- **Health Predictor**: Informs urgency calculations for rank selection
- **Stop Cast Logic**: Works alongside empower release decisions
- **Evade Helper**: Provides danger zone data for positioning

## Future Enhancements

1. **Empower Learning**: Track success rates of different ranks in situations
2. **Predictive Positioning**: Pre-position for Dream Flight before damage
3. **Combo Optimization**: Chain empowered spells with cooldowns
4. **Visual Indicators**: HUD elements showing optimal empower ranks
5. **Profile System**: Save empower preferences per encounter

## Troubleshooting

### Common Issues:

**Empowered spells releasing too early:**
- Check `emergency_release_threshold` setting
- Verify movement prediction timing
- Ensure proper urgency classification

**Dream Flight not finding paths:**
- Check minimum target requirements
- Verify safe zone calculations
- Ensure evade_helper is properly loaded

**Performance issues:**
- Reduce path calculation frequency
- Lower direction test count (16 → 8)
- Increase cache duration

## Code Examples

### Manual Empower Control:
```lua
-- Force specific rank
local context = {
    urgency = "normal",
    target_count = 3,
    avg_health_deficit = 45,
    force_rank = 3  -- Override calculation
}
empower_handler.start_empower(DREAM_BREATH, nil, context)
```

### Dream Flight Override:
```lua
-- Force cast at specific position
local target_pos = vec3(x, y, z)
if evade_helper.is_position_safe(target_pos) then
    izi_spell.cast_position(DREAM_FLIGHT.spell_id, target_pos)
end
```

## Final Notes

These modules represent a significant advancement in healing automation, moving beyond simple priority lists to intelligent, context-aware decision making. The empower system provides nuanced control over Evoker's unique mechanics, while Dream Flight positioning solves one of the most complex positioning challenges in the game.

The system is designed to be maintainable and extensible, with clear separation of concerns and comprehensive configuration options. Each module can be tested independently and integrates cleanly with the existing architecture.
