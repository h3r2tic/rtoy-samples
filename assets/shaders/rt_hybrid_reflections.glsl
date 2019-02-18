#include "rendertoy::shaders/random.inc"
#include "rendertoy::shaders/sampling.inc"
#include "rtoy-rt::shaders/rt.inc"
#include "inc/uv.inc"
#include "inc/mesh_vertex.inc"

uniform sampler2D inputTex;

uniform restrict writeonly image2D outputTex;
uniform vec4 outputTex_size;

layout(std430) buffer constants {
    mat4 view_to_clip;
    mat4 clip_to_view;
    mat4 world_to_view;
    mat4 view_to_world;
};

layout(std430) buffer mesh_vertex_buf {
    VertexPacked vertices[];
};

vec3 diffuse_at_normal(vec3 n) {
    return 0.3 + max(0.0, dot(n, normalize(vec3(1, 1, -1)))).xxx;
}

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
    ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    vec2 uv = get_uv(outputTex_size);
    vec4 gbuffer = texelFetch(inputTex, pix, 0);

    vec3 normal = gbuffer.xyz;
    vec4 col = vec4(0.0.xxx, 1);

    vec4 ray_dir_cs = vec4(uv_to_cs(uv), 0.0, 1.0);
    vec4 ray_dir_ws = view_to_world * (clip_to_view * ray_dir_cs);
    vec3 v = -normalize(ray_dir_ws.xyz);

    const float albedo_scale = 0.04;

    if (gbuffer.a != 0.0) {
        vec4 ray_origin_cs = vec4(uv_to_cs(uv), gbuffer.w, 1.0);
        vec4 ray_origin_vs = clip_to_view * ray_origin_cs;
        vec4 ray_origin_ws = view_to_world * ray_origin_vs;
        ray_origin_ws /= ray_origin_ws.w;

        float ndotv = dot(normal, v);

        Ray r;
        r.d = reflect(-v, normal);
        r.o = ray_origin_ws.xyz;
        r.o += (v + r.d) * (1e-4 * max(length(r.o), abs(ray_origin_vs.z / ray_origin_vs.w)));

        vec3 refl_col = r.d * 0.5 + 0.5;

        RtHit hit;
        if (raytrace(r, hit)) {
            Triangle tri = unpack_triangle(bvh_triangles[hit.tri_idx]);
            vec3 hit_normal = normalize(cross(tri.e0, tri.e1));
            refl_col = diffuse_at_normal(hit_normal) * albedo_scale;
        }

        float schlick = 1.0 - abs(ndotv);
        schlick *= schlick * schlick * schlick * schlick;
        float fresnel = mix(0.04, 1.0, schlick);

        col.rgb += refl_col * fresnel;
        col.rgb += diffuse_at_normal(gbuffer.xyz) * (1.0 - fresnel) * albedo_scale;
    } else {
        col.rgb = -v * 0.5 + 0.5;
    }

    imageStore(outputTex, pix, col);
}
