#include "rendertoy::shaders/view_constants.inc"
#include "rendertoy::shaders/random.inc"
#include "rendertoy::shaders/sampling.inc"
#include "../inc/uv.inc"
#include "../inc/pack_unpack.inc"
#include "../inc/brdf.inc"
#include "../inc/atmosphere.inc"

uniform sampler2D gbuffer;
uniform vec4 gbuffer_size;

uniform sampler2D aoTex;
uniform sampler2D shadowsTex;

uniform sampler2D skyLambertTex;
uniform sampler2D skyTex;
uniform vec4 skyTex_size;

uniform restrict writeonly image2D outputTex;
uniform vec4 outputTex_size;

layout(std430) buffer constants {
    ViewConstants view_constants;
    vec4 light_dir_pad;
    uint frame_idx;
};

vec3 getSkyColor(vec3 rd) {
    vec3 scatter = atmosphere2(
        rd,                 // normalized ray direction
        vec3(0,6371e3,0),               // ray origin
        // sun pos
        light_dir_pad.xyz,
        6371e3,                         // radius of the planet in meters
        6471e3,                         // radius of the atmosphere in meters
        vec3(5.8e-6, 13.5e-6, 33.1e-6), // frostbite
        21e-6,                          // Mie scattering coefficient
        vec3(3.426e-7, 8.298e-7, 0.356e-7), // Ozone extinction, frostbite
        8e3,                            // Rayleigh scale height
        1.2e3,                          // Mie scale height
        0.758                           // Mie preferred scattering direction
    );
    return scatter * 20.0;
}

vec3 sample_environment_light(vec3 dir) {
    dir = normalize(dir);
    return getSkyColor(dir);
}

vec3 sample_quantized_environment_light(vec3 dir) {
    dir = normalize(dir);
    return texelFetch(skyTex, ivec2(skyTex_size.xy * octa_encode(dir)), 0).rgb;
}

vec3 sample_lambert_convolved_environment_light(vec3 dir) {
    dir = normalize(dir);
    return texelFetch(skyLambertTex, ivec2(skyTex_size.xy * octa_encode(dir)), 0).rgb;
}

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
    ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    vec2 uv = get_uv(outputTex_size);
    vec4 ray_origin_cs = vec4(uv_to_cs(uv), 1.0, 1.0);
    vec4 ray_origin_ws = view_constants.view_to_world * (view_constants.sample_to_view * ray_origin_cs);
    ray_origin_ws /= ray_origin_ws.w;

    vec4 ray_dir_cs = vec4(uv_to_cs(uv), 0.0, 1.0);
    vec4 ray_dir_ws = view_constants.view_to_world * (view_constants.sample_to_view * ray_dir_cs);
    vec3 v = -normalize(ray_dir_ws.xyz);

    vec4 gbuffer = texelFetch(gbuffer, pix, 0);

    vec3 result = vec3(0, 0, 0);
    //vec3 sun_color = vec3(1.4, 1, 0.8) * 2.8;
    //vec3 sun_color = sample_environment_light(light_dir_pad.xyz) * vec3(1.4, 1, 0.8) * 2.0;
    vec3 sun_color = sample_quantized_environment_light(light_dir_pad.xyz) * vec3(1.4, 1, 0.8) * 2.0;

    if (gbuffer.a == 0.0) {
        result = sample_environment_light(-v);
    } else {
        vec3 normal = unpack_normal_11_10_11(gbuffer.x);
        vec3 albedo = unpack_color_888(floatBitsToUint(gbuffer.z));
        vec3 env_color = sample_lambert_convolved_environment_light(normal);

        vec4 ssgi = texelFetch(aoTex, pix, 0);
        result += albedo * env_color * ssgi.a;
        result += albedo * ssgi.rgb;

        float shadows = texelFetch(shadowsTex, pix, 0).r;
        float ndotl = max(0, dot(normal, light_dir_pad.xyz));
        result += albedo * ndotl * shadows * sun_color;

        //result = albedo;
    }

    //result = texture(skyTex, uv).rgb;

    imageStore(outputTex, pix, vec4(result, 1));
}
