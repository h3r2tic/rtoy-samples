#include "../inc/uv.inc"

uniform layout(r32f) readonly image2D horizontalInputTex;
uniform layout(r32f) readonly image2D verticalInputTex;

uniform restrict writeonly image2D outputTex;

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);

    uint a = floatBitsToUint(imageLoad(horizontalInputTex, pix).x);
    uint b = floatBitsToUint(imageLoad(verticalInputTex, ivec2(0, pix.y)).x);
    uint sum = a + b;

	imageStore(outputTex, pix, vec4(uintBitsToFloat(uint(sum))));
}
