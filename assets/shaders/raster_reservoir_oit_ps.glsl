#extension GL_ARB_fragment_shader_interlock: require
#extension GL_KHR_shader_subgroup_quad: require

#include "inc/color.inc"
#include "rendertoy::shaders/view_constants.inc"
#include "rendertoy::shaders/random.inc"

layout(location = 0) out vec4 out_color;
layout(location = 0) in vec3 v_normal;
layout(location = 4) in vec3 v_world_position;
layout(location = 6) in vec2 v_uv;
layout(location = 7) in flat uint v_material_id;

uniform texture2D blue_noise_tex;

layout(rgba32ui) uniform coherent uimage2D rwtex;
layout(rgba32ui) uniform coherent uimage2D rwtex2;

layout(std430) buffer frag_constants {
    ViewConstants view_constants;
    uint frame_idx;
};

in vec4 gl_FragCoord;

vec2 uv_to_cs(vec2 uv) {
	return (uv - 0.5.xx) * vec2(2, -2);
}

uvec2 pack_color(vec3 color) {
    return uvec2(packHalf2x16(color.rg), floatBitsToUint(color.b));
}

vec3 unpack_color(uvec2 packed) {
    return vec3(unpackHalf2x16(packed.x), uintBitsToFloat(packed.y));
}

float sqr(float x) {
    return x * x;
}

float depth_diff_penalty(float a, float b) {
    a = 1.0 / a;
    b = 1.0 / b;

    float d = (abs(a - b) / (a + b));
    return (1.0 - exp(-4.0 * d)) * 4.0; // scale-independent; bullshit remap
    //return 0.001 * abs(a - b);    // bullshit scale
}

uvec4 resolve_fragment_against_reservoir(float opacity, uvec2 color_packed, float depth, uvec4 prev_oit, float urand) {
    float p = opacity;
    float p_prev = uintBitsToFloat(prev_oit.w);
    float p_sum = p_prev + p;
    float p_total = 1 - (1 - p_prev) * (1 - p);
    float depth_prev = uintBitsToFloat(prev_oit.z);

    uvec4 result = uvec4(prev_oit.xyz, floatBitsToUint(p_total));

    if (depth > depth_prev) {
        // New fragment is closer than the old one

        // p: place the new pixel
        // (1 - p) * p_prev: use the old pixel
        // (1 - p) * (1 - p_prev): no pixel

        if (urand * p_total < p) {
            result = uvec4(color_packed, floatBitsToUint(depth), floatBitsToUint(p_total));
        }
    } else {
        // New fragment is farther than the old one

        // p_prev: use the old pixel
        // (1 - p_prev) * p: place the new pixel
        // (1 - p_prev) * (1 - p): no pixel

        if (urand * p_total < (1 - p_prev) * p) {
            result = uvec4(color_packed, floatBitsToUint(depth), floatBitsToUint(p_total));
        }
    }

    return result;
}

void main() {
    uvec2 pix = uvec2(gl_FragCoord.xy);
    vec2 uv = (vec2(pix) + 0.5) / vec2(1920, 1080);
    vec4 ray_dir_cs = vec4(uv_to_cs(uv), 0.0, 1.0);
    vec4 ray_dir_vs = view_constants.sample_to_view * ray_dir_cs;
    vec4 ray_dir_ws = view_constants.view_to_world * ray_dir_vs;
    vec3 v = -normalize(ray_dir_ws.xyz);
    float ndotv = abs(dot(normalize(v_normal), v));
    float opacity = mix(0.3, 0.8, 1 - pow(1 - ndotv, 2));
    float ygradient = smoothstep(20.0, 0.0, v_world_position.y * 0.05);
    ygradient = 1 - pow(1 - ygradient, 2);
    opacity = mix(0.7, opacity, ygradient);
    vec3 color = ycbcr_to_rgb(vec3(
        ygradient * 0.18,
        cos(v_world_position.z * 0.01) * 0.2 + 0.6,
        sin(v_world_position.x * 0.013) * 0.5 + sin(v_world_position.y * 0.017) * 0.5
    ) * vec3(1, 0.25 * ygradient, 0.25 * ygradient));
    color += mix(0.0, 0.25, pow(1 - ndotv, 2)) * ygradient;
    //color *= (sin(v_world_position.x * 0.01 + 1.5) * 4.0 + 4.0);
    color = max(0.0.xxx, color);
    opacity *= 0.6; // adjust for two-sided rendering
    //opacity = 0.75;

    // ----

    float depth = gl_FragCoord.z;

    vec4 noise = texelFetch(blue_noise_tex, ivec2(pix + frame_idx * 37) & 255, 0);
    uint udepth = floatBitsToUint(subgroupQuadBroadcast(depth, 0)) ^ hash(frame_idx);
    uint seed = hash(udepth);
    vec4 u = fract(noise * 0.9999 + vec4(rand_float(seed), rand_float(hash(seed)), 0, 0));
    
    beginInvocationInterlockARB();

    uvec4 prev_oit1 = imageLoad(rwtex, ivec2(pix));
    uvec4 prev_oit2 = imageLoad(rwtex2, ivec2(pix));
    float p_prev1 = uintBitsToFloat(prev_oit1.w);
    float p_prev2 = uintBitsToFloat(prev_oit2.w);

    if (p_prev1 == 0.0) {
        imageStore(rwtex, ivec2(pix), uvec4(pack_color(color), floatBitsToUint(depth), floatBitsToUint(opacity)));
    } else if (p_prev2 == 0.0) {
        imageStore(rwtex2, ivec2(pix), uvec4(pack_color(color), floatBitsToUint(depth), floatBitsToUint(opacity)));
    } else {
        vec3 prev_oit1_color = unpack_color(prev_oit1.xy);
        vec3 prev_oit2_color = unpack_color(prev_oit2.xy);

        float l = calculate_luma(color);
        float l1 = calculate_luma(prev_oit1_color);
        float l2 = calculate_luma(prev_oit2_color);

        float depth1 = uintBitsToFloat(prev_oit1.z);
        float depth2 = uintBitsToFloat(prev_oit2.z);

        float p = opacity;
        float p_total1 = 1 - (1 - p_prev1) * (1 - p);
        float p_total2 = 1 - (1 - p_prev2) * (1 - p);
        float p_total3 = 1 - (1 - p_prev1) * (1 - p_prev2);

        float err1 = abs(l - l1) + depth_diff_penalty(depth1, depth);
        float err2 = abs(l - l2) + depth_diff_penalty(depth2, depth);
        float err3 = abs(l1 - l2) + depth_diff_penalty(depth1, depth2);

        if (err3 < min(err1, err2)) {
            imageStore(rwtex2, ivec2(pix), resolve_fragment_against_reservoir(
                p_prev1, prev_oit1.xy, depth1, prev_oit2, u.x
            ));

            imageStore(rwtex, ivec2(pix), uvec4(pack_color(color), floatBitsToUint(depth), floatBitsToUint(p)));
        } else {
            if (err1 < err2) {  // Less noisy, but noise varies
                imageStore(rwtex, ivec2(pix), resolve_fragment_against_reservoir(
                    opacity, pack_color(color), depth, prev_oit1, u.x
                ));
            } else {
                imageStore(rwtex2, ivec2(pix), resolve_fragment_against_reservoir(
                    opacity, pack_color(color), depth, prev_oit2, u.x
                ));
            }
        }
    }

    endInvocationInterlockARB();
    discard;
}
