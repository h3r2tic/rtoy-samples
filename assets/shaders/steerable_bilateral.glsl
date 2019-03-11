#include "rendertoy::shaders/random.inc"

uniform restrict writeonly image2D outputTex;
uniform sampler2D inputTex;
uniform sampler2D varianceTex;

layout(std430) buffer constants {
    float sharpen_amount;
};

const int max_sample_count = 1;
const float kernel_size_scaling = 5.0;

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);

	vec4 col = 0.0.xxxx;

    float variance_estimate = texelFetch(varianceTex, pix, 0).x;
    variance_estimate = max(variance_estimate, texelFetch(varianceTex, pix + ivec2(-1, 0), 0).x);
    variance_estimate = max(variance_estimate, texelFetch(varianceTex, pix + ivec2(+1, 0), 0).x);
    variance_estimate = max(variance_estimate, texelFetch(varianceTex, pix + ivec2(0, -1), 0).x);
    variance_estimate = max(variance_estimate, texelFetch(varianceTex, pix + ivec2(0, +1), 0).x);
    variance_estimate *= variance_estimate;
    
    uint seed0 = 38204;
    seed0 = hash(seed0 + 15488981u * uint(pix.x));
    seed0 = seed0 + 1302391u * uint(pix.y);

    int sample_count = max(1, min(int(max_sample_count * variance_estimate), int(max_sample_count)));
    //int sample_count = max_sample_count;

    for (int i = 0; i < sample_count; ++i) {
        const float golden_angle = 2.39996322972865332 + rand_float(hash(seed0));
        float angle = i * golden_angle + 1.0;
        //float dist = i == 0 ? 0.0 : float(i + 1.0);
        float dist = float(i);
        dist *= kernel_size_scaling;
        dist = sqrt(dist);

        vec2 off = vec2(cos(angle), sin(angle)) * dist;
        ivec2 xyoff = ivec2(off);

        float w = 1;
        col += vec4(texelFetch(inputTex, pix + xyoff, 0).rgb, 1.0) * w;
    }

    col /= col.w;

    //col.rgb = variance_estimate.xxx;

#if 0
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

    // TEMP HACK: tonemap
    {
        float tm_luma = 1.0 - exp(-calculate_luma(col.rgb));
        vec3 tm0 = col.rgb * max(0.0, tm_luma / max(1e-5, calculate_luma(col.rgb)));
        vec3 tm1 = col.rgb = 1.0 - exp(-col.rgb);
        col.rgb = mix(tm0, tm1, tm_luma * tm_luma);
        col.rgb = pow(max(0.0.xxx, col.rgb), 1.1.xxx);
    }

#else
    //col.rgb = col.rrr * col.rrr;
#endif

	imageStore(outputTex, pix, col);
}
