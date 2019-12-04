#include "../inc/uv.inc"

uniform texture2D inputTex;
uniform sampler linear_sampler;
uniform restrict writeonly image2D outputTex;

layout(std140) uniform globals {
    vec4 inputTex_size;
    vec4 outputTex_size;
};

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 out_pix = ivec2(gl_GlobalInvocationID.xy);
    ivec2 in_pix = out_pix * 8;

    vec2 uv = get_uv(in_pix, inputTex_size);

    vec2 input_texel_size = inputTex_size.zw;

    float sum = 0.0;

    for (int y = 0; y < 4; ++y) {
        for (int x = 0; x < 4; ++x) {
            sum += dot(textureGather(sampler2D(inputTex, linear_sampler), uv + input_texel_size * 2.0 * vec2(x, y), 0), vec4(1.0));
        }
    }

	imageStore(outputTex, out_pix, vec4(uintBitsToFloat(uint(sum))));
}
