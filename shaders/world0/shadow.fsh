#version 450 compatibility

#include "/settings.glsl"

#if defined VOXEL_BRANCH
    #include "/lib/voxel/shadow/Shadow.frag"
#else
    #include "/program/shadow/Shadow.frag"
#endif