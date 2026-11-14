shader_type spatial;
// Story cinematics: a soft puff of smoke, steam or dust on a sphere mesh. Alpha falls off to the
// silhouette (no hard disc edge) and a slow noise breaks the outline up. Alpha-blended, unshaded.
render_mode unshaded, blend_mix, cull_back, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.9, 0.92, 0.95, 0.5);
uniform float power = 1.6;
uniform float seed = 0.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float f = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float n = noise(normalize(lp) * 2.6 + seed);
	float a = pow(f, power) * mix(0.55, 1.0, n);
	ALBEDO = tint.rgb * mix(0.82, 1.05, n);
	ALPHA = clamp(a * tint.a, 0.0, 1.0);
}
