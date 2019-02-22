#define PI 3.14159
#define TWO_PI 6.28318

struct BrdfSampleParams {
    vec3 outgoing;
    vec2 urand;
};

struct BrdfEvalParams {
    vec3 normal;
    vec3 outgoing;  // "towards light"
    vec3 incident;  // "towards eye"
    vec3 microfacet_normal;
};

vec3 calculate_microfacet_normal(vec3 incident, vec3 outgoing) {
    return normalize(incident + outgoing);
}

struct BrdfEvalResult {
	// Defined wrt the projected solid angle measure (no ndotl)
    float value;
	float value_over_pdf;
	float pdf;
    float ldotm;
};

struct BrdfSampleResult {
    BrdfEvalResult eval;

    vec3 incident;
    float ndotm;
};

struct GgxParams {
    float roughness;
};

float d_ggx(float a2, float ndotm) {
	float denom_sqrt = ndotm * ndotm * (a2 - 1.0) + 1.0;
	return a2 / (PI * denom_sqrt * denom_sqrt);
}

float g_smith_ggx1(float ndotv, float alpha_g)
{
    float tan2_v = (1.0 - ndotv * ndotv) / (ndotv * ndotv);
	return 2.0 / (1.0 + sqrt(1.0 + alpha_g * alpha_g * tan2_v));
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

float g_smith_ggx(float ndotv, float ndotl, float alpha_g)
{
#if 1
	return g_smith_ggx_correlated(ndotl, ndotv, alpha_g);
#else
	return g_smith_ggx1(ndotl, alpha_g) * g_smith_ggx1(ndotv, alpha_g);
#endif 
}

BrdfEvalResult evaluate_ggx(BrdfEvalParams params, GgxParams brdf_params) {
    float a2 = brdf_params.roughness * brdf_params.roughness;
    vec3 m = params.microfacet_normal;

    float ndotv = dot(params.normal, params.outgoing);
    float ndotl = dot(params.normal, params.incident);
    float ndotm = dot(params.normal, m);
    float ldotm = dot(params.incident, m);

    float d_val = d_ggx(a2, ndotm);

	// Change of variables from the half-direction space to regular lighting geometry
	float jacobian = 1.0 / (4.0 * ldotm);

    BrdfEvalResult eval;
	eval.pdf = d_val * ndotm * jacobian;
    eval.value = 1.0
		* d_val
		* g_smith_ggx(ndotv, ndotl, brdf_params.roughness)
		/ (4 * ndotv * ndotl);
	eval.value_over_pdf = 1.0
		/ (ndotm * jacobian)
		* g_smith_ggx(ndotv, ndotl, brdf_params.roughness)
		/ (4 * ndotv * ndotl);

    eval.ldotm = ldotm;

    return eval;
}

bool sample_ggx(BrdfSampleParams params, GgxParams brdf_params, inout BrdfSampleResult res) {
	float a2 = brdf_params.roughness * brdf_params.roughness;

	float cos2_theta = (1 - params.urand.x) / (1 - params.urand.x + a2 * params.urand.x);
	float cos_theta = sqrt(cos2_theta);

	float phi = TWO_PI * params.urand.y;

	float sin_theta = sqrt(max(0.0, 1.0 - cos2_theta));
	vec3 m = vec3(cos(phi) * sin_theta, sin(phi) * sin_theta, cos_theta);
	vec3 l = -params.outgoing + m * dot(params.outgoing, m) * 2.0;

	if (m.z <= 0.0 || l.z <= 0.0 || params.outgoing.z <= 0.0) {
		return false;
	}

    BrdfEvalParams eval_params;
    eval_params.normal = vec3(0, 0, 1);
    eval_params.outgoing = params.outgoing;
    eval_params.incident = l;
    eval_params.microfacet_normal = m;
    res.eval = evaluate_ggx(eval_params, brdf_params);

    res.ndotm = cos_theta;
	res.incident = l;

	return true;
}
