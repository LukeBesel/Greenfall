shader_type spatial;
// Conveyor belt surface: worn black rubber with raised chevron cleats that scroll along UV.x.
// `scroll` is the belt's travelled distance in metres (driven from script so speed upgrades
// and stops stay smooth). Mesh: a PlaneMesh whose UV.x runs along the belt.
render_mode diffuse_burley, specular_schlick_ggx;

uniform float scroll = 0.0;
uniform float length_m = 1.0;
uniform float width_m = 0.8;
uniform float pitch = 0.32;
uniform vec4 rubber : source_color = vec4(0.075, 0.075, 0.08, 1.0);
uniform vec4 dust_color : source_color = vec4(0.42, 0.38, 0.33, 1.0);
uniform sampler2D grit : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float n2(vec2 x) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

// Cleat height profile: chevrons pointing along the travel direction.
float cleat(vec2 m) {
	float across = abs(m.y - 0.5 * width_m) / (0.5 * width_m);
	float u = (m.x - scroll + across * pitch * 0.35) / pitch;
	float f = fract(u);
	float bar = smoothstep(0.0, 0.06, f) * (1.0 - smoothstep(0.16, 0.24, f));
	return bar * (1.0 - smoothstep(0.86, 0.95, across));
}

void fragment() {
	vec2 m = vec2(UV.x * length_m, UV.y * width_m);
	float h = cleat(m);
	float e = 0.01;
	float dx = (cleat(m + vec2(e, 0.0)) - cleat(m - vec2(e, 0.0))) / (2.0 * e);
	float dy = (cleat(m + vec2(0.0, e)) - cleat(m - vec2(0.0, e))) / (2.0 * e);
	// Fabric weave and grime travel with the belt.
	vec2 bm = vec2(m.x - scroll, m.y);
	float weave = n2(bm * vec2(60.0, 60.0)) * 0.5 + n2(bm * 9.0) * 0.5;
	float grime = smoothstep(0.35, 0.85, n2(bm * 2.3 + 3.1));
	float edge = smoothstep(0.82, 1.0, abs(UV.y - 0.5) * 2.0);
	vec3 col = rubber.rgb * (0.85 + weave * 0.3);
	col = mix(col, rubber.rgb * 1.9, h * 0.55);
	col = mix(col, dust_color.rgb * 0.55, grime * 0.35 + edge * 0.25);
	ALBEDO = col;
	ROUGHNESS = mix(0.9, 0.62, h) - weave * 0.05;
	METALLIC = 0.0;
	vec3 gn = texture(grit, bm * 1.5).xyz * 2.0 - 1.0;
	vec3 nm = normalize(vec3(-dx * 0.05 + gn.x * 0.25, -dy * 0.05 + gn.y * 0.25, 1.0));
	NORMAL_MAP = nm * 0.5 + 0.5;
}
