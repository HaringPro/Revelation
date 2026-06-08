// Remap thread index to 2D index following Z-order curve.
uvec2 RemapThread8x8(uint idx) {
	return uvec2((((idx >> 2) & 0x7) & 0xFFFE) | (idx & 0x1), ((idx >> 1) & 0x3) | (((idx >> 3) & 0x7) & 0xFFFC));
}

uvec2 RemapThread16x16(uint idx) {
	return RemapThread8x8(idx & 63) + (uvec2((idx >> 6) & 1, idx >> 7) << 3);
}

// https://developer.nvidia.com/blog/optimizing-compute-shaders-for-l2-locality-using-thread-group-id-swizzling/
// https://github.com/LouisBavoil/ThreadGroupIDSwizzling/blob/master/ThreadGroupTilingX.hlsl

// Normally argument "dipatchGridDim" is parsed through a constant buffer. However, if for some reason it is a
// static value, some DXC compiler versions will be unable to compile the code.
// If that's the case for you, flip DXC_STATIC_DISPATCH_GRID_DIM definition from 0 to 1.
#define DXC_STATIC_DISPATCH_GRID_DIM 0

// Divide the 2D-Dispatch_Grid into tiles of dimension [N, DipatchGridDim.y]
// “CTA” (Cooperative Thread Array) == Thread Group in DirectX terminology
uvec2 ThreadGroupTilingX(
	const uvec2 dipatchGridDim,	// Arguments of the Dispatch call (typically from a ConstantBuffer)
	const uvec2 ctaDim,			// Already known in HLSL, eg:[numthreads(8, 8, 1)] -> uvec2(8, 8)
	const uint maxTileWidth,	// User parameter (N). Recommended values: 8, 16 or 32.
	const uvec2 groupThreadID,	// SV_GroupThreadID
	const uvec2 groupId			// SV_GroupID
) {
	// A perfect tile is one with dimensions = [maxTileWidth, dipatchGridDim.y]
	const uint Number_of_CTAs_in_a_perfect_tile = maxTileWidth * dipatchGridDim.y;

	// Possible number of perfect tiles
	const uint Number_of_perfect_tiles = dipatchGridDim.x / maxTileWidth;

	// Total number of CTAs present in the perfect tiles
	const uint Total_CTAs_in_all_perfect_tiles = Number_of_perfect_tiles * maxTileWidth * dipatchGridDim.y;
	const uint vThreadGroupIDFlattened = dipatchGridDim.x * groupId.y + groupId.x;

	// Tile_ID_of_current_CTA : current CTA to TILE-ID mapping.
	const uint Tile_ID_of_current_CTA = vThreadGroupIDFlattened / Number_of_CTAs_in_a_perfect_tile;
	const uint Local_CTA_ID_within_current_tile = vThreadGroupIDFlattened % Number_of_CTAs_in_a_perfect_tile;
	uint Local_CTA_ID_y_within_current_tile;
	uint Local_CTA_ID_x_within_current_tile;

	if (Total_CTAs_in_all_perfect_tiles <= vThreadGroupIDFlattened) {
		// Path taken only if the last tile has imperfect dimensions and CTAs from the last tile are launched.
		uint X_dimension_of_last_tile = dipatchGridDim.x % maxTileWidth;
	#if DXC_STATIC_DISPATCH_GRID_DIM
		X_dimension_of_last_tile = max(1, X_dimension_of_last_tile);
	#endif
		Local_CTA_ID_y_within_current_tile = Local_CTA_ID_within_current_tile / X_dimension_of_last_tile;
		Local_CTA_ID_x_within_current_tile = Local_CTA_ID_within_current_tile % X_dimension_of_last_tile;
	} else {
		Local_CTA_ID_y_within_current_tile = Local_CTA_ID_within_current_tile / maxTileWidth;
		Local_CTA_ID_x_within_current_tile = Local_CTA_ID_within_current_tile % maxTileWidth;
	}

	const uint Swizzled_vThreadGroupIDFlattened =
		Tile_ID_of_current_CTA * maxTileWidth +
		Local_CTA_ID_y_within_current_tile * dipatchGridDim.x +
		Local_CTA_ID_x_within_current_tile;

	uvec2 SwizzledvThreadGroupID;
	SwizzledvThreadGroupID.y = Swizzled_vThreadGroupIDFlattened / dipatchGridDim.x;
	SwizzledvThreadGroupID.x = Swizzled_vThreadGroupIDFlattened % dipatchGridDim.x;

	uvec2 SwizzledvThreadID;
	SwizzledvThreadID.x = ctaDim.x * SwizzledvThreadGroupID.x + groupThreadID.x;
	SwizzledvThreadID.y = ctaDim.y * SwizzledvThreadGroupID.y + groupThreadID.y;

	return SwizzledvThreadID.xy;
}
