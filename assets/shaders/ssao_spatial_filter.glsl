#include "inc/pack_unpack.inc"
#include "inc/uv.inc"

uniform texture2D aoTex;
uniform texture2D depthTex;
uniform texture2D normalTex;

uniform restrict writeonly image2D outputTex;

layout(std140) uniform globals {
    vec4 outputTex_size;
};

uniform sampler linear_sampler;

vec2 process_sample(float ao, float depth, float normal_packed, float center_depth, vec3 center_normal) {
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

        return vec2(ao, 1) * w;
    } else {
        return vec2(0, 0);
    }
}

vec2 process_four_samples(vec2 uv, float center_depth, vec3 center_normal) {
    vec4 ao = textureGather(sampler2D(aoTex, linear_sampler), uv, 0);
    vec4 depth = textureGather(sampler2D(depthTex, linear_sampler), uv, 0);
    vec4 normal = textureGather(sampler2D(normalTex, linear_sampler), uv, 0);

    return 
        process_sample(ao.x, depth.x, normal.x, center_depth, center_normal) +
        process_sample(ao.y, depth.y, normal.y, center_depth, center_normal) +
        process_sample(ao.z, depth.z, normal.z, center_depth, center_normal) +
        process_sample(ao.w, depth.w, normal.w, center_depth, center_normal);
}

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    vec2 result = vec2(0.0, 0.0);

    float center_depth = texelFetch(depthTex, pix, 0).x;
    if (center_depth != 0.0) {
        vec3 center_normal = unpack_normal_11_10_11(texelFetch(normalTex, pix, 0).x);

#if 0
    	float center_ao = texelFetch(aoTex, pix, 0).x;
        result = vec2(center_ao, 1.0);

        const int kernel_half_size = 2;
        for (int y = -kernel_half_size; y <= kernel_half_size; ++y) {
            for (int x = -kernel_half_size; x <= kernel_half_size; ++x) {
                if (x != 0 || y != 0) {
                    ivec2 sample_pix = pix + ivec2(x, y);
                    float depth = texelFetch(depthTex, sample_pix, 0).x;
                    float ao = texelFetch(aoTex, sample_pix, 0).x;
                    float normal_packed = texelFetch(normalTex, sample_pix, 0).x;
                    result += process_sample(ao, depth, normal_packed, center_depth, center_normal);
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
        result = vec2(0.1, 1);
    }

	imageStore(outputTex, pix, (result.x / max(result.y, 1e-5)).xxxx);
}
