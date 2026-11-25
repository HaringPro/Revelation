/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2026 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

#define UNLABELLED_FOILAGE_DETECTION

//======// Output //==============================================================================//

flat out uint normalPack;
#if defined MC_NORMAL_MAP || defined AUTO_GENERATED_NORMAL
flat out uint tangentPack;
#endif

out vec3 vertColor;
out vec2 texCoord;
out vec2 lightmap;
flat out uint materialID;

#if defined PARALLAX || defined AUTO_GENERATED_NORMAL
	flat out vec2 tileScale;
	flat out vec2 tileOffset;
#endif

//======// Attribute //===========================================================================//

in vec4 mc_Entity;
in vec2 mc_midTexCoord;
in vec4 at_tangent;

//======// Uniform //=============================================================================//

#include "/lib/universal/Uniform.glsl"

//======// Function //============================================================================//

#include "/lib/surface/Foliage.glsl"

//======// Main //================================================================================//
void main() {
	vertColor = gl_Color.rgb;
	texCoord = vec2(gl_TextureMatrix[0] * gl_MultiTexCoord0);

	lightmap = saturate((gl_MultiTexCoord1.xy - 8.0) * rcp(232.0));

	vec3 worldPos = transMAD(gbufferModelViewInverse, transMAD(gl_ModelViewMatrix, gl_Vertex.xyz));

	materialID = DecodeMaterialID(int(mc_Entity.x));

	// Unlabelled foliage detection
	#ifdef UNLABELLED_FOILAGE_DETECTION
		// Crossed plant quads are vertical and diagonal in block space.
        vec3 absNormal = abs(gl_Normal);
		if (mc_Entity.x < float(MATERIAL_PROPERTY_BASE) && absNormal.y < 0.02 && minOf(absNormal.xz) > 0.6) {
			materialID = MAT_STATIC_PLANT;
		}
	#endif

	// Encode normal and tangent
	vec3 normal = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * gl_Normal);
	normalPack = packSnorm2x16(OctEncodeSnorm(normal));
	#if defined MC_NORMAL_MAP || defined AUTO_GENERATED_NORMAL
		vec3 tangent = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * at_tangent.xyz);
		tangentPack = bitfieldInsert(PackSnorm3x10(tangent), uint(at_tangent.w < 0.0), 30, 1);
	#endif

	ApplyFoliageDisplacement(worldPos, materialID, lightmap.y, step(gl_MultiTexCoord0.y, mc_midTexCoord.y));

	#if defined PARALLAX || defined AUTO_GENERATED_NORMAL
        vec2 halfSize = abs(texCoord - mc_midTexCoord);
		tileScale = halfSize * 2.0;
		tileOffset = mc_midTexCoord - halfSize;
	#endif

	vec3 viewPos = transMAD(gbufferModelView, worldPos);
    gl_Position = project(gl_ProjectionMatrix, viewPos);
    #ifdef SHOULD_APPLY_JITTER
        gl_Position.xy += taaJitter * gl_Position.w;
    #endif
    #if (RENDER_SCALE_1000X != 1000) || SR_ENABLE
        gl_Position.xy = gl_Position.xy * renderScale + (renderScale - 1.0) * gl_Position.w;
    #endif
}
