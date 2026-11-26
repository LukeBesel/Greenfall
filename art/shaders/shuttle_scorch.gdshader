shader_type spatial;
// [art5] The scorch the shuttle's lift engines leave on a pad (art/shuttle_fx.gd): two sooty
// blooms under the wing ducts with streaks blown outward, a paler smear between them. A quad
// lying on the pad (UV 0..1 over 7.5 m, the ship's nose toward +V); `amount` fades it out.
render_mode blend_mix, depth_draw_never, cull_back, unshaded, shadows_disabled, world_vertex_coords;

uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform float seed = 0.0;
uniform float size_m = 7.5;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float n2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

float bloom(vec2 p, vec2 c, float r) {
	vec2 d = p - c;
	float ang = atan(d.y, d.x);
	float l = length(d);
	// streaks: the reach changes with the direction
	float reach = r * (0.75 + 0.5 * n2(vec2(ang * 5.0 + seed, 1.0)) + 0.25 * n2(vec2(ang * 17.0, seed)));
	return pow(clamp(1.0 - l / reach, 0.0, 1.0), 1.6);
}

void vertex() {
	// Drawn a hand's width nearer along the eye's own ray: it wins the depth test against the pad
	// it lies on at any distance, and does not shift on screen.
	VERTEX += normalize(CAMERA_POSITION_WORLD - VERTEX) * 0.12;
}

void fragment() {
	vec2 p = (UV - 0.5) * size_m * vec2(1.0, -1.0);      // metres on the pad: x right, y = toward the nose (+Z)
	float s = bloom(p, vec2(1.72, -0.95), 1.9) + bloom(p, vec2(-1.72, -0.95), 1.9);
	s += 0.45 * bloom(p, vec2(0.0, -0.6), 2.6);
	s += 0.5 * bloom(p, vec2(0.0, -3.0), 1.5);          // the main engines' wash behind the tail
	float grain = n2(p * 9.0 + seed) * 0.5 + n2(p * 31.0) * 0.5;
	s = clamp(s * (0.7 + 0.6 * grain), 0.0, 1.0);
	ALBEDO = mix(vec3(0.05, 0.04, 0.035), vec3(0.015), smoothstep(0.3, 0.9, s));
	ALPHA = smoothstep(0.02, 0.75, s) * 0.8 * amount;
}
