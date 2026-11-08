shader_type spatial;
// [v2feel] Owner item 38: the crashed pod's smoke as a very tall plume, the landmark for home seen
// from far across the globe. One open cylinder (no particles): soft edges from the view angle,
// slow rising noise, a lean with the wind higher up, a faint glow so it still reads at night.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float height = 320.0;
uniform vec4 base_color : source_color = vec4(0.62, 0.6, 0.58, 1.0);
uniform vec4 top_color : source_color = vec4(0.85, 0.84, 0.82, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.55, 0.3, 1.0);
uniform float opacity = 0.55;
uniform float lean = 38.0;          // metres of drift at the top
uniform float near_fade = 6.0;      // fades out close to the camera (no wall of smoke on the pad)

varying float h;
varying float edge;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	h = clamp(VERTEX.y / height + 0.5, 0.0, 1.0);
	float w = sin(TIME * 0.11 + h * 3.0) * 0.15;
	VERTEX.x += (h * h) * lean * (1.0 + w);
	VERTEX.z += (h * h) * lean * 0.35 + sin(TIME * 0.07 + h * 5.0) * h * 4.0;
	vec3 n = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 vpos = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	edge = abs(dot(n, normalize(-vpos)));
}

void fragment() {
	float t = TIME * 0.035;
	vec2 uv = vec2(UV.x * 6.0, h * 14.0 - t * 14.0);
	float n = noise(uv) * 0.6 + noise(uv * 2.3 + 7.0) * 0.3 + noise(uv * 5.1 + 3.0) * 0.1;
	float body = smoothstep(0.08, 0.6, edge) * (0.55 + 0.6 * n);
	float rise = smoothstep(0.0, 0.03, h) * (1.0 - smoothstep(0.55, 1.0, h));
	float dist = length(VERTEX);
	float a = body * rise * opacity * smoothstep(near_fade, near_fade * 3.0, dist);
	vec3 col = mix(base_color.rgb, top_color.rgb, h) * (0.85 + 0.3 * n);
	col += glow_color.rgb * 0.35 * (1.0 - smoothstep(0.0, 0.12, h));
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
}
