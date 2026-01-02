/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

	Reference: https://publications.lib.chalmers.se/records/fulltext/241770/241770.pdf
			   https://www.advances.realtimerendering.com/s2019/slides_public_release.pptx

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 9,13 */
layout (location = 0) out vec4 cloudOut;
layout (location = 1) out uint frameOut;

//======// Uniform //=============================================================================//

uniform sampler2D cloudOriginTex;

#include "/lib/universal/Uniform.glsl"

//======// SSBO //================================================================================//

#include "/lib/universal/SSBO.glsl"

//======// Function //============================================================================//

#include "/lib/universal/Transform.glsl"
#include "/lib/universal/Fetch.glsl"
#include "/lib/universal/Random.glsl"

#include "/lib/atmosphere/Common.glsl"
#include "/lib/atmosphere/clouds/Common.glsl"

vec3 ReprojectClouds(in vec2 coord, in float depth) {
	vec3 cloudPos = ScreenToViewVectorRaw(coord) * depth;
	cloudPos = transMAD(gbufferModelViewInverse, cloudPos); // To world space

	vec3 motionVector = vec3(0.0);

	// Apply wind
	float radius = depth + viewerHeight;
	if (radius < cloudMidRadius) {
		// Low clouds
		const float windAngle = radians(CLOUD_LOW_WIND_ANGLE);
		const vec3 windDir = vec3(cos(windAngle), 0.5, sin(windAngle));
		const vec3 windVelocity = windDir * CLOUD_LOW_WIND_SPEED;
		motionVector -= windVelocity;
	} else if (radius < cloudHighRadius) {
		// Mid clouds
		const float windAngle = radians(CLOUD_MID_WIND_ANGLE);
		const vec2 windVelocity = vec2(cos(windAngle), sin(windAngle)) * CLOUD_MID_WIND_SPEED;
		motionVector.xz -= windVelocity;
	} else {
		// High clouds
		const float windAngle = radians(CLOUD_HIGH_WIND_ANGLE);
		const vec2 windVelocity = vec2(cos(windAngle), sin(windAngle)) * CLOUD_HIGH_WIND_SPEED;
		motionVector.xz -= windVelocity;
	}
	motionVector *= (worldTime - global.prevWorldTime) * 0.05;
	motionVector += cameraMovement;

	cloudPos += motionVector; // To previous frame's world space
    cloudPos = transMAD(gbufferPreviousModelView, cloudPos); // To previous frame's view space
	cloudPos = projMAD(gbufferPreviousProjection, cloudPos) * rcp(-cloudPos.z); // To previous frame's NDC space

    return cloudPos * 0.5 + 0.5;
}

//======// Main //================================================================================//
void main() {
	// Initialize
	cloudOut = vec4(0.0, 0.0, 0.0, 1.0);
	frameOut = 0u;

	vec2 screenCoord = gl_FragCoord.xy * viewPixelSize;

	const float currScale = rcp(float(CLOUD_TAAU_SCALE));
	vec2 currCoord = screenCoord * currScale - taaOffset * 0.5;
	currCoord = min(currCoord, currScale - viewPixelSize * 2.0);

	// Fetch closest cloud depth
	float cloudDepth = minOf(textureGather(cloudOriginTex, currCoord + 0.5));

	// Skip ground
	if (cloudDepth < EPS) return;

	frameOut = 1u;

	vec2 prevCoord = ReprojectClouds(screenCoord, cloudDepth).xy;
	uint frameIndex = texture(colortex13, prevCoord).x;

	bool disocclusion = worldTimeChanged;
	// Offscreen invalidation
	disocclusion = disocclusion || saturate(prevCoord) != prevCoord;
	// Previous ground invalidation
	disocclusion = disocclusion || frameIndex < 1u;
	// Fov change invalidation
	// disocclusion = disocclusion || (gbufferProjection[0].x - gbufferPreviousProjection[0].x) > 0.25;

	if (disocclusion) {
		// Return smoothed origin
		cloudOut = textureBicubic(cloudOriginTex, currCoord);
	} else {
		// vec4 prevData = max0(textureLanczos(cloudReconstructTex, prevCoord));
		vec4 prevData = max0(textureCatmullRomFast(cloudReconstructTex, prevCoord));

		ivec2 currTexel = uvToTexel(currCoord);
		vec4 currData = texelFetch(cloudOriginTex, currTexel, 0);

		#ifdef CLOUD_TAAU_CLIPPING
			vec4 moment1 = currData;
			vec4 moment2 = currData * currData;

			// Fetch 3x3 neighbour pixels
			for (uint i = 0u; i < 8u; ++i) {
				vec4 sampleData = texelFetch(cloudOriginTex, currTexel + offset3x3N[i], 0);

				moment1 += sampleData;
				moment2 += sampleData * sampleData;
			}
			moment1 *= rcp(9.0);
			moment2 *= rcp(9.0);

			// Ellipsoid intersection clipping
			vec4 clipStdDevInv = inversesqrt(abs(moment2 - moment1 * moment1) + EPS);
			prevData -= moment1;
			prevData *= saturate(inversesqrt(sdot(prevData * clipStdDevInv * 0.25)));
			prevData += moment1;
		#endif

		// Accumulate
		float currLum = luminance(currData.rgb), prevLum = luminance(prevData.rgb);
		float temporalContrast = saturate(abs(currLum - prevLum) / max(currLum, prevLum));
		float antiFlicker = 1.0 + sqr(temporalContrast) * CLOUD_TAAU_ANTIFLICKER;

		frameOut = min(frameIndex + 1u, CLOUD_MAX_ACCUM_FRAMES);
		cloudOut = mix(prevData, currData, rcp(antiFlicker * float(frameOut)));
	}
}