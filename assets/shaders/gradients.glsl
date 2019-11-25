#include "rendertoy::shaders/color.inc"
#include "inc/uv.inc"

uniform restrict writeonly layout(binding = 0) image2D outputTex;

layout(std140, binding = 1) uniform globals {
    vec4 outputTex_size;
    float time;
};

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
	vec2 uv = fract(get_uv(outputTex_size) + vec2(0.0, time));
    //vec2 uv = vec2(pix) / 256.0;
	float hue = fract(int(uv.y * 6) / 6.0 + 0.09);
	vec4 col = vec4(hsv_to_rgb(vec3(hue, 1.0, 1)) * uv.x, 1);
	imageStore(outputTex, pix, col);
}
