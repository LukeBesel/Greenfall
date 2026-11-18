shader_type spatial;
// [planet-ochre] Shade sails (canvas, sun-faded) and solar sails (dark photovoltaic membrane with
// a fine cell grid and a thin light seam along the hem). UV: 0..1 across the sail.
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform vec3 cloth = vec3(0.93, 0.9, 0.84);
uniform float solar = 0.0;
uniform float wear = 0.0;
uniform vec3 line_col = vec3(0.78, 0.94, 1.0);
uniform float line_amt = 0.0;
uniform float night = 0.0;

float h21(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }

void fragment() {
	vec2 uv = UV;
	float weave = 0.96 + 0.04 * sin(uv.x * 900.0) * sin(uv.y * 900.0);
	vec3 c = cloth * weave;
	float stain = h21(floor(uv * 7.0)) * wear;
	c *= 1.0 - stain * 0.25;
	vec3 pv = vec3(0.05, 0.07, 0.16);
	vec2 g = abs(fract(uv * vec2(18.0, 10.0)) - 0.5);
	float grid = smoothstep(0.47, 0.49, max(g.x, g.y));
	pv = mix(pv, vec3(0.5, 0.55, 0.62), grid * 0.6);
	ALBEDO = mix(c, pv, solar);
	ROUGHNESS = mix(0.85, 0.18, solar);
	METALLIC = solar * 0.4;
	float hem = 1.0 - smoothstep(0.0, 0.012, min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y)));
	EMISSION = line_col * hem * line_amt * mix(0.5, 1.4, night);
	BACKLIGHT = vec3(0.35, 0.3, 0.22) * (1.0 - solar);
}
