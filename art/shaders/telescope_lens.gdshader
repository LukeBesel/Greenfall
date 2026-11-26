// [scope] Telescope eyepiece: the remote view seen through optics. A soft vignette, a faint
// chromatic fringe that grows toward the rim and shimmers slowly (air between the worlds),
// a touch of lift in the blacks. Classy, not a fish-eye: the centre stays sharp and true.
shader_type canvas_item;

uniform float vignette : hint_range(0.0, 1.0) = 0.6;
uniform float fringe : hint_range(0.0, 0.01) = 0.0022;
uniform float shimmer : hint_range(0.0, 1.0) = 0.35;
uniform float fade : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tint : source_color = vec3(0.97, 1.0, 1.02);

void fragment() {
	vec2 uv = UV;
	vec2 c = uv - 0.5;
	float r = length(c * vec2(1.0, 0.8)) * 1.6;
	float w = sin(uv.y * 31.0 + TIME * 1.3) * 0.6 + sin(uv.x * 17.0 - TIME * 0.9) * 0.4;
	vec2 off = c * fringe * (0.3 + r * 2.2) * (1.0 + shimmer * 0.35 * w);
	float cr = texture(TEXTURE, uv + off).r;
	float cg = texture(TEXTURE, uv).g;
	float cb = texture(TEXTURE, uv - off).b;
	vec3 col = vec3(cr, cg, cb) * tint;
	col = col * 0.985 + 0.012;
	float v = smoothstep(1.05, 0.5, r);
	col *= mix(1.0 - vignette, 1.0, v);
	col = mix(col, vec3(0.005, 0.007, 0.01), fade);
	COLOR = vec4(col, 1.0);
}
