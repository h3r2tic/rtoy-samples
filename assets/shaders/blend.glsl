#include "inc/color.inc"

uniform restrict writeonly layout(binding = 0) image2D outputTex;
uniform layout(binding = 1) texture2D inputTex1;
uniform layout(binding = 2) texture2D inputTex2;

/*layout(std140, binding = 3) uniform globals {
    vec4 outputTex_size;
    float blendAmount;
};*/

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    #if 0
        float blendAmount = 0.03;
        //float blendAmount = 1.0;

    	vec4 a = texelFetch(inputTex1, pix, 0);
    	vec4 b = texelFetch(inputTex2, pix, 0);
        vec4 c = b * blendAmount;
        if (blendAmount != 1.0) {
            c += a * (1.0 - blendAmount);
        }

    	imageStore(outputTex, pix, c);
    #else
    	vec3 hist = rgb_to_ycbcr(texelFetch(inputTex1, pix, 0).rgb);
    	vec3 c = rgb_to_ycbcr(texelFetch(inputTex2, pix, 0).rgb);
        
    	vec3 vsum = vec3(0.);
    	vec3 vsum2 = vec3(0.);
    	float wsum = 0;

        const int k = 2;
        for (int y = -k; y <= k; ++y) {
            for (int x = -k; x <= k; ++x) {
                vec3 neigh = rgb_to_ycbcr(texelFetch(inputTex2, pix + ivec2(x, y), 0).rgb);

    			float w = exp(-3.0 * float(x * x + y * y) / float((k+1.) * (k+1.)));
                //float w = 1.0;
    			vsum += neigh * w;
    			vsum2 += neigh * neigh * w;
    			wsum += w;
            }
        }

    	vec3 ex = vsum / wsum;
    	vec3 ex2 = vsum2 / wsum;
    	vec3 dev = sqrt(max(vec3(0.0), ex2 - ex * ex));

        float local_contrast = dev.x / (ex.x + 1e-5);

        float box_size = 1.0;
        box_size *= mix(0.5, 1.0, smoothstep(-0.1, 0.3, local_contrast));
        //float center_blend = box_size * box_size;
        float center_blend = 0.5;
        
        const float n_deviations = 1.0;
    	vec3 nmin = mix(c, ex, center_blend) - dev * box_size * n_deviations;
    	vec3 nmax = mix(c, ex, center_blend) + dev * box_size * n_deviations;

        hist = clamp(hist, nmin, nmax);
        c = mix(hist, c, 1.0 / 8);

        c = ycbcr_to_rgb(c);
        imageStore(outputTex, pix, vec4(c, 1));
    #endif
}
