uniform restrict writeonly layout(binding = 0) image2D outputTex;
uniform layout(binding = 1) texture2D g_filteredLightTex;
uniform layout(binding = 2) texture2D g_filteredSurfaceTex;

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);

	vec4 light = texelFetch(g_filteredLightTex, pix, 0);
	vec4 surf = texelFetch(g_filteredSurfaceTex, pix, 0);

	vec4 col = light + surf;
	//vec4 col = mix(light, surf, 1 - light.a);
	//vec4 col = light * light.a;
	col.a = 1;

	imageStore(outputTex, pix, col);
}
