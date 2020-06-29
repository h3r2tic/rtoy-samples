#include "inc/pack_unpack.inc"

uint pack_color(vec3 color) {
    return float3_to_rgb9e5(color);
}

vec3 unpack_color(uint pck) {
    return rgb9e5_to_float3(pck);
}

struct UnpackedSample {
    vec3 color;
    float depth;
    float p;
};

UnpackedSample unpack_oit(uvec2 pck) {
    UnpackedSample res;
    res.color = unpack_color(pck.x);
    vec2 depth_p = unpackHalf2x16(pck.y);
    res.depth = depth_p.x;
    res.p = depth_p.y;
    return res;
}

uint pack_oit_depth_p(float depth, float p) {
    return packHalf2x16(vec2(depth, p));
}

uvec2 pack_oit(vec3 color, float depth, float p) {
    return uvec2(pack_color(color), pack_oit_depth_p(depth, p));
}
