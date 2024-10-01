const ivec2 offset2x2[4] = ivec2[4](
	ivec2(0, 0), ivec2(1, 0),
	ivec2(0, 1), ivec2(1, 1)
);

const ivec2 offset3x3[9] = ivec2[9](
    ivec2(-1, -1), ivec2(0, -1), ivec2(1, -1),
    ivec2(-1,  0), ivec2(0,  0), ivec2(1,  0),
    ivec2(-1,  1), ivec2(0,  1), ivec2(1,  1)
);

const ivec2 offset3x3N[8] = ivec2[8](
    ivec2(-1, -1), ivec2(0, -1), ivec2(1, -1),
    ivec2(-1,  0), 				 ivec2(1,  0),
    ivec2(-1,  1), ivec2(0,  1), ivec2(1,  1)
);

const ivec2 offset4x4[16] = ivec2[16](
	ivec2(-2, -2), ivec2(-1, -2), ivec2(1, -2), ivec2(2, -2),
	ivec2(-2, -1), ivec2(-1, -1), ivec2(1, -1), ivec2(2, -1),
	ivec2(-2,  1), ivec2(-1,  1), ivec2(1,  1), ivec2(2,  1), 
	ivec2(-2,  2), ivec2(-1,  2), ivec2(1,  2), ivec2(2,  2)
);

const ivec2 offset5x5[25] = ivec2[25](
	ivec2(-2, -2), ivec2(-1, -2), ivec2(0, -2), ivec2(1, -2), ivec2(2, -2),
	ivec2(-2, -1), ivec2(-1, -1), ivec2(0, -1), ivec2(1, -1), ivec2(2, -1),
	ivec2(-2,  0), ivec2(-1,  0), ivec2(0,  0), ivec2(1,  0), ivec2(2,  0), 
	ivec2(-2,  1), ivec2(-1,  1), ivec2(0,  1), ivec2(1,  1), ivec2(2,  1), 
	ivec2(-2,  2), ivec2(-1,  2), ivec2(0,  2), ivec2(1,  2), ivec2(2,  2)
);

const ivec2 offset5x5N[24] = ivec2[24](
	ivec2(-2, -2), ivec2(-1, -2), ivec2(0, -2), ivec2(1, -2), ivec2(2, -2),
	ivec2(-2, -1), ivec2(-1, -1), ivec2(0, -1), ivec2(1, -1), ivec2(2, -1),
	ivec2(-2,  0), ivec2(-1,  0), 				ivec2(1,  0), ivec2(2,  0), 
	ivec2(-2,  1), ivec2(-1,  1), ivec2(0,  1), ivec2(1,  1), ivec2(2,  1), 
	ivec2(-2,  2), ivec2(-1,  2), ivec2(0,  2), ivec2(1,  2), ivec2(2,  2)
);

const ivec2 offset7x7[49] = ivec2[49](
	ivec2(-3, -3), ivec2(-2, -3), ivec2(-1, -3), ivec2(0, -3), ivec2(1, -3), ivec2(2, -3), ivec2(3, -3),
	ivec2(-3, -2), ivec2(-2, -2), ivec2(-1, -2), ivec2(0, -2), ivec2(1, -2), ivec2(2, -2), ivec2(3, -2),
	ivec2(-3, -1), ivec2(-2, -1), ivec2(-1, -1), ivec2(0, -1), ivec2(1, -1), ivec2(2, -1), ivec2(3, -1),
	ivec2(-3,  0), ivec2(-2,  0), ivec2(-1,  0), ivec2(0,  0), ivec2(1,  0), ivec2(2,  0), ivec2(3,  0),
	ivec2(-3,  1), ivec2(-2,  1), ivec2(-1,  1), ivec2(0,  1), ivec2(1,  1), ivec2(2,  1), ivec2(3,  1),
	ivec2(-3,  2), ivec2(-2,  2), ivec2(-1,  2), ivec2(0,  2), ivec2(1,  2), ivec2(2,  2), ivec2(3,  2),
	ivec2(-3,  3), ivec2(-2,  3), ivec2(-1,  3), ivec2(0,  3), ivec2(1,  3), ivec2(2,  3), ivec2(3,  3)
);

#if CLOUD_CBR_SCALE == 2
	const ivec2 checkerboardOffset[4] = ivec2[4](
		ivec2(0, 0), ivec2(1, 1),
		ivec2(1, 0), ivec2(0, 1)
	);
#elif CLOUD_CBR_SCALE == 3
	const ivec2 checkerboardOffset[9] = ivec2[9](
		ivec2(0, 0), ivec2(2, 0), ivec2(0, 2),
		ivec2(2, 2), ivec2(1, 1), ivec2(1, 0),
		ivec2(1, 2), ivec2(0, 1), ivec2(2, 1)
	);
#elif CLOUD_CBR_SCALE == 4
	const ivec2 checkerboardOffset[16] = ivec2[16](
		ivec2(0, 0), ivec2(2, 0), ivec2(0, 2), ivec2(2, 2),
		ivec2(1, 1), ivec2(3, 1), ivec2(1, 3), ivec2(3, 3),
		ivec2(1, 0), ivec2(3, 0), ivec2(1, 2), ivec2(3, 2),
		ivec2(0, 1), ivec2(2, 1), ivec2(0, 3), ivec2(2, 3)
	);
#endif