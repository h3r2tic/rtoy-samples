#include "inc/mesh_vertex.inc"

layout(std430) buffer constants {
    mat4 view_to_clip;
    mat4 clip_to_view;
    mat4 world_to_view;
    mat4 view_to_world;
};

layout(std430) buffer mesh_vertex_buf {
    VertexPacked vertices[];
};

out vec3 v_normal;
out vec3 v_world_position;
out vec4 v_clip_position;

void main() {
    Vertex vertex = unpack_vertex(vertices[gl_VertexID]);
    v_normal = vertex.normal;
	vec3 world_position = vertex.position;
    v_world_position = world_position;

    vec4 clip_position = view_to_clip * world_to_view * vec4(world_position, 1.0);
    v_clip_position = clip_position;
	gl_Position = clip_position;
}
