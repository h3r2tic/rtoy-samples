// Rec. 709
float calculate_luma(vec3 col) {
	return dot(vec3(0.2126, 0.7152, 0.0722), col);
}

// Rec. 709
vec3 rgb_to_ycbcr(vec3 col) {
    mat3 m = mat3(0.2126, 0.7152, 0.0722, -0.1146,-0.3854, 0.5, 0.5,-0.4542,-0.0458);
    return col * m;
}

// Rec. 709
vec3 ycbcr_to_rgb(vec3 col) {
    mat3 m = mat3(1.0, 0.0, 1.5748, 1.0, -0.1873, -.4681, 1.0, 1.8556, 0.0);
    return col * m;
}
