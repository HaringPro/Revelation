#version 450 core

/*
--------------------------------------------------------------------------------

	Revelation Shaders

	Copyright (C) 2024 HaringPro
	Apache License 2.0

--------------------------------------------------------------------------------
*/

//======// Output //==============================================================================//

/* RENDERTARGETS: 6 */
out vec4 albedoOut;

//======// Input //===============================================================================//

in vec2 texCoord;

//======// Uniform //=============================================================================//

uniform sampler2D tex;

//======// Main //================================================================================//
void main() {
    float albedoAlpha = texture(tex, texCoord).a;

    if (albedoAlpha < 0.1) discard;

	albedoOut.a = albedoAlpha;
}