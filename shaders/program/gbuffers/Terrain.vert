
//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

#define WAVING_FOLIAGE // Enables waving foilage effect
#define UNLABELLED_FOILAGE_DETECTION // Enables unlabelled foilage detection

//======// Output //==============================================================================//

#if defined NORMAL_MAPPING
	flat out mat3 tbnMatrix;
#else
	flat out vec3 flatNormal;
#endif

out vec3 vertColor;
out vec2 texCoord;
out vec2 lightmap;
flat out uint materialID;

#if defined PARALLAX || defined AUTO_GENERATED_NORMAL
	out vec2 tileBase;
	flat out vec2 tileScale;
	flat out vec2 tileOffset;

	out vec3 tangentViewPos;
#endif

//======// Attribute //===========================================================================//

in vec3 vaPosition;
in vec4 vaColor;
in vec2 vaUV0;

in vec3 vaNormal;

#ifndef MC_GL_VENDOR_INTEL
	#define attribute in
#endif

attribute vec4 mc_Entity;
attribute vec2 mc_midTexCoord;
attribute vec4 at_tangent;

//======// Uniform //=============================================================================//

uniform sampler2D noisetex;

uniform vec3 chunkOffset;

uniform mat3 normalMatrix;
uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

uniform vec3 cameraPosition;
uniform float frameTimeCounter;
uniform float wetnessCustom;

uniform vec2 taaOffset;

//======// Main //================================================================================//
void main() {
	vertColor = vaColor.rgb;
	texCoord = vaUV0;

	lightmap = saturate(vec2(vaUV2) * r240);

	vec3 worldPos = transMAD(gbufferModelViewInverse, transMAD(modelViewMatrix, vaPosition + chunkOffset));

	#if defined NORMAL_MAPPING
		tbnMatrix[2] = mat3(gbufferModelViewInverse) * normalize(normalMatrix * vaNormal);
		tbnMatrix[0] = mat3(gbufferModelViewInverse) * normalize(normalMatrix * at_tangent.xyz);
		tbnMatrix[1] = cross(tbnMatrix[0], tbnMatrix[2]) * fastSign(at_tangent.w);
	#else
		flatNormal = mat3(gbufferModelViewInverse) * normalize(normalMatrix * vaNormal);
	#endif

	materialID = uint(max0(mc_Entity.x - 1e4));

	#ifdef WAVING_FOLIAGE
		// Plants
		if (materialID > 8u && materialID < 12u) {
			float tick = frameTimeCounter * PI;
			float windIntensity = cube(saturate(lightmap.y * 1.5 - 0.5)) * fma(wetnessCustom, 0.2, 0.1);
			worldPos += cameraPosition;

			windIntensity *= materialID > 9u ? 0.75 : 1.0;
			float topVertex = step(vaUV0.y, mc_midTexCoord.y) + float(materialID == 10u);

			vec2 noise = texture(noisetex, worldPos.xz * rcp(256.0) + sin(tick * 1e-3) * 0.5 + 0.5).xy * 1.4 - 0.4;
			vec2 wind = sin(dot(worldPos.xz, vec2(0.87, 0.5)) + tick) * noise - cossin(PI * 0.2) * approxSqrt(max(worldPos.y, 1.0) * 0.4) * 0.2;
			worldPos.xz += wind * (windIntensity * topVertex);
			worldPos -= cameraPosition;
		}

		// Leaves
		if (materialID == 12u) {
			float tick = frameTimeCounter * PI;
			float windIntensity = cube(saturate(lightmap.y * 1.5 - 0.5)) * fma(wetnessCustom, 0.2, 0.1);
			worldPos += cameraPosition;

			vec2 noise = texture(noisetex, worldPos.xz * rcp(256.0) + sin(tick * 1e-3) * 0.5 + 0.5).xy * 1.4 - 0.4;
			vec3 wind = sin(dot(worldPos, vec3(0.87, 0.6, 0.5)) + tick) * vec3(noise.x, noise.x * noise.y, noise.y);
			worldPos += wind * (windIntensity * 0.75) - cameraPosition;
		}
	#endif

	// Unlabelled foilage detection
	#ifdef UNLABELLED_FOILAGE_DETECTION
		if (materialID < 1u && maxOf(abs(vaNormal)) < 0.99) materialID = 13u;
	#endif

	#if defined PARALLAX || defined AUTO_GENERATED_NORMAL
		vec2 minMidCoord = texCoord - mc_midTexCoord;
		tileBase = fastSign(minMidCoord) * 0.5 + 0.5;
		tileScale = abs(minMidCoord) * 2.0;
		tileOffset = min(texCoord, mc_midTexCoord - minMidCoord);

		tangentViewPos = (worldPos - gbufferModelViewInverse[3].xyz) * tbnMatrix;
	#endif

	gl_Position = diagonal4(projectionMatrix) * transMAD(gbufferModelView, worldPos).xyzz + projectionMatrix[3];

	#ifdef TAA_ENABLED
		gl_Position.xy += taaOffset * gl_Position.w;
	#endif
}