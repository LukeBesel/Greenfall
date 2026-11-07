shader_type spatial;
// [globes] Rime, the ice moon farthest from the suns: cracked glassy ice plates (cellular noise)
// with deep blue fault lines that glow faintly from within, pressure ridges along the faults, long
// Europa-like lineae, finer cracks up close, bright polar frost caps, and a glassy double glint.
// Pale and luminous: the faults and a soft inner glow carry the dim far-sun light. Restoration
// opens teal meltwater pools and warms the fault glow.
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

#include "res://art/shaders/planet_lib.gdshaderinc"

uniform float bump = 0.025;
uniform float feature_bump = 1.0;
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
	vec3 wv = pl_warp(p * 2.4 + seed, min(oct, 3)) * 0.55;
	vec4 b = pl_fbmd(p * 2.0 + seed, oct, 0.5, 0.0);
	vec3 c1 = pl_cells(p * 3.4 + wv + seed);
	float e1 = c1.y - c1.x;
	float w1 = max(fwidth(e1) * 1.2, 0.025);
	float fault = 1.0 - smoothstep(0.0, w1, e1);
	float ridge = exp(-pow(e1 / 0.13, 2.0));
	float crack2 = 0.0;
	float plate2 = 0.5;
	if (oct >= 6) {
		vec3 c2 = pl_cells(p * 10.0 + wv * 2.0 + 4.0);
		float e2 = c2.y - c2.x;
		crack2 = 1.0 - smoothstep(0.0, max(fwidth(e2) * 1.2, 0.03), e2);
		plate2 = c2.z;
	}
	// lineae: long thin iso-line cracks of two warped fields
	float l1 = pl_fbm(p * 1.9 + wv * 1.5 + 6.0, min(oct, 4));
	float l2 = pl_fbm(p * 2.6 - wv * 1.2 + 15.0, min(oct, 4));
	float wl = max(fwidth(l1) * 1.5, 0.004);
	float lin = max(1.0 - smoothstep(0.0, wl, abs(l1 - 0.5)), (1.0 - smoothstep(0.0, wl, abs(l2 - 0.52))) * 0.8);
	float lat = abs(p.y);
	float cap = smoothstep(0.7, 0.82, lat + 0.06 * (b.x));
	float crackk = 1.0 - cap * 0.75;

	vec3 ice = mix(vec3(0.74, 0.83, 0.93), vec3(0.88, 0.9, 0.92), c1.z);
	ice = mix(ice, vec3(0.86, 0.83, 0.78), smoothstep(0.75, 0.95, c1.z) * 0.5);  // old creamy plates
	ice *= 0.92 + 0.12 * plate2;
	ice = mix(ice, vec3(0.93, 0.95, 0.98), ridge * 0.35);
	vec3 faultc = vec3(0.1, 0.34, 0.75);
	vec3 albedo = mix(ice, faultc, fault * crackk);
	albedo = mix(albedo, vec3(0.35, 0.55, 0.82), max(crack2 * 0.55, lin * 0.7) * crackk);
	albedo = mix(albedo, vec3(0.95, 0.97, 1.0), cap * 0.85);
	// restoration: teal meltwater pools in some plates
	float pools = smoothstep(0.86, 0.9, pl_fbm(p * 5.0 + 3.0, 4)) * smoothstep(0.3, 0.9, restoration) * (1.0 - cap);
	albedo = mix(albedo, vec3(0.04, 0.3, 0.36), pools);

	float feat = ridge * 0.4 - fault * 0.7 - crack2 * 0.2 - lin * 0.25;
	vec3 nb_o = pl_grad_normal(p, b.yzw * 0.4, bump);
	nb_o = pl_dd_normal(p, nb_o, feat * 0.012 * feature_bump);
	vec3 ng = normalize(w_n);
	vec3 nb = normalize(mat3(MODEL_MATRIX) * nb_o);
	vec3 v = normalize(CAMERA_POSITION_WORLD - w_p);
	vec3 lit = pl_light2(ng, nb, 0.14, 0.15);
	vec3 col = albedo * (lit + vec3(0.03, 0.04, 0.06));
	// glassy: a broad satin sheen and a sharp glint per sun
	col += (pl_spec2(ng, nb, v, 16.0, 0.05) + pl_spec2(ng, nb, v, 140.0, 0.35)) * (1.0 - fault * 0.5);
	col += pl_spec2(ng, ng, v, 300.0, 0.8) * pools;
	// luminous: faults and lineae glow faintly from within (stronger on the night side)
	float day = pl_daylight(ng);
	vec3 glow = mix(vec3(0.12, 0.42, 1.0), vec3(0.2, 0.85, 0.9), restoration);
	col += glow * (fault * 0.1 + lin * 0.05 + crack2 * 0.03) * crackk * (0.35 + 0.65 * (1.0 - day));
	col += albedo * vec3(0.03, 0.045, 0.07) * (1.0 - day);  // soft inner light, never pitch black
	float fr = 1.0 - clamp(dot(ng, v), 0.0, 1.0);
	col = mix(col, vec3(0.7, 0.85, 1.0) * (lit + 0.04), pow(fr, 3.0) * 0.45);
	ALBEDO = col;
}
