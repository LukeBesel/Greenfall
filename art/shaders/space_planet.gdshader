shader_type spatial;
// Verdance from space (story cinematics): murky dark seas, dusty brown-orange waste continents,
// drifting haze bands. green = 0..1 tints the land back toward living green (finale/memories).
uniform float seed = 3.7;
uniform float green : hint_range(0.0, 1.0) = 0.0;
uniform float spin = 0.0;
varying vec3 lp;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
				mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 6; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec3 n = normalize(lp);
	float c = cos(spin), s = sin(spin);
	n = vec3(c * n.x - s * n.z, n.y, s * n.x + c * n.z);
	float h = fbm(n * 6.0 + seed);
	float land = smoothstep(0.52, 0.56, h);
	float detail = fbm(n * 30.0 + seed * 2.0);
	vec3 sea = mix(vec3(0.03, 0.06, 0.07), vec3(0.07, 0.1, 0.09), detail);
	vec3 waste = mix(vec3(0.22, 0.19, 0.16), vec3(0.42, 0.35, 0.27), detail);
	waste = mix(waste, vec3(0.5, 0.3, 0.17), smoothstep(0.62, 0.75, fbm(n * 12.0 + 4.0)) * 0.6);
	vec3 living = mix(vec3(0.16, 0.36, 0.14), vec3(0.3, 0.5, 0.2), detail);
	vec3 col = mix(sea, mix(waste, living, green), land);
	// Haze bands (dusty clouds).
	float cl = smoothstep(0.55, 0.8, fbm(n * vec3(7.0, 16.0, 7.0) + vec3(spin * 0.3, 0.0, 0.0) + 11.0));
	col = mix(col, mix(vec3(0.62, 0.58, 0.52), vec3(0.92, 0.95, 1.0), green), cl * 0.6);
	ALBEDO = col;
	ROUGHNESS = mix(0.35, 0.95, max(land, cl));
	SPECULAR = mix(0.6, 0.2, land);
}
