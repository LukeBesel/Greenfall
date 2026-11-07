shader_type spatial;
// [biomes] Open water (or sea ice) beyond the hex field: the Sunken City's flood and the Frozen
// Port's harbour. Discards inside the playable hex grid (the field's own water.gdshader covers
// those hexes) and, with half_plane, west of a line (the harbour only lies east of the quay).
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

uniform int grid_radius = 4;
uniform float hex_size = 10.0;
uniform sampler2D wave_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D ice_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 murky : source_color = vec4(0.16, 0.2, 0.17, 0.95);
uniform vec4 clear : source_color = vec4(0.07, 0.3, 0.34, 0.6);
uniform float clarity = 0.0;
uniform float ice = 0.0;          // 1 = frozen sea ice
uniform float half_plane_x = -99999.0;
uniform float fade_far = 420.0;
uniform float mirror = 0.0;      // [biomes2] flatter waves, glossier (sky reflections)
// [biomes2] Natural borders: where the flood meets the field is found at the same warped position
// as water.gdshader (and the junk), so the two surfaces meet seamlessly along a wandering line.
uniform sampler2D warp_tex : filter_linear;
uniform float warp_size = 280.0;
uniform float warp_amp = 0.0;
uniform float wave_scale = 1.0;  // match water.gdshader's ripple size where the two meet

#include "res://art/shaders/water_light.gdshaderinc"

varying vec3 wpos;
const float SQRT3 = 1.7320508;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

vec2 hex_round(vec2 qr) {
	vec3 c = vec3(qr.x, qr.y, -qr.x - qr.y);
	vec3 r = round(c);
	vec3 d = abs(r - c);
	if (d.x > d.y && d.x > d.z) { r.x = -r.y - r.z; } else if (d.y > d.z) { r.y = -r.x - r.z; }
	return r.xy;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	if (p.x < half_plane_x) { discard; }
	vec2 pw = p + texture(warp_tex, p / warp_size + 0.5).rg * warp_amp;
	vec2 qr = vec2((SQRT3 / 3.0 * pw.x - pw.y / 3.0) / hex_size, (2.0 / 3.0 * pw.y) / hex_size);
	vec2 ax = hex_round(qr);
	float hd = (abs(ax.x) + abs(ax.y) + abs(ax.x + ax.y)) * 0.5;
	if (hd <= float(grid_radius)) { discard; }
	vec2 uv1 = p * 0.05 * wave_scale + vec2(TIME * 0.006, TIME * 0.004) * wave_scale;
	vec2 uv2 = p * 0.075 * wave_scale - vec2(TIME * 0.005, -TIME * 0.003) * wave_scale;
	vec3 n = mix(texture(wave_nrm, uv1).rgb, texture(wave_nrm, uv2).rgb, 0.5);
	vec4 w = mix(murky, clear, clarity);
	vec3 alb = w.rgb + vec3(0.03, 0.0, 0.04) * sin(p.x * 0.05 + p.y * 0.04 + TIME * 0.1) * (1.0 - clarity) * (1.0 - mirror);
	float a = w.a;
	float rough = mix(0.14, 0.05, clarity) * (1.0 - 0.6 * mirror);
	// Sea ice: pale, cracked plates with snow in the seams.
	if (ice > 0.001) {
		float plate = vnoise(p * 0.07) * 0.6 + vnoise(p * 0.21) * 0.4;
		float crack = smoothstep(0.47, 0.5, plate) * (1.0 - smoothstep(0.5, 0.53, plate));
		vec3 icec = mix(vec3(0.62, 0.74, 0.82), vec3(0.86, 0.91, 0.96), smoothstep(0.3, 0.8, plate));
		icec = mix(icec, vec3(0.95, 0.97, 1.0), crack * 0.8);
		alb = mix(alb, icec, ice);
		a = mix(a, 1.0, ice);
		rough = mix(rough, 0.32 - 0.2 * plate, ice);
		n = mix(n, texture(ice_nrm, p * 0.12).rgb, ice);
	}
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	a = mix(a, 1.0, fres * mirror * (1.0 - ice));
	float far = smoothstep(fade_far * 0.7, fade_far, length(p));
	ALBEDO = alb;
	ALPHA = a * (1.0 - far);
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = mix(0.7, 0.45, ice);
	NORMAL_MAP = n;
	NORMAL_MAP_DEPTH = mix(0.5 * (1.0 - 0.6 * mirror), 0.35, ice);
}
