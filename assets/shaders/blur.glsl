uniform restrict writeonly image2D outputTex;
uniform int blurRadius;
uniform ivec2 blurDir;
uniform sampler2D inputImage;

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
