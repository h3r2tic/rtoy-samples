uniform sampler2D inputTex;
uniform restrict writeonly image2D outputTex;

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
	float depth = texelFetch(inputTex, pix, 0).w;
	imageStore(outputTex, pix, depth.xxxx);
}
