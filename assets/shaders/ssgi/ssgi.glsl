#include "rendertoy::shaders/view_constants.inc"
#include "rendertoy::shaders/random.inc"
#include "rendertoy::shaders/sampling.inc"
#include "rtoy-rt::shaders/rt.inc"
#include "../inc/uv.inc"
#include "../inc/pack_unpack.inc"

// TODO: proper constant in a common include file
#define PI 3.14159265359

uniform sampler2D gbufferTex;
uniform vec4 gbufferTex_size;

uniform sampler2D reprojectedLightingTex;
uniform vec4 reprojectedLightingTex_size;

uniform sampler2D depthTex;
uniform vec4 depthTex_size;
uniform sampler2D normalTex;

uniform restrict writeonly image2D outputTex;
uniform vec4 outputTex_size;

layout(std140) uniform constants {
    ViewConstants view_constants;
    uint frame_idx;
};

const float temporal_rotations[] = {60.0, 300.0, 180.0, 240.0, 120.0, 0.0};
const float temporal_offsets[] = {0.0, 0.5, 0.25, 0.75};

const uint ssgi_half_sample_count = 8;

float fast_sqrt(float x) {
    return uintBitsToFloat(0x1fbd1df5 + (floatBitsToUint(x) >> 1u));
}

// max absolute error 9.0x10^-3
// Eberly's polynomial degree 1 - respect bounds
// 4 VGPR, 12 FR (8 FR, 1 QR), 1 scalar
// input [-1, 1] and output [0, PI]
float fast_acos(float inX) 
{ 
    float x = abs(inX); 
    float res = -0.156583f * x + (PI / 2.0); 
    res *= fast_sqrt(1.0f - x); 
    return (inX >= 0) ? res : PI - res; 
}

Ray offset_ray_origin(Ray r, vec3 v) {
    r.o += (v + r.d) * (1e-3 * length(r.o));
    return r;
}

float fetch_depth(vec2 uv) {
    return texelFetch(depthTex, ivec2(depthTex_size.xy * uv), 0).x;
}

vec3 fetch_lighting(vec2 uv) {
    //return 1.0.xxx;
    return texelFetch(reprojectedLightingTex, ivec2(reprojectedLightingTex_size.xy * uv), 0).xyz;
}

vec3 fetch_normal_vs(vec2 uv) {
    ivec2 pix = ivec2(depthTex_size.xy * uv);
    vec3 normal_vs = texelFetch(normalTex, pix, 0).xyz;
    return normal_vs;
}

float integrate_half_arc(float h1, float n) {
    float a = -cos(2.0 * h1 - n) + cos(n) + 2.0 * h1 * sin(n);
    return 0.25 * a;
}

float integrate_arc(float h1, float h2, float n) {
    float a = -cos(2.0 * h1 - n) + cos(n) + 2.0 * h1 * sin(n);
    float b = -cos(2.0 * h2 - n) + cos(n) + 2.0 * h2 * sin(n);
    return 0.25 * (a + b);
}

float update_horizion_angle(float prev, float new) {
    float t = exp(-0.3 * float(ssgi_half_sample_count));
    return new > prev ? max(new, prev) : mix(prev, new, t);
    //return new > prev ? max(new, prev) : prev;
}

float intersect_dir_plane_onesided(vec3 dir, vec3 normal, vec3 pt) {
    float d = -dot(pt, normal);
    float t = d / max(1e-5, -dot(dir, normal));
    return t;
}

vec3 project_point_on_plane(vec3 point, vec3 normal) {
    return point - normal * dot(point, normal);
}

float process_sample(float intsgn, float n_angle, inout vec3 prev_sample_vs, vec4 sample_cs, vec3 center_vs, vec3 normal_vs, vec3 v_vs, float ao_radius, float theta_cos_max, inout vec4 color_accum) {
    if (sample_cs.z > 0) {
        vec4 sample_vs4 = view_constants.sample_to_view * sample_cs;
        vec3 sample_vs = sample_vs4.xyz / sample_vs4.w;
        vec3 sample_vs_offset = sample_vs - center_vs;
        float sample_vs_offset_len = length(sample_vs_offset);

        float sample_theta_cos = dot(sample_vs_offset, v_vs) / sample_vs_offset_len;
        if (sample_vs_offset_len < ao_radius)
        {
            bool sample_visible = sample_theta_cos >= theta_cos_max;
            float theta_prev = theta_cos_max;
            float theta_delta = theta_cos_max;
            theta_cos_max = update_horizion_angle(theta_cos_max, sample_theta_cos);
            theta_delta = theta_cos_max - theta_delta;

            if (sample_visible) {
                vec3 lighting = fetch_lighting(cs_to_uv(sample_cs.xy));

                vec3 sample_normal_vs = fetch_normal_vs(cs_to_uv(sample_cs.xy));

#if 1
                // TODO: finish the derivations, truncate arc integration angles
                // instead of ad-hoc multiplying by projected arc length
                vec3 p0 = prev_sample_vs * min(1.0, intersect_dir_plane_onesided(
                    prev_sample_vs, normal_vs, center_vs
                ));
                vec3 p1 = prev_sample_vs * min(
                    intersect_dir_plane_onesided(prev_sample_vs, sample_normal_vs, sample_vs),
                    intersect_dir_plane_onesided(prev_sample_vs, normal_vs, center_vs)
                );
                vec3 p2 = sample_vs;

                p0 = project_point_on_plane(normalize(p0 - center_vs), normal_vs);
                p1 = project_point_on_plane(normalize(p1 - center_vs), normal_vs);
                p2 = project_point_on_plane(normalize(p2 - center_vs), normal_vs);

                lighting *= min(1.0, distance(p1, p2) / max(1e-5, distance(p0, p2)));
#endif
#if 1
                n_angle *= -intsgn;

                float h1 = fast_acos(theta_prev);
                float h2 = fast_acos(theta_cos_max);

                float h1p = n_angle + max(h1 - n_angle, -PI / 2.0);
                float h2p = n_angle + min(h2 - n_angle, PI / 2.0);

                float inv_ao =
                    integrate_half_arc(h1p, n_angle) -
                    integrate_half_arc(h2p, n_angle);
                    
                lighting *= inv_ao;
                lighting *= step(0.0, dot(-normalize(sample_vs_offset), sample_normal_vs));
#endif

                color_accum += vec4(lighting, 1.0);
            }
        }

        prev_sample_vs = sample_vs;
    } else {
        // Sky; assume no occlusion
        theta_cos_max = update_horizion_angle(theta_cos_max, -1);
    }

    return theta_cos_max;
}

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
    ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    vec2 uv = get_uv(outputTex_size);
    vec4 gbuffer = texelFetch(gbufferTex, pix*2, 0);
    vec3 normal = unpack_normal_11_10_11(gbuffer.x);
    vec3 normal_vs = normalize((view_constants.world_to_view * vec4(normal, 0)).xyz);

    vec3 basis0 = normalize(build_orthonormal_basis(normal));
    vec3 basis1 = cross(basis0, normal);
    mat3 basis = mat3(basis0, basis1, normal);

    vec4 col = 0.0.xxxx;
    float ao_radius = 80.0;

    if (gbuffer.a != 0.0) {
        vec4 ray_dir_cs = vec4(uv_to_cs(uv), 0.0, 1.0);
        vec4 ray_dir_vs = view_constants.sample_to_view * ray_dir_cs;
        vec4 ray_dir_ws = view_constants.view_to_world * ray_dir_vs;

        vec3 v = -normalize(ray_dir_ws.xyz);
        vec3 v_vs = -normalize(ray_dir_vs.xyz);

        vec4 ray_origin_cs = vec4(uv_to_cs(uv), gbuffer.w, 1.0);
        vec4 ray_origin_vs = view_constants.sample_to_view * ray_origin_cs;
        vec4 ray_origin_ws = view_constants.view_to_world * ray_origin_vs;
        ray_origin_ws /= ray_origin_ws.w;

        float spatial_direction_noise = 1.0 / 16.0 * ((((pix.x + pix.y) & 3) << 2) + (pix.x & 3));
        float temporal_direction_noise = temporal_rotations[frame_idx % 6] / 360.0;
        float spatial_offset_noise = (1.0 / 4.0) * ((pix.y - pix.x) & 3);
        float temporal_offset_noise = temporal_offsets[frame_idx / 6 % 4];

        uint seed0 = hash(hash(frame_idx ^ hash(pix.x)) ^ pix.y);
        spatial_direction_noise += rand_float(seed0) * 0.1;

        float ss_angle = fract(spatial_direction_noise + temporal_direction_noise) * PI;
        float rand_offset = fract(spatial_offset_noise + temporal_offset_noise);

        vec2 cs_slice_dir = vec2(cos(ss_angle) * gbufferTex_size.y / gbufferTex_size.x, sin(ss_angle));

        float ao_radius_shrinkage;
        {
            // Convert AO radius into world scale
            float cs_ao_radius_rescale = ao_radius * view_constants.view_to_clip[1][1] / (-ray_origin_vs.z / ray_origin_vs.w);
            cs_slice_dir *= cs_ao_radius_rescale;

            // TODO: better units (pixels? degrees?)
            // Calculate AO radius shrinkage (if camera is too close to a surface)
            float max_ao_radius_cs = 0.4;
            //float max_ao_radius_cs = 1;
            ao_radius_shrinkage = min(1.0, max_ao_radius_cs / cs_ao_radius_rescale);
        }

        // Shrink the AO radius
        cs_slice_dir *= ao_radius_shrinkage;
        float ao_radius = ao_radius * ao_radius_shrinkage;

        vec3 center_vs = ray_origin_vs.xyz / ray_origin_vs.w;

        cs_slice_dir *= 1.0 / float(ssgi_half_sample_count);
        vec2 vs_slice_dir = (vec4(cs_slice_dir, 0, 0) * view_constants.sample_to_view).xy;
        vec3 slice_normal_vs = normalize(cross(v_vs, vec3(vs_slice_dir, 0)));

        vec3 proj_normal_vs = normal_vs - slice_normal_vs * dot(slice_normal_vs, normal_vs);
        float slice_contrib_weight = length(proj_normal_vs);
        proj_normal_vs /= slice_contrib_weight;

        //vec3 slice_tangent_vs = normalize(cross(slice_normal_vs, v_vs));
        //float n_angle = atan(dot(normal_vs, slice_tangent_vs), dot(normal_vs, v_vs));
        float n_angle = fast_acos(clamp(dot(proj_normal_vs, v_vs), -1.0, 1.0)) * sign(dot(vs_slice_dir, proj_normal_vs.xy - v_vs.xy));

        float theta_cos_max1 = cos(n_angle - PI / 2.0);
        float theta_cos_max2 = cos(n_angle + PI / 2.0);

        vec4 color_accum = 0.0.xxxx;

        vec3 prev_sample0_vs = v_vs;
        vec3 prev_sample1_vs = v_vs;

        for (uint i = 0; i < ssgi_half_sample_count; ++i) {
            {
                float t = float(i) + rand_offset;

                vec4 sample_cs = vec4(ray_origin_cs.xy - cs_slice_dir * t, 0, 1);
                sample_cs.z = fetch_depth(cs_to_uv(sample_cs.xy));

                theta_cos_max1 = process_sample(1, n_angle, prev_sample0_vs, sample_cs, center_vs, normal_vs, v_vs, ao_radius, theta_cos_max1, color_accum);
            }

            {
                float t = float(i) + (1.0 - rand_offset);

                vec4 sample_cs = vec4(ray_origin_cs.xy + cs_slice_dir * t, 0, 1);
                sample_cs.z = fetch_depth(cs_to_uv(sample_cs.xy));

                theta_cos_max2 = process_sample(-1, n_angle, prev_sample1_vs, sample_cs, center_vs, normal_vs, v_vs, ao_radius, theta_cos_max2, color_accum);
            }
        }

        float h1 = -fast_acos(theta_cos_max1);
        float h2 = +fast_acos(theta_cos_max2);

        float h1p = n_angle + max(h1 - n_angle, -PI / 2.0);
        float h2p = n_angle + min(h2 - n_angle, PI / 2.0);

        float inv_ao = integrate_arc(h1p, h2p, n_angle);
        col.a = max(0.0, inv_ao);
        col.rgb = color_accum.rgb;
        col *= slice_contrib_weight;

#if 0
        {
            col.rgb = 0.0.xxx;

            int gi_sample_count = 12;
            float gi_wt_sum = 0.0;

            for (int i = 0; i < gi_sample_count; ++i) {
                uint seed0 = hash(hash((frame_idx + i * 10811) ^ hash(pix.x)) ^ pix.y);
                uint seed1 = hash(seed0);

                vec3 sr = uniform_sample_sphere(vec2(rand_float(seed0), rand_float(seed1)));
                vec3 ao_dir = normalize(normal + sr);

                Ray r;
                r.o = ray_origin_ws.xyz;
                r.d = ao_dir;
                r = offset_ray_origin(r, v);

                RtHit hit;
                hit.t = ao_radius;
                if (raytrace(r, hit)) {
                    vec3 hit_pos_ws = r.o + r.d * hit.t;
                    vec4 hit_pos_vs = view_constants.world_to_view * vec4(hit_pos_ws, 1);
                    vec4 hit_pos_cs = view_constants.view_to_clip * hit_pos_vs;
                    hit_pos_cs /= hit_pos_cs.w;
                    vec2 hit_pos_uv = cs_to_uv(hit_pos_cs.xy);

                    if (hit_pos_uv == clamp(hit_pos_uv, 0.0.xx, 1.0.xx)) {
                        vec4 sample_cs = vec4(hit_pos_cs.xy, 0, 1);
                        sample_cs.z = fetch_depth(hit_pos_uv);
                        vec4 sample_vs = view_constants.clip_to_view * sample_cs;
                        
                        vec3 p0 = hit_pos_vs.xyz / hit_pos_vs.w;
                        vec3 p1 = sample_vs.xyz / sample_vs.w;

                        if (abs(p0.z - p1.z) < 2.0)
                        {
                            col.rgb += fetch_lighting(hit_pos_uv);
                            gi_wt_sum += 1;
                        }
                    }
                }
            }

            col.rgb /= gi_sample_count;
            //col.rgb /= max(1e-5, gi_wt_sum);
        }
#endif
    }

    imageStore(outputTex, pix, col);
}
