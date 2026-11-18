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
	// [v1world] Covered in trash (owner, Nov 8): dark bag clusters, rust and plastic blotches and
	// sun-bleached paper flecks over the whole waste land, so the fall shows a trashed planet.
	// [v9intro] Two octaves each: one octave of value noise showed its grid (rows of round blobs).
	float sp = noise(n * 240.0 + seed) * 0.62 + noise(n * 531.0 + seed + 3.0) * 0.38;
	float sp2 = noise(n * 150.0 + seed + 7.0) * 0.62 + noise(n * 347.0 + seed + 9.0) * 0.38;
	float sp3 = fbm(n * 48.0 + seed + 2.0);
	// [v9intro] The same trash, read from orbit: it was hard black and white blotches (camouflage).
	// Now a finer, softer mottle of bags, rust, plastic and bleached paper over the waste.
	float fine = noise(n * 520.0 + seed * 3.0);
	waste = mix(waste, vec3(0.1, 0.095, 0.09), smoothstep(0.46, 0.7, sp) * 0.5);
	waste = mix(waste, vec3(0.72, 0.68, 0.6), smoothstep(0.58, 0.78, sp2) * 0.4);
	waste = mix(waste, vec3(0.5, 0.25, 0.15), smoothstep(0.56, 0.72, sp3) * 0.4);
	waste = mix(waste, vec3(0.24, 0.36, 0.46), smoothstep(0.66, 0.74, sp3 + sp * 0.1) * 0.25);
	waste *= mix(0.86, 1.1, fine);
	sea = mix(vec3(0.05, 0.075, 0.075), vec3(0.1, 0.115, 0.1), detail);  // murky, not black
	sea = mix(sea, vec3(0.2, 0.17, 0.12), smoothstep(0.44, 0.54, h) * 0.6);  // silted, scummy shores
	vec3 living = mix(vec3(0.16, 0.36, 0.14), vec3(0.3, 0.5, 0.2), detail);
	vec3 col = mix(sea, mix(waste, living, green), land);
	// Haze bands (dusty clouds).
	float cl = smoothstep(0.55, 0.8, fbm(n * vec3(7.0, 16.0, 7.0) + vec3(spin * 0.3, 0.0, 0.0) + 11.0));
	col = mix(col, mix(vec3(0.62, 0.58, 0.52), vec3(0.92, 0.95, 1.0), green), cl * 0.42);  // [v1world] thinner haze (was 0.6): the trash shows
	// [v9intro] Air: the surface fades into the dusty haze toward the edge of the disc.
	float limb = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.2);
	col = mix(col, mix(vec3(0.74, 0.6, 0.47), vec3(0.7, 0.82, 0.95), green), limb * 0.6);
	ALBEDO = col;
	ROUGHNESS = mix(0.6, 0.95, max(land, cl));  // [v9intro] was 0.35: the sun's glint on the sea blew out to a white patch
	SPECULAR = mix(0.3, 0.2, land);
}
