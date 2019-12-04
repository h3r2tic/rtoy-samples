#include "inc/pack_unpack.inc"

uniform texture2D inputTex;
uniform restrict writeonly uimage2D outputTex;

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    imageStore(outputTex, pix, floatBitsToUint(texelFetch(inputTex, pix, 0).x).xxxx);
}
