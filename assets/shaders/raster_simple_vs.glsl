layout(std430) buffer constants {
    mat4 view_to_clip;
    mat4 clip_to_view;
    mat4 world_to_view;
    mat4 view_to_world;
};

struct VertexPacked {
	vec4 data0;
};

struct Vertex {
    vec3 position;
    vec3 normal;
};

vec3 unpack_unit_direction_11_10_11(uint pck)
{
    return vec3(
        float(pck & ((1u << 11u)-1u)) * (2.0f / float((1u << 11u)-1u)) - 1.0f,
        float((pck >> 11u) & ((1u << 10u)-1u)) * (2.0f / float((1u << 10u)-1u)) - 1.0f,
        float((pck >> 21u)) * (2.0f / float((1u << 11u)-1u)) - 1.0f
    );
}

Vertex unpack_vertex(VertexPacked p) {
    Vertex res;
    res.position = p.data0.xyz;
    res.normal = unpack_unit_direction_11_10_11(floatBitsToUint(p.data0.w));
    return res;
}

layout(std430) buffer mesh_vertex_buf {
    VertexPacked vertices[];
};

out vec3 v_normal;

void main() {
    Vertex vertex = unpack_vertex(vertices[gl_VertexID]);
    v_normal = vertex.normal;
	vec3 world_position = vertex.position;
	gl_Position = view_to_clip * world_to_view * vec4(world_position, 1.0);
}
