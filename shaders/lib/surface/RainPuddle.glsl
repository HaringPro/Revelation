// https://www.shadertoy.com/view/ldfyzl

#define RIPPLE_MAX_RADIUS 1 // [1 2 3]
#define RIPPLE_SCALE 4.0 // [1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0]
#define RIPPLE_INTENSITY 0.2 // [0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5]

vec2 RippleSlope(vec2 uv, float time) {
    vec2 p0 = floor(uv);

    vec2 circles = vec2(0.0);
    for (int j = -RIPPLE_MAX_RADIUS; j <= RIPPLE_MAX_RADIUS; ++j) {
        for (int i = -RIPPLE_MAX_RADIUS; i <= RIPPLE_MAX_RADIUS; ++i) {
			vec2 pi = p0 + vec2(i, j);
            vec2 p = pi + hash22(pi);

            float t = fract(time + hash12(pi));
            vec2 v = p - uv;
            float lenV = length(v);
            float d = lenV - float(RIPPLE_MAX_RADIUS + 1) * t;

            const float h = 1e-3;
            vec2 d12 = vec2(d - h, d + h);
            vec2 p12 = sin(32.0 * d12) * smoothstep(0.3, 0.0, abs(d12 + 0.3));
            circles += v * ((p12.x - p12.y) / (lenV * h) * sqr(1.0 - t));
        }
    }
    circles *= RIPPLE_INTENSITY / float((RIPPLE_MAX_RADIUS * 2 + 1) * (RIPPLE_MAX_RADIUS * 2 + 1));

    return circles;
}

void ApplyRainPuddleMaterial(inout vec3 albedo, inout vec3 specTex, vec3 worldPos, inout vec3 normal, vec3 geoNormal, float skylight) {
	vec3 minecraftPos = worldPos + cameraPosition;
	vec2 puddlePos = minecraftPos.xz - minecraftPos.y * 0.1;
	puddlePos -= worldTimeCounter * vec2(0.016, 0.01);
	puddlePos *= RAIN_PUDDLE_SCALE;

	// Puddle noise
	float noise = texture(noisetex, puddlePos).z;
	noise += texture(noisetex, puddlePos * 0.7).z;
	noise += texture(noisetex, puddlePos * 0.3).z * 2.0;
	noise = saturate(noise * 0.2) * wetnessCustom;

	float puddles = smoothstep(0.4, 0.6, noise);

	// Normal falloff
	puddles *= saturate(geoNormal.y * 0.5 + 0.5);
	// Skylight falloff
	puddles *= saturate(skylight * 5.0 - 4.0);

	if (puddles < EPS) return;

	#if defined MC_SPECULAR_MAP && TEXTURE_FORMAT == 0
		// https://shaderlabs.org/wiki/LabPBR_Material_Standard
		float porosity = saturate(specTex.b * (255.0 / 64.0) - step(64.5, specTex.b * 255.0));
	#else
		const float porosity = 0.25;
	#endif

	// Apply wetness to albedo
	float darkness = puddles * porosity * 0.5;
	albedo = pow(albedo, vec3(1.0 + darkness)) * saturate(1.0 - darkness);

	// Apply wetness to normal
    vec2 rippleSlope = RippleSlope(minecraftPos.xz * RIPPLE_SCALE, frameTimeCounter);
    rippleSlope *= saturate(4.0 * abs(dot(geoNormal, worldPos) * inversesqrt(sdot(worldPos))));
    vec3 rippleNormal = vec3(rippleSlope * noise * rainStrength, 4.0).xzy;
    normal = normalize(normal + rippleNormal * puddles);

	// Apply wetness to specular
	specTex.r = mix(specTex.r, RAIN_PUDDLE_SMOOTHNESS, puddles);
	// specTex.g = mix(specTex.g, 0.02, puddles);
}
