#include "inc/uv.inc"

uniform restrict writeonly image2D outputTex;
uniform vec4 outputTex_size;

layout(std430) buffer constants {
    mat4 clip_to_view;
    mat4 view_to_world;
};

layout(std430) buffer bvh_meta {
    uint bvh_node_count;
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

bool intersect_ray_aabb(Ray r, vec3 pmin, vec3 pmax, inout float t)
{
	const vec3 f = (pmax.xyz - r.o.xyz) / r.d;
	const vec3 n = (pmin.xyz - r.o.xyz) / r.d;

	const vec3 tmax = max(f, n);
	const vec3 tmin = min(f, n);

	const float t1 = min(tmax.x, min(tmax.y, tmax.z));
	const float t0 = max(max(tmin.x, max(tmin.y, tmin.z)), 0.0);

    t = t0;
	return t1 >= t0;
}


layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    vec2 uv = get_uv(outputTex_size);
    vec4 ray_origin_cs = vec4(uv_to_cs(uv), 1.0, 1.0);
    vec4 ray_origin_ws = view_to_world * (clip_to_view * ray_origin_cs);
    ray_origin_ws /= ray_origin_ws.w;

    vec4 ray_dir_cs = vec4(uv_to_cs(uv), 0.0, 1.0);
    vec4 ray_dir_ws = view_to_world * (clip_to_view * ray_dir_cs);
    vec3 v = -normalize(ray_dir_ws.xyz);

    Ray r;
    r.o = ray_origin_ws.xyz;
    r.d = -v;

	vec4 col = vec4(r.d * 0.5 + 0.5, 1.0) * 0.5;

#if 0
    for (uint i = 26 + pix.x % 13; i < 128 * 256; i += 64) {
        BvhNode node = bvh_nodes[i];
        bool intersects_box = intersect_ray_aabb(r, node.box_min.xyz, node.box_max.xyz);

        if (intersects_box) {
            col += 0.3;
        }
    }
#else
    uint node_idx = 0;
    {
        vec3 absdir = abs(r.d);
        float maxcomp = max(absdir.x, max(absdir.y, absdir.z));
        if (absdir.x == maxcomp) {
            node_idx = r.d.x > 0.0 ? 0 : 1;
        } else if (absdir.y == maxcomp) {
            node_idx = r.d.y > 0.0 ? 2 : 3;
        } else if (absdir.z == maxcomp) {
            node_idx = r.d.z > 0.0 ? 4 : 5;
        }
        node_idx *= bvh_node_count;
    }

    uint end_idx = node_idx + bvh_node_count;
    
    float tmin = 1.0e10;

    uint iter = 0;
    for (; iter < 1024 && node_idx < end_idx; ++iter) {
        BvhNode node = bvh_nodes[node_idx];
        float t = 0;
        bool intersects_box = intersect_ray_aabb(r, node.box_min.xyz, node.box_max.xyz, t) && t < tmin;

        uint miss_offset = floatBitsToUint(node.box_min.w);
        bool is_leaf = floatBitsToUint(node.box_max.w) != 0;

        if (intersects_box) {
            tmin = is_leaf ? t : tmin;
        }

        if (is_leaf || intersects_box) {
            node_idx += 1;
        } else {
            node_idx += miss_offset;
        }
    }
#endif

    if (tmin != 1.0e10) {
        col = (max(0.0, tmin - 100.0) * 0.004).xxxx;
    }

    col.r = iter * 0.01;
    col.a = 1;

    //col = vec4(uv, 0, 1);

    //vec4 col = vec4(uv, 0.1, 1);
	imageStore(outputTex, pix, col);
}
