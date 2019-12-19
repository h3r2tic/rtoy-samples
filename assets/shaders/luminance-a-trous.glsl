uniform texture2D inputTex;
uniform texture2D origInputTex;
uniform restrict writeonly image2D outputTex;

layout(std140, binding = 1) uniform globals {
    int px_skip;
    vec4 inputTex_size;
};


const float gaussian_weights[5] = float[](
    1.0 / 16.0,
    1.0 / 4.0,
    3.0 / 8.0,
    1.0 / 4.0,
    1.0 / 16.0
);

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
    ivec2 tex_dim = ivec2(inputTex_size.xy);
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    float center = texelFetch(origInputTex, pix, 0).x;
    //float center = texelFetch(inputTex, pix, 0).r;
	vec3 result = 0.0.xxx;
    for (int y = 0; y < 5; ++y) {
        for (int x = 0; x < 5; ++x) {
            ivec2 offset = ivec2(x - 2, y - 2) * px_skip;
            ivec2 loc = pix + offset;
            if (loc.x >= 0 && loc.y >= 0 && loc.x < tex_dim.x && loc.y < tex_dim.y)
            {
                vec2 val = texelFetch(inputTex, loc, 0).xy;
                float orig_val = texelFetch(origInputTex, loc, 0).x;
                float w = 1;
                //w *= exp2(-(val - center) * (val - center) * 0.08 * (1.0 + log2(float(px_skip))));
                //w *= exp2(-(orig_val - center) * (orig_val - center) * 0.1 * (1.0 + log2(float(px_skip))));
                //w *= exp2(-(val - center) * (val - center) * 0.5);
                float diff = orig_val - center;
                w *= exp2(-diff * diff * 0.4);
                //w *= gaussian_weights[x] * gaussian_weights[y];
                w *= exp2(-dot(offset, offset) / (80 * 80));
                result += vec3(val, 1) * w;
            }
        }
    }
    result.xy /= result.z;
	imageStore(outputTex, pix, result.xyyy);
}
