shader_type spatial;
// [planet-ochre] Heat shimmer: a ring around the camera that bends the already-rendered scene
// behind it with rising, wobbling noise, strongest at eye level toward the horizon.
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount = 1.0;
uniform float time_s = 0.0;

float h21(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y); }

void fragment() {
	vec3 vd = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float band = 1.0 - smoothstep(0.0, 0.16, abs(vd.y + 0.02));
	vec2 q = SCREEN_UV * vec2(90.0, 40.0) + vec2(0.0, time_s * 3.2);
	vec2 off = vec2(vn(q) - 0.5, vn(q + 31.0) - 0.5) * vec2(0.0016, 0.0024) * amount * band;
	ALBEDO = textureLod(screen_tex, SCREEN_UV + off, 0.0).rgb;
	ALPHA = band * clamp(amount, 0.0, 1.0);
}
