#include "inc/pack_unpack.inc"

layout(location = 0) out vec4 out_color;

layout(std430) buffer constants {
    mat4 view_to_clip;
    mat4 clip_to_view;
    mat4 world_to_view;
    mat4 view_to_world;
};

in vec3 v_normal;
in vec3 v_world_position;
in vec4 v_clip_position;

void main() {
    float z_over_w = v_clip_position.z / v_clip_position.w;
    float roughness = 0.2;
    //float roughness = 0.08 + pow(fract(v_world_position.z * 0.03), 2.0) * 0.3;

    vec4 res = 0.0.xxxx;
    res.x = pack_normal_11_10_11(normalize(v_normal));
    res.y = roughness;
    res.w = z_over_w;
    out_color = res;
}
