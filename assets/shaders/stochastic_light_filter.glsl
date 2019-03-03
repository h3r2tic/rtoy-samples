#include "rendertoy::shaders/random.inc"
#include "inc/uv.inc"
#include "inc/pack_unpack.inc"
#include "inc/math.inc"
#include "inc/brdf.inc"

// TEMP; only for Triangle
#include "rtoy-rt::shaders/rt.inc"

uniform restrict writeonly image2D outputTex;
uniform vec4 outputTex_size;

uniform float g_mouseX;
#define iMouse vec4(g_mouseX, 0, 0, 0)

#define iResolution outputTex_size

uniform sampler2D g_primaryVisTex;
uniform sampler2D g_lightSamplesTex;
uniform sampler2D g_varianceEstimate;

layout(std430) buffer constants {
    mat4 view_to_clip;
    mat4 clip_to_view;
    mat4 world_to_view;
    mat4 view_to_world;
    uint frame_idx;
};

const uint light_count = 3;

Triangle get_light_source(uint idx) {
    Triangle tri;

    float a = float(idx) * TWO_PI / float(light_count) + float(frame_idx) * 0.005 * 0.0;
    vec3 offset = vec3(cos(a), 0.0, sin(a)) * 350.0;
    vec3 side = vec3(-sin(a), 0.0, cos(a)) * 10.0 * sqrt(2.0) / 2.0;
    vec3 up = vec3(0.0, 1.0, 0.0) * 400.0;

    tri.v = offset;
    tri.e0 = side + up;
    tri.e1 = -side + up;

    return tri;
}

const float light_intensity_scale = 50.0 * 3.0 / light_count;

const vec3 light_colors[3] = vec3[](
    mix(vec3(0.7, 0.2, 1), 1.0.xxx, 0.75) * 1.0 * light_intensity_scale,
    mix(vec3(1, 0.5, 0.0), 1.0.xxx, 0.25) * 0.5 * light_intensity_scale,
    mix(vec3(0.2, 0.2, 1), 1.0.xxx, 0.25) * 0.1 * light_intensity_scale
);


// Sorted by distance to center
const vec2 poissonOffsets[16] = vec2[](
    vec2(0.0, 0.0),
    vec2(0.1518793217962363, -0.4039150022001042),
    vec2(-0.48050868974624406, -0.06854120361397874),
    vec2(-0.25236411891373095, 0.4296090204971095),
    vec2(0.5120272111118559, -0.11081946551775732),
    vec2(0.28025639448220807, 0.45628402276197544),
    vec2(-0.2503764251086612, -0.5030819543468117),
    vec2(0.0037964097054232517, -0.9241597866851664),
    vec2(0.9418779871059333, 0.06879617681996429),
    vec2(-0.7533143807237, -0.5820875051377233),
    vec2(-0.6426261012036244, 0.7239260110726607),
    vec2(0.4910447081406396, -0.8434546160724686),
    vec2(0.8261908171981129, 0.5217921615083018),
    vec2(-0.9826672958850468, 0.06512294159950414),
    vec2(0.8664518673756076, -0.48257357628816927),
    vec2(0.06177281215017559, 0.9926963649033903)
);

struct Gbuffer {
    float roughness;
    float metallic;
    vec3 normal;
};

bool unpack_gbuffer(vec4 gbuffer, inout Gbuffer res) {
    if (gbuffer.a != 0) {
        res.normal = unpack_normal_11_10_11(gbuffer.x);
        res.roughness = gbuffer.y;
        res.metallic = gbuffer.z;
        return true;
    } else {
        return false;
    }
}

mat2 rotate2d(float _angle){
    return mat2(cos(_angle),-sin(_angle),
                sin(_angle),cos(_angle));
}

struct SurfaceInfo2 {
    vec3 point;
    vec3 normal;
    vec3 wo;
    float roughness;
    float metallic;
};

void eval_sample(SurfaceInfo2 surface, ivec2 px, int sidx, bool approxVisibility, uint seed, inout int scount, inout vec3 lcol, inout float wsum)
{
    float k = 9.0;

	ivec2 xyoff = ivec2((rotate2d(rand_float(seed) * PI) * poissonOffsets[sidx]) * k);
	//ivec2 xyoff = ivec2(poissonOffsets[sidx] * k);
    //ivec2 xyoff = ivec2((rotate2d(((px.x & 1) + 2 * (px.y & 1)) * 0.3539) * poissonOffsets[sidx]) * k);
	float w = 1.0;

    ivec2 sample_px = ivec2(px) + xyoff;

	vec4 hit_data = texelFetch(g_lightSamplesTex, sample_px, 0);
    vec3 point_on_light;
    vec3 le;
    point_on_light.xy = unpackHalf2x16(floatBitsToUint(hit_data.x));
    point_on_light.z = unpackHalf2x16(floatBitsToUint(hit_data.y)).x;
    le.x = unpackHalf2x16(floatBitsToUint(hit_data.y)).y;
    le.yz = unpackHalf2x16(floatBitsToUint(hit_data.z));
    point_on_light = (view_to_world * vec4(point_on_light, 1)).xyz;

	float lpdf = hit_data.w;
	vec3 hitOffset = point_on_light - surface.point;
	float hitOffsetLenSq = dot(hitOffset, hitOffset);

	// Adjust the PDF of the borrowed sample. It's defined wrt the solid angle
	// of the neighbor. We need to transform it into the solid angle of the current point.
	if (approxVisibility) {
        vec3 neigh_pos;
        vec3 neigh_norm;
        float neigh_roughness;
        {
            vec4 gbuffer_packed = texelFetch(g_primaryVisTex, sample_px, 0);
            vec2 uv = get_uv(sample_px, outputTex_size);

            Gbuffer gbuffer;
            if (!unpack_gbuffer(gbuffer_packed, gbuffer)) {
                w = 0;
                return;
            }

            vec4 ray_origin_cs = vec4(uv_to_cs(uv), gbuffer_packed.w, 1.0);
            vec4 ray_origin_vs = clip_to_view * ray_origin_cs;
            vec4 ray_origin_ws = view_to_world * ray_origin_vs;
            ray_origin_ws /= ray_origin_ws.w;

            neigh_pos = ray_origin_ws.xyz;
            neigh_norm = gbuffer.normal;
            neigh_roughness = gbuffer.roughness;
        }

		lpdf *= hitOffsetLenSq / max(1e-10, dist_squared(neigh_pos, point_on_light));

        float a2 = surface.roughness * surface.roughness;
        float cutoff_threshold = d_ggx(a2, 1.0) * a2;
        float cutoff_value = d_ggx(a2, dot(neigh_norm, surface.normal));
        float roughness_threshold = 0.4;
        float roughness_diff = abs(surface.roughness - neigh_roughness);

        // TODO: depth-based cutoff
        if (cutoff_value < cutoff_threshold || roughness_diff > roughness_threshold)
        {
            lpdf = -1;
        }
	}

	vec3 lightSample = hitOffset / sqrt(hitOffsetLenSq);
	float ndotl = dot(lightSample, surface.normal);

	if (lpdf >= 0.0)
	{
		wsum += w;
	}

	if (lpdf > 0.)
	{
		++scount;

        vec3 microfacet_normal = calculate_microfacet_normal(lightSample, surface.wo);

        BrdfEvalParams brdf_eval_params;
        brdf_eval_params.normal = surface.normal;
        brdf_eval_params.outgoing = surface.wo;
        brdf_eval_params.incident = lightSample;
        brdf_eval_params.microfacet_normal = microfacet_normal;

        GgxParams ggx_params;
        ggx_params.roughness = surface.roughness;

        BrdfEvalResult brdf_result = evaluate_ggx(brdf_eval_params, ggx_params);
        float refl = brdf_result.value;

		vec3 p = vec3(1.0);

        p *= brdf_result.value;
		p /= lpdf;
		p *= saturate(ndotl);

        float schlick = 1.0 - abs(brdf_result.ldotm);
        schlick = schlick * schlick * schlick * schlick * schlick;
        float fresnel = mix(mix(0.04, 1.0, surface.metallic), 1.0, schlick);
        p *= fresnel;

        if (!true) {
            // TEMP: Renormalize; fit by Patapom (https://patapom.com/blog/BRDF/MSBRDFEnergyCompensation/)
            float a = surface.roughness;
            float energy = PI - 0.446898 * a - 5.72019 * a * a + 6.61848 * a * a * a - 2.41727 * a * a * a * a;
            p *= PI / energy;
        }

		//if (p.x > 0.)
		{
			lcol += w * p * le;
		}
	}
}

float calculate_luma(vec3 col) {
	return dot(vec3(0.299, 0.587, 0.114), col);
}

vec4 reconstruct_lighting(SurfaceInfo2 surface, ivec2 px, uint seed)
{
    vec3 lcol = vec3(0);
    vec3 lcol2 = vec3(0);
    float wsum = 0.0;
    
	int scount = 0;

    float variance_estimate = texelFetch(g_varianceEstimate, px, 0).x;
	eval_sample(surface, px, 0, false, seed, scount, lcol, wsum);

    int sample_count = min(int(16 * variance_estimate), 16);
	for (int sidx = 1; sidx < sample_count; ++sidx)
    //for (int sidx = 1; sidx < 16; ++sidx)
    //for (int sidx = 1; sidx < 1; ++sidx)
    {
        vec3 contrib = 0.0.xxx;
        float w = 0.0;
        
		eval_sample(surface, px, sidx, true, seed, scount, contrib, w);

        lcol += contrib;
        lcol2 += contrib * contrib;

        wsum += w;
    }

    float norm_factor = 1.0 / max(1e-5, wsum);

    lcol *= norm_factor;

    //lcol.rgb = variance_estimate.xxx;
    return vec4(lcol, 1.0);
}    

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    vec2 uv = get_uv(outputTex_size);
        
	float seed = 0;
    vec4 finalColor = vec4(0.05.xxx, 0.0);

    float distance_to_surface = 1e10;
    vec4 ray_dir_cs = vec4(uv_to_cs(uv), 0.0, 1.0);
    vec4 ray_dir_ws = view_to_world * (clip_to_view * ray_dir_cs);

    vec4 gbuffer_packed = texelFetch(g_primaryVisTex, pix, 0);

    Gbuffer gbuffer;
    if (unpack_gbuffer(gbuffer_packed, gbuffer)) {
		SurfaceInfo2 surface;// = unpackSurfaceInfo(surfacePckd,  fragCoord);
        {
            vec4 ray_origin_cs = vec4(uv_to_cs(uv), gbuffer_packed.w, 1.0);
            vec4 ray_origin_vs = clip_to_view * ray_origin_cs;
            vec4 ray_origin_ws = view_to_world * ray_origin_vs;
            ray_origin_ws /= ray_origin_ws.w;

            surface.point = ray_origin_ws.xyz;
            surface.normal = gbuffer.normal;
            surface.wo = -normalize(ray_dir_ws.xyz);
            surface.roughness = gbuffer.roughness;
            surface.metallic = gbuffer.metallic;

            vec3 eye_pos = (view_to_world * vec4(0, 0, 0, 1)).xyz;
            distance_to_surface = length(surface.point - eye_pos);
        }

        uint seed0 = hash(frame_idx);
        seed0 = hash(seed0 + 15488981u * uint(pix.x));
        seed0 = seed0 + 1302391u * uint(pix.y);

      	finalColor = reconstruct_lighting(surface, pix, seed0);

        //finalColor.rgb = fract(surface.roughness.xxx);
        //finalColor.rgb = surface.normal * 0.5 + 0.5;
    }

    if (false) {
        vec3 eye_pos = (view_to_world * vec4(0, 0, 0, 1)).xyz;

        Ray r;
        r.o = eye_pos;
        r.d = normalize(ray_dir_ws.xyz);
        vec3 barycentric;

        for (int i = 0; i < light_count; ++i) {
            if (intersect_ray_tri(r, get_light_source(i), distance_to_surface, barycentric)) {
                finalColor.rgb = light_colors[i] * 5.0;
            }
        }
    }

    fragColor = finalColor;
}

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	vec2 fragCoord = vec2(gl_GlobalInvocationID.xy) + 0.5;
	vec4 finalColor;

	mainImage(finalColor, fragCoord);

	finalColor.a = 1.;
    finalColor.rgb *= 0.75;

	imageStore(outputTex, ivec2(gl_GlobalInvocationID.xy), finalColor);
}