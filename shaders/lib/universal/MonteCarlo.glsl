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
