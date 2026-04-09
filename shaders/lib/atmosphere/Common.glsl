/*
--------------------------------------------------------------------------------

	References:
		Sébastien Hillaire. "A Scalable and Production Ready Sky and Atmosphere Rendering Technique". EGSR 2020.
            https://sebh.github.io/publications/egsr2020.pdf
		Epic Games, Inc. "Unreal Engine Sky Atmosphere Rendering Technique". 2020.
            https://github.com/sebh/UnrealEngineSkyAtmosphere

--------------------------------------------------------------------------------
*/

//================================================================================================//

// #define PLANET_GROUND

#define VIEWER_BASE_ALTITUDE 256.0 // [64.0 128.0 256.0 384.0 512.0 1024.0 2048.0 4096.0 8192.0 16384.0 32768.0 65536.0 131072.0 262144.0 524288.0 1048576.0 2097152.0 4194304.0 8388608.0 16777216.0 33554432.0 67108864.0 134217728.0 268435456.0 536870912.0 1073741824.0]
#define ATMOSPHERE_THICKNESS 100000.0 // [0.0 5000.0 10000.0 20000.0 30000.0 40000.0 50000.0 60000.0 70000.0 80000.0 90000.0 100000.0 110000.0 120000.0 130000.0 140000.0 150000.0 160000.0]

#define ATMOSPHERE_TURBIDITY 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 1.75 2.0 2.25 2.5 2.75 3.0 3.25 3.5 3.75 4.0 4.25 4.5 4.75 5.0]

#define ATMOSPHERE_SKY_SAMPLES 32 // [16 24 32 40 48 56 64 72 80 88 96 104 112 120 128]
#define ATMOSPHERE_TLUT_SAMPLES 64 // [16 24 32 40 48 56 64 72 80 88 96 104 112 120 128]
#define ATMOSPHERE_MSLUT_SAMPLES 24 // [16 24 32 40 48 56 64 72 80 88 96 104 112 120 128]

#define ProjectSky      OctEncodeUnorm
#define UnprojectSky    OctDecodeUnorm

//================================================================================================//

struct AtmosphereParameters {
    float bottomRadius;
    float topRadius;
    vec3 rayleighScattering;
    vec3 mieScattering;
    vec3 mieExtinction;
    vec3 ozoneExtinction;
    vec3 groundAlbedo;
};

//================================================================================================//

const float planetRadius = 6371e3; // The average radius of the Earth: 6,371 kilometers
const float aerosol_g = 0.8; // Asymmetry factor for mie phase function
const float aerosol_d = 1.6; // Mean diameter in µm

// https://www.desmos.com/calculator/giz0uiar7k
#define PreethamMieScatteringCoeff(turbidity) \
	max(vec3(-7.67542206226e-6, -8.22772032997e-6, -1.21707541321e-5) + \
		vec3( 7.71550875198e-6,  8.27069152678e-6, 	1.22343187466e-5) * turbidity, 0.0)

const vec3 mieCoeffBase = PreethamMieScatteringCoeff(exp2(ATMOSPHERE_TURBIDITY)) * sRGB_2_Rec2020;

// Every length is in m
const AtmosphereParameters atmosphere = AtmosphereParameters(
    planetRadius,
    planetRadius + ATMOSPHERE_THICKNESS,
    vec3(8.059375432e-6, 1.671209429e-5, 4.080133294e-5) * sRGB_2_Rec2020,
    mieCoeffBase * 0.9,
    mieCoeffBase,
    vec3(8.304280072e-7, 1.314911970e-6, 5.440679729e-8) * sRGB_2_Rec2020,
    vec3(0.2, 0.25, 0.45) * sRGB_2_Rec2020
);

const mat3 atmosphereExtinction = mat3(
	atmosphere.rayleighScattering,
	atmosphere.mieExtinction,
	atmosphere.ozoneExtinction
);

const mat2x3 atmosphereScattering = mat2x3(
	atmosphere.rayleighScattering,
	atmosphere.mieScattering
);

float atmosphereViewHeight = planetRadius + VIEWER_BASE_ALTITUDE + eyeAltitude;
vec3 atmosphereViewPos = vec3(0.0, atmosphereViewHeight, 0.0);

//================================================================================================//

vec2 RaySphereIntersection(vec3 pos, vec3 dir, float rad) {
	float PdotD = dot(pos, dir);
	float delta = sqr(PdotD) - sdot(pos) + sqr(rad);

	if (delta >= 0.0) {
		delta *= inversesqrt(delta);
		return vec2(-delta, delta) - PdotD;
	} else {
		return vec2(-1.0);
	}
}

vec2 RaySphereIntersection(float r, float mu, float rad) {
	float delta = sqr(r) * (sqr(mu) - 1.0) + sqr(rad);

	if (delta >= 0.0) {
		delta *= inversesqrt(delta);
		return vec2(-delta, delta) - r * mu;
	} else {
		return vec2(-1.0);
	}
}

vec2 RaySphericalShellIntersection(vec3 pos, vec3 dir, float bottomRad, float topRad) {
    vec2 bottomIntersection = RaySphereIntersection(pos, dir, bottomRad);
    vec2 topIntersection = RaySphereIntersection(pos, dir, topRad);

    if (topIntersection.y >= 0.0) {
		vec2 intersection;
		if (bottomIntersection.y < 0.0) {
			intersection.x = max0(topIntersection.x);
			intersection.y = topIntersection.y;
		} else if (bottomIntersection.x < 0.0) {
			intersection.x = bottomIntersection.y;
			intersection.y = topIntersection.y;
		} else {
			intersection.x = max0(topIntersection.x);
			intersection.y = bottomIntersection.x;
		}

		return intersection;
	} else {
		return vec2(-1.0);
	}
}

vec2 RaySphericalShellIntersection(float r, float mu, float bottomRad, float topRad) {
    vec2 bottomIntersection = RaySphereIntersection(r, mu, bottomRad);
    vec2 topIntersection = RaySphereIntersection(r, mu, topRad);

    if (topIntersection.y >= 0.0) {
		vec2 intersection;
		if (bottomIntersection.y < 0.0) {
			intersection.x = max0(topIntersection.x);
			intersection.y = topIntersection.y;
		} else if (bottomIntersection.x < 0.0) {
			intersection.x = bottomIntersection.y;
			intersection.y = topIntersection.y;
		} else {
			intersection.x = max0(topIntersection.x);
			intersection.y = bottomIntersection.x;
		}

		return intersection;
	} else {
		return vec2(-1.0);
	}
}

// From https://gamedev.stackexchange.com/questions/96459/fast-ray-sphere-collision-code.
// - ro: ray origin
// - rd: normalized ray direction
// - sr: sphere radius
// - Returns distance from ro to first intersecion with sphere,
//   or -1.0 if no intersection.
float RaySphereIntersectNearest(vec3 ro, vec3 rd, float sr) {
    float a = dot(rd, rd);
    float b = 2.0 * dot(rd, ro);
    float c = dot(ro, ro) - (sr * sr);
    float delta = b * b - 4.0 * a * c;
    if (delta < 0.0 || a == 0.0) {
        return -1.0;
    }
    float sol0 = (-b - sqrt(delta)) / (2.0 * a);
    float sol1 = (-b + sqrt(delta)) / (2.0 * a);
    if (sol0 < 0.0 && sol1 < 0.0) {
        return -1.0;
    }
    if (sol0 < 0.0) {
        return max0(sol1);
    } else if (sol1 < 0.0) {
        return max0(sol0);
    }
    return max0(min(sol0, sol1));
}

// https://doi.org/10.1364/JOSA.47.000176
float AirPhase(float mu) {
	return uniformPhase * 0.7629 * (1.0 + 0.932 * mu * mu);
}

// HG-Draine for aerosols
float AerosolPhase(float mu) {
    const float ld = log(aerosol_d);

    const float gHG = 0.0604931 * log(ld) + 0.940256;
    const float gD 	= 0.500411 - 0.081287 / (-2.0 * ld + tan(ld) + 1.27551);
    const float a 	= 7.30354 * ld + 6.31675;
    const float wD 	= 0.026914 * (ld - cos(5.68947 * (log(ld) - 0.0292149))) + 0.376475;

	return mix(HenyeyGreensteinPhase(mu, gHG), DrainePhase(mu, gD, a), wD);
}

vec2 AtmospherePhase(float mu) {
	return vec2(RayleighPhase(mu), AerosolPhase(mu));
}

vec3 LightningContribution(vec3 pos) {
	if (lightningBoltPosition.w < 0.5) return vec3(0.0);

    float distSq = sdot(lightningBoltPosition.xyz - pos);
	return vec3(0.32, 0.3, 1.0) * 5e5 / (1.0 + distSq);
}

vec3 LightningContribution(vec3 pos, vec3 normal) {
	if (lightningBoltPosition.w < 0.5) return vec3(0.0);

    vec3 vector = lightningBoltPosition.xyz - pos;
    float distSq = sdot(vector);
    vec3 lightDir = vector * inversesqrt(distSq);

    float diffuse = saturate(dot(normal, lightDir)) * 0.75 + 0.25;
	return vec3(0.32, 0.3, 1.0) * 5e3 / (1.0 + distSq) * diffuse;
}

//================================================================================================//

vec2 UnitToSubUv(vec2 uv, vec2 res) {
	return uv * (1.0 - 1.0 / res) + 0.5 / res;
}

// Transmittance LUT function parameterisation from Bruneton 2017 https://github.com/ebruneton/precomputed_atmospheric_scattering
// uv in [0, 1]
// mu in [-1, 1]
// r in [bottomRadius, topRadius]

void UvToLutTransmittanceParams(out float r, out float mu, vec2 uv) {
	float x_mu = uv.x;
	float x_r = uv.y;

	float H = sqrt(atmosphere.topRadius * atmosphere.topRadius - atmosphere.bottomRadius * atmosphere.bottomRadius);
	float rho = H * x_r;
	r = sqrt(rho * rho + atmosphere.bottomRadius * atmosphere.bottomRadius);

	float d_min = atmosphere.topRadius - r;
	float d_max = rho + H;
	float d = d_min + x_mu * (d_max - d_min);
	mu = d == 0.0 ? 1.0 : (H * H - rho * rho - d * d) / (2.0 * r * d);
	mu = clamp(mu, -1.0, 1.0);
}

vec2 LutTransmittanceParamsToUv(float r, float mu) {
	float H = sqrt(max0(atmosphere.topRadius * atmosphere.topRadius - atmosphere.bottomRadius * atmosphere.bottomRadius));
	float rho = sqrt(max0(r * r - atmosphere.bottomRadius * atmosphere.bottomRadius));

	float discriminant = r * r * (mu * mu - 1.0) + atmosphere.topRadius * atmosphere.topRadius;
	float d = max0(-r * mu + sqrt(discriminant)); // Distance to atmosphere boundary

	float d_min = atmosphere.topRadius - r;
	float d_max = rho + H;
	float x_mu = (d - d_min) / (d_max - d_min);
	float x_r = rho / H;

	return vec2(x_mu, x_r);
}

vec3 AtmosphereDensityAtPoint(vec3 pos) {
    float altitude = length(pos) - atmosphere.bottomRadius;
    return vec3(exp(-altitude * rcp(vec2(8e3, 1.4e3))), saturate(1.0 - abs(altitude - 2.5e4) * rcp(1.5e4)));
}

vec3 ReadTransmittanceLUT(float r, float mu) {
    vec2 uv = LutTransmittanceParamsToUv(r, mu);
    return texture(tLutTex, uv).rgb;
}

bool RayIntersectPlanetGround(float r, float mu) {
	return mu < 0.0 && r * r * (mu * mu - 1.0) + atmosphere.bottomRadius * atmosphere.bottomRadius >= 0.0;
}

vec3 AtmosphereTransmittanceToPoint(vec3 pos, vec3 dir) {
    float r = length(pos);
	float mu = dot(dir, pos) / r;
    float earthShadow = float(!RayIntersectPlanetGround(r, mu));

    return ReadTransmittanceLUT(r, mu) * earthShadow;
}

vec3 AtmosphereTransmittanceToSun(float r, float mu) {
	float sinThetaH = atmosphere.bottomRadius / r;
	float cosThetaH = sqrt(saturate(1.0 - sinThetaH * sinThetaH));
    float earthShadow = linearstep(-sinThetaH * sunAngularRadius, sinThetaH * sunAngularRadius, mu + cosThetaH);

	return ReadTransmittanceLUT(r, mu) * earthShadow;
}

vec3 AtmosphereTransmittanceToSun(vec3 pos, vec3 dir) {
    float r = length(pos);
	float mu = dot(dir, pos) / r;

	return AtmosphereTransmittanceToSun(r, mu);
}

vec3 AtmosphereMultiScattering(float r, float mu) {
    vec2 uv = vec2(saturate(0.5 + 0.5 * mu), linearstep(atmosphere.bottomRadius, atmosphere.topRadius, r));
    return texture(msLutTex, uv).rgb;
}

vec3 AtmosphereSkyView(vec3 viewPos, vec3 rayDir, vec3 sunDir) {
    float height = length(viewPos);
    vec3 up = viewPos / height;

	float viewZenithCos = dot(rayDir, up);
	vec3 sideVector = normalize(cross(up, rayDir));
	vec3 forwardVector = normalize(cross(sideVector, up));

    vec2 lightOnPlane = vec2(dot(sunDir, sideVector), dot(sunDir, forwardVector));
	float lightViewCos = normalize(lightOnPlane).y;

	vec2 uv;
	uv.x = sqrt(-lightViewCos * 0.5 + 0.5);

	float vHorizon = sqrt(height * height - atmosphere.bottomRadius * atmosphere.bottomRadius);
	float beta = fastAcos(vHorizon / height);
	float zenithHorizon = PI - beta;

	float coord = fastAcos(viewZenithCos);
	if (RayIntersectPlanetGround(height, viewZenithCos)) {
		coord = (coord - zenithHorizon) / beta;
		coord = sqrt(coord); // Non-linear mapping
		uv.y = coord * 0.5 + 0.5;
	} else {
		coord = 1.0 - coord / zenithHorizon;
		coord = sqrt(coord); // Non-linear mapping
		uv.y = (1.0 - coord) * 0.5;
	}

	uv = UnitToSubUv(uv, textureSize(skyViewTex, 0));
    return textureRGBE8(skyViewTex, saturate(uv));
}

bool AtmosphereSetupRay(inout vec3 rayPos, vec3 rayDir, out float tMax, out bool groundHit) {
    float viewHeight = length(rayPos);

    if (viewHeight > atmosphere.topRadius) {
        float tTop = RaySphereIntersectNearest(rayPos, rayDir, atmosphere.topRadius);
        if (tTop < 0.0) {
            return true; // No intersection with atmosphere
        }
        vec3 upVector = rayPos / viewHeight;
        rayPos += rayDir * tTop - upVector;
    }

    float tBottom = RaySphereIntersectNearest(rayPos, rayDir, atmosphere.bottomRadius);
    float tTop = RaySphereIntersectNearest(rayPos, rayDir, atmosphere.topRadius);

    if (tBottom < 0.0) {
        if (tTop < 0.0) {
            return true; // No intersection with earth nor atmosphere
        } else {
            tMax = tTop;
        }
    } else {
        if (tTop > 0.0) {
            tMax = min(tTop, tBottom);
        }
    }

    groundHit = tMax == tBottom;

    return false;
}
