// TODO
#define PI 3.14159265359

#include "rendertoy::shaders/view_constants.inc"

#include "../inc/uv.inc"
#include "../inc/atmosphere.inc"

uniform restrict writeonly image2D outputTex;
uniform vec4 outputTex_size;

layout(std430) buffer constants {
    ViewConstants view_constants;
    vec4 light_dir_pad;
    uint frame_idx;
};

vec3 get_sky_color(vec3 rd) {
    vec3 scatter = atmosphere2(
        rd,                 // normalized ray direction
        vec3(0,6371e3,0),               // ray origin
        // sun pos
        light_dir_pad.xyz,
        6371e3,                         // radius of the planet in meters
        6471e3,                         // radius of the atmosphere in meters
        vec3(5.8e-6, 13.5e-6, 33.1e-6), // frostbite
        21e-6,                          // Mie scattering coefficient
        vec3(3.426e-7, 8.298e-7, 0.356e-7), // Ozone extinction, frostbite
        8e3,                            // Rayleigh scale height
        1.2e3,                          // Mie scale height
        0.758                           // Mie preferred scattering direction
    );
    return scatter * 20.0;
}

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
    ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    vec2 uv = get_uv(outputTex_size);
    vec4 ray_dir_cs = vec4(uv_to_cs(uv), 0.0, 1.0);
    vec4 ray_dir_ws = view_constants.view_to_world * (view_constants.sample_to_view * ray_dir_cs);
    vec3 v = -normalize(ray_dir_ws.xyz);

    vec3 result = get_sky_color(-v);

    imageStore(outputTex, pix, vec4(result, 1));
}
