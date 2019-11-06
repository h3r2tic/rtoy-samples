#define PI 3.14159265359

#include "rendertoy::shaders/random.inc"
#include "rendertoy::shaders/sampling.inc"
#include "inc/uv.inc"
#include "inc/atmosphere.inc"
#include "inc/pack_unpack.inc"

uniform sampler2D input_tex;
uniform vec4 input_tex_size;

uniform restrict writeonly image2D outputTex;
uniform vec4 outputTex_size;

vec4 sample_input(vec3 dir) {
    return texelFetch(input_tex, ivec2(input_tex_size.xy * octa_encode(dir)), 0);
}

float radical_inverse(int n, int base) {
    float val = 0;
    float invBase = 1.0 / base, invBi = invBase;
    while (n > 0) {
        // Compute next digit of radical inverse
        int d_i = (n % base);
        val += d_i * invBi;
        n = int(float(n) * invBase);
        invBi *= invBase;
    }
    return val;
}

vec2 halton(int i) {
    return vec2(radical_inverse(i + 1, 2), radical_inverse(i + 1, 3));
}

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    vec2 uv = get_uv(outputTex_size);

    vec3 normal = octa_decode(uv);
    vec4 col = 0.0.xxxx;

    int sample_cnt = 256;
    for (int i = 0; i < sample_cnt; ++i)
    {
        vec3 sr = uniform_sample_sphere(halton(i));
        vec3 dir = normal + sr;
        col += sample_input(dir);
    }
    col /= float(sample_cnt);

	imageStore(outputTex, pix, col);
}
