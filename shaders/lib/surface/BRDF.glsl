/*
--------------------------------------------------------------------------------

	References:
		https://ubm-twvideo01.s3.amazonaws.com/o1/vault/gdc2017/Presentations/Hammon_Earl_PBR_Diffuse_Lighting.pdf
		https://schuttejoe.github.io/post/disneybsdf/
		https://www.pbr-book.org/3ed-2018/Reflection_Models/Microfacet_Models#\
		https://media.disneyanimation.com/uploads/production/publication_asset/48/asset/s2012_pbs_disney_brdf_notes_v3.pdf
		https://www.gamedevs.org/uploads/real-shading-in-unreal-engine-4.pdf
		https://www.gdcvault.com/play/1024478/PBR-Diffuse-Lighting-for-GGX
		https://disneyanimation.com/publications/physically-based-shading-at-disney/
		https://www.guerrilla-games.com/read/decima-engine-advances-in-lighting-and-aa

--------------------------------------------------------------------------------
*/

// PDF = D * NoH / (4 * VoH)
vec3 SampleGGX(vec2 xy, float alpha, vec3 normal) {
	float phi = TAU * xy.x;
	float cosTheta = sqrt((1.0 - xy.y) / (1.0 + (alpha * alpha - 1.0) * xy.y));
	float sinTheta = sqrt(1.0 - cosTheta * cosTheta);

	vec3 hemisphere = vec3(cossin(phi) * sinTheta, cosTheta);
	return BuildOrthonormalBasis(normal) * hemisphere;
}

// Sampling Visible GGX Normals with Spherical Caps
// https://arxiv.org/pdf/2306.05044
vec3 SampleGGXVNDF(vec3 viewDir, float alpha, vec2 xy) {
	// Importance sampling bias
	xy.y *= 1.0 - SPECULAR_IMPORTANCE_SAMPLING_BIAS;

	viewDir = normalize(vec3(alpha * viewDir.xy, viewDir.z));

	float phi = TAU * xy.x;
	float cosTheta = 1.0 - viewDir.z * xy.y - xy.y;
	float sinTheta = sqrt(saturate(1.0 - cosTheta * cosTheta));
	viewDir += vec3(cossin(phi) * sinTheta, cosTheta);

	return normalize(vec3(alpha * viewDir.xy, viewDir.z));
}

// https://ggx-research.github.io/publication/2023/06/09/publication-ggx.html
// world-space isotropic-only version
// benefits:
// - no need for moving to tangent space
// - it avoids the need for an orthonormal basis
// - it's (slightly) faster than the general version
vec3 SampleGGXVNDF(vec2 u, vec3 wi, float alpha, vec3 n) {
	// Importance sampling bias
	u.y *= 1.0 - SPECULAR_IMPORTANCE_SAMPLING_BIAS;

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
	vec3 up = abs(n.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
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

//================================================================================================//

// Schlick approximation
float FresnelSchlick(float VdotH, float f0) {
	return saturate(f0 + oms(f0) * pow5(1.0 - VdotH));
}

vec3 FresnelSchlick(float VdotH, vec3 f0) {
	return saturate(f0 + oms(f0) * pow5(1.0 - VdotH));
}

float FresnelSchlick(float VdotH, float f0, float f90) {
	return saturate(f0 + (f90 - f0) * pow5(1.0 - VdotH));
}

vec3 FresnelSchlick(float VdotH, vec3 f0, vec3 f90) {
	return saturate(f0 + (f90 - f0) * pow5(1.0 - VdotH));
}

// Lazanyi approximation correction
vec3 FresnelLazanyi2019(float VdotH, vec3 f0, vec3 f82) {
	vec3 a = 17.6513846 * (f0 - f82) + 8.16666667 * oms(f0);
	float invMu5 = pow5(1.0 - VdotH);
	return saturate(f0 + oms(f0) * invMu5 - a * VdotH * invMu5 * oms(VdotH));
}

float FresnelSchlickGaussian(float VdotH, float f0) {
	return saturate(f0 + oms(f0) * exp2(-9.60232 * pow8(VdotH) - 8.58092 * VdotH));
}

// Kutz et al. 2021, "Novel aspects of the Adobe Standard Material"
vec3 FresnelAdobeF82(float VdotH, vec3 f0, vec3 f82) {
	const float K = 49.0 / 46656.0;
	vec3 b = (K - K * f82) * (7776.0 + 9031.0 * f0);
	return saturate(f0 + pow5(1.0 - VdotH) * (oms(f0) - b * (VdotH - VdotH * VdotH)));
}

// Based on the F0 (Fresnel reflectance at 0 degrees incidence)
float FresnelDielectric(float VdotH, float f0) {
	f0 = min(sqrt(f0), 0.99999);
	f0 = (1.0 + f0) * rcp(1.0 - f0);

	float cosR = 1.0 - sqr(sqrt(1.0 - sqr(VdotH)) * rcp(max(f0, 1e-16)));
	if (cosR < 0.0) return 1.0;

	cosR *= inversesqrt(cosR);
	float a = f0 * VdotH;
	float b = f0 * cosR;
	float r1 = (a - cosR) / (a + cosR);
	float r2 = (b - VdotH) / (b + VdotH);
	return saturate(0.5 * (r1 * r1 + r2 * r2));
}

// Based on the refractive index N
float FresnelDielectricN(float VdotH, float n) {
	float cosR = sqr(n) + sqr(VdotH) - 1.0;
	if (cosR < 0.0) return 1.0;

	cosR *= inversesqrt(cosR);
	float a = n * VdotH;
	float b = n * cosR;
	float r1 = (a - cosR) / (a + cosR);
	float r2 = (b - VdotH) / (b + VdotH);
	return saturate(0.5 * (r1 * r1 + r2 * r2));
}

// Based on the refractive index N and the attenuation coefficient K
vec3 FresnelConductor(float VdotH, vec3 n, vec3 k) {
	vec3 n2k2 = n * n + k * k;
	n *= 2.0 * VdotH;

	float VdotH2 = VdotH * VdotH;
	vec3 a = n2k2 + VdotH2;
	vec3 b = n2k2 * VdotH2 + 1.0;
	vec3 r1 = (a - n) / (a + n);
	vec3 r2 = (b - n) / (b + n);
	return saturate(0.5 * (r1 + r2));
}

//================================================================================================//

// Beckmann 1963, "The scattering of electromagnetic waves from rough surfaces"
float NDFBeckmann(float NdotH2, float alpha2) {
	return exp((NdotH2 - 1.0) / (alpha2 * NdotH2)) / (PI * alpha2 * NdotH2 * NdotH2);
}

float NDFGaussian(float NdotH, float alpha2) {
	float thetaH = fastAcos(NdotH);
	return exp(-thetaH * thetaH / alpha2);
}

// GGX / Trowbridge-Reitz
// Walter et al. 2007, "Microfacet models for refraction through rough surfaces"
float NDFTrowbridgeReitz(float NdotH2, float alpha2) {
	return alpha2 * rPI / sqr(1.0 + (alpha2 - 1.0) * NdotH2);
}

// Anisotropic GGX
// Burley 2012, "Physically-Based Shading at Disney"
float NDFAnisotropicGGX(float ax, float ay, float NdotH, float XdotH, float YdotH) {
	float a2 = ax * ay;
	vec3 V = vec3(ay * XdotH, ax * YdotH, a2 * NdotH);
	return rPI * a2 * sqr(a2 / dot(V, V));
}

//================================================================================================//

// Smith 1967, "Geometrical shadowing of a random rough surface"
float VisSmithGGX(float cosTheta, float alpha2) {
	return rcp(sqrt((cosTheta - cosTheta * alpha2) * cosTheta + alpha2) + cosTheta);
}

float VisSmithGGX(float NdotL, float NdotV, float alpha2) {
	float visL = NdotL + sqrt((NdotL - NdotL * alpha2) * NdotL + alpha2);
	float visV = NdotV + sqrt((NdotV - NdotV * alpha2) * NdotV + alpha2);
	return rcp(visL * visV);
}

// Heitz 2014, "Understanding the Masking-Shadowing Function in Microfacet-Based BRDFs"
float VisSmithJoint(float NdotL, float NdotV, float alpha2) {
	float visL = NdotV * sqrt((NdotL - NdotL * alpha2) * NdotL + alpha2);
	float visV = NdotL * sqrt((NdotV - NdotV * alpha2) * NdotV + alpha2);
	return 0.5 * rcp(visL + visV);
}

// Schlick 1994, "An Inexpensive BRDF Model for Physically-Based Rendering"
float VisSchlick(float cosTheta, float k) {
	return 0.5 / (cosTheta * oms(k) + k);
}

float VisSchlick(float NdotL, float NdotV, float alpha) {
	float k = alpha * 0.5; // sqr(alpha + 1.0) * 0.125;
	return VisSchlick(NdotL, k) * VisSchlick(NdotV, k);
}

float VisSchlickBeckman(float NdotL, float NdotV, float alpha2) {
	float k = alpha2 * 0.797884560802865;
	return VisSchlick(NdotL, k) * VisSchlick(NdotV, k);
}

//================================================================================================//

// Cook-Torrance model
vec3 SpecularGGX(float LdotH, float NdotV, float NdotL, float NdotH, float roughness, vec3 f0) {
	float alpha2 = maxEps(roughness * roughness);

	// Fresnel term
	vec3 F = FresnelSchlick(LdotH, f0, saturate(50.0 * f0));

	// Distribution term
	float D = NDFTrowbridgeReitz(NdotH * NdotH, alpha2);

	// Visibility term (= G / (4 * NdotV * NdotL))
	float Vis = VisSmithJoint(NdotL, NdotV, alpha2);

	return F * D * Vis;
}

// Hammon 2017, "PBR Diffuse Lighting for GGX+Smith Microsurfaces"
vec3 DiffuseHammon(float NdotV, float NdotL, float VdotH, float NdotH, float roughness, vec3 albedo) {
	float facing = saturate(VdotH * VdotH);

	float singleSmooth = 1.05 * oms(pow5(1.0 - NdotL)) * oms(pow5(1.0 - NdotV));
	float singleRough = facing * (0.9 - 0.4 * facing) * (0.5 + NdotH) / max(NdotH, 1e-2);

	float single = mix(singleSmooth, singleRough, roughness) * rPI;
	float multi = 0.1159 * roughness;

	return (multi * albedo + single);
}

// Burley 2012, "Physically-Based Shading at Disney"
float DiffuseBurley(float LdotH, float NdotV, float NdotL, float roughness) {
	float f90 = 0.5 + 2.0 * roughness * LdotH * LdotH;

	return rPI * FresnelSchlick(NdotL, 1.0, f90) * FresnelSchlick(NdotV, 1.0, f90);
}

// Gotanda 2012, "Beyond a Simple Physically Based Blinn-Phong Model in Real-Time"
float DiffuseOrenNayar(float NdotV, float NdotL, float VdotL, float roughness) {
	float a = roughness * roughness;
	float s = a; // / ( 1.29 + 0.5 * a );
	float s2 = s * s;
	float cosri = VdotL - NdotV * NdotL;
	float C1 = 1.0 - 0.5 * s2 / (s2 + 0.33);
	float C2 = 0.45 * s2 / (s2 + 0.09) * cosri * mix(rcp(max(NdotL, NdotV)), 1.0, cosri < 0.0);
	return rPI * (C1 + C2) * (1.0 + roughness * 0.5);
}

// Portsmouth et al. 2025, "EON: A Practical Energy-Preserving Rough Diffuse BRDF"
vec3 DiffuseEON(float NdotV, float NdotL, float VdotL, float roughness, vec3 albedo) {
	// Albedo inversion for EON model to maintain a consistent color with lambert
	vec3 Rho = /* albedo *  */(1.0 + (0.189468 - 0.189468 * albedo) * roughness);

	// This is the main shaping term from the Oren-Nayar model (with tweaks by Fujii)
	float S = VdotL - NdotV * NdotL;
	float SOverT = max(S * rcp(maxEps(max(NdotV, NdotL))), S);
	const float constant1_FON = 0.5 - 2.0 / (3.0 * PI);
	// AF = rcp(1 + roughness * constant1_FON) is nearly a straight line, so approximate it as such
	float AF = 1.0 - roughness * (1.0 - rcp(1.0 + constant1_FON));
	float f_ss = AF * (1.0 + roughness * SOverT);

	// 4th Order approximation from the paper is a bit too heavy, first order seems to work just as well
	const float g1 = 0.262048f;
	float GoverPi_V = g1 - g1 * NdotV;
	// Use (1 - Eo) only as a non-reciprocal approach to energy conservation
	float f_ms = 1.0 - AF * (1.0 + roughness * GoverPi_V);
	// The Rho_ms term from the paper can be approximated as just Rho^2
	return Rho * (f_ss + albedo * Rho * f_ms) * rPI;
}

// de Carpentier 2017, "Decima Engine: Advances in Lighting and AA"
float GetNoHSquared(float radius, float NdotL, float NdotV, float VdotL) {
	float radiusCos = cos(radius);
	float radiusTan = tan(radius);

	// Early out if R falls within the disc​
	float RoL = 2.0 * NdotL * NdotV - VdotL;
	if (RoL >= radiusCos) return 1.0;

	float rOverLengthT = radiusCos * radiusTan * inversesqrt(1.0 - RoL * RoL);
	float NoTr = rOverLengthT * (NdotV - RoL * NdotL);
	float VoTr = rOverLengthT * (2.0 * NdotV * NdotV - 1.0 - RoL * VdotL);

	// Calculate dot(cross(N, L), V). This could already be calculated and available.​
	float triple = sqrt(saturate(1.0 - NdotL * NdotL - NdotV * NdotV - VdotL * VdotL + 2.0 * NdotL * NdotV * VdotL));

	// Do one Newton iteration to improve the bent light Direction​
	float NoBr = rOverLengthT * triple, VoBr = rOverLengthT * (2.0 * triple * NdotV);
	float NdotLVTr = NdotL * radiusCos + NdotV + NoTr, VdotLVTr = VdotL * radiusCos + 1.0 + VoTr;
	float p = NoBr * VdotLVTr, q = NdotLVTr * VdotLVTr, s = VoBr * NdotLVTr;
	float xNum = q * (-0.5 * p + 0.25 * VoBr * NdotLVTr);
	float xDenom = p * p + s * (s - 2.0 * p) + NdotLVTr * ((NdotL * radiusCos + NdotV) * VdotLVTr * VdotLVTr +
				q * (-0.5 * (VdotLVTr + VdotL * radiusCos) - 0.5));
	float twoX1 = 2.0 * xNum / (xDenom * xDenom + xNum * xNum);
	float sinTheta = twoX1 * xDenom;
	float cosTheta = 1.0 - twoX1 * xNum;
	NoTr = cosTheta * NoTr + sinTheta * NoBr;
	VoTr = cosTheta * VoTr + sinTheta * VoBr;

	// Calculate (N.H)^2 based on the bent light direction​
	float newNdotL = NdotL * radiusCos + NoTr;
	float newVdotL = VdotL * radiusCos + VoTr;
	float NoH = NdotV + newNdotL;
	float HoH = 2.0 * newVdotL + 2.0;

	return max0(NoH * NoH / HoH);
}

vec3 SphericalAreaGGX(float LdotH, float NdotV, float NdotL, float LdotV, float alpha, vec3 f0, float radius) {
	// alpha = max(alpha, 1e-2);
	float alpha2 = alpha * alpha;

	// Fresnel term
	vec3 F = FresnelSchlick(LdotH, f0, saturate(50.0 * f0));

	// Distribution term
	float NdotH2 = GetNoHSquared(radius, NdotL, NdotV, LdotV);
	float D = NDFTrowbridgeReitz(NdotH2, alpha2);

	// Visibility term (= G / (4 * NdotV * NdotL))
	float Vis = VisSmithJoint(NdotL, NdotV, alpha2);

	// Both Karis’ approach and our approach are not truely energy conserving as their normalization is only approximate.
	// We’re experimenting with different formulas for the normalization to try to improve its accuracy, of which this is one:
	float alphaSquaredLdotH = alpha2 * (LdotH + 0.001);
	float normalization = alphaSquaredLdotH / (alphaSquaredLdotH + 0.25 * radius * (3.0 * alpha + radius));

	return F * D * Vis * normalization;
}

float SpecularThroughputGGX(float NdotV, float NdotL, float roughness) {
	float alpha2 = roughness * roughness;
	return VisSmithJoint(NdotL, NdotV, alpha2) / VisSmithGGX(NdotV, alpha2);
}
