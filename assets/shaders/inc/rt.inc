#define INVALID_TRIANGLE_INDEX 0xffffff

struct PackedBvhNode {
    uint data[4];
};

struct BvhNode {
    vec3 box_min;
    uint exit_idx;
    vec3 box_max;
    uint prim_idx;
};

#define RGB9E5_EXPONENT_BITS 5
#define RGB9E5_MANTISSA_BITS 9
#define RGB9E5_EXP_BIAS 15

// https://www.khronos.org/registry/OpenGL/extensions/EXT/EXT_texture_shared_exponent.txt
vec3 rgb9e5_to_float3(uint v) {
    uint biasedexponent = v & ((1u << RGB9E5_EXPONENT_BITS) - 1u);
    int exponent = int(biasedexponent) - RGB9E5_EXP_BIAS - RGB9E5_MANTISSA_BITS;
    float scale = exp2(exponent);

    const uint MANTISSA_MASK = ((1u << RGB9E5_MANTISSA_BITS) - 1u);

    uint r = v >> (32 - 9);
    uint g = (v >> (32 - 9 * 2)) & MANTISSA_MASK;
    uint b = (v >> (32 - 9 * 3)) & MANTISSA_MASK;

    return vec3(r * scale, g * scale, b * scale);
}

BvhNode unpack_bvh_node(PackedBvhNode node) {
    vec3 box_extent = rgb9e5_to_float3(node.data[0]);

    BvhNode res;
    res.box_min.xy = unpackHalf2x16(node.data[1]).yx;
    res.box_min.z = unpackHalf2x16(node.data[2]).y;
    res.box_max = res.box_min + box_extent;
    res.prim_idx = ((node.data[2] & 0xffffu) << 8u) | (node.data[3] >> 24u);
    res.exit_idx = node.data[3] & 0xffffffu;
    return res;
}

struct PackedTriangle {
    float data[9];
};

struct Triangle {
    vec3 v;
    vec3 e0;
    vec3 e1;
};

Triangle unpack_triangle(PackedTriangle tri) {
    Triangle res;
    res.v = vec3(tri.data[0], tri.data[1], tri.data[2]);
    res.e0 = vec3(tri.data[3], tri.data[4], tri.data[5]);
    res.e1 = vec3(tri.data[6], tri.data[7], tri.data[8]);
    return res;
}

layout(std430) buffer bvh_meta_buf {
    uint bvh_node_count;
};

layout(std430) buffer bvh_nodes_buf {
    PackedBvhNode bvh_nodes[];
};

layout(std430) buffer bvh_triangles_buf {
    PackedTriangle bvh_triangles[];
};

struct Ray {
	vec3 o;
	vec3 d;
};

// From https://github.com/tigrazone/glslppm
bool intersect_ray_tri(Ray r, Triangle tri, inout float t, inout vec3 barycentric) {
    vec3 pv = cross(r.d, tri.e1);
    float det = dot(tri.e0, pv);

    const bool cull_backface = false;

    if ((cull_backface && det > 1e-10) || !cull_backface)
    {
    	vec3 tv = r.o - tri.v;
    	vec3 qv = cross(tv, tri.e0);

        float hit_t = dot(tri.e1, qv) / det;
        if (hit_t >= 0.0 && hit_t < t) {
        	vec3 uvw;
        	uvw.x = dot(tv, pv);
        	uvw.y = dot(r.d, qv);
        	uvw.xy = uvw.xy / det;
        	uvw.z = 1.0 - uvw.x - uvw.y;

            float barycentric_eps = -1e-4;

        	if (all(greaterThanEqual(uvw, vec3(barycentric_eps.xxx))))
    	    {
    		    barycentric = uvw.yzx;
                t = hit_t;
                return true;
    	    }
        }
    }

    return false;
}

// From https://github.com/tigrazone/glslppm
bool intersect_ray_aabb(Ray r, vec3 pmin, vec3 pmax, float t)
{
	vec3 min_interval = (pmax.xyz - r.o.xyz) / r.d;
	vec3 max_interval = (pmin.xyz - r.o.xyz) / r.d;

	vec3 a = min(min_interval, max_interval);
	vec3 b = max(min_interval, max_interval);

    float tmin = max(max(a.x, a.y), a.z);
    float tmax = min(min(b.x, b.y), b.z);

    return tmin <= tmax && tmin < t && tmax >= 0.0;
}

struct RtHit {
    float t;
    vec3 barycentric;
    uint tri_idx;
    uint debug_iter_count;
};

bool raytrace(Ray r, inout RtHit hit) {
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
    vec3 barycentric;
    uint hit_tri = INVALID_TRIANGLE_INDEX;

    uint iter = 0;
    for (; iter < 1024 && node_idx < end_idx; ++iter) {
        BvhNode node = unpack_bvh_node(bvh_nodes[node_idx]);
        bool intersects_box = intersect_ray_aabb(r, node.box_min, node.box_max, tmin);

        bool is_leaf = node.prim_idx != INVALID_TRIANGLE_INDEX;

        if (intersects_box && is_leaf) {
            if (intersect_ray_tri(r, unpack_triangle(bvh_triangles[node.prim_idx]), tmin, barycentric)) {
                hit_tri = node.prim_idx;
            }
        }

        if (is_leaf || intersects_box) {
            node_idx += 1;
        } else {
            node_idx += node.exit_idx;
        }
    }

    hit.debug_iter_count = iter;

    if (hit_tri != INVALID_TRIANGLE_INDEX) {
        hit.t = tmin;
        hit.barycentric = barycentric;
        hit.tri_idx = hit_tri;
        return true;
    }

    return false;
}
