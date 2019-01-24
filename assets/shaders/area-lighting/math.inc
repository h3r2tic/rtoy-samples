#define PI 3.14159
#define TWO_PI 6.28318
#define INV_TWO_PI .159155
#define PI_OVER_TWO 1.570796

#define REALLY_SMALL_NUMBER 0.0001
#define REALLY_BIG_NUMBER 1000000.

float saturate(float v) { return clamp(v, 0., 1.); }
vec2 saturate(vec2 v) { return clamp(v, 0., 1.); }
vec3 saturate(vec3 v) { return clamp(v, 0., 1.); }
vec4 saturate(vec4 v) { return clamp(v, 0., 1.); }

float sqr(float v) { return v * v; }
vec2 sqr(vec2 v) { return v * v; }
vec3 sqr(vec3 v) { return v * v; }
vec4 sqr(vec4 v) { return v * v; }

// Rotate the input point around the y-axis by the angle given as a cos(angle)
// and sin(angle) argument.  There are many times where I want to reuse the
// same angle on different points, so why do the heavy trig twice. Range of
// outputs := ([-1.,-1.,-1.] -> [1.,1.,1.])
vec3 rotate_yaxis( vec3 point, float cosa, float sina )
{
    return vec3(point.x * cosa  + point.z * sina,
                point.y,
                point.x * -sina + point.z * cosa);
}

// Rotate the input point around the x-axis by the angle given as a cos(angle)
// and sin(angle) argument.  There are many times where  I want to reuse the
// same angle on different points, so why do the  heavy trig twice. Range of
// outputs := ([-1.,-1.,-1.] -> [1.,1.,1.])
vec3 rotate_xaxis( vec3 point, float cosa, float sina )
{
    return vec3(point.x,
                point.y * cosa - point.z * sina,
                point.y * sina + point.z * cosa);
}

// --------------------------------------
// from dave hoskins: https://www.shadertoy.com/view/4djSRW

#define HASHSCALE3 vec3(.1031, .1030, .0973)
vec2 hash21(float p)
{
    vec3 p3 = fract(vec3(p) * HASHSCALE3);
    p3 += dot(p3, p3.yzx + 19.19);
    return fract(vec2((p3.x + p3.y)*p3.z, (p3.x+p3.z)*p3.y));
}

#define HASHSCALE1 .1031
float hash12(vec2 p)
{
    vec3 p3  = fract(vec3(p.xyx) * HASHSCALE1);
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.x + p3.y) * p3.z);
}

// ----
// http://amindforeverprogramming.blogspot.com/2013/07/random-floats-in-glsl-330.html
uint hashInt1D( uint x )
{
	x += x >> 11;
	x ^= x << 7;
	x += x >> 15;
	x ^= x << 5;
	x += x >> 12;
	x ^= x << 9;
	return x;
}

uint hashInt2D( uint x, uint y )
{
	x += x >> 11;
	x ^= x << 7;
	x += y;
	x ^= x << 6;
	x += x >> 15;
	x ^= x << 5;
	x += x >> 12;
	x ^= x << 9;
	return x;
}

uint hashInt3D( uint x, uint y, uint z )
{
	x += x >> 11;
	x ^= x << 7;
	x += y;
	x ^= x << 3;
	x += z ^ ( x >> 14 );
	x ^= x << 6;
	x += x >> 15;
	x ^= x << 5;
	x += x >> 12;
	x ^= x << 9;
	return x;
}
// ----

uint bobJenkinsHash( uint x ) {
	x += ( x << 10u );
	x ^= ( x >>  6u );
	x += ( x <<  3u );
	x ^= ( x >> 11u );
	x += ( x << 15u );
	return x;
}

uint bobJenkinsHash(uvec2 v) {
    return bobJenkinsHash( v.x ^ bobJenkinsHash(v.y));
}

uint bobJenkinsHash(uvec3 v) {
    return bobJenkinsHash( v.x ^ bobJenkinsHash(v.y) ^ bobJenkinsHash(v.z));
}

float uintToUniformFloat(uint h) {
	const uint mantissaMask = 0x007FFFFFu;
	const uint one = 0x3F800000u;

	h &= mantissaMask;
	h |= one;

	float  r2 = uintBitsToFloat( h );
	return r2 - 1.0;
}
// --------------------------------------

float dist_squared(vec3 v1, vec3 v2)
{
    return (v1.x - v2.x) * (v1.x - v2.x) + 
        (v1.y - v2.y) * (v1.y - v2.y) + 
        (v1.z - v2.z) * (v1.z - v2.z);
}

#if 1
vec4 intersect_sphere(vec3 ro, vec3 rd, vec3 sphc, float sphr)
{
    if (dist_squared(ro,sphc) < sphr * sphr)
    { 
        return vec4(-1., vec3(0.)); 
    }
    
    vec3 sphro = ro - sphc; 
    float a = dot(rd, rd);
    float b = dot(sphro, rd);
    float c = dot(sphro, sphro) - sphr * sphr;
    float sign = mix(-1., 1., step(0., a));
    float t = (-b + sign * sqrt(b*b - a*c))/a; 
    
    vec3 n = normalize(ro + t * rd - sphc);
    return vec4(max(0., t), n);    
    
}
#else
vec4 intersect_sphere(vec3 ro, vec3 rd, vec3 sphc, float sphr)
{
 vec3 rayToCenter = sphc - ro;

 /* calculate coefficients a, b, c from quadratic equation */

 /* float a = dot(ray->dir, ray->dir); // ray direction is normalised, dotproduct simplifies to 1 */ 
 float b = dot(rayToCenter, rd);
 float c = dot(rayToCenter, rayToCenter) - sphr*sphr;
 float disc = b * b - c; /* discriminant of quadratic formula */

 /* solve for t (distance to hitpoint along ray) */
    
 float t = 0.0;

 if (disc < 0.0f) return vec4(-1., vec3(0.)); 
 else t = b - sqrt(disc);

 if (t < 0.0f){
  t = b + sqrt(disc);
  if (t < 0.0f) return vec4(-1., vec3(0.)); 
 }

  vec3 n = normalize(ro + t * rd - sphc);
  return vec4(max(0., t), n);    
}

#endif

vec3 polar_to_cartesian(float sinTheta, 
                        float cosTheta, 
                        float sinPhi,
                        float cosPhi)
{
    return vec3(sinTheta * cosPhi,
                sinTheta * sinPhi,
                cosTheta);
}


// **************************************************************************
// DISTANCE FIELDS

float sphere_df( vec3 p, float r) 
{ 
    return length(p) - r; 
}

float envsphere_df ( vec3 p, float r) 
{ 
    return r - length(p); 
}

float roundbox_df ( vec3 p, vec3 b, float r ) 
{
    return length(max(abs(p-vec3(0., .5*b.y, 0.))-.5*b,0.))-r; 
}
