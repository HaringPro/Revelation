uniform sampler2D noisetex;

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex4;
uniform sampler2D colortex5;
uniform sampler2D colortex6;
uniform usampler2D colortex7;
uniform sampler2D colortex8;
uniform sampler2D colortex9;
uniform sampler2D colortex10;
uniform usampler2D colortex11;
uniform sampler2D colortex12;
uniform usampler2D colortex13;
uniform sampler2D colortex14;
uniform sampler2D colortex15;

uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D depthtex2;

// Custom samplers
uniform sampler3D scatteringLut;
uniform sampler2D transmittanceLut;
uniform sampler2D irradianceLut;

uniform sampler2D brdfLutTex;

uniform sampler3D stbnVec1Tex;
uniform sampler3D stbnVec2Tex;
uniform sampler3D stbnUnitvec2Tex;

uniform sampler3D baseNoiseTex;
uniform sampler3D detailNoiseTex;

uniform sampler2D cloudMapTex;
uniform sampler2D verticalLut;
uniform sampler2D curlNoiseTex;
uniform sampler2D cirroLutTex;

//================================================================================================//

uniform int heldItemId;                         // held item ID (main hand), used only for items defined in "item.properties"
uniform int heldBlockLightValue;                // held item light value (main hand)
uniform int heldItemId2;                        // held item ID (off hand), used only for items defined in "item.properties"
uniform int heldBlockLightValue2;               // held item light value (off hand)
uniform int fogMode;                            // GL_LINEAR, GL_EXP or GL_EXP2
uniform float fogStart;                         // fog start distance (m)
uniform float fogEnd;                           // fog end distance (m)
uniform int fogShape;                           // 0 = sphere, 1 = cylinder
uniform float fogDensity;                       // 0.0-1.0
uniform vec3 fogColor;                          // r, g, b
uniform vec3 skyColor;                          // r, g, b
uniform int worldTime;                          // <ticks> = worldTicks % 24000
uniform int worldDay;                           // <days> = worldTicks / 24000
uniform int moonPhase;                          // 0-7
uniform int frameCounter;                       // Frame index (0 to 720719, then resets to 0)
uniform float frameTime;                        // last frame time, seconds
uniform float frameTimeCounter;                 // run time, seconds (resets to 0 after 3600s)
uniform float sunAngle;                         // 0.0-1.0
uniform float shadowAngle;                      // 0.0-1.0
uniform float rainStrength;                     // 0.0-1.0
uniform float aspectRatio;                      // viewWidth / viewHeight
uniform float viewWidth;                        // viewWidth
uniform float viewHeight;                       // viewHeight
uniform float near;                             // near viewing plane distance
uniform float far;                              // far viewing plane distance
uniform vec3 sunPosition;                       // sun position in eye space
uniform vec3 moonPosition;                      // moon position in eye space
uniform vec3 shadowLightPosition;               // shadow light (sun or moon) position in eye space
uniform vec3 upPosition;                        // direction up
uniform vec3 cameraPosition;                    // camera position in world space
uniform vec3 previousCameraPosition;            // last frame cameraPosition

uniform mat4 gbufferModelView;                  // modelview matrix after setting up the camera transformations
uniform mat4 gbufferModelViewInverse;           // inverse gbufferModelView
uniform mat4 gbufferPreviousModelView;          // last frame gbufferModelView
uniform mat4 gbufferProjection;                 // projection matrix when the gbuffers were generated
uniform mat4 gbufferProjectionInverse;          // inverse gbufferProjection
uniform mat4 gbufferPreviousProjection;         // last frame gbufferProjection
uniform mat4 shadowProjection;                  // projection matrix when the shadow map was generated
uniform mat4 shadowProjectionInverse;           // inverse shadowProjection
uniform mat4 shadowModelView;                   // modelview matrix when the shadow map was generated
uniform mat4 shadowModelViewInverse;            // inverse shadowModelView
uniform float wetness;                          // rainStrength smoothed with wetnessHalfLife or drynessHalfLife
uniform float eyeAltitude;                      // view entity Y position
uniform ivec2 eyeBrightness;                    // x = block brightness, y = sky brightness, light 0-15 = brightness 0-240
uniform ivec2 eyeBrightnessSmooth;              // eyeBrightness smoothed with eyeBrightnessHalflife
uniform ivec2 terrainTextureSize;               // not used
uniform int terrainIconSize;                    // not used
uniform int isEyeInWater;                       // 1 = camera is in water, 2 = camera is in lava, 3 = camera is in powder snow
uniform float nightVision;                      // night vision (0.0-1.0)
uniform float blindness;                        // blindness (0.0-1.0)
uniform float screenBrightness;                 // screen brightness (0.0-1.0)
uniform int hideGUI;                            // GUI is hidden
uniform float centerDepthSmooth;                // centerDepth smoothed with centerDepthSmoothHalflife
uniform ivec2 atlasSize;                        // texture atlas size (only set when the atlas texture is bound)
uniform vec4 spriteBounds;                      // sprite bounds in the texture atlas (u0, v0, u1, v1), set when MC_ANISOTROPIC_FILTERING is enabled
uniform vec4 entityColor;                       // entity color multiplier (entity hurt, creeper flashing when exploding)
uniform int entityId;                           // entity ID
uniform int blockEntityId;                      // block entity ID (block ID for the tile entity, only for blocks specified in "block.properties")
uniform ivec4 blendFunc;                        // blend function (srcRGB, dstRGB, srcAlpha, dstAlpha)
uniform int instanceId;                         // instance ID when instancing is enabled (countInstances > 1), 0 = original, 1-N = copies
uniform float playerMood;                       // player mood (0.0-1.0), increases the longer a player stays underground
uniform int renderStage;                        // render stage, see "Standard Macros", "J. Render stages"
uniform int bossBattle;                         // 1 = custom, 2 = ender dragon, 3 = wither, 4 = raid
// 1.17+
uniform mat4 modelViewMatrix;                   // model view matrix
uniform mat4 modelViewMatrixInverse;            // inverse model view matrix
uniform mat4 projectionMatrix;                  // projection matrix
uniform mat4 projectionMatrixInverse;           // inverse projection matrix
uniform mat4 textureMatrix = mat4(1.0);         // texture matrix, default is identity
uniform mat3 normalMatrix;                      // normal matrix
uniform vec3 chunkOffset;                       // terrain chunk origin, used with attribute "vaPosition"
uniform float alphaTestRef;                     // alpha test reference value, the check is "if (color.a < alphaTestRef) discard;"
// 1.19+
uniform float darknessFactor;                   // strength of the darkness effect (0.0-1.0)
uniform float darknessLightFactor;              // lightmap variations caused by the darkness effect (0.0-1.0)

// Custom uniforms
uniform bool worldTimeChanged;
uniform bool viewSizeChanged;

uniform float wetnessCustom;
uniform float eyeSkylightSmooth;
uniform float worldTimeCounter;
uniform float timeNoon;
uniform float timeMidnight;
uniform float timeSunrise;
uniform float timeSunset;
uniform float cameraVelocity;

uniform vec2 viewSize;
uniform vec2 viewPixelSize;
uniform vec2 halfViewSize;
uniform vec2 halfViewEnd;
uniform vec2 taaOffset;
uniform vec2 prevTaaOffset;

uniform vec3 cameraMovement;
uniform vec3 worldSunVector;
uniform vec3 worldLightVector;
uniform vec3 viewLightVector;
uniform vec3 lightningShading;


#if defined DISTANT_HORIZONS

    #define LOD_MOD
    uniform sampler2D dhDepthTex0;
    uniform sampler2D dhDepthTex1;

    uniform int dhRenderDistance;

    uniform float dhNearPlane;
    uniform float dhFarPlane;

    uniform mat4 dhProjection;
    uniform mat4 dhProjectionInverse;
    uniform mat4 dhPreviousProjection;

    #define lodDepthTex0 dhDepthTex0
    #define lodDepthTex1 dhDepthTex1

    #define lodRenderDistance dhRenderDistance

    #define lodNearPlane dhNearPlane
    #define lodFarPlane dhFarPlane

    #define lodProj dhProjection
    #define lodProjInv dhProjectionInverse
    #define lodProjPrev dhPreviousProjection

#elif defined VOXY

    #define LOD_MOD
    uniform sampler2D vxDepthTexTrans;
    uniform sampler2D vxDepthTexOpaque;

    uniform int vxRenderDistance;

    uniform mat4 vxProj;
    uniform mat4 vxProjInv;
    uniform mat4 vxProjPrev;

    #define lodDepthTex0 vxDepthTexTrans
    #define lodDepthTex1 vxDepthTexOpaque

    #define lodRenderDistance vxRenderDistance

    // Hardcoded near/far planes in Voxy
    // src: https://github.com/MCRcortex/voxy/blob/aa314781d6b70acb1639d1285a734d9892363306/src/main/java/me/cortex/voxy/client/iris/VoxyUniforms.java#L62-L63
    #define lodNearPlane 16
    #define lodFarPlane 16*3000

    #define lodProj vxProj
    #define lodProjInv vxProjInv
    #define lodProjPrev vxProjPrev

#endif
