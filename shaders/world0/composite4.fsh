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

/* RENDERTARGETS: 0 */
out vec3 sceneOut;

//======// Input //===============================================================================//

//======// Attribute //===========================================================================//

//======// Uniform //=============================================================================//

uniform sampler2D noisetex;

uniform sampler2D colortex0; // Scene color

uniform sampler2D colortex2; // Sky-View LUT

uniform sampler2D colortex3; // Gbuffer data 0
uniform sampler2D colortex4; // Gbuffer data 1

uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

uniform int moonPhase;

uniform float near;
uniform float far;

uniform float nightVision;

uniform float eyeAltitude;
uniform float eyeSkylightFix;

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

//======// Main //================================================================================//
void main() {
    ivec2 screenTexel = ivec2(gl_FragCoord.xy);

    sceneOut = texelFetch(colortex0, screenTexel, 0).rgb;

	float depth = sampleDepth(screenTexel);

	vec3 screenPos = vec3(gl_FragCoord.xy * viewPixelSize, depth);
	vec3 viewPos = ScreenToViewSpace(screenPos);

	vec3 worldPos = mat3(gbufferModelViewInverse) * viewPos;
	vec3 worldDir = normalize(worldPos);

    // vec4 translucentAlbedo = texelFetch(colortex8, screenTexel, 0);

    // sceneOut *= sqr(mix(vec3(1.0), translucentAlbedo.rgb, pow(translucentAlbedo.a, 0.2)));

	vec4 gbufferData0 = texelFetch(colortex3, screenTexel, 0);

	uint materialID = uint(gbufferData0.y * 255.0);

	#ifdef BORDER_FOG
		if (depth < 1.0) {
			float density = saturate(1.0 - exp2(-sqr(pow4(dotSelf(worldPos.xz) * rcp(far * far))) * BORDER_FOG_FALLOFF));

			density *= oneMinus(saturate(worldDir.y * 3.0));

			vec3 skyRadiance = textureBicubic(colortex2, FromSkyViewLutParams(worldDir)).rgb;
			sceneOut = mix(sceneOut, skyRadiance, density);
		}
	#endif
}