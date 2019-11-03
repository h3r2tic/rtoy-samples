#include "rendertoy::shaders/view_constants.inc"
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
    ViewConstants view_constants;
    uint frame_idx;
};

layout(std430) buffer mesh_vertex_buf {
    VertexPacked vertices[];
};

vec3 sample_environment_light(vec3 dir) {
    dir = normalize(dir);
    vec3 col = (dir.zyx * vec3(1, 1, -1) * 0.5 + vec3(0.6, 0.5, 0.5)) * 0.75;
    col = mix(col, 1.3 * dot(col, vec3(0.2, 0.7, 0.1)).xxx, smoothstep(0.3, 0.8, col.g).xxx);
    return col;
}

vec3 diffuse_at_point(vec3 pos, vec3 normal, vec3 v) {
    vec3 col = 0.0.xxx;

    vec3 l = normalize(vec3(0.5, 0.3, -0.6));
    float ndotl = max(0.0, dot(l, normal));

    if (ndotl > 0.0) {
        Ray sr;
        sr.d = l;
        sr.o = pos.xyz;
        sr.o += (v + sr.d) * (1e-4 * length(sr.o));

        if (!raytrace_intersects_any(sr)) {
            col += ndotl * 20.0;
        }
    }

    col += sample_environment_light(normal);
    return col;
}

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
    ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    vec2 uv = get_uv(outputTex_size);
    vec4 gbuffer = texelFetch(inputTex, pix, 0);

    vec3 normal = unpack_normal_11_10_11(gbuffer.x);
    float roughness = gbuffer.y;
    vec4 col = vec4(0.0.xxx, 1);

    vec4 ray_dir_cs = vec4(uv_to_cs(uv), 0.0, 1.0);
    vec4 ray_dir_ws = view_constants.view_to_world * (view_constants.clip_to_view * ray_dir_cs);
    vec3 v = -normalize(ray_dir_ws.xyz);

    const float albedo_scale = 0.04;

    if (gbuffer.a != 0.0) {
        vec4 ray_origin_cs = vec4(uv_to_cs(uv), gbuffer.w, 1.0);
        vec4 ray_origin_vs = view_constants.clip_to_view * ray_origin_cs;
        vec4 ray_origin_ws = view_constants.view_to_world * ray_origin_vs;
        ray_origin_ws /= ray_origin_ws.w;

        uint seed0 = hash(hash(uint(pix.x) ^ hash(frame_idx)) ^ uint(pix.y));
        uint seed1 = hash(seed0);

        vec3 basis0 = normalize(build_orthonormal_basis(normal));
        vec3 basis1 = cross(basis0, normal);
        mat3 basis = mat3(basis0, basis1, normal);

        BrdfSampleParams brdf_sample_params;
        brdf_sample_params.outgoing = v * basis;
        brdf_sample_params.urand = vec2(rand_float(seed0), rand_float(seed1));

        GgxParams ggx_params;
        ggx_params.roughness = roughness;

        BrdfSampleResult brdf_sample;
        bool is_valid_sample = sample_ggx(brdf_sample_params, ggx_params, brdf_sample);

        //col.rgb += diffuse_at_normal(gbuffer.xyz) * (1.0 - fresnel) * albedo_scale;
        col.rgb += diffuse_at_point(ray_origin_ws.xyz, normal, v) * albedo_scale;

        if (is_valid_sample) {
            Ray r;
            r.d = basis * brdf_sample.incident;
            r.o = ray_origin_ws.xyz;
            r.o += (v + r.d) * (1e-4 * max(length(r.o), abs(ray_origin_vs.z / ray_origin_vs.w)));

            vec3 refl_col;

            RtHit hit;
            hit.t = 1e10;
            if (raytrace(r, hit)) {
                vec3 hit_normal = hit.normal;
                vec3 hit_pos = r.o + r.d * hit.t;
                refl_col = diffuse_at_point(hit_pos, hit_normal, -r.d) * albedo_scale;
            } else {
                refl_col = sample_environment_light(r.d);
            }

            float schlick = 1.0 - abs(brdf_sample.eval.ldotm);
            schlick = schlick * schlick * schlick * schlick * schlick;
            float fresnel = mix(0.04, 1.0, schlick);

            col.rgb += 1.0.xxx
            * refl_col
            * fresnel
            * (brdf_sample.eval.value_over_pdf
            * max(0.0, dot(r.d, normal)));
        }
    } else {
        col.rgb = sample_environment_light(-v);
    }


    imageStore(outputTex, pix, col);
}
