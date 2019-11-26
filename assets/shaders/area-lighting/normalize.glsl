uniform layout(binding = 0) texture2D g_inputTex;
uniform restrict writeonly layout(binding = 1) image2D outputTex;

void mainImage(out vec4 fragColor, in ivec2 pix)
{
	vec4 val = texelFetch(g_inputTex, pix, 0);

    vec3 scol = vec3(0.);
	scol = 4. * val.xyz / val.w;
    
    fragColor = vec4(scol, 1.0);
}

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
    vec4 fragColor;
    mainImage(fragColor, ivec2(gl_GlobalInvocationID.xy));
    imageStore(outputTex, ivec2(gl_GlobalInvocationID.xy), fragColor);
}