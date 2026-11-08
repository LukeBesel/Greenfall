shader_type spatial;
// Worn paint for the hero bot (art/models/aurora), v2 matched to the owner's Aurora concept:
// glossy clear-coated cream paint with lighter worn edges; dark speckle chips (exposed dark metal)
// dense on edges, around joints and on the top of the head, sparse elsewhere, in two sizes plus a
// few bigger flakes; tiny rust/dirt specks; fine scratches; grime in seams and cavities and short
// streaks running down from them; dust on top faces. All of it per pixel in object space (locked to
// the mesh), driven by the per-vertex masks baked in Blender: R = ambient occlusion, G = convex edge
// wear, B = cavity dirt, A = 1 - joint wear. A soft fresnel rim, warm peach on the sun side and cool
// cyan on the shadow side (like the concept's rim light). Colours stay parameters (character builder).
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 paint_color : source_color = vec4(0.9, 0.9, 0.87, 1.0);
uniform float paint_coverage : hint_range(0.0, 1.0) = 0.86;
uniform float rust_amount : hint_range(0.0, 1.0) = 0.25;
uniform float fade : hint_range(0.0, 1.0) = 0.2;
uniform float grime : hint_range(0.0, 1.0) = 0.5;
uniform float dust : hint_range(0.0, 1.0) = 0.4;
uniform float edge_wear : hint_range(0.0, 1.0) = 0.6;
uniform float specks : hint_range(0.0, 1.0) = 0.8;      // dark speckle chip amount
uniform float metallic_bare = 0.85;
uniform float paint_metallic = 0.0;
uniform float paint_roughness = 0.42;
uniform float clearcoat = 0.0;                          // glossy lacquer over the paint
uniform float tex_scale = 2.4;
uniform float seed = 0.0;
uniform float ao_strength = 1.0;
uniform vec4 chip_color : source_color = vec4(0.11, 0.115, 0.125, 1.0);  // dark metal under the paint
uniform vec4 rust_color : source_color = vec4(0.42, 0.22, 0.1, 1.0);
uniform vec4 rim_color : source_color = vec4(0.62, 0.85, 1.0, 1.0);      // shadow-side rim (cool)
uniform vec4 rim_warm : source_color = vec4(1.0, 0.72, 0.5, 1.0);        // sun-side rim (peach)
uniform float rim_strength = 0.07;
uniform float moss : hint_range(0.0, 1.0) = 0.0;
uniform vec4 moss_color : source_color = vec4(0.27, 0.38, 0.12, 1.0);
uniform float stripes : hint_range(0.0, 1.0) = 0.0;
uniform vec4 stripe_color : source_color = vec4(0.08, 0.075, 0.07, 1.0);
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

vec3 h33(vec3 p) {
	return vec3(h31(p), h31(p + vec3(17.3, 5.1, 9.7)), h31(p + vec3(3.7, 31.1, 13.3)));
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

// Cellular: (distance to the nearest feature point, that cell's random value).
vec2 cell(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float d = 9.0;
	float id = 0.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 r = g + h33(i + g) - f;
				float dd = dot(r, r);
				if (dd < d) {
					d = dd;
					id = h31(i + g + 11.0);
				}
			}
		}
	}
	return vec2(sqrt(d), id);
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
	vec3 r_nrm = tri(rust_nrm, p * 0.7, w).rgb;

	float ao = vcol.r;
	float edge = vcol.g;
	float cav = vcol.b;
	float joint = 1.0 - vcol.a;
	vec3 q = opos * 6.0 + vec3(seed);
	float big = fbm3(q);
	float fine = fbm3(q * 4.0 + 3.0);
	// Where the wear gathers: convex edges, joints, the top (up-facing) and broad patches.
	float up = smoothstep(0.35, 0.95, onrm.y);
	float patch_ = smoothstep(0.42, 0.7, big);
	float dens = clamp(edge * edge_wear * 1.5 + joint * 0.7 + up * 0.45 + patch_ * 0.35, 0.0, 1.0);
	// Ragged dark speckle chips in two sizes (cells warped by noise) plus a few big flakes on edges.
	vec3 wp = opos + (vec3(n3(opos * 60.0), n3(opos * 60.0 + 7.0), n3(opos * 60.0 + 13.0)) - 0.5) * 0.006;
	float r1 = 0.08 + 0.24 * dens;
	vec2 c1 = cell(wp * 95.0 + seed);
	float on1 = step(c1.y, 0.04 + 0.7 * dens * dens);
	float sp1 = (1.0 - smoothstep(0.0, 0.05, c1.x - r1)) * on1;
	vec2 c2 = cell(wp * 210.0 + seed * 2.0);
	float sp2 = (1.0 - smoothstep(0.0, 0.08, c2.x - (0.12 + 0.2 * dens))) * step(c2.y, 0.03 + 0.45 * dens * dens);
	vec2 c3 = cell(wp * 34.0 + seed * 3.0);
	float fl_r = 0.34 * smoothstep(0.35, 1.0, edge * edge_wear * 1.4 + joint * 0.5);
	float flake = (1.0 - smoothstep(0.0, 0.04, c3.x - fl_r)) * step(c3.y, 0.55) * step(0.001, fl_r);
	float chips = clamp(max(max(sp1, sp2 * 0.9), flake), 0.0, 1.0) * specks;
	// Paint cover: chips (dark metal) and very worn edges where the coverage runs out.
	float worn_n = big * 0.45 + fine * 0.55 - edge * edge_wear * 0.9 - joint * 0.3;
	float bare_edge = 1.0 - smoothstep(1.0 - paint_coverage - 0.04, 1.0 - paint_coverage + 0.04, worn_n);
	float paint = (1.0 - chips) * (1.0 - bare_edge);
	// Rust / dirt specks (tiny, warm brown).
	vec2 c4 = cell(opos * 330.0 + seed * 5.0);
	float rs = (1.0 - smoothstep(0.0, 0.08, c4.x - 0.2)) * step(c4.y, 0.12 + rust_amount * 0.3) * smoothstep(0.35, 0.7, fbm3(q * 1.6 + 40.0));
	// Colours.
	vec3 pc = paint_color.rgb;
	pc = mix(pc, vec3(dot(pc, vec3(0.33))), fade * 0.4);
	pc *= mix(0.94, 1.03, fine);
	// Lighter, slightly chalky worn edges and a thin light halo round each chip.
	float worn_light = clamp(edge * edge_wear * 1.2 + joint * 0.3, 0.0, 1.0) * smoothstep(0.3, 0.6, fine + 0.15);
	pc = mix(pc, mix(pc, vec3(1.0, 0.98, 0.95), 0.35), worn_light * 0.6);
	float halo = (1.0 - smoothstep(0.0, 0.03, abs(c1.x - r1))) * on1;
	pc = mix(pc, pc * 1.08, halo * 0.5);
	// [skins] Hazard chevrons painted across the part (worn with the paint).
	float stp = step(0.5, fract((opos.x + opos.y * 0.9 - opos.z * 0.4) * 11.0 + seed * 0.37));
	pc = mix(pc, stripe_color.rgb * mix(0.9, 1.1, fine), stp * stripes);
	vec3 bare = mix(chip_color.rgb, m_alb * 0.5, 0.35) * mix(0.8, 1.15, fine);
	vec3 alb = mix(bare, pc, paint);
	alb = mix(alb, rust_color.rgb * mix(0.7, 1.2, fine), rs * 0.85);
	vec3 nrm = mix(mix(m_nrm, r_nrm, rs), mix(vec3(0.5, 0.5, 1.0), m_nrm, 0.12), paint);
	float rough = mix(mix(0.32, m_arm.g * 0.7, 0.4), paint_roughness + fine * 0.1, paint);
	rough = mix(rough, 0.85, rs);
	float metal = mix(metallic_bare, paint_metallic, paint);
	metal = mix(metal, 0.0, rs);
	// Fine scratches (two directions, patchy, more on edges and joints): bright bare metal lines.
	float scr = smoothstep(0.986, 1.0, n3(vec3(opos.x * 170.0, opos.y * 8.0, opos.z * 170.0) + seed));
	scr = max(scr, smoothstep(0.988, 1.0, n3(vec3(opos.y * 170.0 + opos.x * 60.0, opos.x * 7.0, opos.z * 170.0) + seed + 9.0)));
	scr *= clamp(smoothstep(0.35, 0.7, fbm3(q * 0.9 + 41.0)) + edge * 0.6 + joint * 0.6, 0.0, 1.0);
	alb = mix(alb, m_alb * 0.95 + 0.1, scr * paint * 0.55);
	rough = mix(rough, 0.3, scr * paint * 0.5);
	// Grime: seams / cavities / occlusion, short streaks running down from them, broad stains.
	float g = clamp(cav * 1.3 + (1.0 - ao) * 0.9, 0.0, 1.0);
	float streak = smoothstep(0.55, 0.85, n3(vec3(opos.x * 34.0, opos.y * 3.0, opos.z * 34.0) + seed)) * (1.0 - smoothstep(-0.2, 0.6, onrm.y));
	g = max(g, streak * 0.55);
	g = max(g, smoothstep(0.58, 0.85, fbm3(q * 1.3 + 21.0)) * 0.4);
	g *= grime;
	alb = mix(alb, alb * vec3(0.42, 0.36, 0.3), g);
	rough = mix(rough, 0.85, g * 0.8);
	float d = up * dust * smoothstep(0.4, 0.8, fbm3(q * 3.0));
	alb = mix(alb, vec3(0.62, 0.55, 0.47), d * 0.55);
	rough = mix(rough, 0.9, d * 0.8);
	// [skins] Moss: soft green cushions on top faces, in cavities and along seams.
	if (moss > 0.0) {
		float mz = fbm3(q * 1.15 + 31.0) + smoothstep(-0.1, 0.9, onrm.y) * 0.32 + cav * 0.35 + (1.0 - ao) * 0.2;
		float mm = smoothstep(0.78, 0.92, mz + moss * 0.25) * moss;
		vec3 mc = moss_color.rgb * mix(0.65, 1.25, fbm3(q * 7.0 + 2.0)) * mix(vec3(1.0), vec3(1.15, 1.1, 0.7), fine * 0.6);
		alb = mix(alb, mc, mm);
		rough = mix(rough, 0.92, mm);
		metal = mix(metal, 0.0, mm);
	}
	ALBEDO = alb;
	NORMAL_MAP = nrm;
	ROUGHNESS = clamp(rough, 0.08, 1.0);
	METALLIC = metal;
	CLEARCOAT = clearcoat * paint * (1.0 - g * 0.8) * (1.0 - d);
	CLEARCOAT_ROUGHNESS = 0.12 + fine * 0.1;
	AO = mix(1.0, ao, ao_strength);
	AO_LIGHT_AFFECT = 0.4;
	// Fresnel rim: warm peach where the surface faces the sun, cool cyan on the shadow side.
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float sunward = clamp(dot(wnrm, normalize(sun_dir)) * 0.5 + 0.5, 0.0, 1.0);
	vec3 rim = mix(rim_color.rgb, rim_warm.rgb, smoothstep(0.35, 0.8, sunward));
	EMISSION = rim * fres * rim_strength * mix(0.5, 1.0, ao) * (0.4 + 0.6 * paint);
}
