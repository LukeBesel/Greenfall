shader_type spatial;
// [pod2] Escape pod paint: Seedglider pearl / tangerine satin clear-coat (same palette and finish
// as art/shaders/ship_paint.gdshader on wt/ship), plus re-entry heat: a titanium heat-tint gradient
// (straw -> bronze -> blue-violet) rising from the base in streaks, with soot right at the bottom.
// heat 0 = factory clean, 1 = just landed. Height comes from UV.y (the lathed shell's UV.y is its
// height in metres) unless height_override >= 0. Works in Forward+, Mobile and Compatibility.

uniform vec4 paint_color : source_color = vec4(0.93, 0.93, 0.91, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.3;
uniform float clearcoat_amt : hint_range(0.0, 1.0) = 0.6;
uniform float heat : hint_range(0.0, 1.0) = 0.0;
uniform float heat_top = 1.5;
uniform float height_override = -1.0;
uniform float pearl : hint_range(0.0, 1.0) = 0.4;

float hash(float x) { return fract(sin(x * 127.1) * 43758.5453); }

void fragment() {
	float y = height_override >= 0.0 ? height_override : UV.y;
	float h = clamp(1.0 - y / heat_top, 0.0, 1.0);
	// Vertical streaks: hot air dragged up the hull during re-entry.
	float s = 0.55 + 0.45 * sin(UV.x * 37.0 + sin(UV.x * 11.0) * 2.5);
	s *= 0.75 + 0.25 * hash(floor(UV.x * 18.0));
	float hs = clamp(h * (0.65 + 0.6 * s), 0.0, 1.0);
	vec3 straw = vec3(0.86, 0.74, 0.5);
	vec3 bronze = vec3(0.6, 0.4, 0.26);
	vec3 violet = vec3(0.3, 0.27, 0.42);
	vec3 soot = vec3(0.09, 0.08, 0.075);
	vec3 tint = mix(straw, bronze, smoothstep(0.25, 0.55, hs));
	tint = mix(tint, violet, smoothstep(0.55, 0.8, hs));
	vec3 col = paint_color.rgb;
	// A faint pearlescent shift with the view angle.
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	col = mix(col, col * vec3(0.96, 0.99, 1.05), pearl * fres);
	col = mix(col, tint * mix(vec3(1.0), paint_color.rgb, 0.25), heat * smoothstep(0.08, 0.5, hs));
	col = mix(col, soot, heat * smoothstep(0.78, 1.0, hs));
	ALBEDO = col;
	float burnt = heat * hs;
	ROUGHNESS = clamp(roughness + burnt * 0.35, 0.0, 1.0);
	METALLIC = 0.05 + burnt * 0.35;
	CLEARCOAT = clearcoat_amt * (1.0 - burnt);
	CLEARCOAT_ROUGHNESS = 0.12 + burnt * 0.4;
	RIM = 0.15;
	RIM_TINT = 0.4;
}
