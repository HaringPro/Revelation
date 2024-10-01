
// References:
// https://ubm-twvideo01.s3.amazonaws.com/o1/vault/gdc2017/Presentations/Hammon_Earl_PBR_Diffuse_Lighting.pdf
// https://schuttejoe.github.io/post/disneybsdf/

//======// Fresnel //=============================================================================//

// Schlick approximation
float FresnelSchlick(in float cosTheta, in float f0) {
    return saturate(f0 + oneMinus(f0) * pow5(1.0 - cosTheta));
}

// Lazanyi approximation correction
vec3 FresnelLazanyi2019(in float cosTheta, in vec3 f0, in vec3 f82) {
    vec3 a = 17.6513846 * (f0 - f82) + 8.16666667 * oneMinus(f0);
    float invMu5 = pow5(1.0 - cosTheta);
    return saturate(f0 + oneMinus(f0) * invMu5 - a * cosTheta * invMu5 * oneMinus(cosTheta));
}

// Based on the F0 (Fresnel reflectance at 0 degrees incidence)
float FresnelDielectric(in float cosTheta, in float f0) {
    f0 = min(sqrt(f0), 0.99999);
    f0 = (1.0 + f0) * rcp(1.0 - f0);

    float cosR = 1.0 - sqr(sqrt(1.0 - sqr(cosTheta)) * rcp(max(f0, 1e-16)));
    if (cosR < 0.0) return 1.0;

    cosR *= inversesqrt(cosR);
    float a = f0 * cosTheta;
    float b = f0 * cosR;
    float r1 = (a - cosR) / (a + cosR);
    float r2 = (b - cosTheta) / (b + cosTheta);
    return saturate(0.5 * (r1 * r1 + r2 * r2));
}

// Based on the refractive index N
float FresnelDielectricN(in float cosTheta, in float n) {
    float cosR = sqr(n) + sqr(cosTheta) - 1.0;
    if (cosR < 0.0) return 1.0;

    cosR *= inversesqrt(cosR);
    float a = n * cosTheta;
    float b = n * cosR;
    float r1 = (a - cosR) / (a + cosR);
    float r2 = (b - cosTheta) / (b + cosTheta);
    return saturate(0.5 * (r1 * r1 + r2 * r2));
}

// Based on the refractive index N and the attenuation coefficient K
vec3 FresnelConductor(in float cosTheta, in vec3 n, in vec3 k) {
    vec3 n2k2 = n * n + k * k;
    n *= 2.0 * cosTheta;

    float cosTheta2 = cosTheta * cosTheta;
    vec3 a = n2k2 + cosTheta2;
    vec3 b = n2k2 * cosTheta2 + 1.0;
    vec3 r1 = (a - n) / (a + n);
    vec3 r2 = (b - n) / (b + n);
    return saturate(0.5 * (r1 + r2));
}

//======// Distribution GGX //====================================================================//

float DistributionGGX(in float NdotH, in float alpha2) {
	return alpha2 * rPI / sqr(1.0 + (alpha2 - 1.0) * NdotH * NdotH);
}

//======// Smith GGX //===========================================================================//

// float lambda(in float cosTheta, in float alpha2) {
//     return (sqrt(alpha2 + oneMinus(alpha2) * cosTheta * cosTheta) / cosTheta - 1.0) * 0.5;
// }

// float G1SmithGGX(in float cosTheta, in float alpha2) {
//     return rcp(1.0 + lambda(cosTheta, alpha2));
// }

// float G1SmithGGXInverse(in float cosTheta, in float alpha2) {
//     return 1.0 + lambda(cosTheta, alpha2);
// }

// float G2SmithGGX(in float NdotL, in float NdotV, in float alpha2) {
//     return rcp(1.0 + lambda(NdotL, alpha2) + lambda(NdotV, alpha2));
// }

float G1SmithGGX(in float NdotV, in float alpha2) {
    return 2.0 * NdotV * rcp(sqrt(alpha2 + oneMinus(alpha2) * NdotV * NdotV) + NdotV);
}

float G1SmithGGXInverse(in float NdotV, in float alpha2) {
    return (sqrt(alpha2 + oneMinus(alpha2) * NdotV * NdotV) + NdotV) * (0.5 / NdotV);
}

float G2SmithGGX(in float NdotL, in float NdotV, in float alpha2) {
    return 2.0 * NdotL * NdotV * rcp(NdotL * sqrt(alpha2 + oneMinus(alpha2) * NdotV * NdotV) + NdotV * sqrt(alpha2 + oneMinus(alpha2) * NdotL * NdotL));
}

//================================================================================================//

float SpecularBRDF(in float LdotH, in float NdotV, in float NdotL, in float NdotH, in float alpha2, in float f0) {
    alpha2 = max(alpha2, 1e-6);

    // Fresnel term
    float F = FresnelSchlick(LdotH, f0);

    // Distribution term
	float D = DistributionGGX(NdotH, alpha2);

    // Geometric term
    float G = G2SmithGGX(NdotL, NdotV, alpha2);

	return min(F * D * G / (4.0/*  * NdotL */ * NdotV), 5e2); // Prevent overflow
}

vec3 DiffuseHammon(in float LdotV, in float NdotV, in float NdotL, in float NdotH, in float roughness, in vec3 albedo) {
    float facing = max0(LdotV) * 0.5 + 0.5;

    float singleSmooth = 1.05 * oneMinus(pow5(1.0 - NdotL)) * oneMinus(pow5(1.0 - NdotV));
    float singleRough = facing * (0.45 - 0.2 * facing) * (rcp(NdotH) + 2.0);

    float single = mix(singleSmooth, singleRough, roughness) * rPI;
    float multi = 0.1159 * roughness;

    return (multi * albedo + single) * NdotL;
}

//================================================================================================//

// From https://ggx-research.github.io/publication/2023/06/09/publication-ggx.html
vec3 sampleGGXVNDF(in vec3 viewDir, in float roughness, in vec2 xy) {
    // Randomness clamping
    #ifdef SPECULAR_DIFFUSION_CLAMP
        xy.y *= 0.5;
    #endif

    // Transform viewer direction to the hemisphere configuration
    viewDir = normalize(vec3(roughness * viewDir.xy, viewDir.z));

    // Sample a reflection direction off the hemisphere
    float phi = TAU * xy.x;
    float cosTheta = oneMinus(xy.y) * (1.0 + viewDir.z) - viewDir.z;
    float sinTheta = sqrt(saturate(1.0 - cosTheta * cosTheta));
    vec3 reflected = vec3(cossin(phi) * sinTheta, cosTheta);

    // Evaluate halfway direction
    // This gives the normal on the hemisphere
    vec3 halfway = reflected + viewDir;

    // Transform the halfway direction back to hemiellispoid configuation
    // This gives the final sampled normal
    return normalize(vec3(roughness * halfway.xy, halfway.z));
}

vec3 sampleCosineVector(in vec3 vector, in vec2 xy) {
    float phi = TAU * xy.x;
    float cosTheta = xy.y * 2.0 - 1.0;
    float sinTheta = sqrt(saturate(1.0 - cosTheta * cosTheta));
    vec3 hemisphere = vec3(cossin(phi) * sinTheta, cosTheta);

	vec3 cosineVector = normalize(vector + hemisphere);
	return dot(cosineVector, vector) < 0.0 ? -cosineVector : cosineVector;
}

vec3 importanceSampleCosine(in vec3 normal, in vec2 xy) {
    float phi = TAU * xy.y;

    float cosTheta = sqrt(xy.x);
    float sinTheta = sqrt(1.0 - xy.x);
    vec3 sampleHemisphere = vec3(cos(phi) * sinTheta, sin(phi) * sinTheta, cosTheta);

    // Orient sample into world space
    vec3 up = abs(normal.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent = normalize(cross(up, normal));
    vec3 bitangent = cross(normal, tangent);

    vec3 sampleWorld = vec3(0.0);
    sampleWorld += sampleHemisphere.x * tangent;
    sampleWorld += sampleHemisphere.y * bitangent;
    sampleWorld += sampleHemisphere.z * normal;

    return sampleWorld;
}

// From https://github.com/Jessie-LC/open-source-utility-code/blob/main/simple/misc.glsl
vec3 rotate(vec3 vector, vec3 from, vec3 to) {
	// where "from" and "to" are two unit vectors determining how far to rotate
	// adapted version of https://en.wikipedia.org/wiki/Rodrigues%27_rotation_formula

	float cosTheta = dot(from, to);
	if (abs(cosTheta) >= 0.9999) { return cosTheta < 0.0 ? -vector : vector; }
	vec3 axis = normalize(cross(from, to));

	vec2 sc = vec2(sqrt(1.0 - cosTheta * cosTheta), cosTheta);
	return sc.y * vector + sc.x * cross(axis, vector) + (1.0 - sc.y) * dot(axis, vector) * axis;
}

vec3 generateConeVector(vec3 vector, vec2 xy, float angle) {
    xy.x *= TAU;
    float cosAngle = cos(angle);
    xy.y = xy.y * (1.0 - cosAngle) + cosAngle;
    vec3 sphereCap = vec3(vec2(cos(xy.x), sin(xy.x)) * sqrt(1.0 - xy.y * xy.y), xy.y);
    return rotate(sphereCap, vec3(0, 0, 1), vector);
}