uniform restrict writeonly layout(binding = 0) image2D outputTex;
uniform layout(binding = 1) texture2D inputImage;

layout(std140, binding = 2) uniform globals {
    ivec2 blurDir;
    int blurRadius;
};

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
	vec4 col = texelFetch(inputImage, pix, 0);
	for (int i = 1; i <= blurRadius; ++i) {
		col += texelFetch(inputImage, pix + blurDir * i, 0);
		col += texelFetch(inputImage, pix - blurDir * i, 0);
	}
	col *= 1.0 / (1 + 2 * blurRadius);
	imageStore(outputTex, pix, col);
}
