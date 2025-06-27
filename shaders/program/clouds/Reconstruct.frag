/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

	Pass: Temporal reconstruct clouds
	Reference: https://www.intel.com/content/dam/develop/external/us/en/documents/checkerboard-rendering-for-real-time-upscaling-on-intel-integrated-graphics.pdf
			   https://developer.nvidia.com/sites/default/files/akamai/gameworks/samples/DeinterleavedTexturing.pdf

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 9,13 */
layout (location = 0) out vec4 cloudOut;
layout (location = 1) out uint frameOut;

//======// Uniform //=============================================================================//

#include "/lib/universal/Uniform.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Transform.glsl"
#include "/lib/universal/Fetch.glsl"
#include "/lib/universal/Random.glsl"
#include "/lib/universal/Offset.glsl"

vec4 textureCatmullRom(in sampler2D tex, in vec2 coord) {
	vec2 res = vec2(textureSize(tex, 0));
	vec2 pixelSize = 1.0 / res;

	vec2 position = coord * res;
	vec2 centerPosition = floor(position - 0.5) + 0.5;

	vec2 f = position - centerPosition;

	vec2 w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
	vec2 w1 = 1.0 + f * f * (-2.5 + 1.5 * f);
	vec2 w2 = f * (0.5 + f * (2.0 - 1.5 * f));
	vec2 w3 = f * f * (-0.5 + 0.5 * f);

	vec2 w12 = w1 + w2;

	vec2 tc0 = pixelSize * (centerPosition - 1.0);
	vec2 tc3 = pixelSize * (centerPosition + 2.0);
	vec2 tc12 = pixelSize * (centerPosition + w2 * rcp(w12));

	vec4 color = vec4(0.0);
	color += textureLod(tex, vec2(tc0.x, tc0.y), 0) * w0.x * w0.y;
	color += textureLod(tex, vec2(tc12.x, tc0.y), 0) * w12.x * w0.y;
	color += textureLod(tex, vec2(tc3.x, tc0.y), 0) * w3.x * w0.y;

	color += textureLod(tex, vec2(tc0.x, tc12.y), 0) * w0.x * w12.y;
	color += textureLod(tex, vec2(tc12.x, tc12.y), 0) * w12.x * w12.y;
	color += textureLod(tex, vec2(tc3.x, tc12.y), 0) * w3.x * w12.y;

	color += textureLod(tex, vec2(tc0.x, tc3.y), 0) * w0.x * w3.y;
	color += textureLod(tex, vec2(tc12.x, tc3.y), 0) * w12.x * w3.y;
	color += textureLod(tex, vec2(tc3.x, tc3.y), 0) * w3.x * w3.y;

	return color;
}

// Approximation from SMAA presentation from siggraph 2016
vec4 textureCatmullRomFast(in sampler2D tex, in vec2 coord, in const float sharpness) {
    vec2 position = viewSize * coord;
    vec2 centerPosition = floor(position - 0.5) + 0.5;
    vec2 f = position - centerPosition;
    vec2 f2 = f * f;
    vec2 f3 = f * f2;

    vec2 w0 = -sharpness        * f3 + 2.0 * sharpness         * f2 - sharpness * f;
    vec2 w1 = (2.0 - sharpness) * f3 - (3.0 - sharpness)       * f2 + 1.0;
    vec2 w2 = (sharpness - 2.0) * f3 + (3.0 - 2.0 * sharpness) * f2 + sharpness * f;
    vec2 w3 = sharpness         * f3 - sharpness               * f2;

    vec2 w12 = w1 + w2;

    vec2 tc0 = viewPixelSize * (centerPosition - 1.0);
    vec2 tc3 = viewPixelSize * (centerPosition + 2.0);
    vec2 tc12 = viewPixelSize * (centerPosition + w2 / w12);

    float l0 = w12.x * w0.y;
    float l1 = w0.x  * w12.y;
    float l2 = w12.x * w12.y;
    float l3 = w3.x  * w12.y;
    float l4 = w12.x * w3.y;

    vec4 color =  texture(tex, vec2(tc12.x, tc0.y )) * l0
                + texture(tex, vec2(tc0.x,  tc12.y)) * l1
                + texture(tex, vec2(tc12.x, tc12.y)) * l2
                + texture(tex, vec2(tc3.x,  tc12.y)) * l3
                + texture(tex, vec2(tc12.x, tc3.y )) * l4;

    return color / (l0 + l1 + l2 + l3 + l4);
}

float sinc(float x) {
    return sin(PI * x) / (PI * x);
}

float lanczos(float x) {
    if (abs(x) < 1e-6) return 1.0;
    else return sinc(x) * sinc(x * rcp(3.0));
}

vec4 textureLanczos(in sampler2D tex, in vec2 coord) {
	vec2 res = vec2(textureSize(tex, 0));
	vec2 pixelSize = 1.0 / res;

	coord *= res;

    vec2 uv = floor(coord - 0.5) + 0.5;
    vec2 fp = coord - uv;

    vec4 sum = vec4(0.0);
	float weightSum = 0.0;

    for (int x = -2; x <= 2; ++x) {
        float fx = lanczos(float(x) - fp.x);

        for (int y = -2; y <= 2; ++y) {
			float fy = lanczos(float(y) - fp.y);

			vec4 sampleData = texture(tex, (uv + vec2(x, y)) * pixelSize);
            sum += sampleData * fx * fy;
			weightSum += fx * fy;
        }
    }

    return sum / weightSum;
}

#define currentLoad(offset) texelFetchOffset(colortex2, currTexel, 0, offset)

#define mean(a, b, c, d, e, f, g, h, i) (a + b + c + d + e + f + g + h + i) * rcp(9.0)
#define sqrMean(a, b, c, d, e, f, g, h, i) (a * a + b * b + c * c + d * d + e * e + f * f + g * g + h * h + i * i) * rcp(9.0)

vec3 ReprojectClouds(in vec2 coord, in float depth) {
	vec3 cloudPos = ScreenToViewVectorRaw(coord) * depth;
	cloudPos = transMAD(gbufferModelViewInverse, cloudPos); // To world space
	cloudPos += cameraPosition - previousCameraPosition; // To previous frame's world space
    cloudPos = transMAD(gbufferPreviousModelView, cloudPos); // To previous frame's view space
	cloudPos = projMAD(gbufferPreviousProjection, cloudPos) * rcp(-cloudPos.z); // To previous frame's NDC space

    return cloudPos * 0.5 + 0.5;
}

//======// Main //================================================================================//
void main() {
	cloudOut = vec4(0.0, 0.0, 0.0, 1.0);
	frameOut = 0u;

    ivec2 screenTexel = ivec2(gl_FragCoord.xy);
	float depth = loadDepth0(screenTexel);
	#if defined DISTANT_HORIZONS
		if (depth > 0.999999) depth = loadDepth0DH(screenTexel);
	#endif

	if (depth > 0.999999 || depth < 0.56) {
		frameOut = 1u;

		vec2 screenCoord = gl_FragCoord.xy * viewPixelSize;

		const float currScale = rcp(float(CLOUD_CBR_SCALE));
		vec2 currCoord = min(screenCoord * currScale, currScale - viewPixelSize);

		float cloudDepth = minOf(textureGather(colortex3, currCoord, 0));

		vec2 prevCoord = ReprojectClouds(screenCoord, cloudDepth).xy;
		uint frameIndex = texture(colortex13, prevCoord).x;

		bool disocclusion = worldTimeChanged;
		// Offscreen invalidation
		disocclusion = disocclusion || saturate(prevCoord) != prevCoord;
		// Previous land invalidation
		disocclusion = disocclusion || frameIndex < 1u;
		// Fov change invalidation
		// disocclusion = disocclusion || (gbufferProjection[0].x - gbufferPreviousProjection[0].x) > 0.25;

		if (disocclusion) {
			cloudOut = texture(colortex2, currCoord);
		} else {
			vec4 prevData = textureCatmullRomFast(colortex9, prevCoord, 0.65);
			// vec4 prevData = textureSmoothFilter(colortex9, prevCoord);
			prevData = satU16f(prevData); // Fix black border artifacts
			frameOut += frameIndex;

			ivec2 currTexel = clamp(screenTexel / CLOUD_CBR_SCALE, ivec2(0), ivec2(viewSize) / CLOUD_CBR_SCALE - 1);
			vec4 currData = texelFetch(colortex2, currTexel, 0);

			// Variance clip
			#ifdef CLOUD_VARIANCE_CLIP
			float velocityWeight = sqr(cameraVelocity * rcp(frameTime));
			velocityWeight /= 1.0 + velocityWeight;

			if (velocityWeight > 0.125) {
				vec4 sample1 = currentLoad(ivec2(-1,  1));
				vec4 sample2 = currentLoad(ivec2( 0,  1));
				vec4 sample3 = currentLoad(ivec2( 1,  1));
				vec4 sample4 = currentLoad(ivec2(-1,  0));
				vec4 sample5 = currentLoad(ivec2( 1,  0));
				vec4 sample6 = currentLoad(ivec2(-1, -1));
				vec4 sample7 = currentLoad(ivec2( 0, -1));
				vec4 sample8 = currentLoad(ivec2( 1, -1));

				vec4 clipAvg = mean(currData, sample1, sample2, sample3, sample4, sample5, sample6, sample7, sample8);
				vec4 clipAvg2 = sqrMean(currData, sample1, sample2, sample3, sample4, sample5, sample6, sample7, sample8);

				vec4 variance = sqrt(abs(clipAvg2 - clipAvg * clipAvg)) * 2.0;
				vec4 clipMin = clipAvg - variance;
				vec4 clipMax = clipAvg + variance;

				prevData = mix(prevData, clamp(prevData, clipMin, clipMax), velocityWeight);
			}
			#endif

			// Checkerboard upscaling
			ivec2 offset = cloudCbrOffset[frameCounter % cloudRenderArea];
			if (screenTexel % CLOUD_CBR_SCALE == offset) {
				// Accumulate enough frame for checkerboard pattern
				float blendWeight = 1.0 - rcp(max(float(min(frameOut, CLOUD_MAX_ACCUM_FRAMES)) - cloudRenderArea, 1.0));

				// Offcenter rejection
				vec2 pixelCenterDist = 1.0 - abs(fract(prevCoord * viewSize) * 2.0 - 1.0);
				blendWeight *= sqrt(pixelCenterDist.x * pixelCenterDist.y) * 0.5 + 0.5;

				#ifndef CLOUD_VARIANCE_CLIP
					// Camera movement rejection
					blendWeight *= exp2(-cameraVelocity * (0.125 / frameTime)) * 0.75 + 0.25;
				#endif

				// Blend with current frame
				cloudOut = mix(currData, prevData, saturate(blendWeight));
			} else cloudOut = prevData;
		}
	}
}