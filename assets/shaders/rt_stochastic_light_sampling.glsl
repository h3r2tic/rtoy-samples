#include "rendertoy::shaders/view_constants.inc"
#include "rendertoy::shaders/random.inc"
#include "rendertoy::shaders/sampling.inc"
#include "rtoy-rt::shaders/rt.inc"
#include "inc/uv.inc"
#include "inc/mesh_vertex.inc"
#include "inc/pack_unpack.inc"
#include "inc/brdf.inc"

uniform texture2D inputTex;
uniform texture2D blue_noise_tex;

uniform restrict writeonly image2D outputTex;

layout(std430) buffer constants {
    ViewConstants view_constants;
    uint frame_idx;
};

layout(std430) buffer mesh_vertex_buf {
    VertexPacked vertices[];
};

layout(std140) uniform globals {
    vec4 outputTex_size;
    float time_seconds;
};

struct LightTriangle {
    float data[12];
};

struct LightAliasEntry {
    float prob;
    uint alias;
};

layout(std430) buffer light_triangles_buf {
    LightTriangle light_triangles[];
};

layout(std430) buffer light_alias_buf {
    LightAliasEntry light_alias_table[];
};

layout(std430) buffer light_count_buf {
    uint tri_light_count;
};

const uint light_count = 3;
Triangle get_light_source(uint idx) {
    Triangle tri;

    float a = float(idx) * TWO_PI / float(light_count) + float(time_seconds) * 0.5 + 1.4;
    vec3 offset = vec3(cos(a), 0.0, sin(a)) * 350.0;
    vec3 side = vec3(-sin(a), 0.0, cos(a)) * 10.0 * sqrt(2.0) / 2.0;
    vec3 up = vec3(0.0, 1.0, 0.0) * 400.0;

    tri.v = offset;
    tri.e0 = side + up;
    tri.e1 = -side + up;

    return tri;
}

/*Triangle get_light_source(uint idx) {
    LightTriangle lt = light_triangles[idx];

    Triangle tri;

    vec3 a = vec3(lt.data[0], lt.data[1], lt.data[2]);
    vec3 b = vec3(lt.data[3], lt.data[4], lt.data[5]);
    vec3 c = vec3(lt.data[6], lt.data[7], lt.data[8]);

    tri.v = a;
    tri.e0 = b - a;
    tri.e1 = c - a;

    return tri;
}*/


const float light_intensity_scale = 30.0;
//const float light_intensity_scale = 2.7;// * 3.0 / light_count;

const vec3 light_colors[3] = vec3[](
    mix(vec3(0.7, 0.2, 1), 1.0.xxx, 0.75) * 1.0 * light_intensity_scale,
    mix(vec3(1, 0.5, 0.0), 1.0.xxx, 0.25) * 0.5 * light_intensity_scale,
    mix(vec3(0.2, 0.2, 1), 1.0.xxx, 0.25) * 0.1 * light_intensity_scale
);

float radical_inverse_vdc(uint bits) {
    bits = (bits << 16u) | (bits >> 16u);
    bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
    bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
    bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
    bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
    return float(bits) * 2.3283064365386963e-10; // / 0x100000000
}

float radical_inverse(int n, int base) {
    float val = 0;
    float invBase = 1.0 / base, invBi = invBase;
    while (n > 0) {
        // Compute next digit of radical inverse
        int d_i = (n % base);
        val += d_i * invBi;
        n = int(float(n) * invBase);
        invBi *= invBase;
    }
    return val;
}

vec2 hammersley_2d(uint i, uint N) {
    return vec2((float(i) + 0.5) / float(N), radical_inverse_vdc(i));
}

vec3 sample_point_on_triangle(Triangle tri, vec2 urand) {
    float su0 = sqrt(urand.x);
    float b0 = 1.0 - su0;
    float b1 = urand.y * su0;

    return tri.v + b0 * tri.e0 + b1 * tri.e1;
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

struct AdaptiveLightSamplingGuide {
    vec3 v;
    vec3 pos;
    vec3 normal;
    float roughness2;
};

float eval_adaptive_light_sampling_weight(AdaptiveLightSamplingGuide guide, vec3 point_on_light, int level) {
    vec3 l = normalize(point_on_light - guide.pos);

    vec3 microfacet_normal = calculate_microfacet_normal(l, guide.v);
    // HACK
    float r = min(guide.roughness2 + max(0.0, 0.04 / float(1 << (level * 2))), 1);
    //float r = min(guide.roughness2 * 1.2, 1);
    return d_ggx(r, dot(microfacet_normal, guide.normal)) * max(0.001, dot(l, guide.normal));
}

vec3 sample_point_on_triangle_basu_owen(Triangle tri, float u) {
    vec2 A = vec2(1, 0);
    vec2 B = vec2(0, 1);
    vec2 C = vec2(0, 0);

    uint uf = uint(u * 4294967295.0);           // Convert to fixed point

    for (int i = 0; i < 16; ++i) {            // For each base-4 digit
        uint d = (uf >> (2 * (15 - i))) & 0x3; // Get the digit

        vec2 An, Bn, Cn;
        switch (d) {
        case 0:
            An = (B + C) / 2;
            Bn = (A + C) / 2;
            Cn = (A + B) / 2;
            break;
        case 1:
            An = A;
            Bn = (A + B) / 2;
            Cn = (A + C) / 2;
            break;
        case 2:
            An = (B + A) / 2;
            Bn = B;
            Cn = (B + C) / 2;
            break;
        case 3:
            An = (C + A) / 2;
            Bn = (C + B) / 2;
            Cn = C;
            break;
        }
        A = An;
        B = Bn;
        C = Cn;
    }

    vec2 r = (A + B + C) / 3.0;
    return tri.v + tri.e0 * r.x + tri.e1 * r.y;
}

LightSampleResultAm sample_light_basu_owen(Triangle tri, float urand) {
    vec3 perp = cross(tri.e0, tri.e1);
    float perp_inv_len = 1.0 / sqrt(dot(perp, perp));

    LightSampleResultAm res;
    res.pos = sample_point_on_triangle_basu_owen(tri, urand);
    res.normal = perp * perp_inv_len;
    res.pdf.value = 2.0 * perp_inv_len;   // 1.0 / triangle area
    return res;
}

vec3 sample_point_on_triangle_adaptive(Triangle tri, AdaptiveLightSamplingGuide guide, float u, inout float pdf) {
    vec3 a = tri.v;
    vec3 b = tri.v + tri.e0;
    vec3 c = tri.v + tri.e1;

    pdf = 1.0;

    for (int i = 0; i < 10; ++i) {            // For each base-4 digit
        vec3 p[4] = {
            (a + b + c) / 3.0,
            (a * 2.0 + b * 0.5 + c * 0.5) / 3.0,
            (a * 0.5 + b * 2.0 + c * 0.5) / 3.0,
            (a * 0.5 + b * 0.5 + c * 2.0) / 3.0,
        };

        float w[4] = { 1.0, 1.0, 1.0, 1.0 };

        if (i < 6) {
            for (int j = 0; j < 4; ++j) {
                w[j] = sqrt(eval_adaptive_light_sampling_weight(guide, p[j], i));
            }
        }

        float wsum = w[0] + w[1] + w[2] + w[3];

        u *= wsum;
        vec3 na, nb, nc;

        if (u <= w[0]) {
            u /= w[0];
            pdf *= 4.0 * w[0] / wsum;

            na = (b + c) * 0.5;
            nb = (a + c) * 0.5;
            nc = (a + b) * 0.5;
        } else {
            u -= w[0];

            if (u <= w[1]) {
                u /= w[1];
                pdf *= 4.0 * w[1] / wsum;

                na = a;
                nb = (a + b) * 0.5;
                nc = (a + c) * 0.5;
            } else {
                u -= w[1];

                if (u <= w[2]) {
                    u /= w[2];
                    pdf *= 4.0 * w[2] / wsum;

                    na = (b + a) * 0.5;
                    nb = b;
                    nc = (b + c) * 0.5;
                } else {
                    u -= w[2];
                    u /= w[3];
                    pdf *= 4.0 * w[3] / wsum;

                    na = (c + a) * 0.5;
                    nb = (c + b) * 0.5;
                    nc = c;
                }
            }
        }

        a = na;
        b = nb;
        c = nc;
    }

    return (a + b + c) / 3.0;
}

LightSampleResultAm sample_light_adaptive(Triangle tri, AdaptiveLightSamplingGuide guide, float urand) {
    vec3 perp = cross(tri.e0, tri.e1);
    float perp_inv_len = 1.0 / sqrt(dot(perp, perp));

    float adaptive_pdf = 1.0;

    LightSampleResultAm res;
    res.pos = sample_point_on_triangle_adaptive(tri, guide, urand, adaptive_pdf);
    res.normal = perp * perp_inv_len;
    res.pdf.value = adaptive_pdf * (2.0 * perp_inv_len);   // 1.0 / triangle area
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
    float roughness = gbuffer.y;
    vec4 col = -1.0.xxxx;

    vec3 eye_pos = (view_constants.view_to_world * vec4(0, 0, 0, 1)).xyz;

    vec4 ray_dir_cs = vec4(uv_to_cs(uv), 0.0, 1.0);
    vec4 ray_dir_ws = view_constants.view_to_world * (view_constants.sample_to_view * ray_dir_cs);
    vec3 v = -normalize(ray_dir_ws.xyz);

    float distance_to_surface = 1e10;

    if (gbuffer.a != 0.0) {
        col = 0.0.xxxx;

        vec4 ray_origin_cs = vec4(uv_to_cs(uv), gbuffer.w, 1.0);
        vec4 ray_origin_vs = view_constants.sample_to_view * ray_origin_cs;
        vec4 ray_origin_ws = view_constants.view_to_world * ray_origin_vs;
        ray_origin_ws /= ray_origin_ws.w;

        distance_to_surface = length(ray_origin_ws.xyz - eye_pos);

        uint seed0 = hash(frame_idx);
        seed0 = hash(seed0 + 15488981u * uint(pix.x));
        seed0 = seed0 + 1302391u * uint(pix.y);

#define ADAPTIVE true

        //const uint light_sample_count_sqrt = 1;
        //const uint light_sample_count = light_sample_count_sqrt * light_sample_count_sqrt;
        //const uint light_sample_count = 16;
        //const uint light_sample_count = light_count;
        const uint light_sample_count = ADAPTIVE ? 1 : 16;

        float reservoir_lpdf = -1.0;
        vec3 reservoir_point_on_light = vec3(0);
        float reservoir_rate_sum = 0.0;
        vec3 reservoir_emission = 0.0.xxx;

        vec2 urand_offset = vec2(0.0, 0.0);
        {
            uint seed1 = hash(seed0 + frame_idx);
            uint seed2 = hash(seed1);
            seed0 = hash(seed2);
            urand_offset = vec2(rand_float(seed0), rand_float(seed1));
        }

        for (uint sample_idx = 0; sample_idx < light_sample_count; ++sample_idx) {
        /*for (uint light_sample_y = 0; light_sample_y < light_sample_count_sqrt; ++light_sample_y)
        for (uint light_sample_x = 0; light_sample_x < light_sample_count_sqrt; ++light_sample_x) {
            uint sample_idx = light_sample_y * light_sample_count_sqrt + light_sample_x;*/

#if !ADAPTIVE

#if 0
    uint light_idx = 0;
    float light_sel_dart = 0.9;

            uint seed1 = hash(seed0);
            uint seed2 = hash(seed1);
            seed0 = hash(seed2);
            vec2 urand = vec2(rand_float(seed0), rand_float(seed1));
#elif 0
            //seed0 = hash(frame_idx + hash(light_sample_y * light_sample_count_sqrt + light_sample_x + hash((pix.x & 7) + (pix.y & 7) * 8)));
            seed0 = hash(seed0);
            //seed0 = hash(1348);

        //uint seed0 = hash(frame_idx);
        //seed0 = hash(seed0 + 15488981u * uint(pix.x));
        //seed0 = seed0 + 1302391u * uint(pix.y);

            vec2 urand = fract(urand_offset + vec2(
                float(light_sample_x) / light_sample_count_sqrt,
                float(light_sample_y) / light_sample_count_sqrt
            ));
#elif 0
            seed0 = hash((frame_idx * 3 + 17 * ((pix.x & 7) + (pix.y & 7) * 8)) % 64);
            seed0 = hash(seed0 + sample_idx);
            //seed0 = hash(seed0 + 15488981u * uint(pix.x & 3));
            //seed0 = seed0 + 1302391u * uint(pix.y & 3);

            {
                uint seed0 = hash(frame_idx + sample_idx * 4);
                seed0 = hash(seed0 + 15488981u * uint(pix.x));
                seed0 = seed0 + 1302391u * uint(pix.y);

                uint seed1 = hash(seed0 + sample_idx);
                uint seed2 = hash(seed1);
                urand_offset = vec2(rand_float(seed1), rand_float(seed2));
            }

            uint seed1 = hash(seed0);
            uint seed2 = hash(seed1);

            vec2 urand = fract(vec2(rand_float(seed1), rand_float(seed2)) + urand_offset * 0.25);

        uint seed3 = 0; {
        //seed3 = hash(frame_idx);
        seed3 = hash(seed3 + 15488981u * uint(pix.x));
        seed3 = hash(seed3 + 1302391u * uint(pix.y));
        seed3 = seed3 + sample_idx;
        }

            float light_sel_dart = rand_float(hash(seed0 ^ 9832001));
            light_sel_dart = fract(rand_float(seed3) * 0.05 + light_sel_dart);
            uint light_idx = sample_idx;

#else
            const uint halton_seq_len = 1024;

            uint frame = frame_idx;
            vec4 sample_rot = texelFetch(blue_noise_tex, (pix + 0*ivec2(sample_idx * 31) + 0*ivec2(frame * 91, frame * 71)) & 255, 0);

            int halton_idx = int((sample_idx + frame * light_sample_count) % halton_seq_len) + 1;
            //vec2 urand = hammersley_2d(sample_idx, light_sample_count);
            //vec2 urand = vec2((halton_idx + 0.5) / float(halton_seq_len), radical_inverse_vdc(halton_idx + 1));
            vec2 urand = vec2(radical_inverse(halton_idx, 3), radical_inverse(halton_idx, 5));
            //vec2 urand = vec2(0.3, 0.7) * 1.0;
            float light_sel_dart = radical_inverse_vdc(halton_idx);

            /*if (1 == sample_idx)
            {
                urand = vec2(radical_inverse(halton_idx, 7), radical_inverse(halton_idx, 11));
                light_sel_dart = radical_inverse(halton_idx, 13);
            }*/

//uint light_idx = 0;
//            uint light_idx = sample_idx;
            uint light_idx = min(uint(fract(sample_rot.w + radical_inverse(halton_idx, 7)) * light_count), light_count - 1);

            //urand *= 0.2;
            urand += sample_rot.xy;
            urand = fract(urand);
            //light_sel_dart = fract(light_sel_dart + 0.0 * rand_float(seed0));
            
            //light_sel_dart *= 0.2;
            light_sel_dart += sample_rot.z;
            light_sel_dart = fract(light_sel_dart);
#endif
            #if 0
            LightSampleResultAm light_sample = sample_light(get_light_source(light_idx), urand);
            #else
            LightSampleResultSam light_sample = sample_light_sam(
                ray_origin_ws.xyz, get_light_source(light_idx), urand);
            #endif

#else
        uint frame = frame_idx;
        vec4 sample_rot = texelFetch(blue_noise_tex, (pix + ivec2(frame * 91, frame * 71)) & 255, 0);

        float light_sel_dart = 0.9;
        uint light_idx = 0;
        light_idx = min(uint(fract(sample_rot.y + radical_inverse(int(frame), 3)) * light_count), light_count - 1);

        vec2 urand = sample_rot.xy;
        //LightSampleResultAm light_sample = sample_light(get_light_source(light_idx), urand);

        float u = 0.0;
        //u += radical_inverse_vdc((frame_idx + uint(sample_rot.x * 16)) % 16);
        //u += urand.y * 0.05;
        u += radical_inverse_vdc(frame);
        u += urand.x;
        u = fract(u);

        #if 0
        LightSampleResultAm light_sample = sample_light_basu_owen(get_light_source(light_idx), u);
        #else

        AdaptiveLightSamplingGuide guide;
        guide.v = v;
        guide.pos = ray_origin_ws.xyz;
        guide.normal = normal;
        guide.roughness2 = roughness * roughness;

        LightSampleResultAm light_sample = sample_light_adaptive(get_light_source(light_idx), guide, u);
        #endif
#endif

            vec3 to_light = light_sample.pos - ray_origin_ws.xyz;
            float to_light_sqlen = dot(to_light, to_light);
            vec3 l = to_light / sqrt(to_light_sqlen);

            //vec3 em = 100000.0.xxx;//light_colors[(seed2 % light_count) % 3u] * 50.0 * light_count;
            vec3 em = light_colors[light_idx % 3u] * 50.0 * light_count;

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
            /*float light_sel_dart = rand_float(hash(seed0 ^ 9832001));

            #if 1
            light_sel_dart = fract(rand_float(seed3) * 0.05 + light_sel_dart);
            #endif*/

            reservoir_rate_sum += light_sel_rate;

            if (light_sel_prob > light_sel_dart && lndotl > 0.0) {
                //float pdf = to_projected_solid_angle_measure(light_sample.pdf, ndotl, lndotl, to_light_sqlen);
                float pdf = to_projected_solid_angle_measure(light_sample.pdf, 1.0, lndotl, to_light_sqlen);

                reservoir_lpdf = pdf * light_sel_rate;
                reservoir_point_on_light = light_sample.pos;
                reservoir_emission = em;
            }
        }
        
        if (reservoir_lpdf > 0.0) {
            vec3 l = normalize(reservoir_point_on_light - ray_origin_ws.xyz);

            float ray_bias = 1e-4 * length(ray_origin_ws.xyz);

            Ray r;
            r.o = ray_origin_ws.xyz + l * ray_bias;
            r.d = (reservoir_point_on_light - r.o) - l * ray_bias;

            if (!raytrace_intersects_any(r, 1.0))
            {
                vec3 pt = (view_constants.world_to_view * vec4(reservoir_point_on_light, 1)).xyz;
                vec3 emission = reservoir_emission;
                col.r = uintBitsToFloat(packHalf2x16(pt.xy));
                col.g = uintBitsToFloat(packHalf2x16(vec2(pt.z, emission.x)));
                col.b = uintBitsToFloat(packHalf2x16(emission.yz));
                col.a = reservoir_lpdf / reservoir_rate_sum * light_sample_count;
            }
        }
    }

    imageStore(outputTex, pix, col);
}
