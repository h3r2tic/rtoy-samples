uniform restrict writeonly image2D outputTex;
uniform sampler2D finalTex;
uniform sampler2D ssgiTex;
uniform vec4 outputTex_size;

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
	vec2 uv = (vec2(pix) + 0.5) * outputTex_size.zw;

	vec4 a = textureLod(finalTex, uv, 0);
	vec4 b = textureLod(ssgiTex, uv, 0);
    vec4 c = a;
    //vec4 c = 1.0 - clamp(b, 0.0, 1.0).aaaa;
    //vec4 c = b.aaaa;
    //vec4 c = vec4(b.rgb * (1.0 - clamp(b.a, 0.0, 1.0)), 1);

	imageStore(outputTex, pix, c);
}
