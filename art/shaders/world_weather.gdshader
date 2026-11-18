shader_type spatial;
// [worlds2] A Cradle Mode world's weathering over its city (planet/world_look_view.gd sets it as a
// material overlay on buildings, skyline and landmark): frost or sand settles on ledges and roofs,
// a band climbs from the ground (salt-wet stone by the sea, moss in the marsh, sand banks in the
// desert) and streaks run down under ledges (rust, rain stains). All in world space, broken up by
// noise so nothing reads as a flat tint. `amount` eases off as the district is restored.
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 coat : source_color = vec4(0.93, 0.96, 1.0, 1.0);
uniform float top_amt = 0.8;
uniform float film = 0.1;
uniform vec4 low_col : source_color = vec4(0.3, 0.4, 0.2, 1.0);
uniform float low_amt = 0.0;
uniform float low_h = 2.0;
uniform vec4 streak_col : source_color = vec4(0.45, 0.22, 0.1, 1.0);
uniform float streak_amt = 0.0;
uniform float amount = 1.0;
uniform float roughness = 0.9;
uniform float ground_y = 0.0;

varying vec3 wn;
varying vec3 wp;

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

void vertex() {
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(wn);
	float side = 1.0 - abs(n.y);
	// Wall coordinate along the face (x or z, whichever the wall runs along).
	float along = abs(n.x) > abs(n.z) ? wp.z : wp.x;
	float nz = vnoise(wp.xz * 0.9 + wp.y * 0.35) * 0.6 + vnoise(wp.xz * 3.7 + wp.y * 1.3) * 0.4;
	// Cover on up faces (roofs, ledges, sills).
	float up = smoothstep(0.35, 0.85, n.y) * top_amt * smoothstep(0.2, 0.55, nz);
	// A band rising from the ground, ragged at the top.
	float hy = wp.y - ground_y;
	float lowm = low_amt * side * (1.0 - smoothstep(low_h * (0.55 + 0.6 * nz), low_h * (0.8 + 0.7 * nz), hy));
	// Streaks down the walls: thin vertical runs that fade out downwards from where they start.
	float col_id = floor(along * 1.6);
	float run = h21(vec2(col_id, floor(wp.y / 6.0) + 3.0));
	float start = fract(wp.y / 6.0);
	float streak = streak_amt * side * step(0.55, run) * smoothstep(0.0, 0.35, start) * (0.4 + 0.6 * vnoise(vec2(along * 9.0, wp.y * 0.6)));
	float a = film + up;
	vec3 c = coat.rgb * (0.9 + 0.2 * nz);
	if (lowm > a) { c = mix(c, low_col.rgb * (0.85 + 0.3 * nz), 0.85); a = lowm; }
	c = mix(c, streak_col.rgb, clamp(streak / max(a + streak, 0.001), 0.0, 1.0));
	a = max(a, streak);
	ALBEDO = c;
	ALPHA = clamp(a * amount, 0.0, 0.92);
	ROUGHNESS = roughness;
	SPECULAR = 0.3;
}
