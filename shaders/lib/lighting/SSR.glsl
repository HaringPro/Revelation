#include "/lib/lighting/SSRT.glsl"
#ifdef SSRT_HIZ
#include "/lib/lighting/SSRT_HiZ.glsl"
#endif
#include "/lib/universal/MonteCarlo.glsl"

vec4 CalculateSpecularReflections(Material material, vec3 worldNormal, vec3 screenPos, vec3 worldDir, vec3 viewPos, float skylight, float dither) {
    viewPos += mat3(gbufferModelView) * worldNormal * saturate(length(viewPos) * 3e-4);

    vec3 halfway = worldNormal;
#ifdef ROUGH_REFLECTIONS
    if (!material.mirrorMask) {
        mat3 tbnMatrix = BuildOrthonormalBasis(worldNormal);
        vec2 noise = SampleStbnVec2(ivec2(gl_FragCoord.xy), frameCounter + 3);
        halfway = tbnMatrix * SampleVisibleGGX(-worldDir * tbnMatrix, material.roughness, noise);
    }
#endif
    vec3 lightDir = reflect(worldDir, halfway);

    float NdotV = abs(dot(worldNormal, worldDir));
    float NdotL = dot(worldNormal, lightDir);
    if (NdotL < EPS) return vec4(0.0);

    vec4 reflection = vec4(0.0, 0.0, 0.0, FP16_MAX);
    if (skylight > EPS && isEyeInWater == 0) {
        vec3 skyRadiance = textureBicubic(skyEnvMapTex, saturate(ProjectCubemap(lightDir, 96.0))).rgb;
        reflection.rgb = skyRadiance * smoothstep(0.3, 0.7, skylight);
    }

    // Step count optimization: NdotV-based heuristic
    float stepFactor = 1.0 - NdotV * 0.5;
    float distFactor = saturate(length(viewPos) * 0.02);
    uint stepCount = uint(SSRT_MAX_SAMPLES * oms(material.roughness * 0.75) * stepFactor * mix(1.0, 0.5, distFactor));
    stepCount = max(stepCount, 4u);

    // Mipmap rough tracing: fewer steps for rough surfaces
#ifdef SSRT_MIPMAP_ROUGH
    float traceScale = mix(1.0, 0.5, saturate(material.roughness * 2.0));
    if (!material.mirrorMask) {
        stepCount = uint(float(stepCount) * traceScale);
        stepCount = max(stepCount, 4u);
    }
#endif

    vec3 traceScreenPos = screenPos;
    bool hit = false;

#ifdef SSRT_HIZ
    hit = HiZRaytrace(viewPos, mat3(gbufferModelView) * lightDir, dither, stepCount, traceScreenPos);
#endif

    if (!hit) {
        hit = ScreenSpaceRaytrace(viewPos, mat3(gbufferModelView) * lightDir, dither, stepCount, traceScreenPos);
    }

    if (hit) {
        // Edge fade with adjustable strength
        float edgeFade = traceScreenPos.x * traceScreenPos.y * oms(traceScreenPos.x) * oms(traceScreenPos.y);
        float fadeStrength = 1e2 + cube(saturate(1.0 - gbufferModelViewInverse[2].y)) * (0.5e3 * SSRT_EDGE_FADE);
        edgeFade *= fadeStrength;

        vec3 reflectColor = texture(colortex4, scaleScreenUv(traceScreenPos.xy)).rgb;
        reflection.rgb += (reflectColor - reflection.rgb) * saturate(edgeFade);

        ivec2 texel = uvToTexelScaled(traceScreenPos.xy);
        vec3 reflectViewPos = ScreenToViewPos(vec3(traceScreenPos.xy, loadDepth0(texel)));
        reflection.a = distance(reflectViewPos, viewPos);
    }

    return reflection;
}