uniform restrict writeonly image2D outputTex;
uniform sampler2D g_filteredLightTex;
uniform sampler2D g_filteredSurfaceTex;
uniform vec4 outputTex_size;

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
	vec2 uv = (vec2(pix) + 0.5) * outputTex_size.zw;

	vec4 light = textureLod(g_filteredLightTex, uv, 0);
	vec4 surf = textureLod(g_filteredSurfaceTex, uv, 0);

	vec4 col = light + surf;
	//vec4 col = mix(light, surf, 1 - light.a);
	//vec4 col = light * light.a;
	col.a = 1;

	imageStore(outputTex, pix, col);
}
