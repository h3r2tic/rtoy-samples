#include "rtoy-rt::shaders/rt.inc"
#include "inc/uv.inc"
#include "inc/pack_unpack.inc"

uniform sampler2D inputTex;

uniform restrict writeonly image2D outputTex;
uniform vec4 outputTex_size;

layout(std430) buffer constants {
    mat4 view_to_clip;
    mat4 clip_to_view;
    mat4 world_to_view;
    mat4 view_to_world;
    vec4 light_dir_pad;
};

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
    ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    vec2 uv = get_uv(outputTex_size);
    vec4 gbuffer = texelFetch(inputTex, pix, 0);
    vec3 normal = unpack_normal_11_10_11(gbuffer.x);

    vec3 l = normalize(light_dir_pad.xyz);

    vec4 col = vec4(normal * 0.5 + 0.5, 1);
    float ndotl = max(0.0, dot(normal, l));
    col.rgb *= ndotl;

    if (gbuffer.a != 0.0) {
        if (ndotl > 0.0) {
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
                col.rgb *= 0.1;
            }
        }

        // Simple ambient
        col.rgb += 0.05;
    } else {
        col.rgb = 0.1.xxx;
    }

    imageStore(outputTex, pix, col);
}
