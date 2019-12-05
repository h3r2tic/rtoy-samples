#include "rendertoy::shaders/view_constants.inc"
#include "rendertoy::shaders/random.inc"
#include "rendertoy::shaders/sampling.inc"
#include "../inc/uv.inc"
#include "../inc/pack_unpack.inc"
#include "../inc/brdf.inc"
#include "../inc/atmosphere.inc"

uniform texture2D gbuffer;
uniform texture2D aoTex;
uniform texture2D shadowsTex;

uniform restrict writeonly image2D outputTex;

layout(std430) buffer constants {
    ViewConstants view_constants;
    vec4 light_dir_pad;
    uint frame_idx;
};

layout(std140) uniform globals {
    vec4 gbuffer_size;
    vec4 outputTex_size;
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

    /*float sundot = clamp(dot(rd, light_dir_pad.xyz),0.0,1.0);
	vec3 col = vec3(0.2,0.5,0.85)*1.1 - max(rd.y,0.01)*max(rd.y,0.01)*0.5;
    col = mix( col, 0.85*vec3(0.7,0.75,0.85), pow(1.0-max(rd.y,0.0), 6.0) );

    col += 0.25*vec3(1.0,0.7,0.4)*pow( sundot,5.0 );
    col += 0.25*vec3(1.0,0.8,0.6)*pow( sundot,64.0 );
    col += 0.20*vec3(1.0,0.8,0.6)*pow( sundot,512.0 );
    
    col += clamp((0.1-rd.y)*10., 0., 1.) * vec3(.0,.1,.2);
    col += 0.2*vec3(1.0,0.8,0.6)*pow( sundot, 8.0 );

    //col = pow(max(0.0.xxx, col), 2.2.xxx);

    return col;*/
}

vec3 sample_environment_light(vec3 dir) {
    return getSkyColor(dir);
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
    vec4 ray_origin_ws = view_constants.view_to_world * (view_constants.sample_to_view * ray_origin_cs);
    ray_origin_ws /= ray_origin_ws.w;

    vec4 ray_dir_cs = vec4(uv_to_cs(uv), 0.0, 1.0);
    vec4 ray_dir_ws = view_constants.view_to_world * (view_constants.sample_to_view * ray_dir_cs);
    vec3 v = -normalize(ray_dir_ws.xyz);

    vec4 gbuffer = texelFetch(gbuffer, pix, 0);

    vec3 result = vec3(0, 0, 0);
    vec3 sun_color = sample_environment_light(light_dir_pad.xyz);

    float sang = acos(min(1.0, dot(-v, light_dir_pad.xyz))) * 180.0 / PI;

    if (gbuffer.a == 0.0) {
        result = sample_environment_light(-v);
        float sangm = 0.52;
        #if 0
        if (sang < sangm) {
            float t = sang / sangm;
            result.rgb += result.rgb * mix(12.0, 4.0, t);
        }
        #else
        float t = sang / sangm;
        result.rgb += result.rgb * mix(10.0, 8.0, min(1.0, t)) * smoothstep(1.2, 0.7, t);
        //result.rgb *= 0.0;
        #endif
    } else {
        vec3 normal = unpack_normal_11_10_11(gbuffer.x);
        vec3 albedo = 0.3.xxx;
        //vec3 albedo = unpack_color_888(floatBitsToUint(gbuffer.z));

        // De-light in a horrible way
        //albedo = 0.35 * albedo / max(0.001, max(max(albedo.x, albedo.y), albedo.z));

        vec3 env_color = sample_environment_light(normal);
        // Desaturate for a cheapo pretend diffuse pre-integration
        env_color = mix(env_color, dot(vec3(0.212, 0.701, 0.087), env_color).xxx, 0.7);

#if 1
        env_color = 0.0.xxx;
        uint env_sample_cnt = 8;
        for (uint env_sample_idx = 0; env_sample_idx < env_sample_cnt; ++env_sample_idx)
        {
            uint sample_seed = env_sample_idx + frame_idx * 4;
            uint seed0 = hash(hash(sample_seed ^ hash(pix.x) ^ 19329) ^ pix.y);
            uint seed1 = hash(seed0);
            vec3 sr = uniform_sample_sphere(vec2(rand_float(seed0), rand_float(seed1)));
            vec3 ao_dir = normal + sr;
            env_color += sample_environment_light(ao_dir);
        }
        env_color /= float(env_sample_cnt);
#endif

        float ao = texelFetch(aoTex, pix, 0).r;
        result += albedo * env_color * ao_multibounce(ao, albedo);

        float shadows = texelFetch(shadowsTex, pix, 0).r;
        float ndotl = max(0, dot(normal, light_dir_pad.xyz));
        //vec3 sun_color = vec3(1.0, 0.95, 0.9) * 2.0;
        result += albedo * ndotl * shadows * sun_color;

        /*vec3 microfacet_normal = calculate_microfacet_normal(light_dir_pad.xyz, v);
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
        result += ndotl * shadows * sun_color * refl * fresnel;*/

        //result = ao.xxx;
        //result = albedo;
    }

    // glare
    #if 1
    result.rgb += exp(-sang*sang * 0.0001) * sun_color * 0.003;
    result.rgb += exp(-sang*sang * 0.001) * sun_color * 0.02;
    result.rgb += exp(-sang*sang * 0.01) * sun_color * 0.1;
    result.rgb += exp(-sang*sang * 0.1) * sun_color * 0.1;
    result.rgb += exp(-sang*sang * 0.6) * sun_color * 0.2;
    result.rgb += exp(-sang*sang * 2.4) * sun_color * 0.2;
    #endif

    {
        uint seed0 = hash(hash(pix.x) ^ pix.y);
        float rnd = rand_float(seed0);
        result.rgb += (rnd - 0.5) / 256.0;
    }

    imageStore(outputTex, pix, vec4(result, 1));
}
