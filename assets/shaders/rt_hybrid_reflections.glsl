#include "rendertoy::shaders/random.inc"
#include "rendertoy::shaders/sampling.inc"
#include "rtoy-rt::shaders/rt.inc"
#include "inc/uv.inc"
#include "inc/mesh_vertex.inc"

#define PI 3.14159
#define TWO_PI 6.28318

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

vec3 diffuse_at_normal(vec3 n) {
    return 0.3 + max(0.0, dot(n, normalize(vec3(1, 1, -1)))).xxx;
}

struct BrdfSampleParams {
    vec3 prev_dir;
    vec2 urand;
};

struct BrdfEvalResult {
	// Defined wrt the projected solid angle measure.
	float value_over_pdf;
	float pdf;

    vec3 direction;
};

vec3 brdf_value(BrdfEvalResult e) {
    return e.value_over_pdf * e.pdf;
}

struct GgxParams {
    float roughness;
};

float ggx(float a2, float ndotm) {
	float denom_sqrt = ndotm * ndotm * (a2 - 1.0) + 1.0;
	return a2 / (PI * denom_sqrt * denom_sqrt);
}

float g_smith_ggx1(float ndotv, float alpha_g)
{
	return 2.0 / (1.0 + sqrt(alpha_g * alpha_g * (1.0 - ndotv * ndotv) / (ndotv * ndotv) + 1.0));
}

float g_smith_ggx_correlated(float ndotv, float ndotl, float alpha_g)
{
	float alpha_g2 = alpha_g * alpha_g;
	float ndotl2 = ndotl * ndotl;
	float ndotv2 = ndotv * ndotv;

	float lambda_v = ndotl * sqrt((-ndotv * alpha_g2 + ndotv) * ndotv + alpha_g2);
	float lambda_l = ndotv * sqrt((-ndotl * alpha_g2 + ndotl) * ndotl + alpha_g2);

	return 2.0 * ndotl * ndotv / (lambda_v + lambda_l);
}

float g_smith_ggx(float ndotl, float ndotv, float alpha_g)
{
#if 1
	return g_smith_ggx_correlated(ndotl, ndotv, alpha_g);
#else
	return g_smith_ggx1(ndotl, alpha_g) * g_smith_ggx1(ndotv, alpha_g);
#endif 
}

bool sample_ggx(BrdfSampleParams params, GgxParams brdf_params, inout BrdfEvalResult res) {
	float a2 = brdf_params.roughness * brdf_params.roughness;

	float cos2_theta = (1 - params.urand.x) / (1 - params.urand.x + a2 * params.urand.x);
	float cos_theta = sqrt(cos2_theta);

	float phi = TWO_PI * params.urand.y;

	float sin_theta = sqrt(max(0.0, 1.0 - cos2_theta));
	vec3 m = vec3(cos(phi) * sin_theta, sin(phi) * sin_theta, cos_theta);
	vec3 l = -params.prev_dir + m * dot(params.prev_dir, m) * 2.0;

	if (m.z <= 0.0 || l.z <= 0.0 || params.prev_dir.z <= 0.0) {
		return false;
	}

	float pdf_h = ggx(a2, cos_theta) * cos_theta;

	// Change of variables from the half-direction space to regular lighting geometry.
	float jacobian = 1.0 / (4.0 * dot(l, m));

	res.pdf = pdf_h * jacobian / l.z;
	res.value_over_pdf =
		1.0
		/ (cos_theta * jacobian)
		*	g_smith_ggx(params.prev_dir.z, l.z, brdf_params.roughness)
		/ (4 * params.prev_dir.z);
	res.direction = l;

	return true;
}

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
    ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    vec2 uv = get_uv(outputTex_size);
    vec4 gbuffer = texelFetch(inputTex, pix, 0);

    vec3 normal = gbuffer.xyz;
    vec4 col = vec4(0.0.xxx, 1);

    vec4 ray_dir_cs = vec4(uv_to_cs(uv), 0.0, 1.0);
    vec4 ray_dir_ws = view_to_world * (clip_to_view * ray_dir_cs);
    vec3 v = -normalize(ray_dir_ws.xyz);

    const float albedo_scale = 0.04;

    if (gbuffer.a != 0.0) {
        vec4 ray_origin_cs = vec4(uv_to_cs(uv), gbuffer.w, 1.0);
        vec4 ray_origin_vs = clip_to_view * ray_origin_cs;
        vec4 ray_origin_ws = view_to_world * ray_origin_vs;
        ray_origin_ws /= ray_origin_ws.w;

        float ndotv = dot(normal, v);

        uint seed0 = hash(hash(uint(pix.x) ^ hash(frame_idx)) ^ uint(pix.y));
        uint seed1 = hash(seed0);

        vec3 basis0 = normalize(build_orthonormal_basis(normal));
        vec3 basis1 = cross(basis0, normal);
        mat3 basis = mat3(basis0, basis1, normal);

        BrdfSampleParams brdf_sample_params;
        brdf_sample_params.prev_dir = v * basis;
        brdf_sample_params.urand = vec2(rand_float(seed0), rand_float(seed1));

        GgxParams ggx_params;
        //ggx_params.roughness = 1e-3;
        ggx_params.roughness = 0.1;

        BrdfEvalResult brdf_sample;
        bool valid_sample = sample_ggx(brdf_sample_params, ggx_params, brdf_sample);

        //col.rgb += diffuse_at_normal(gbuffer.xyz) * (1.0 - fresnel) * albedo_scale;
        col.rgb += diffuse_at_normal(gbuffer.xyz) * albedo_scale;

        if (valid_sample) {
            Ray r;
            //r.d = reflect(-v, normal);
            r.d = basis * brdf_sample.direction;
            r.o = ray_origin_ws.xyz;
            r.o += (v + r.d) * (1e-4 * max(length(r.o), abs(ray_origin_vs.z / ray_origin_vs.w)));

            vec3 refl_col = r.d * 0.5 + 0.5;

            RtHit hit;
            if (raytrace(r, hit)) {
                Triangle tri = unpack_triangle(bvh_triangles[hit.tri_idx]);
                vec3 hit_normal = normalize(cross(tri.e0, tri.e1));
                refl_col = diffuse_at_normal(hit_normal) * albedo_scale;
            }

            vec3 m = normalize(r.d + v);
            float schlick = 1.0 - abs(dot(m, v));
            //float schlick = 1.0 - abs(ndotv);
            schlick *= schlick * schlick * schlick * schlick;
            float fresnel = mix(0.04, 1.0, schlick);

            col.rgb += refl_col * fresnel;
        }
    } else {
        col.rgb = -v * 0.5 + 0.5;
    }

    imageStore(outputTex, pix, col);
}
