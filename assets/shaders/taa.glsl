#include "inc/uv.inc"

uniform restrict writeonly image2D outputTex;
uniform vec4 outputTex_size;

uniform sampler2D inputTex;
uniform sampler2D historyTex;
uniform sampler2D reprojectionTex;

vec4 fetchHistory(vec2 uv)
{
	return texture2D(historyTex, uv, 0.0);
}

// note: entirely stolen from https://gist.github.com/TheRealMJP/c83b8c0f46b63f3a88a5986f4fa982b1
// Samples a texture with Catmull-Rom filtering, using 9 texture fetches instead of 16.
// See http://vec3.ca/bicubic-filtering-in-fewer-taps/ for more details
vec4 fetchHistoryCatmullRom(vec2 uv)
{
    vec2 texelSize = outputTex_size.zw;

    // We're going to sample a a 4x4 grid of texels surrounding the target UV coordinate. We'll do this by rounding
    // down the sample location to get the exact center of our "starting" texel. The starting texel will be at
    // location [1, 1] in the grid, where [0, 0] is the top left corner.
    vec2 samplePos = uv / texelSize;
    vec2 texPos1 = floor(samplePos - 0.5) + 0.5;

    // Compute the fractional offset from our starting texel to our original sample location, which we'll
    // feed into the Catmull-Rom spline function to get our filter weights.
    vec2 f = samplePos - texPos1;

    // Compute the Catmull-Rom weights using the fractional offset that we calculated earlier.
    // These equations are pre-expanded based on our knowledge of where the texels will be located,
    // which lets us avoid having to evaluate a piece-wise function.
    vec2 w0 = f * ( -0.5 + f * (1.0 - 0.5*f));
    vec2 w1 = 1.0 + f * f * (-2.5 + 1.5*f);
    vec2 w2 = f * ( 0.5 + f * (2.0 - 1.5*f) );
    vec2 w3 = f * f * (-0.5 + 0.5 * f);
    
    // Work out weighting factors and sampling offsets that will let us use bilinear filtering to
    // simultaneously evaluate the middle 2 samples from the 4x4 grid.
    vec2 w12 = w1 + w2;
    vec2 offset12 = w2 / (w1 + w2);

    // Compute the final UV coordinates we'll use for sampling the texture
    vec2 texPos0 = texPos1 - vec2(1.0);
    vec2 texPos3 = texPos1 + vec2(2.0);
    vec2 texPos12 = texPos1 + offset12;

    texPos0 *= texelSize;
    texPos3 *= texelSize;
    texPos12 *= texelSize;

    vec4 result = vec4(0.0);
    result += fetchHistory(vec2(texPos0.x,  texPos0.y)) * w0.x * w0.y;
    result += fetchHistory(vec2(texPos12.x, texPos0.y)) * w12.x * w0.y;
    result += fetchHistory(vec2(texPos3.x,  texPos0.y)) * w3.x * w0.y;

    result += fetchHistory(vec2(texPos0.x,  texPos12.y)) * w0.x * w12.y;
    result += fetchHistory(vec2(texPos12.x, texPos12.y)) * w12.x * w12.y;
    result += fetchHistory(vec2(texPos3.x,  texPos12.y)) * w3.x * w12.y;

    result += fetchHistory(vec2(texPos0.x,  texPos3.y)) * w0.x * w3.y;
    result += fetchHistory(vec2(texPos12.x, texPos3.y)) * w12.x * w3.y;
    result += fetchHistory(vec2(texPos3.x,  texPos3.y)) * w3.x * w3.y;

    return result;
}


void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    ivec2 px = ivec2(fragCoord);
    vec2 uv = get_uv(outputTex_size);
    
    vec3 center = texelFetch(inputTex, px, 0).rgb;
	//vec4 history = texelFetch(historyTex, px, 0);
    vec4 reproj = texelFetch(reprojectionTex, px, 0);
    vec4 history = max(0.0.xxxx, fetchHistoryCatmullRom(uv + reproj.xy));
    
	vec3 vsum = vec3(0.);
	vec3 vsum2 = vec3(0.);
	float wsum = 0;

    vec3 nmin = center;
    vec3 nmax = center;
    
	const int k = 1;
    for (int y = -k; y <= k; ++y) {
        for (int x = -k; x <= k; ++x) {
            vec3 neigh = texelFetch(inputTex, px + ivec2(x, y), 0).rgb;
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

    float box_size = mix(0.5, 2.5, smoothstep(0.01, 0.0, length(reproj.xy)));

	nmin = ex - dev * box_size;
	nmax = ex + dev * box_size;
    
	#if 1
		vec3 result;
		if (true) {
			vec3 clamped_history = clamp(history.rgb, nmin, nmax);
			//clamped_history = mix(clamped_history, history.rgb, 0.6);
			result = mix(clamped_history, center, mix(1.0, 1.0 / 16.0, reproj.z));
		} else if (true) {
			result = mix(history.rgb, center, 1.0 / 16.0);
		} else {
			result = center;
		}
		
		fragColor = vec4(result, 1.0);
	#else
		fragColor = vec4(center, 1.0);
	#endif
}

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	vec2 fragCoord = vec2(gl_GlobalInvocationID.xy) + 0.5;
	vec4 finalColor;

	mainImage(finalColor, fragCoord);

	imageStore(outputTex, ivec2(gl_GlobalInvocationID.xy), finalColor);
}