shader_type spatial;
// [yard] Chunky painted-kit material for the yard builds (systems/camp/yard_art.gd). No UVs needed.
// Albedo comes from the vertex colour (sRGB); vertex alpha 0 = bare metal, 1 = paint.
// `wear` adds rust patches and chipped, faded paint (broken builds ~0.7, fresh ones ~0.1);
// grime collects near the object's base (object-space y), dust settles on top faces.
// `stripes` turns it into diagonal hazard stripes (vertex colour + near-black).
render_mode diffuse_burley, specular_schlick_ggx;

uniform float wear : hint_range(0.0, 1.0) = 0.15;
uniform float grime : hint_range(0.0, 1.0) = 0.6;
uniform float grime_height = 0.45;
uniform float stripes : hint_range(0.0, 1.0) = 0.0;
uniform float stripe_freq = 5.0;
uniform float seed = 0.0;
uniform sampler2D detail_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rust_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 opos;
varying vec3 onrm;

float h31(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float n3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h31(i), h31(i + vec3(1, 0, 0)), f.x), mix(h31(i + vec3(0, 1, 0)), h31(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(h31(i + vec3(0, 0, 1)), h31(i + vec3(1, 0, 1)), f.x), mix(h31(i + vec3(0, 1, 1)), h31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * n3(p);
		p = p * 2.07 + 5.3;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	opos = VERTEX;
	onrm = NORMAL;
}

void fragment() {
	vec3 base = pow(COLOR.rgb, vec3(2.2));
	float metal = 1.0 - COLOR.a;
	vec3 q = opos + vec3(seed * 1.7);
	float big = fbm(q * 1.8);
	float fine = fbm(q * 9.0 + 2.0);
	if (stripes > 0.5) {
		float s = fract((opos.x + opos.y * 0.6 + opos.z) * stripe_freq);
		base = mix(base, vec3(0.025, 0.025, 0.03), step(0.5, s));
	}
	// Soft paint variation (never flat).
	base *= 0.9 + 0.2 * big;
	// Fading and chipped paint with wear; rust where the chips go deep.
	float chip = smoothstep(0.62 - wear * 0.35, 0.7 - wear * 0.35, fbm(q * 4.2 + 9.0)) * wear;
	float rusty = smoothstep(1.0 - wear * 0.75, 1.08 - wear * 0.75, big + fine * 0.35);
	vec3 w3 = pow(abs(onrm), vec3(4.0));
	w3 /= (w3.x + w3.y + w3.z);
	vec3 tp = opos * 1.3;
	vec3 rust = (texture(rust_alb, tp.zy).rgb * w3.x + texture(rust_alb, tp.xz).rgb * w3.y + texture(rust_alb, tp.xy).rgb * w3.z);
	base = mix(base, base * vec3(0.78, 0.74, 0.7), wear * 0.5 * (1.0 - metal));  // dulled, dirty paint
	base = mix(base, vec3(0.13, 0.12, 0.115), chip * (1.0 - metal) * 0.85);
	base = mix(base, rust * vec3(0.62, 0.45, 0.32), rusty * clamp(wear * 1.4, 0.0, 1.0));
	// Grime at the base, dust on the tops.
	float g = (1.0 - smoothstep(0.0, grime_height, opos.y)) * grime * (0.6 + 0.4 * fine);
	base = mix(base, base * vec3(0.42, 0.38, 0.33), g);
	float up = smoothstep(0.6, 0.95, onrm.y) * (0.06 + wear * 0.12) * fine;
	base = mix(base, vec3(0.42, 0.39, 0.34), up);
	ALBEDO = base;
	METALLIC = mix(metal * 0.9, 0.2, max(rusty * wear, chip));
	ROUGHNESS = clamp(mix(0.42, 0.32, metal) + rusty * wear * 0.45 + g * 0.25 + up * 0.3 + fine * 0.08, 0.0, 1.0);
	vec3 dn = (texture(detail_nrm, tp.zy * 2.0).rgb * w3.x + texture(detail_nrm, tp.xz * 2.0).rgb * w3.y + texture(detail_nrm, tp.xy * 2.0).rgb * w3.z);
	NORMAL_MAP = dn;
	NORMAL_MAP_DEPTH = 0.25 + wear * 0.6;
}
