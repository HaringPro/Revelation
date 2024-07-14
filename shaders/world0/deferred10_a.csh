#version 450 compatibility

/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

	Pass: Clear colorimg2

--------------------------------------------------------------------------------
*/

layout (local_size_x = 16, local_size_y = 16) in;
const vec2 workGroupsRender = vec2(0.5f, 0.5f);

//======// Output //==============================================================================//

writeonly restrict uniform image2D colorimg2; // Current indirect light

//======// Main //================================================================================//
void main() {
	imageStore(colorimg2, ivec2(gl_GlobalInvocationID.xy), vec4(0.0));
}