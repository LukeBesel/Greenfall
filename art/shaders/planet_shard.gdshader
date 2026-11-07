shader_type spatial;
// [globes] Faceted ice shards for Rime's orbiting ring of ice spikes (MultiMesh): glassy pale-blue
// ice lit by both suns (each with the planet's shadow), a sharp glint per sun, a cold fresnel rim
// and a faint inner glow so the ring stays luminous in the dim far-sun light.
// INSTANCE_CUSTOM: x = tint variation, y = glow.
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

#include "res://art/shaders/planet_lib.gdshaderinc"

uniform vec3 ice_a = vec3(0.78, 0.9, 1.0);
uniform vec3 ice_b = vec3(0.45, 0.68, 0.95);
uniform vec3 glow_col = vec3(0.3, 0.6, 1.0);
uniform float planet_r_world = 1.0;
varying vec3 w_n;
varying vec3 w_p;
varying vec4 custom;

void vertex() {
	w_n = normalize(mat3(MODEL_MATRIX) * NORMAL);
	w_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	custom = INSTANCE_CUSTOM;
}

void fragment() {
	vec3 n = normalize(w_n);
	if (!FRONT_FACING) {
		n = -n;
	}
	vec3 v = normalize(CAMERA_POSITION_WORLD - w_p);
	vec3 center = NODE_POSITION_WORLD;
	vec3 la = normalize(sun_a_dir);
	vec3 lb = normalize(sun_b_dir);
	float sa = pl_planet_shadow(w_p, center, planet_r_world, la);
	float sb = pl_planet_shadow(w_p, center, planet_r_world, lb);
	vec3 albedo = mix(ice_a, ice_b, custom.x);
	vec3 diff = sun_a_col * sa * (clamp(dot(n, la), 0.0, 1.0) * 0.8 + 0.2) + sun_b_col * sb * (clamp(dot(n, lb), 0.0, 1.0) * 0.8 + 0.2);
	float pa = pow(clamp(dot(n, normalize(la + v)), 0.0, 1.0), 90.0) * 3.0;
	float pb = pow(clamp(dot(n, normalize(lb + v)), 0.0, 1.0), 90.0) * 3.0;
	vec3 col = albedo * (diff + vec3(0.03, 0.04, 0.06));
	col += sun_a_col * pa * sa + sun_b_col * pb * sb;
	float fr = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 3.0);
	col += glow_col * (fr * 0.35 + custom.y * 0.12);
	ALBEDO = col;
}
