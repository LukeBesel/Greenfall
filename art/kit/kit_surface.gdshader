shader_type spatial;
// [kit] Shared surface shader for the art kit (art/kit/kit_materials.gd).
// One shader for painted metal, bare/rusty steel, concrete and hazard stripes:
//   base layer   : a Poly Haven PBR set (albedo/normal/ARM), object-space triplanar, tinted
//   paint layer  : flat colour over the base, chipped away at EDGES (vertex COLOR.r = edge mask,
//                  baked by KitMesh bevel generators) and, when worn, in random patches
//   pattern      : 0 = none, 1 = hazard stripes (paint alternates paint_color / paint_color2)
//   AO           : vertex COLOR.g (baked contact/cavity AO) darkens albedo and ambient
//   variation    : vertex COLOR.b (per-part seed) jitters paint value/hue so panels read separately
//   grime/dust   : grime creeps up from object y = 0 (the ground), dust settles on upward faces
// Works without UVs or tangents (triplanar normal mapping in object space).
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 paint_color : source_color = vec4(0.9, 0.86, 0.76, 1.0);
uniform vec4 paint_color2 : source_color = vec4(0.06, 0.06, 0.07, 1.0);
uniform float paint_amount : hint_range(0.0, 1.0) = 1.0;    // 0 = bare base material
uniform int pattern = 0;                                      // 1 = hazard stripes
uniform bool paint_from_vertex = false;                       // paint colour from CUSTOM0 (KitMesh.Builder), a > 0.5 = hazard
uniform float stripe_freq = 2.6;                              // stripes per metre (hazard)
uniform float edge_wear : hint_range(0.0, 1.0) = 0.35;        // chipped paint at edges
uniform float patch_wear : hint_range(0.0, 1.0) = 0.0;        // chipped paint on faces
uniform float rust : hint_range(0.0, 1.0) = 0.2;              // rust where paint is gone
uniform float fade : hint_range(0.0, 1.0) = 0.1;              // sun-faded paint
uniform float grime : hint_range(0.0, 1.0) = 0.4;
uniform float grime_height = 0.9;
uniform float dust : hint_range(0.0, 1.0) = 0.2;
uniform float streaks : hint_range(0.0, 1.0) = 0.2;           // rain/rust streaks on walls
uniform float paint_roughness = 0.42;
uniform float paint_metallic = 0.0;
uniform float clearcoat_amt = 0.0;
uniform float base_metallic = 0.9;                            // metal plates; 0 for concrete
uniform vec4 base_tint : source_color = vec4(1.0);
uniform float base_normal_strength = 0.6;
uniform float paint_normal_strength = 0.18;
uniform float tex_scale = 0.8;                                // texture repeats per metre
uniform float ao_strength = 0.75;
uniform sampler2D base_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rust_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rust_arm : filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 opos;
varying vec3 onrm;
varying vec4 vcol;
varying vec4 vcust;

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
	for (int i = 0; i < 4; i++) {
		v += a * n3(p);
		p = p * 2.03 + 7.1;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	opos = VERTEX;
	onrm = NORMAL;
	vcol = COLOR;
	vcust = CUSTOM0;
}

void fragment() {
	vec3 n = normalize(onrm);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 p = opos * tex_scale + vec3(vcol.b * 7.31);
	vec2 ux = p.zy;
	vec2 uy = p.xz;
	vec2 uz = p.xy;
	vec3 b_alb = (texture(base_alb, ux) * w.x + texture(base_alb, uy) * w.y + texture(base_alb, uz) * w.z).rgb * base_tint.rgb;
	vec3 b_arm = (texture(base_arm, ux) * w.x + texture(base_arm, uy) * w.y + texture(base_arm, uz) * w.z).rgb;
	vec3 r_alb = (texture(rust_alb, ux * 0.8) * w.x + texture(rust_alb, uy * 0.8) * w.y + texture(rust_alb, uz * 0.8) * w.z).rgb;
	vec3 r_arm = (texture(rust_arm, ux * 0.8) * w.x + texture(rust_arm, uy * 0.8) * w.y + texture(rust_arm, uz * 0.8) * w.z).rgb;
	// Triplanar normal (whiteout blend), object space.
	vec3 tx = texture(base_nrm, ux).xyz * 2.0 - 1.0;
	vec3 ty = texture(base_nrm, uy).xyz * 2.0 - 1.0;
	vec3 tz = texture(base_nrm, uz).xyz * 2.0 - 1.0;

	vec3 q = opos * 1.9 + vec3(vcol.b * 13.0);
	float big = fbm3(q);
	float fine = n3(q * 9.0);
	// ---- paint coverage: edges first (baked edge mask), then patches ----
	float edge = vcol.r;
	float chip_noise = big * 0.7 + fine * 0.3;
	float edge_chip = smoothstep(1.0 - edge_wear, 1.0 - edge_wear + 0.08, edge * (0.55 + chip_noise * 0.9));
	float patch_chip = smoothstep(1.0 - patch_wear * 0.6, 1.02 - patch_wear * 0.6, big + fine * 0.15);
	float paint = paint_amount * (1.0 - max(edge_chip, patch_chip));
	// paint colour: per-part variation, hazard pattern, fade
	vec3 pc = paint_from_vertex ? vcust.rgb : paint_color.rgb;
	if (pattern == 1 || (paint_from_vertex && vcust.a > 0.5)) {
		float s = fract((opos.x + opos.y + opos.z * 0.7) * stripe_freq);
		float m = smoothstep(0.47, 0.53, s) * (1.0 - smoothstep(0.97, 1.0, s));
		pc = mix(pc, paint_color2.rgb, m);
	}
	pc *= 0.93 + vcol.b * 0.14;
	pc *= mix(0.94, 1.04, n3(q * 2.5));
	pc = mix(pc, vec3(dot(pc, vec3(0.3, 0.55, 0.15))) * 1.08 + vec3(0.04, 0.03, 0.02), fade * 0.55);
	// brighter primer halo just inside the chips (worn edges read as light lines, like painted toys)
	float halo = smoothstep(1.0 - edge_wear - 0.18, 1.0 - edge_wear, edge * (0.55 + chip_noise * 0.9)) * (1.0 - edge_chip);
	pc = mix(pc, pc * 1.25 + vec3(0.05), halo * 0.55 * paint_amount);
	// ---- base: steel/concrete, rusting where exposed ----
	float r_mask = smoothstep(0.42, 0.62, fbm3(q * 1.4 + 11.0) + rust * 0.55 - 0.25) * rust;
	vec3 base = mix(b_alb, r_alb, r_mask);
	float base_r = mix(b_arm.g, r_arm.g, r_mask);
	float base_m = mix(base_metallic * b_arm.b + base_metallic * 0.4, 0.15, r_mask);
	vec3 alb = mix(base, pc, paint);
	float rough = mix(base_r, paint_roughness + fine * 0.12, paint);
	float metal = mix(clamp(base_m, 0.0, 1.0), paint_metallic, paint);
	float nstr = mix(base_normal_strength, paint_normal_strength, paint);
	// rust streaks running down from edges on walls
	float vert = 1.0 - smoothstep(0.3, 0.7, abs(n.y));
	float stk = smoothstep(0.6, 0.85, n3(vec3(opos.x * 7.0 + opos.z * 7.0, opos.y * 0.6, opos.z * 3.0) + vcol.b * 5.0)) * vert * streaks;
	alb = mix(alb, alb * mix(vec3(0.55, 0.42, 0.32), vec3(0.6), 1.0 - rust), stk * 0.6);
	// grime from the ground up + dust on top faces
	float g = (1.0 - smoothstep(0.0, grime_height, opos.y + (big - 0.5) * 0.4)) * grime;
	alb = mix(alb, alb * vec3(0.42, 0.38, 0.33), g);
	rough = mix(rough, 0.92, g);
	float d = smoothstep(0.55, 0.95, n.y) * dust * smoothstep(0.35, 0.7, fbm3(q * 3.0 + 5.0));
	alb = mix(alb, vec3(0.6, 0.55, 0.48), d * 0.7);
	rough = mix(rough, 0.95, d);
	// baked AO (vertex) + texture AO
	float ao = mix(1.0, vcol.g, ao_strength);
	ao *= mix(1.0, b_arm.r, 1.0 - paint * 0.7);
	alb *= mix(0.55, 1.0, ao);

	tx = vec3(tx.xy * nstr + n.zy, abs(tx.z) * n.x);
	ty = vec3(ty.xy * nstr + n.xz, abs(ty.z) * n.y);
	tz = vec3(tz.xy * nstr + n.xy, abs(tz.z) * n.z);
	vec3 on = normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);
	NORMAL = normalize((VIEW_MATRIX * (MODEL_MATRIX * vec4(on, 0.0))).xyz);

	ALBEDO = clamp(alb, 0.0, 1.0);
	ROUGHNESS = clamp(rough, 0.12, 1.0);
	METALLIC = clamp(metal, 0.0, 1.0);
	AO = ao;
	AO_LIGHT_AFFECT = 0.25;
	CLEARCOAT = clearcoat_amt * paint;
	CLEARCOAT_ROUGHNESS = 0.3;
}
