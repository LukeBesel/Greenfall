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

varying vec3 wpos;
const float SQRT3 = 1.7320508;

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
	vec2 qr = vec2((SQRT3 / 3.0 * p.x - p.y / 3.0) / hex_size, (2.0 / 3.0 * p.y) / hex_size);
	vec2 ax = hex_round(qr);
	float hd = (abs(ax.x) + abs(ax.y) + abs(ax.x + ax.y)) * 0.5;
	if (hd > float(grid_radius)) { discard; }
	float size = float(grid_radius * 2 + 1);
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
	vec3 murky = vec3(0.16, 0.17, 0.14) + vec3(0.06, 0.0, 0.08) * sin(p.x * 0.3 + p.y * 0.2 + TIME * 0.2);
	vec3 clear = vec3(0.08, 0.42, 0.46);
	ALBEDO = mix(murky, clear, clarity);
	ALPHA = mix(0.94, 0.42, clarity);
	ROUGHNESS = mix(0.18, 0.04, clarity);
	METALLIC = 0.0;
	SPECULAR = 0.7;
	NORMAL_MAP = n;
	NORMAL_MAP_DEPTH = mix(0.4, 0.8, clarity);
	// Oily rainbow sheen on dirty water.
	float sheen = (1.0 - clarity) * smoothstep(0.6, 0.9, sin(p.x * 0.7 + p.y * 0.9 + TIME * 0.3) * 0.5 + 0.5);
	EMISSION = vec3(0.12, 0.06, 0.16) * sheen * 0.3;
}
