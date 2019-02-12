uniform restrict writeonly image2D outputTex;
uniform sampler2D inputTex;

float calculate_luma(vec3 col) {
	return dot(vec3(0.299, 0.587, 0.114), col);
}

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
	vec4 col = texelFetch(inputTex, pix, 0);

	const float sharpen_amount = 0.5;

	float neighbors = 0;
	float wt_sum = 0;

	const ivec2 dim_offsets[] = { ivec2(1, 0), ivec2(0, 1) };

	float center = calculate_luma(col.rgb);

	for (int dim = 0; dim < 2; ++dim) {
		ivec2 n0coord = pix + dim_offsets[dim];
		ivec2 n1coord = pix - dim_offsets[dim];

		float n0 = calculate_luma(texelFetch(inputTex, n0coord, 0).rgb);
		float n1 = calculate_luma(texelFetch(inputTex, n1coord, 0).rgb);
		float wt = max(0, 1 - 4 * (abs(center - n0) + abs(center - n1)));
		neighbors += n0 * wt;
		neighbors += n1 * wt;
		wt_sum += wt * 2;
	}

	float sharpened_luma = max(0, center * (wt_sum * sharpen_amount + 1) - neighbors * sharpen_amount);

	col.rgb *= max(0.0, sharpened_luma / max(1e-5, center));
	imageStore(outputTex, pix, col);
}
