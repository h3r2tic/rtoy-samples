uniform restrict writeonly image2D outputTex;
uniform sampler2D inputTex1;
uniform sampler2D inputTex2;
uniform float blendAmount;
uniform vec4 outputTex_size;

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
	vec2 uv = (vec2(pix) + 0.5) * outputTex_size.zw;

	vec4 a = textureLod(inputTex1, uv, 0);
	vec4 b = textureLod(inputTex2, uv, 0);
    vec4 c = b * blendAmount;
    if (blendAmount != 1.0) {
        c += a * (1.0 - blendAmount);
    }

	imageStore(outputTex, pix, c);
}
