#include "rendertoy::shaders/random.inc"
#include "rendertoy::shaders/sampling.inc"
#include "rtoy-rt::shaders/rt.inc"
#include "inc/uv.inc"
#include "inc/mesh_vertex.inc"
#include "inc/pack_unpack.inc"
#include "inc/brdf.inc"

uniform sampler2D inputTex;

uniform restrict writeonly image2D outputTex;
uniform vec4 outputTex_size;

layout(std430) buffer constants {
    mat4 view_to_clip;
    mat4 clip_to_view;
    mat4 world_to_view;
    mat4 view_to_world;
    uint frame_idx;
};

layout(std430) buffer mesh_vertex_buf {
    VertexPacked vertices[];
};

Triangle get_light_source() {
    float size = 1000.0;
    Triangle tri;
    //tri.v = vec3(-200, 100, -99);
    tri.v = vec3(-200, 200, 0);
    tri.e0 = vec3(0, 0, 1) * size;
    tri.e1 = vec3(0, -1, 0.5) * size;
    return tri;
}

vec3 sample_point_on_triangle(Triangle tri, vec2 urand) {
    return urand.x + urand.y < 1
        ? tri.v + urand.x * tri.e0 + urand.y * tri.e1
        : tri.v + (1-urand.x) * tri.e0 + (1-urand.y) * tri.e1;
}

struct LightSampleResult {
    vec3 pos;
    vec3 normal;
    float pdf;
};

LightSampleResult sample_light(Triangle tri, vec2 urand) {
    vec3 perp = cross(tri.e0, tri.e1);
    float perp_inv_len = 1.0 / sqrt(dot(perp, perp));

    LightSampleResult res;
    res.pos = sample_point_on_triangle(tri, urand);
    res.normal = perp * perp_inv_len;
    res.pdf = 2.0 * perp_inv_len;   // 1.0 / triangle area
    return res;
}

vec3 diffuse_at_point(vec3 pos, vec3 normal, vec3 v) {
    vec3 col = 0.0.xxx;

    vec3 l = normalize(vec3(0.5, 0.3, -0.6));
    float ndotl = max(0.0, dot(l, normal));

    col += ndotl * 20.0;

    return col;
}

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
    ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    vec2 uv = get_uv(outputTex_size);
    vec4 gbuffer = texelFetch(inputTex, pix, 0);

    vec3 normal = unpack_normal_11_10_11(gbuffer.x);
    float roughness = 0.1;//gbuffer.y;
    vec4 col = vec4(0.0.xxx, 1);

    vec3 eye_pos = (view_to_world * vec4(0, 0, 0, 1)).xyz;

    vec4 ray_dir_cs = vec4(uv_to_cs(uv), 0.0, 1.0);
    vec4 ray_dir_ws = view_to_world * (clip_to_view * ray_dir_cs);
    vec3 v = -normalize(ray_dir_ws.xyz);

    const float albedo_scale = 0.04;
    float distance_to_surface = 1e10;

    if (gbuffer.a != 0.0) {
        vec4 ray_origin_cs = vec4(uv_to_cs(uv), gbuffer.w, 1.0);
        vec4 ray_origin_vs = clip_to_view * ray_origin_cs;
        vec4 ray_origin_ws = view_to_world * ray_origin_vs;
        ray_origin_ws /= ray_origin_ws.w;

        distance_to_surface = length(ray_origin_ws.xyz - eye_pos);

        uint seed0 = hash(pix.x);
        seed0 = hash(seed0 ^ pix.y);
        seed0 = seed0 ^ (frame_idx);
        uint seed1 = seed0;

        const uint light_sample_count = 1;

        float reservoir_lpdf = -1.0;
        vec3 reservoir_point_on_light = vec3(0);
        float reservoir_rate_sum = 0.0;
        //float reservoir_emission = 0.0;

        for (uint light_sample_i = 0; light_sample_i < light_sample_count; ++light_sample_i) {
            seed0 = hash(seed1);
            seed1 = hash(seed0);

            vec2 urand = vec2(rand_float(seed0), rand_float(seed1));
            LightSampleResult light_sample = sample_light(get_light_source(), urand);
            vec3 to_light = light_sample.pos - ray_origin_ws.xyz;
            float to_light_sqlen = dot(to_light, to_light);
            vec3 l = to_light / sqrt(to_light_sqlen);
            //float emission = max(0.0, dot(-l, light_sample.normal));

            vec3 microfacet_normal = calculate_microfacet_normal(l, v);

            float bpdf = d_ggx(roughness * roughness, dot(microfacet_normal, normal));

            float vis_term = max(0.0, dot(-l, light_sample.normal)) * max(0.0, dot(normal, l)) / to_light_sqlen;
			float light_sel_rate = bpdf * vis_term;
            //float light_sel_rate = 1.0;
            //float light_sel_rate = max(1e-20, bpdf);

            float light_sel_prob = light_sel_rate / (reservoir_rate_sum + light_sel_rate);
            float light_sel_dart = rand_float(hash(seed0 ^ seed1));

            reservoir_rate_sum += light_sel_rate;

            if (light_sel_prob < light_sel_dart) {
                continue;
            }

            float pdf = light_sample.pdf;

            // Convert from area measure to projected solid angle measure
            pdf /= vis_term;

            reservoir_lpdf = pdf * light_sel_rate;
            reservoir_point_on_light = light_sample.pos;
            //reservoir_emission = emission;
        }
        
        vec3 l = normalize(reservoir_point_on_light - ray_origin_ws.xyz);

        Ray r;
        r.o = ray_origin_ws.xyz + l * (1e-4 * length(ray_origin_ws.xyz));
        r.d = (reservoir_point_on_light - r.o) - l * (1e-4 * length(reservoir_point_on_light));

        if (!raytrace_intersects_any(r))
        {
            vec3 microfacet_normal = calculate_microfacet_normal(l, v);

            BrdfEvalParams brdf_eval_params;
            brdf_eval_params.normal = normal;
            brdf_eval_params.outgoing = v;
            brdf_eval_params.incident = l;
            brdf_eval_params.microfacet_normal = microfacet_normal;

            GgxParams ggx_params;
            ggx_params.roughness = roughness;

            BrdfEvalResult brdf_result = evaluate_ggx(brdf_eval_params, ggx_params);
            float refl = brdf_result.value;
            float pdf = reservoir_lpdf / reservoir_rate_sum;

            if (pdf > 0.0) {
                col.rgb += 1.0
                * 0.5
                //* reservoir_emission
                * refl
                //* max(0.0, dot(normal, l))
                / pdf
                / light_sample_count;
            }
        }

        //col.rgb += 0.01;
    }

    {
        Ray r;
        r.o = eye_pos;
        r.d = -v;
        vec3 barycentric;
        if (intersect_ray_tri(r, get_light_source(), distance_to_surface, barycentric))
        {
            col.rgb = 0.5.xxx;
        }
    }

    imageStore(outputTex, pix, col);
}
