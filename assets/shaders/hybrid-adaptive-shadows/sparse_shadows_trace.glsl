#include "rtoy-rt::shaders/rt.inc"
#include "../inc/uv.inc"
#include "../inc/pack_unpack.inc"

uniform sampler2D gbufferTex;
uniform vec4 gbufferTex_size;

uniform layout(rg32f) readonly image2D rtPixelLocationTex;
uniform layout(r32f) readonly image2D tileAllocOffsetTex;
uniform vec4 tileAllocOffsetTex_size;
uniform vec4 rtPixelLocationTex_size;

uniform restrict writeonly image2D outputTex;
uniform vec4 outputTex_size;

layout(std430) buffer constants {
    mat4 view_to_clip;
    mat4 clip_to_view;
    mat4 world_to_view;
    mat4 view_to_world;
    vec4 light_dir_pad;
};

void do_shadow_rt(ivec2 pix) {
    vec2 uv = get_uv(pix, gbufferTex_size);
    vec4 gbuffer = texelFetch(gbufferTex, pix, 0);
    vec3 normal = unpack_normal_11_10_11(gbuffer.x);

    vec3 l = normalize(light_dir_pad.xyz);

    float ndotl = max(0.0, dot(normal, l));
    float result = 1.0;

    if (gbuffer.a != 0.0 && ndotl > 0.0) {
        vec4 ray_origin_cs = vec4(uv_to_cs(uv), gbuffer.w, 1.0);
        vec4 ray_origin_vs = clip_to_view * ray_origin_cs;
        vec4 ray_origin_ws = view_to_world * ray_origin_vs;
        ray_origin_ws /= ray_origin_ws.w;

        vec4 ray_dir_cs = vec4(uv_to_cs(uv), 0.0, 1.0);
        vec4 ray_dir_ws = view_to_world * (clip_to_view * ray_dir_cs);
        vec3 v = -normalize(ray_dir_ws.xyz);

        Ray r;
        r.d = l;
        r.o = ray_origin_ws.xyz;
        r.o += (v + r.d) * (1e-4 * max(length(r.o), abs(ray_origin_vs.z / ray_origin_vs.w)));

        if (raytrace_intersects_any(r)) {
            result = 0.0;
        }
    }

    vec4 color_result = vec4(result);

    imageStore(outputTex, pix, color_result);
}

shared uint total_rt_px_count;

// Due to the allocation method, sparse shadows are mostly
// coherent in 1D lines rather than 2D tiles.
layout (local_size_x = 64, local_size_y = 1) in;
void main() {
    if (gl_LocalInvocationIndex == 0) {
        ivec2 total_rt_px_count_loc = ivec2(tileAllocOffsetTex_size.xy) - 1;
        total_rt_px_count = floatBitsToUint(imageLoad(tileAllocOffsetTex, total_rt_px_count_loc).x);
    }

    barrier();

    uint global_invocation_index = uint(gl_GlobalInvocationID.x) + uint(gl_GlobalInvocationID.y) * uint(outputTex_size.x);
    uint pixel_idx = global_invocation_index / 3;

    // Rendertoy doesn't have indirect dispatch. Just branch out for now.
    if (pixel_idx < total_rt_px_count) {
        ivec2 alloc_pix = ivec2(pixel_idx % uint(rtPixelLocationTex_size.x), pixel_idx / uint(rtPixelLocationTex_size.x));
        ivec2 quad = floatBitsToInt(imageLoad(rtPixelLocationTex, alloc_pix).xy);
        ivec2 pix = 2 * quad;

        uint quad_rotation_idx = (quad.x >> 1u) & 3u;
        ivec2 rendered_pixel_offset = ivec2(0, quad_rotation_idx & 1);

        uint subpix_idx = (global_invocation_index - pixel_idx * 3) + 1;
        ivec2 subpix = ivec2(subpix_idx & 1u, subpix_idx >> 1u);
        ivec2 offset = rendered_pixel_offset ^ subpix;

        do_shadow_rt(pix + offset);
    }
}
