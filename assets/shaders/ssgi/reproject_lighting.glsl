#include "../inc/uv.inc"

uniform texture2D lightingTex;
uniform texture2D reprojectionTex;
uniform sampler linear_sampler;

uniform restrict writeonly image2D outputTex;

layout(std140) uniform globals {
    vec4 outputTex_size;
};

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    vec2 uv = get_uv(outputTex_size);

    vec4 reproj = texelFetch(reprojectionTex, pix * 2, 0);
    vec4 color = 0.0.xxxx;

    if (reproj.z > 0.5) {
        color = textureLod(sampler2D(lightingTex, linear_sampler), uv + reproj.xy, 0.0);
    }

	imageStore(outputTex, pix, color);
}
