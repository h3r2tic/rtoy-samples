#include "../inc/uv.inc"

uniform texture2D horizontalInputTex;
uniform texture2D verticalInputTex;

uniform restrict writeonly image2D outputTex;

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);

    uint a = floatBitsToUint(texelFetch(horizontalInputTex, pix, 0).x);
    uint b = floatBitsToUint(texelFetch(verticalInputTex, ivec2(0, pix.y), 0).x);
    uint sum = a + b;

	imageStore(outputTex, pix, vec4(uintBitsToFloat(uint(sum))));
}
