shader_type spatial;
// [globes] Verdance from space: rust-brown junk-covered continents that turn green as restoration
// rises (patches spreading from the lowlands outward), murky seas clearing to blue, polar caps
// going from grime-grey to white, and real relief (domain-warped FBM continents, ridged ranges).
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
	vec3 q = p * 1.45 + vec3(seed, seed * 0.7, -seed);
	vec3 wv = pl_warp(q * 1.3, min(oct, 4)) * 1.1;
	vec4 c = pl_fbmd(q + wv, oct, 0.5, 0.0);
	float h = c.x - 0.02;
	vec4 m = pl_ridged(p * 3.1 + wv * 1.6 + seed * 1.3, max(oct - 2, 2));
	float inland = smoothstep(0.02, 0.22, h);
	float mtn = m.x * inland;
	float land = smoothstep(-0.006, 0.012, h);
	vec3 grad = c.yzw * 0.6 + m.yzw * inland * 0.5;
	float lat = abs(p.y);

	float n1 = pl_fbm(p * 8.0 + seed, min(oct, 5));
	float n2 = pl_fbm(p * 21.0 + 3.0, min(oct, 4));
	// --- ruined land: rust, grey junk fields, scrap flecks
	vec3 rust = mix(vec3(0.15, 0.075, 0.035), vec3(0.38, 0.19, 0.08), n1);
	rust = mix(rust, vec3(0.3, 0.27, 0.24), smoothstep(0.56, 0.74, n2) * 0.6);
	float speck = oct >= 5 ? smoothstep(0.72, 0.92, pl_noise(p * 95.0 + 1.3)) : 0.0;
	rust = mix(rust, vec3(0.6, 0.55, 0.5), speck * 0.45);
	rust = mix(rust, vec3(0.26, 0.2, 0.16), smoothstep(0.15, 0.6, mtn));
	// --- restored land: forests, grassland, dry belts, brown ranges, snow peaks
	float dry = smoothstep(0.55, 0.8, pl_fbm(p * 3.0 + 11.0, 3)) * (1.0 - smoothstep(0.45, 0.7, lat));
	vec3 green = mix(vec3(0.04, 0.15, 0.04), vec3(0.15, 0.32, 0.08), n1);
	green = mix(green, vec3(0.42, 0.37, 0.2), dry * 0.8);
	green = mix(green, vec3(0.3, 0.26, 0.18), smoothstep(0.2, 0.55, mtn));
	green = mix(green, vec3(0.88, 0.9, 0.92), smoothstep(0.55, 0.75, mtn + lat * 0.3));
	// --- green spreads in patches (lowlands and wet coasts first)
	float s = clamp((pl_fbm(p * 2.3 + 7.0, 4) - 0.3) / 0.4, 0.0, 1.0) * 0.78 + 0.1 + 0.17 * mtn;
	float r = restoration * 1.12 - 0.03;
	float mask = smoothstep(s - 0.05, s + 0.05, r);
	float fringe = mask * (1.0 - mask) * 4.0;
	vec3 land_col = mix(rust, green, mask);
	land_col = mix(land_col, vec3(0.3, 0.42, 0.12), fringe * 0.35);

	// --- oceans: murky grey-teal, clearing to deep blue with turquoise shelves
	float ocean_r = smoothstep(0.05, 0.85, restoration);
	float depth = clamp(-h * 3.5, 0.0, 1.0);
	vec3 sea_ruin = mix(vec3(0.075, 0.085, 0.07), vec3(0.025, 0.035, 0.04), depth);
	sea_ruin = mix(sea_ruin, vec3(0.12, 0.1, 0.07), smoothstep(0.62, 0.8, pl_fbm(p * 6.0 + wv * 3.0, 4)) * 0.5);
	vec3 sea_ok = mix(vec3(0.03, 0.2, 0.28), vec3(0.006, 0.035, 0.12), sqrt(depth));
	vec3 sea = mix(sea_ruin, sea_ok, ocean_r);

	vec3 albedo = mix(sea, land_col, land);
	// --- polar caps
	float cap = smoothstep(0.8, 0.88, lat + 0.07 * (n1 - 0.5) * 2.0);
	albedo = mix(albedo, mix(vec3(0.5, 0.47, 0.43), vec3(0.9, 0.93, 0.96), ocean_r), cap);

	vec3 nb_o = pl_grad_normal(p, grad, bump * land * (1.0 - cap * 0.6));
	vec3 ng = normalize(w_n);
	vec3 nb = normalize(mat3(MODEL_MATRIX) * nb_o);
	vec3 v = normalize(CAMERA_POSITION_WORLD - w_p);
	vec3 lit = pl_light2(ng, nb, 0.1, 0.7);
	vec3 col = albedo * (lit + vec3(0.012, 0.014, 0.02));
	// sun glints on open water (dimmer through the smog)
	vec3 nw = normalize(mat3(MODEL_MATRIX) * pl_grad_normal(p, pl_noised(p * 60.0).yzw, 0.0007));
	col += (pl_spec2(ng, nw, v, 220.0, mix(0.04, 0.12, ocean_r)) + pl_spec2(ng, nw, v, 24.0, mix(0.02, 0.05, ocean_r))) * (1.0 - land) * (1.0 - cap);
	// night side: scattered junk fires when ruined, warm city lights on restored coasts
	float day = pl_daylight(ng);
	float fires = smoothstep(0.86, 0.97, pl_noise(p * 70.0 + 4.0)) * land * (1.0 - mask) * (1.0 - cap);
	float coast = 1.0 - smoothstep(0.0, 0.12, h);
	float city = smoothstep(0.6, 0.75, pl_fbm(p * 13.0 + 2.0, 3)) * smoothstep(0.55, 0.8, pl_noise(p * 80.0)) * land * mask * coast;
	col += (vec3(1.0, 0.42, 0.12) * fires * 0.22 + vec3(1.0, 0.8, 0.55) * city * 0.42) * (1.0 - day);
	// aerial haze toward the limb: dusty when ruined, blue when restored
	float fr = 1.0 - clamp(dot(ng, v), 0.0, 1.0);
	vec3 atmo = mix(vec3(0.55, 0.42, 0.3), vec3(0.32, 0.56, 1.0), restoration);
	col = mix(col, atmo * (lit + 0.01), pow(fr, 3.4) * mix(0.32, 0.26, restoration));
	ALBEDO = col;
}
