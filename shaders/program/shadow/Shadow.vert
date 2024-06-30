/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

out vec2 texCoord;
out vec3 tint;
out vec2 lightmap;
out vec3 viewPos;
out vec3 minecraftPos;

flat out mat3 tbnMatrix;

flat out uint isWater;

//======// Attribute //===========================================================================//

in vec3 vaPosition;
in vec4 vaColor;
in vec2 vaUV0;
in ivec2 vaUV2;
in vec3 vaNormal;

#ifndef MC_GL_VENDOR_INTEL
	#define attribute in
#endif

attribute vec4 mc_Entity;
attribute vec4 at_tangent;

//======// Uniform //=============================================================================//

uniform vec3 chunkOffset;

uniform mat3 normalMatrix;
uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;

uniform vec3 cameraPosition;
uniform mat4 shadowModelViewInverse;

uniform int blockEntityId;

uniform mat4 shadowProjection;

//======// Function //============================================================================//

#include "/lib/lighting/ShadowDistortion.glsl"

//======// Main //================================================================================//
void main() {
	if (blockEntityId == 10030) {
		gl_Position = vec4(-1.0);
		return;
	}

    tbnMatrix[2] = mat3(shadowModelViewInverse) * normalize(normalMatrix * vaNormal);
	#ifdef SHADOW_BACKFACE_CULLING
		if (tbnMatrix[2].z < 0.0) {
			gl_Position = vec4(-1.0);
			return;
		}
	#endif

	tint = vaColor.rgb;

	isWater = 0;
	if (int(mc_Entity.x) == 10003) {
		tbnMatrix[0] = mat3(shadowModelViewInverse) * normalize(normalMatrix * at_tangent.xyz);
		tbnMatrix[1] = cross(tbnMatrix[0], tbnMatrix[2]) * fastSign(at_tangent.w);

		isWater = 1;
	}

	lightmap = saturate(vec2(vaUV2) * r240);
	texCoord = vaUV0;

	viewPos = transMAD(modelViewMatrix, vaPosition + chunkOffset);
	minecraftPos = transMAD(shadowModelViewInverse, viewPos) + cameraPosition;

	gl_Position.xyz = DistortShadowSpace(projMAD(projectionMatrix, viewPos));
	gl_Position.w = 1.0;
}