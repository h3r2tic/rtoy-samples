layout(location = 0) out vec4 out_color;
layout(location = 0) in vec3 v_normal;

void main() {
	out_color = vec4(v_normal * 0.5 + 0.5, 1.0);
}
