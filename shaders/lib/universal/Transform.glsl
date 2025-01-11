vec3 ScreenToViewSpaceRaw(in vec3 screenPos) {	
	vec3 NDCPos = screenPos * 2.0 - 1.0;
	vec3 viewPos = projMAD(gbufferProjectionInverse, NDCPos);
	viewPos *= rcp(gbufferProjectionInverse[2].w * NDCPos.z + gbufferProjectionInverse[3].w);

	return viewPos;
}

vec3 ScreenToViewSpace(in vec3 screenPos) {
	vec3 NDCPos = screenPos * 2.0 - 1.0;
	#ifdef TAA_ENABLED
		NDCPos.xy -= taaOffset;
	#endif
	vec3 viewPos = projMAD(gbufferProjectionInverse, NDCPos);
	viewPos *= rcp(gbufferProjectionInverse[2].w * NDCPos.z + gbufferProjectionInverse[3].w);

	return viewPos;
}

vec3 ScreenToViewSpaceRaw(in vec2 screenCoord, in float linearDepth) {
	vec2 NDCCoord = screenCoord * 2.0 - 1.0;
	return vec3(diagonal2(gbufferProjectionInverse) * NDCCoord, gbufferProjectionInverse[3].z) * linearDepth;
}

vec3 ScreenToViewSpace(in vec2 screenCoord, in float linearDepth) {
	vec2 NDCCoord = screenCoord * 2.0 - 1.0;
	#ifdef TAA_ENABLED
		NDCCoord -= taaOffset;
	#endif
	return vec3(diagonal2(gbufferProjectionInverse) * NDCCoord, gbufferProjectionInverse[3].z) * linearDepth;
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

	position += (cameraPosition - previousCameraPosition) * step(0.56, screenPos.z); // To previous frame's world space
    position = transMAD(gbufferPreviousModelView, position); // To previous frame's view space
	position = projMAD(gbufferPreviousProjection, position) * rcp(-position.z); // To previous frame's NDC space

    return position * 0.5 + 0.5;
}

float ScreenToViewDepth(in float depth) {
	return gbufferProjection[3].z / (gbufferProjection[2].z + (depth * 2.0 - 1.0));
}

float ViewToScreenDepth(in float depth) {
	return (gbufferProjection[3].z - gbufferProjection[2].z * depth) / depth * 0.5 + 0.5;
}

//======// Distant Horizons Transform Function //=================================================//
/*
#if defined DISTANT_HORIZONS
	vec3 ScreenToViewSpaceRawDH(in vec3 screenPos) {	
		vec3 NDCPos = screenPos * 2.0 - 1.0;
		vec3 viewPos = projMAD(dhProjectionInverse, NDCPos);
		viewPos *= rcp(dhProjectionInverse[2].w * NDCPos.z + dhProjectionInverse[3].w);

		return viewPos;
	}

	vec3 ScreenToViewSpaceDH(in vec3 screenPos) {
		vec3 NDCPos = screenPos * 2.0 - 1.0;
		#ifdef TAA_ENABLED
			NDCPos.xy -= taaOffset;
		#endif
		vec3 viewPos = projMAD(dhProjectionInverse, NDCPos);
		viewPos *= rcp(dhProjectionInverse[2].w * NDCPos.z + dhProjectionInverse[3].w);

		return viewPos;
	}

	vec3 ScreenToViewSpaceDH(in vec2 coord) {
		vec3 NDCPos = vec3(coord, texelFetch(dhDepthTex0, uvToTexel(coord), 0).x) * 2.0 - 1.0;
		#ifdef TAA_ENABLED
			NDCPos.xy -= taaOffset;
		#endif
		vec3 viewPos = projMAD(dhProjectionInverse, NDCPos);
		viewPos *= rcp(dhProjectionInverse[2].w * NDCPos.z + dhProjectionInverse[3].w);

		return viewPos;
	}

	vec3 ViewToScreenSpaceRawDH(in vec3 viewPos) {
		vec3 NDCPos = projMAD(dhProjection, viewPos) * rcp(-viewPos.z);

		return NDCPos * 0.5 + 0.5;
	}

	vec3 ViewToScreenSpaceDH(in vec3 viewPos) {
		vec3 NDCPos = projMAD(dhProjection, viewPos) * rcp(-viewPos.z);
		#ifdef TAA_ENABLED
			NDCPos.xy += taaOffset;
		#endif
		return NDCPos * 0.5 + 0.5;
	}

	vec3 ReprojectDH(in vec3 screenPos) {
		vec3 position = ScreenToViewSpaceRawDH(screenPos); // To view space
		position = transMAD(gbufferModelViewInverse, position); // To world space

		position += (cameraPosition - previousCameraPosition) * step(0.56, screenPos.z); // To previous frame's world space
		position = transMAD(gbufferPreviousModelView, position); // To previous frame's view space
		position = projMAD(dhPreviousProjection, position) * rcp(-position.z); // To previous frame's NDC space

		return position * 0.5 + 0.5;
	}

	float ScreenToViewDepthDH(in float depth) {
		return dhProjection[3].z / (dhProjection[2].z + (depth * 2.0 - 1.0));
	}

	float ViewToScreenDepthDH(in float depth) {
		return (dhProjection[3].z - dhProjection[2].z * depth) / depth * 0.5 + 0.5;
	}
#endif
*/