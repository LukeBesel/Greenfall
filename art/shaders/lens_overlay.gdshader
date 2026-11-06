shader_type canvas_item;
// Patch's lens view: vignette, film grain, faint scanlines, slight warm tint and lens dirt.
uniform float strength = 1.0;
uniform float grain = 0.06;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	vec2 c = uv - 0.5;
	c.x *= 1.6;
	float v = smoothstep(0.35, 0.95, length(c));
	float g = (hash(uv * 900.0 + fract(TIME * 13.0)) - 0.5) * grain;
	float scan = sin(uv.y * 700.0) * 0.012;
	float dirt = smoothstep(0.7, 1.0, hash(floor(uv * 40.0))) * 0.03 * smoothstep(0.2, 0.6, length(c));
	vec3 col = vec3(0.02, 0.025, 0.02);
	float a = clamp(v * 0.85 + abs(g) * 0.6 + abs(scan) + dirt, 0.0, 1.0) * strength;
	COLOR = vec4(col + vec3(g + scan), a);
}
