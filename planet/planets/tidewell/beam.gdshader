shader_type spatial;
// [planet-tidewell] A lighthouse's thin light beam: a long narrow cone, brightest at the lamp,
// fading along its length and at its edges. Additive and very faint (owner: thin, subtle glow).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.95, 0.82);
uniform float energy = 0.35;

void fragment() {
	float along = UV.y;               // 0 at the lamp (cylinder top) .. 1 at the far end
	float edge = abs(dot(NORMAL, VIEW));
	float a = pow(edge, 2.0) * exp(-along * 3.0) * smoothstep(0.0, 0.03, along);
	ALBEDO = color * a * energy;
}
