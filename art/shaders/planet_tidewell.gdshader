shader_type spatial;
// [globes] Tidewell, the ocean world: deep blue water with depth (turquoise reef shelves, dark
// trenches), volcanic island chains strung along ridges with green interiors, and specular glints
// from both suns on a rippled sea (each sun's own glint and colour). Ruined: grey-green water with
// drifting garbage gyres; restored: clear water and green islands.
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

#include "res://art/shaders/planet_lib.gdshaderinc"

uniform float bump = 0.05;
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
	vec3 wv = pl_warp(p * 1.6 + seed, min(oct, 4)) * 1.2;
	vec4 sea = pl_fbmd(p * 1.4 + wv + seed, oct, 0.5, 0.0);  // sea floor
	// island chains: crests of a warped ridge field, broken up by finer noise into archipelagos
	vec4 r = pl_ridged(p * 2.4 + wv * 1.4 + 3.0, max(oct - 2, 2));
	float chain = smoothstep(0.55, 0.85, r.x);
	vec4 isl = pl_fbmd(p * 11.0 + wv * 2.0, max(oct - 2, 2), 0.5, 0.6);
	float ih = chain * 0.7 + isl.x * 0.55 + smoothstep(0.35, 0.6, sea.x) * 0.5 - 0.62;
	float land = smoothstep(-0.005, 0.01, ih);
	float shelf = smoothstep(-0.22, 0.0, ih);
	float depth = clamp(0.5 - sea.x * 0.7, 0.0, 1.0);

	float ocean_r = smoothstep(0.05, 0.85, restoration);
	vec3 deep_ok = mix(vec3(0.012, 0.06, 0.2), vec3(0.004, 0.018, 0.08), depth);
	vec3 deep_ruin = mix(vec3(0.05, 0.08, 0.08), vec3(0.02, 0.035, 0.04), depth);
	vec3 water = mix(deep_ruin, deep_ok, ocean_r);
	water = mix(water, mix(vec3(0.1, 0.16, 0.12), vec3(0.06, 0.42, 0.48), ocean_r), shelf * shelf * 0.85);
	// garbage gyres (ruined): brown swirls in the open sea
	float gyre = smoothstep(0.6, 0.75, pl_fbm(p * 4.0 + wv * 3.0 + 8.0, min(oct, 5))) * (1.0 - shelf) * (1.0 - ocean_r);
	water = mix(water, vec3(0.16, 0.13, 0.09), gyre * 0.6);

	float n1 = pl_fbm(p * 30.0, min(oct, 4));
	vec3 isle = mix(vec3(0.42, 0.36, 0.26), vec3(0.2, 0.17, 0.14), smoothstep(0.1, 0.35, ih));  // beach -> basalt
	vec3 jungle = mix(vec3(0.04, 0.2, 0.06), vec3(0.12, 0.32, 0.08), n1);
	isle = mix(isle, jungle, smoothstep(0.02, 0.08, ih) * mix(0.25, 1.0, ocean_r));
	isle = mix(isle, vec3(0.92, 0.88, 0.8), smoothstep(0.012, 0.0, ih) * 0.6);  // surf/sand rim
	vec3 albedo = mix(water, isle, land);
	float cap = smoothstep(0.9, 0.96, abs(p.y) + 0.04 * (n1 - 0.5));
	albedo = mix(albedo, vec3(0.86, 0.9, 0.95), cap);

	vec3 grad = (isl.yzw * 0.55 + r.yzw * 0.4) * land;
	vec3 nb_o = pl_grad_normal(p, grad, bump);
	vec3 ng = normalize(w_n);
	vec3 nb = normalize(mat3(MODEL_MATRIX) * nb_o);
	vec3 v = normalize(CAMERA_POSITION_WORLD - w_p);
	vec3 lit = pl_light2(ng, nb, 0.1, 0.7);
	vec3 col = albedo * (lit + vec3(0.01, 0.014, 0.022));
	// rippled sea: a broad sheen and a tight glint per sun
	vec3 ripple = pl_noised(p * 70.0 + vec3(0.0, TIME * 0.05, 0.0)).yzw + pl_noised(p * 190.0).yzw * 0.5;
	vec3 nw = normalize(mat3(MODEL_MATRIX) * pl_grad_normal(p, ripple, 0.0035));
	float wet = (1.0 - land) * (1.0 - cap);
	col += (pl_spec2(ng, nw, v, 22.0, 0.08) + pl_spec2(ng, nw, v, 260.0, 0.65)) * wet * mix(0.55, 1.0, ocean_r);
	float day = pl_daylight(ng);
	float town = smoothstep(0.78, 0.92, pl_noise(p * 120.0)) * land * smoothstep(0.0, 0.05, ih) * (1.0 - smoothstep(0.1, 0.2, ih));
	col += vec3(1.0, 0.78, 0.5) * town * 0.4 * ocean_r * (1.0 - day);
	float fr = 1.0 - clamp(dot(ng, v), 0.0, 1.0);
	col = mix(col, vec3(0.35, 0.6, 1.0) * (lit + 0.012), pow(fr, 2.4) * 0.5);
	ALBEDO = col;
}
