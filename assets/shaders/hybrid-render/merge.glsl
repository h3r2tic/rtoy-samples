#include "rendertoy::shaders/random.inc"
#include "../inc/uv.inc"
#include "../inc/pack_unpack.inc"
#include "../inc/brdf.inc"

uniform sampler2D gbuffer;
uniform vec4 gbuffer_size;

uniform sampler2D aoTex;
uniform sampler2D shadowsTex;

uniform restrict writeonly image2D outputTex;
uniform vec4 outputTex_size;

layout(std430) buffer constants {
    mat4 view_to_clip;
    mat4 clip_to_view;
    mat4 world_to_view;
    mat4 view_to_world;
    vec4 light_dir_pad;
};

vec3 sample_environment_light(vec3 dir) {
    //return vec3(0.09, 0.2, 0.4);
    //return 0.2.xxx;
    dir = normalize(dir);
    //dir.y = abs(dir.y);
    vec3 col = (dir.zyx * vec3(1, 1, -1) * 0.5 + vec3(0.6, 0.5, 0.5)) * 0.75;
    col = mix(col, 1.3 * dot(col, vec3(0.2, 0.7, 0.1)).xxx, smoothstep(0.3, 0.8, col.g).xxx);
    return col * 0.6;
}

vec3 ao_multibounce(float visibility, vec3 albedo) {
    vec3 a = 2.0404 * albedo - 0.3324;
    vec3 b = -4.7951 * albedo + 0.6417;
    vec3 c = 2.7552 * albedo + 0.6903;

    float x = visibility;
    return max(x.xxx, ((x * a + b) * x + c) * x);
}

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
    ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    vec2 uv = get_uv(outputTex_size);
    vec4 ray_origin_cs = vec4(uv_to_cs(uv), 1.0, 1.0);
    vec4 ray_origin_ws = view_to_world * (clip_to_view * ray_origin_cs);
    ray_origin_ws /= ray_origin_ws.w;

    vec4 ray_dir_cs = vec4(uv_to_cs(uv), 0.0, 1.0);
    vec4 ray_dir_ws = view_to_world * (clip_to_view * ray_dir_cs);
    vec3 v = -normalize(ray_dir_ws.xyz);

    vec4 gbuffer = texelFetch(gbuffer, pix, 0);

    vec3 result = vec3(0, 0, 0);

    if (gbuffer.a == 0.0) {
        result = sample_environment_light(-v);
    } else {
        vec3 normal = unpack_normal_11_10_11(gbuffer.x);
        //vec3 albedo = 0.3.xxx;
        vec3 albedo = unpack_color_888(floatBitsToUint(gbuffer.z));

        // De-light in a horrible way
        //albedo = 0.35 * albedo / max(0.001, max(max(albedo.x, albedo.y), albedo.z));

        vec3 env_color = sample_environment_light(normal);
        // Desaturate for a cheapo pretend diffuse pre-integration
        env_color = mix(env_color, dot(vec3(0.212, 0.701, 0.087), env_color).xxx, 0.7);

        float ao = texelFetch(aoTex, pix, 0).r;
        result += albedo * env_color * ao_multibounce(ao, albedo);

        float shadows = texelFetch(shadowsTex, pix, 0).r;
        float ndotl = max(0, dot(normal, light_dir_pad.xyz));
        vec3 sun_color = vec3(1.0, 0.95, 0.9) * 2.0;
        result += albedo * ndotl * shadows * sun_color;

        vec3 microfacet_normal = calculate_microfacet_normal(light_dir_pad.xyz, v);
        BrdfEvalParams brdf_eval_params;
        brdf_eval_params.normal = normal;
        brdf_eval_params.outgoing = v;
        brdf_eval_params.incident = light_dir_pad.xyz;
        brdf_eval_params.microfacet_normal = microfacet_normal;

        GgxParams ggx_params;
        ggx_params.roughness = 0.1;

        BrdfEvalResult brdf_result = evaluate_ggx(brdf_eval_params, ggx_params);
        float refl = brdf_result.value;

        float schlick = 1.0 - abs(brdf_result.ldotm);
        schlick = schlick * schlick * schlick * schlick * schlick;
        float fresnel = mix(0.04, 1.0, schlick);
        result += ndotl * shadows * sun_color * refl * fresnel;

        //result = ao.xxx;
        //result = albedo;
    }

    {
        uint seed0 = hash(hash(pix.x) ^ pix.y);
        float rnd = rand_float(seed0);
        result.rgb += (rnd - 0.5) / 256.0;
    }

    imageStore(outputTex, pix, vec4(result, 1));
}
