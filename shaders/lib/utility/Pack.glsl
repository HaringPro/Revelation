#if defined MC_NORMAL_MAP
	void DecodeNormalTex(inout vec3 normalTex) {
		normalTex = normalTex * 2.0 - 1.0;
		#if TEXTURE_FORMAT == 0
			normalTex.z = sqrt(saturate(oms(sdot(normalTex.xy))));
		#endif
		normalTex.xy = uintBitsToFloat(floatBitsToUint(saturate(abs(normalTex.xy) - rcp255)) ^ (floatBitsToUint(normalTex.xy) & 0x80000000u));
	}
#endif

float Packup2x8(vec2 data) {
	return dot(floor(data * 255.0 + 0.5), vec2(256.0 / 65535.0, 1.0 / 65535.0));
}

float PackupDithered2x8(vec2 data, float dither) {
	return dot(floor(data * 255.0 + dither), vec2(256.0 / 65535.0, 1.0 / 65535.0));
}

vec2 Unpack2x8(float data) {
	float x, y = modf(data * (65535.0 / 256.0), x) * 256.0;
	return vec2(x, y) * rcp255;
}

float Packup2x8X(float data) { return floor(data * (65535.0 / 256.0)) * rcp255; }
float Packup2x8Y(float data) { return fract(data * (65535.0 / 256.0)) * (256.0 * rcp255); }

uint Packup2x8U(vec2 data) {
	uvec2 u = uvec2(data * 255.0 + 0.5);
	return bitfieldInsert(u.x, u.y, 8, 8);
}

uint PackupDithered2x8U(vec2 data, float dither) {
	uvec2 u = uvec2(data * 255.0 + dither);
	return bitfieldInsert(u.x, u.y, 8, 8);
}

vec2 Unpack2x8U(uint data) {
	return uvec2(bitfieldExtract(data, 0, 8), bitfieldExtract(data, 8, 8)) * rcp255;
}

float Unpack2x8UX(uint data) { return bitfieldExtract(data, 0, 8) * rcp255; }
float Unpack2x8UY(uint data) { return bitfieldExtract(data, 8, 8) * rcp255; }

//================================================================================================//

// Octahedral encoding
// https://jcgt.org/published/0003/02/01/paper.pdf
vec2 OctEncodeSnorm(vec3 dir) {
	dir.xy *= 1.0 / dot(vec3(1.0), abs(dir));
	vec2 oct = mix(signMul(1.0 - abs(dir.yx), dir.xy), dir.xy, step(0.0, dir.z));
	return oct;
}

vec3 OctDecodeSnorm(vec2 oct) {
	vec3 dir = vec3(oct.x, oct.y, 1.0 - abs(oct.x) - abs(oct.y));
	float t = saturate(-dir.z);
	dir.xy += mix(vec2(t), vec2(-t), step(0.0, dir.xy));
	return normalize(dir);
}

vec2 OctEncodeUnorm(vec3 dir) {
	return OctEncodeSnorm(dir) * 0.5 + 0.5;
}

vec3 OctDecodeUnorm(vec2 oct) {
	return OctDecodeSnorm(oct * 2.0 - 1.0);
}

// Mercator projection
vec2 ProjectMercator(vec3 dir) {
	float phi = atan(dir.x, dir.z); // Longitude
	float theta = fastAsin(dir.y); // Latitude

	vec2 uv = vec2(phi, log(tan(fma(theta, 0.5, PI * 0.25))));
	return uv * rTAU + 0.5; // Scale to [0, 1]
}

vec3 UnprojectMercator(vec2 uv) {
	uv = uv * TAU - PI; // Scale to [-π, π]
	float phi = uv.x; // Longitude
	float theta = atan(exp(uv.y)) * 2.0 - hPI; // Latitude

	return vec3(sincos(phi) * cos(theta), sin(theta)).yzx;
}

// Equirectangular projection
vec2 ProjectEquirectanglar(vec3 dir) {
	float phi = atan(dir.x, dir.z); // Longitude
	float theta = fastAsin(dir.y) * 2.0; // Latitude

	return vec2(phi, theta) * rTAU + 0.5;
}

vec3 UnprojectEquirectanglar(vec2 uv) {
	uv = uv * 2.0 - 1.0; // Scale to [-1, 1]
	float phi = uv.x * PI; // Longitude
	float theta = uv.y * hPI; // Latitude

	return vec3(sincos(phi) * cos(theta), sin(theta)).yzx;
}

vec2 ProjectEquirectanglarNonlinear(vec3 dir) {
	float phi = atan(dir.x, dir.z); // Longitude
	float theta = fastAsin(dir.y); // Latitude
	theta = signI(theta) * sqrt(abs(theta)); // Non-linear mapping

	return vec2(phi, theta) * rTAU + 0.5;
}

vec3 UnprojectEquirectanglarNonlinear(vec2 uv) {
	uv = uv * 2.0 - 1.0; // Scale to [-1, 1]
	float phi = uv.x * PI; // Longitude
	float theta = signI(uv.y) * sqr(uv.y * hPI); // Latitude

	return vec3(sincos(phi) * cos(theta), sin(theta)).yzx;
}

// [+X][+Y][+Z]
// [-X][-Y][-Z]

vec2 ProjectCubemap(vec3 dir, float tileSize) {
	float scale = 0.5 - 1.0 / tileSize;
	vec3 dirAbs = abs(dir);

	vec3 mask = step(vec3(maxOf(dirAbs)), dirAbs);
	scale /= dot(mask, dirAbs);

	vec3 scaleMasked = scale * mask;
	float offsetX = dot(vec3(0.0, 1.0, 2.0), mask);
	float offsetY = step(0.0, dot(mask, dir));

	vec2 uv = dir.yz * scaleMasked.x;
	uv += dir.xz * scaleMasked.y;
	uv += dir.xy * scaleMasked.z;
	uv += vec2(offsetX, offsetY);

	return uv * rcp(vec2(3.0, 2.0)) + 0.5 / vec2(3.0, 2.0);
}

vec3 UnprojectCubemap(vec2 uv, float tileSize) {
	uv = uv * vec2(3.0, 2.0) - 0.5;
	float scale = tileSize / (0.5 * tileSize - 1.0);

	float signAxis = step(0.5, uv.y);
	vec2 temp = vec2((uv.y - signAxis) * scale, signAxis * 2.0 - 1.0);

	vec3 dir;
	if (uv.x < 0.5) {
		// X
		dir.y = uv.x * scale;
		dir.zx = temp;
	} else if (uv.x < 1.5) {
		// Y
		dir.x = uv.x * scale - scale;
		dir.zy = temp;
	} else {
		// Z
		dir.x = uv.x * scale - scale * 2.0;
		dir.yz = temp;
	}

	return normalize(dir);
}

//================================================================================================//

// RGBE8 encoding
// Exponent range: [-128, 127]
vec4 EncodeRGBE8(vec3 data) {
	float e = ceil(log2(maxOf(data)));
	return vec4(data * exp2(-e), e * rcp255 + 127.0 * rcp255);
}

vec3 DecodeRGBE8(vec4 data) {
	return data.rgb * exp2(data.a * 255.0 - 127.0);
}

uint EncodeRGBE8U(vec3 data) {
	return packUnorm4x8(EncodeRGBE8(data));
}

vec3 DecodeRGBE8U(uint data) {
	return DecodeRGBE8(unpackUnorm4x8(data));
}

// Ericson, Christer. "Converting RGB to LogLuv in a fragment shader". 2007.
// https://realtimecollisiondetection.net/blog/?p=15

// M matrix, for encoding
const mat3 logLuvM = mat3(
	0.2209, 0.3390, 0.4184,
	0.1138, 0.6780, 0.7319,
	0.0102, 0.1130, 0.2969
);

// Inverse M matrix, for decoding
const mat3 logLuvInverseM = mat3(
	6.0014, -2.7008, -1.7996,
-1.3320,  3.1029, -5.7721,
	0.3008, -1.0882,  5.6268
);

vec4 LogLuvEncode(vec3 rgb) {
	vec4 result;
	vec3 Xp_Y_XYZp = max(logLuvM * rgb, EPS);
	result.xy = Xp_Y_XYZp.xy / Xp_Y_XYZp.z;

	float Le = log2(Xp_Y_XYZp.y) * 2.0 + 127.0;

	result.w = fract(Le);
	result.z = (Le - (floor(result.w * 255.0)) * rcp255) * rcp255;
	return result;
}

vec3 LogLuvDecode(vec4 logLuv) {
	float Le = logLuv.z * 255.0 + logLuv.w;

	vec3 Xp_Y_XYZp;
	Xp_Y_XYZp.y = exp2(Le * 0.5 - 127.0 * 0.5);
	Xp_Y_XYZp.z = Xp_Y_XYZp.y / logLuv.y;
	Xp_Y_XYZp.x = logLuv.x * Xp_Y_XYZp.z;

	return max0(logLuvInverseM * Xp_Y_XYZp);
}

uint LogLuvEncodeU(vec3 data) {
	return packUnorm4x8(LogLuvEncode(data));
}

vec3 LogLuvDecodeU(uint data) {
	return LogLuvDecode(unpackUnorm4x8(data));
}
