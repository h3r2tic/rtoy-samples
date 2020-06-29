vec2 get_uv(vec4 texSize) {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
	return (vec2(pix) + 0.5) * texSize.zw;
}

vec2 get_uv(ivec2 pix, vec4 texSize) {
	return (vec2(pix) + 0.5) * texSize.zw;
}

vec2 get_uv(vec2 pix, vec4 texSize) {
	return (pix + 0.5) * texSize.zw;
}

vec2 cs_to_uv(vec2 cs)
{
	return cs * vec2(0.5, -0.5) + vec2(0.5, 0.5);
}

vec2 uv_to_cs(vec2 uv)
{
	return (uv - 0.5.xx) * vec2(2, -2);
}
