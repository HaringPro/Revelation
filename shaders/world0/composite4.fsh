#version 450 compatibility

/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/utility.inc"

//======// Output //==============================================================================//

/* RENDERTARGETS: 0,6 */
layout (location = 0) out vec3 sceneOut;
layout (location = 1) out float bloomyFogTrans;

//======// Input //===============================================================================//

flat in vec3 directIlluminance;
flat in vec3 skyIlluminance;

//======// Attribute //===========================================================================//

//======// Uniform //=============================================================================//

uniform sampler2D noisetex;

uniform sampler2D colortex0; // Scene data

uniform sampler2D colortex2; // Translucent data
uniform sampler2D colortex3; // Gbuffer data 0
uniform sampler2D colortex4; // Gbuffer data 1

uniform sampler2D colortex5; // Sky-View LUT

uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

uniform int moonPhase;
uniform int isEyeInWater;

uniform float near;
uniform float far;

uniform float nightVision;

uniform float eyeAltitude;
uniform float eyeSkylightFix;
uniform float wetnessCustom;

uniform vec2 viewPixelSize;
uniform vec2 viewSize;
uniform vec2 taaOffset;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform vec3 worldSunVector;
uniform vec3 worldLightVector;

uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferPreviousProjection;

uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferModelView;

//======// Struct //==============================================================================//

//======// Function //============================================================================//

#include "/lib/utility/Transform.inc"
#include "/lib/utility/Fetch.inc"

#include "/lib/atmospherics/Global.inc"

#include "/lib/water/WaterFog.glsl"

//======// Main //================================================================================//
void main() {
    ivec2 screenTexel = ivec2(gl_FragCoord.xy);

    sceneOut = sampleSceneColor(screenTexel);

	vec2 screenCoord = gl_FragCoord.xy * viewPixelSize;
	float depth = sampleDepth(screenTexel);
	float sDepth = sampleDepthSoild(screenTexel);

	vec3 viewPos = ScreenToViewSpace(vec3(screenCoord, depth));
	vec3 sViewPos = ScreenToViewSpace(vec3(screenCoord, sDepth));

	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos;
	vec3 worldDir = normalize(worldPos);
	worldPos += gbufferModelViewInverse[3].xyz;

	vec4 gbufferData0 = texelFetch(colortex3, screenTexel, 0);

	vec2 lightmap = unpackUnorm2x8(gbufferData0.x);
	uint materialID = uint(gbufferData0.y * 255.0);

	float LdotV = dot(worldLightVector, worldDir);

	bloomyFogTrans = 1.0;
	if (isEyeInWater == 1) {
		mat2x3 waterFog = CalculateWaterFog(saturate(eyeSkylightFix + 0.2), length(viewPos), LdotV);
		sceneOut = sceneOut * waterFog[1] + waterFog[0];
		bloomyFogTrans = GetLuminance(waterFog[1]);
	} else if (materialID == 3u) {
		mat2x3 waterFog = CalculateWaterFog(lightmap.y, distance(viewPos, sViewPos), LdotV);
		sceneOut = sceneOut * waterFog[1] + waterFog[0];
	}

    vec4 translucents = texelFetch(colortex2, screenTexel, 0);
	sceneOut += (translucents.rgb - sceneOut) * translucents.a;

	#ifdef BORDER_FOG
		if (depth + isEyeInWater < 1.0) {
			float density = saturate(1.0 - exp2(-sqr(pow4(dotSelf(worldPos.xz) * rcp(far * far))) * BORDER_FOG_FALLOFF));
			density *= oneMinus(saturate(worldDir.y * 3.0));

			vec3 skyRadiance = textureBicubic(colortex5, FromSkyViewLutParams(worldDir)).rgb;
			sceneOut = mix(sceneOut, skyRadiance, density);
		}
	#endif
}