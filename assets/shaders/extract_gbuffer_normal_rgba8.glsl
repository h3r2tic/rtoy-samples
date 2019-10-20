#include "inc/pack_unpack.inc"

uniform sampler2D inputTex;
uniform restrict writeonly image2D outputTex;

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    vec3 center_normal = unpack_normal_11_10_11(texelFetch(inputTex, pix, 0).x);
	imageStore(outputTex, pix, vec4(center_normal * 0.5 + 0.5, 1));
}
