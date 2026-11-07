shader_type spatial;
// [globes] A flat ring band around a planet globe (Ochre's sand/dust ring, Rime's ice dust, Anvil's
// ash band). UV.x runs 0 (inner edge) .. 1 (outer edge). Fine radial bands and gaps, clumps along
// the orbit, lit by both suns with the planet's shadow across it and a forward-scatter brightening
// when backlit (dust lights up against the sun). `ember` adds a thin warm self-glow (Anvil).
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://art/shaders/planet_lib.gdshaderinc"

uniform vec3 col_a = vec3(0.85, 0.65, 0.4);
uniform vec3 col_b = vec3(0.6, 0.42, 0.25);
uniform float opacity = 0.35;
uniform float band_freq = 34.0;
uniform float gaps = 0.5;
uniform float clumps = 0.4;
uniform float scatter = 1.2;
uniform float inner_fade = 0.18;
uniform float outer_fade = 0.45;
uniform vec3 ember = vec3(0.0);
uniform float planet_r_world = 1.0;
varying vec3 w_p;
varying vec3 l_p;

void vertex() {
	w_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	l_p = VERTEX;
}

void fragment() {
	float t = UV.x;
	float ang = atan(l_p.z, l_p.x);
	float bands = pl_noise(vec3(t * band_freq, seed, 0.5)) * 0.6 + pl_noise(vec3(t * band_freq * 3.1, seed + 3.0, 1.5)) * 0.4;
	float gap = smoothstep(0.25, 0.55, pl_noise(vec3(t * band_freq * 0.35, seed + 7.0, 2.5)));
	float dens = mix(1.0, gap, gaps) * (0.55 + 0.45 * bands);
	float cl = pl_fbm(vec3(cos(ang) * 4.0, sin(ang) * 4.0, t * 6.0 + seed), 4);
	dens *= mix(1.0, smoothstep(0.25, 0.75, cl) * 1.4, clumps);
	dens *= smoothstep(0.0, inner_fade, t) * (1.0 - smoothstep(1.0 - outer_fade, 1.0, t));
	vec3 center = NODE_POSITION_WORLD;
	vec3 v = normalize(CAMERA_POSITION_WORLD - w_p);
	vec3 la = normalize(sun_a_dir);
	vec3 lb = normalize(sun_b_dir);
	float sa = pl_planet_shadow(w_p, center, planet_r_world, la);
	float sb = pl_planet_shadow(w_p, center, planet_r_world, lb);
	float fa = 0.55 + scatter * pow(clamp(dot(-v, la), 0.0, 1.0), 5.0);
	float fb = 0.55 + scatter * pow(clamp(dot(-v, lb), 0.0, 1.0), 5.0);
	vec3 light = sun_a_col * sa * fa + sun_b_col * sb * fb + vec3(0.02);
	vec3 col = mix(col_b, col_a, bands) * light;
	col += ember * (0.6 + 0.4 * bands) * smoothstep(0.3, 0.8, cl);
	ALBEDO = col;
	ALPHA = clamp(dens * opacity, 0.0, 1.0);
}
