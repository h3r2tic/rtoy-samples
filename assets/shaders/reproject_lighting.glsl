#include "inc/uv.inc"

uniform sampler2D lightingTex;
uniform sampler2D reprojectionTex;

uniform restrict writeonly image2D outputTex;
uniform vec4 outputTex_size;

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    vec2 uv = get_uv(outputTex_size);

    vec4 reproj = texelFetch(reprojectionTex, ivec2(outputTex_size.xy * uv), 0);
    vec4 color = 0.0.xxxx;

    if (reproj.z > 0.5) {
        color = texelFetch(lightingTex, ivec2(outputTex_size.xy * (uv + reproj.xy)), 0);
    }

	imageStore(outputTex, pix, color);
}
