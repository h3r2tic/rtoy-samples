#include "rendertoy::shaders/random.inc"
#include "rendertoy::shaders/sampling.inc"

uniform restrict writeonly image2D outputTex;
uniform texture2D inputTex;
uniform texture2D filteredLogLumTex;
layout(std140) uniform globals {
    float sharpen_amount;
    vec4 outputTex_size;
};

// Rec. 709
float calculate_luma(vec3 col) {
	return dot(vec3(0.2126, 0.7152, 0.0722), col);
}

float tonemap_curve(float v, float lin_part) {
    #if 0
        float c = v + v*v + 0.5*v*v*v;
        return c / (1.0 + c);
    #elif 0
        return 1 - exp(-v);
    #else
        float n = 1.0 + exp(3 * lin_part);
        return 1 - (1.0 - v) / (1.0 - pow(v, n));
    #endif
}

vec3 tonemap_curve(vec3 v, float lin_part) {
    return vec3(tonemap_curve(v.r, lin_part), tonemap_curve(v.g, lin_part), tonemap_curve(v.b, lin_part));
}

vec3 neutral_tonemap(vec3 col, float lin_part) {
    mat3 ycbr_mat = mat3(.2126, .7152, .0722, -.1146,-.3854, .5, .5,-.4542,-.0458);
    vec3 ycbcr = col * ycbr_mat;

    float chroma = length(ycbcr.yz) * 2.4;
    float bt = tonemap_curve(chroma, lin_part);

    float desat = max((bt - 0.7) * 0.8, 0.0);
    desat *= desat;
    //return bt.xxx * 1;

    vec3 desat_col = mix(col.rgb, ycbcr.xxx, desat);

    float tm_luma = tonemap_curve(ycbcr.x, lin_part);
    vec3 tm0 = col.rgb * max(0.0, tm_luma / max(1e-5, calculate_luma(col.rgb)));
    float final_mult = 0.97;
    vec3 tm1 = tonemap_curve(desat_col, lin_part);

    col = mix(tm0, tm1, bt * bt);

    return col * final_mult;
}

float sharpen_remap(float l) {
    return sqrt(l);
}

float sharpen_inv_remap(float l) {
    return l * l;
}

float local_tmo_constrain(float x, float max_compression) {
    return exp(tanh(log(x) / max_compression) * max_compression);
}

vec3 piecewise(vec3 threshold, vec3 a, vec3 b) {
    vec3 res;
    res.x = a.x < threshold.x ? a.x : b.x;
    res.y = a.y < threshold.y ? a.y : b.y;
    res.z = a.z < threshold.z ? a.z : b.z;
    return res;
}

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    float filtered_luminance = exp(texelFetch(filteredLogLumTex, pix, 0).x);
    float filtered_luminance_high = texelFetch(filteredLogLumTex, pix, 0).y;

    if (!true) {
        vec3 col = neutral_tonemap(filtered_luminance_high.xxx, 0.0);
        //col -= neutral_tonemap(filtered_luminance.xxx);
        imageStore(outputTex, pix, col.rgbg);
        return;
    }

    float avg_luminance = 0;
    for (float y = 0.05; y < 1.0; y += 0.1) {
        for (float x = 0.05; x < 1.0; x += 0.1) {
            avg_luminance += texelFetch(filteredLogLumTex, ivec2(outputTex_size.xy * vec2(x, y)), 0).x;
        }
    }
    avg_luminance = exp(avg_luminance / (10 * 10));

	vec4 col = texelFetch(inputTex, pix, 0);

    if (!true) {
        col *= 0.333 / avg_luminance;
        col.rgb = 1.0 - exp(-col.rgb);
        //col.rgb = neutral_tonemap(col.rgb, 0.3);
        imageStore(outputTex, pix, col);
        return;
    }

    float avg_mult = 0.333 / avg_luminance;
    float mult = 0.333 / filtered_luminance;
    float relative_mult = mult / avg_mult;
    float max_compression = 1.0;
    relative_mult = local_tmo_constrain(relative_mult, max_compression);
    float remapped_mult = relative_mult * avg_mult;
    remapped_mult = mix(remapped_mult, avg_mult, 0.1);
    col *= remapped_mult;

    float lin_part = clamp(remapped_mult * (0.8 * filtered_luminance - 0.2 * filtered_luminance_high), 0.0, 0.5);

    col.rgb = neutral_tonemap(col.rgb, lin_part);
    //col.r = col.a * 10.0;
    //col.rgb = 1.0 - exp(-col.rgb);
    //col.rgb = lin_part.xxx;

	imageStore(outputTex, pix, col);
}
