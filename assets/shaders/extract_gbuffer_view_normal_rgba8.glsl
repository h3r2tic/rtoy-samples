#include "rendertoy::shaders/view_constants.inc"
#include "inc/pack_unpack.inc"

uniform sampler2D inputTex;
uniform vec4 inputTex_size;

uniform restrict writeonly image2D outputTex;
uniform vec4 outputTex_size;

layout(std430) buffer constants {
    ViewConstants view_constants;
};

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    ivec2 src_pix = pix * ivec2((inputTex_size.xy + 1.0) / outputTex_size.xy);
    vec3 normal = unpack_normal_11_10_11(texelFetch(inputTex, src_pix, 0).x);
    vec3 normal_vs = normalize((view_constants.world_to_view * vec4(normal, 0)).xyz);
	imageStore(outputTex, pix, vec4(normal_vs, 1));
}
