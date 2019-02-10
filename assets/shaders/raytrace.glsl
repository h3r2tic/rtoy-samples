#include "inc/uv.inc"
#include "inc/rt.inc"

uniform restrict writeonly image2D outputTex;
uniform vec4 outputTex_size;

layout(std430) buffer constants {
    mat4 clip_to_view;
    mat4 view_to_world;
};

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
        r.o -= r.d * 1e-4 * length(r.o);
        r.d = l;
        bool shadowed = raytrace(r, hit);
        //iter = hit.debug_iter_count;

		const float ambient = 0.1;

        col.rgb = ndotl.xxx * 0.8 * (shadowed ? 0.0 : 1.0) + mix(normal * 0.5 + 0.5, 0.5.xxx, 0.5.xxx) * ambient;

        //col.rgb *= 0.1;
    }

    //col.r = hit.debug_iter_count * 0.01;
    col.a = 1;

	imageStore(outputTex, pix, col);
}
