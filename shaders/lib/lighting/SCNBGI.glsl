/*
--------------------------------------------------------------------------------
    Revelation Shaders – Skylight Compensation for Large Interiors
    Copyright (C) 2026 AnotherCream
    Apache License 2.0

    Call ApplySkylightCompensation() in deferred lighting to brighten enclosed
    areas that are above sea level but have no sky light, using SH‑based
    directional lighting.
    (Screen‑space visibility test removed; green debug output)
--------------------------------------------------------------------------------
*/

// User‑tuneable macros (override before including this file if desired)
#ifndef COMPENSATION_Y_THRESHOLD
    #define COMPENSATION_Y_THRESHOLD -20.0          // World Y above which compensation may apply
#endif
#ifndef COMPENSATION_BOOST
    #define COMPENSATION_BOOST 1.0                 // Overall brightness multiplier for the compensation
#endif
#ifndef COMPENSATION_FADE_RANGE
    #define COMPENSATION_FADE_RANGE 8.0            // Distance over which the effect fades in (meters)
#endif

//================================================================================================//
// Required external uniforms & functions (ensure they are present in the calling shader):
//
// layout(std430, binding = 0) buffer GlobalData { ... } global;
// vec3 ConvolvedReconstructSH3(vec3[9] coeff, vec3 dir);
// float luminance(vec3);
//================================================================================================//

vec3 ApplySkylightCompensation(vec3 worldNormal, vec3 worldPos, float lightmapY, vec3 viewPos) {
    // Only apply above the threshold and where sky light is nearly absent
    if (worldPos.y < COMPENSATION_Y_THRESHOLD || lightmapY > 0.01) {
        return vec3(0.0);
    }

    // Compensation brightness based on the sky SH distribution in the normal direction,
    // scaled by the current global sky up‑illuminance (or a representative maximum).
    vec3 skyIrradiance = ConvolvedReconstructSH3(global.skySH, worldNormal);
    float maxSky = luminance(global.skyUpIlluminance);
    vec3 compensation = skyIrradiance * maxSky * COMPENSATION_BOOST;

    // Fade the compensation based on distance to the viewer, so nearby surfaces
    // gradually blend from full compensation to none.
    float dist = length(viewPos);
    float fade = saturate(dist / COMPENSATION_FADE_RANGE);

    // Green debug output – remove vec3(0,1,0) to restore normal colour
    return vec3(0.0, 1.0, 0.0) * compensation * fade;
}