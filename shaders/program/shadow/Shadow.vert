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

flat out uint materialID;

//======// Attribute //===========================================================================//

in vec4 mc_Entity;
in vec2 mc_midTexCoord;

//======// Uniform //=============================================================================//

#include "/lib/universal/Uniform.glsl"

//======// Function //============================================================================//

#include "/lib/lighting/shadow/Common.glsl"
#include "/lib/surface/Foliage.glsl"

//======// Main //================================================================================//
void main() {
	if (blockEntityId == MATERIAL_PROPERTY_BASE + int(MAT_BEACON)) {
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

	materialID = DecodeMaterialID(int(mc_Entity.x));
	if (materialID == MAT_WATER) {
		vectorData = transMAD(shadowModelViewInverse, viewPos) + cameraPosition;
	} else {
		vectorData = gl_Color.rgb;
	}

	if (materialID == MAT_LEAVES || materialID >= MATERIAL_ROOTED_BASE) {
		vec3 worldPos = transMAD(shadowModelViewInverse, viewPos);
		float skylight = saturate((gl_MultiTexCoord1.y - 8.0) * rcp(232.0));
		ApplyFoliageDisplacement(worldPos, materialID, skylight, step(gl_MultiTexCoord0.y, mc_midTexCoord.y));
		viewPos = transMAD(shadowModelView, worldPos);
	}

	gl_Position.xyz = DistortShadowSpace(projMAD(gl_ProjectionMatrix, viewPos));
	gl_Position.w = 1.0;
}
