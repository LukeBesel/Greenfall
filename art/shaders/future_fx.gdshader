shader_type spatial;
// Future layer one-shots and sky: the level-up light sweep (a hex curtain whose band rises and
// fades, mode 0) and the night aurora curtains (mode 1). Additive, unshaded.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform int mode = 0;
uniform float progress = 0.0;      // sweep: 0..1 over its life
uniform float strength = 1.0;      // aurora: night * district score
uniform vec4 tint : source_color = vec4(0.3, 1.0, 0.95, 1.0);
uniform vec4 tint2 : source_color = vec4(1.0, 0.3, 0.9, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 uv = UV;
	if (mode == 0) {
		float y = 1.0 - uv.y;
		float band = smoothstep(0.25, 0.0, abs(y - progress * 1.2 + 0.1));
		float base = smoothstep(0.35, 0.0, y) * (1.0 - progress);
		float fade = 1.0 - smoothstep(0.65, 1.0, progress);
		float lines = 0.75 + 0.25 * step(0.5, fract(y * 18.0 - TIME * 3.0));
		ALBEDO = mix(tint.rgb, vec3(1.0), band * 0.5) * (band * 2.4 + base * 1.2) * fade * lines;
	} else {
		float y = 1.0 - uv.y;
		float x = uv.x * 18.0;
		float n = noise(vec2(x + TIME * 0.03, TIME * 0.02)) * 0.6 + noise(vec2(x * 2.7 - TIME * 0.05, 3.0)) * 0.4;
		float folds = 0.55 + 0.45 * sin(x * 3.0 + n * 6.0 + TIME * 0.1);
		float rays = 0.6 + 0.4 * noise(vec2(uv.x * 260.0, TIME * 0.2));
		float body = smoothstep(0.0, 0.25, y) * smoothstep(1.0, 0.45, y);
		float curtain = smoothstep(0.35, 0.8, n) * folds * rays * body;
		vec3 c = mix(tint.rgb, tint2.rgb, smoothstep(0.35, 0.95, y + n * 0.2));
		ALBEDO = c * curtain * strength * 0.9;
	}
}
