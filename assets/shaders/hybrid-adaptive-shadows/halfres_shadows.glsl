#include "rendertoy::shaders/view_constants.inc"
#include "rendertoy::shaders/random.inc"
#include "rendertoy::shaders/sampling.inc"
#include "rtoy-rt::shaders/rt.inc"
#include "../inc/uv.inc"
#include "../inc/pack_unpack.inc"

uniform texture2D gbufferTex;
uniform restrict writeonly image2D outputTex;

layout(std140) uniform globals {
    vec4 outputTex_size;
    vec4 gbufferTex_size;
};

layout(std430) buffer constants {
    ViewConstants view_constants;
    vec4 light_dir_pad;
};

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
    ivec2 pix = ivec2(gl_GlobalInvocationID.xy) * 2;
    uint quad_rotation_idx = (gl_GlobalInvocationID.x >> 1u) & 3u;
    pix += ivec2(0, quad_rotation_idx & 1);

    vec2 uv = get_uv(vec2(pix), gbufferTex_size);
    vec4 gbuffer = texelFetch(gbufferTex, pix, 0);
    vec3 normal = unpack_normal_11_10_11(gbuffer.x);

    vec3 l = normalize(light_dir_pad.xyz);

    float ndotl = max(0.0, dot(normal, l));
    float result = 1.0;

    if (gbuffer.a != 0.0 && ndotl > 0.0) {
        vec4 ray_origin_cs = vec4(uv_to_cs(uv), gbuffer.w, 1.0);
        vec4 ray_origin_vs = view_constants.sample_to_view * ray_origin_cs;
        vec4 ray_origin_ws = view_constants.view_to_world * ray_origin_vs;
        ray_origin_ws /= ray_origin_ws.w;

        vec4 ray_dir_cs = vec4(uv_to_cs(uv), 0.0, 1.0);
        vec4 ray_dir_ws = view_constants.view_to_world * (view_constants.sample_to_view * ray_dir_cs);
        vec3 v = -normalize(ray_dir_ws.xyz);

        const float ray_bias = 1e-4;

        Ray r;
        r.d = l;
        r.o = ray_origin_ws.xyz;
        r.o += (v + normal) * (ray_bias * max(length(r.o), abs(ray_origin_vs.z / ray_origin_vs.w)));

        if (raytrace_intersects_any(r)) {
            result = 0.0;
        }
    } else {
        result = 0.0;
    }

    imageStore(outputTex, pix / 2, vec4(result));
}
