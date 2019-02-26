#include "rendertoy::shaders/random.inc"
#include "inc/uv.inc"
#include "inc/pack_unpack.inc"
#include "inc/math.inc"
#include "inc/brdf.inc"

uniform restrict writeonly image2D outputTex;
uniform vec4 outputTex_size;

uniform float g_mouseX;
#define iMouse vec4(g_mouseX, 0, 0, 0)

#define iResolution outputTex_size

uniform sampler2D g_primaryVisTex;
uniform sampler2D g_lightSamplesTex;

uniform uint g_frameIndex;

layout(std430) buffer constants {
    mat4 view_to_clip;
    mat4 clip_to_view;
    mat4 world_to_view;
    mat4 view_to_world;
    uint frame_idx;
};

#if 1
const vec2 poissonOffsets[16] = vec2[](
    vec2(0.0f, 0.0f),
    vec2(0.06177281215017559f, 0.9926963649033903f),
    vec2(-0.9826672958850468f, 0.06512294159950414f),
    vec2(0.8664518673756076f, -0.48257357628816927f),
    vec2(0.0037964097054232517f, -0.9241597866851664f),
    vec2(0.8261908171981129f, 0.5217921615083018f),
    vec2(-0.6426261012036244f, 0.7239260110726607f),
    vec2(-0.7533143807237f, -0.5820875051377233f),
    vec2(0.5120272111118559f, -0.11081946551775732f),
    vec2(0.28025639448220807f, 0.45628402276197544f),
    vec2(-0.2503764251086612f, -0.5030819543468117f),
    vec2(0.9418779871059333f, 0.06879617681996429f),
    vec2(-0.25236411891373095f, 0.4296090204971095f),
    vec2(-0.48050868974624406f, -0.06854120361397874f),
    vec2(0.4910447081406396f, -0.8434546160724686f),
    vec2(0.1518793217962363f, -0.40391500220010423f)
);
#else
const vec2 poissonOffsets[32] = vec2[](
    vec2(0.0f, 0.0f),
    vec2(-0.9135136592216178f, -0.40462640701835195f),
    vec2(0.082167225654306f, 0.980453017993303f),
    vec2(0.0721876140306982f, -0.9945465264125127f),
    vec2(0.9752658681929658f, -0.21056028303849572f),
    vec2(-0.7624083502300749f, 0.6404811449040694f),
    vec2(0.8305562106591965f, 0.5558133679523944f),
    vec2(0.4879528508829686f, -0.49916506376489883f),
    vec2(-0.3378654109721166f, -0.5580551154567451f),
    vec2(-0.5626647624924962f, -0.0033572372653002283f),
    vec2(0.30261393847514306f, 0.4682954578988519f),
    vec2(0.5521055408091617f, 0.04806767993661225f),
    vec2(-0.11066519414731835f, 0.5221220330664509f),
    vec2(0.10316202363615408f, -0.41685718418903095f),
    vec2(-0.36318095192575917f, 0.8589552754682322f),
    vec2(-0.9683057185504641f, 0.16482264428421214f),
    vec2(-0.45610322605475107f, 0.4070447233948135f),
    vec2(0.4934005858104175f, 0.8485539011139696f),
    vec2(0.9552155171421254f, 0.18143592265706823f),
    vec2(-0.3293469161752369f, -0.9136951084651815f),
    vec2(0.3494539960865413f, -0.8319063858893272f),
    vec2(0.616075913899782f, 0.3476312772330385f),
    vec2(-0.2861479029680008f, -0.23010553043954424f),
    vec2(0.3120249999841332f, -0.12208179967965951f),
    vec2(0.8388781829227475f, -0.5256032052802209f),
    vec2(-0.6309926114050529f, -0.746963777599633f),
    vec2(-0.584692585892695f, -0.33884453413279914f),
    vec2(-0.060330027511877625f, -0.707601265763343f),
    vec2(-0.19914839439519164f, 0.19243890589468077f),
    vec2(-0.815199930667029f, 0.3759363252279692f),
    vec2(-0.8920618153449156f, -0.12331721138773649f),
    vec2(0.21366746949323107f, 0.17085573918730404f)
);
#endif

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

mat2 rotate2d(float _angle){
    return mat2(cos(_angle),-sin(_angle),
                sin(_angle),cos(_angle));
}

struct SurfaceInfo2 {
    vec3 point;
    vec3 normal;
    vec3 wo;
    float roughness;
};

void eval_sample(SurfaceInfo2 surface, ivec2 px, int sidx, bool approxVisibility, uint seed, inout int scount, inout vec3 lcol, inout float wsum)
{
    float k = 8.0;

	//ivec2 xyoff = ivec2((rotate2d(rand_float(seed) * PI) * poissonOffsets[sidx]) * k);
	//ivec2 xyoff = ivec2(poissonOffsets[sidx] * k);
    ivec2 xyoff = ivec2((rotate2d(((px.x & 1) + 2 * (px.y & 1)) * 0.3539) * poissonOffsets[sidx]) * k);
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
        vec3 neighPoint;
        vec3 neighNorm;
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

            neighPoint = ray_origin_ws.xyz;
            neighNorm = gbuffer.normal;
        }

		lpdf *= hitOffsetLenSq / max(1e-10, dist_squared(neighPoint, point_on_light));

        float a2 = surface.roughness * surface.roughness;
        float cutoff_threshold = d_ggx(a2, 1.0) * 0.8;
        float cutoff_value = d_ggx(a2, dot(neighNorm, surface.normal));

        if (cutoff_value < cutoff_threshold)
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

        {
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

vec4 reconstruct_lighting(SurfaceInfo2 surface, ivec2 px, uint seed)
{
    vec3 lcol = vec3(0);
    float wsum = 0.0;
    
	int scount = 0;

	eval_sample(surface, px, 0, false, seed, scount, lcol, wsum);
    
	for (int sidx = 1; sidx < 16; ++sidx)
    //for (int sidx = 1; sidx < 32; ++sidx)
    //for (int sidx = 1; sidx < 1; ++sidx)
    {
		eval_sample(surface, px, sidx, true, seed, scount, lcol, wsum);
    }

    return vec4(lcol / max(1e-5, wsum), 1.0);
}    


void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    vec2 uv = get_uv(outputTex_size);
        
    // ----------------------------------
    // SAMPLING 
    
#if 0
	uint useed = bobJenkinsHash(ivec3(ivec2(fragCoord) >> 1, g_frameIndex));
    float seed = uintToUniformFloat(useed);
#elif 0
    float seed = g_frameIndex + hash12(uv);
#else
	float seed = 0;
#endif
    //float seed = float(floor(float(g_frameIndex)/10.));
    
    // ----------------------------------
    // FINAL GATHER 

    vec4 finalColor = vec4(0.);
    
    if (g_frameIndex > 0)
    {
        //finalColor = texture(iChannel2, uv);
    }
    
    //if (g_frameIndex < 0.5)
    {
	    //RaySampleInfo currSample = setup_cameraRay(fragCoord, vec2(0));
        //RaySampleInfo currSample = setup_cameraRay(vec2(0));
    
        vec4 contrib = vec4(0);

        // hacky hack!
		// already accounted for in filter_surface
        /*if (MATCHES_ID(surface.id, LIGHT_ID))
        {
            contrib.rgb += calc_light_emission(surface.point) * 0.07;
        }*/

        vec4 gbuffer_packed = texelFetch(g_primaryVisTex, pix, 0);

        Gbuffer gbuffer;
        if (unpack_gbuffer(gbuffer_packed, gbuffer)) {
    		SurfaceInfo2 surface;// = unpackSurfaceInfo(surfacePckd,  fragCoord);
            {
                vec4 ray_origin_cs = vec4(uv_to_cs(uv), gbuffer_packed.w, 1.0);
                vec4 ray_origin_vs = clip_to_view * ray_origin_cs;
                vec4 ray_origin_ws = view_to_world * ray_origin_vs;
                ray_origin_ws /= ray_origin_ws.w;

                vec4 ray_dir_cs = vec4(uv_to_cs(uv), 0.0, 1.0);
                vec4 ray_dir_ws = view_to_world * (clip_to_view * ray_dir_cs);

                surface.point = ray_origin_ws.xyz;
                surface.normal = gbuffer.normal;
                surface.wo = -normalize(ray_dir_ws.xyz);
                surface.roughness = gbuffer.roughness;
            }

            uint seed0 = hash(frame_idx);
            seed0 = hash(seed0 + 15488981u * uint(pix.x));
            seed0 = seed0 + 1302391u * uint(pix.y);

          	contrib += reconstruct_lighting(surface, pix, seed0);
        }
        
        finalColor = contrib;
    }
    
    fragColor = finalColor;
}

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	vec2 fragCoord = vec2(gl_GlobalInvocationID.xy) + 0.5;
	vec4 finalColor;

	mainImage(finalColor, fragCoord);

	// Temp
	//finalColor /= max(1e-3, finalColor.a);
	finalColor.a = 1.;



    finalColor.rgb *= 0.75;

    //finalColor.rgb /= 2;

	imageStore(outputTex, ivec2(gl_GlobalInvocationID.xy), finalColor);
}