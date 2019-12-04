uniform texture2D inputTex;
uniform restrict writeonly image2D outputTex;

layout(std140) uniform globals {
    vec4 inputTex_size;
    vec4 outputTex_size;
};

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    ivec2 src_pix = pix * ivec2((inputTex_size.xy + 1.0) / outputTex_size.xy);
	float depth = texelFetch(inputTex, src_pix, 0).w;
	imageStore(outputTex, pix, depth.xxxx);
}
