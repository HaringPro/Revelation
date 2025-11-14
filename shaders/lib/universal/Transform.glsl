vec3 ProjectDivide(in vec3 v, in mat4 m) {
	return projMAD(m, v) * rcp(m[2].w * v.z + m[3].w);
}

vec3 ScreenToViewSpaceRaw(in vec3 screenPos) {
	vec3 NDCPos = screenPos * 2.0 - 1.0;
	return ProjectDivide(NDCPos, gbufferProjectionInverse);
}

vec3 ScreenToViewSpace(in vec3 screenPos) {
	vec3 NDCPos = screenPos * 2.0 - 1.0;
	#ifdef TAA_ENABLED
		NDCPos.xy -= taaOffset;
	#endif
	return ProjectDivide(NDCPos, gbufferProjectionInverse);
}

vec3 ScreenToViewSpaceRaw(in vec2 screenCoord, in float viewDepth) {
	vec2 NDCCoord = screenCoord * 2.0 - 1.0;
	return vec3(diagonal2(gbufferProjectionInverse) * NDCCoord * -viewDepth, viewDepth);
}

vec3 ScreenToViewSpace(in vec2 screenCoord, in float viewDepth) {
	vec2 NDCCoord = screenCoord * 2.0 - 1.0;
	#ifdef TAA_ENABLED
		NDCCoord -= taaOffset;
	#endif
	return vec3(diagonal2(gbufferProjectionInverse) * NDCCoord * -viewDepth, viewDepth);
}

vec3 ScreenToViewSpace(in vec2 screenCoord) {
	vec3 NDCPos = vec3(screenCoord, loadDepth0(uvToTexel(screenCoord))) * 2.0 - 1.0;
	#ifdef TAA_ENABLED
		NDCPos.xy -= taaOffset;
	#endif
	return ProjectDivide(NDCPos, gbufferProjectionInverse);
}

vec3 ViewToScreenSpaceRaw(in vec3 viewPos) {
	vec3 NDCPos = projMAD(gbufferProjection, viewPos) * rcp(-viewPos.z);

	return NDCPos * 0.5 + 0.5;
}

vec3 ViewToScreenSpace(in vec3 viewPos) {
	vec3 NDCPos = projMAD(gbufferProjection, viewPos) * rcp(-viewPos.z);
	#ifdef TAA_ENABLED
		NDCPos.xy += taaOffset;
	#endif
	return NDCPos * 0.5 + 0.5;
}

vec3 ScreenToViewVectorRaw(in vec2 screenCoord) {
	vec2 NDCCoord = screenCoord * 2.0 - 1.0;
	return normalize(vec3(diagonal2(gbufferProjectionInverse) * NDCCoord, gbufferProjectionInverse[3].z));
}

vec3 ScreenToViewVector(in vec2 screenCoord) {
	vec2 NDCCoord = screenCoord * 2.0 - 1.0;
	#ifdef TAA_ENABLED
		NDCCoord -= taaOffset;
	#endif
	return normalize(vec3(diagonal2(gbufferProjectionInverse) * NDCCoord, gbufferProjectionInverse[3].z));
}

vec3 Reproject(in vec3 screenPos) {
	vec3 position = ScreenToViewSpaceRaw(screenPos); // To view space
    position = transMAD(gbufferModelViewInverse, position); // To world space

	position += cameraMovement * step(0.56, screenPos.z); // To previous frame's world space
    position = transMAD(gbufferPreviousModelView, position); // To previous frame's view space
	position = projMAD(gbufferPreviousProjection, position) * rcp(-position.z); // To previous frame's NDC space

    return position * 0.5 + 0.5;
}

float ScreenToViewDepth(in float depth) {
	return -gbufferProjection[3].z / (gbufferProjection[2].z + (depth * 2.0 - 1.0));
}

float ViewToScreenDepth(in float depth) {
	return 0.5 - (gbufferProjection[3].z / depth + gbufferProjection[2].z) * 0.5;
}

//======// LoD Mods Transform Function //=================================================//

#if defined DISTANT_HORIZONS || defined VOXY
	vec3 ScreenToViewSpaceRawLod(in vec3 screenPos) {
		vec3 NDCPos = screenPos * 2.0 - 1.0;
		return ProjectDivide(NDCPos, lodProjInv);
	}

	vec3 ScreenToViewSpaceLod(in vec3 screenPos) {
		vec3 NDCPos = screenPos * 2.0 - 1.0;
		#ifdef TAA_ENABLED
			NDCPos.xy -= taaOffset;
		#endif
		return ProjectDivide(NDCPos, lodProjInv);
	}

	vec3 ScreenToViewSpaceLod(in vec2 screenCoord) {
		vec3 NDCPos = vec3(screenCoord, loadDepthTransLod(uvToTexel(screenCoord))) * 2.0 - 1.0;
		#ifdef TAA_ENABLED
			NDCPos.xy -= taaOffset;
		#endif
		return ProjectDivide(NDCPos, lodProjInv);
	}

	vec3 ViewToScreenSpaceRawLod(in vec3 viewPos) {
		vec3 NDCPos = projMAD(lodProj, viewPos) * rcp(-viewPos.z);

		return NDCPos * 0.5 + 0.5;
	}

	vec3 ViewToScreenSpaceLod(in vec3 viewPos) {
		vec3 NDCPos = projMAD(lodProj, viewPos) * rcp(-viewPos.z);
		#ifdef TAA_ENABLED
			NDCPos.xy += taaOffset;
		#endif
		return NDCPos * 0.5 + 0.5;
	}

	vec3 ReprojectLod(in vec3 screenPos) {
		vec3 position = ScreenToViewSpaceRawLod(screenPos); // To view space
		position = transMAD(gbufferModelViewInverse, position); // To world space

		position += cameraMovement/*  * step(0.56, screenPos.z) */; // To previous frame's world space
		position = transMAD(gbufferPreviousModelView, position); // To previous frame's view space
		position = projMAD(lodProjPrev, position) * rcp(-position.z); // To previous frame's NDC space

		return position * 0.5 + 0.5;
	}

	float ScreenToViewDepthLod(in float depth) {
		return -lodProj[3].z / (lodProj[2].z + (depth * 2.0 - 1.0));
	}

	float ViewToScreenDepthLod(in float depth) {
		return 0.5 - (lodProj[3].z / depth + lodProj[2].z) * 0.5;
	}
#endif
