#include "../inc/uv.inc"

uniform texture2D inputTex;
uniform restrict writeonly image2D outputTex;

layout(std140) uniform globals {
    vec4 outputTex_size;
};

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    vec2 uv = get_uv(outputTex_size);

#define METHOD 1

#if METHOD == 0
	vec4 col = vec4(0);
    col += textureGather(inputTex, uv, 0);
    float col_sum = dot(col, vec4(1.0));
    float discontinuity = fract(col_sum / 4.0) > 0.0 ? 1.0 : 0.0;
#elif METHOD == 1
    float col_sum = 0.0;
    col_sum += texelFetch(inputTex, pix, 0).r;
    col_sum += texelFetch(inputTex, pix + ivec2(1, 0), 0).r;
    col_sum += texelFetch(inputTex, pix + ivec2(-1, 0), 0).r;
    float discontinuity = fract(col_sum / 3.0) > 0.0 ? 1.0 : 0.0;
#elif METHOD == 2
    uint quad_rotation_idx = (pix.x >> 1u) & 3u;
    ivec2 rendered_pixel_offset = ivec2(0, quad_rotation_idx & 1);

    float col_sum = 0.0;
    col_sum += texelFetch(inputTex, pix, 0).r;
    col_sum += texelFetch(inputTex, pix + ivec2(1, 0), 0).r;
    col_sum += texelFetch(inputTex, pix + ivec2(-1, 0), 0).r;
    col_sum += texelFetch(inputTex, pix - ivec2(0, rendered_pixel_offset.y * 2 - 1), 0).r;
    float discontinuity = fract(col_sum / 4.0) > 0.0 ? 1.0 : 0.0;
#elif METHOD == 3
    float col_sum = 0.0;
    col_sum += texelFetch(inputTex, pix, 0).r;
    col_sum += texelFetch(inputTex, pix + ivec2(1, 0), 0).r;
    col_sum += texelFetch(inputTex, pix + ivec2(-1, 0), 0).r;
    col_sum += texelFetch(inputTex, pix + ivec2(0, 1), 0).r;
    col_sum += texelFetch(inputTex, pix + ivec2(0,-1), 0).r;
    float discontinuity = fract(col_sum / 5.0) > 0.0 ? 1.0 : 0.0;
#endif

	imageStore(outputTex, pix, vec4(discontinuity));
}
