shader_type spatial;
// Painted floor markings on the hub yard (safety lines, hazard border, numbered bays, arrows)
// plus cracks with moss, all baked into one RGBA image by StreetDressing. Here the paint is worn
// down by world-space noise (scuffed paths, chipped edges) so it reads as old and walked on.
render_mode blend_mix, depth_draw_never, cull_back;

uniform sampler2D paint : source_color, filter_linear_mipmap;

varying vec3 v_world;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 c = texture(paint, UV);
	vec2 w = v_world.xz;
	float big = noise(w * 0.45) * 0.6 + noise(w * 1.7) * 0.4;
	float chip = noise(w * 11.0) * 0.6 + noise(w * 37.0) * 0.4;
	float wear = smoothstep(0.45, 0.8, big * 0.55 + chip * 0.45);
	float is_paint = step(0.3, max(c.r, max(c.g, c.b)));
	float a = c.a * (1.0 - wear * 0.85 * is_paint) * (0.75 + 0.25 * chip);
	ALBEDO = c.rgb * (0.82 + 0.18 * chip);
	ALPHA = clamp(a, 0.0, 1.0);
	ROUGHNESS = 0.8;
}
