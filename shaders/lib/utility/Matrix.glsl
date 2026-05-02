
mat4 BuildOrthoMat(float left, float right, float bottom, float top, float near, float far) {
	float rw = rcp(left - right);
	float rh = rcp(bottom - top);
	float rd = rcp(near - far);

	return mat4(
		-2.0 * rw, 0.0, 0.0, 0.0,
		0.0, -2.0 * rh, 0.0, 0.0,
		0.0, 0.0, 2.0 * rd, 0.0,
		(left + right) * rw, (bottom + top) * rh, (near + far) * rd, 1.0
	);
}

mat4 BuildOrthoMat(float width, float height, float near, float far) {
	float rw = rcp(width);
	float rh = rcp(height);
	float rd = rcp(near - far);

	return mat4(
		-2.0 * rw, 0.0, 0.0, 0.0,
		0.0, -2.0 * rh, 0.0, 0.0,
		0.0, 0.0, 2.0 * rd, 0.0,
		0.0, 0.0, (near + far) * rd, 1.0
	);
}

mat4 BuildPerspectiveMat(float fov, float aspect, float near, float far) {
	float f = 1.0 / tan(fov * (PI / 180.0));
	float rd = rcp(near - far);

	return mat4(
		f / aspect, 0.0, 0.0, 0.0,
		0.0, f, 0.0, 0.0,
		0.0, 0.0, (near + far) * rd, -1.0,
		0.0, 0.0, near * far * rd * 2.0, 0.0
	);
}

// https://www.jcgt.org/published/0006/01/01/
mat3 BuildOrthonormalBasis(vec3 n) {
	float s = n.z < 0.0 ? -1.0 : 1.0;
	float a = -rcp(s + n.z);
	float b = n.x * n.y * a;

	vec3 b1 = vec3(1.0 + s * n.x * n.x * a, s * b, -s * n.x);
	vec3 b2 = vec3(b, s + n.y * n.y * a, -n.y);

	return mat3(b1, b2, n);
}

mat2 rotateMat(float angle) {
	float cosine = cos(angle);
	float sine = sin(angle);
	return mat2(cosine, -sine, sine, cosine);
}

mat3 rotateMatX(float angle) {
	float cosine = cos(angle);
	float sine = sin(angle);
	return mat3(1.0, 0.0, 0.0, 0.0, cosine, -sine, 0.0, sine, cosine);
}

mat3 rotateMatY(float angle) {
	float cosine = cos(angle);
	float sine = sin(angle);
	return mat3(cosine, 0.0, sine, 0.0, 1.0, 0.0, -sine, 0.0, cosine);
}

mat3 rotateMatZ(float angle) {
	float cosine = cos(angle);
	float sine = sin(angle);
	return mat3(cosine, -sine, 0.0, sine, cosine, 0.0, 0.0, 0.0, 1.0);
}
