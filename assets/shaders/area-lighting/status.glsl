uniform sampler2D iChannel0;
uniform sampler2D iChannel1;
uniform uint iFrame;

uniform restrict writeonly image2D outputTex;
uniform vec4 outputTex_size;

// Buffer A is used to store persistent state in one pixel

// r = start frame
// g = sampling type (brdf, light, multiple)
// b = color samples? (green for brdf importance samples, red for light importance samples)

// INPUTS

// 1 := select brdf importance sampling only
// 2 := select light importance sampling only
// 3 := select multiple importance sampling
// 4 := turn on green coloring of brdf importance samples, red coloring of light importance samples
// SPACE := reset to no coloring and multiple importance sampling

// **************************************************************************
// CONSTANTS

const float KEY_SPACE = 32.5/256.0;
const float KEY_ONE = 49.5/256.0;
const float KEY_TWO = 50.5/256.0;
const float KEY_THREE = 51.5/256.0;
const float KEY_FOUR = 52.5/256.0;

const float BRDF_IMPORTANCE_SAMPLING = 2.;
const float LIGHT_IMPORTANCE_SAMPLING = 1.;
const float MULTIPLE_IMPORTANCE_SAMPLING = 0.;

bool this_pixel_is_being_rendered(vec2 fragCoord, vec2 r)
{
    return (step(r.y-.2, fragCoord.y) * step(fragCoord.y, r.y+1.2) * 
            step(r.x-.2, fragCoord.x) * step(fragCoord.x, r.x+1.2)) > .5;
}

bool this_pixel_is_in_the_range(vec2 fragCoord, vec2 r0, vec2 r1)
{
    return (step(r0.y-.2, fragCoord.y) * step(fragCoord.y, r1.y+1.2) * 
            step(r0.x-.2, fragCoord.x) * step(fragCoord.x, r1.x+1.2)) > .5;
}

// **************************************************************************
// MAIN COLOR

vec3 process_inputs(vec2 fragCoord)
{
    
	vec3 resultingColor = vec3(0.);
    
    vec3 storedState = textureLod(iChannel0, vec2(0., 0.), -100.).rgb;

    float initialFrame = storedState.r;
    float samplingType = storedState.g;
    float colorSamples = storedState.b;

    // space bar resets coloring and sampling to default
    float pressSpace = texture( iChannel1, vec2(KEY_SPACE,0.25) ).x;
    if (pressSpace > .5 || iFrame == 0) 
    { 
        initialFrame = float(iFrame);         
        samplingType = MULTIPLE_IMPORTANCE_SAMPLING; 
        colorSamples = 0.;
    }	

    // one enables brdf sampling only
    float pressOne = texture( iChannel1, vec2(KEY_ONE,0.25) ).x;
    if (pressOne > .5) { 
        initialFrame = float(iFrame); 
        samplingType = BRDF_IMPORTANCE_SAMPLING; 
    }	

    // two enables lighting sampling only
    float pressTwo = texture( iChannel1, vec2(KEY_TWO,0.25) ).x;
    if (pressTwo > .5) { 
        initialFrame = float(iFrame); 
        samplingType = LIGHT_IMPORTANCE_SAMPLING; 
    }	

    // three enables multiple importance sampling
    float pressThree = texture( iChannel1, vec2(KEY_THREE,0.25) ).x;
    if (pressThree > .5) { 
        initialFrame = float(iFrame); 
        samplingType = MULTIPLE_IMPORTANCE_SAMPLING; 
    }	

    // four enables color sampling - green for brdf, red for light
    float pressFour = texture( iChannel1, vec2(KEY_FOUR,0.25) ).x;
    if (pressFour > .5) { 
        initialFrame = float(iFrame); 
        colorSamples = 1.;
    }
    
    
    if (this_pixel_is_being_rendered(fragCoord, vec2(0., 0.)))
    {        
		resultingColor = vec3(initialFrame, samplingType, colorSamples);
    }
                
    return resultingColor;
}


layout (local_size_x = 8, local_size_y = 8) in;
void main() {
    vec2 fragCoord = vec2(gl_GlobalInvocationID.xy) + 0.5;
    
    if (!this_pixel_is_in_the_range(fragCoord, vec2(0., 0.), vec2(1., 0.)))
    {
        return;
    }
    
    vec3 finalColor = process_inputs(fragCoord);
    
    imageStore(outputTex, ivec2(gl_GlobalInvocationID.xy), vec4(finalColor,1.0));
}
