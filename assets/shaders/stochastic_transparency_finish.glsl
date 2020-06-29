#include "stochastic_transparency_common.glsl"

uniform utexture2D inputTex;
uniform utexture2D inputTex2;
uniform restrict writeonly image2D outputTex;

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    uvec4 c0 = texelFetch(inputTex, pix, 0);
    uvec4 c1 = texelFetch(inputTex2, pix, 0);

    vec4 color0 = vec4(unpack_color(c0.xy), 1.0) * uintBitsToFloat(c0.w);
    vec4 color1 = vec4(unpack_color(c1.xy), 1.0) * uintBitsToFloat(c1.w);

    vec4 color;
    if (uintBitsToFloat(c1.z) > uintBitsToFloat(c0.z)) {
        color = color1 + (1 - color1.w) * color0;
    } else {
        color = color0 + (1 - color0.w) * color1;
    }

    vec4 background = 0.9.xxxx;
    color = color + background * (1 - color.w);
    //color = color0 + background * (1 - color0.w);
    //color = color1 + background * (1 - color1.w);

	imageStore(outputTex, pix, color);
}
