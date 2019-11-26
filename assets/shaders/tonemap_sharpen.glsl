uniform restrict writeonly layout(binding = 0) image2D outputTex;
uniform layout(binding = 1) texture2D inputTex;
layout(std140, binding = 2) uniform globals {
    float sharpen_amount;
};

// Rec. 709
float calculate_luma(vec3 col) {
	return dot(vec3(0.2126, 0.7152, 0.0722), col);
}

float tonemap_curve(float v) {
    // Similar in shape, but more linear (less compression) in the mids
    float c = v + v*v + 0.5*v*v*v;
    return c / (1.0 + c);
}

vec3 tonemap_curve(vec3 v) {
    return vec3(tonemap_curve(v.r), tonemap_curve(v.g), tonemap_curve(v.b));
}

vec3 neutral_tonemap(vec3 col) {
    mat3 ycbr_mat = mat3(.2126, .7152, .0722, -.1146,-.3854, .5, .5,-.4542,-.0458);
    vec3 ycbcr = col * ycbr_mat;

    float chroma = length(ycbcr.yz) * 2.4;
    float bt = tonemap_curve(chroma);

    float desat = max((bt - 0.7) * 0.8, 0.0);
    desat *= desat;

    vec3 desat_col = mix(col.rgb, ycbcr.xxx, desat);

    float tm_luma = tonemap_curve(ycbcr.x);
    vec3 tm0 = col.rgb * max(0.0, tm_luma / max(1e-5, calculate_luma(col.rgb)));
    float final_mult = 0.97;
    vec3 tm1 = tonemap_curve(desat_col);

    col = mix(tm0, tm1, bt * bt);

    return col * final_mult;
}

float sharpen_remap(float l) {
    return sqrt(l);
}

float sharpen_inv_remap(float l) {
    return l * l;
}

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
	vec4 col = texelFetch(inputTex, pix, 0);

#if 1
	float neighbors = 0;
	float wt_sum = 0;

	const ivec2 dim_offsets[] = { ivec2(1, 0), ivec2(0, 1) };

	float center = sharpen_remap(calculate_luma(col.rgb));
    vec2 wts;

	for (int dim = 0; dim < 2; ++dim) {
		ivec2 n0coord = pix + dim_offsets[dim];
		ivec2 n1coord = pix - dim_offsets[dim];

		float n0 = sharpen_remap(calculate_luma(texelFetch(inputTex, n0coord, 0).rgb));
		float n1 = sharpen_remap(calculate_luma(texelFetch(inputTex, n1coord, 0).rgb));
		float wt = max(0, 1.0 - 6.0 * (abs(center - n0) + abs(center - n1)));
        wt = min(wt, sharpen_amount * wt * 1.25);
        
		neighbors += n0 * wt;
		neighbors += n1 * wt;
		wt_sum += wt * 2;
	}

    float sharpened_luma = max(0, center * (wt_sum + 1) - neighbors);
    sharpened_luma = sharpen_inv_remap(sharpened_luma);

	col.rgb *= max(0.0, sharpened_luma / max(1e-5, calculate_luma(col.rgb)));
#endif

    col.rgb = neutral_tonemap(col.rgb);
    //col.r = col.a * 10.0;
    //col.rgb = 1.0 - exp(-col.rgb);

	imageStore(outputTex, pix, col);
}
