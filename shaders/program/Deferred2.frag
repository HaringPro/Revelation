/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

	Pass: Clouds temporal upscaling
	Reference: https://github.com/sixthsurge/photon
	Statement: I refer to the photon shader because of its MIT license, if it violates the license, I will rectify it immediately.

	The MIT License

	Copyright © 2023 SixthSurge

	Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

	The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 9,14 */
layout (location = 0) out vec4 cloudOut;
layout (location = 1) out vec3 historyBuffer;

//======// Uniform //=============================================================================//

uniform sampler2D noisetex;

uniform sampler2D colortex1; // Scene history

uniform sampler2D colortex3; // Current clouds
uniform sampler2D colortex9; // Previous clouds

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

#include "/lib/utility/Transform.glsl"
#include "/lib/utility/Fetch.glsl"
#include "/lib/utility/Noise.glsl"
#include "/lib/utility/Offset.glsl"

vec4 textureCatmullRom(in sampler2D tex, in vec2 coord) {
	vec2 res = textureSize(tex, 0);
	vec2 screenPixelSize = 1.0 / res;

	vec2 position = coord * res;
	vec2 centerPosition = floor(position - 0.5) + 0.5;

	vec2 f = position - centerPosition;

	vec2 w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
	vec2 w1 = 1.0 + f * f * (-2.5 + 1.5 * f);
	vec2 w2 = f * (0.5 + f * (2.0 - 1.5 * f));
	vec2 w3 = f * f * (-0.5 + 0.5 * f);

	vec2 w12 = w1 + w2;

	vec2 tc0 = screenPixelSize * (centerPosition - 1.0);
	vec2 tc3 = screenPixelSize * (centerPosition + 2.0);
	vec2 tc12 = screenPixelSize * (centerPosition + w2 * rcp(w12));

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

//======// Main //================================================================================//
void main() {
    ivec2 screenTexel = ivec2(gl_FragCoord.xy);

	float depth = sampleDepth(screenTexel);

	historyBuffer.rg = texelFetch(colortex14, screenTexel, 0).rg;
	historyBuffer.b = 1.0 - depth;

	if (depth > 0.999999) {
		vec2 screenCoord = gl_FragCoord.xy * viewPixelSize;
		vec2 prevCoord = Reproject(vec3(screenCoord, 1.0)).xy;

		if (saturate(prevCoord) != prevCoord // Offscreen invalidation
		 || maxOf(textureGather(colortex14, prevCoord, 2)) > 1e-6 // Previous depth invalidation
		 || worldTimeChanged) {
			cloudOut = textureBicubic(colortex3, min(screenCoord * rcp(float(CLOUD_TEMPORAL_UPSCALING)), rcp(float(CLOUD_TEMPORAL_UPSCALING)) - viewPixelSize));
		} else {
			ivec2 offset = checkerboardOffset[frameCounter % cloudRenderArea];

			float frameIndex = min(texelFetch(colortex1, rawCoord(prevCoord), 0).a, CLOUD_MAX_BLENDED_FRAMES);

			// Accumulate enough frame for checkerboard pattern
			float blendWeight = 1.0 - rcp(max(frameIndex - cloudRenderArea, 1.0));

			// Camera movement rejection
			float cameraMovement = exp2(-24.0 * distance(cameraPosition, previousCameraPosition));
			blendWeight *= cameraMovement * 0.5 + 0.5;

			// Offcenter rejection
			vec2 distanceToPixelCenter = 1.0 - abs(fract(prevCoord * viewSize) * 2.0 - 1.0);
			blendWeight *= sqrt(distanceToPixelCenter.x * distanceToPixelCenter.y) * 0.5 + 0.5;

			vec4 prevData = textureSmoothFilter(colortex9, prevCoord);

			// Checkerboard upscaling
			if (screenTexel % CLOUD_TEMPORAL_UPSCALING == offset) {
				ivec2 currTexel = clamp((screenTexel - offset) / CLOUD_TEMPORAL_UPSCALING, ivec2(0), ivec2(viewSize) / CLOUD_TEMPORAL_UPSCALING - 1);
				cloudOut = mix(texelFetch(colortex3, currTexel, 0), prevData, blendWeight);
			} else cloudOut = prevData;
		}
	} else {
		cloudOut = vec4(0.0, 0.0, 0.0, 1.0);
	}
}