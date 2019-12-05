#include "../inc/uv.inc"

uniform restrict writeonly image2D outputTex;

uniform texture2D inputTex;
uniform texture2D historyTex;
uniform texture2D reprojectionTex;

layout(std140) uniform globals {
    vec4 outputTex_size;
};

uniform sampler linear_sampler;

vec4 run_filter(in vec2 fragCoord)
{
    ivec2 px = ivec2(fragCoord);
    vec2 uv = get_uv(outputTex_size);
    
    vec4 center = texelFetch(inputTex, px, 0);
    vec4 reproj = texelFetch(reprojectionTex, px, 0);
    vec4 history = textureLod(sampler2D(historyTex, linear_sampler), uv + reproj.xy, 0);
    
	vec4 vsum = 0.0.xxxx;
	vec4 vsum2 = 0.0.xxxx;
	float wsum = 0.0;

    vec4 nmin = center;
    vec4 nmax = center;
    
	const int k = 1;
    for (int y = -k; y <= k; ++y) {
        for (int x = -k; x <= k; ++x) {
            vec4 neigh = texelFetch(inputTex, px + ivec2(x, y) * 2, 0);
			float w = exp(-3.0 * float(x * x + y * y) / float((k+1.) * (k+1.)));
			vsum += neigh * w;
			vsum2 += neigh * neigh * w;
			wsum += w;
        }
    }

	vec4 ex = vsum / wsum;
	vec4 ex2 = vsum2 / wsum;
	vec4 dev = sqrt(max(0.0.xxxx, ex2 - ex * ex));

    float box_size = mix(0.5, 5.0, smoothstep(0.05, 0.0, length(reproj.xy)));

	nmin = ex - dev * box_size;
	nmax = ex + dev * box_size;
    
	vec4 clamped_history = clamp(history, nmin, nmax);
	return mix(clamped_history, center, mix(1.0, 1.0 / 16.0, reproj.z));
}

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	vec2 fragCoord = vec2(gl_GlobalInvocationID.xy) + 0.5;
	vec4 result = run_filter(fragCoord);

	imageStore(outputTex, ivec2(gl_GlobalInvocationID.xy), result);
}