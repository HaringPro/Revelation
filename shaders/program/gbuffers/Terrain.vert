
//======// Utility //=============================================================================//

#include "/lib/utility.glsl"

#define PLANT_WAVING

//======// Output //==============================================================================//

flat out mat3 tbnMatrix;

out vec4 tint;
out vec2 texCoord;
out vec2 lightmap;
flat out uint materialID;

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
attribute vec4 mc_midTexCoord;
attribute vec4 at_tangent;

//======// Uniform //=============================================================================//

uniform vec3 chunkOffset;

uniform mat3 normalMatrix;
uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;

uniform sampler2D noisetex;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

uniform vec3 cameraPosition;
uniform float frameTimeCounter;
uniform float wetnessCustom;

uniform vec2 taaOffset;

//======// Main //================================================================================//
void main() {
	tint = vaColor;
	texCoord = vaUV0;

	lightmap = saturate(vec2(vaUV2) * r240);

	vec4 worldPos = gbufferModelViewInverse * modelViewMatrix * vec4(vaPosition + chunkOffset, 1.0);

    tbnMatrix[2] = mat3(gbufferModelViewInverse) * normalize(normalMatrix * vaNormal);
	#if defined MC_NORMAL_MAP
		tbnMatrix[0] = mat3(gbufferModelViewInverse) * normalize(normalMatrix * at_tangent.xyz);
		tbnMatrix[1] = cross(tbnMatrix[0], tbnMatrix[2]) * sign(at_tangent.w);
	#endif

	materialID = uint(max0(mc_Entity.x - 1e4));

	#ifdef PLANT_WAVING
		worldPos.xyz += cameraPosition;

		float windIntensity = pow4(saturate(lightmap.y * 1.5 - 0.5)) * fma(wetnessCustom, 0.2, 0.1);

		// Plants
		if (materialID > 8u && materialID < 12u) {
			float tick = frameTimeCounter * PI;

			windIntensity *= materialID > 9u ? 0.75 : 1.0;
			float topVertex = step(vaUV0.y, mc_midTexCoord.y) + float(materialID == 10u);

			vec2 noise = texture(noisetex, worldPos.xz * rcp(256.0) + sin(tick * 6e-4) * 2.0 - 1.0).xy * 1.3 - 0.3;
			vec2 wind = sin(dot(worldPos.xz, vec2(0.87, 0.5)) + tick) * noise - cossin(PI * 0.2) * fastSqrt(max(worldPos.y, 1.0) * 0.4) * 0.2;
			worldPos.xz += wind * windIntensity * topVertex;
		}

		// Leaves
		if (materialID == 12u) {
			float tick = frameTimeCounter * PI;

			vec2 noise = texture(noisetex, worldPos.xz * rcp(256.0) + sin(tick * 6e-4) * 2.0 - 1.0).xy * 1.3 - 0.3;
			vec3 wind = sin(dot(worldPos.xyz, vec3(0.87, 0.6, 0.5)) + tick) * vec3(noise.x, noise.x * noise.y, noise.y);
			worldPos.xyz += wind * windIntensity * 0.5;
		}

		worldPos.xyz -= cameraPosition;
	#endif

	// if (materialID > 0u) { materialID = max(materialID, 6u); }
	// #ifdef GENERAL_GRASS_FIX
	// else if (abs(vaNormal.x) > 0.01 && abs(vaNormal.x) < 0.99 ||
	// 		 abs(vaNormal.y) > 0.01 && abs(vaNormal.y) < 0.99 ||
	// 		 abs(vaNormal.z) > 0.01 && abs(vaNormal.z) < 0.99
	// 		) materialID = 6u;
	// #endif

	// minecraftPos = worldPos.xyz;

	gl_Position = projectionMatrix * gbufferModelView * worldPos;

	#ifdef TAA_ENABLED
		gl_Position.xy += taaOffset * gl_Position.w;
	#endif
}