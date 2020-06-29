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
layout(rgba32f) uniform coherent image2D rwtex;

layout(std430) buffer frag_constants {
    ViewConstants view_constants;
    uint frame_idx;
};

in vec4 gl_FragCoord;
//in int gl_PrimitiveID;

vec2 uv_to_cs(vec2 uv) {
	return (uv - 0.5.xx) * vec2(2, -2);
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

    #if 1
        #if 1
            vec4 noise = texelFetch(blue_noise_tex, (ivec2(pix) + ivec2(frame_idx * 59, frame_idx * 37)) & 255, 0);
            //float noise = (1.0 / 4.0) * ((pix.y - pix.x) & 3);

            depth = subgroupQuadBroadcast(depth, 0);
            uint udepth = floatBitsToUint(depth) ^ hash(frame_idx);
            uint seed = hash(udepth);
            float u = fract(noise.x + rand_float(seed));
        #else
            uint seed = hash(gl_PrimitiveID);
            vec4 noise = texelFetch(blue_noise_tex, (ivec2(pix) + ivec2(seed, seed >> 8) + ivec2(frame_idx * 59, frame_idx * 37)) & 255, 0);
            float u = noise.x * 0.9999;
            //float u = fract(noise.x + rand_float(hash(frame_idx)));
        #endif
    #else
        vec4 noise = texelFetch(blue_noise_tex, ivec2(pix + frame_idx * 37) & 255, 0);
        uint udepth = floatBitsToUint(depth) ^ hash(frame_idx);
        uint seed = hash(udepth);
        float u = fract(noise.x + rand_float(seed));
    #endif

    if (u > opacity) {
        discard;
    }

	out_color = vec4(color, 1.0);
}
