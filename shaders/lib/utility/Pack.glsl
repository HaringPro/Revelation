#if defined NORMAL_MAPPING
	void DecodeNormalTex(inout vec3 normalTex) {
        if (any(greaterThan(normalTex, vec3(0.003)))) {
			normalTex = normalTex * 2.0 - 1.0 + r255;
			#if TEXTURE_FORMAT == 0
				normalTex.z = sqrt(saturate(oneMinus(dotSelf(normalTex.xy))));
			#else
				normalTex = normalize(normalTex);
			#endif
    		normalTex.xy = uintBitsToFloat(floatBitsToUint(max0(abs(normalTex.xy) - r255)) ^ (floatBitsToUint(normalTex.xy) & 0x80000000u));
		}
	}
#endif

float Packup2x8(in vec2 data) {
	return dot(floor(data * max8f + 0.5), vec2(256.0 / max16f, 1.0 / max16f));
}

float PackupDithered2x8(in vec2 data, in float dither) {
	return dot(floor(data * max8f + dither), vec2(256.0 / max16f, 1.0 / max16f));
}

vec2 Unpack2x8(in float data) {
	float x, y = modf(data * (max16f / 256.0), x) * 256.0;
	return vec2(x, y) * r255;
}

float Packup2x8X(in float data) { return floor(data * (max16f / 256.0)) * r255; }
float Packup2x8Y(in float data) { return fract(data * (max16f / 256.0)) * (256.0 * r255); }

float Packup2x8F(in vec2 data) {
	return dot(floor(data * max8f + 0.5), vec2(256.0, 1.0));
}

vec2 Unpack2x8F(in float data) {
	float x, y = modf(data * rcp(256.0), x) * 256.0;
	return vec2(x, y) * r255;
}

uint Packup2x8U(in vec2 data) {
	uvec2 u = uvec2(data * max8f + 0.5);
	return (u.x << 8) | u.y;
}

uint PackupDithered2x8U(in vec2 data, in float dither) {
	uvec2 u = uvec2(data * max8f + dither);
	return (u.x << 8) | u.y;
}

vec2 Unpack2x8U(in uint data) {
	return vec2(float(data >> 8), float(data & 0xFF)) * r255;
}

float Unpack2x8UX(in uint data) { return float(data >> 8) * r255; }
float Unpack2x8UY(in uint data) { return float(data & 0xFF) * r255; }

uint PackupR11G11B10(in vec3 data) {
	uvec3 u = uvec3(data * vec3(2047.0, 2047.0, 1023.0) + 0.5);
	return (u.x << 21) | (u.y << 10) | u.z;
}

vec3 UnpackR11G11B10(in uint data) {
	return vec3(float(data >> 21) * rcp(2047.0), float((data >> 10) & 0x7FF) * rcp(2047.0), float(data & 0x3FF) * rcp(1023.0));
}

// Modified from https://github.com/Jessie-LC/open-source-utility-code/blob/main/advanced/packing.glsl

// Octahedral Unit Vector encoding
// Intuitive, fast, and has very little error.
vec2 encodeUnitVector(in vec3 vector) {
	// Scale down to octahedron, project onto XY plane
    vector.xy /= dot(vec3(1.0), abs(vector));
	// Reflect -Z hemisphere folds over the diagonals
	vec2 encoded = vector.z <= 0.0 ? (1.0 - abs(vector.yx)) * vec2(vector.x >= 0.0 ? 1.0 : -1.0, vector.y >= 0.0 ? 1.0 : -1.0) : vector.xy;
	// Scale to [0, 1]
	return encoded * 0.5 + 0.5;
}

vec3 decodeUnitVector(in vec2 encoded) {
	// Scale to [-1, 1]
	encoded = encoded * 2.0 - 1.0;
	// Exctract Z component
	vec3 vector = vec3(encoded, 1.0 - abs(encoded.x) - abs(encoded.y));
	// Reflect -Z hemisphere folds over the diagonals
	float t = max(-vector.z, 0.0);
	vector.xy += vec2(vector.x >= 0.0 ? -t : t, vector.y >= 0.0 ? -t : t);
	// Normalize and return
	return normalize(vector);
}

vec2 ToSphereMap(in vec3 dir) {
    return vec2(atan(-dir.x, -dir.z) * rTAU + 0.5, fastAcos(dir.y) * rPI);
}

vec3 FromSphereMap(in vec2 coord) {
    coord.y *= PI;
    return vec3(sincos(coord.x * TAU) * sin(coord.y), cos(coord.y)).xzy;
}
