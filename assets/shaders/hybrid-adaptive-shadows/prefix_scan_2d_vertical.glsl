layout (local_size_x = 1, local_size_y = 512) in;

uniform texture2D inputTex;
layout(std140) uniform globals {
    vec4 inputTex_size;
};
uniform restrict writeonly image2D outputTex;

shared uint shared_data[gl_WorkGroupSize.y * 2];

uint align64(uint a) {
	return (a + 63u) & ~63u;
}

uint load_input(uint x, uint y) {
    return floatBitsToUint(texelFetch(inputTex, ivec2(x, y), 0).x);
}

void store_output(uint x, uint y, uint val) {
    imageStore(outputTex, ivec2(x, y), vec4(uintBitsToFloat(val)));
}

void main() {
    uint id = gl_LocalInvocationID.y;
    uint input_slice = uint(inputTex_size.x) - 1;
    uint rd_id;
    uint wr_id;
    uint mask;

    const uint steps = uint(log2(gl_WorkGroupSize.y)) + 1;
    uint step = 0;

    shared_data[id * 2] = id > 0 ? load_input(input_slice, id * 2 - 1) : 0;
    shared_data[id * 2 + 1]	= load_input(input_slice, id * 2);

    barrier();

    for (step = 0; step < steps; step++)
    {
        mask = (1 << step) - 1;
        rd_id = ((id >> step) << (step + 1)) + mask;
        wr_id = rd_id + 1 + (id & mask);

        shared_data[wr_id] += shared_data[rd_id];

        barrier();
    }

    store_output(0, id * 2, shared_data[id * 2]);
    store_output(0, id * 2 + 1, shared_data[id * 2 + 1]);
}
