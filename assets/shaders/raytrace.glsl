#include "inc/uv.inc"

uniform restrict writeonly image2D outputTex;
uniform vec4 outputTex_size;

layout(std430) buffer constants {
    mat4 clip_to_view;
    mat4 view_to_world;
};

struct BvhNode {
    vec4 box_min;
    vec4 box_max;
};

layout(std430) buffer bvh {
    BvhNode bvh_nodes[];
};

struct Ray {
	vec3 o;
	vec3 d;
};

bool intersect_ray_aabb(Ray r, vec3 pmin, vec3 pmax)
{
	const vec3 f = (pmax.xyz - r.o.xyz) / r.d;
	const vec3 n = (pmin.xyz - r.o.xyz) / r.d;

	const vec3 tmax = max(f, n);
	const vec3 tmin = min(f, n);

	const float t1 = min(tmax.x, min(tmax.y, tmax.z));
	const float t0 = max(max(tmin.x, max(tmin.y, tmin.z)), 0.0);

	return t1 >= t0;
}


layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    vec2 uv = get_uv(outputTex_size);
    vec4 ray_origin_cs = vec4(uv_to_cs(uv), 1.0, 1.0);
    vec4 ray_origin_ws = view_to_world * (clip_to_view * ray_origin_cs);
    ray_origin_ws /= ray_origin_ws.w;

    vec3 camera_pos_ws = (view_to_world * vec4(0, 0, 0, 1)).xyz;
    vec3 v = normalize(camera_pos_ws - ray_origin_ws.xyz);

    Ray r;
    r.o = ray_origin_ws.xyz;
    r.d = -v;

	vec4 col = vec4(r.d * 0.5 + 0.5, 1.0) * 0.5;

    for (uint i = 26; i < 256 * 256; i += 64) {
        BvhNode node = bvh_nodes[i];
        bool intersects_box = intersect_ray_aabb(r, node.box_min.xyz, node.box_max.xyz);

        if (intersects_box) {
            col += 0.1;
        }
    }

    //col = vec4(uv, 0, 1);

    //vec4 col = vec4(uv, 0.1, 1);
	imageStore(outputTex, pix, col);
}
