// Rec. 709
float calculate_luma(float3 col) {
	return dot(float3(0.2126, 0.7152, 0.0722), col);
}

// Rec. 709
float3 rgb_to_ycbcr(float3 col) {
    float3x3 m = float3x3(0.2126, 0.7152, 0.0722, -0.1146,-0.3854, 0.5, 0.5,-0.4542,-0.0458);
    return mul(col, m);
}

// Rec. 709
float3 ycbcr_to_rgb(float3 col) {
    float3x3 m = float3x3(1.0, 0.0, 1.5748, 1.0, -0.1873, -.4681, 1.0, 1.8556, 0.0);
    return mul(col, m);
}
