// https://www.shadertoy.com/view/XtGGRt

// Auroras by nimitz 2017 (twitter: @stormoid)
// License Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License
// Contact the author for other licensing options

/*
--------------------------------------------------------------------------------
	There are two main hurdles I encountered rendering this effect. 
	First, the nature of the texture that needs to be generated to get a believable effect
	needs to be very specific, with large scale band-like structures, small scale non-smooth variations
	to create the trail-like effect, a method for animating said texture smoothly and finally doing all
	of this cheaply enough to be able to evaluate it several times per fragment/pixel.

	The second obstacle is the need to render a large volume while keeping the computational cost low.
	Since the effect requires the trails to extend way up in the atmosphere to look good, this means
	that the evaluated volume cannot be as constrained as with cloud effects. My solution was to make
	the sample stride increase polynomially, which works very well as long as the trails are lower opcaity than
	the rest of the effect. Which is always the case for auroras.

	After that, there were some issues with getting the correct emission curves and removing banding at lowered
	sample densities, this was fixed by a combination of sample number influenced dithering and slight sample blending.

	N.B. the base setup is from an old shader and ideally the effect would take an arbitrary ray origin and
	direction. But this was not required for this demo and would be trivial to fix.
--------------------------------------------------------------------------------
*/

uniform float worldTimeCounter;

float auroraAmount = smoothstep(0.0, 0.2, -worldSunVector.y) * AURORA_STRENGTH;
vec3 auroraShading = vec3(0.0, 0.005, 0.0025) * auroraAmount;

//================================================================================================//

mat2 mm2(in float a)  { float c = cos(a), s = sin(a); return mat2(c, s, -s, c); }
mat2 m2 = mat2(0.95534, 0.29552, -0.29552, 0.95534);
float tri(in float x) { return clamp(abs(fract(x) - 0.5), 0.01, 0.49); }
vec2 tri2(in vec2 p)  { return vec2(tri(p.x) + tri(p.y), tri(p.y + tri(p.x))); }

float triNoise2d(in vec2 p, in float spd) {
    float z = 1.8;
    float z2 = 2.5;
	float rz = 0.0;
    p *= mm2(p.x * 0.06);
    vec2 bp = p;
	for (uint i = 0u; i < 5u; ++i) {
        vec2 dg = tri2(bp * 1.85) * 0.75;
        dg *= mm2(worldTimeCounter * spd);
        p -= dg / z2;

        bp *= 1.3;
        z2 *= 0.45;
        z *= 0.42;
		p *= 1.21 + (rz - 1.0) * 0.02;    
        p *= -m2;
        rz += tri(p.x + tri(p.y)) * z;
	}

    return clamp(pow(rz * 29.0, -1.3), 0.0, 0.55);
}

float hash21(in vec2 n) { return fract(sin(dot(n, vec2(12.9898, 4.1414))) * 43758.5453); }

vec4 aurora(in vec3 ro, in vec3 rd) {
    vec4 col = vec4(0.0);
    vec4 avgCol = vec4(0.0);

    float hash = 0.006 * hash21(gl_FragCoord.xy);
    float rf = 1.0 / (rd.y * 2.0 + 0.4);

    for (float i = 0.0; i < 36.0; ++i) {
        float of = hash * smoothstep(0.0, 15.0, i);
        float pt = ((0.8 + pow(i, 1.4) * 0.002) - ro.y) * rf;
        pt -= of;
    	vec3 bpos = ro + pt * rd;
        vec2 p = bpos.zx;
        float rzt = triNoise2d(p, 0.1883);
        vec4 col2 = vec4(0.0, 0.0, 0.0, rzt);
        col2.rgb = (sin(1.0 - vec3(2.15, -0.5, 1.2) + i * 0.043) * 0.5 + 0.5) * rzt;
        avgCol = mix(avgCol, col2, 0.5);
        col += avgCol * exp2(-i * 0.065 - 2.5) * smoothstep(0.0, 5.0, i);  
    }

    col *= saturate(rd.y * 15.0 + 0.4);

    return col;
}

vec3 NightAurora(in vec3 rayDir) {	
    if (auroraAmount > 1e-2 && rayDir.y > 0.0 && eyeAltitude < 2e4) {
        float raylength = (planetRadius + 2e4 - viewerHeight) / rayDir.y * 1e-5;

        if (clamp(raylength, 0.0, 5.0) != raylength) return vec3(0.0);

        vec3 rd = rayDir * raylength;
        float fade = fastExp(-raylength);

        vec4 aur = smoothstep(0.0, 2.5, aurora(vec3(0.0, 0.0, -6.7), rd));
        return aur.rgb * fade * auroraAmount;
    } else {
        return vec3(0.0);
    }
}