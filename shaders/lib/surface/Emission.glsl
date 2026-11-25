#if !defined INCLUDE_SURFACE_EMISSION
#define INCLUDE_SURFACE_EMISSION

float BuiltinEmission(uint materialID, vec3 rgb, vec3 localPos) {
	uint profile = materialID & MATERIAL_PROFILE_MASK;

	float peak = maxOf(rgb);
	// First dispatch on the shared high bits, then test up to four adjacent profiles.
	switch (profile >> 2u) {
		case (MAT_ACCENT >> 2u): {
			if (profile == MAT_ACCENT) return 0.4 * sqr(peak);
			if (profile == MAT_GLOW) return sqr(peak);
			if (profile == MAT_FIRE) return 4.0 * sqr(peak);
			if (profile == MAT_LAMP) return 6.0 * sqr(saturate((peak - 0.26) * 1.35));
			break;
		}
		case (MAT_WARM_FLAME >> 2u): {
			if (profile == MAT_WARM_FLAME) {
				return 8.0 * saturate((rgb.r - 0.68) * 3.2) * max(step(rgb.b + 0.12, rgb.r), step(0.94, minOf(rgb)));
			}
			if (profile == MAT_SOUL_FLAME) {
				return 6.0 * max(saturate((min(rgb.g, rgb.b) - rgb.r - 0.16) * 2.0), saturate((min(rgb.g, rgb.b) - 0.78) * 4.5));
			}
			if (profile == MAT_COPPER_FLAME) {
				// Oxidized copper leans toward cyan. The flame has nearly equal red and blue.
				return 6.0 * max(saturate((rgb.g - 0.4) * 2.5) * step(abs(rgb.r - rgb.b), 0.04), step(0.91, minOf(rgb)));
			}
			if (profile == MAT_REDSTONE) {
				// Pink highlights have matching green and blue. Gold rail trim does not.
				float pink = step(0.96, rgb.r) * step(abs(rgb.g - rgb.b), 0.04) * step(rgb.g + 0.10, rgb.r);
				return 3.0 * max(pink, saturate((rgb.r - 1.4 * max(rgb.g, rgb.b) - 0.10) * 2.2));
			}
			break;
		}
		case (MAT_WIRE >> 2u): {
			if (profile == MAT_WIRE) return 2.0 * sqr(rgb.r) * step(max(rgb.g, rgb.b) + 0.09, rgb.r);
			if (profile == MAT_BERRIES) {
				return 5.0 * sqr(rgb.r) * step(0.60, rgb.r) * step(rgb.g + 0.04, rgb.r) * step(rgb.b + 0.12, rgb.g);
			}
			if (profile == MAT_VIOLET) return 2.5 * saturate((min(rgb.b, rgb.r) - rgb.g - 0.045) * 3.5);
			if (profile == MAT_AMETHYST) return 2.0 * sqr(saturate((peak - 0.40) * 1.65));
			break;
		}
		case (MAT_SCULK >> 2u): {
			if (profile == MAT_SCULK) return 0.65 * saturate((min(rgb.g, rgb.b) - rgb.r - 0.12) * 2.4);
			if (profile == MAT_LICHEN) return 0.3 + 1.8 * saturate((rgb.r - 0.49) * 4.0);
			if (profile == MAT_BEACON) {
				// Vanilla core spans x/z 3..13, y 3..14. Exclude the shell and obsidian base.
				return 5.0 * sqr(peak) * step(maxOf(abs(localPos.xz - 0.5)), 0.318)
					* step(0.182, localPos.y) * step(localPos.y, 0.88) * step(0.45, rgb.g);
			}
			if (profile == MAT_BREWING_STAND) {
				vec2 p = abs(localPos.xz - 0.5);
				return 0.65 * sqr(rgb.r) * step(maxOf(p), 0.067) * step(rgb.b + 0.15, rgb.r);
			}
			break;
		}
		case (MAT_CANDLE >> 2u): {
			if (profile == MAT_CANDLE) return 1.0 + 3.0 * sqr(peak);
			if (profile == MAT_CANDLE_CAKE) {
				// The cake top is at 8/16. Only the candle rises above it.
				return localPos.y > 0.5001 ? 1.0 + 3.0 * sqr(peak) : 0.0;
			}
			if (profile == MAT_LAVA_CAULDRON) return 5.0 * sqr(rgb.r) * step(rgb.b + 0.2, rgb.r);
			if (profile == MAT_PUMPKIN) return 5.0 * saturate((rgb.g - 0.69) * 4.0);
			break;
		}
		case (MAT_END_ROD >> 2u): {
			if (profile == MAT_END_ROD) return 4.0 * saturate((rgb.r - 0.72) * 4.0);
			if (profile == MAT_SEA_PICKLE) return 4.0 * saturate((min(rgb.g, rgb.b) - 0.47) * 3.0);
			if (profile == MAT_PORTAL_FRAME) return 0.6 * sqr(rgb.g) * step(rgb.r + 0.035, rgb.g);
			if (profile == MAT_ENCHANTING_TABLE) {
				return 2.0 * saturate((min(rgb.g, rgb.b) - rgb.r + 0.05) * 2.5) * step(0.58, rgb.g);
			}
			break;
		}
		case (MAT_FUNGUS >> 2u): {
			if (profile == MAT_FUNGUS) return 0.65 * sqr(saturate((peak - 0.35) * 1.8));
			if (profile == MAT_FIREFLY) {
				// Even the dimmest animation frame is less yellow than the foliage sprite.
				return 4.0 * sqr(peak) * step(0.62 * rgb.r, rgb.b);
			}
			if (profile == MAT_COPPER_BULB) {
				float pane = step(0.17, rgb.g - rgb.b) * step(rgb.g + 0.015, rgb.r);
				float indicator = saturate((rgb.r - 2.0 * rgb.g - 0.12) * 3.0);
				return 5.0 * sqr(rgb.g) * max(pane, step(0.80, minOf(rgb))) + 1.8 * indicator;
			}
			if (profile == MAT_TRIAL) {
				return 3.0 * max(saturate((rgb.r - rgb.b - 0.26) * 2.0), saturate((min(rgb.g, rgb.b) - rgb.r - 0.22) * 2.5));
			}
			break;
		}
		case (MAT_TRIAL_DIM >> 2u): {
			if (profile == MAT_TRIAL_DIM) return 0.35 * sqr(peak) * step(rgb.r + 0.015, rgb.b);
			if (profile == MAT_ANCHOR) {
				return 3.0 * max(saturate((rgb.b - rgb.g - 0.12) * 2.0), saturate((rgb.r - rgb.b - 0.24) * 2.0));
			}
			if (profile == MAT_END_PORTAL) {
				return 8.0 * peak;
			}
			if (profile == MAT_NETHER_PORTAL) {
                return 2.0 * peak;
            }
			break;
		}
		case (MAT_CONDUIT >> 2u): {
			if (profile == MAT_CONDUIT) {
				return 0.35 * sqr(peak) + 2.5 * saturate((min(rgb.g, rgb.b) - rgb.r - 0.08) * 2.5);
			}
			if (profile == MAT_LIGHTNING) {
				return 8.0;
			}
			if (profile == MAT_MAGMA) return 4.0 * saturate((rgb.r - rgb.b - 0.38) * 2.5);
			if (profile == MAT_STEM) return 0.6 * saturate((max(rgb.r, rgb.g) - min(rgb.r, rgb.g) - 0.25) * 3.0);
			break;
		}
		case (MAT_END_CRYSTAL >> 2u): {
			if (profile == MAT_END_CRYSTAL) return 4.0 * sqr(rgb.b) * step(rgb.g + 0.06, rgb.b);
			if (profile == MAT_SCULK_ACTIVE) return 2.4 * saturate((min(rgb.g, rgb.b) - rgb.r - 0.12) * 2.4);
			if (profile == MAT_COPPER_INDICATOR) return 1.8 * saturate((rgb.r - 2.0 * rgb.g - 0.12) * 3.0);
			if (profile == MAT_CHARGED_EYES) return 2.0 * sqr(saturate((peak - 0.52) * 2.1));
			break;
		}
		case (MAT_GUARDIAN >> 2u): {
			if (profile == MAT_GUARDIAN) return 3.0 * sqr(peak);
			if (profile == MAT_CHARGED_CREEPER) return 2.5 * saturate((rgb.b - max(rgb.r, rgb.g) - 0.045) * 3.0);
			if (profile == MAT_GLOW_SQUID) return 2.0 * sqr(saturate((peak - 0.52) * 2.1));
			break;
		}
		case (MAT_CAMPFIRE >> 2u): {
			if (profile == MAT_CAMPFIRE) {
				// Char and wood stay below both thresholds. Embers range from dark red to pale yellow.
				float ember = saturate(max((rgb.r - 1.31 * rgb.g) * 45.0, (rgb.r - 0.78) * 22.0));
				return 6.0 * sqr(peak) * ember;
			}
			if (profile == MAT_REDSTONE_TORCH) {
				return 3.0 * sqr(rgb.r) * max(step(0.92, rgb.r), step(1.60 * max(rgb.g, rgb.b) + 0.32, rgb.r));
			}
			if (profile == MAT_DETECTOR_RAIL) {
				return 3.0 * sqr(rgb.r) * saturate((rgb.r - rgb.g) * 2.5) * step(abs(rgb.g - rgb.b), 0.02);
			}
			if (profile == MAT_DIODE) {
				float trace = saturate((rgb.r - 1.4 * max(rgb.g, rgb.b) - 0.10) * 2.2);
				float torchHead = step(0.13, localPos.y) * step(0.92, rgb.r);
				return 3.0 * max(trace * step(0.52, rgb.r), torchHead);
			}
			break;
		}
	}
	return 0.0;
}

// The low byte of colortex7.g is always the display ID. The upper byte holds
// square-root encoded intrinsic emission, independently of the LabPBR channels.
uint WriteBuiltinMaterial(uint id, vec3 rgb, vec3 localPos) {
	#if EMISSIVE_MODE < 2
		if ((id & MATERIAL_PROFILE_MASK) >= MAT_ACCENT) {
			float emission = BuiltinEmission(id, rgb, localPos);
			float encoded = sqrt(saturate(emission * rcp(MATERIAL_EMISSION_MAX)));
			return id | (uint(encoded * 255.0 + 0.5) << 8u);
		}
	#endif
	return id;
}

#endif
