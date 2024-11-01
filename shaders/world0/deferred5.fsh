#version 450 core

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

#ifdef SSILVB_ENABLED
    #include "/program/SSILVB/Accumulate.frag"
#else
    #include "/program/RSM/Accumulate.frag"
#endif