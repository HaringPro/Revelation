// From https://iquilezles.org/www/articles/texture/texture.htm
vec4 textureSmoothFilter(sampler2D tex, vec2 coord) {
	vec2 res = vec2(textureSize(tex, 0));

	coord = coord * res + 0.5;

	vec2 i, f = modf(coord, i);
	f *= f * f * (f * (f * 6.0 - 15.0) + 10.0);
	coord = i + f;

	coord = (coord - 0.5) / res;
	return textureLod(tex, coord, 0.0);
}

// From https://jvm-gaming.org/t/glsl-simple-fast-bicubic-filtering-shader-function/52549
vec4 cubic(float v) {
	vec4 n = vec4(1.0, 2.0, 3.0, 4.0) - v;
	vec4 s = n * n * n;
	float x = s.x;
	float y = s.y - 4.0 * s.x;
	float z = s.z - 4.0 * s.y + 6.0 * s.x;
	float w = 6.0 - x - y - z;
	return vec4(x, y, z, w) * rcp(6.0);
}

vec4 textureBicubic(sampler2D tex, vec2 coord) {
	vec2 res = vec2(textureSize(tex, 0));

	coord = coord * res - 0.5;

	vec2 fxy = fract(coord);
	coord -= fxy;

	vec4 xCubic = cubic(fxy.x);
	vec4 yCubic = cubic(fxy.y);

	vec4 c = coord.xxyy + vec2(-0.5, 1.5).xyxy;
	vec4 s = vec4(xCubic.xz + xCubic.yw, yCubic.xz + yCubic.yw);

	vec4 offset = c + vec4(xCubic.yw, yCubic.yw) / s;
	offset *= 1.0 / res.xxyy;

	vec4 sample0 = textureLod(tex, offset.xz, 0.0);
	vec4 sample1 = textureLod(tex, offset.yz, 0.0);
	vec4 sample2 = textureLod(tex, offset.xw, 0.0);
	vec4 sample3 = textureLod(tex, offset.yw, 0.0);

	float sx = s.x / (s.x + s.y);
	float sy = s.z / (s.z + s.w);

	return mix(mix(sample3, sample2, sx), mix(sample1, sample0, sx), sy);
}

vec4 textureBicubicLod(sampler2D tex, vec2 coord, float lod) {
	vec2 res = vec2(textureSize(tex, 0));

	coord = coord * res - 0.5;

	vec2 fxy = fract(coord);
	coord -= fxy;

	vec4 xCubic = cubic(fxy.x);
	vec4 yCubic = cubic(fxy.y);

	vec4 c = coord.xxyy + vec2(-0.5, 1.5).xyxy;
	vec4 s = vec4(xCubic.xz + xCubic.yw, yCubic.xz + yCubic.yw);

	vec4 offset = c + vec4(xCubic.yw, yCubic.yw) / s;
	offset *= 1.0 / res.xxyy;

	vec4 sample0 = textureLod(tex, offset.xz, lod);
	vec4 sample1 = textureLod(tex, offset.yz, lod);
	vec4 sample2 = textureLod(tex, offset.xw, lod);
	vec4 sample3 = textureLod(tex, offset.yw, lod);

	float sx = s.x / (s.x + s.y);
	float sy = s.z / (s.z + s.w);

	return mix(mix(sample3, sample2, sx), mix(sample1, sample0, sx), sy);
}

vec4 catmullRom(float f) {
	return vec4(
		f * (-0.5 + f * (1.0 - 0.5 * f)),
		1.0 + f * f * (-2.5 + 1.5 * f),
		f * (0.5 + f * (2.0 - 1.5 * f)),
		f * f * (-0.5 + 0.5 * f)
	);
}

// https://gist.github.com/TheRealMJP/bc503b0b87b643d3505d41eab8b332ae
// The following code is licensed under the MIT license

// Samples a texture with Catmull-Rom filtering, using 9 texture fetches instead of 16.
// See http://vec3.ca/bicubic-filtering-in-fewer-taps/ for more details
vec4 textureCatmullRom(sampler2D tex, vec2 uv) {
	vec2 res = vec2(textureSize(tex, 0));
	vec2 pixelSize = 1.0 / res;

	vec2 samplePos = uv * res;
	vec2 texPos1 = floor(samplePos - 0.5) + 0.5;

	vec2 f = samplePos - texPos1;

	vec2 w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
	vec2 w1 = 1.0 + f * f * (-2.5 + 1.5 * f);
	vec2 w2 = f * (0.5 + f * (2.0 - 1.5 * f));
	vec2 w3 = f * f * (-0.5 + 0.5 * f);

	vec2 w12 = w1 + w2;
	vec2 offset12 = w2 / (w1 + w2);

	vec2 texPos0  = texPos1 - 1.0;
	vec2 texPos3  = texPos1 + 2.0;
	vec2 texPos12 = texPos1 + offset12;

	texPos0  *= pixelSize;
	texPos3  *= pixelSize;
	texPos12 *= pixelSize;

	vec4 result = vec4(0.0);
	result += texture(tex, vec2(texPos0.x , texPos0.y)) * w0.x  * w0.y;
	result += texture(tex, vec2(texPos12.x, texPos0.y)) * w12.x * w0.y;
	result += texture(tex, vec2(texPos3.x , texPos0.y)) * w3.x  * w0.y;

	result += texture(tex, vec2(texPos0.x , texPos12.y)) * w0.x  * w12.y;
	result += texture(tex, vec2(texPos12.x, texPos12.y)) * w12.x * w12.y;
	result += texture(tex, vec2(texPos3.x , texPos12.y)) * w3.x  * w12.y;

	result += texture(tex, vec2(texPos0.x , texPos3.y)) * w0.x  * w3.y;
	result += texture(tex, vec2(texPos12.x, texPos3.y)) * w12.x * w3.y;
	result += texture(tex, vec2(texPos3.x , texPos3.y)) * w3.x  * w3.y;
	return result;
}

// Approximation from SMAA presentation [Jimenez 2016]
vec4 textureCatmullRomFast(sampler2D tex, vec2 coord) {
	vec2 res = vec2(textureSize(tex, 0));
	vec2 pixelSize = 1.0 / res;

	vec2 pos = coord * res;
	vec2 tc1 = floor(pos - 0.5) + 0.5;
	vec2 f  = pos - tc1;
	vec2 f2 = f * f;
	vec2 f3 = f * f2;

	const float c = 0.5;
	vec2 w0  = -c         * f3 +  2.0 * c        * f2 - c * f;
	vec2 w1  =  (2.0 - c) * f3 - (3.0 - c)       * f2 + 1.0;
	vec2 w2  = -(2.0 - c) * f3 + (3.0 - 2.0 * c) * f2 + c * f;
	vec2 w3  = c          * f3 - c               * f2;
	vec2 w12 = w1 + w2;

	vec2 tc0  = pixelSize * (tc1 - 1.0);
	vec2 tc3  = pixelSize * (tc1 + 2.0);
	vec2 tc12 = pixelSize * (tc1 + w2 / w12);

	vec4 s0 = texture(tex, vec2(tc12.x,  tc0.y));
	vec4 s1 = texture(tex, vec2(tc0.x,  tc12.y));
	vec4 s2 = texture(tex, vec2(tc12.x, tc12.y));
	vec4 s3 = texture(tex, vec2(tc3.x,  tc12.y));
	vec4 s4 = texture(tex, vec2(tc12.x,  tc3.y));

	float cw0 = w12.x * w0.y;
	float cw1 = w0.x  * w12.y;
	float cw2 = w12.x * w12.y;
	float cw3 = w3.x  * w12.y;
	float cw4 = w12.x * w3.y;

	s0 *= cw0;
	s1 *= cw1;
	s2 *= cw2;
	s3 *= cw3;
	s4 *= cw4;

	vec4 color = (s0 + s1 + s2 + s3 + s4) / (cw0 + cw1 + cw2 + cw3 + cw4);
	return color;
}

vec4 textureCatmullRomFastAntiRing(sampler2D tex, vec2 coord) {
	vec2 res = vec2(textureSize(tex, 0));
	vec2 pixelSize = 1.0 / res;

	vec2 pos = coord * res;
	vec2 tc1 = floor(pos - 0.5) + 0.5;
	vec2 f  = pos - tc1;
	vec2 f2 = f * f;
	vec2 f3 = f * f2;

	const float c = 0.5;
	vec2 w0  = -c         * f3 +  2.0 * c        * f2 - c * f;
	vec2 w1  =  (2.0 - c) * f3 - (3.0 - c)       * f2 + 1.0;
	vec2 w2  = -(2.0 - c) * f3 + (3.0 - 2.0 * c) * f2 + c * f;
	vec2 w3  = c          * f3 - c               * f2;
	vec2 w12 = w1 + w2;

	vec2 tc0  = pixelSize * (tc1 - 1.0);
	vec2 tc3  = pixelSize * (tc1 + 2.0);
	vec2 tc12 = pixelSize * (tc1 + w2 / w12);

	vec4 s0 = texture(tex, vec2(tc12.x,  tc0.y));
	vec4 s1 = texture(tex, vec2(tc0.x,  tc12.y));
	vec4 s2 = texture(tex, vec2(tc12.x, tc12.y));
	vec4 s3 = texture(tex, vec2(tc3.x,  tc12.y));
	vec4 s4 = texture(tex, vec2(tc12.x,  tc3.y));

	vec4 minColor = min3(min(s0, s1), min(s2, s3), s4);
	vec4 maxColor = max3(max(s0, s1), max(s2, s3), s4);

	float cw0 = w12.x * w0.y;
	float cw1 = w0.x  * w12.y;
	float cw2 = w12.x * w12.y;
	float cw3 = w3.x  * w12.y;
	float cw4 = w12.x * w3.y;

	s0 *= cw0;
	s1 *= cw1;
	s2 *= cw2;
	s3 *= cw3;
	s4 *= cw4;

	vec4 color = (s0 + s1 + s2 + s3 + s4) / (cw0 + cw1 + cw2 + cw3 + cw4);

	// Anti-ring from unity
	return clamp(color, minColor, maxColor);
}

float sinc(float x) {
	return sin(PI * x) / (PI * x);
}

float lanczos2(float x) {
	x = clamp(x, -2.0, 2.0);
	if (abs(x) < EPS) return 1.0;
	else return sinc(x) * sinc(x * 0.5);
}

vec4 textureLanczos(sampler2D tex, vec2 coord) {
	const int radius = 2;

	vec2 res = vec2(textureSize(tex, 0));
	coord = coord * res - 0.5;

	vec2 p = floor(coord);
	vec2 f = coord - p;

	ivec2 texel = ivec2(p);

	vec4 sum = vec4(0.0);
	float sumWeight = 0.0;

	for (int x = -radius; x <= radius; ++x) {
		float fx = lanczos2(float(x) - f.x);

		for (int y = -radius; y <= radius; ++y) {
			float fy = lanczos2(float(y) - f.y);
			float weight = fx * fy;

			vec4 sampleData = texelFetch(tex, texel + ivec2(x, y), 0);
			sum += sampleData * weight;
			sumWeight += weight;
		}
	}

	return sum * rcp(sumWeight);
}

vec3 textureRGBE8(sampler2D tex, vec2 coord) {
	vec2 res = vec2(textureSize(tex, 0));
	coord = coord * res - 0.5;

	ivec2 i = ivec2(floor(coord));
	vec2 f = coord - i;

	vec3 sample0 = DecodeRGBE8(texelFetch(tex, i, 0));
	vec3 sample1 = DecodeRGBE8(texelFetch(tex, i + ivec2(1, 0), 0));
	vec3 sample2 = DecodeRGBE8(texelFetch(tex, i + ivec2(0, 1), 0));
	vec3 sample3 = DecodeRGBE8(texelFetch(tex, i + ivec2(1, 1), 0));

	return mix(mix(sample0, sample1, f.x), mix(sample2, sample3, f.x), f.y);
}

vec4 textureTiling(sampler2D tex, vec2 coord) {
	vec2 p = coord - 0.5;

	vec2 weight0 = hermite(abs(fract(p) * 2.0 - 1.0));
	vec2 weight1 = hermite(abs(fract(p + vec2(0.5, 0.5)) * 2.0 - 1.0));
	vec2 weight2 = hermite(abs(fract(p + vec2(1.0, 0.5)) * 2.0 - 1.0));
	vec2 weight3 = hermite(abs(fract(p + vec2(0.5, 1.0)) * 2.0 - 1.0));

	vec4 sample0 = texture(tex, coord) * weight0.x * weight0.y;
	vec4 sample1 = texture(tex, coord + vec2(0.5, 0.5)) * weight1.x * weight1.y;
	vec4 sample2 = texture(tex, coord + vec2(1.0, 0.5)) * weight2.x * weight2.y;
	vec4 sample3 = texture(tex, coord + vec2(0.5, 1.0)) * weight3.x * weight3.y;

	return sample0 + sample1 + sample2 + sample3;
}
