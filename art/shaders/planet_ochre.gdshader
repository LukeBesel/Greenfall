shader_type spatial;
// [globes] Ochre, the desert world closest to the suns: golden dune seas in the basins (crests and
// slip faces, faded out where they would alias), eroded plateaus with stratified canyon walls,
// a branching canyon network (iso-lines of warped noise), salt pans, and one giant terraced
// strip-mine scar (stepped benches and risers, spoil heaps on the rim). Restoration greens the
// canyon floors and floods the bottom of the pit.
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

#include "res://art/shaders/planet_lib.gdshaderinc"

uniform float bump = 0.035;
uniform float feature_bump = 1.0;
uniform vec3 mine_dir = vec3(0.42, 0.3, 0.86);
uniform float mine_radius = 0.33;
varying vec3 o_p;
varying vec3 w_n;
varying vec3 w_p;

void vertex() {
	o_p = VERTEX;
	w_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	w_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 p = normalize(o_p);
	int oct = octaves;
	vec3 wv = pl_warp(p * 1.8 + seed, min(oct, 4));
	vec4 b = pl_fbmd(p * 1.7 + wv * 0.9 + seed, oct, 0.5, 1.4);
	float n1 = pl_fbm(p * 7.0 + 2.0, min(oct, 5));

	// canyon network: thin iso-lines of a warped field, plus finer tributaries up close
	vec3 cw = pl_warp(p * 2.2 + 4.0, min(oct, 4)) * 1.1;
	float cn = pl_fbm(p * 3.3 + cw + 2.0, min(oct, 5));
	float rv = 1.0 - abs(cn - 0.5) * 2.0;
	float plateau = smoothstep(-0.12, 0.08, b.x);
	float canyon = smoothstep(0.9, 0.985, rv) * plateau;
	float canyon2 = 0.0;
	if (oct >= 6) {
		float cn2 = pl_fbm(p * 8.5 + cw * 2.0 + 9.0, 4);
		canyon2 = smoothstep(0.935, 0.99, 1.0 - abs(cn2 - 0.5) * 2.0) * plateau * (1.0 - canyon);
	}

	// dune seas in the low basins
	float sand = 1.0 - smoothstep(-0.16, 0.02, b.x);
	float ph = (p.x * 0.78 + p.z * 0.62 + p.y * 0.1) * 95.0 + pl_fbm(p * 5.0 + 1.0, 3) * 16.0 + pl_fbm(p * 14.0, 2) * 4.0;
	float fw = fwidth(ph);
	float f = fract(ph / 6.2831853);
	float prof = smoothstep(0.0, 0.78, f) * (1.0 - smoothstep(0.78, 1.0, f));
	float dune_fade = 1.0 - smoothstep(0.6, 2.2, fw);
	float dune = prof * dune_fade * (0.6 + 0.4 * n1);
	float erg = smoothstep(0.35, 0.6, pl_fbm(p * 3.6 + 5.0, 3));  // big star-dune fields
	float salt = smoothstep(0.62, 0.72, pl_fbm(p * 2.6 + 13.0, 4)) * sand * (1.0 - erg);

	// the strip mine
	float front = dot(p, normalize(mine_dir));
	vec2 xy = pl_tangent_xy(p, normalize(mine_dir));
	float e = length(vec2(xy.x, xy.y * 1.5)) + 0.03 * (pl_noise(p * 16.0) - 0.5) + 0.015 * (pl_noise(p * 45.0) - 0.5);
	float inside = clamp(1.0 - e / mine_radius, 0.0, 1.0) * step(0.0, front);
	float steps = 9.0;
	float tt = inside * steps;
	float riser = smoothstep(0.78, 1.0, fract(tt)) * step(0.001, inside);
	float terrace = (floor(tt) + riser) / steps;
	float spoil = exp(-pow((e - mine_radius * 1.08) / 0.035, 2.0)) * step(0.0, front);
	float in_mine = step(0.001, inside);
	float pit = smoothstep(0.86, 0.9, inside);

	float feat = -canyon * 0.26 - canyon2 * 0.09 + dune * sand * 0.035 * (0.5 + erg) - terrace * 0.3 + spoil * 0.05;
	float hraw = b.x * 0.5 + feat;
	vec3 nb_o = pl_grad_normal(p, b.yzw * 0.5 * (1.0 - in_mine * 0.8), bump);
	nb_o = pl_dd_normal(p, nb_o, feat * 0.02 * feature_bump);
	float slope = 1.0 - clamp(dot(nb_o, p), 0.0, 1.0);

	// colours by height, slope and latitude
	vec3 rock = mix(vec3(0.5, 0.28, 0.13), vec3(0.72, 0.47, 0.23), n1);
	float strata = 0.5 + 0.5 * sin(hraw * 110.0 + n1 * 3.0);
	rock *= 0.82 + 0.22 * mix(1.0, strata, smoothstep(0.02, 0.12, slope));
	rock = mix(rock, vec3(0.36, 0.19, 0.1), smoothstep(0.08, 0.3, slope) * 0.7);
	vec3 sand_c = mix(vec3(0.6, 0.38, 0.17), vec3(0.88, 0.66, 0.34), prof * dune_fade * 0.8 + n1 * 0.3);
	vec3 albedo = mix(rock, sand_c, sand);
	albedo = mix(albedo, vec3(0.88, 0.82, 0.68), salt);
	vec3 floor_c = vec3(0.34, 0.15, 0.08);
	albedo = mix(albedo, floor_c, max(canyon, canyon2 * 0.8));
	vec3 bench = mix(vec3(0.62, 0.56, 0.47), vec3(0.5, 0.44, 0.38), pl_noise(p * 60.0));
	vec3 mine_c = mix(bench, vec3(0.3, 0.26, 0.23), riser);
	mine_c = mix(mine_c, vec3(0.17, 0.15, 0.14), pit);
	albedo = mix(albedo, mine_c, in_mine);
	albedo = mix(albedo, vec3(0.74, 0.62, 0.48), spoil * 0.7);
	albedo = mix(albedo, vec3(0.95, 0.9, 0.82), smoothstep(0.92, 0.98, abs(p.y)) * 0.6);  // thin frost caps

	// restoration: oases along canyon floors, terraced farms in the pit, a pit lake
	float sr = clamp((pl_fbm(p * 2.8 + 21.0, 3) - 0.3) / 0.4, 0.0, 1.0) * 0.8 + 0.1;
	float grow = smoothstep(sr - 0.06, sr + 0.06, restoration * 1.1);
	float wet = max(canyon, canyon2) + sand * 0.15 * smoothstep(0.55, 0.7, n1);
	albedo = mix(albedo, mix(vec3(0.12, 0.26, 0.08), vec3(0.24, 0.36, 0.12), n1), clamp(wet * grow, 0.0, 1.0) * 0.85);
	albedo = mix(albedo, vec3(0.22, 0.38, 0.12), in_mine * (1.0 - riser) * (1.0 - pit) * smoothstep(0.35, 0.9, restoration) * 0.7);
	float lake = pit * smoothstep(0.2, 0.7, restoration);
	albedo = mix(albedo, vec3(0.02, 0.17, 0.22), lake);

	vec3 ng = normalize(w_n);
	vec3 nb = normalize(mat3(MODEL_MATRIX) * nb_o);
	vec3 v = normalize(CAMERA_POSITION_WORLD - w_p);
	vec3 lit = pl_light2(ng, nb, 0.09, 0.6);
	vec3 col = albedo * (lit + vec3(0.016, 0.012, 0.01));
	col += pl_spec2(ng, ng, v, 90.0, 0.6) * lake;
	col += pl_spec2(ng, nb, v, 14.0, 0.05) * salt;
	// night: a few working lights in the pit (ruined), oasis towns (restored)
	float day = pl_daylight(ng);
	float lights = smoothstep(0.88, 0.97, pl_noise(p * 85.0 + 7.0)) * (in_mine * (1.0 - restoration) + wet * grow * 0.7);
	col += vec3(1.0, 0.62, 0.3) * lights * 0.35 * (1.0 - day);
	float fr = 1.0 - clamp(dot(ng, v), 0.0, 1.0);
	col = mix(col, vec3(0.92, 0.66, 0.4) * (lit + 0.01), pow(fr, 3.0) * mix(0.36, 0.28, restoration));
	ALBEDO = col;
}
