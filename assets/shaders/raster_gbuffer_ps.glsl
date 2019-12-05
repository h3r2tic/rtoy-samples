#extension GL_EXT_nonuniform_qualifier: require
#include "rendertoy::shaders/bindless.inc"
#include "inc/pack_unpack.inc"

layout(location = 0) out vec4 out_color;

struct Material {
    float base_color_mult[4];
    uint normal_map;
    uint spec_map;
    uint albedo_map;
    uint pad;
};

vec4 array_to_vec4(float v[4]) {
    return vec4(v[0], v[1], v[2], v[3]);
}

layout(std430) buffer mesh_materials_buf {
    Material materials[];
};

uniform sampler linear_sampler;

layout(location = 0) in vec3 v_normal;
layout(location = 1) in vec4 v_color;
layout(location = 2) in vec3 v_tangent;
layout(location = 3) in vec3 v_bitangent;
layout(location = 4) in vec3 v_world_position;
layout(location = 5) in vec4 v_clip_position;
layout(location = 6) in vec2 v_uv;
layout(location = 7) flat in uint v_material_id;


//uniform sampler2D metallicRoughnessTex;
//uniform sampler2D normalTex;

void real_main(
    Material material,
    texture2D normalTex,
    texture2D metallicRoughnessTex,
    texture2D albedoTex
) {
    vec2 uv = v_uv;
    vec4 metallicRoughness = texture(sampler2D(metallicRoughnessTex, linear_sampler), uv);
    vec3 ts_normal = (texture(sampler2D(normalTex, linear_sampler), uv).xyz * 2.0 - 1.0);

    float z_over_w = v_clip_position.z / v_clip_position.w;
    //float roughness = 0.25;
    //float roughness = 0.08 + pow(fract(v_world_position.z * 0.03), 2.0) * 0.3;

    // TODO: add BRDF sampling, reduce the lower clamp
    //float roughness = 0.4;
    float roughness = clamp(metallicRoughness.y, 0.1, 0.9);
    float metallic = 1;//metallicRoughness.z;

    vec3 normal = v_normal;
    if (dot(v_bitangent, v_bitangent) > 0.0) {
        mat3 tbn = mat3(v_tangent, v_bitangent, v_normal);
        normal = tbn * ts_normal;
    }
    normal = normalize(normal);

    vec3 albedo =
        texture(sampler2D(albedoTex, linear_sampler), uv).rgb *
        clamp(v_color.rgb, 0.0.xxx, 1.0.xxx) *
        array_to_vec4(material.base_color_mult).rgb;
    
    //ts_normal = vec3(0, 0, 1);
    //roughness = float(v_material_id) * 0.2;

    vec4 res = 0.0.xxxx;
    res.x = pack_normal_11_10_11(normal);
    res.y = roughness * roughness;      // UE4 remap
    //res.z = metallic;
    res.z = uintBitsToFloat(pack_color_888(albedo));
    //res.z = v_material_id;
    res.w = z_over_w;
    out_color = res;
}

void main() {
    Material material = materials[v_material_id];
    real_main(
        material,
        all_textures[nonuniformEXT(material.normal_map)],
        all_textures[nonuniformEXT(material.spec_map)],
        all_textures[nonuniformEXT(material.albedo_map)]
    );
}
