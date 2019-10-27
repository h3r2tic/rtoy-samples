uniform restrict writeonly image2D outputTex;
uniform vec4 outputTex_size;

uniform float g_mouseX;
#define iMouse vec4(g_mouseX, 0, 0, 0)

#define iResolution outputTex_size

#include "math.inc"
#include "world.inc"
#include "brdf.inc"

uniform sampler2D g_primaryVisTex;
//uniform sampler2D g_blueNoise;

uniform uint g_frameIndex;

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

float power_heuristic(float nf, 
                      float fPdf, 
                      float ng, 
                      float gPdf)
{
    float f = nf * fPdf;
    float g = ng * gPdf;
    return (f*f)/(f*f + g*g);
}

vec4 integrate_lighting(SurfaceInfo surface, MaterialInfo material, vec3 wi, uint useed)
{
    float reservoir_lpdf = -1.;
    vec3 reservoir_point_on_light = vec3(0);
    vec3 le = vec3(0);
    
    float reservoir_rateSum = 0.0f;

    vec3 lcol = vec3(0.);
    
    {
        reservoir_lpdf = 0.0;
        
		//vec2 u12 = hash21(material.seed * 23430424.1224);
		//vec2 u12 = texhash_21(material.seed + 0.123);
		uint useed1 = bobJenkinsHash(useed);

		vec2 u12 = vec2(
			uintToUniformFloat(useed1),
			uintToUniformFloat(bobJenkinsHash(useed1))
		);

        // sample brdf        
        float bpdf = -1.;
        vec3 brdfSample = sample_brdf(surface, material, u12, bpdf);
        if (bpdf > 0.)
        {
            //bpdf = brdf_pdf(wi, brdfSample, surface, material);
            
	        SurfaceInfo hit_surf = dist_march(0.0, surface.point + brdfSample * 0.01, brdfSample);
            //if (MATCHES_ID(hit_surf.id, LIGHT_ID))
			reservoir_lpdf = bpdf;// * lightSelRate;
			reservoir_point_on_light = hit_surf.point;
        }
        
        reservoir_lpdf = max(0., reservoir_lpdf);

		return vec4(reservoir_point_on_light, reservoir_lpdf);
    }
}

vec4 sample_lights(SurfaceInfo surface, MaterialInfo material, uint useed)
{
    return integrate_lighting(surface, material, -surface.incomingRayDir, useed);
}

// **************************************************************************
// MAIN COLOR

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
	vec4 surfacePckd = texelFetch(g_primaryVisTex, ivec2(fragCoord), 0);
	SurfaceInfo surface = unpackSurfaceInfo(surfacePckd,  fragCoord);
    RaySampleInfo currSample = setup_cameraRay(fragCoord, vec2(0));

	MaterialInfo material;
	bool hasMaterial = calc_material(surface, currSample, 0, material);

    if (hasMaterial && material.specExponent > 10) {
		uint useed = bobJenkinsHash(ivec3(fragCoord, g_frameIndex));
	    fragColor = sample_lights(surface, material, useed);
		//fragColor = vec4(surface.normal * 0.5 + 0.5, 1);
		//fragColor = vec4(material.baseColor, 1);
		//fragColor = vec4(uv, 0, 1);
    } else {
        fragColor = vec4(0, 0, 0, -1);
    }
}

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	vec2 fragCoord = vec2(gl_GlobalInvocationID.xy) + 0.5;
	vec4 finalColor;
	mainImage(finalColor, fragCoord);

	imageStore(outputTex, ivec2(gl_GlobalInvocationID.xy), finalColor);
}
