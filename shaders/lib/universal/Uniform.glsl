uniform sampler2D noisetex;

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex4;
uniform sampler2D skyMapTex;
uniform sampler2D colortex6;
uniform usampler2D colortex7;
uniform sampler2D colortex8;
uniform sampler2D colortex9;
uniform sampler2D colortex10;
uniform sampler2D colortex12;
uniform usampler2D colortex13;
uniform sampler2D colortex14;
uniform sampler2D colortex15;

uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D depthtex2;

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

uniform int frameCounter;
uniform int isEyeInWater;
uniform int heldItemId;
uniform int heldBlockLightValue;
uniform int heldItemId2;
uniform int heldBlockLightValue2;
uniform int moonPhase;
uniform int worldTime;
uniform int worldDay;

uniform bool worldTimeChanged;
uniform bool viewSizeChanged;

uniform float frameTime;
uniform float frameTimeCounter;
uniform float nightVision;
uniform float near;
uniform float far;
uniform float viewWidth;
uniform float viewHeight;
uniform float aspectRatio;
uniform float rainStrength;
uniform float wetness;
uniform float wetnessCustom;
uniform float sunAngle;
uniform float eyeAltitude;
uniform float biomeSnowySmooth;
uniform float eyeSkylightSmooth;
uniform float worldTimeCounter;
uniform float timeNoon;
uniform float timeMidnight;
uniform float timeSunrise;
uniform float timeSunset;
uniform float cameraVelocity;

uniform vec2 viewPixelSize;
uniform vec2 viewSize;
uniform vec2 halfViewSize;
uniform vec2 halfViewEnd;
uniform vec2 taaOffset;
uniform vec2 prevTaaOffset;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform vec3 cameraMovement;
uniform vec3 worldSunVector;
uniform vec3 worldLightVector;
uniform vec3 viewLightVector;
uniform vec3 lightningShading;

uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferPreviousProjection;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferPreviousModelView;

uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;

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

    #define lodRenderDistance vxRenderDistance

    // Hardcoded near/far planes in Voxy
    // src: https://github.com/MCRcortex/voxy/blob/aa314781d6b70acb1639d1285a734d9892363306/src/main/java/me/cortex/voxy/client/iris/VoxyUniforms.java#L62-L63
    #define lodNearPlane 16
    #define lodFarPlane 16*3000

    #define lodProj vxProj
    #define lodProjInv vxProjInv
    #define lodProjPrev vxProjPrev

#endif