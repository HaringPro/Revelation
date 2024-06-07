/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

/* RENDERTARGETS: 0 */
out vec3 bloomTiles;

uniform sampler2D colortex0;

uniform vec2 viewPixelSize;

//======// Main //================================================================================//
void main() {
    int index = int(-log2(1.0 - gl_FragCoord.x * viewPixelSize.x));
    if (index > 7) discard;

	ivec2 texel = ivec2(gl_FragCoord.xy);

	const float sumWeight[5] = float[5](0.27343750, 0.21875000, 0.10937500, 0.03125000, 0.00390625);

	bloomTiles = vec3(0.0);
	for (int i = -4; i <= 4; ++i) {
		bloomTiles += texelFetch(colortex0, texel + ivec2(0,  i), 0).rgb * sumWeight[abs(i)];
	}
}
