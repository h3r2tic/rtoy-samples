#include "inc/uv.inc"

uniform restrict writeonly image2D outputTex;

layout(std430) buffer buf0 {
    vec4 bg_col;
};

layout(std430) buffer buf1 {
    vec2 circle_center;
};

layout(std140) uniform globals {
    uniform vec4 outputTex_size;
};

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    vec2 uv = get_uv(outputTex_size);
	vec4 col = bg_col + smoothstep(0.25, 0.245, length(circle_center - uv));
	imageStore(outputTex, pix, col);
}
