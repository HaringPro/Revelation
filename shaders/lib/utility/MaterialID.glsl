// Display material shared by the raster passes. Properties use 10000 + display ID.
#if !defined INCLUDE_LIB_UTILITY_MATERIAL_ID
#define INCLUDE_LIB_UTILITY_MATERIAL_ID

#define MATERIAL_PROPERTY_BASE 10000
#define PHYSICS_SNOW_ENTITY_ID 829925

#define MATERIAL_ID_MASK 255u
#define MATERIAL_EMISSION_MAX 8.0
#define MATERIAL_PROFILE_MASK 63u
#define MATERIAL_SSS_BASE 64u
#define MATERIAL_FOLIAGE_BASE 128u
#define MATERIAL_ROOTED_BASE 192u

#define MAT_SKY 0u
#define MAT_SOLID 1u
#define MAT_GLASS 2u
#define MAT_WATER 3u
#define MAT_TRANSLUCENT_PARTICLE 4u

#define MAT_ACCENT 16u
#define MAT_GLOW 17u
#define MAT_FIRE 18u
#define MAT_LAMP 19u
#define MAT_WARM_FLAME 20u
#define MAT_SOUL_FLAME 21u
#define MAT_COPPER_FLAME 22u
#define MAT_REDSTONE 23u
#define MAT_WIRE 24u
#define MAT_BERRIES 25u
#define MAT_VIOLET 26u
#define MAT_AMETHYST 27u
#define MAT_SCULK 28u
#define MAT_LICHEN 29u
#define MAT_BEACON 30u
#define MAT_BREWING_STAND 31u
#define MAT_CANDLE 32u
#define MAT_CANDLE_CAKE 33u
#define MAT_LAVA_CAULDRON 34u
#define MAT_PUMPKIN 35u
#define MAT_END_ROD 36u
#define MAT_SEA_PICKLE 37u
#define MAT_PORTAL_FRAME 38u
#define MAT_ENCHANTING_TABLE 39u
#define MAT_FUNGUS 40u
#define MAT_FIREFLY 41u
#define MAT_COPPER_BULB 42u
#define MAT_TRIAL 43u
#define MAT_TRIAL_DIM 44u
#define MAT_ANCHOR 45u
#define MAT_END_PORTAL 46u
#define MAT_NETHER_PORTAL 47u
#define MAT_CONDUIT 48u
#define MAT_LIGHTNING 49u
#define MAT_MAGMA 50u
#define MAT_STEM 51u
#define MAT_END_CRYSTAL 52u
#define MAT_SCULK_ACTIVE 53u
#define MAT_COPPER_INDICATOR 54u
#define MAT_CHARGED_EYES 55u
#define MAT_GUARDIAN 56u
#define MAT_CHARGED_CREEPER 57u
#define MAT_GLOW_SQUID 58u
#define MAT_SIGN 59u
#define MAT_CAMPFIRE 60u
#define MAT_REDSTONE_TORCH 61u
#define MAT_DETECTOR_RAIL 62u
#define MAT_DIODE 63u

// Bits 6..7 classify material behavior. The low six bits of emissive variants
// are identical across banks (e.g. 25, 153 and 217 use the same orange mask).
#define MAT_WEAK_SSS 65u
#define MAT_STRONG_SSS 66u
#define MAT_PARTICLE 67u
#define MAT_STATIC_PLANT 129u
#define MAT_LEAVES 130u
#define MAT_SHORT_PLANT 193u
#define MAT_TALL_LOWER 194u
#define MAT_TALL_UPPER 195u

uint DecodeMaterialID(int propertyID) {
	uint id = uint(propertyID) - uint(MATERIAL_PROPERTY_BASE);
	return id != MAT_SKY && id <= MATERIAL_ID_MASK ? id : MAT_SOLID;
}

#endif
