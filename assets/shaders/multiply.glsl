uniform float factor;
uniform sampler2D inputTex;

uniform restrict writeonly image2D outputTex;
uniform vec4 outputTex_size;

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
	vec2 uv = (vec2(pix) + 0.5) * outputTex_size.zw;
    vec4 col = textureLod(inputTex, uv, 0);
	col.rgb *= factor;
	imageStore(outputTex, pix, col);
}
