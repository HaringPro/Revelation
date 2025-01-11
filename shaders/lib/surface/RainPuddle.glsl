
void CalculateRainPuddles(inout vec3 albedo, inout vec3 normal, inout vec3 specTex, in vec3 worldPos, in vec3 flatNormal, in float skylight) {
    vec3 minecraftPos = worldPos + cameraPosition;
    vec2 puddlePos = minecraftPos.xz - minecraftPos.y;
	puddlePos -= worldTimeCounter * vec2(0.016, 0.01);
	puddlePos *= RAIN_PUDDLE_SCALE;

    // Puddle noise
	float noise = texture(noisetex, puddlePos * 0.75).z * 0.8;
	noise += textureBicubic(noisetex, puddlePos * 0.45).x * 1.6;
	noise += textureBicubic(noisetex, puddlePos * 0.15).y * 2.6;
	noise = saturate(noise * 0.2) * wetnessCustom;

    // Normal falloff
    noise *= saturate(flatNormal.y * 0.3 + 0.7);
    // Skylight falloff
    noise *= saturate(skylight * 4.0 - 3.0);

    float puddles = sqr(remap(0.22, 0.51, noise));
    if (puddles < 1e-5) return;

    // Apply wetness to albedo
    vec3 wetAlbedo = colorSaturation(albedo, 0.7) * 0.75;
    #if TEXTURE_FORMAT == 0
        // https://shaderlabs.org/wiki/LabPBR_Material_Standard
        float porosity = saturate(specTex.b * (255.0 / 64.0) - step(64.5, specTex.b * 255.0));

        puddles *= 1.0 - porosity;
        wetAlbedo *= oneMinus(porosity * wetAlbedo);
    #endif
    albedo = mix(albedo, wetAlbedo, puddles);

    // Apply wetness to normal
    // TODO: Add ripple normal
    vec3 rippleNormal = vec3(0.0, 1.0, 0.0);
    normal = normalize(mix(normal, rippleNormal, puddles));

    // Apply wetness to specular
    specTex.r = mix(specTex.r, RAIN_PUDDLE_SMOOTHNESS, puddles);
    specTex.g = max(specTex.g, 0.04 * puddles);
}