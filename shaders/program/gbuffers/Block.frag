
//======// Utility //=============================================================================//

#include "/lib/utility.inc"

//======// Output //==============================================================================//

/* RENDERTARGETS: 0,3,4 */
layout(location = 0) out vec4 albedoOut;
layout(location = 1) out vec2 gbufferOut0;
layout(location = 2) out vec2 gbufferOut1;

//======// Input //===============================================================================//

flat in mat3 tbnMatrix;

in vec4 tint;
in vec2 texCoord;
in vec2 lightmap;
flat in uint materialID;

in vec4 viewPos;

//======// Uniform //=============================================================================//

uniform sampler2D tex;

uniform mat4 gbufferModelViewInverse;

uniform float frameTimeCounter;

//======// Function //============================================================================//

float bayer2 (vec2 a) { a = 0.5 * floor(a); return fract(1.5 * fract(a.y) + a.x); }
#define bayer4(a) (bayer2(0.5 * (a)) * 0.25 + bayer2(a))

const vec3[] COLORS = vec3[](
    vec3(0.022087, 0.098399, 0.110818),
    vec3(0.011892, 0.095924, 0.089485),
    vec3(0.027636, 0.101689, 0.100326),
    vec3(0.046564, 0.109883, 0.114838),
    vec3(0.064901, 0.117696, 0.097189),
    vec3(0.063761, 0.086895, 0.123646),
    vec3(0.084817, 0.111994, 0.166380),
    vec3(0.097489, 0.154120, 0.091064),
    vec3(0.106152, 0.131144, 0.195191),
    vec3(0.097721, 0.110188, 0.187229),
    vec3(0.133516, 0.138278, 0.148582),
    vec3(0.070006, 0.243332, 0.235792),
    vec3(0.196766, 0.142899, 0.214696),
    vec3(0.047281, 0.315338, 0.321970),
    vec3(0.204675, 0.390010, 0.302066),
    vec3(0.080955, 0.314821, 0.661491)
);

mat2 mat2RotateZ(in float radian) {
	return mat2(cos(radian), -sin(radian), sin(radian), cos(radian));
}

vec2 endPortalLayer(in vec2 coord, in float layer) {
	vec2 offset = vec2(8.5 / layer, (1.0 + layer / 3.0) * (frameTimeCounter * 0.0015)) + 0.25;

	mat2 rotate = mat2RotateZ(radians(layer * layer * 8642.0 + layer * 18.0));

	return (4.5 - layer * 0.25) * (rotate * coord) + offset;
}

//======// Main //================================================================================//
void main() {
	vec4 albedo = texture(tex, texCoord) * tint;

	if (albedo.a < 0.1) { discard; return; }

	#ifdef WHITE_WORLD
		albedo.rgb = vec3(1.0);
	#endif

	if (materialID == 46u) {
		vec3 worldDir = mat3(gbufferModelViewInverse) * normalize(viewPos.xyz);
		vec3 worldDirAbs = abs(worldDir);
		vec3 samplePartAbs = step(maxOf(worldDirAbs), worldDirAbs);
		vec3 samplePart = samplePartAbs * sign(worldDir);
		float intersection = 1.0 / dot(samplePartAbs, worldDirAbs);
		vec3 sampleNDCRaw = samplePart - worldDir * intersection;
		vec2 sampleNDC = sampleNDCRaw.xy * vec2(samplePartAbs.y + samplePart.z, 1.0 - samplePartAbs.y) + sampleNDCRaw.z * vec2(-samplePart.x, samplePartAbs.y);
		vec2 portalCoord = sampleNDC * 0.5 + 0.5;

		vec3 portalColor = texture(tex, portalCoord).rgb * COLORS[0];
		for (int i = 0; i < 16; ++i) {
			portalColor += texture(tex, endPortalLayer(portalCoord, float(i + 1))).rgb * COLORS[i];
		}
		albedo.rgb = portalColor;
		// specularData = vec4(1.0, 0.04, vec2(254.0 / 255.0));
	}

	albedoOut = albedo;

	gbufferOut0.x = packUnorm2x8Dithered(lightmap, bayer4(gl_FragCoord.xy));
	gbufferOut0.y = float(materialID + 0.1) * r255;

	gbufferOut1.x = packUnorm2x8(encodeUnitVector(tbnMatrix[2]));
	gbufferOut1.y = gbufferOut1.x;
}
