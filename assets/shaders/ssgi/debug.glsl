uniform restrict writeonly image2D outputTex;
uniform texture2D finalTex;
uniform texture2D ssgiTex;
uniform sampler linear_sampler;

layout(std140) uniform globals {
    vec4 outputTex_size;
};

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
	vec2 uv = (vec2(pix) + 0.5) * outputTex_size.zw;

	vec4 a = textureLod(sampler2D(finalTex, linear_sampler), uv, 0);
	vec4 b = textureLod(sampler2D(ssgiTex, linear_sampler), uv, 0);
    vec4 c = a;
    //vec4 c = 1.0 - clamp(b, 0.0, 1.0).aaaa;
    //vec4 c = max(0.0.xxxx, b.aaaa - 0.8) + b.aaaa * 0.03;
    //c = 1 - b.aaaa;
    //vec4 c = smoothstep(0.6, 1.5, b).aaaa;
    //c = vec4(b.rgb * (1.0 - clamp(b.a, 0.0, 1.0)), 1);
    //c.rgb += 0.1;

    //c = pow(c, 30.0.xxxx);

	imageStore(outputTex, pix, c);
}
