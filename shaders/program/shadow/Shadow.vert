/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

//======// Fix for https://github.com/HaringPro/Revelation/issues/18 //===========================//

in ivec2 vaUV2;

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

out vec2 texCoord;

// out vec3 viewPos;
out vec3 vectorData; // Minecraf position in water, vertColor in other materials

// flat out mat3 tbnMatrix;

flat out uint isWater;

//======// Attribute //===========================================================================//

in vec3 vaPosition;
in vec4 vaColor;
in vec2 vaUV0;
in vec3 vaNormal;

in vec4 mc_Entity;
in vec4 at_tangent;

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

#include "/lib/lighting/shadow/Common.glsl"

//======// Main //================================================================================//
void main() {
	if (blockEntityId == 10030) {
		gl_Position = vec4(-1.0);
		return;
	}

    vec3 normal = normalize(normalMatrix * vaNormal);
	#ifdef SHADOW_BACKFACE_CULLING
		if (normal.z < 0.0) {
			gl_Position = vec4(-1.0);
			return;
		}
	#endif

	texCoord = vaUV0;

	vec3 viewPos = transMAD(modelViewMatrix, vaPosition + chunkOffset);

	isWater = 0u;
	if (int(mc_Entity.x) == 10003) {
		isWater = 1u;
		vectorData = transMAD(shadowModelViewInverse, viewPos) + cameraPosition;
	} else {
		vectorData = vaColor.rgb;
	}

	gl_Position.xyz = DistortShadowSpace(projMAD(projectionMatrix, viewPos));
	gl_Position.w = 1.0;
}