shader_type spatial;
// Nova's little holo screen (PatchModel "holo"): a thin glowing frame with a ring icon, a bar
// chart and text lines, scanlines and a soft flicker. Additive, unshaded, both sides.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 col : source_color = vec4(0.7, 0.4, 1.0, 1.0);
uniform float amt = 1.0;
uniform float t_now = 0.0;

float box(vec2 p, vec2 a, vec2 b) {
	vec2 s = step(a, p) * step(p, b);
	return s.x * s.y;
}

void fragment() {
	vec2 uv = UV;
	vec2 c = uv - 0.5;
	// Frame: rounded rectangle outline plus a faint fill.
	vec2 q = abs(c) - vec2(0.46, 0.44);
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - 0.03;
	float frame = smoothstep(0.012, 0.0, abs(d));
	float fill = step(d, 0.0) * 0.1;
	// Ring icon (left), bars (right), text lines (bottom).
	vec2 rc = (uv - vec2(0.28, 0.4)) * vec2(1.4, 1.0);
	float rl = length(rc);
	float ang = atan(rc.y, rc.x);
	float ring = smoothstep(0.012, 0.0, abs(rl - 0.12)) * step(0.6, fract(ang / 6.2832 * 3.0 + t_now * 0.25) + 0.45);
	float bars = 0.0;
	for (int i = 0; i < 5; i++) {
		float x0 = 0.55 + float(i) * 0.075;
		float h = 0.12 + 0.22 * fract(sin(float(i) * 12.9 + 1.7) * 43758.5) + 0.03 * sin(t_now * 2.0 + float(i));
		bars += box(uv, vec2(x0, 0.6 - h), vec2(x0 + 0.045, 0.6));
	}
	float lines = 0.0;
	for (int i = 0; i < 3; i++) {
		float y = 0.7 + float(i) * 0.075;
		float len = 0.5 + 0.3 * fract(sin(float(i) * 7.3) * 9123.1);
		lines += box(uv, vec2(0.12, y), vec2(0.12 + len * 0.76, y + 0.022)) * 0.6;
	}
	float scan = 0.82 + 0.18 * sin(uv.y * 160.0 - t_now * 6.0);
	float flick = 0.92 + 0.08 * sin(t_now * 37.0) * sin(t_now * 13.0);
	float a = (frame * 0.9 + fill + ring + bars * 0.7 + lines) * scan * flick * amt;
	ALBEDO = col.rgb * 2.2 * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
