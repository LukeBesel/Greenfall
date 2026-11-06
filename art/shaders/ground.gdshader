shader_type spatial;
// Restoration ground. Reads a per-hex state texture: R = removed fraction, G = flip time,
// B = clean flag. Dirty ground is rusty/violet-stained/cracked; clean ground is warm earth with a
// ripple of color spreading out from the hex center when it flips, plus sparkles and an outline glow.
#include "res://art/shaders/toon_lib.gdshaderinc"

uniform sampler2D state_tex : filter_nearest;
uniform int grid_radius = 9;
uniform float hex_size = 3.2;
uniform float time_now = 0.0;
uniform vec2 focus_axial = vec2(9999.0);
uniform vec4 dirty_a : source_color = vec4(0.62, 0.38, 0.27, 1.0);
uniform vec4 dirty_b : source_color = vec4(0.5, 0.33, 0.52, 1.0);
uniform vec4 crack_col : source_color = vec4(0.44, 0.41, 0.45, 1.0);
uniform vec4 clean_a : source_color = vec4(0.86, 0.68, 0.45, 1.0);
uniform vec4 clean_b : source_color = vec4(0.94, 0.8, 0.56, 1.0);
uniform vec4 hub_col : source_color = vec4(0.72, 0.7, 0.66, 1.0);
uniform float ripple_speed = 7.0;

varying vec3 wpos;

const float SQRT3 = 1.7320508;

vec2 hex_round(vec2 qr) {
	vec3 c = vec3(qr.x, qr.y, -qr.x - qr.y);
	vec3 r = round(c);
	vec3 d = abs(r - c);
	if (d.x > d.y && d.x > d.z) {
		r.x = -r.y - r.z;
	} else if (d.y > d.z) {
		r.y = -r.x - r.z;
	}
	return r.xy;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 qr = vec2((SQRT3 / 3.0 * p.x - p.y / 3.0) / hex_size, (2.0 / 3.0 * p.y) / hex_size);
	vec2 ax = hex_round(qr);
	vec2 center = vec2(hex_size * (SQRT3 * ax.x + SQRT3 * 0.5 * ax.y), hex_size * 1.5 * ax.y);
	vec2 local = p - center;
	// Distance to the hex edge (pointy-top: edge normals at 0, 60, 120 degrees).
	float apothem = hex_size * SQRT3 * 0.5;
	float m = max(abs(local.x), max(abs(dot(local, vec2(0.5, SQRT3 * 0.5))), abs(dot(local, vec2(0.5, -SQRT3 * 0.5)))));
	float edge_d = apothem - m;
	float hex_dist = (abs(ax.x) + abs(ax.y) + abs(ax.x + ax.y)) * 0.5;
	bool inside = hex_dist <= float(grid_radius);

	float n = gf_fbm(wpos * 0.45);
	float n2 = gf_fbm(wpos * 1.7 + vec3(7.0));
	// Dirty palette: rusty earth, violet stains, gray cracks.
	vec3 dirty = mix(dirty_a.rgb, dirty_b.rgb, smoothstep(0.48, 0.66, n));
	float crack = smoothstep(0.035, 0.0, abs(gf_noise(wpos * 1.3) - 0.5)) * step(0.45, n2);
	dirty = mix(dirty, crack_col.rgb, crack * 0.7);
	// Clean palette: warm earth with pebbles.
	vec3 cleanc = mix(clean_a.rgb, clean_b.rgb, smoothstep(0.35, 0.7, n));
	cleanc = mix(cleanc, cleanc * 0.8, step(0.82, gf_noise(wpos * 6.0)));

	vec3 col = dirty;
	vec3 glow = vec3(0.0);
	float outline = smoothstep(0.12, 0.0, edge_d);
	if (inside) {
		float size = float(grid_radius * 2 + 1);
		vec2 uv = (ax + vec2(float(grid_radius)) + 0.5) / size;
		vec4 st = texture(state_tex, uv);
		float removed = st.r;
		float flip_t = st.g;
		float is_clean = st.b;
		float is_hub = st.a;
		vec3 partial = mix(dirty, mix(dirty, cleanc, 0.3), removed);
		col = partial;
		if (is_clean > 0.5) {
			float age = time_now - flip_t;
			float front = age * ripple_speed;
			float d = length(local);
			float reveal = clamp((front - d) / 1.2, 0.0, 1.0);
			col = mix(partial, cleanc, reveal);
			// Bright leading edge of the ripple.
			float wave = smoothstep(1.0, 0.0, abs(front - d)) * smoothstep(3.0, 1.5, age);
			glow += vec3(1.0, 0.95, 0.6) * wave * 0.6;
			// Sparkle for a few seconds after flipping.
			vec3 cell = floor(wpos * 2.5);
			float h = gf_hash(cell);
			float tw = step(0.93, h) * smoothstep(4.0, 0.5, age) * (0.5 + 0.5 * sin(TIME * 14.0 + h * 40.0));
			glow += vec3(1.0, 0.9, 0.7) * tw * reveal;
			// Outline flash.
			glow += vec3(1.0, 0.85, 0.4) * outline * smoothstep(2.0, 0.2, age) * 1.2;
		}
		if (is_hub > 0.5) {
			col = mix(hub_col.rgb, hub_col.rgb * 0.88, step(0.5, fract((wpos.x + wpos.z) * 0.5)));
		}
		// Faint grid lines so hexes read as units.
		col = mix(col, col * 0.78, outline * 0.6);
		if (distance(ax, focus_axial) < 0.5) {
			glow += vec3(0.6, 1.0, 0.8) * outline * (0.45 + 0.15 * sin(TIME * 4.0));
		}
	} else {
		col = mix(dirty, dirty * 0.85, 0.5);
	}
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
	EMISSION = glow;
}
