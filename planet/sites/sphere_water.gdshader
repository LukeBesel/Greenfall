shader_type spatial;
// [orbD] Lake surface on the walkable globe (planet/sites/sphere_water.gd): the flat water's look
// (art/shaders/water.gdshader: murky -> clear with cleaning, scrolling ripples, sheen) per water
// cell. Waves run in the cell's local space; `clarity` (0 murky .. 1 clear) is per instance.
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;

uniform sampler2D wave_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 murky_col = vec3(0.16, 0.17, 0.14);
uniform vec3 clear_col = vec3(0.08, 0.42, 0.46);
uniform vec2 alpha_mc = vec2(0.94, 0.62);
uniform vec2 rough_mc = vec2(0.18, 0.04);
instance uniform float clarity = 0.0;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec2 p = lp.xz;
	vec3 n1 = texture(wave_nrm, p * 0.18 + vec2(TIME * 0.02, TIME * 0.013)).rgb;
	vec3 n2 = texture(wave_nrm, p * 0.27 - vec2(TIME * 0.017, -TIME * 0.011)).rgb;
	NORMAL_MAP = normalize(mix(n1, n2, 0.5) * 2.0 - 1.0) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = mix(0.6, 0.35, clarity);
	float c = clamp(clarity, 0.0, 1.0);
	vec3 col = mix(murky_col, clear_col, c * c);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = col + vec3(0.05, 0.07, 0.08) * fres;
	ROUGHNESS = mix(rough_mc.x, rough_mc.y, c);
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ALPHA = mix(alpha_mc.x, alpha_mc.y, c) + fres * 0.2;
}
