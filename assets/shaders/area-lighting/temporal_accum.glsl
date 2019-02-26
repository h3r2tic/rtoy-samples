uniform restrict writeonly image2D outputTex;
uniform vec4 outputTex_size;

uniform sampler2D g_filteredLightingTex;
uniform sampler2D g_prevOutputTex;

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    ivec2 px = ivec2(fragCoord);
    
    vec3 center = texelFetch(g_filteredLightingTex, px, 0).rgb;
    //vec4 history = 0.0.xxxx;
	vec4 history = 1.*texelFetch(g_prevOutputTex, px, 0);
    
	vec3 vsum = vec3(0.);
	vec3 vsum2 = vec3(0.);
	float wsum = 0;

    vec3 nmin = center;
    vec3 nmax = center;
    
	const int k = 2;
    for (int y = -k; y <= k; ++y) {
        for (int x = -k; x <= k; ++x) {
            vec3 neigh = texelFetch(g_filteredLightingTex, px + ivec2(x, y), 0).rgb;
            //nmin = min(nmin, neigh);
            //nmax = max(nmax, neigh);
			float w = exp(-3.0 * float(x * x + y * y) / float((k+1.) * (k+1.)));
			vsum += neigh * w;
			vsum2 += neigh * neigh * w;
			wsum += w;
        }
    }

	vec3 ex = vsum / wsum;
	vec3 ex2 = vsum2 / wsum;
	vec3 dev = sqrt(max(vec3(0.0), ex2 - ex * ex));

	nmin = ex - dev * 1.5;
	nmax = ex + dev * 1.5;
    
	#if 1
		vec3 result;
		if (true) {
			vec3 clamped_history = clamp(history.rgb, nmin, nmax);
			//clamped_history = mix(clamped_history, history.rgb, 0.6);
			result = mix(clamped_history, center, 1.0 / 16.0);
		} else if (true) {
			result = mix(history.rgb, center, 1.0 / 16.0);
		} else {
			result = center;
		}
		
		fragColor = vec4(result, 1.0);
	#else
		fragColor = history;
		//if (fragColor.a < 15.5)
		{
			fragColor += vec4(center, 1.0);
		}
	#endif
}

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	vec2 fragCoord = vec2(gl_GlobalInvocationID.xy) + 0.5;
	vec4 finalColor;

	mainImage(finalColor, fragCoord);

	imageStore(outputTex, ivec2(gl_GlobalInvocationID.xy), finalColor);
}