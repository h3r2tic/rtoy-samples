uniform restrict writeonly layout(binding = 0) uimage2D outputTex;

uvec2 pack_color(vec3 color) {
    return uvec2(packHalf2x16(color.rg), floatBitsToUint(color.b));
}

vec3 unpack_color(uvec2 packed) {
    return vec3(unpackHalf2x16(packed.x), uintBitsToFloat(packed.y));
}

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
	imageStore(outputTex, pix, uvec4(pack_color(0.0.xxx), floatBitsToUint(0.0), floatBitsToUint(0.0)));
}
