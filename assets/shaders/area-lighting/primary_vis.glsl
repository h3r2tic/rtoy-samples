uniform layout(binding = 0) texture2D g_roughnessMultTex;
layout(std140, binding = 1) uniform globals {
    vec4 outputTex_size;
    vec4 g_roughnessMultTex_size;
    float g_mouseX;
};

#define iMouse vec4(g_mouseX, 0, 0, 0)
#define iResolution outputTex_size

#include "math.inc"
#include "world.inc"

uniform restrict writeonly layout(binding = 2) image2D outputTex;

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	vec2 fragCoord = vec2(gl_GlobalInvocationID.xy) + 0.5;

    RaySampleInfo currSample = setup_cameraRay(fragCoord, 0.0.xx);

    SurfaceInfo surface = dist_march(0.0, currSample.origin,  currSample.direction);
	surface.roughnessMult *= 0.75;

    ivec2 rpix = ivec2(gl_GlobalInvocationID.xy) / ivec2(2, 1);
    //rpix %= ivec2(g_roughnessMultTex_size.xy);
	surface.roughnessMult *= pow(texelFetch(g_roughnessMultTex, rpix, 0).x, 1.5);

	imageStore(outputTex, ivec2(gl_GlobalInvocationID.xy), packSurfaceInfo(surface));
}
