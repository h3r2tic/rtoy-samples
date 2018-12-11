#include "nested_inc/dummy.inc"
#include "/shaders/dummy.inc"

vec2 getUv(vec4 texSize) {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
	return (vec2(pix) + 0.5) * texSize.zw;
}
