#include "inc/uv.inc"

uniform restrict writeonly image2D outputTex;
uniform vec4 outputTex_size;

uniform sampler2D inputTex;
uniform sampler2D historyTex;
uniform sampler2D reprojectionTex;

float run_filter(in vec2 fragCoord)
{
    ivec2 px = ivec2(fragCoord);
    vec2 uv = get_uv(outputTex_size);
    
    float center = texelFetch(inputTex, px, 0).x;
    vec4 reproj = texelFetch(reprojectionTex, px, 0);
    float history = max(0.0, textureLod(historyTex, uv + reproj.xy, 0).x);
    
	float vsum = 0.0;
	float vsum2 = 0.0;
	float wsum = 0.0;

    float nmin = center;
    float nmax = center;
    
	const int k = 1;
    for (int y = -k; y <= k; ++y) {
        for (int x = -k; x <= k; ++x) {
            float neigh = texelFetch(inputTex, px + ivec2(x, y), 0).x;
			float w = exp(-3.0 * float(x * x + y * y) / float((k+1.) * (k+1.)));
			vsum += neigh * w;
			vsum2 += neigh * neigh * w;
			wsum += w;
        }
    }

	float ex = vsum / wsum;
	float ex2 = vsum2 / wsum;
	float dev = sqrt(max(0.0, ex2 - ex * ex));

    float box_size = mix(0.5, 5.0, smoothstep(0.05, 0.0, length(reproj.xy)));

	nmin = ex - dev * box_size;
	nmax = ex + dev * box_size;
    
	float clamped_history = clamp(history, nmin, nmax);
	return mix(clamped_history, center, mix(1.0, 1.0 / 16.0, reproj.z));
}

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	vec2 fragCoord = vec2(gl_GlobalInvocationID.xy) + 0.5;
	float result = run_filter(fragCoord);

	imageStore(outputTex, ivec2(gl_GlobalInvocationID.xy), result.xxxx);
}