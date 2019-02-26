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

const uint light_count = 3;
const float light_size_scale = 0;//3.0 / float(light_count);
const float light_size_bias = 1.0;

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

Triangle get_light_source(uint idx) {
    Triangle tri;

    float smult = pow(sin(frame_idx * 0.008) * 0.45 + 0.55, 2.0) * 15.0 * light_size_scale + light_size_bias;

    float a = float(idx) * TWO_PI / float(light_count) + float(frame_idx) * 0.01;
    vec3 offset = vec3(cos(a), -0.4, sin(a)) * 350.0;
    vec3 side = vec3(-sin(a), 0.0, cos(a)) * 30.0 * smult;
    vec3 up = vec3(0.0, 1.0, 0.0) * 30.0 * smult;

    tri.v = offset;
    tri.e0 = side + up;
    tri.e1 = -side + up;

    return tri;
}

const vec3 light_colors[3] = vec3[](
    vec3(0.7, 0.2, 1),
    vec3(1, 0.5, 0.0),
    vec3(0.2, 0.2, 1)
);

vec3 sample_point_on_triangle(Triangle tri, vec2 urand) {
    return urand.x + urand.y < 1
        ? tri.v + urand.x * tri.e0 + urand.y * tri.e1
        : tri.v + (1-urand.x) * tri.e0 + (1-urand.y) * tri.e1;
}

// Solid angle measure
struct PdfSam {
    float value;
};

struct PdfAm {
    float value;
};

float to_projected_solid_angle_measure(PdfAm pdf, float ndotl, float lndotl, float sqdist) {
    return pdf.value * sqdist / ndotl / lndotl;
}

float to_projected_solid_angle_measure(PdfSam pdf, float ndotl, float lndotl, float sqdist) {
    return pdf.value / ndotl;
}

struct LightSampleResultAm {
    vec3 pos;
    vec3 normal;
    PdfAm pdf;
};

struct LightSampleResultSam {
    vec3 pos;
    vec3 normal;
    PdfSam pdf;
};

LightSampleResultAm sample_light(Triangle tri, vec2 urand) {
    vec3 perp = cross(tri.e0, tri.e1);
    float perp_inv_len = 1.0 / sqrt(dot(perp, perp));

    LightSampleResultAm res;
    res.pos = sample_point_on_triangle(tri, urand);
    res.normal = perp * perp_inv_len;
    res.pdf.value = 2.0 * perp_inv_len;   // 1.0 / triangle area
    return res;
}

vec3 intersect_ray_plane(vec3 normal, vec3 plane_pt, vec3 o, vec3 dir) {
    return o - dir * (dot(o - plane_pt, normal) / dot(dir, normal));
}

// Based on "The Solid Angle of a Plane Triangle" by Oosterom and Strackee
float spherical_triangle_area(vec3 a, vec3 b, vec3 c) {
    float numer = abs(dot(a, cross(b, c)));
    float denom = 1.0 + dot(a, b) + dot(a, c) + dot(b, c);
    return atan(numer, denom) * 2.0;
}

// Based on "Sampling for Triangular Luminaire", Graphics Gems III p312
// https://github.com/erich666/GraphicsGems/blob/master/gemsiii/luminaire/triangle_luminaire.C
LightSampleResultSam sample_light_sam(vec3 pt, Triangle tri, vec2 urand) {
    vec3 normal = normalize(cross(tri.e0, tri.e1));

    vec3 p1_sph = normalize(tri.v - pt);
    vec3 p2_sph = normalize(tri.v + tri.e0 - pt);
    vec3 p3_sph = normalize(tri.v + tri.e1 - pt);

    vec2 uv = vec2(1.0 - sqrt(1.0 - urand.x), urand.y * sqrt(1.0 - urand.x));
    vec3 x_sph = p1_sph + uv.x * (p2_sph - p1_sph) + uv.y * (p3_sph - p1_sph);

    float sample_sqdist = dot(x_sph, x_sph);

    vec3 x_ = intersect_ray_plane(normal, tri.v, pt, x_sph);

    vec3 proj_tri_norm = cross(p2_sph - p1_sph, p3_sph - p1_sph);
    float area = 0.5 * sqrt(dot(proj_tri_norm, proj_tri_norm));
    proj_tri_norm /= sqrt(dot(proj_tri_norm, proj_tri_norm));

    float l2ndotl = -dot(proj_tri_norm, x_sph) / sqrt(sample_sqdist);

    LightSampleResultSam res;
    res.pos = x_;
    res.normal = normal;
    res.pdf.value = sample_sqdist / (l2ndotl * area);

    return res;
}

vec3 diffuse_at_point(vec3 pos, vec3 normal, vec3 v) {
    vec3 col = 0.0.xxx;

    vec3 l = normalize(vec3(0.5, 0.3, -0.6));
    float ndotl = max(0.0, dot(l, normal));

    col += ndotl * 20.0;

    return col;
}

float calculate_luma(vec3 col) {
	return dot(vec3(0.299, 0.587, 0.114), col);
}

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
    ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    vec2 uv = get_uv(outputTex_size);
    vec4 gbuffer = texelFetch(inputTex, pix, 0);

    vec3 normal = unpack_normal_11_10_11(gbuffer.x);
    float roughness = 0.08;//gbuffer.y;
    vec4 col = -1.0.xxxx;

    vec3 eye_pos = (view_to_world * vec4(0, 0, 0, 1)).xyz;

    vec4 ray_dir_cs = vec4(uv_to_cs(uv), 0.0, 1.0);
    vec4 ray_dir_ws = view_to_world * (clip_to_view * ray_dir_cs);
    vec3 v = -normalize(ray_dir_ws.xyz);

    float distance_to_surface = 1e10;

    if (gbuffer.a != 0.0) {
        col = 0.0.xxxx;

        vec4 ray_origin_cs = vec4(uv_to_cs(uv), gbuffer.w, 1.0);
        vec4 ray_origin_vs = clip_to_view * ray_origin_cs;
        vec4 ray_origin_ws = view_to_world * ray_origin_vs;
        ray_origin_ws /= ray_origin_ws.w;

        distance_to_surface = length(ray_origin_ws.xyz - eye_pos);

        uint seed0 = hash(frame_idx);
        seed0 = hash(seed0 + 15488981u * uint(pix.x));
        seed0 = seed0 + 1302391u * uint(pix.y);

        const uint light_sample_count = 32;

        float reservoir_lpdf = -1.0;
        vec3 reservoir_point_on_light = vec3(0);
        float reservoir_rate_sum = 0.0;
        vec3 reservoir_emission = 0.0.xxx;

        for (uint light_sample_i = 0; light_sample_i < light_sample_count; ++light_sample_i) {
            uint seed1 = hash(seed0);
            uint seed2 = hash(seed1);
            seed0 = hash(seed2);

            vec2 urand = vec2(rand_float(seed0), rand_float(seed1));
            
            #if 0
            LightSampleResultAm light_sample = sample_light(get_light_source(seed2 % light_count), urand);
            #else
            LightSampleResultSam light_sample = sample_light_sam(ray_origin_ws.xyz, get_light_source(seed2 % light_count), urand);
            #endif

            vec3 to_light = light_sample.pos - ray_origin_ws.xyz;
            float to_light_sqlen = dot(to_light, to_light);
            vec3 l = to_light / sqrt(to_light_sqlen);

            float smult = pow(sin(frame_idx * 0.008) * 0.45 + 0.55, 2.0) * 15.0 * light_size_scale + light_size_bias;
            float intens = 150.0 / pow(smult, 2.0);
            vec3 em = light_colors[(seed2 % light_count) % 3u] * 15.0 * intens;

            vec3 microfacet_normal = calculate_microfacet_normal(l, v);

            float bpdf = d_ggx(roughness * roughness, dot(microfacet_normal, normal));

            float ndotl = max(0.0, dot(normal, l));
            float lndotl = max(0.0, dot(-l, light_sample.normal));
            
            float vis_term = ndotl * lndotl / to_light_sqlen;
            //float light_sel_rate = bpdf;
			float light_sel_rate = bpdf * vis_term * calculate_luma(em);
            //float light_sel_rate = 1.0;
            //float light_sel_rate = max(1e-20, bpdf);
            //float light_sel_rate = max(1.0, bpdf);

            // TODO: why does this produce more stable results?
            light_sel_rate = sqrt(light_sel_rate);

            float light_sel_prob = light_sel_rate / (reservoir_rate_sum + light_sel_rate);
            float light_sel_dart = rand_float(hash(seed0 ^ seed1));

            reservoir_rate_sum += light_sel_rate;

            if (light_sel_prob < light_sel_dart || lndotl <= 0.0) {
                continue;
            }

            //float pdf = to_projected_solid_angle_measure(light_sample.pdf, ndotl, lndotl, to_light_sqlen);
            float pdf = to_projected_solid_angle_measure(light_sample.pdf, 1.0, lndotl, to_light_sqlen);

            reservoir_lpdf = pdf * light_sel_rate;
            reservoir_point_on_light = light_sample.pos;
            reservoir_emission = em;
        }
        
        if (reservoir_lpdf > 0.0) {
            vec3 l = normalize(reservoir_point_on_light - ray_origin_ws.xyz);

            Ray r;
            r.o = ray_origin_ws.xyz + l * (1e-4 * length(ray_origin_ws.xyz));
            r.d = (reservoir_point_on_light - r.o) - l * (1e-4 * length(reservoir_point_on_light));

            if (!raytrace_intersects_any(r, 1.0))
            {
                vec3 pt = (world_to_view * vec4(reservoir_point_on_light, 1)).xyz;
                vec3 emission = reservoir_emission;
                col.r = uintBitsToFloat(packHalf2x16(pt.xy));
                col.g = uintBitsToFloat(packHalf2x16(vec2(pt.z, emission.x)));
                col.b = uintBitsToFloat(packHalf2x16(emission.yz));
                col.a = reservoir_lpdf / reservoir_rate_sum * light_sample_count;
                //col = vec4(pt, reservoir_lpdf / reservoir_rate_sum * light_sample_count);
            }
        }
    }

    imageStore(outputTex, pix, col);
}
