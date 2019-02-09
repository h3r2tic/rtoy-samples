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
    vec3 box_min;
    uint exit_idx;
    vec3 box_max;
    uint prim_id;
};

layout(std430) buffer bvh {
    BvhNode bvh_nodes[];
};

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

layout(std430) buffer triangles {
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
    const bool cull_backface = true;

    if ((cull_backface && det > 1e-10) || !cull_backface)
    {
    	vec3 tv = r.o - tri.v;
    	vec3 qv = cross(tv, tri.e0);

    	vec4 uvt;
    	uvt.x = dot(tv, pv);
    	uvt.y = dot(r.d, qv);
    	uvt.z = dot(tri.e1, qv);
    	uvt.xyz = uvt.xyz / det;
    	uvt.w = 1.0 - uvt.x - uvt.y;

        float barycentric_eps = -1e-4;

    	if (all(greaterThanEqual(uvt, vec4(barycentric_eps.xxx, 0.0))) && uvt.z < t)
    	{
    		barycentric = uvt.ywx;
            t = uvt.z;
            return true;
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
    uint hit_tri = 0xffffffff;

    uint iter = 0;
    for (; iter < 1024 && node_idx < end_idx; ++iter) {
        BvhNode node = bvh_nodes[node_idx];
        bool intersects_box = intersect_ray_aabb(r, node.box_min, node.box_max, tmin);

        bool is_leaf = node.prim_id != 0xffffffff;

        if (intersects_box && is_leaf) {
            if (intersect_ray_tri(r, unpack_triangle(bvh_triangles[node.prim_id]), tmin, barycentric)) {
                hit_tri = node.prim_id;
            }
        }

        if (is_leaf || intersects_box) {
            node_idx += 1;
        } else {
            node_idx += node.exit_idx;
        }
    }

    hit.debug_iter_count = iter;

    if (hit_tri != 0xffffffff) {
        hit.t = tmin;
        hit.barycentric = barycentric;
        hit.tri_idx = hit_tri;
        return true;
    }

    return false;
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

    RtHit hit;
    if (raytrace(r, hit)) {
        Triangle tri = unpack_triangle(bvh_triangles[hit.tri_idx]);
        vec3 normal = normalize(cross(tri.e0, tri.e1));
        vec3 l = normalize(vec3(1, 1, -1));
        float ndotl = max(0.0, dot(normal, l));
        uint iter = hit.debug_iter_count;

        r.o += r.d * hit.t;
        r.o -= r.d * 1e-6 * length(r.o);
        r.d = l;
        bool shadowed = raytrace(r, hit);
        //iter = hit.debug_iter_count;

        col.rgb = ndotl.xxx * (shadowed ? 0.0 : 1.0) + 0.02;

        //col.rgb *= 0.1;
        //col.r = iter * 0.01;
    }

    col.a = 1;

	imageStore(outputTex, pix, col);
}
