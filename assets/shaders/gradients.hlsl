#include "rendertoy::shaders/color.hlsl"
#include "inc/uv.hlsl"

RWTexture2D<float4> outputTex;

cbuffer globals {
    float4 outputTex_size;
    float time;
};

[numthreads(8, 8, 1)]
void main(in uint2 pix : SV_DispatchThreadID) {
	float2 uv = frac(get_uv(pix, outputTex_size) + float2(0.0, time));
	float hue = frac(int(uv.y * 6) / 6.0 + 0.09);
	float4 col = float4(hsv_to_rgb(float3(hue, 1.0, 1)) * uv.x, 1);
    outputTex[pix] = col;
}
