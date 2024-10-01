/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

	Pass: Cloud CBR temporal upscaling
	Reference: https://www.intel.com/content/dam/develop/external/us/en/documents/checkerboard-rendering-for-real-time-upscaling-on-intel-integrated-graphics.pdf
			   https://developer.nvidia.com/sites/default/files/akamai/gameworks/samples/DeinterleavedTexturing.pdf

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 9 */
layout (location = 0) out vec4 cloudOut;

#if !defined SSPT_ENABLED || !defined SVGF_ENABLED
/* RENDERTARGETS: 9,14 */
layout (location = 1) out vec3 historyBuffer; // xy: moments history, z: inverse depth
#endif

//======// Uniform //=============================================================================//

uniform sampler2D noisetex;

uniform sampler2D colortex1; // Scene history

uniform sampler2D colortex9; // Previous clouds
uniform sampler2D colortex13; // Current clouds

uniform sampler2D colortex14; // Depth history

uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;

uniform float near;
uniform float far;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform vec2 viewSize;
uniform vec2 viewPixelSize;
uniform vec2 taaOffset;

uniform int frameCounter;
uniform bool worldTimeChanged;

//======// Function //============================================================================//

#include "/lib/universal/Transform.glsl"
#include "/lib/universal/Fetch.glsl"
#include "/lib/universal/Noise.glsl"
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

	coord *= res;

    vec2 uv = floor(coord - 0.5) + 0.5;
    vec2 fp = coord - uv;
    uv /= res;

    vec4 sum = vec4(0.0);
	float weightSum = 0.0;

    for (int x = -2; x <= 2; ++x) {
        float fx = lanczos(float(x) - fp.x);

        for (int y = -2; y <= 2; ++y) {
			float fy = lanczos(float(y) - fp.y);

			vec4 sampleData = textureOffset(tex, uv, ivec2(x, y));
            sum += sampleData * fx * fy;
			weightSum += fx * fy;
        }
    }

    return sum / weightSum;
}

//======// Main //================================================================================//
void main() {
    ivec2 screenTexel = ivec2(gl_FragCoord.xy);

	float depth = sampleDepth(screenTexel);

	#if !defined SSPT_ENABLED || !defined SVGF_ENABLED
		historyBuffer.rg = texelFetch(colortex14, screenTexel, 0).rg;
		historyBuffer.b = 1.0 - depth; // Inverse depth
	#endif

	if (depth > 0.999999) {
		vec2 screenCoord = gl_FragCoord.xy * viewPixelSize;
		vec2 prevCoord = Reproject(vec3(screenCoord, 1.0)).xy;

		if (saturate(prevCoord) != prevCoord // Offscreen invalidation
		 || maxOf(textureGather(colortex14, prevCoord, 2)) > 1e-6 // Previous depth invalidation
    	//  || (gbufferProjection[0][0] - gbufferPreviousProjection[0][0]) > 0.25 // Fov change invalidation
		 || worldTimeChanged) {
			cloudOut = textureBicubic(colortex13, min(screenCoord * rcp(float(CLOUD_CBR_SCALE)), rcp(float(CLOUD_CBR_SCALE)) - viewPixelSize));
		} else {
			vec4 prevData = textureCatmullRomFast(colortex9, prevCoord, 0.6);

			// Checkerboard upscaling
			ivec2 offset = checkerboardOffset[frameCounter % cloudRenderArea];
			if (screenTexel % CLOUD_CBR_SCALE == offset) {
				float frameIndex = min(texture(colortex1, prevCoord).a, CLOUD_MAX_BLENDED_FRAMES);

				// Accumulate enough frame for checkerboard pattern
				float blendWeight = 1.0 - rcp(max(frameIndex - cloudRenderArea, 1.0));

				// Offcenter rejection
				vec2 distToPixelCenter = 1.0 - abs(fract(prevCoord * viewSize) * 2.0 - 1.0);
				blendWeight *= sqrt(distToPixelCenter.x * distToPixelCenter.y) * 0.7 + 0.3;

				ivec2 currTexel = clamp((screenTexel - offset) / CLOUD_CBR_SCALE, ivec2(0), ivec2(viewSize) / CLOUD_CBR_SCALE - 1);
				cloudOut = mix(texelFetch(colortex13, currTexel, 0), prevData, blendWeight);

			} else cloudOut = prevData;
		}
	} else {
		cloudOut = vec4(0.0, 0.0, 0.0, 1.0);
	}
}