#define MIRROR_ID 1.
#define SEMI_MIRROR_ID 2.
#define SEMI_ROUGH_ID 3.
#define ROUGH_ID 4.
#define LIGHT_ID 5.

#define BACKDROP_ID 6.
#define ENVIRONMENT_ID 7.

#define MATCHES_ID(id1, id2) (id1 > (id2 - .5)) && (id1 < (id2 + .5))

const vec4 g_lights[4] = vec4[](
	vec4(-2.,1.8, -3., 0.1),
	vec4(-.666,1.8, -3., .2),
	vec4(.666,1.8, -3., .3),
	vec4(2.,1.8, -3., .4)
);

vec4 get_light(int i)
{
    vec4 res = g_lights[i];
    
    res.x += ((iMouse.x / iResolution.x) - 0.5) * 8.0;
    
    return res;
}

vec4 get_light_by_pos(vec3 p)
{
    float lpoff = ((iMouse.x / iResolution.x) - 0.5) * 8.0;
    if (p.x - lpoff > 1.5) {
        return g_lights[3];
    } else if (p.x - lpoff > 0.0) {
        return g_lights[2];
    } else if (p.x - lpoff > -1.5) {
        return g_lights[1];
    } else {
        return g_lights[0];
    }
}

struct RaySampleInfo
{
    vec3 origin;
    vec3 direction;
    vec2 imagePlaneUV;
};
RaySampleInfo INIT_RAY_INFO() {
	return RaySampleInfo(vec3(0.) /* origin */, vec3(0.) /* direction */, vec2(0.) /* imagePlaneUV */);
}

RaySampleInfo setup_cameraRay(vec2 fragCoord, vec2 aaoffset)
{
    vec3 origin = vec3(0.0, 2., 6.0);
    vec3 cameraPointsAt = vec3(0., .5, 0.);

    float invAspectRatio = iResolution.y / iResolution.x;
    vec2 imagePlaneUV = (fragCoord + aaoffset) / iResolution.xy - .5;
    imagePlaneUV.y *= invAspectRatio;

    vec3 iu = vec3(0., 1., 0.);

    vec3 iz = normalize( cameraPointsAt - origin );
    vec3 ix = normalize( cross(iz, iu) );
    vec3 iy = cross(ix, iz);

    vec3 direction = normalize( imagePlaneUV.x * ix + imagePlaneUV.y * iy + .8 * iz );

    return RaySampleInfo(origin, direction, imagePlaneUV);

}

struct SurfaceInfo
{
    float id;
    vec3 incomingRayDir;
    vec3 point;
    vec3 normal;
    float incomingRayLength;
    float rayDepth;
    float roughnessMult;
};
SurfaceInfo INIT_SURFACE_INFO(vec3 incomingRayDir) {
	return SurfaceInfo(-1. /* id */, incomingRayDir /* incomingRayDir */, vec3(0.) /* point */, vec3(0.) /* normal */, 0. /* incomingRayLength */, 0. /* rayDepth */, 1.);
}

float unpackUnorm(uint pckd, uint bitCount) {
	uint maxVal = (1u << bitCount) - 1;
	return float(pckd & maxVal) / maxVal;
}

uint packUnorm(float val, uint bitCount) {
	uint maxVal = (1u << bitCount) - 1;
	return uint(saturate(val) * maxVal);
}

float packNormal_11_10_11(vec3 n) {
	uint pckd = 0;
	pckd += packUnorm(n.x * 0.5 + 0.5, 11);
	pckd += packUnorm(n.y * 0.5 + 0.5, 10) << 11;
	pckd += packUnorm(n.z * 0.5 + 0.5, 11) << 21;
	return uintBitsToFloat(pckd);
}

vec3 unpackNormal_11_10_11(float pckd) {
	uint p = floatBitsToUint(pckd);
	return normalize(vec3(
		unpackUnorm(p, 11),
		unpackUnorm(p >> 11, 10),
		unpackUnorm(p >> 21, 11)
	) * 2.0 - 1.0);
}

vec4 packSurfaceInfo(SurfaceInfo surface) {
	vec4 result = vec4(0.);
	result.x = packNormal_11_10_11(surface.normal);
	result.y = surface.incomingRayLength;
	result.z = surface.id;
	result.w = surface.roughnessMult;
	return result;
}

SurfaceInfo unpackSurfaceInfo(vec4 pckd, vec2 fragCoord) {
	SurfaceInfo surface;
	surface.normal = unpackNormal_11_10_11(pckd.x);
	surface.incomingRayLength = pckd.y;
	surface.id = pckd.z;
	surface.roughnessMult = pckd.w;

	RaySampleInfo rsi = setup_cameraRay(fragCoord, vec2(0.0));
    surface.incomingRayDir = rsi.direction;
    surface.point = rsi.origin + surface.incomingRayDir * surface.incomingRayLength;
    surface.rayDepth = 0.0;

	return surface;
}

vec3  unpackSurfacePoint(vec4 pckd, vec2 fragCoord) {
	RaySampleInfo rsi = setup_cameraRay(fragCoord, vec2(0.0));
    return rsi.origin + rsi.direction * pckd.y;
}

// **************************************************************************

struct MaterialInfo
{
    float seed;
    float specExponent;
    float specIntensity;
    vec3  baseColor;
};
MaterialInfo INIT_MATERIAL_INFO(float seed) {
	return MaterialInfo(seed, 1. /* specExponent */, 1. /* specIntensity */, vec3(.8) /* baseColor */);
}

// **************************************************************************
// MARCH

vec2 union_obj(vec2 o1, vec2 o2)
{
    return (o1.x < o2.x) ? o1 : o2;
}

vec2 map(float depth, vec3 p)
{
    vec2 roughObj =       vec2(roundbox_df(rotate_xaxis(p - vec3(0., -.4,  1.2), cos( 0.0), sin( 0.0)), vec3(5., .02, 1.), .01), ROUGH_ID);
    vec2 semiroughObj =   vec2(roundbox_df(rotate_xaxis(p - vec3(0., -.38,  0.), cos(-0.12), sin(-0.12)) , vec3(5., .02, 1.), .01), SEMI_ROUGH_ID);
    vec2 semimirrorObj =  vec2(roundbox_df(rotate_xaxis(p - vec3(0., -.2, -1.2), cos(-0.26), sin(-0.26)) , vec3(5., .02, 1.), .01), SEMI_MIRROR_ID);
    vec2 mirrorObj =      vec2(roundbox_df(rotate_xaxis(p - vec3(0., .2, -2.4), cos(-0.5), sin(-0.5)) , vec3(5., .02, 1.), .01), MIRROR_ID);    
    
    
    vec2 resultObj = union_obj(mirrorObj, semimirrorObj);
    resultObj = union_obj(resultObj, semiroughObj);
    resultObj = union_obj(resultObj, roughObj);    
    
    float backdropDF = roundbox_df(p + vec3(0., 1., 0.), vec3(20.,.2,10.), 0.);
    backdropDF = min(backdropDF, roundbox_df(rotate_xaxis(p - vec3(0., -3.8, -3.2), cos(.5), sin(.5)), vec3(20., 10., .2), 0.));
    vec2 backdropObjs = vec2(backdropDF, BACKDROP_ID);    
    resultObj = union_obj(resultObj, backdropObjs);
    
    if (depth < .5)
    {
        vec4 l = get_light(0);
        float lightDF = sphere_df(p - l.xyz, l.w);
        l = get_light(1);
        lightDF = min(lightDF, sphere_df(p - l.xyz, l.w));
        l = get_light(2);
        lightDF = min(lightDF, sphere_df(p - l.xyz, l.w));
        l = get_light(3);
        lightDF = min(lightDF, sphere_df(p - l.xyz, l.w));
        
        vec2 lightObjs =       vec2(lightDF, LIGHT_ID);
        resultObj = union_obj(resultObj, lightObjs);
    }
    
    resultObj = union_obj(resultObj, vec2( envsphere_df(p, 11.), ENVIRONMENT_ID) );
        
    return resultObj;
}

vec3 calc_normal(vec3 p)
{
 
    vec3 epsilon = vec3(0.001, 0., 0.);
    
    vec3 n = vec3(map(1., p + epsilon.xyy).x - map(1., p - epsilon.xyy).x,
                  map(1., p + epsilon.yxy).x - map(1., p - epsilon.yxy).x,
                  map(1., p + epsilon.yyx).x - map(1., p - epsilon.yyx).x);
    
    return normalize(n);
}

SurfaceInfo dist_march(float depth, vec3 ro, vec3 rd)
{
    SurfaceInfo surface = INIT_SURFACE_INFO(rd); 
    
    float t = 0.;
    vec3 p = ro;    
    vec2 obj = vec2(0.);
    float d = REALLY_BIG_NUMBER;
    
    for (int i = 0; i < 32 && d >= .001; i++)
    {
        obj = map(depth, p);
        d = obj.x;
        
        t += d;
        p += rd * d;
        
        //if (d < .001) { break; }
        //obj.y = 0.;
    }

    surface.id = obj.y;        
    surface.point = p;
    surface.normal = calc_normal(surface.point);
    surface.incomingRayLength = t;
    surface.rayDepth = depth;
    
    return surface;
}

bool calc_material(SurfaceInfo surface, RaySampleInfo currSample, float seed, out MaterialInfo material)
{
        material = INIT_MATERIAL_INFO(seed);
        float roughness = 1.;

        if (surface.id < .5)
        {
            return false;
        }        
        else if (MATCHES_ID(surface.id, LIGHT_ID))
        {
            return false;
        }
        else if (MATCHES_ID(surface.id, MIRROR_ID))
        {
            roughness = 0.;
            material.baseColor = vec3(.005);
        }
        else if (MATCHES_ID(surface.id, SEMI_MIRROR_ID))
        {
            roughness = .4;
            material.baseColor = vec3(.005);
        }
        else if (MATCHES_ID(surface.id, SEMI_ROUGH_ID))
        {
            roughness = .8;
            material.baseColor = vec3(.005);
        }
        else if (MATCHES_ID(surface.id, ROUGH_ID))
        {
            roughness = .95;
            material.baseColor = vec3(.005);
        }
                   
        
        else if (MATCHES_ID(surface.id, BACKDROP_ID))
        {
            roughness = 1.;
            material.baseColor = vec3(.015, .012, .012);
        }
         
        else
        {
            return false;
        }
    
        material.specExponent = floor(max(1., (1. - pow(roughness, .15)) * 40000.));    
        material.specIntensity = 15.;

		float nonlinearity = 0.75;
		material.specExponent = pow(material.specExponent, nonlinearity);
        material.specExponent *= surface.roughnessMult;
		material.specExponent = pow(material.specExponent, 1.0 / nonlinearity);

    return true;
}
