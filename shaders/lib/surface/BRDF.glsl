
// References:
// https://ubm-twvideo01.s3.amazonaws.com/o1/vault/gdc2017/Presentations/Hammon_Earl_PBR_Diffuse_Lighting.pdf
// https://schuttejoe.github.io/post/disneybsdf/
// https://www.pbr-book.org/3ed-2018/Reflection_Models/Microfacet_Models#\
// https://media.disneyanimation.com/uploads/production/publication_asset/48/asset/s2012_pbs_disney_brdf_notes_v3.pdf
// https://www.gamedevs.org/uploads/real-shading-in-unreal-engine-4.pdf

//================================================================================================//

vec3 SampleCosineHemisphere(in vec3 normal, in vec2 xy) {
    float phi = TAU * xy.x;
    float cosTheta = xy.y * 2.0 - 1.0;
    float sinTheta = sqrt(saturate(1.0 - cosTheta * cosTheta));
    vec3 hemisphere = vec3(cossin(phi) * sinTheta, cosTheta);

	vec3 cosineVector = normalize(normal + hemisphere);
	return cosineVector * fastSign(dot(cosineVector, normal));
}

// From https://github.com/Jessie-LC/open-source-utility-code/blob/main/simple/misc.glsl
vec3 SampleConeVector(in vec3 vector, in vec2 xy, in float angle) {
    xy.x *= TAU;
    float cosAngle = cos(angle);
    xy.y = xy.y * (1.0 - cosAngle) + cosAngle;
    vec3 sphereCap = vec3(vec2(cos(xy.x), sin(xy.x)) * sqrt(1.0 - xy.y * xy.y), xy.y);
    return rotate(sphereCap, vec3(0.0, 0.0, 1.0), vector);
}

// From https://ggx-research.github.io/publication/2023/06/09/publication-ggx.html
// world-space isotropic-only version
// benefits: 
// - no need for moving to tangent space
// - it avoids the need for an orthonormal basis
// - it's (slightly) faster than the general version
vec3 SampleGGXVNDF(in vec2 u, in vec3 wi, in float alpha, in vec3 n) {
    // Importance sampling bias
    u.x = mix(u.x, 1.0, SPECULAR_IMPORTANCE_SAMPLING_BIAS);

    // decompose the vector in parallel and perpendicular components
    vec3 wi_z = n * dot(wi, n);
    vec3 wi_xy = wi - wi_z;
    // warp to the hemisphere configuration
    vec3 wiStd = normalize(wi_z - alpha * wi_xy);
    // sample a spherical cap in (-wiStd.z, 1]
    float wiStd_z = dot(wiStd, n);
    float phi = (2.0 * u.x - 1.0) * PI;
    float z = (1.0 - u.y) * (1.0 + wiStd_z) - wiStd_z;
    float sinTheta = sqrt(saturate(1.0 - z * z));
    float x = sinTheta * cos(phi);
    float y = sinTheta * sin(phi);
    vec3 cStd = vec3(x, y, z);
    // reflect sample to align with normal
    vec3 up = vec3(0.0, 0.0, 1.0);
    vec3 wr = n + up;
    vec3 c = dot(wr, cStd) * wr / wr.z - cStd;
    // compute halfway direction as standard normal
    vec3 wmStd = c + wiStd;
    vec3 wmStd_z = n * dot(n, wmStd);
    vec3 wmStd_xy = wmStd_z - wmStd;
    // warp back to the ellipsoid configuration
    vec3 wm = normalize(wmStd_z + alpha * wmStd_xy);
    // return final normal
    return wm;
}

// pdf = D * NoH / (4 * VoH)
vec3 SampleGGX(in vec2 Xi, in float a, in vec3 N) {
    // Spherical coordinates
    float phi = TAU * Xi.x;
    float cosTheta = sqrt((1.0 - Xi.y) / (1.0 + (a * a - 1.0) * Xi.y));
    float sinTheta = sqrt(1.0 - cosTheta * cosTheta);

    // Convert to hemisphere vector
    vec3 H;
    H.x = cos(phi) * sinTheta;
    H.y = sin(phi) * sinTheta;
    H.z = cosTheta;

    // Convert tangent space normal to world space
    vec3 up = abs(N.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent = normalize(cross(up, N));
    vec3 bitangent = cross(N, tangent);

    return tangent * H.x + bitangent * H.y + N * H.z;
}

//======// Fresnel //=============================================================================//

// Schlick approximation
float FresnelSchlick(in float cosTheta, in float f0) {
    return saturate(f0 + oms(f0) * pow5(1.0 - cosTheta));
}

vec3 FresnelSchlick(in float cosTheta, in vec3 f0) {
    return saturate(f0 + oms(f0) * pow5(1.0 - cosTheta));
}

float FresnelSchlick(in float cosTheta, in float f0, in float f90) {
    return saturate(f0 + (f90 - f0) * pow5(1.0 - cosTheta));
}

vec3 FresnelSchlickMS(in float cosTheta, in vec3 f0, float roughness) {
    float weight = rcp(1.0 + 5.0 * roughness * roughness); // Empirical compensation factor
    vec3 fresnel = f0 + oms(f0) * pow5(1.0 - cosTheta);
    return mix(fresnel, vec3(1.0), weight); // Add energy compensation
}

// Lazanyi approximation correction
vec3 FresnelLazanyi2019(in float cosTheta, in vec3 f0, in vec3 f82) {
    vec3 a = 17.6513846 * (f0 - f82) + 8.16666667 * oms(f0);
    float invMu5 = pow5(1.0 - cosTheta);
    return saturate(f0 + oms(f0) * invMu5 - a * cosTheta * invMu5 * oms(cosTheta));
}

float FresnelSchlickGaussian(in float cosTheta, in float f0) {
    return saturate(f0 + oms(f0) * exp2(-9.60232 * pow8(cosTheta) - 8.58092 * cosTheta));
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

//======// Normal Distribution //=================================================================//

float NDFBeckmann(in float NdotH, in float alpha2) {
    float NdotH2 = NdotH * NdotH;
    return maxEps(rcp(PI * alpha2 * NdotH2 * NdotH2) * fastExp((NdotH2 - 1.0) / (alpha2 * NdotH2)));
}

float NDFGaussian(in float NdotH, in float alpha2) {
	float thetaH = fastAcos(NdotH);
    return fastExp(-thetaH * thetaH / alpha2);
}

float NDFGGX(in float NdotH, in float alpha) {
    float NdotH2 = NdotH * NdotH;
    float tanNdotH2 = oms(NdotH2) / NdotH2;
    return rPI * sqr(alpha / (NdotH2 * (sqr(alpha) + tanNdotH2)));
}

float NDFTrowbridgeReitz(in float NdotH, in float alpha2) {
	return alpha2 * rPI / sqr(1.0 + (alpha2 - 1.0) * NdotH * NdotH);
}

//======// Geometric GGX //=======================================================================//

// Smith-based
// float lambda(in float cosTheta, in float alpha2) {
//     return (sqrt(alpha2 + oms(alpha2) * cosTheta * cosTheta) / cosTheta - 1.0) * 0.5;
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

float G1SmithGGX(in float cosTheta, in float alpha2) {
    return 2.0 * cosTheta * rcp(sqrt(alpha2 + oms(alpha2) * cosTheta * cosTheta) + cosTheta);
}

float G1SmithGGXInverse(in float cosTheta, in float alpha2) {
    return (sqrt(alpha2 + oms(alpha2) * cosTheta * cosTheta) + cosTheta) * (0.5 / cosTheta);
}

float G2SmithGGX(in float NdotL, in float NdotV, in float alpha2) {
    return 2.0 * NdotL * NdotV * rcp(NdotL * sqrt(alpha2 + oms(alpha2) * NdotV * NdotV) + NdotV * sqrt(alpha2 + oms(alpha2) * NdotL * NdotL));
}

float G2withG1SmithGGX(in float NdotL, in float NdotV, in float alpha2) {
	float lt = sqrt(alpha2 + oms(alpha2) * sqr(NdotL));
	float vt = sqrt(alpha2 + oms(alpha2) * sqr(NdotV));
	return saturate(NdotL * (NdotV + vt) / (lt * NdotV + vt * NdotL));
}

// Schlick-based
float G1Schlick(in float cosTheta, in float k) {
    return cosTheta / (cosTheta * oms(k) + k);
}

float G2Schlick(in float NdotL, in float NdotV, in float alpha2) {
    return G1Schlick(NdotL, alpha2) * G1Schlick(NdotV, alpha2);
}

float G2SchlickBeckman(in float NdotL, in float NdotV, in float alpha2) {
    float k = alpha2 * 0.797884560802865;
    return G1Schlick(NdotL, k) * G1Schlick(NdotV, k);
}

float G2SchlickGGX(in float NdotL, in float NdotV, in float alpha) {
    // float k = sqr(alpha + 1.0) * 0.125;
    float k = alpha * 0.5;
    return G1Schlick(NdotL, k) * G1Schlick(NdotV, k);
}

//================================================================================================//

// Cook-Torrance model
vec3 SpecularGGX(in float LdotH, in float NdotV, in float NdotL, in float NdotH, in float roughness, in vec3 f0) {
    float alpha2 = maxEps(roughness * roughness);

    // Fresnel term
    vec3 F = FresnelSchlick(LdotH, f0);

    // Distribution term
	float D = NDFTrowbridgeReitz(NdotH, alpha2);

    // Geometric term
    float G = G2SmithGGX(NdotL, NdotV, alpha2);

	return F * D * G / (4.0 * NdotV);
}

// From https://www.gdcvault.com/play/1024478/PBR-Diffuse-Lighting-for-GGX
vec3 DiffuseHammon(in float LdotV, in float NdotV, in float NdotL, in float NdotH, in float roughness, in vec3 albedo) {
    float facing = saturate(LdotV) * 0.5 + 0.5;

    float singleSmooth = 1.05 * oms(pow5(1.0 - NdotL)) * oms(pow5(1.0 - NdotV));
    float singleRough = facing * (0.45 - 0.2 * facing) * (rcp(NdotH) + 2.0);

    float single = mix(singleSmooth, singleRough, roughness) * rPI;
    float multi = 0.1159 * roughness;

    return (multi * albedo + single) * NdotL;
}

// From https://disneyanimation.com/publications/physically-based-shading-at-disney/
float DiffuseBurley(in float LdotH, in float NdotV, in float NdotL, in float roughness) {
	float f90 = 0.5 + 2.0 * roughness * LdotH * LdotH;

	return NdotL * rPI * FresnelSchlick(NdotL, roughness, f90) * FresnelSchlick(NdotV, roughness, f90);
}

// From https://blog.selfshadow.com/publications/turquin/ms_comp_final.pdf
vec3 TurquinBRDF(in float NdotV, in float NdotL, in float NdotH, in float VdotH, in float f0, in float metallic, in float roughness, in vec3 albedo) {
    vec3 F0 = mix(vec3(f0), albedo, metallic); 
    float alpha2 = roughness * roughness;

    // Fresnel term
    vec3 F = FresnelSchlickMS(VdotH, F0, roughness);

    // Distribution term
    float D = NDFTrowbridgeReitz(NdotH, alpha2);   

    // Geometric term
    float G = G2SchlickGGX(NdotL, NdotV, alpha2);      

    // Diffuse contribution with energy compensation
    vec3 kD = oms(F) * oms(metallic);
    vec3 diffuse = kD * albedo * rPI;

    // Specular contribution
    vec3 numerator = D * G * F; 
    float denominator = 4.0 * NdotV * NdotL;
    vec3 specular = numerator / maxEps(denominator);  

    return (diffuse + specular) * NdotL;
}