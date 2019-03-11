#include "inc/uv.inc"

uniform restrict writeonly image2D outputTex;
uniform vec4 outputTex_size;

uniform sampler2D inputTex;
uniform sampler2D historyTex;
uniform sampler2D reprojectionTex;

float calculate_luma(vec3 col) {
	return dot(vec3(0.299, 0.587, 0.114), col);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    vec2 uv = get_uv(outputTex_size);
        
    vec4 contrib = vec4(0.0);

    vec4 reproj = texelFetch(reprojectionTex, pix, 0);
    vec4 history = textureLod(historyTex, uv + reproj.xy, 0);

    float ex = calculate_luma(texelFetch(inputTex, pix, 0).rgb);
    ex = sqrt(ex);
    
    float ex2 = ex * ex;

    float validity = reproj.z * smoothstep(0.1, 0.0, length(reproj.xy));
    float blend = mix(1.0, 0.2, validity);
    ex = mix(history.y, ex, blend);
    ex2 = mix(history.z * history.z, ex2, blend);

    float var = ex2 - ex * ex;
    float dev = sqrt(max(0.0, var));
    float luma_dev = dev / max(1e-1, ex);

    //luma_dev = mix(1.0, luma_dev, validity);

    vec4 result = vec4(max(0.0, luma_dev), ex, sqrt(ex2), 0.0);
    //vec4 result = 1.0.xxxx;
    fragColor = result;
}

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	vec2 fragCoord = vec2(gl_GlobalInvocationID.xy) + 0.5;
	vec4 finalColor;

	mainImage(finalColor, fragCoord);

	imageStore(outputTex, ivec2(gl_GlobalInvocationID.xy), finalColor);
}