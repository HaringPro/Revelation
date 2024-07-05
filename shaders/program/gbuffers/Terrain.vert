
//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

#define WAVING_FOILAGE // Enables waving foilage effect

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
		tbnMatrix[1] = cross(tbnMatrix[0], tbnMatrix[2]) * fastSign(at_tangent.w);
	#endif

	materialID = uint(max0(mc_Entity.x - 1e4));

	#ifdef WAVING_FOILAGE
		worldPos.xyz += cameraPosition;

		float windIntensity = cube(saturate(lightmap.y * 1.5 - 0.5)) * fma(wetnessCustom, 0.2, 0.1);

		// Plants
		if (materialID > 8u && materialID < 12u) {
			float tick = frameTimeCounter * PI;

			windIntensity *= materialID > 9u ? 0.75 : 1.0;
			float topVertex = step(vaUV0.y, mc_midTexCoord.y) + float(materialID == 10u);

			vec2 noise = texture(noisetex, worldPos.xz * rcp(256.0) + sin(tick * 1e-3) * 0.5 + 0.5).xy * 1.4 - 0.4;
			vec2 wind = sin(dot(worldPos.xz, vec2(0.87, 0.5)) + tick) * noise - cossin(PI * 0.2) * fastSqrt(max(worldPos.y, 1.0) * 0.4) * 0.2;
			worldPos.xz += wind * windIntensity * topVertex;
		}

		// Leaves
		if (materialID == 12u) {
			float tick = frameTimeCounter * PI;

			vec2 noise = texture(noisetex, worldPos.xz * rcp(256.0) + sin(tick * 1e-3) * 0.5 + 0.5).xy * 1.4 - 0.4;
			vec3 wind = sin(dot(worldPos.xyz, vec3(0.87, 0.6, 0.5)) + tick) * vec3(noise.x, noise.x * noise.y, noise.y);
			worldPos.xyz += wind * windIntensity * 0.75;
		}

		worldPos.xyz -= cameraPosition;
	#endif

	// minecraftPos = worldPos.xyz;

	gl_Position = projectionMatrix * gbufferModelView * worldPos;

	#ifdef TAA_ENABLED
		gl_Position.xy += taaOffset * gl_Position.w;
	#endif
}