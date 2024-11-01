#version 450 core

//======// Utility //=============================================================================//

#include "/lib/Utility.glsl"

#ifdef SSILVB_ENABLED
    #include "/program/SSILVB/SpatialFilter.comp"
#else
    #include "/program/RSM/SpatialFilter.comp"
#endif