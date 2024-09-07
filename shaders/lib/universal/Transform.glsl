vec3 ScreenToViewSpaceRaw(in vec3 screenPos) {	
	vec3 NDCPos = screenPos * 2.0 - 1.0;
	vec3 viewPos = projMAD(gbufferProjectionInverse, NDCPos);
	viewPos /= gbufferProjectionInverse[2].w * NDCPos.z + gbufferProjectionInverse[3].w;

	return viewPos;
}

vec3 ScreenToViewSpace(in vec3 screenPos) {
	vec3 NDCPos = screenPos * 2.0 - 1.0;
	#ifdef TAA_ENABLED
		NDCPos.xy -= taaOffset;
	#endif
	vec3 viewPos = projMAD(gbufferProjectionInverse, NDCPos);
	viewPos /= gbufferProjectionInverse[2].w * NDCPos.z + gbufferProjectionInverse[3].w;

	return viewPos;
}

vec3 ScreenToViewSpace(in vec2 coord) {
	vec3 NDCPos = vec3(coord, texelFetch(depthtex0, rawCoord(coord), 0).x) * 2.0 - 1.0;
	#ifdef TAA_ENABLED
		NDCPos.xy -= taaOffset;
	#endif
	vec3 viewPos = projMAD(gbufferProjectionInverse, NDCPos);
	viewPos /= gbufferProjectionInverse[2].w * NDCPos.z + gbufferProjectionInverse[3].w;

	return viewPos;
}

vec3 ViewToScreenSpaceRaw(in vec3 viewPos) {
	vec3 NDCPos = projMAD(gbufferProjection, viewPos) / -viewPos.z;

	return NDCPos * 0.5 + 0.5;
}

vec3 ViewToScreenSpace(in vec3 viewPos) {
	vec3 NDCPos = projMAD(gbufferProjection, viewPos) / -viewPos.z;
	#ifdef TAA_ENABLED
		NDCPos.xy += taaOffset;
	#endif
	return NDCPos * 0.5 + 0.5;
}

vec3 Reproject(in vec3 screenPos) {
	vec3 position = ScreenToViewSpaceRaw(screenPos); // To view space
    position = transMAD(gbufferModelViewInverse, position); // To world space

	if (screenPos.z > 0.56) position += cameraPosition - previousCameraPosition; // To previous frame's world space
    position = transMAD(gbufferPreviousModelView, position); // To previous frame's view space
	position = projMAD(gbufferPreviousProjection, position) / -position.z; // To previous frame's NDC space

    return position * 0.5 + 0.5;
}

float ScreenToViewDepth(in float depth) {
	return gbufferProjection[3].z / (gbufferProjection[2].z + (depth * 2.0 - 1.0));
}

float ViewToScreenDepth(in float depth) {
	return (gbufferProjection[3].z - gbufferProjection[2].z * depth) / depth * 0.5 + 0.5;
}

float ScreenToLinearDepth(in float depth) {
    return (near * far) / (depth * (near - far) + far);
}

float LinearToScreenDepth(in float depthLinear) {
	return (far + near) / (far - near) + (2.0 * far * near) / (depthLinear * (far - near));
}
