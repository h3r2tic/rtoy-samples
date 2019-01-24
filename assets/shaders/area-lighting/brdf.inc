void calc_binormals(vec3 normal,
                    out vec3 tangent,
                    out vec3 binormal)
{
    if (abs(normal.x) > abs(normal.y))
    {
        tangent = normalize(vec3(-normal.z, 0., normal.x));
    }
    else
    {
        tangent = normalize(vec3(0., normal.z, -normal.y));
    }
    
    binormal = cross(normal, tangent);
}
 
vec3 uniform_sample_cone(vec2 u12, 
                         float cosThetaMax, 
                         vec3 xbasis, vec3 ybasis, vec3 zbasis)
{
    float cosTheta = (1. - u12.x) + u12.x * cosThetaMax;
    float sinTheta = sqrt(1. - cosTheta * cosTheta);
    float phi = u12.y * TWO_PI;
    vec3 samplev = polar_to_cartesian(sinTheta, cosTheta, sin(phi), cos(phi));
    return samplev.x * xbasis + samplev.y * ybasis + samplev.z * zbasis;
}

float ggx( float a2, float ndotm ) {
	return a2 / (PI * sqr( ndotm * ndotm * ( a2 - 1 ) + 1));
}
             
vec3 brdf(vec3 wi, 
          vec3 wo, 
          vec3 n,
          MaterialInfo material)
{
    
    float cosThetaN_Wi = abs(dot(n, wi));
    float cosThetaN_Wo = abs(dot(n, wo));
    vec3 wh = normalize(wi + wo);
    float cosThetaN_Wh = abs(dot(n, wh));   
    
    // Compute geometric term of blinn microfacet      
    float cosThetaWo_Wh = abs(dot(wo, wh));
    float G = min(1., min((2. * cosThetaN_Wh * cosThetaN_Wo / cosThetaWo_Wh),
                           (2. * cosThetaN_Wh * cosThetaN_Wi / cosThetaWo_Wh)));
    
    // Compute distribution term
    float D = (material.specExponent+2.) * INV_TWO_PI * pow(max(0., cosThetaN_Wh), material.specExponent);
    
    // assume no fresnel
    float F = 1.;
    
    return material.baseColor * D * G * F / (4. * cosThetaN_Wi * cosThetaN_Wo);
}

vec3 brdf(vec3 wi, 
          vec3 wo, 
          vec3 n,
          MaterialInfo material,
		  out float pdf)
{
    
    float cosThetaN_Wi = abs(dot(n, wi));
    float cosThetaN_Wo = abs(dot(n, wo));
    vec3 wh = normalize(wi + wo);
    float cosThetaN_Wh = abs(dot(n, wh));   
    
    // Compute geometric term of blinn microfacet      
    float cosThetaWo_Wh = abs(dot(wo, wh));
    float G = min(1., min((2. * cosThetaN_Wh * cosThetaN_Wo / cosThetaWo_Wh),
                           (2. * cosThetaN_Wh * cosThetaN_Wi / cosThetaWo_Wh)));

	float lobe = pow(max(0., cosThetaN_Wh), material.specExponent);
    
    // Compute distribution term
    float D = (material.specExponent+2.) * INV_TWO_PI * lobe;
    
    pdf = ((material.specExponent + 1.) * lobe)/(TWO_PI * 4. * cosThetaWo_Wh);

    // assume no fresnel
    float F = 1.;
    
    return material.baseColor * D * G * F / (4. * cosThetaN_Wi * cosThetaN_Wo);
}

float brdf_pdf( vec3 wi, vec3 wo, 
                SurfaceInfo surface, 
                MaterialInfo material )
{
    vec3 wh = normalize(wi + wo);    
    float cosTheta = abs(dot(wh, surface.normal));
        
    float pdf = -1.;
    if (dot(wo, wh) > 0.)
    {
        pdf = ((material.specExponent + 1.) * pow(max(0., cosTheta), material.specExponent))/(TWO_PI * 4. * dot(wo, wh));
    }
    
    return pdf;
}

vec3 sample_brdf( SurfaceInfo surface,
                 MaterialInfo material,
				 vec2 u12,
                out float pdf)
{
           
    //vec2 u12 = hash21(material.seed);
    //vec2 u12 = texhash_21(material.seed + 0.123);
    
    float cosTheta = pow(max(0., u12.x), 1./(material.specExponent+1.));
    float sinTheta = sqrt(max(0., 1. - cosTheta * cosTheta));
    float phi = u12.y * TWO_PI;
    
    vec3 whLocal = polar_to_cartesian(sinTheta, cosTheta, sin(phi), cos(phi));

    vec3 tangent = vec3(0.), binormal = vec3(0.);
    calc_binormals(surface.normal, tangent, binormal);
    
    vec3 wh = whLocal.x * tangent + whLocal.y * binormal + whLocal.z * surface.normal;
    
    vec3 wo = -surface.incomingRayDir;    
    if (dot(wo, wh) < 0.)
    {
       wh *= -1.;
    }
	
    vec3 wi = reflect(surface.incomingRayDir, wh);
    
    pdf = ((material.specExponent + 1.) * pow(clamp(abs(dot(wh, surface.normal)),0.,1.), material.specExponent))/(TWO_PI * 4. * dot(wo, wh));
    return wi;
}    
