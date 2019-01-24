uniform sampler2D g_roughnessMultTex;

uniform restrict writeonly image2D outputTex;
uniform vec4 outputTex_size;

uniform float g_mouseX;
#define iMouse vec4(g_mouseX, 0, 0, 0)

#define iResolution outputTex_size

#include "math.inc"
#include "world.inc"

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	vec2 fragCoord = vec2(gl_GlobalInvocationID.xy) + 0.5;

    RaySampleInfo currSample = setup_cameraRay(fragCoord, 0.0.xx);

    SurfaceInfo surface = dist_march(0.0, currSample.origin,  currSample.direction);
	surface.roughnessMult *= 0.75;
	surface.roughnessMult *= pow(texture(g_roughnessMultTex, vec2(fragCoord) * outputTex_size.zw).x, 1.5);

	imageStore(outputTex, ivec2(gl_GlobalInvocationID.xy), packSurfaceInfo(surface));
}
