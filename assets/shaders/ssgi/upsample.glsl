#include "../inc/pack_unpack.inc"
#include "../inc/uv.inc"

uniform texture2D ssgiTex;
uniform texture2D gbufferTex;

uniform restrict writeonly image2D outputTex;

layout(std140) uniform globals {
    vec4 outputTex_size;
};

vec4 process_sample(vec4 ssgi, float depth, vec3 normal, float center_depth, vec3 center_normal, inout float w_sum) {
    if (depth != 0.0)
    {
        float depth_diff = 1.0 - (center_depth / depth);
        float depth_factor = exp2(-200.0 * abs(depth_diff));

        float normal_factor = max(0.0, dot(normal, center_normal));
        normal_factor *= normal_factor;
        normal_factor *= normal_factor;
        normal_factor *= normal_factor;

        float w = 1;
        w *= depth_factor;  // TODO: differentials
        w *= normal_factor;

        w_sum += w;
        return ssgi * w;
    } else {
        return 0.0.xxxx;
    }
}

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    vec4 result = 0.0.xxxx;
    float w_sum = 0.0;

    float center_depth = texelFetch(gbufferTex, pix, 0).w;
    if (center_depth != 0.0) {
        vec3 center_normal = unpack_normal_11_10_11(texelFetch(gbufferTex, pix, 0).x);

    	vec4 center_ssgi = 0.0.xxxx;
        w_sum = 0.0;
        result = center_ssgi;

        const int kernel_half_size = 1;
        for (int y = -kernel_half_size; y <= kernel_half_size; ++y) {
            for (int x = -kernel_half_size; x <= kernel_half_size; ++x) {
                ivec2 sample_pix = pix / 2 + ivec2(x, y);
                float depth = texelFetch(gbufferTex, sample_pix * 2, 0).w;
                vec4 ssgi = texelFetch(ssgiTex, sample_pix, 0);
                vec3 normal = unpack_normal_11_10_11(texelFetch(gbufferTex, sample_pix * 2, 0).x);
                result += process_sample(ssgi, depth, normal, center_depth, center_normal, w_sum);
            }
        }
    } else {
        result = 0.0.xxxx;
    }

	imageStore(outputTex, pix, (result / max(w_sum, 1e-6)));
}
