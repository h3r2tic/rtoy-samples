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

float dist_squared(vec3 v1, vec3 v2)
{
    return (v1.x - v2.x) * (v1.x - v2.x) + 
        (v1.y - v2.y) * (v1.y - v2.y) + 
        (v1.z - v2.z) * (v1.z - v2.z);
}
