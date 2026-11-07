shader_type spatial;
// [globes] Anvil, the red foundry world: rust-red dust highlands, dark basalt lowlands, ridged
// mountain ranges, a great rift canyon with branching side canyons, a few impact craters, and thin
// glowing lava/foundry seams in the lowlands and canyon floors (a soft core and halo, brighter on
// the night side; thin and subtle, never neon). Restoration cools the seams and greens the rift.
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

#include "res://art/shaders/planet_lib.gdshaderinc"

uniform float bump = 0.045;
uniform float feature_bump = 1.0;
uniform vec3 tint = vec3(1.0, 1.0, 1.0);  // generic rocky worlds reuse this shader
uniform float seams = 1.0;
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
	vec3 wv = pl_warp(p * 1.7 + seed, min(oct, 4)) * 1.0;
	vec4 b = pl_fbmd(p * 1.5 + wv + seed, oct, 0.5, 1.2);
	vec4 m = pl_ridged(p * 3.2 + wv * 1.4 + seed * 2.0, max(oct - 1, 2));
	float high = smoothstep(-0.05, 0.25, b.x);
	float mtn = m.x * high;
	float n1 = pl_fbm(p * 9.0 + 3.0, min(oct, 5));

	// the great rift: a band along a great circle, wandering, on one face of the world
	vec3 k = normalize(vec3(0.25, 0.92, -0.3));
	float g = dot(p, k) + 0.16 * (pl_fbm(p * 2.2 + 2.0, 4) - 0.5) + 0.03 * (pl_fbm(p * 9.0, 3) - 0.5);
	float rw = 0.6 + 0.8 * pl_fbm(p * 3.0 + 11.0, 3);
	float arc = smoothstep(0.05, 0.55, dot(p, normalize(vec3(0.85, 0.0, 0.5))));
	float wg = max(fwidth(g), 0.004);
	float rift = (1.0 - smoothstep(0.006 * rw, 0.026 * rw + wg, abs(g))) * arc;
	float rift_wall = (1.0 - smoothstep(0.015 * rw, 0.055 * rw, abs(g))) * arc;
	// side canyons: iso-lines of a warped field near the rift and in the highlands
	float cf = pl_fbm(p * 5.0 + wv * 1.6 + 8.0, min(oct, 5));
	float side = (1.0 - smoothstep(0.0, max(fwidth(cf) * 1.4, 0.012), abs(cf - 0.5))) * high * 0.8;
	// craters
	float crater_h = 0.0;
	float crater_rim = 0.0;
	for (int i = 0; i < 7; i++) {
		vec3 c = normalize(pl_hash3(vec3(float(i) * 3.71, seed, 5.3)) * 2.0 - 1.0);
		float rr = 0.05 + 0.1 * pl_hash(vec3(float(i), 2.0, seed));
		float d = acos(clamp(dot(p, c), -1.0, 1.0));
		float bowl = 1.0 - smoothstep(0.0, rr, d);
		float rim = exp(-pow((d - rr) / (rr * 0.2), 2.0));
		crater_h += -bowl * bowl * 0.5 + rim * 0.25;
		crater_rim = max(crater_rim, rim);
	}
	// lava / foundry seams in the low basins and along the rift floor
	float lf = pl_fbm(p * 4.2 + wv * 2.2 + 17.0, min(oct, 5));
	float low = 1.0 - smoothstep(-0.2, 0.05, b.x);
	float seam = (1.0 - smoothstep(0.0, max(fwidth(lf) * 1.3, 0.006), abs(lf - 0.5))) * low;
	float seam_halo = (1.0 - smoothstep(0.0, 0.045, abs(lf - 0.5))) * low;
	float rift_lava = rift * smoothstep(0.45, 0.7, pl_noise(p * 30.0 + 2.0));
	float foundry = smoothstep(0.9, 0.97, pl_noise(p * 46.0 + 5.0)) * max(seam_halo, rift) ;

	float feat = -rift * 0.35 - side * 0.12 + crater_h * 0.08 - seam * 0.02;
	vec3 nb_o = pl_grad_normal(p, b.yzw * 0.45 + m.yzw * high * 0.45, bump);
	nb_o = pl_dd_normal(p, nb_o, feat * 0.025 * feature_bump);
	float slope = 1.0 - clamp(dot(nb_o, p), 0.0, 1.0);

	vec3 dust = mix(vec3(0.45, 0.17, 0.07), vec3(0.66, 0.32, 0.15), n1);
	vec3 basalt = mix(vec3(0.15, 0.07, 0.05), vec3(0.24, 0.1, 0.06), n1);
	vec3 albedo = mix(basalt, dust, high);
	albedo = mix(albedo, vec3(0.3, 0.13, 0.08), smoothstep(0.2, 0.55, mtn));
	albedo = mix(albedo, vec3(0.7, 0.42, 0.25), smoothstep(0.55, 0.8, mtn) * 0.6);  // dusty peaks
	albedo = mix(albedo, vec3(0.24, 0.1, 0.06), smoothstep(0.06, 0.25, slope) * 0.6);
	albedo = mix(albedo, vec3(0.2, 0.08, 0.05), max(rift_wall * 0.7, side * 0.6));
	albedo = mix(albedo, vec3(0.62, 0.36, 0.22), crater_rim * 0.35);
	albedo = mix(albedo, vec3(0.86, 0.8, 0.76), smoothstep(0.88, 0.94, abs(p.y) + 0.03 * n1));
	// restoration: green creeps along the rift floor and the low basins
	float grow = smoothstep(0.25, 0.95, restoration);
	albedo = mix(albedo, vec3(0.16, 0.25, 0.08), (rift_wall * 0.8 + low * 0.25 * smoothstep(0.5, 0.7, n1)) * grow);
	albedo *= tint;

	vec3 ng = normalize(w_n);
	vec3 nb = normalize(mat3(MODEL_MATRIX) * nb_o);
	vec3 v = normalize(CAMERA_POSITION_WORLD - w_p);
	vec3 lit = pl_light2(ng, nb, 0.1, 0.5);
	vec3 col = albedo * (lit + vec3(0.014, 0.01, 0.009));
	float day = pl_daylight(ng);
	float flick = 0.85 + 0.15 * sin(TIME * 1.3 + n1 * 25.0);
	float heat = (seam * 0.55 + seam_halo * 0.12 + rift_lava * 0.4 + foundry * 0.5) * seams * flick * (1.0 - grow * 0.7);
	vec3 lava = mix(vec3(1.0, 0.28, 0.05), vec3(1.0, 0.62, 0.28), clamp(seam + foundry, 0.0, 1.0));
	col += lava * heat * mix(0.35, 0.8, 1.0 - day);
	float fr = 1.0 - clamp(dot(ng, v), 0.0, 1.0);
	col = mix(col, vec3(0.8, 0.45, 0.28) * (lit + 0.01), pow(fr, 3.2) * mix(0.3, 0.22, restoration));
	ALBEDO = col;
}
