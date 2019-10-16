layout (local_size_x = 512, local_size_y = 1) in;

uniform layout(r32f) readonly image2D inputTex;
uniform restrict writeonly image2D outputTex;

shared uint shared_data[gl_WorkGroupSize.x * 2];

uint align64(uint a) {
	return (a + 63u) & ~63u;
}

uint load_input(uint x, uint y) {
    return floatBitsToUint(imageLoad(inputTex, ivec2(x, y)).x);
}

void store_output(uint x, uint y, uint val) {
    imageStore(outputTex, ivec2(x, y), vec4(uintBitsToFloat(val)));
}

void main() {
    uint id = gl_LocalInvocationID.x;
    uint slice = gl_WorkGroupID.y;
    uint rd_id;
    uint wr_id;
    uint mask;

    const uint steps = uint(log2(gl_WorkGroupSize.x)) + 1;
    uint step = 0;

    shared_data[id * 2] = id > 0 ? load_input(id * 2 - 1, slice) : 0;
    shared_data[id * 2 + 1]	= load_input(id * 2, slice);

    barrier();

    for (step = 0; step < steps; step++)
    {
        mask = (1 << step) - 1;
        rd_id = ((id >> step) << (step + 1)) + mask;
        wr_id = rd_id + 1 + (id & mask);

        shared_data[wr_id] += shared_data[rd_id];

        barrier();
    }

    store_output(id * 2, slice, shared_data[id * 2]);
    store_output(id * 2 + 1, slice, shared_data[id * 2 + 1]);
}
