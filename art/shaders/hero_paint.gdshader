shader_type spatial;
// Worn paint for the hero bot's baked mesh (art/models/aurora). Same layering as worn_metal
// (paint over rust over steel, object-space triplanar textures) but driven by the vertex colours
// baked in Blender: R = ambient occlusion, G = convex edge wear, B = cavity dirt. Chips and scuffs
// gather on edges, grime in cavities and seams. A soft cool fresnel rim (stronger on the side
// facing away from the sun) helps the hero read against the busy world.
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 paint_color : source_color = vec4(0.9, 0.9, 0.87, 1.0);
uniform float paint_coverage : hint_range(0.0, 1.0) = 0.86;
uniform float rust_amount : hint_range(0.0, 1.0) = 0.25;
uniform float fade : hint_range(0.0, 1.0) = 0.2;
uniform float grime : hint_range(0.0, 1.0) = 0.5;
uniform float dust : hint_range(0.0, 1.0) = 0.4;
uniform float edge_wear : hint_range(0.0, 1.0) = 0.6;
uniform float specks : hint_range(0.0, 1.0) = 0.8;
uniform float metallic_bare = 0.85;
uniform float paint_metallic = 0.0;
uniform float paint_roughness = 0.42;
uniform float tex_scale = 2.4;
uniform float seed = 0.0;
uniform float ao_strength = 1.0;
uniform vec4 rim_color : source_color = vec4(0.62, 0.85, 1.0, 1.0);
uniform float rim_strength = 0.12;
uniform vec3 sun_dir = vec3(-0.5, 0.6, 0.6);   // world direction TOWARD the sun
uniform sampler2D metal_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metal_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metal_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rust_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rust_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rust_arm : filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 opos;
varying vec3 onrm;
varying vec3 wnrm;
varying vec4 vcol;

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
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vcol = COLOR;
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

	float ao = vcol.r;
	float edge = vcol.g;
	float cav = vcol.b;
	vec3 q = opos * 6.0 + vec3(seed);
	float big = fbm3(q);
	float fine = fbm3(q * 4.0 + 3.0);
	// Paint chips: noise everywhere, much stronger on convex edges.
	float chip_n = big * 0.75 + fine * 0.35 - edge * edge_wear * 0.55;
	float paint = smoothstep(1.0 - paint_coverage - 0.03, 1.0 - paint_coverage + 0.03, chip_n);
	// Small dark specks / pits in the paint (like the concept's speckled shell).
	float sp = smoothstep(0.8, 0.9, n3(opos * 110.0 + seed * 5.0)) * clamp(smoothstep(0.45, 0.75, fbm3(q * 0.8 + 5.0)) + edge * 0.6, 0.0, 1.0);
	paint *= 1.0 - sp * specks;
	float rust = smoothstep(0.35, 0.65, fbm3(q * 1.7 + 11.0) + rust_amount * 0.4 - 0.2);
	vec3 bare_alb = mix(m_alb * 0.55, r_alb * 0.7, max(rust, 0.4));
	vec3 bare_nrm = mix(m_nrm, r_nrm, rust);
	float bare_rough = mix(m_arm.g, r_arm.g, rust);
	float bare_metal = mix(metallic_bare, 0.1, rust);
	vec3 pc = paint_color.rgb;
	pc = mix(pc, vec3(dot(pc, vec3(0.33))), fade * 0.4);
	pc *= mix(0.9, 1.05, fine);
	// Thin lighter halo of worn paint around each chip.
	float halo = smoothstep(0.0, 0.06, abs(chip_n - (1.0 - paint_coverage)));
	pc = mix(pc * 1.08, pc, halo);
	// Rust/dirt streaks running down the sides.
	float streak = smoothstep(0.55, 0.85, n3(vec3(opos.x * 24.0, opos.y * 2.5, opos.z * 24.0) + seed)) * (1.0 - smoothstep(-0.3, 0.6, onrm.y));
	pc = mix(pc, pc * vec3(0.62, 0.5, 0.4), streak * grime * 0.6);
	vec3 alb = mix(bare_alb, pc, paint);
	vec3 nrm = mix(bare_nrm, mix(vec3(0.5, 0.5, 1.0), m_nrm, 0.18), paint);
	float rough = mix(bare_rough, paint_roughness + fine * 0.15, paint);
	float metal = mix(bare_metal, paint_metallic, paint);
	// Fine scratches.
	float scr = smoothstep(0.985, 1.0, n3(vec3(opos.x * 160.0, opos.y * 8.0, opos.z * 160.0) + seed));
	alb = mix(alb, m_alb * 0.9, scr * paint * 0.6);
	// Grime: cavities, occluded areas, low on each part; dust settles on top faces.
	float g = clamp(cav * 1.2 + (1.0 - ao) * 1.1, 0.0, 1.0) * grime;
	// Broad brownish smudges and stains.
	g = max(g, smoothstep(0.55, 0.85, fbm3(q * 1.3 + 21.0)) * grime * 0.45);
	alb = mix(alb, alb * vec3(0.36, 0.3, 0.25), g);
	rough = mix(rough, 0.9, g);
	float d = smoothstep(0.5, 0.95, onrm.y) * dust * smoothstep(0.35, 0.75, fbm3(q * 3.0));
	alb = mix(alb, vec3(0.6, 0.53, 0.45), d * 0.7);
	rough = mix(rough, 0.95, d);

	ALBEDO = alb;
	NORMAL_MAP = nrm;
	ROUGHNESS = clamp(rough, 0.15, 1.0);
	METALLIC = metal;
	AO = mix(1.0, ao, ao_strength) * mix(1.0, mix(m_arm.r, r_arm.r, rust), 1.0 - paint);
	AO_LIGHT_AFFECT = 0.4;
	// Fresnel rim, stronger on the side turned away from the sun.
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float away = 0.45 + 0.55 * (1.0 - clamp(dot(wnrm, normalize(sun_dir)) * 0.5 + 0.5, 0.0, 1.0));
	EMISSION = rim_color.rgb * fres * rim_strength * away * mix(0.5, 1.0, ao) * (0.4 + 0.6 * paint);
}
