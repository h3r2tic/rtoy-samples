#extension GL_ARB_bindless_texture : require
#include "inc/pack_unpack.inc"

layout(location = 0) out vec4 out_color;

layout(std430) buffer constants {
    mat4 view_to_clip;
    mat4 clip_to_view;
    mat4 world_to_view;
    mat4 view_to_world;
};

struct Material {
    uvec2 normal_map;
    uvec2 spec_map;
};

layout(std430) buffer mesh_materials_buf {
    Material materials[];
};

in vec3 v_normal;
in vec3 v_tangent;
in vec3 v_bitangent;
in vec3 v_world_position;
in vec4 v_clip_position;
in vec2 v_uv;
flat in uint v_material_id;

//uniform sampler2D metallicRoughnessTex;
//uniform sampler2D normalTex;

void main() {
    Material material = materials[v_material_id];

    sampler2D normalTex = sampler2D(material.normal_map);
    sampler2D metallicRoughnessTex = sampler2D(material.spec_map);

    //vec2 uv = v_uv * vec2(1, -1) + vec2(0, 1);
    vec2 uv = v_uv * vec2(1, -1) + vec2(0, 1);
    vec4 metallicRoughness = texture2D(metallicRoughnessTex, uv);
    vec3 ts_normal = (texture2D(normalTex, uv).xyz * 2.0 - 1.0);

    float z_over_w = v_clip_position.z / v_clip_position.w;
    //float roughness = 0.25;
    //float roughness = 0.08 + pow(fract(v_world_position.z * 0.03), 2.0) * 0.3;

    // TODO: add BRDF sampling, reduce the lower clamp
    //float roughness = 0.4;
    float roughness = clamp(metallicRoughness.y, 0.1, 0.9);
    float metallic = 1;//metallicRoughness.z;

    mat3 tbn = mat3(v_tangent, v_bitangent, v_normal);
    
    //ts_normal = vec3(0, 0, 1);
    //roughness = float(v_material_id) * 0.2;

    vec4 res = 0.0.xxxx;
    res.x = pack_normal_11_10_11(normalize(tbn * ts_normal));
    res.y = roughness * roughness;      // UE4 remap
    res.z = metallic;
    //res.z = v_material_id;
    res.w = z_over_w;
    out_color = res;
}
