shader_type spatial;
// [planet-ochre] Thin water spilling from a terrace channel down the wall below (futuristic
// stage): streaks scroll down UV.y, foam at the foot.
render_mode cull_disabled, depth_draw_never, shadows_disabled;

uniform float time_s = 0.0;
uniform vec3 water = vec3(0.6, 0.85, 0.85);

float h21(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y); }

void fragment() {
	float edge = smoothstep(0.0, 0.25, UV.x) * smoothstep(1.0, 0.75, UV.x);
	float streak = vn(vec2(UV.x * 14.0, UV.y * 3.0 - time_s * 2.4));
	float foam = smoothstep(0.8, 1.0, UV.y);
	ALBEDO = mix(water, vec3(0.95), 0.4 * streak + foam * 0.6);
	ROUGHNESS = 0.1;
	SPECULAR = 0.6;
	ALPHA = edge * (0.25 + 0.45 * streak + foam * 0.3);
}
