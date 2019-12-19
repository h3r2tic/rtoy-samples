uniform texture2D inputTex;
uniform restrict writeonly image2D outputTex;

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
	vec3 col = texelFetch(inputTex, pix, 0).rgb;
    //float luminance = clamp(dot(vec3(0.2126, 0.7152, 0.0722), col), 1e-8, 1e8);
    //float luminance = clamp(dot(vec3(0.2126, 0.7152, 0.0722), col), 0.1, 2.0);
    float luminance = clamp(dot(vec3(0.2126, 0.7152, 0.0722), col), 0.3, 1e8);
	imageStore(outputTex, pix, vec4(log(luminance), luminance, 0, 0));
}
