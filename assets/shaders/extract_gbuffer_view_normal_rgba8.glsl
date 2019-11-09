#include "rendertoy::shaders/view_constants.inc"
#include "inc/pack_unpack.inc"

uniform sampler2D inputTex;
uniform restrict writeonly image2D outputTex;

layout(std430) buffer constants {
    ViewConstants view_constants;
};

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    vec3 normal = unpack_normal_11_10_11(texelFetch(inputTex, pix, 0).x);
    vec3 normal_vs = normalize((view_constants.world_to_view * vec4(normal, 0)).xyz);
	imageStore(outputTex, pix, vec4(normal_vs, 1));
}
