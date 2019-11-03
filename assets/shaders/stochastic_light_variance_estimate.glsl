#include "rendertoy::shaders/view_constants.inc"
#include "inc/uv.inc"
#include "inc/pack_unpack.inc"
#include "inc/math.inc"
#include "inc/brdf.inc"

uniform restrict writeonly image2D outputTex;
uniform vec4 outputTex_size;

uniform sampler2D g_primaryVisTex;
uniform sampler2D inputTex;
uniform sampler2D historyTex;
uniform sampler2D reprojectionTex;

layout(std430) buffer constants {
    ViewConstants view_constants;
    uint frame_idx;
};

struct Gbuffer {
    float roughness;
    vec3 normal;
};

bool unpack_gbuffer(vec4 gbuffer, inout Gbuffer res) {
    if (gbuffer.a != 0) {
        res.normal = unpack_normal_11_10_11(gbuffer.x);
        res.roughness = gbuffer.y;
        return true;
    } else {
        return false;
    }
}

struct SurfaceInfo2 {
    vec3 point;
    vec3 normal;
    vec3 wo;
    float roughness;
};

vec3 eval_sample(SurfaceInfo2 surface, ivec2 px)
{
	vec4 hit_data = texelFetch(inputTex, px, 0);
    vec3 point_on_light;
    vec3 le;

    point_on_light.xy = unpackHalf2x16(floatBitsToUint(hit_data.x));
    point_on_light.z = unpackHalf2x16(floatBitsToUint(hit_data.y)).x;
    le.x = unpackHalf2x16(floatBitsToUint(hit_data.y)).y;
    le.yz = unpackHalf2x16(floatBitsToUint(hit_data.z));
    point_on_light = (view_constants.view_to_world * vec4(point_on_light, 1)).xyz;

	float lpdf = hit_data.w;
	vec3 hitOffset = point_on_light - surface.point;
	float hitOffsetLenSq = dot(hitOffset, hitOffset);

	vec3 lightSample = hitOffset / sqrt(hitOffsetLenSq);
	float ndotl = dot(lightSample, surface.normal);

	if (lpdf > 0.)
	{
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

        return p;
	} else {
        return 0.0.xxx;
    }
}

float calculate_luma(vec3 col) {
	return dot(vec3(0.299, 0.587, 0.114), col);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    vec2 uv = get_uv(outputTex_size);
        
    vec4 contrib = vec4(0.0);

    float distance_to_surface = 1e10;
    vec4 ray_dir_cs = vec4(uv_to_cs(uv), 0.0, 1.0);
    vec4 ray_dir_ws = view_constants.view_to_world * (view_constants.clip_to_view * ray_dir_cs);

    vec4 gbuffer_packed = texelFetch(g_primaryVisTex, pix, 0);

    Gbuffer gbuffer;
    if (unpack_gbuffer(gbuffer_packed, gbuffer)) {
		SurfaceInfo2 surface;// = unpackSurfaceInfo(surfacePckd,  fragCoord);
        {
            vec4 ray_origin_cs = vec4(uv_to_cs(uv), gbuffer_packed.w, 1.0);
            vec4 ray_origin_vs = view_constants.clip_to_view * ray_origin_cs;
            vec4 ray_origin_ws = view_constants.view_to_world * ray_origin_vs;
            ray_origin_ws /= ray_origin_ws.w;

            surface.point = ray_origin_ws.xyz;
            surface.normal = gbuffer.normal;
            surface.wo = -normalize(ray_dir_ws.xyz);
            surface.roughness = gbuffer.roughness;

            vec3 eye_pos = (view_constants.view_to_world * vec4(0, 0, 0, 1)).xyz;
            distance_to_surface = length(surface.point - eye_pos);
        }

        vec4 reproj = texelFetch(reprojectionTex, pix, 0);
        vec4 history = textureLod(historyTex, uv + reproj.xy, 0);

        float ex = calculate_luma(eval_sample(surface, pix));
        float ex2 = ex * ex;

        float validity = reproj.z * smoothstep(0.1, 0.0, length(reproj.xy));
        float blend = mix(1.0, 0.333, validity);
        ex = mix(history.y, ex, blend);
        ex2 = mix(history.z * history.z, ex2, blend);

        float var = ex2 - ex * ex;
        float dev = sqrt(max(0.0, var));
        float luma_dev = dev / max(1e-5, ex);

        luma_dev = mix(1.0, luma_dev, validity);
        /*if (!(luma_dev >= 0.0)) {
            luma_dev = 1.0;
        }*/

        vec4 result = vec4(clamp(luma_dev, 0.0, 1.0), ex, sqrt(ex2), 0.0);
        fragColor = result;
    } else {
        fragColor = 0.0.xxxx;
    }
}

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	vec2 fragCoord = vec2(gl_GlobalInvocationID.xy) + 0.5;
	vec4 finalColor;

	mainImage(finalColor, fragCoord);

	imageStore(outputTex, ivec2(gl_GlobalInvocationID.xy), finalColor);
}