#include "../inc/pack_unpack.inc"
#include "../inc/uv.inc"

uniform sampler2D ssgiTex;
uniform sampler2D depthTex;
uniform sampler2D normalTex;

uniform restrict writeonly image2D outputTex;
uniform vec4 outputTex_size;

vec4 process_sample(vec4 ssgi, float depth, float normal_packed, float center_depth, vec3 center_normal, inout float w_sum) {
    if (depth != 0.0)
    {
        vec3 normal = unpack_normal_11_10_11_no_normalize(normal_packed);

        //float depth_diff = (1.0 / center_depth) - (1.0 / depth);
        //float depth_factor = exp2(-(200.0 * center_depth) * abs(depth_diff));
        float depth_diff = 1.0 - (center_depth / depth);
        float depth_factor = exp2(-200.0 * abs(depth_diff));

        float normal_factor = max(0.0, dot(normal, center_normal));
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

/*vec2 process_four_samples(vec2 uv, float center_depth, vec3 center_normal) {
    vec4 ao = textureGather(ssgiTex, uv, 0);
    vec4 depth = textureGather(depthTex, uv, 0);
    vec4 normal = textureGather(normalTex, uv, 0);

    return 
        process_sample(ao.x, depth.x, normal.x, center_depth, center_normal) +
        process_sample(ao.y, depth.y, normal.y, center_depth, center_normal) +
        process_sample(ao.z, depth.z, normal.z, center_depth, center_normal) +
        process_sample(ao.w, depth.w, normal.w, center_depth, center_normal);
}*/

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    vec4 result = 0.0.xxxx;
    float w_sum = 0.0;

    float center_depth = texelFetch(depthTex, pix, 0).x;
    if (center_depth != 0.0) {
        vec3 center_normal = unpack_normal_11_10_11(texelFetch(normalTex, pix, 0).x);

#if 1
    	vec4 center_ssgi = texelFetch(ssgiTex, pix, 0);
        w_sum = 1.0;
        result = center_ssgi;

        const int kernel_half_size = 2;
        for (int y = -kernel_half_size; y <= kernel_half_size; ++y) {
            for (int x = -kernel_half_size; x <= kernel_half_size; ++x) {
                if (x != 0 || y != 0) {
                    ivec2 sample_pix = pix + ivec2(x, y);
                    float depth = texelFetch(depthTex, sample_pix, 0).x;
                    vec4 ssgi = texelFetch(ssgiTex, sample_pix, 0);
                    float normal_packed = texelFetch(normalTex, sample_pix, 0).x;
                    result += process_sample(ssgi, depth, normal_packed, center_depth, center_normal, w_sum);
                }
            }
        }
#else
        vec2 uv = get_uv(outputTex_size);
        result += process_four_samples(uv + outputTex_size.zw * vec2(-1, -1), center_depth, center_normal);
        result += process_four_samples(uv + outputTex_size.zw * vec2(-1, +1), center_depth, center_normal);
        result += process_four_samples(uv + outputTex_size.zw * vec2(+1, -1), center_depth, center_normal);
        result += process_four_samples(uv + outputTex_size.zw * vec2(+1, +1), center_depth, center_normal);
#endif
    } else {
        result = 0.0.xxxx;
    }

	imageStore(outputTex, pix, (result / max(w_sum, 1e-5)));
}
