# Preservation Evoker - Modular Healing Rotation

## Overview

A sophisticated, modular healing rotation for World of Warcraft Preservation Evoker using the IZI SDK framework. This implementation showcases modern software engineering principles with a clean, maintainable architecture.

## Features

### Core Systems
- **Smart Target Selection**: Priority-based healing target selection with role weighting
- **Health Prediction**: Advanced health forecasting using damage patterns and incoming damage
- **Healing Calculator**: Sophisticated healing calculations with mastery, versatility, and crit
- **Essence Management**: Intelligent resource pooling and spending optimization
- **Stop Cast**: Smart cast interruption for overheal prevention and emergency responses
- **Empower Handler**: Dynamic rank calculation and optimal release timing
- **Dream Flight**: Complex positioning system with path optimization

### Hero Specialization Support
- ✅ **Chronowarden** (Fully Implemented)
  - Echo setup and consumption mechanics
  - Temporal magic synergies
  - Intelligent cooldown management
  - Emergency response system

- 📝 **Flameshaper** (Planned)
  - Documented in `chronowarden_v2.md`
  - Ready for implementation

## Architecture

### Modular Design

```
preservation_evoker/
├── main.lua                    # Main controller
├── spells.lua                  # Spell definitions
├── menu.lua                    # UI configuration
├── modules/                    # Core healing modules
│   ├── target_selector.lua     # Smart target selection
│   ├── health_predictor.lua    # Health prediction system
│   ├── healing_calculator.lua  # Healing calculations
│   ├── essence_manager.lua     # Resource management
│   ├── stop_cast.lua          # Cast interruption logic
│   ├── empower_handler.lua    # Empowered spell mechanics
│   └── dream_flight_handler.lua# Positioning system
└── apl/                       # Action Priority Lists
    └── chronowarden.lua       # Chronowarden rotation
```

### Module Responsibilities

#### Target Selector (`target_selector.lua`)
- Evaluates targets based on priority scoring
- Considers health deficit, incoming damage, role priority, and positioning
- Provides best single target and AoE target selection
- Tank-specific targeting and group analysis

#### Health Predictor (`health_predictor.lua`)
- Tracks damage history for pattern detection
- Predicts health states 2-3 seconds ahead
- Detects spike damage and burst patterns
- Estimates incoming healing from HoTs

#### Healing Calculator (`healing_calculator.lua`)
- Calculates effective healing needed per target
- Accounts for mastery (Life-Binder) bonuses
- Estimates spell healing amounts with stat multipliers
- Predicts overheal for efficiency optimization

#### Essence Manager (`essence_manager.lua`)
- Tracks and predicts essence generation
- Determines optimal spending priorities
- Manages resource pooling for upcoming damage
- Validates spell costs before casting

#### Stop Cast (`stop_cast.lua`)
- Tracks current cast information
- Decides when to interrupt for better opportunities
- Calculates optimal empower ranks based on need
- Handles emergency interruptions

#### Empower Handler (`empower_handler.lua`)
- Manages Evoker's unique empowered spell mechanics
- Dynamically calculates optimal ranks based on context
- Handles release timing with movement prediction
- Integrates with emergency response system

#### Dream Flight Handler (`dream_flight_handler.lua`)
- Calculates flight paths and healing targets
- Scores paths based on efficiency
- Finds safe landing positions
- Optimizes for raid clustering

## Usage

### Installation

1. Place the `preservation_evoker` folder in your IZI SDK scripts directory
2. Load the script through the IZI SDK interface
3. Configure settings through the in-game menu

### Configuration

Access the configuration menu through the IZI SDK main menu:

**Preservation Evoker (Chronowarden)**
- Enable/disable the rotation
- Configure keybinds
- Set defensive thresholds
- Customize cooldown usage
- Adjust healing priorities
- Fine-tune empowered spell behavior

### Key Settings

#### Defensives
- **Obsidian Scales**: Health thresholds for damage reduction
- **Renewing Blaze**: Emergency self-heal activation points

#### Cooldowns
- **Dream Flight**: Minimum injured count and health percentage
- **Rewind**: Minimum injured allies for activation
- **Temporal Anomaly**: Echo setup triggers

#### Healing
- **Emergency HP %**: Threshold for emergency healing (default: 30%)
- **Maintenance HP %**: Proactive healing threshold (default: 85%)

#### Empowered Spells
- **Prefer Speed**: Use lower ranks for faster casts
- **Minimum Rank**: Enforce minimum empower rank (1-4)

## Rotation Logic

### Priority System

1. **Dream Flight Check**: Evaluate positioning opportunities
2. **Emergency Healing**: Handle critical situations (< 30% HP)
   - Rewind for multiple low targets
   - Tip the Scales for instant max rank
   - Verdant Embrace for instant healing
   - Emergency Spiritbloom

3. **Echo Setup**: Apply echoes to party members
   - Temporal Anomaly for free echoes
   - Manual echo application

4. **Echo Consumption**: Use healing spells to trigger echoes
   - Verdant Embrace + Emerald Communion combo
   - Empowered Spiritbloom for burst
   - Empowered Dream Breath for HoTs

5. **Maintenance**: Proactive healing
   - Keep Reversion on tanks
   - Chrono Flame with Essence Burst
   - Time Dilation for tank protection

6. **DPS**: Filler when no healing needed
   - Fire Breath for Leaping Flames
   - Living Flame spam

## Performance Considerations

### Optimizations
- Values cached per game tick (ping, GCD, essence)
- Efficient distance calculations (squared distances when possible)
- Minimal API calls through smart caching
- Module updates only when needed

### Best Practices
- Uses izi_sdk methods wherever possible
- Falls back to raw API only when necessary
- Proper separation of concerns
- Clear module interfaces

## Known Limitations

1. **Empower Release**: The exact API method for releasing empower at specific ranks needs SDK confirmation
2. **Evade Helper**: Not yet integrated for danger zone detection in Dream Flight
3. **Debuff Database**: Dangerous debuff IDs need per-encounter population
4. **Movement Prediction**: Not yet integrated with evade_helper for movement-aware empowering

## Future Enhancements

- [ ] Flameshaper APL implementation
- [ ] Evade helper integration
- [ ] Encounter-specific debuff tracking
- [ ] Advanced movement prediction
- [ ] Stasis optimization logic
- [ ] Mythic+ vs Raid mode switching
- [ ] Advanced echo tracking and consumption optimization

## Development Notes

This implementation follows the design specifications from:
- `implementation.md` / `preservation_evoker_implementation.md`
- `advanced_features_summary.md`
- `empower_handler.md`
- `dream_flight_handler.md`
- `chronowarden_v2.md`

All modules are fully compliant with the izi_sdk framework and use the underlying API only when the SDK doesn't provide the required functionality.

## Contributing

This is a school project demonstrating modular architecture principles. When extending:

1. Maintain module separation
2. Follow existing naming conventions
3. Use izi_sdk methods first, raw API second
4. Document complex logic with comments
5. Update this README with changes

## Credits

- **Architecture**: Based on comprehensive design documentation
- **Framework**: IZI SDK for World of Warcraft
- **Inspiration**: Death Knight flat rotation example

---

**Status**: ✅ Fully Implemented and Ready for Testing

**Last Updated**: 2025-11-13
