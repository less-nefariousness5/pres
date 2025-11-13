--[[
    Preservation Evoker Spellbook for IZI SDK

    Complete spellbook with all Preservation Evoker abilities organized by category.
    Each spell is defined with its spell ID(s) for easy reference throughout the rotation.

    Categories:
    - Core healing abilities
    - Empowered spells
    - Cooldowns and defensives
    - Damage abilities
    - Buffs and utility

    Author: Modular Healing System
]]

local izi = require("common/izi_sdk")
local enums = require("common/enums")
local spell = izi.spell
local BUFFS = enums.buff_db

---@class preservation_evoker_spells
local SPELLS = {
    -- Core Heals
    ECHO = spell(364343),
    REVERSION = spell(366155),
    LIVING_FLAME = spell(361469),
    VERDANT_EMBRACE = spell(360995),
    EMERALD_BLOSSOM = spell(355913),

    -- Empowered Spells (Healing)
    DREAM_BREATH = spell(355941),
    SPIRITBLOOM = spell(367364),

    -- Empowered Spells (Damage)
    FIRE_BREATH = spell(357208),

    -- Major Cooldowns
    TEMPORAL_ANOMALY = spell(373861),      -- Chronowarden: Free echoes
    TIP_THE_SCALES = spell(370553),        -- Instant max rank empower
    STASIS = spell(370537),                -- Store 3 spells
    REWIND = spell(363534),                -- Recast last 3 spells
    TIME_DILATION = spell(357170),         -- Extend HoTs on target
    EMERALD_COMMUNION = spell(370960),     -- AoE heal while hovering
    DREAM_FLIGHT = spell(358267),          -- Flight path healing

    -- Flameshaper Abilities
    ENGULF = spell(382614),                -- Flameshaper heal
    RENEWING_BLAZE = spell(374348),        -- Becomes Lifecinders (external)

    -- Damage
    DISINTEGRATE = spell(356995),
    AZURE_STRIKE = spell(362969),

    -- Defensives
    OBSIDIAN_SCALES = spell(363916),
    RENEWING_BLAZE_SELF = spell(374348),

    -- Utility
    RESCUE = spell(370665),
    HOVER = spell(358267),
    DEEP_BREATH = spell(357210),

    -- Movement
    BLESSING_OF_THE_BRONZE = spell(364342),

    -- Passives (Talent tracking)
    CALL_OF_YSERA = spell(373835),         -- Verdant Embrace bonus
    CYCLE_OF_LIFE = spell(371832),         -- Echo mechanics
    ESSENCE_ATTUNEMENT = spell(375350),    -- Essence regen
    DREAM_PROJECTION = spell(377509),      -- Dream Breath range
}

-- Track buffs for rotation logic
SPELLS.BUFFS = {
    ECHO = 364343,
    ESSENCE_BURST = 369256,
    TEMPORAL_COMPRESSION = 431462,         -- Chronowarden buff
    CHRONO_FLAME = 431442,                 -- Chronowarden Living Flame
    CONSUME_FLAME = 431869,                -- Flameshaper mechanic
    INNER_FLAME = 431872,                  -- Tier set bonus
    VERDANT_EMBRACE_BUFF = 360995,         -- Verdant Embrace active
    LIFEBIND = 373267,                     -- Echo healing
    REVERSION_HOT = 366155,
    DREAM_BREATH_HOT = 355941,
    TIP_THE_SCALES = 370553,
    STASIS = 370537,
    LEAPING_FLAMES = 370901,
}

-- Track debuffs that can be applied
SPELLS.DEBUFFS = {
    FIRE_BREATH_DOT = 357208,
}

return SPELLS
