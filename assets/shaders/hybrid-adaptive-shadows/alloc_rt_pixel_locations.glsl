layout (local_size_x = 8, local_size_y = 8) in;

uniform texture2D discontinuityTex;
uniform texture2D tileAllocOffsetTex;
uniform layout(rg32f) restrict writeonly image2D outputTex;

layout(std140) uniform globals {
    uniform vec4 outputTex_size;
};

shared uint alloc_count;

void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    ivec2 tile_pix = pix >> 3;

    if (gl_LocalInvocationIndex == 0) {
        alloc_count = 0;
    }

    barrier();

    uint outputTexWidth = uint(outputTex_size.x);

    float discontinuity = texelFetch(discontinuityTex, pix, 0).r;
    if (discontinuity > 0.0) {
        uint tile_prefix_val = floatBitsToUint(texelFetch(tileAllocOffsetTex, tile_pix, 0).x);
        uint index_within_tile = atomicAdd(alloc_count, 1);
        uint pixel_alloc_slot = tile_prefix_val + index_within_tile;
        ivec2 pixel_alloc_px = ivec2(pixel_alloc_slot % outputTexWidth, pixel_alloc_slot / outputTexWidth);

    	imageStore(outputTex, pixel_alloc_px, vec4(intBitsToFloat(pix), 0, 0));
    }
}
