
mat3 CalculateTBNMatrix(in vec3 position, in vec2 coord) {
    vec3 deltaPos1 = dFdx(position);
    vec3 deltaPos2 = dFdy(position);

	vec3 normal = mat3(gbufferModelViewInverse) * normalize(cross(deltaPos1, deltaPos2));

	#if defined NORMAL_MAPPING
        vec3 deltaPos1Perp = cross(normal, deltaPos1);
        vec3 deltaPos2Perp = cross(deltaPos2, normal);

        vec2 deltaUV1 = dFdx(coord);
        vec2 deltaUV2 = dFdy(coord);

        vec3 tangent   = normalize(deltaPos2Perp * deltaUV1.x + deltaPos1Perp * deltaUV2.x);
        vec3 bitangent = normalize(deltaPos2Perp * deltaUV1.y + deltaPos1Perp * deltaUV2.y);

        float invmax = inversesqrt(max(dotSelf(tangent), dotSelf(bitangent)));

        return mat3(tangent * invmax, bitangent * invmax, normal);
    #else
        return mat3(vec3(0.0), vec3(0.0), normal);
    #endif
}