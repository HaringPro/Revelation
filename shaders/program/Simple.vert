/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2026 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

//======// Main //================================================================================//
void main() {
	// Full screen triangle
    // http://www.altdev.co/2011/08/08/interesting-vertex-shader-trick/
	vec2 uv = vec2(gl_VertexID & 2, (gl_VertexID & 1) << 1);
	gl_Position = vec4(uv * vec2(2.0, -2.0) + vec2(-1.0, 1.0), 0.0, 1.0);
}
