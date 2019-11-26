uniform restrict writeonly layout(binding = 0) image2D outputTex;
layout(std140, binding = 1) uniform globals {
    vec4 outputTex_size;
    float g_mouseX;
};

#define iMouse vec4(g_mouseX, 0, 0, 0)
#define iResolution outputTex_size

#include "math.inc"
#include "world.inc"
#include "brdf.inc"

uniform layout(binding = 2) texture2D g_primaryVisTex;
uniform layout(binding = 3) texture2D g_lightSamplesTex;

//uniform uint g_frameIndex;

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



/*vec3 light_emission(vec3 lp, vec3 ln)
{
    return 10. * vec3(1., .98, .95);
}*/

float calc_visibility( vec3 ro, vec3 rd, float ray_extent )
{
    
    SurfaceInfo surface = dist_march(1., ro, rd);
    return step(ray_extent, surface.incomingRayLength);
    
}

float light_pdf( vec4 light,
                SurfaceInfo surface )
{
    
    float sinThetaMax2 = light.w * light.w / dist_squared(light.xyz, surface.point);
    float cosThetaMax = sqrt(max(0., 1. - sinThetaMax2));
    return 1. / (TWO_PI * (1. - cosThetaMax));
    
}

vec3 sample_light( SurfaceInfo surface,
                   MaterialInfo material,
                   vec4 light,
                 out float pdf )
{
    vec2 u12 = hash21(material.seed);
    
    vec3 tangent = vec3(0.), binormal = vec3(0.);
    vec3 ldir = normalize(light.xyz - surface.point);
    calc_binormals(ldir, tangent, binormal);
    
    float sinThetaMax2 = light.w * light.w / dist_squared(light.xyz, surface.point);
    float cosThetaMax = sqrt(max(0., 1. - sinThetaMax2));
    vec3 light_sample = uniform_sample_cone(u12, cosThetaMax, tangent, binormal, ldir);
    
    pdf = -1.;
    if (dot(light_sample, surface.normal) > 0.)
    {
        pdf = 1. / (TWO_PI * (1. - cosThetaMax));
    }
    
    return light_sample;
    
}
 
vec3 calc_light_emission(vec3 p)
{
    vec3 le = vec3(1., .98, .95) * 10.;

    float lpoff = ((iMouse.x / iResolution.x) - 0.5) * 8.0;
    if (p.x - lpoff > 1.5) {
        le = vec3(1., .4, .1) * 10.;
    } else if (p.x - lpoff > 0.0) {
        le = vec3(.3, 1.0, .2) * 10.;
    } else if (p.x - lpoff > -1.5) {
        le = vec3(.2, 0.5, 1.0) * 10.;
    } else {
        le = vec3(.7, 0.15, 1.0) * 15.;
    }
    
    vec4 lt = get_light_by_pos(p) + vec4(lpoff, 0, 0, 0);
    if (dot(lt.xyz - p, lt.xyz - p) > lt.w * lt.w * 1.05) {
        le = vec3(0.);
    }
    
    return le;
}

mat2 rotate2d(float _angle){
    return mat2(cos(_angle),-sin(_angle),
                sin(_angle),cos(_angle));
}

void eval_sample(SurfaceInfo surface, MaterialInfo material, vec3 wi, vec2 px, int sidx, bool approxVisibility, inout int scount, inout vec3 lcol, inout float wsum)
{
    float k = 11.0;

	//ivec2 xyoff = ivec2((rotate2d(material.seed * PI) * poissonOffsets[sidx]) * k);
	ivec2 xyoff = ivec2(poissonOffsets[sidx] * k);

	//float w = exp(-1.0 * float(xyoff.x * xyoff.x + xyoff.y * xyoff.y) / float((k+1.) * (k+1.)));
	float w = 1.0;
	//float w = exp(-0.02 * dot(vec2(xyoff), vec2(xyoff)));

	//vec4 hit_data = texelFetch(iChannel0, ivec2(px) + ivec2(xoff * km, yoff * km), 0);
	vec4 hit_data = texelFetch(g_lightSamplesTex, ivec2(px) + xyoff, 0);

	float lpdf = hit_data.w;
	vec3 hitOffset = hit_data.xyz - surface.point;
	float hitOffsetLenSq = dot(hitOffset, hitOffset);

	// Adjust the PDF of the borrowed sample. It's defined wrt the solid angle
	// of the neighbor. We need to transform it into the solid angle of the current point.
	if (approxVisibility) {
		RaySampleInfo neighSample = setup_cameraRay(ivec2(px) + xyoff, vec2(0));
		vec4 surfacePckd = texelFetch(g_primaryVisTex, ivec2(px) + xyoff, 0);
		vec3 neighPoint = unpackSurfacePoint(surfacePckd,  ivec2(px) + xyoff);

		lpdf *= hitOffsetLenSq / max(1e-10, dist_squared(neighPoint, hit_data.xyz));

		// Approximate shadowing
		vec3 surfaceOffset = neighPoint - surface.point;

		if (dot(hitOffset, surface.normal) * 0.2 / length(hitOffset) < dot(surfaceOffset, surface.normal) / length(surfaceOffset))
		{
			w = 0;
		}

		// TODO: what of non-overlapping horizons?

		//lpdf /= max(1e-5, dot(neighSurface.normal, normalize(hit_data.xyz - neighPoint)));
		/*if (dot(surface.normal, hit_data.xyz - surface.point) <= 0.0) {
			lpdf = -1;
		}*/
	}

	vec3 lightSample = hitOffset / sqrt(hitOffsetLenSq);

	vec3 le = calc_light_emission(hit_data.xyz);
	//float bpdf = brdf_pdf(wi, lightSample, surface, material);
	float bpdf;

	float bpdf_threshold = 0.;
	float ndotl = dot(lightSample, surface.normal);

	//if (lpdf >= 0. && bpdf > bpdf_threshold)
	//if (ndotl > 0)
	if (lpdf >= 0.0)
	{
		wsum += w;
	}

	//if (lpdf > 0.5 && ndotl > 0. && bpdf > bpdf_threshold)
	if (lpdf > 0.)
	{
		++scount;

		vec3 p = vec3(1.0);
		p *= brdf(wi, lightSample, surface.normal, material, bpdf);
		p /= lpdf;
		p *= saturate(ndotl);

		float techniqueW = lpdf / (lpdf + bpdf);
		p *= techniqueW;

		//if (p.x > 0.)
		{
			lcol += w * p * le;
		}
	}
}

vec4 reconstruct_lighting(SurfaceInfo surface, MaterialInfo material, vec3 wi, vec2 px)
{
    vec3 lcol = vec3(0);
    float wsum = 0.0;
    
	int scount = 0;

	eval_sample(surface, material, wi, px, 0, false, scount, lcol, wsum);
    
	for (int sidx = 1; sidx < 16; ++sidx)
    //for (int sidx = 1; sidx < 32; ++sidx)
    //for (int sidx = 1; sidx < 1; ++sidx)
    {
		eval_sample(surface, material, wi, px, sidx, true, scount, lcol, wsum);
    }

	lcol *= material.specIntensity;

    return vec4(lcol / max(1e-5, wsum), 1.0);
}    


void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    vec2 uv = fragCoord.xy / iResolution.xy;        
        
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
    
    //if (g_frameIndex > 0)
    //{
        //finalColor = texture(iChannel2, uv);
    //}
    
    //if (g_frameIndex < 0.5)
    {
	    RaySampleInfo currSample = setup_cameraRay(fragCoord, vec2(0));
        //RaySampleInfo currSample = setup_cameraRay(vec2(0));
    
		vec4 surfacePckd = texelFetch(g_primaryVisTex, ivec2(fragCoord), 0);
		SurfaceInfo surface = unpackSurfaceInfo(surfacePckd,  fragCoord);
        
        vec4 contrib = vec4(0);

        // hacky hack!
		// already accounted for in filter_surface
        /*if (MATCHES_ID(surface.id, LIGHT_ID))
        {
            contrib.rgb += calc_light_emission(surface.point) * 0.07;
        }*/

        MaterialInfo material;
        if (calc_material(surface, currSample, seed, material)) {
        	contrib += reconstruct_lighting(surface, material, -surface.incomingRayDir, fragCoord);
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
	//finalColor.a = 1.;

	imageStore(outputTex, ivec2(gl_GlobalInvocationID.xy), finalColor);
}