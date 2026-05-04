vec3 ScreenToViewPosRaw(vec3 screenPos) {
	vec3 ndcPos = screenPos * 2.0 - 1.0;
	return projectAndDivide(gbufferProjectionInverse, ndcPos);
}

vec3 ScreenToViewPos(vec3 screenPos) {
	vec3 ndcPos = screenPos * 2.0 - 1.0;
	#ifdef SHOULD_APPLY_JITTER
		ndcPos.xy -= taaJitter;
	#endif
	return projectAndDivide(gbufferProjectionInverse, ndcPos);
}

vec3 ScreenToViewPosRaw(vec2 screenPos, float viewDepth) {
	vec2 ndcPos = screenPos * 2.0 - 1.0;
	return vec3(diagonal2(gbufferProjectionInverse) * ndcPos * -viewDepth, viewDepth);
}

vec3 ScreenToViewPos(vec2 screenPos, float viewDepth) {
	vec2 ndcPos = screenPos * 2.0 - 1.0;
	#ifdef SHOULD_APPLY_JITTER
		ndcPos -= taaJitter;
	#endif
	return vec3(diagonal2(gbufferProjectionInverse) * ndcPos * -viewDepth, viewDepth);
}

vec3 ScreenToViewPos(vec2 screenPos) {
	vec3 ndcPos = vec3(screenPos, loadDepth0(uvToTexelScaled(screenPos))) * 2.0 - 1.0;
	#ifdef SHOULD_APPLY_JITTER
		ndcPos.xy -= taaJitter;
	#endif
	return projectAndDivide(gbufferProjectionInverse, ndcPos);
}

vec3 ViewToScreenPosRaw(vec3 viewPos) {
	vec3 ndcPos = projMAD(gbufferProjection, viewPos) * rcp(-viewPos.z);

	return ndcPos * 0.5 + 0.5;
}

vec3 ViewToScreenPos(vec3 viewPos) {
	vec3 ndcPos = projMAD(gbufferProjection, viewPos) * rcp(-viewPos.z);
	#ifdef SHOULD_APPLY_JITTER
		ndcPos.xy += taaJitter;
	#endif
	return ndcPos * 0.5 + 0.5;
}

vec3 ScreenToViewDirRaw(vec2 screenPos) {
	vec2 ndcPos = screenPos * 2.0 - 1.0;
	return normalize(vec3(diagonal2(gbufferProjectionInverse) * ndcPos, gbufferProjectionInverse[3].z));
}

vec3 ScreenToViewDir(vec2 screenPos) {
	vec2 ndcPos = screenPos * 2.0 - 1.0;
	#ifdef SHOULD_APPLY_JITTER
		ndcPos -= taaJitter;
	#endif
	return normalize(vec3(diagonal2(gbufferProjectionInverse) * ndcPos, gbufferProjectionInverse[3].z));
}

vec3 ReprojectScreenPos(vec3 screenPos) {
	vec3 position = ScreenToViewPosRaw(screenPos); // To view
	position = transMAD(gbufferModelViewInverse, position); // To world

	position += cameraMovement * step(0.56, screenPos.z); // To previous world
	position = transMAD(gbufferPreviousModelView, position); // To previous view
	position = projMAD(gbufferPreviousProjection, position) * rcp(-position.z); // To previous NDC

	return position * 0.5 + 0.5;
}

float ScreenToViewDepth(float depth) {
	return -gbufferProjection[3].z / (gbufferProjection[2].z + (depth * 2.0 - 1.0));
}

float ViewToScreenDepth(float depth) {
	return 0.5 - (gbufferProjection[3].z / depth + gbufferProjection[2].z) * 0.5;
}

//================================================================================================//

#if defined LOD_MOD
	vec3 ScreenToViewPosRawLod(vec3 screenPos) {
		vec3 ndcPos = screenPos * 2.0 - 1.0;
		return projectAndDivide(lodProjectionInv, ndcPos);
	}

	vec3 ScreenToViewPosLod(vec3 screenPos) {
		vec3 ndcPos = screenPos * 2.0 - 1.0;
		#ifdef SHOULD_APPLY_JITTER
			ndcPos.xy -= taaJitter;
		#endif
		return projectAndDivide(lodProjectionInv, ndcPos);
	}

	vec3 ScreenToViewPosLod(vec2 screenPos) {
		vec3 ndcPos = vec3(screenPos, loadDepth0Lod(uvToTexel(screenPos))) * 2.0 - 1.0;
		#ifdef SHOULD_APPLY_JITTER
			ndcPos.xy -= taaJitter;
		#endif
		return projectAndDivide(lodProjectionInv, ndcPos);
	}

	vec3 ViewToScreenPosRawLod(vec3 viewPos) {
		vec3 ndcPos = projMAD(lodProjection, viewPos) * rcp(-viewPos.z);

		return ndcPos * 0.5 + 0.5;
	}

	vec3 ViewToScreenPosLod(vec3 viewPos) {
		vec3 ndcPos = projMAD(lodProjection, viewPos) * rcp(-viewPos.z);
		#ifdef SHOULD_APPLY_JITTER
			ndcPos.xy += taaJitter;
		#endif
		return ndcPos * 0.5 + 0.5;
	}

	vec3 ReprojectScreenPosLod(vec3 screenPos) {
		vec3 position = ScreenToViewPosRawLod(screenPos); // To view
		position = transMAD(gbufferModelViewInverse, position); // To world

		position += cameraMovement/*  * step(0.56, screenPos.z) */; // To previous world
		position = transMAD(gbufferPreviousModelView, position); // To previous view
		position = projMAD(lodPrevProjection, position) * rcp(-position.z); // To previous NDC

		return position * 0.5 + 0.5;
	}

	float ScreenToViewDepthLod(float depth) {
		return -lodProjection[3].z / (lodProjection[2].z + (depth * 2.0 - 1.0));
	}

	float ViewToScreenDepthLod(float depth) {
		return 0.5 - (lodProjection[3].z / depth + lodProjection[2].z) * 0.5;
	}
#endif
