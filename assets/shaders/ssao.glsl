#include "rendertoy::shaders/random.inc"
#include "rendertoy::shaders/sampling.inc"
#include "rtoy-rt::shaders/rt.inc"
#include "inc/uv.inc"
#include "inc/pack_unpack.inc"

// TODO: proper constant in a common include file
#define PI 3.14159

uniform sampler2D inputTex;
uniform vec4 inputTex_size;

uniform restrict writeonly image2D outputTex;
uniform vec4 outputTex_size;

layout(std430) buffer constants {
    mat4 view_to_clip;
    mat4 clip_to_view;
    mat4 world_to_view;
    mat4 view_to_world;
    uint frame_idx;
};

Ray offset_ray_origin(Ray r, vec3 v) {
    r.o += (v + r.d) * (1e-4 * length(r.o));
    return r;
}

float fetch_depth(vec2 uv) {
    // TODO: use a slimmed down depth buffer
    return texelFetch(inputTex, ivec2(inputTex_size.xy * uv), 0).w;
}

float integrate_arc(float h1, float h2, float n) {
    float a = -cos(2.0 * h1 - n) + cos(n) + 2.0 * h1 * sin(n);
    float b = -cos(2.0 * h2 - n) + cos(n) + 2.0 * h2 * sin(n);
    return 0.25 * (a + b);
}

float update_horizion_angle(float prev, float new) {
    return new > prev ? max(new, prev) : mix(prev, new, 0.1);
}

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
    ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    vec2 uv = get_uv(outputTex_size);
    vec4 gbuffer = texelFetch(inputTex, pix, 0);
    vec3 normal = unpack_normal_11_10_11(gbuffer.x);
    vec3 normal_vs = normalize((world_to_view * vec4(normal, 0)).xyz);

    //uint seed0 = hash(frame_idx);
    uint seed0 = hash(hash(frame_idx ^ hash(pix.x)) ^ pix.y);
    uint seed1 = hash(seed0);

    vec3 basis0 = normalize(build_orthonormal_basis(normal));
    vec3 basis1 = cross(basis0, normal);
    mat3 basis = mat3(basis0, basis1, normal);

    vec3 col = 0.1.xxx;
    float ao_radius = 20.0;

    if (gbuffer.a != 0.0) {
        vec4 ray_dir_cs = vec4(uv_to_cs(uv), 0.0, 1.0);
        vec4 ray_dir_vs = clip_to_view * ray_dir_cs;
        vec4 ray_dir_ws = view_to_world * ray_dir_vs;

        vec3 v = -normalize(ray_dir_ws.xyz);
        vec3 v_vs = -normalize(ray_dir_vs.xyz);

        vec4 ray_origin_cs = vec4(uv_to_cs(uv), gbuffer.w, 1.0);
        vec4 ray_origin_vs = clip_to_view * ray_origin_cs;
        vec4 ray_origin_ws = view_to_world * ray_origin_vs;
        ray_origin_ws /= ray_origin_ws.w;

#if 0
        vec3 sr = uniform_sample_sphere(vec2(rand_float(seed0), rand_float(seed1)));
        vec3 ao_dir = normal + sr;

        Ray r;
        r.o = ray_origin_ws.xyz;
        r.d = ao_dir;
        r = offset_ray_origin(r, v);

        if (!raytrace_intersects_any(r, ao_radius)) {
            col = 1.0.xxx;
        }
#else
        // TODO: less thrashing
        float ss_angle = rand_float(seed0) * PI;
        float rand_offset = rand_float(seed1);

        vec2 cs_slice_dir = vec2(cos(ss_angle) * inputTex_size.y / inputTex_size.x, sin(ss_angle));

        float ao_radius_shrinkage;
        {
            // Convert AO radius into world scale
            float cs_ao_radius_rescale = ao_radius * view_to_clip[1][1] / (-ray_origin_vs.z / ray_origin_vs.w);
            cs_slice_dir *= cs_ao_radius_rescale;

            // TODO: better units
            // Calculate AO radius shrinkage (if camera is too close to a surface)
            float max_ao_radius_cs = 0.15;
            ao_radius_shrinkage = min(1.0, max_ao_radius_cs / cs_ao_radius_rescale);
        }

        // Shrink the AO radius
        cs_slice_dir *= ao_radius_shrinkage;
        float ao_radius = ao_radius * ao_radius_shrinkage;

        vec3 center_vs = ray_origin_vs.xyz / ray_origin_vs.w;

        const uint half_sample_count = 8;
        cs_slice_dir *= 1.0 / float(half_sample_count);

        float theta_cos_max1 = -1.0;
        float theta_cos_max2 = -1.0;

        //float error = 0.0;

        // TODO: double-check this
        vec2 vs_slice_dir = (vec4(cs_slice_dir, 0, 0) * clip_to_view).xy;
        vec3 slice_normal_vs = normalize(cross(v_vs, vec3(vs_slice_dir, 0)));

        for (uint i = 0; i < half_sample_count; ++i) {
            float wt = float(i) / half_sample_count;
            wt = exp2(-3.0 * wt);

            {
                float t = float(i) + rand_offset;

                vec4 sample_cs = vec4(ray_origin_cs.xy - cs_slice_dir * t, 0, 1);
                sample_cs.z = fetch_depth(cs_to_uv(sample_cs.xy));

                vec4 sample_vs4 = clip_to_view * sample_cs;
                vec3 sample_vs = sample_vs4.xyz / sample_vs4.w;
                vec3 sample_vs_offset = sample_vs - center_vs;
                float sample_vs_offset_len = length(sample_vs_offset);

                //error += abs(dot(normalize(sample_vs_offset), slice_normal_vs));

                float sample_theta_cos = dot(sample_vs_offset, v_vs) / sample_vs_offset_len;
                if (sample_vs_offset_len < ao_radius) {
                    theta_cos_max1 = update_horizion_angle(theta_cos_max1, sample_theta_cos);
                }
            }

            {
                float t = float(i) + (1.0 - rand_offset);

                vec4 sample_cs = vec4(ray_origin_cs.xy + cs_slice_dir * t, 0, 1);
                sample_cs.z = fetch_depth(cs_to_uv(sample_cs.xy));

                vec4 sample_vs4 = clip_to_view * sample_cs;
                vec3 sample_vs = sample_vs4.xyz / sample_vs4.w;
                vec3 sample_vs_offset = sample_vs - center_vs;
                float sample_vs_offset_len = length(sample_vs_offset);
                
                //error += abs(dot(normalize(sample_vs_offset), slice_normal_vs));

                float sample_theta_cos = dot(sample_vs_offset, v_vs) / sample_vs_offset_len;

                if (sample_vs_offset_len < ao_radius) {
                    theta_cos_max2 = update_horizion_angle(theta_cos_max2, sample_theta_cos);
                }
            }
        }

        float h1 = -acos(theta_cos_max1);
        float h2 = +acos(theta_cos_max2);

        vec3 proj_normal_vs = normal_vs - slice_normal_vs * dot(slice_normal_vs, normal_vs);
        float slice_contrib_weight = length(proj_normal_vs);
        proj_normal_vs /= slice_contrib_weight;

        float n_angle = acos(clamp(dot(proj_normal_vs, v_vs), 0.0, 1.0)) * sign(dot(vs_slice_dir, proj_normal_vs.xy - v_vs.xy));

        float h1p = n_angle + max(h1 - n_angle, -PI / 2.0);
        float h2p = n_angle + min(h2 - n_angle, PI / 2.0);

        col = integrate_arc(h1p, h2p, n_angle).xxx * slice_contrib_weight;
        //col = error.xxx * 100000;
#endif
    }

    col *= 0.8;

    imageStore(outputTex, pix, vec4(col, 1));
}
