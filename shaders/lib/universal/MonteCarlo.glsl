// Monte Carlo integration of distributions

// PDF = 1 / (4 * PI)
vec3 SampleUniformSphere(vec2 xy) {
	float phi = TAU * xy.x;
	float cosTheta = 1.0 - xy.y * 2.0;
	float sinTheta = sqrt(1.0 - cosTheta * cosTheta);

	float x = sinTheta * cos(phi);
	float y = sinTheta * sin(phi);
	float z = cosTheta;

	return vec3(x, y, z);
}

// PDF = 1 / (2 * PI)
vec3 SampleUniformHemisphere(vec2 xy) {
	float phi = TAU * xy.x;
	float cosTheta = xy.y;
	float sinTheta = sqrt(1.0 - cosTheta * cosTheta);

	float x = sinTheta * cos(phi);
	float y = sinTheta * sin(phi);
	float z = cosTheta;

	return vec3(x, y, z);
}

// PDF = NoL / PI
vec3 SampleCosineHemisphere(vec2 xy) {
	float phi = TAU * xy.x;
	float cosTheta = sqrt(xy.y);
	float sinTheta = sqrt(1.0 - cosTheta * cosTheta);

	float x = sinTheta * cos(phi);
	float y = sinTheta * sin(phi);
	float z = cosTheta;

	return vec3(x, y, z);
}

// PDF = NoL / PI
vec3 SampleCosineHemisphereConcentric(vec2 xy) {
	// Rescale input from [0,1) to (-1,1). This ensures the output radius is in [0,1)
	vec2 p = 2.0 * xy - 0.99999994;
	vec2 a = abs(p);
	float Lo = min(a.x, a.y);
	float Hi = max(a.x, a.y);
	const float epsilon = 5.42101086243e-20; // 2^-64 (this avoids 0/0 without changing the rest of the mapping)
	float phi = (PI / 4.0) * (Lo / (Hi + epsilon) + 2.0 * step(a.x, a.y));
	float radius = Hi;

	// Copy sign bits from p
	vec2 disk = signMul(cossin(phi), p);
	return vec3(disk * radius, sqrt(1.0 - radius * radius));
}

// PDF = NoL / PI
vec3 SampleCosineHemisphere(vec3 vector, vec2 xy) {
	vec3 hemisphere = SampleUniformSphere(xy);
	hemisphere = normalize(vector + hemisphere);
	return signMul(hemisphere, dot(hemisphere, vector));
}

// PDF = 1 / (2 * PI * (1 - cosThetaMax));
vec3 SampleUniformCone(vec2 xy, float cosThetaMax) {
	float phi = TAU * xy.x;
	float cosTheta = mix(cosThetaMax, 1.0, xy.y);
	float sinTheta = sqrt(1.0 - cosTheta * cosTheta);

	float x = sinTheta * cos(phi);
	float y = sinTheta * sin(phi);
	float z = cosTheta;
	return vec3(x, y, z);
}

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
// PDF = D * G_SmithV / (4 * NoV)
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

// Veach 1997, "Robust Monte Carlo Methods for Light Transport Simulation"
float MISWeightBalanced(float pdf, float otherPdf) {
	float X = min(pdf, otherPdf) / max(pdf, otherPdf);
	float Y = pdf == otherPdf ? 1.0 : X;
	float M = rcp(1.0 + Y);
	return pdf > otherPdf ? M : 1.0 - M;
}

float MISWeightPower(float pdf, float otherPdf, float power) {
	float X = min(pdf, otherPdf) / max(pdf, otherPdf);
	float Y = pdf == otherPdf ? 1.0 : X;
	float M = rcp(1.0 + pow(Y, power));
	return pdf > otherPdf ? M : 1.0 - M;
}

void AddLobeWithMIS(inout vec3 weight, inout float pdf, vec3 lobeWeight, float lobePdf, float lobeProb) {
	const float kMinLobeProb = 1.1754943508e-38; // Smallest normal float
	if (lobeProb > kMinLobeProb) {
		lobePdf *= lobeProb;
		lobeWeight *= rcp(lobeProb);

		weight = mix(weight, lobeWeight, MISWeightBalanced(lobePdf, pdf));
		pdf += lobePdf;
	}
}
