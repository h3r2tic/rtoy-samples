#define PI 3.14159265359

#include "inc/uv.inc"
#include "inc/atmosphere.inc"
#include "inc/pack_unpack.inc"

uniform restrict writeonly image2D outputTex;
uniform vec4 outputTex_size;

layout(std430) buffer constants {
    vec3 light_dir;
};

vec3 getSkyColor(vec3 rd) {
    vec3 scatter = atmosphere2(
        rd,                 // normalized ray direction
        vec3(0,6371e3,0),               // ray origin
        // sun pos
        light_dir,
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

    //vec3 v = octahedral_unmapping(uv);
    vec3 v = octa_decode(uv);
    vec4 col = 0.0.xxxx;
    col.rgb = getSkyColor(v);

	imageStore(outputTex, pix, col);
}
