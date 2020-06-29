uniform restrict writeonly layout(binding = 0) image2D outputTex;
uniform layout(binding = 1) texture2D inputTex1;
uniform layout(binding = 2) texture2D inputTex2;

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
    float blendAmount = 0.5;

	vec4 a = texelFetch(inputTex1, pix, 0);
	vec4 b = texelFetch(inputTex2, pix, 0);
    vec4 c = a * 0.5 + b * 0.5;
    //vec4 c = abs(a - b);
    //c = a;
    imageStore(outputTex, pix, c);
}
