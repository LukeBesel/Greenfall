shader_type canvas_item;
render_mode blend_add, unshaded;
// The screen's edge glow while a Surge runs (art/surge_fx.gd): light added round the frame, never
// a dark vignette. `strength` is the steady glow, `flash` the burst at the release.

uniform float strength = 0.0;
uniform float flash = 0.0;
// 0 with Reduced motion: the rays stand still.
uniform float motion = 1.0;
// Saturated: light added over a sunlit scene turns to white haze unless its colour is strong.
uniform vec4 inner_color : source_color = vec4(0.1, 0.95, 0.4, 1.0);
uniform vec4 outer_color : source_color = vec4(0.05, 0.7, 1.0, 1.0);
uniform vec4 warm_color : source_color = vec4(1.0, 0.65, 0.05, 1.0);

void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d) * 1.4142;
	float edge = smoothstep(0.52, 1.0, r);
	float angle = atan(d.y, d.x);
	float rays = 0.72 + 0.28 * sin(angle * 12.0 + TIME * 4.0 * motion);
	float warm = 0.5 + 0.5 * sin(angle * 3.0 - TIME * 1.5 * motion);
	vec3 col = mix(mix(inner_color.rgb, outer_color.rgb, edge), warm_color.rgb, warm * 0.35);
	float a = edge * strength * rays + flash * (0.03 + 0.5 * edge);
	COLOR = vec4(col, clamp(a, 0.0, 0.7));
}
