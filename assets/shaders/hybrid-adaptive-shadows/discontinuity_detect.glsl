#include "../inc/uv.inc"

uniform sampler2D inputTex;

uniform restrict writeonly image2D outputTex;
uniform vec4 outputTex_size;

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    vec2 uv = get_uv(outputTex_size);

	vec4 col = vec4(0);
    col += textureGather(inputTex, uv, 0);

    float col_sum = dot(col, vec4(1.0));
    float discontinuity = fract(col_sum / 4.0) > 0.0 ? 1.0 : 0.0;

	imageStore(outputTex, pix, vec4(discontinuity));
}
