#include "rendertoy::shaders/view_constants.inc"
#include "inc/uv.inc"

uniform texture2D inputTex;
uniform restrict writeonly image2D outputTex;

layout(std430) buffer constants {
    ViewConstants view_constants;
    mat4 prev_world_to_clip;
};

layout(std140) uniform globals {
    vec4 outputTex_size;
};

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
    ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    vec2 uv = get_uv(outputTex_size);

    vec3 eye_pos = (view_constants.view_to_world * vec4(0, 0, 0, 1)).xyz;

    float depth = 0.0;
    const int k = 1;
    for (int y = -k; y <= k; ++y) {
        for (int x = -k; x <= k; ++x) {
            vec4 gbuffer = texelFetch(inputTex, pix + ivec2(x, y), 0);
            if (gbuffer.a != 0.0) {
                depth = max(depth, gbuffer.w);
            }
        }
    }

    vec4 pos_cs = vec4(uv_to_cs(uv), depth, 1.0);
    vec4 pos_vs = view_constants.clip_to_view * pos_cs;
    vec4 pos_ws = view_constants.view_to_world * pos_vs;

    vec4 prev_clip = prev_world_to_clip * pos_ws;
    prev_clip /= prev_clip.w;

    vec2 uv_diff = cs_to_uv(prev_clip.xy) - uv;

    imageStore(
        outputTex,
        pix,
        vec4(
            uv_diff,
            prev_clip.xy == clamp(
                prev_clip.xy,
                -1.0 + outputTex_size.zw,
                1.0 - outputTex_size.zw
            ),
            1.0
        ));
}
