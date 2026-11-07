shader_type spatial;
// Lake surface over water hexes. Murky purple-green with oily sheen when dirty; clear teal you can
// see the lakebed through when clean. Reads the same per-hex state texture as the ground.
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D state_tex : filter_nearest;
uniform sampler2D wave_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform int grid_radius = 3;
uniform float hex_size = 10.0;
uniform float time_now = 0.0;
uniform float clarity_bonus = 0.0;  // research (silt filters, irrigation)
// [biomes2] Look overrides (the Sunken City's deep flood): dirty / clear colours, opacity and
// roughness, and a mirror amount that flattens the waves so the sky reflects.
uniform vec3 murky_col = vec3(0.16, 0.17, 0.14);
uniform vec3 clear_col = vec3(0.08, 0.42, 0.46);
uniform vec2 alpha_mc = vec2(0.94, 0.42);
uniform vec2 rough_mc = vec2(0.18, 0.04);
uniform float mirror = 0.0;
uniform float sheen_amt = 1.0;
// [biomes2] Natural borders (frontiers set warp_amp > 0): the lake / flood edge is found at the
// same noise-warped position as the junk and the ground (HexField.border_warp_image), so the
// shoreline wanders instead of following hex edges. frozen: the Frozen Port's harbour sea ice.
uniform sampler2D warp_tex : filter_linear;
uniform float warp_size = 280.0;
uniform float warp_amp = 0.0;
uniform float frozen = 0.0;
uniform sampler2D ice_nrm : hint_normal, filter_linear_mipmap, repeat_enable;

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
	float size = float(grid_radius * 2 + 1);
	vec2 qr = vec2((SQRT3 / 3.0 * p.x - p.y / 3.0) / hex_size, (2.0 / 3.0 * p.y) / hex_size);
	vec2 ax = hex_round(qr);
	if (warp_amp > 0.0) {
		// The yard slab stays on its true hex: never flood it.
		if ((abs(ax.x) + abs(ax.y) + abs(ax.x + ax.y)) * 0.5 <= float(grid_radius)
				&& texture(state_tex, (ax + vec2(float(grid_radius)) + 0.5) / size).a > 0.6) { discard; }
		vec2 pw = p + texture(warp_tex, p / warp_size + 0.5).rg * warp_amp;
		qr = vec2((SQRT3 / 3.0 * pw.x - pw.y / 3.0) / hex_size, (2.0 / 3.0 * pw.y) / hex_size);
		ax = hex_round(qr);
	}
	float hd = (abs(ax.x) + abs(ax.y) + abs(ax.x + ax.y)) * 0.5;
	if (hd > float(grid_radius)) { discard; }
	vec4 st = texture(state_tex, (ax + vec2(float(grid_radius)) + 0.5) / size);
	if (st.a < 0.4 || st.a > 0.6) { discard; }
	float clarity = st.b > 0.5 ? 1.0 : st.r * 0.7;
	// Clear-water wave rolling across after the hex flips.
	vec2 center = vec2(hex_size * (SQRT3 * ax.x + SQRT3 * 0.5 * ax.y), hex_size * 1.5 * ax.y);
	float age = time_now - st.g;
	if (st.b > 0.5) {
		clarity = clamp((age * 6.0 - length(p - center)) / 3.0, 0.15, 1.0);
	}
	clarity = clamp(clarity + clarity_bonus * (st.b > 0.5 ? 1.0 : 0.5), 0.0, 1.0);
	vec2 uv1 = p * 0.18 + vec2(TIME * 0.02, TIME * 0.013);
	vec2 uv2 = p * 0.27 - vec2(TIME * 0.017, -TIME * 0.011);
	vec3 n = mix(texture(wave_nrm, uv1).rgb, texture(wave_nrm, uv2).rgb, 0.5);
	vec3 murky = murky_col + vec3(0.06, 0.0, 0.08) * sin(p.x * 0.3 + p.y * 0.2 + TIME * 0.2) * sheen_amt;
	vec3 clear = clear_col;
	vec3 alb = mix(murky, clear, clarity);
	float alpha = mix(alpha_mc.x, alpha_mc.y, clarity);
	// Water is see-through looking down and a mirror at grazing angles.
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	alpha = mix(alpha, 1.0, fres * mirror);
	float rough = mix(rough_mc.x, rough_mc.y, clarity);
	float ndepth = mix(0.4, 0.8, clarity) * (1.0 - 0.65 * mirror);
	if (mirror > 0.001) {
		// The deep flood: one calm look shared with flood.gdshader so the two surfaces meet unseen.
		n = mix(texture(wave_nrm, p * 0.18 + vec2(TIME * 0.0216, TIME * 0.0144)).rgb, texture(wave_nrm, p * 0.27 - vec2(TIME * 0.018, -TIME * 0.0108)).rgb, 0.5);
		ndepth = 0.5 * (1.0 - 0.6 * mirror);
	}
	if (frozen > 0.001) {
		// Harbour sea ice: pale plates with snow in the pressure ridges (matches flood.gdshader).
		float plate = vnoise(p * 0.07) * 0.6 + vnoise(p * 0.21) * 0.4;
		float crack = smoothstep(0.47, 0.5, plate) * (1.0 - smoothstep(0.5, 0.53, plate));
		vec3 icec = mix(vec3(0.62, 0.74, 0.82), vec3(0.86, 0.91, 0.96), smoothstep(0.3, 0.8, plate));
		icec = mix(icec, vec3(0.95, 0.97, 1.0), crack * 0.8);
		alb = mix(alb, icec, frozen);
		alpha = mix(alpha, 1.0, frozen);
		rough = mix(rough, 0.32 - 0.2 * plate, frozen);
		n = mix(n, texture(ice_nrm, p * 0.12).rgb, frozen);
		ndepth = mix(ndepth, 0.35, frozen);
	}
	ALBEDO = alb;
	ALPHA = alpha;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = 0.7;
	NORMAL_MAP = n;
	NORMAL_MAP_DEPTH = ndepth;
	// Oily rainbow sheen on dirty water.
	float sheen = (1.0 - clarity) * smoothstep(0.6, 0.9, sin(p.x * 0.7 + p.y * 0.9 + TIME * 0.3) * 0.5 + 0.5);
	EMISSION = vec3(0.12, 0.06, 0.16) * sheen * 0.3 * sheen_amt * (1.0 - frozen);
}
