float unpack_unorm(uint pckd, uint bitCount) {
	uint maxVal = (1u << bitCount) - 1;
	return float(pckd & maxVal) / maxVal;
}

uint pack_unorm(float val, uint bitCount) {
	uint maxVal = (1u << bitCount) - 1;
	return uint(clamp(val, 0.0, 1.0) * maxVal);
}

float pack_normal_11_10_11(vec3 n) {
	uint pckd = 0;
	pckd += pack_unorm(n.x * 0.5 + 0.5, 11);
	pckd += pack_unorm(n.y * 0.5 + 0.5, 10) << 11;
	pckd += pack_unorm(n.z * 0.5 + 0.5, 11) << 21;
	return uintBitsToFloat(pckd);
}

vec3 unpack_normal_11_10_11(float pckd) {
	uint p = floatBitsToUint(pckd);
	return normalize(vec3(
		unpack_unorm(p, 11),
		unpack_unorm(p >> 11, 10),
		unpack_unorm(p >> 21, 11)
	) * 2.0 - 1.0);
}

vec3 unpack_normal_11_10_11_no_normalize(float pckd) {
	uint p = floatBitsToUint(pckd);
	return vec3(
		unpack_unorm(p, 11),
		unpack_unorm(p >> 11, 10),
		unpack_unorm(p >> 21, 11)
	) * 2.0 - 1.0;
}

uint pack_color_888(vec3 color) {
    color = sqrt(color);
	uint pckd = 0;
	pckd += pack_unorm(color.x, 8);
	pckd += pack_unorm(color.y, 8) << 8;
	pckd += pack_unorm(color.z, 8) << 16;
    return pckd;
}

vec3 unpack_color_888(uint p) {
	vec3 color = vec3(
		unpack_unorm(p, 8),
		unpack_unorm(p >> 8, 8),
		unpack_unorm(p >> 16, 8)
	);
    return color * color;
}

vec2 octa_wrap( vec2 v ) {
    return (1.0 - abs(v.yx)) * (step(0.0.xx, v.xy) * 2.0 - 1.0);
}
 
vec2 octa_encode(vec3 n) {
    n /= (abs(n.x) + abs(n.y) + abs(n.z));
    if (n.z < 0.0) {
        n.xy = octa_wrap(n.xy);
    }
    n.xy = n.xy * 0.5 + 0.5;
    return n.xy;
}

vec3 octa_decode(vec2 f)
{
    f = f * 2.0 - 1.0;
 
    // https://twitter.com/Stubbesaurus/status/937994790553227264
    vec3 n = vec3( f.x, f.y, 1.0 - abs( f.x ) - abs( f.y ) );
    float t = clamp(-n.z, 0.0, 1.0);
    //n.xy += n.xy >= 0.0 ? -t : t;
    n.xy -= (step(0.0, n.xy) * 2 - 1) * t;
    return normalize( n );
}
