/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2026 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

out vec2 texCoord;
out vec3 vectorData; // Minecraft position in water, vertColor in other materials

flat out uint isWater;

//======// Attribute //===========================================================================//

in vec4 mc_Entity;
in vec4 at_tangent;

//======// Uniform //=============================================================================//

uniform vec3 cameraPosition;
uniform mat4 shadowModelViewInverse;

uniform int blockEntityId;

//======// Function //============================================================================//

#include "/lib/lighting/shadow/Common.glsl"

//======// Main //================================================================================//
void main() {
	if (blockEntityId == 10030) {
		gl_Position = vec4(-1.0);
		return;
	}

	#ifdef SHADOW_BACKFACE_CULLING
		if ((gl_NormalMatrix * gl_Normal).z < 0.0) {
			gl_Position = vec4(-1.0);
			return;
		}
	#endif

	texCoord = vec2(gl_TextureMatrix[0] * gl_MultiTexCoord0);

	vec3 viewPos = transMAD(gl_ModelViewMatrix, gl_Vertex.xyz);

	isWater = 0u;
	if (int(mc_Entity.x) == 10003) {
		isWater = 1u;
		vectorData = transMAD(shadowModelViewInverse, viewPos) + cameraPosition;
	} else {
		vectorData = gl_Color.rgb;
	}

	gl_Position.xyz = DistortShadowSpace(projMAD(gl_ProjectionMatrix, viewPos));
	gl_Position.w = 1.0;
}
