void CalculateRainPuddles(inout vec3 albedo, inout vec3 normal, inout vec3 specTex, in vec3 worldPos, in vec3 geoNormal, in float skylight) {
    vec3 minecraftPos = worldPos + cameraPosition;
    vec2 puddlePos = minecraftPos.xz - minecraftPos.y;
    puddlePos -= worldTimeCounter * vec2(0.016, 0.01);
    puddlePos *= RAIN_PUDDLE_SCALE;

    // 降低采样次数：从 3 次降为 2 次，通过调整乘数保持噪声形态
    float noise = texture(noisetex, puddlePos).z;
    noise += texture(noisetex, puddlePos * 0.3).z * 2.0;  // 去掉中间一层，调大低层权重
    noise = saturate(noise * 0.2) * wetnessCustom;

    float puddles = smoothstep(0.45, 0.55, noise);
    if (puddles < EPS) return;

    puddles *= saturate(geoNormal.y * 0.5 + 0.5);
    puddles *= saturate(skylight * 5.0 - 4.0);

    vec3 wetAlbedo = desaturate(albedo, 0.25) * 0.5;
    #if TEXTURE_FORMAT == 0
        float porosity = saturate(specTex.b * (255.0 / 64.0) - step(64.5, specTex.b * 255.0));
        puddles *= 1.0 - porosity;
        wetAlbedo *= oms(porosity * wetAlbedo);
    #endif
    albedo = mix(albedo, wetAlbedo, puddles);

    specTex.r = mix(specTex.r, RAIN_PUDDLE_SMOOTHNESS, puddles);
    specTex.g = max(specTex.g, DEFAULT_DIELECTRIC_F0 * puddles);
}