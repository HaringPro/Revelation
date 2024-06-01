uniform sampler2D noisetex;

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex4;
uniform sampler2D colortex5;
uniform sampler2D colortex6;
uniform sampler2D colortex7;

uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D depthtex2;

uniform float frameTime;
uniform float frameTimeCounter;
uniform float nightVision;
uniform float near;
uniform float far;
uniform float viewWidth;
uniform float viewHeight;
uniform float aspectRatio;
uniform float wetness;
uniform float wetnessCustom;
uniform float sunAngle;
uniform float eyeAltitude;
uniform float weatherSnowySmooth;
uniform float eyeSkylightFix;
uniform float lightningFlashing;
uniform float worldTimeCounter;
uniform float timeNoon;
uniform float timeMidnight;
uniform float timeSunrise;
uniform float timeSunset;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform vec3 worldSunVector;
uniform vec3 worldLightVector;

uniform int frameCounter;
uniform int isEyeInWater;
uniform int heldItemId;
uniform int heldBlockLightValue;
uniform int heldItemId2;
uniform int heldBlockLightValue2;
uniform int moonPhase;

uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferPreviousProjection;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferModelView;

uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;
uniform mat4 shadowModelView;

uniform vec2 viewPixelSize;
uniform vec2 viewSize;
uniform vec2 taaOffset;

#if defined DISTANT_HORIZONS
    uniform sampler2D dhDepthTex0;
    uniform sampler2D dhDepthTex1;

    uniform int dhRenderDistance;

    uniform float dhNearPlane;
    uniform float dhFarPlane;

    uniform mat4 dhProjection;
    uniform mat4 dhProjectionInverse;
    uniform mat4 dhPreviousProjection;
#endif
