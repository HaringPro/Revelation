/*
--------------------------------------------------------------------------------

    Revelation Shaders (Ultra Performance Edition - Horizon Fix Removed)

    Copyright (C) 2026 HaringPro
    Apache License 2.0

    Pass: Compute refraction, combine translucent and fog
    Optimizations: 
      - Sky-bypass early Z culling.
      - Zero-iteration screen space projection refraction.
      - Full-resolution inline analytical fog (Zero bandwidth upscale).
      - Removed unused LdotV calculation.
    Note: Horizon blending (edgeFactor) removed for performance / compatibility.
--------------------------------------------------------------------------------
*/

#define PASS_COMPOSITE

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 0 */
layout (location = 0) out vec4 sceneOut;

//======// Uniform //=============================================================================//

#include "/lib/universal/Uniform.glsl"

//======// SSBO //================================================================================//

#include "/lib/universal/SSBO.glsl"

//======// Struct //==============================================================================//

#include "/lib/universal/Material.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Transform.glsl"
#include "/lib/universal/Fetch.glsl"
#include "/lib/universal/Random.glsl"

#include "/lib/atmosphere/Common.glsl"

#include "/lib/atmosphere/AtmosphericFog.glsl" 
#include "/lib/atmosphere/CommonFog.glsl"
#include "/lib/SpatialUpscale.glsl"

#include "/lib/water/WaterFog.glsl"
#include "/lib/surface/BRDF.glsl"
#include "/lib/surface/SSRT.glsl"

vec2 CalculateRefractedCoord(in ivec2 texelPos, in vec3 viewPos, in vec3 screenPos, in bool waterMask) {
    vec3 viewNormal = mat3(gbufferModelView) * FetchSurfaceNormal(texelPos);
    float viewLengthInv = inversesqrt(sdot(viewPos));
    vec3 viewDir = viewPos * viewLengthInv;

    vec3 refractedDir;
    if (waterMask) {
        vec3 viewGeometryNormal = mat3(gbufferModelView) * FetchGeometryNormal(texelPos);
        refractedDir = refract(viewDir, viewNormal - viewGeometryNormal * 0.95, 1.0 / WATER_IOR);
    } else {
        refractedDir = refract(viewDir, viewNormal, 1.0 / GLASS_IOR);
    }

    // 零步进屏幕空间投影折射
    float estimatedThickness = waterMask ? 3.0 : 0.3; 
    refractedDir *= estimatedThickness * REFRACTION_STRENGTH;
    
    vec2 refractedCoord = ViewToScreenPos(viewPos + refractedDir).xy;

    float refractedDepth = loadDepth1(uvToTexel(refractedCoord));
    refractedCoord = mix(refractedCoord, screenPos.xy, step(refractedDepth, screenPos.z));

    vec2 edgeFade = smoothstep(0.8, 1.0, abs(refractedCoord * 2.0 - 1.0));
    return mix(refractedCoord, screenPos.xy, edgeFade);
}

void main() {
    ivec2 texelPos = ivec2(gl_FragCoord.xy);
    vec2 screenCoord = gl_FragCoord.xy * viewPixelSize;

    float depth = loadDepth0(texelPos);

    vec3 screenPos = vec3(screenCoord, depth);
    vec3 viewPos = ScreenToViewPos(screenPos);
    #if defined LOD_MOD
        if (depth > 1.0 - EPS) {
            depth = screenPos.z = loadDepth0Lod(texelPos);
            viewPos = ScreenToViewPosLod(screenPos);
        }
    #endif

    vec3 sceneColor;
    float fogMask = 1.0;
    
    vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos;
    vec3 worldDir = normalize(worldPos);

    float viewDistance = 0.0;
    if (depth < 1.0 || isEyeInWater == 1) {
        viewDistance = length(viewPos);
    }

    // ====================================================================================
    // 天空 / 半透明物体处理
    // ====================================================================================
    if (depth >= 1.0) {
        sceneColor = loadSceneMain(texelPos);
    } else {
        uvec4 materialPack = loadMaterialPack(texelPos);
        uint materialID = materialPack.y;
        bool glassMask = materialID == 2u;
        bool waterMask = materialID == 3u;

        ivec2 refractedTexel = texelPos;
        if (glassMask || waterMask) {
            refractedTexel = uvToTexel(CalculateRefractedCoord(texelPos, viewPos, screenPos, waterMask));
        }

        sceneColor = loadSceneMain(refractedTexel);

        vec4 translucent = ExtractSpecularTex(materialPack);
        vec3 albedo = sRGBToLinear(translucent.rgb);

        // 安全回退：部分玻璃实体（掉落物/展示实体）可能未把 albedo 打包进 materialPack.zw，
        // zw 为 0 时 log2(0) 得到 -inf/NaN，会让玻璃乘出纯黑不可见。
        // 此时回退使用 colortex6 中的真实 albedo，保证物体至少可见。
        if (maxOf(translucent.rgb) < 0.001 || translucent.a < 0.001) {
            vec4 fallbackAlbedo = texelFetch(colortex6, texelPos, 0);
            translucent = vec4(sRGBToLinear(fallbackAlbedo.rgb), max(fallbackAlbedo.a, 0.75));
            albedo = translucent.rgb;
        }

        if (materialID == 500u) {
            vec3 diffuseLight = texelFetch(colortex3, texelPos, 0).rgb;
            sceneColor = mix(sceneColor, albedo * diffuseLight, translucent.a);
        }

        if (glassMask || waterMask) {
            if (glassMask) {
                sceneColor *= exp2(log2(albedo) * approxSqrt(translucent.a));
                sceneColor += (2.0 * EMISSIVE_BRIGHTNESS) * Unpack2x8UX(materialPack.x) * mean(albedo) * albedo;
            }
            vec4 specularLight = texelFetch(colortex3, texelPos, 0);
            sceneColor = sceneColor * specularLight.a + specularLight.rgb;
        }

        #ifdef BORDER_FOG
            if (isEyeInWater == 0) {
                float xzDistSq = sdot(worldPos.xz) * (1.0 / (2048.0 * 2048.0));
                float xzDistPow4 = xzDistSq * xzDistSq;
                float density = exp2(-0.1 * max0(worldPos.y - 63.0)) * (xzDistPow4 * xzDistPow4); 
                float transmittance = exp2(-BORDER_FOG_FALLOFF * density);

                vec3 skyRadiance = AtmosphereSkyView(atmosphereViewPos, worldDir, worldSunDir);
                sceneColor = mix(skyRadiance, sceneColor, transmittance);
            }
        #endif
    }

    // ====================================================================================
    // 体积雾 / 水下雾（统一处理，并修复天空所有方向的雾）
    // ====================================================================================
    mat2x3 fogData = mat2x3(vec3(0.0), vec3(1.0));

    if (isEyeInWater == 1) {
        float LdotV = dot(worldLightDir, worldDir);
        fogData = AnalyticWaterFog(eyeSkylightSmooth, viewDistance, LdotV);
    } else {
        #ifdef VOLUMETRIC_FOG
            float dither = BlueNoise(texelPos, frameCounter);
            
            bool skyMask = (depth >= 1.0 - EPS);
            vec3 fogEndPos = worldPos;

            if (skyMask) {
                // 天空像素：强制使用几何路径，固定有限距离，覆盖全方向
                skyMask = false;
                const float skyFogDist = 256.0;           // 控制天空雾的浓度（调小变浓）
                fogEndPos = vec3(0.0) + worldDir * min(length(worldPos), skyFogDist);
            } else {
                // 非天空：检查后方是否实际是天空（例如半透明区域）
                float opaqueDepth = loadDepth1(texelPos);
                #if defined LOD_MOD
                    if (opaqueDepth > 1.0 - EPS) opaqueDepth = loadDepth1Lod(texelPos);
                #endif
                if (opaqueDepth >= 1.0 - EPS) {
                    skyMask = true;          // 实际为天空，同样使用有限距离
                    const float skyFogDist = 512.0;
                    fogEndPos = vec3(0.0) + worldDir * min(length(worldPos), skyFogDist);
                }
            }
            
            fogData = RaymarchAtmosphericFog(vec3(0.0), fogEndPos, dither, skyMask, 1u);
        #endif
    }

    sceneColor = ApplyFog(sceneColor, fogData);
    fogMask = mix(1.0, mean(fogData[1]), eyeSkylightSmooth);

    if (viewDistance == 0.0) viewDistance = length(viewPos);
    RenderVanillaFog(sceneColor, fogMask, viewDistance);

    #if defined TAA_ENABLED && RENDER_MODE == 1
        sceneColor = RGBToYCoCg(sceneColor);
    #endif

    #if DEBUG_NORMALS == 1
        sceneColor = FetchSurfaceNormal(texelPos) * 0.5 + 0.5;
    #elif DEBUG_NORMALS == 2
        sceneColor = FetchGeometryNormal(texelPos) * 0.5 + 0.5;
    #endif

    sceneOut = vec4(sceneColor, saturate(1.0 - fogMask));
}