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
    out_color = vec4(v_normal, z_over_w);
}
