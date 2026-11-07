shader_type spatial;
// Realistic worn painted metal for procedural meshes (no UVs needed: object-space triplanar).
// Layers: bare metal (metal_plate) -> rust (rusty_metal_02) -> paint (flat color, chipped, faded),
// plus grime that collects low on the object, scratches, and dust on upward faces.
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 paint_color : source_color = vec4(0.82, 0.55, 0.16, 1.0);
uniform float paint_coverage : hint_range(0.0, 1.0) = 0.7;   // 1 = mostly paint, 0 = all rust
uniform float rust_amount : hint_range(0.0, 1.0) = 0.5;       // rust vs bare metal where paint is gone
uniform float fade : hint_range(0.0, 1.0) = 0.35;             // sun-fading of the paint
uniform float grime : hint_range(0.0, 1.0) = 0.5;
uniform float dust : hint_range(0.0, 1.0) = 0.4;
uniform float metallic_bare = 0.85;
uniform float paint_roughness = 0.55;
uniform float tex_scale = 1.6;                                // texture repeats per meter
uniform float seed = 0.0;
uniform float grime_floor = 0.0;   // object-space Y where grime is strongest
uniform float grime_height = 0.6;
uniform sampler2D metal_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metal_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metal_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rust_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rust_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rust_arm : filter_linear_mipmap_anisotropic, repeat_enable;

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

float fbm3(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * n3(p);
		p = p * 2.03 + 7.1;
		a *= 0.5;
	}
	return v;
}

vec3 tri_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / (w.x + w.y + w.z);
}

vec4 tri(sampler2D t, vec3 p, vec3 w) {
	return texture(t, p.zy) * w.x + texture(t, p.xz) * w.y + texture(t, p.xy) * w.z;
}

void vertex() {
	opos = VERTEX;
	onrm = NORMAL;
}

void fragment() {
	vec3 w = tri_weights(onrm);
	vec3 p = opos * tex_scale + vec3(seed * 3.1);
	vec3 m_alb = tri(metal_alb, p, w).rgb;
	vec3 m_nrm = tri(metal_nrm, p, w).rgb;
	vec3 m_arm = tri(metal_arm, p, w).rgb;
	vec3 r_alb = tri(rust_alb, p * 0.7, w).rgb;
	vec3 r_nrm = tri(rust_nrm, p * 0.7, w).rgb;
	vec3 r_arm = tri(rust_arm, p * 0.7, w).rgb;

	vec3 q = opos * 2.2 + vec3(seed);
	float big = fbm3(q);
	float fine = fbm3(q * 4.0 + 3.0);
	// Paint chips: where noise falls below coverage threshold, paint is gone.
	float chip_n = big * 0.75 + fine * 0.35;
	float paint = smoothstep(1.0 - paint_coverage - 0.03, 1.0 - paint_coverage + 0.03, chip_n);
	// Rust bloom spreading from under the paint edges.
	float rust = smoothstep(0.35, 0.65, fbm3(q * 1.7 + 11.0) + rust_amount * 0.4 - 0.2);
	vec3 bare_alb = mix(m_alb, r_alb, rust);
	vec3 bare_nrm = mix(m_nrm, r_nrm, rust);
	float bare_rough = mix(m_arm.g, r_arm.g, rust);
	float bare_metal = mix(metallic_bare, 0.1, rust);
	// Paint: faded, slightly mottled, with rust stains running down (vertical streaks).
	vec3 pc = paint_color.rgb;
	pc = mix(pc, vec3(dot(pc, vec3(0.33))) * 1.1, fade * 0.5);
	pc *= mix(0.86, 1.06, fine);
	float streak = smoothstep(0.55, 0.8, n3(vec3(opos.x * 9.0, opos.y * 1.2, opos.z * 9.0) + seed)) * (1.0 - smoothstep(-0.2, 0.6, onrm.y));
	pc = mix(pc, r_alb * 0.8, streak * rust_amount * 0.6);
	// Edge-ish halo: paint near chips is thinner and lighter.
	float halo = smoothstep(0.0, 0.08, abs(chip_n - (1.0 - paint_coverage))) ;
	pc = mix(pc * 1.12, pc, halo);
	vec3 alb = mix(bare_alb, pc, paint);
	vec3 nrm = mix(bare_nrm, mix(vec3(0.5, 0.5, 1.0), m_nrm, 0.25), paint);
	float rough = mix(bare_rough, paint_roughness + fine * 0.2, paint);
	float metal = mix(bare_metal, 0.0, paint);
	// Scratches.
	float scr = smoothstep(0.985, 1.0, n3(vec3(opos.x * 60.0, opos.y * 3.0, opos.z * 60.0) + seed));
	alb = mix(alb, m_alb * 1.2, scr * paint * 0.7);
	// Grime low down + in crevices (approximated by noise), dust on upward faces.
	float g = (1.0 - smoothstep(grime_floor, grime_floor + grime_height, opos.y)) * grime;
	g = max(g, smoothstep(0.62, 0.8, fbm3(q * 3.0 + 21.0)) * grime * 0.6);
	alb = mix(alb, alb * vec3(0.32, 0.28, 0.24), g);
	rough = mix(rough, 0.95, g);
	float d = smoothstep(0.5, 0.95, onrm.y) * dust * smoothstep(0.3, 0.7, fbm3(q * 5.0));
	alb = mix(alb, vec3(0.55, 0.5, 0.44), d);
	rough = mix(rough, 1.0, d);

	ALBEDO = alb;
	NORMAL_MAP = nrm;
	ROUGHNESS = clamp(rough, 0.2, 1.0);
	METALLIC = metal;
	AO = mix(1.0, mix(m_arm.r, r_arm.r, rust), 1.0 - paint);
}
