uniform restrict writeonly layout(binding = 0) image2D outputTex;
layout(std140, binding = 1) uniform globals {
    vec4 outputTex_size;
    float g_mouseX;
    uint g_frameIndex;
};

#define iMouse vec4(g_mouseX, 0, 0, 0)
#define iResolution outputTex_size

#include "math.inc"
#include "world.inc"
#include "brdf.inc"

uniform layout(binding = 2) texture2D g_primaryVisTex;
uniform layout(binding = 3) texture2D g_whiteNoise;

// Buffer B does the sampling and accumulation work 

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

vec2 texhash_21(float seed) {
    ivec2 nc = ivec2(seed * 255.0, fract(seed * 255.0) * 255.0);
    return vec2(
        texelFetch(g_whiteNoise, nc % 256, 0).x,
        texelFetch(g_whiteNoise, (nc + ivec2(1, 0)) % 256, 0).x
    );
}

float texhash_12(float seed0, float seed1) {
    ivec2 nc = ivec2(seed0 * 255.0, seed1 * 255.0 * 255.0);
    return texelFetch(g_whiteNoise, nc % 256, 0).x;
}


vec3 sample_light( SurfaceInfo surface,
                   MaterialInfo material,
                   vec4 light,
                 out float pdf )
{
    //return normalize(light.xyz - surface.point);
    
    //vec2 u12 = hash21(material.seed);
    //vec2 u12 = vec2(0.0);
    vec2 u12 = texhash_21(material.seed);
    
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
 
float power_heuristic(float nf, 
                      float fPdf, 
                      float ng, 
                      float gPdf)
{
    float f = nf * fPdf;
    float g = ng * gPdf;
    return (f*f)/(f*f + g*g);
}

vec4 integrate_lighting(SurfaceInfo surface, MaterialInfo material, vec3 wi)
{
    float reservoir_lpdf = -1.;
    vec3 reservoir_point_on_light = vec3(0);
    vec3 le = vec3(0);
    
    float reservoir_rateSum = 0.0f;

    vec3 lcol = vec3(0.);

    for (int i = 0; i < 4; ++i)
    {
        vec4 light = get_light(i);

        {
            // sample light
            float lpdf = -1.;
            vec3 lightSample = sample_light(surface, material, light, lpdf);

            float bpdf = brdf_pdf(wi, lightSample, surface, material);
			/*if (bpdf <= 0) {
				lpdf = -1;
			}*/

			float lightSelRate = bpdf;
            //float lightSelRate = 1.0;
            //float lightSelRate = max(1e-20, bpdf);

            float lightSelProb = lightSelRate / (reservoir_rateSum + lightSelRate);
            float lightSelDart = hash12(vec2(material.seed + float(i) * 8323.183, hash21(material.seed)));
            //float lightSelDart = texhash_12(fract(material.seed + 0.1), float(i) / 4.0);

            reservoir_rateSum += lightSelRate;

            if (lightSelProb < lightSelDart) {
                continue;
            }

            if (lpdf > 0.)
            {
                vec4 r = intersect_sphere(surface.point, lightSample, light.xyz, light.w);
                //r.x = length(light.xyz - surface.point);
                
                if (r.x > .0)
                {
	                vec3 point_on_light = surface.point + lightSample * r.x;
			        float visibility = 1.f;//calc_visibility(mix(surface.point, point_on_light, 0.001), lightSample, r.x);
                    reservoir_lpdf = lpdf * lightSelRate * visibility;
                    reservoir_point_on_light = point_on_light;
                }
            }
        }
    }

	const bool test_visibility = true;
	if (test_visibility && reservoir_lpdf > 0) {
		reservoir_lpdf *= calc_visibility(mix(surface.point, reservoir_point_on_light, 0.001), normalize(reservoir_point_on_light - surface.point), length(reservoir_point_on_light - surface.point));
	}
    
   	return vec4(reservoir_point_on_light, reservoir_lpdf / reservoir_rateSum);
}

vec4 sample_lights(SurfaceInfo surface, MaterialInfo material, float seed)
{
    return integrate_lighting(surface, material, -surface.incomingRayDir);
}

// **************************************************************************
// MAIN COLOR

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    vec2 uv = fragCoord.xy / iResolution.xy;
        
    //float seed = g_frameIndex + hash12( uv );
    //float seed = float(floor(float(g_frameIndex)/10.));
    //float seed = texelFetch(g_blueNoise, (ivec2(fragCoord) + ivec2(23, 37) * int(g_frameIndex)) % 1024, 0).x;
    //float seed = texelFetch(g_blueNoise, (ivec2(fragCoord)) % 1024, 0).x;
    //float seed = texelFetch(g_blueNoise, ivec2(fragCoord) % 1024, 0).x + g_frameIndex + hash12( uv ) / 256.0;

#if 1
	uint useed = bobJenkinsHash(ivec3(fragCoord, g_frameIndex));
    float seed = uintToUniformFloat(useed);
#else
    float seed = texelFetch(
		g_blueNoise,
		(ivec2(fragCoord) + ivec2(23, 37) * int(g_frameIndex)) % 1024, 0).x
		//+ uintToUniformFloat(bobJenkinsHash(ivec3(fragCoord, g_frameIndex))) / 256.0
		+ uintToUniformFloat(hashInt3D(uint(fragCoord.x), uint(fragCoord.y), g_frameIndex)) / 256.0
		;
#endif
    
    // ----------------------------------

    /*if (g_frameIndex > 0.5)
    {
        fragColor = vec4(0);
        return;
    }*/
    
    //RaySampleInfo currSample = setup_cameraRay( sin(.712 * seed) * vec2(.6 * cos(.231 * seed), .6 * sin(.231 * seed)) );
    RaySampleInfo currSample = setup_cameraRay(fragCoord, vec2(0));

    //SurfaceInfo surface = dist_march(0.0, currSample.origin,  currSample.direction);
	vec4 surfacePckd = texelFetch(g_primaryVisTex, ivec2(fragCoord), 0);
	SurfaceInfo surface = unpackSurfaceInfo(surfacePckd,  fragCoord);
	//fragColor = packSurfaceInfo(surface);

    MaterialInfo material;
    if (calc_material(surface, currSample, seed, material)) {
	    fragColor = sample_lights(surface, material, seed);
		//fragColor = vec4(surface.normal * 0.5 + 0.5, 1);
		//fragColor = vec4(material.baseColor, 1);
		//fragColor = vec4(uv, 0, 1);
    } else {
        fragColor = vec4(0);
    }
}

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	vec2 fragCoord = vec2(gl_GlobalInvocationID.xy) + 0.5;
	vec4 finalColor;
	mainImage(finalColor, fragCoord);

	imageStore(outputTex, ivec2(gl_GlobalInvocationID.xy), finalColor);
}
