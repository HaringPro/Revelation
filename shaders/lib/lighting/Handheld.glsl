#if !defined INCLUDE_LIB_LIGHTING_HANDHELD
#define INCLUDE_LIB_LIGHTING_HANDHELD

uniform bool isRightHanded;
uniform bool firstPersonCamera;
uniform vec3 relativeEyePosition;
uniform vec3 playerBodyVector;

// item.properties assigns color within each 16-ID bank and emitter size by bank.
vec4 HandheldEmitter(int itemId) {
	// Preconverted from the indicated sRGB values to the working linear Rec.2020 space.
	const vec3 colors[10] = vec3[10](
		vec3(0.805575, 0.551119, 0.187721), // Flame (1.00, 0.75, 0.41)
		vec3(0.288143, 0.571685, 0.949911), // Soul flame (0.30, 0.80, 1.00)
		vec3(0.636837, 0.094165, 0.027735), // Redstone (1.00, 0.18, 0.10)
		vec3(0.705592, 0.966845, 0.893883), // Aquatic (0.76, 1.00, 0.95)
		vec3(0.900043, 0.796605, 0.360608), // Golden (1.00, 0.90, 0.59)
		vec3(0.429574, 0.183986, 0.917339), // Violet (0.76, 0.42, 1.00)
		vec3(0.613522, 0.953994, 0.522075), // Verdant (0.68, 1.00, 0.72)
		vec3(0.915297, 0.768106, 0.937596), // Pearlescent (1.00, 0.88, 0.98)
		vec3(0.693045, 0.249539, 0.055570), // Ember (1.00, 0.48, 0.17)
		vec3(0.403693, 0.931108, 0.543506)  // Copper flame (0.32, 1.00, 0.74)
	);
	const float radii[3] = float[3](0.055, 0.105, 0.18);
	int profile = itemId - 20000;
	int colorId = (profile & 15) - 1;
	if (profile < 0 || profile >= 48 || colorId < 0 || colorId >= 10) return vec4(blocklightColor, 0.09);
	return vec4(colors[colorId], radii[profile >> 4]);
}

vec3 HandheldViewPosition(bool mainHand, float radius) {
	float side = mainHand == isRightHanded ? 1.0 : -1.0;
	if (firstPersonCamera) {
		vec3 pos = vec3(side * 0.25, -0.2, -0.3);
		// Pull the light in front of a nearby wall along the eye-to-light ray.
		vec2 uv = ViewToScreenPos(pos).xy;
		if (saturate(uv) == uv) {
			float wallZ = ScreenToViewDepth(loadDepth2(uvToTexelScaled(uv)));
			pos *= saturate((wallZ + radius) / pos.z);
		}
		return pos;
	}

	vec2 forward = playerBodyVector.xz;
	forward = sdot(forward) > EPS ? normalize(forward) : vec2(0.0, 1.0);
	vec2 offset = 0.18 * forward + side * 0.36 * vec2(-forward.y, forward.x);
	return transMAD(gbufferModelView, vec3(offset.x, -0.68, offset.y) - relativeEyePosition);
}

#ifdef HANDHELD_SHADOWS
float HandheldVisibility(vec3 viewPos, vec3 geoN, vec3 L, float lightDist, float radius, float dither) {
	vec3 start = viewPos + geoN * min(-viewPos.z * scaledTexelSize.y * (2.0 - dot(geoN, L)), 0.05);
	float reach = min(lightDist - radius, 4.0);

	if (L.z > EPS) reach = min(reach, (-near - start.z) / L.z);
	if (start.z >= -near || reach < EPS) return 1.0;

	vec3 end = start + L * reach;
	vec3 origin = ViewToScreenPos(start);
	vec3 delta = ViewToScreenPos(end) - origin;

	float prevT = 0.0;
	for (uint i = 0u; i < 12u; ++i) {
		float t = sqr((float(i) + dither) * rcp(12.0));
		float mid = 0.5 * (prevT + t);
		vec2 uv = origin.xy + delta.xy * mid;
		if (saturate(uv) != uv) break;

		vec2 interval = origin.z + delta.z * vec2(prevT, t);
		float depth = loadDepth2(uvToTexelScaled(uv));

		// Intersect the whole depth interval with a thin slab behind the visible surface.
		if (depth < maxOf(interval) && ViewToScreenDepth(ScreenToViewDepth(depth) - 0.1) > minOf(interval)) {
			float travel = reach * mid * start.z / mix(end.z, start.z, mid);
			return smoothstep(2.0, 4.0, travel);
		}
		prevT = t;
	}
	return 1.0;
}
#endif

// All geometric inputs use view space.
void HandheldLighting(
    vec3 viewPos, vec3 geoNormal, vec3 normal, vec3 V,
    vec3 albedo, float roughness, vec3 f0, float dither,
    inout vec3 diffuse, inout vec3 specular
) {
	if (heldBlockLightValue + heldBlockLightValue2 == 0) return;

	vec3 eye = firstPersonCamera ? vec3(0.0) : transMAD(gbufferModelView, -relativeEyePosition);
	if (sdot(viewPos - eye) >= sqr(float(max(heldBlockLightValue, heldBlockLightValue2)) + 3.0)) return;

	float NdotV = saturate(dot(normal, V));
	for (uint hand = 0u; hand < 2u; ++hand) {
		bool mainHand = hand == 0u;
		int level = mainHand ? heldBlockLightValue : heldBlockLightValue2;
		if (level <= 0) continue;

		vec4 emitter = HandheldEmitter(mainHand ? heldItemId : heldItemId2);
		vec3 lightPos = HandheldViewPosition(mainHand, emitter.a);
		vec3 toLight = lightPos - viewPos;
		float dist2 = sdot(toLight);
		float rangeRatio2 = dist2 / sqr(float(level) + 2.0);
		if (rangeRatio2 >= 1.0 || dist2 < EPS) continue;

		float invDist = inversesqrt(dist2);
		vec3 L = toLight * invDist;
		float NdotL = saturate(dot(normal, L));
		if (NdotL < EPS) continue;

		float falloff = sqr(1.0 - sqr(rangeRatio2)) / (1.0 + dist2);
		#ifdef HANDHELD_SHADOWS
			falloff *= HandheldVisibility(viewPos, geoNormal, L, dist2 * invDist, emitter.a, fract(dither + float(hand) * 0.5));
		#endif
		vec3 radiance = emitter.rgb * (PI * HELD_LIGHT_BRIGHTNESS * float(level) * falloff * NdotL);

		vec3 H = normalize(L + V);
		float NdotH = saturate(dot(normal, H));
		float VdotH = saturate(dot(V, H));

		diffuse += radiance * DiffuseHammon(NdotV, NdotL, VdotH, NdotH, roughness, albedo);
		specular += radiance * SpecularGGX(VdotH, NdotV, NdotL, NdotH, roughness, f0);
	}
}

#endif // INCLUDE_LIB_LIGHTING_HANDHELD
