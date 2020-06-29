#include "inc/pack_unpack.inc"

uvec2 pack_color(vec3 color) {
    return uvec2(packHalf2x16(color.rg), floatBitsToUint(color.b));
    //return uvec2(float3_to_rgb9e5(color), 0);
}

vec3 unpack_color(uvec2 packed) {
    return vec3(unpackHalf2x16(packed.x), uintBitsToFloat(packed.y));
    //return rgb9e5_to_float3(packed.x);
}
