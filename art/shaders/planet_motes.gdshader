shader_type spatial;
// [globes] Billboard motes for planet ring/debris MultiMeshes: Anvil's embers (hot, flickering,
// additive, thin), Ochre's drifting dust grains and Rime's ice glitter (lit by both suns, in the
// planet's shadow when behind it). INSTANCE_CUSTOM: x = phase, y = heat 0..1, z = brightness.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://art/shaders/planet_lib.gdshaderinc"

uniform vec3 col_hot = vec3(1.0, 0.62, 0.28);
uniform vec3 col_cool = vec3(0.7, 0.16, 0.04);
uniform float intensity = 1.0;
uniform float flicker = 0.5;
uniform float sunlit = 0.0;  // 0 = self-lit embers, 1 = reflects the suns (dust, ice)
uniform float planet_r_world = 1.0;
varying vec3 w_c;
varying vec4 custom;

void vertex() {
	w_c = MODEL_MATRIX[3].xyz;
	custom = INSTANCE_CUSTOM;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float a = exp(-r * r * 4.5) * (1.0 - smoothstep(0.85, 1.0, r));
	float ph = custom.x;
	float fl = mix(1.0, 0.55 + 0.45 * sin(TIME * (1.5 + ph * 2.5) + ph * 40.0), flicker);
	vec3 col = mix(col_cool, col_hot, custom.y) * intensity * custom.z * fl;
	if (sunlit > 0.0) {
		vec3 center = NODE_POSITION_WORLD;
		vec3 la = normalize(sun_a_dir);
		vec3 lb = normalize(sun_b_dir);
		vec3 light = sun_a_col * pl_planet_shadow(w_c, center, planet_r_world, la) + sun_b_col * pl_planet_shadow(w_c, center, planet_r_world, lb);
		col = mix(col, col * light, sunlit);
	}
	ALBEDO = col * a;
}
