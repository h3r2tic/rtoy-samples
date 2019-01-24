uniform sampler2D g_inputTex;

uniform restrict writeonly image2D outputTex;
uniform vec4 outputTex_size;

#define iResolution outputTex_size

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
	vec4 val = texelFetch(g_inputTex, ivec2(fragCoord), 0);

    vec3 scol = vec3(0.);
	scol = 4. * val.xyz / val.w;
	scol = 1.0 - exp(-scol);
	scol = pow( scol, vec3(1.1) );
    
    fragColor = vec4(scol, 1.0);
}

layout (local_size_x = 8, local_size_y = 8) in;
void main() {
    vec4 fragColor;
    mainImage(fragColor, vec2(gl_GlobalInvocationID.xy) + 0.5);

    imageStore(outputTex, ivec2(gl_GlobalInvocationID.xy), fragColor);
}