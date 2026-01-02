
//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

//======// Output //==============================================================================//

/* RENDERTARGETS: 7,8 */
layout (location = 0) out uvec4 materialOut;
layout (location = 1) out vec4 normalOut;

//======// Input //===============================================================================//

in vec3 worldPos;

in vec4 vertColor;
in vec2 texCoord;
in vec2 lightmap;

//======// Uniform //=============================================================================//

uniform sampler2D tex;

//======// Main //================================================================================//
void main() {
	vec4 albedo = texture(tex, texCoord) * vertColor;

	if (albedo.a < 0.1) { discard; return; }

	materialOut.x = Packup2x8U(lightmap);
	materialOut.y = 500u;

	materialOut.z = Packup2x8U(albedo.xy);
	materialOut.w = Packup2x8U(albedo.zw);

	vec3 flatNormal = normalize(cross(dFdx(worldPos), dFdy(worldPos)));

	normalOut.xy = OctEncodeUnorm(flatNormal);
	normalOut.zw = normalOut.xy;
}