#include "stochastic_transparency_common.glsl"

uniform restrict writeonly layout(binding = 0) uimage2D outputTex;


layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
	imageStore(outputTex, pix, uvec4(pack_color(0.0.xxx), floatBitsToUint(0.0), floatBitsToUint(0.0)));
}
