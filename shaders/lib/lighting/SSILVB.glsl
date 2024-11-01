// Adapted from "Screen Space sBitMask Lighting with Visibility Bitmask" by Olivier Therrien, et al.
// https://cdrinmatane.github.io/posts/cgspotlight-slides/

/*
// const bool colortex4MipmapEnabled = true;
*/

vec3 ScreenToViewSpace(in vec2 screenCoord) {
	vec3 NDCPos = vec3(screenCoord, readDepth0(uvToTexel(screenCoord))) * 2.0 - 1.0;
	#ifdef TAA_ENABLED
		NDCPos.xy -= taaOffset;
	#endif
	vec3 viewPos = projMAD(gbufferProjectionInverse, NDCPos);
	viewPos /= gbufferProjectionInverse[2].w * NDCPos.z + gbufferProjectionInverse[3].w;

	return viewPos;
}

// https://cdrinmatane.github.io/posts/ssaovb-code/
const uint sectorCount = 32u;
uint updateSectors(float minHorizon, float maxHorizon, uint outBitfield) {
    uint startBit = uint(minHorizon * float(sectorCount));
    uint horizonAngle = uint(ceil((maxHorizon - minHorizon) * float(sectorCount)));
    uint angleBit = horizonAngle > 0u ? uint(0xFFFFFFFFu >> (sectorCount - horizonAngle)) : 0u;
    uint currentBitfield = angleBit << startBit;
    return outBitfield | currentBitfield;
}

vec4 CalculateSSILVB(in vec2 fragUV, in vec3 position, in vec3 normal) {
	const uint sliceCount = 4u;
	const uint sampleCount = 4u;
	const float sampleRadius = 4.0;
	const float hitThickness = 2.0;

	const float rSliceCount = 1.0 / float(sliceCount);
	const float rSampleCount = 1.0 / float(sampleCount);
	const float rSectorCount = 1.0 / float(sectorCount);

    NoiseGenerator noiseGenerator = initNoiseGenerator(gl_GlobalInvocationID.xy, uint(frameCounter));
    vec2 dither = nextVec2(noiseGenerator);

    uint bitMask = 0u;

    float visibility = 0.0;
    vec3 lighting = vec3(0.0);
    vec2 frontBackHorizon = vec2(0.0);
    vec2 aspect = vec2(1.0, aspectRatio);
    vec3 camera = normalize(-position);

    float sliceRotation = TAU / float(sliceCount - 1u);
    float sampleScale = (-sampleRadius * gbufferProjection[0][0]) / position.z;

    for (uint slice = 0u; slice < sliceCount; ++slice) {
        float phi = sliceRotation * (float(slice) + dither.x) + PI;
        vec2 omega = vec2(cos(phi), sin(phi));
        vec3 direction = vec3(omega, 0.0);
        vec3 orthoDirection = direction - dot(direction, camera) * camera;
        vec3 axis = cross(direction, camera);
        vec3 projNormal = normal - axis * dot(normal, axis);
        float projNorm = inversesqrt(dot(projNormal, projNormal));

        float signN = fastSign(dot(orthoDirection, projNormal));
        float cosN = saturate(dot(projNormal, camera) * projNorm);
        float n = signN * fastAcos(cosN);

        for (uint currentSample = 0u; currentSample < sampleCount; ++currentSample) {
            float sampleStep = (float(currentSample) + dither.y) * rSampleCount;
            vec2 sampleUV = fragUV - sampleStep * sampleScale * omega * aspect;

			if (saturate(sampleUV) == sampleUV) {
				vec3 sampleDiff = ScreenToViewSpace(sampleUV) - position;
				vec3 sampleDirFront = normalize(sampleDiff);
				vec3 sampleDirBack = normalize(sampleDiff - camera * hitThickness);

				frontBackHorizon.x = fastAcos(dot(sampleDirFront, camera));
				frontBackHorizon.y = fastAcos(dot(sampleDirBack, camera));

				frontBackHorizon = saturate((frontBackHorizon + n + hPI) * rPI);

				uint sBitMask = updateSectors(frontBackHorizon.x, frontBackHorizon.y, 0u);
				uint sampleOccludedBit = bitCount(sBitMask & ~bitMask);

				if (sampleOccludedBit > 0u) {
					vec3 sampleNormal = mat3(gbufferModelView) * FetchWorldNormal(readGbufferData0(uvToTexel(sampleUV)));
                    // uint mipLevel = min((currentSample + 1u) >> 2u, 4u);
					vec3 sampleRadiance = textureLod(colortex4, sampleUV * 0.5, 0.0).rgb;
					lighting += float(sampleOccludedBit) * 
						saturate(dot(normal, sampleDirFront)) *
						saturate(dot(sampleNormal, -sampleDirFront)) *
						sampleRadiance;

					bitMask |= sBitMask;
				}
			}
        }
        visibility += float(bitCount(bitMask));
    }

    return vec4(lighting, visibility)/*  * rSectorCount */ * rSliceCount;
}
