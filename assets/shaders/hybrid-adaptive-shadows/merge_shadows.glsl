#include "rendertoy::shaders/view_constants.inc"
#include "rtoy-rt::shaders/rt.inc"
#include "../inc/uv.inc"
#include "../inc/pack_unpack.inc"

uniform texture2D gbuffer;

uniform texture2D halfresShadowsTex;
uniform texture2D discontinuityTex;
uniform texture2D sparseShadowsTex;

uniform restrict writeonly image2D outputTex;

layout(std140) uniform globals {
    vec4 outputTex_size;
    vec4 gbuffer_size;
};

#if 1
layout (local_size_x = 8, local_size_y = 8) in;
void main() {
    ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    float discontinuity = texelFetch(discontinuityTex, pix / 2, 0).r;
    float result = texelFetch(halfresShadowsTex, pix / 2, 0).r;

    ivec2 quad = pix / 2;
    uint quad_rotation_idx = (quad.x >> 1u) & 3u;
    ivec2 offset = ivec2(0, quad_rotation_idx & 1);

    if (discontinuity > 0.0 && (pix & 1) != offset) {
        result = texelFetch(sparseShadowsTex, pix, 0).r;
    }

    #if 0
        vec2 uv = get_uv(outputTex_size);
        vec4 gbuffer = texelFetch(gbuffer, pix, 0);

        if (gbuffer.a == 0.0) {
            result = 0.0;
        } else {
            vec3 normal = unpack_normal_11_10_11_no_normalize(gbuffer.x);
            result *= dot(normal, light_dir_pad.xyz) > 0.0 ? 1.0 : 0.0;
        }
    #endif

    imageStore(outputTex, pix, result.xxxx);
}
#else
layout(std430) buffer constants {
    ViewConstants view_constants;
    vec4 light_dir_pad;
};

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
    ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    vec2 uv = get_uv(pix, gbuffer_size);
    vec4 gbuffer = texelFetch(gbuffer, pix, 0);
    vec3 normal = unpack_normal_11_10_11(gbuffer.x);

    vec3 l = normalize(light_dir_pad.xyz);

    float ndotl = max(0.0, dot(normal, l));
    float result = 1.0;

    if (gbuffer.a != 0.0) {
        if (ndotl > 0.0) {
            vec4 ray_origin_cs = vec4(uv_to_cs(uv), gbuffer.w, 1.0);
            vec4 ray_origin_vs = view_constants.clip_to_view * ray_origin_cs;
            vec4 ray_origin_ws = view_constants.view_to_world * ray_origin_vs;
            ray_origin_ws /= ray_origin_ws.w;

            vec4 ray_dir_cs = vec4(uv_to_cs(uv), 0.0, 1.0);
            vec4 ray_dir_ws = view_constants.view_to_world * (view_constants.clip_to_view * ray_dir_cs);
            vec3 v = -normalize(ray_dir_ws.xyz);

            Ray r;
            r.d = l;
            r.o = ray_origin_ws.xyz;
            r.o += (v + r.d) * (1e-4 * max(length(r.o), abs(ray_origin_vs.z / ray_origin_vs.w)));

            if (raytrace_intersects_any(r)) {
                result = 0.0;
            }
        }
    }

    vec4 color_result = vec4(result);

    #if 0
        color_result *= 0.5;
    #else
        if (gbuffer.a == 0.0) {
            color_result = vec4(0.05.xxx, 1.0);
        } else {
            color_result.rgb *= ndotl;
            color_result.rgb *= normal * 0.5 + 0.5;
        }
    #endif

    imageStore(outputTex, pix, color_result);
}
#endif