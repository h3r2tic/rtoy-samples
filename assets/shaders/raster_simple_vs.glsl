#include "rendertoy::shaders/view_constants.inc"
#include "inc/mesh_vertex.inc"

layout(std430) buffer constants {
    ViewConstants view_constants;
};

layout(std430) buffer mesh_vertex_buf {
    VertexPacked vertices[];
};

layout(std430) buffer mesh_uv_buf {
    vec2 uvs[];
};

layout(std430) buffer mesh_tangent_buf {
    vec4 tangents[];
};

layout(std430) buffer mesh_material_id_buf {
    uint material_ids[];
};

layout(std430) buffer instance_transform {
    mat4 model_to_world;
};

out vec3 v_normal;
out vec3 v_tangent;
out vec3 v_bitangent;
out vec3 v_world_position;
out vec4 v_clip_position;
out vec2 v_uv;
flat out uint v_material_id;

void main() {
    Vertex vertex = unpack_vertex(vertices[gl_VertexID]);
    v_normal = (model_to_world * vec4(vertex.normal, 0.0)).xyz;
	vec3 world_position = (model_to_world * vec4(vertex.position, 1.0)).xyz;
    v_world_position = world_position;

    vec4 tangents_packed = tangents[gl_VertexID];
    vec3 tangent = tangents_packed.xyz;
    vec3 bitangent = normalize(cross(vertex.normal, tangent) * tangents_packed.w);

    vec4 clip_position = view_constants.view_to_sample * view_constants.world_to_view * vec4(world_position, 1.0);
    v_clip_position = clip_position;
	gl_Position = clip_position;

    v_uv = uvs[gl_VertexID];
    v_tangent = tangent;
    v_bitangent = bitangent;
    v_material_id = material_ids[gl_VertexID];
}
