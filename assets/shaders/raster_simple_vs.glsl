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

layout(std430) buffer mesh_color_buf {
    vec4 colors[];
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

layout(location = 0) out vec3 v_normal;
layout(location = 1) out vec4 v_color;
layout(location = 2) out vec3 v_tangent;
layout(location = 3) out vec3 v_bitangent;
layout(location = 4) out vec3 v_world_position;
layout(location = 5) out vec4 v_clip_position;
layout(location = 6) out vec2 v_uv;
layout(location = 7) flat out uint v_material_id;

void main() {
    Vertex vertex = unpack_vertex(vertices[gl_VertexIndex]);
    v_normal = (model_to_world * vec4(vertex.normal, 0.0)).xyz;
	vec3 world_position = (model_to_world * vec4(vertex.position, 1.0)).xyz;
    v_world_position = world_position;

    vec4 tangents_packed = tangents[gl_VertexIndex];
    vec3 tangent = tangents_packed.xyz;
    vec3 bitangent = normalize(cross(vertex.normal, tangent) * tangents_packed.w);

    vec4 clip_position = view_constants.view_to_sample * view_constants.world_to_view * vec4(world_position, 1.0);
    v_clip_position = clip_position;
	gl_Position = clip_position;

    v_uv = uvs[gl_VertexIndex];
    v_color = colors[gl_VertexIndex];
    v_tangent = tangent;
    v_bitangent = bitangent;
    v_material_id = material_ids[gl_VertexIndex];
}
