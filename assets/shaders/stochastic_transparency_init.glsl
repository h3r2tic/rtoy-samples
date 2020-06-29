#include "stochastic_transparency_common.glsl"

uniform restrict writeonly layout(binding = 0) uimage2D outputTex;


layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    /*uvec4 val = uvec4(
        pack_oit(0.0.xxx, 0.0, 0.0),
        pack_oit(0.0.xxx, 0.0, 0.0)
    );*/
    uvec4 val = uvec4(0, 0, 0, 0);
	imageStore(outputTex, pix, val);
}
