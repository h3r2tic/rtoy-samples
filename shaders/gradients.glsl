uniform restrict writeonly image2D outputTex;
uniform vec4 outputTex_size;
uniform float time;

vec3 hsv2rgb(vec3 c)
{
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
	vec2 uv = fract(vec2(pix.xy + 0.5) * outputTex_size.zw + vec2(0.0, time));
	float hue = fract(int(uv.y * 6) / 6.0 + 0.09);
	vec4 col = vec4(hsv2rgb(vec3(hue, 1.0, 1)) * uv.x, 1);
	imageStore(outputTex, pix, col);
}
