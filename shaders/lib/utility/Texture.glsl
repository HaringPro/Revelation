// From https://iquilezles.org/www/articles/texture/texture.htm
vec4 textureSmoothFilter(in sampler2D tex, in vec2 coord) {
	vec2 res = vec2(textureSize(tex, 0));

	coord = coord * res + 0.5;

	vec2 i, f = modf(coord, i);
	f *= f * f * (f * (f * 6.0 - 15.0) + 10.0);
	coord = i + f;

	coord = (coord - 0.5) / res;
	return textureLod(tex, coord, 0.0);
}

// From https://jvm-gaming.org/t/glsl-simple-fast-bicubic-filtering-shader-function/52549
vec4 cubic(in float v){
    vec4 n = vec4(1.0, 2.0, 3.0, 4.0) - v;
    vec4 s = n * n * n;
    float x = s.x;
    float y = s.y - 4.0 * s.x;
    float z = s.z - 4.0 * s.y + 6.0 * s.x;
    float w = 6.0 - x - y - z;
    return vec4(x, y, z, w) * rcp(6.0);
}

vec4 textureBicubic(in sampler2D tex, in vec2 coord) {
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

vec4 textureBicubicLod(in sampler2D tex, in vec2 coord, in int lod) {
	vec2 res = vec2(textureSize(tex, lod));

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

vec4 textureSmooth(in sampler2D tex, in vec2 coord) {
	vec2 res = vec2(textureSize(tex, 0));
	vec2 pixelSize = 1.0 / res;

	coord = coord * res - 0.5;

    vec2 p = floor(coord);
    vec2 f = coord - p;

	p *= pixelSize;
    vec4 sample0 = texture(tex, p);
    vec4 sample1 = textureOffset(tex, p, ivec2(1, 0));
    vec4 sample2 = textureOffset(tex, p, ivec2(0, 1));
    vec4 sample3 = textureOffset(tex, p, ivec2(1, 1));

    return mix(mix(sample0, sample1, f.x), mix(sample2, sample3, f.x), f.y);
}