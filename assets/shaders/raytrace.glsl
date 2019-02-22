#include "rendertoy::shaders/random.inc"
#include "rendertoy::shaders/sampling.inc"
#include "rtoy-rt::shaders/rt.inc"
#include "inc/uv.inc"

uniform restrict writeonly image2D outputTex;
uniform vec4 outputTex_size;

layout(std430) buffer constants {
    uint frame_idx;
    uint pad[3];
    mat4 view_to_clip;
    mat4 clip_to_view;
    mat4 world_to_view;
    mat4 view_to_world;
};

vec3 sample_environment_light(vec3 dir) {
    dir = normalize(dir);
    vec3 col = (dir.zyx * vec3(1, 1, -1) * 0.5 + vec3(0.6, 0.5, 0.5)) * 0.75;
    col = mix(col, 1.3 * dot(col, vec3(0.2, 0.7, 0.1)).xxx, smoothstep(0.3, 0.8, col.g).xxx);
    return col;
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

    const float direct_light_amount = 1.25;

    vec4 col = vec4(sample_environment_light(r.d), 1.0);

    RtHit hit;
    if (raytrace(r, hit)) {
        Triangle tri = unpack_triangle(bvh_triangles[hit.tri_idx]);
        vec3 normal = normalize(cross(tri.e0, tri.e1));

        // Pick a light direction
        vec3 l = normalize(vec3(1, -1, -1));

        // Randomize light direction within a cone for soft shadows
        {
            vec3 t0 = normalize(build_orthonormal_basis(l));
            vec3 t1 = cross(t0, l);

            // Angular diameter of sun is 0.5 degrees, tangent of half that is ~0.0043
            // Scale up as an artistic license to account for scattering in the sky
            const float cone_angle_tan = 0.0043 * 1.5;

            uint seed0 = hash(hash(frame_idx ^ hash(pix.x)) ^ pix.y);
            uint seed1 = hash(seed0);
            float theta = rand_float(seed0) * 6.28318530718;
            float r = cone_angle_tan * sqrt(rand_float(seed1));
            l += r * t0 * cos(theta) + r * t1 * sin(theta);

            l = normalize(l);
        }

        float ndotl = max(0.0, dot(normal, l));
        uint iter = hit.debug_iter_count;

        vec3 hit_pos = r.o + r.d * hit.t;
        hit_pos -= r.d * 1e-4 * length(hit_pos);

        bool shadowed = true;
        if (ndotl > 0.0) {
            r.o = hit_pos;
            r.d = l;

            shadowed = raytrace_intersects_any(r);
        }

        float diffuse_albedo = 0.7;
        vec3 ambient = 0.0.xxx;

        {
            uint seed0 = hash(hash(frame_idx ^ hash(pix.x) ^ 19329) ^ pix.y);
            uint seed1 = hash(seed0);
            vec3 sr = uniform_sample_sphere(vec2(rand_float(seed0), rand_float(seed1)));
            vec3 ao_dir = normal + sr;
            r.o = hit_pos;
            r.d = ao_dir;

            if (!raytrace_intersects_any(r)) {
                ambient += sample_environment_light(ao_dir);
            }
        }

        col.rgb = (direct_light_amount * ndotl.xxx * (shadowed ? 0.0 : 1.0) + ambient) * diffuse_albedo;
    }

    {
        uint seed0 = hash(hash(pix.x) ^ pix.y);
        float rnd = rand_float(seed0);
        col.rgb += (rnd - 0.5) / 256.0;
    }

    //col.r = hit.debug_iter_count * 0.01;
    col.a = 1;

    imageStore(outputTex, pix, col);
}
