#include "inc/uv.inc"

uniform restrict writeonly image2D outputTex;
uniform vec4 outputTex_size;

uniform sampler2D inputTex;
uniform sampler2D historyTex;
uniform sampler2D reprojectionTex;

layout(std430) buffer constants {
    vec2 jitter;
};

float calculate_luma(vec3 col) {
	return dot(vec3(0.2126, 0.7152, 0.0722), col);
}

#define ENCODING_VARIANT 2

vec3 decode(vec3 a) {
    #if 0 == ENCODING_VARIANT
    return a;
    #elif 1 == ENCODING_VARIANT
    return sqrt(a);
    #elif 2 == ENCODING_VARIANT
    return log(1+sqrt(a));
    #endif
}

vec3 encode(vec3 a) {
    #if 0 == ENCODING_VARIANT
    return a;
    #elif 1 == ENCODING_VARIANT
    return a * a;
    #elif 2 == ENCODING_VARIANT
    a = exp(a) - 1;
    return a * a;
    #endif
}

vec4 fetchHistory(vec2 uv)
{
	return vec4(decode(texture2D(historyTex, uv, 0.0).xyz), 1);
}

vec4 fetchHistoryPx(ivec2 pix)
{
	return vec4(decode(texelFetch(historyTex, pix, 0).xyz), 1);
}

vec3 CubicHermite (vec3 A, vec3 B, vec3 C, vec3 D, float t)
{
	float t2 = t*t;
    float t3 = t*t*t;
    vec3 a = -A/2.0 + (3.0*B)/2.0 - (3.0*C)/2.0 + D/2.0;
    vec3 b = A - (5.0*B)/2.0 + 2.0*C - D / 2.0;
    vec3 c = -A/2.0 + C/2.0;
   	vec3 d = B;
    
    return a*t3 + b*t2 + c*t + d;
}

// https://www.shadertoy.com/view/MllSzX
vec3 BicubicHermiteTextureSample (vec2 P)
{
    vec2 pixel = P * outputTex_size.xy + 0.5;
    vec2 c_onePixel = outputTex_size.zw;
    vec2 c_twoPixels = outputTex_size.zw * 2.0;
    
    vec2 frac = fract(pixel);
    //pixel = floor(pixel) / outputTex_size.xy - vec2(c_onePixel/2.0);
    ivec2 ipixel = ivec2(pixel) - 1;
    
    vec3 C00 = fetchHistoryPx(ipixel + ivec2(-1 ,-1)).rgb;
    vec3 C10 = fetchHistoryPx(ipixel + ivec2( 0        ,-1)).rgb;
    vec3 C20 = fetchHistoryPx(ipixel + ivec2( 1 ,-1)).rgb;
    vec3 C30 = fetchHistoryPx(ipixel + ivec2( 2,-1)).rgb;
    
    vec3 C01 = fetchHistoryPx(ipixel + ivec2(-1 , 0)).rgb;
    vec3 C11 = fetchHistoryPx(ipixel + ivec2( 0        , 0)).rgb;
    vec3 C21 = fetchHistoryPx(ipixel + ivec2( 1 , 0)).rgb;
    vec3 C31 = fetchHistoryPx(ipixel + ivec2( 2, 0)).rgb;    
    
    vec3 C02 = fetchHistoryPx(ipixel + ivec2(-1 , 1)).rgb;
    vec3 C12 = fetchHistoryPx(ipixel + ivec2( 0        , 1)).rgb;
    vec3 C22 = fetchHistoryPx(ipixel + ivec2( 1 , 1)).rgb;
    vec3 C32 = fetchHistoryPx(ipixel + ivec2( 2, 1)).rgb;    
    
    vec3 C03 = fetchHistoryPx(ipixel + ivec2(-1 , 2)).rgb;
    vec3 C13 = fetchHistoryPx(ipixel + ivec2( 0        , 2)).rgb;
    vec3 C23 = fetchHistoryPx(ipixel + ivec2( 1 , 2)).rgb;
    vec3 C33 = fetchHistoryPx(ipixel + ivec2( 2, 2)).rgb;    
    
    vec3 CP0X = CubicHermite(C00, C10, C20, C30, frac.x);
    vec3 CP1X = CubicHermite(C01, C11, C21, C31, frac.x);
    vec3 CP2X = CubicHermite(C02, C12, C22, C32, frac.x);
    vec3 CP3X = CubicHermite(C03, C13, C23, C33, frac.x);
    
    return CubicHermite(CP0X, CP1X, CP2X, CP3X, frac.y);
}

vec4 fetchHistoryCatmullRom(vec2 uv)
{
    // The one below seems to smear a bit vertically; Use the brute force version for now.
    return vec4(BicubicHermiteTextureSample(uv), 1);

    // note: entirely stolen from https://gist.github.com/TheRealMJP/c83b8c0f46b63f3a88a5986f4fa982b1
    // Samples a texture with Catmull-Rom filtering, using 9 texture fetches instead of 16.
    // See http://vec3.ca/bicubic-filtering-in-fewer-taps/ for more details
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

float mitchell_netravali(float x) {
    float B = 1.0 / 3.0;
    float C = 1.0 / 3.0;

    float ax = abs(x);
    if (ax < 1) {
        return ((12 - 9 * B - 6 * C) * ax * ax * ax + (-18 + 12 * B + 6 * C) * ax * ax + (6 - 2 * B)) / 6;
    } else if ((ax >= 1) && (ax < 2)) {
        return ((-B - 6 * C) * ax * ax * ax + (6 * B + 30 * C) * ax * ax + (-12 * B - 48 * C) * ax + (8 * B + 24 * C)) / 6;
    } else {
        return 0;
    }
}

vec3 fetch_center_filtered(ivec2 pix) {
    vec4 res = 0.0.xxxx;
    float scl = 1.1;

    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            ivec2 src = pix + ivec2(x, y);
            vec4 col = vec4(decode(texelFetch(inputTex, src, 0).rgb), 1);
            float dist = length(-jitter - vec2(x, y));
            float wt = mitchell_netravali(dist * scl);
            col *= wt;
            res += col;
        }
    }

    return res.rgb / res.a;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    ivec2 px = ivec2(fragCoord);
    vec2 uv = get_uv(outputTex_size);
    
    vec3 center = decode(texelFetch(inputTex, px, 0).rgb);
	//vec4 history = texelFetch(historyTex, px, 0);
    vec4 reproj = texelFetch(reprojectionTex, px, 0);
    vec2 history_uv = uv + reproj.xy * vec2(1.0, 1.0);
    vec3 history = max(0.0.xxx, fetchHistoryCatmullRom(history_uv).xyz);
    
	vec3 vsum = vec3(0.);
	vec3 vsum2 = vec3(0.);
	float wsum = 0;

    vec3 nmin = center;
    vec3 nmax = center;
    
	const int k = 1;
    for (int y = -k; y <= k; ++y) {
        for (int x = -k; x <= k; ++x) {
            vec3 neigh = decode(texelFetch(inputTex, px + ivec2(x, y), 0).rgb);
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

    //float local_contrast = calculate_luma(dev / (min(ex, history) + 1e-5));
    float local_contrast = calculate_luma(dev / (ex + 1e-5));

    vec2 history_pixel = history_uv * outputTex_size.xy;
    float texel_center_dist = dot(1.0.xx, abs(0.5 - fract(history_pixel)));

    float box_size = 1.0;
    box_size *= mix(0.5, 1.0, smoothstep(-0.1, 0.3, local_contrast));
    box_size *= mix(0.5, 1.0, clamp(1.0 - texel_center_dist, 0.0, 1.0));

    center = fetch_center_filtered(px);

    const float n_deviations = 1.5;
	nmin = mix(center, ex, box_size * box_size) - dev * box_size * n_deviations;
	nmax = mix(center, ex, box_size * box_size) + dev * box_size * n_deviations;
    nmin = max(nmin, 0.0.xxx);

    float blend_factor = 1.0;
    
	#if 1
		vec3 result;
		if (true) {
			vec3 clamped_history = clamp(history, nmin, nmax);
            blend_factor = mix(1.0, 1.0 / 12.0, reproj.z);

            // "Anti-flicker"
            float clamp_dist = dot(1.0.xxx, (min(abs(history - nmin), abs(history - nmax))) / max(max(history, ex), 1e-5));
            blend_factor *= mix(0.2, 1.0, smoothstep(0.0, 4.0, clamp_dist));

			result = mix(clamped_history, center, blend_factor);
		} else if (true) {
            //float blend = mix(1.0, 1.0 / 16, smoothstep(0.05, 0.0, length(reproj.xy)));
            float blend = 1.0 / 16;
			result = mix(history.rgb, center, blend);
		} else {
			result = center;
		}

		fragColor = vec4(encode(result), blend_factor);
	#else
		fragColor = vec4(encode(center), 1.0);
	#endif

    //fragColor = vec4(texel_center_dist.xxx, 1);
    //fragColor = vec4(box_size.xxx, 1);
    //fragColor = vec4((dev / (ex + 1e-5)), 1);
}

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	vec2 fragCoord = vec2(gl_GlobalInvocationID.xy) + 0.5;
	vec4 finalColor;

	mainImage(finalColor, fragCoord);

	imageStore(outputTex, ivec2(gl_GlobalInvocationID.xy), finalColor);
}