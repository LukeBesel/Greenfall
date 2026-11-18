shader_type spatial;
// Rocket energy plume: a lathed cone (UV.y = 0 at the nozzle, 1 at the tail). Unshaded.
// Alpha-blended (not additive) so it still reads against a bright hazy sky; HDR colour makes the
// core glow. Hot white core -> cyan -> violet edge -> transparent, scrolling noise turbulence, shock diamonds
// near the nozzle, soft silhouette from the view angle. `power` 0..1 scales brightness and length.
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float power : hint_range(0.0, 1.5) = 1.0;
uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 mid_color : source_color = vec4(0.35, 0.9, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.45, 0.35, 1.0, 1.0);
uniform float brightness = 3.0;
uniform float diamonds = 0.0;      // 0 = no shock diamonds (outer shell), 1 = full (core)
uniform float scroll = 7.0;
uniform float opacity = 1.0;
uniform float seed = 0.0;

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

void fragment() {
	float v = UV.y;
	float t = TIME * scroll;
	// Turbulence: two octaves of noise wrapping around the cone (u) and streaming down it (v).
	vec2 q = vec2(UV.x * 10.0 + seed, v * 6.0 - t);
	float n = n2(q) * 0.6 + n2(q * 2.3 + 11.0) * 0.4;
	// Soft silhouette: faces seen edge-on fade out.
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge = pow(facing, 1.6);
	// Length falloff, eaten by noise so the tail breaks up.
	float reach = clamp(power, 0.0, 1.0);
	float tail = smoothstep(reach * 1.02, reach * 0.35, v + (n - 0.5) * 0.35);
	float head = smoothstep(0.0, 0.04, v);
	// Shock diamonds: bright bands near the nozzle.
	float sd = pow(0.5 + 0.5 * cos(v * 48.0 - TIME * 2.0), 6.0) * smoothstep(0.55, 0.05, v) * diamonds;
	float heat = clamp(1.0 - v * 1.6 + sd * 0.8, 0.0, 1.0);
	vec3 col = mix(edge_color.rgb, mid_color.rgb, smoothstep(0.0, 0.55, heat));
	col = mix(col, core_color.rgb, smoothstep(0.55, 1.0, heat));
	float a = edge * tail * head * (0.55 + 0.45 * n + sd) * clamp(power * 1.5, 0.0, 1.0);
	ALBEDO = col * (1.0 + heat * brightness);
	ALPHA = clamp(a * opacity, 0.0, 1.0);
}
