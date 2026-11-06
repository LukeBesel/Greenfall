// Shared toon lighting + noise for Greenfall. 3 light bands, soft rim, banded highlight.
uniform float rim_strength = 0.35;
uniform float spec_strength = 0.25;
uniform float band_softness = 0.04;

float gf_hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float gf_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(gf_hash(i + vec3(0, 0, 0)), gf_hash(i + vec3(1, 0, 0)), f.x),
				   mix(gf_hash(i + vec3(0, 1, 0)), gf_hash(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(gf_hash(i + vec3(0, 0, 1)), gf_hash(i + vec3(1, 0, 1)), f.x),
				   mix(gf_hash(i + vec3(0, 1, 1)), gf_hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float gf_fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * gf_noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float s = band_softness;
	float bands = smoothstep(-s, s, ndl) * 0.6 + smoothstep(0.5 - s, 0.5 + s, ndl) * 0.4;
	float shadow = smoothstep(0.35, 0.65, ATTENUATION);
	vec3 lc = LIGHT_COLOR / PI;
	DIFFUSE_LIGHT += bands * shadow * lc;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	DIFFUSE_LIGHT += smoothstep(0.45, 0.55, rim) * rim_strength * lc * (0.4 + 0.6 * shadow);
	vec3 h = normalize(VIEW + LIGHT);
	SPECULAR_LIGHT += smoothstep(0.93, 0.96, dot(NORMAL, h)) * spec_strength * lc * shadow;
}
