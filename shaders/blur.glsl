uniform restrict writeonly image2D outputTex;
uniform int blurRadius;
uniform ivec2 blurDir;
layout(rgba16f) uniform restrict readonly image2D inputImage;

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
	vec4 col = imageLoad(inputImage, pix);
	for (int i = 1; i <= blurRadius; ++i) {
		col += imageLoad(inputImage, pix + blurDir * i);
		col += imageLoad(inputImage, pix - blurDir * i);
	}
	col *= 1.0 / (1 + 2 * blurRadius);
	imageStore(outputTex, pix, col);
}
