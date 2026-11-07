shader_type spatial;
// [planet-tidewell] The companion star's disc in the sky: a hard bright core with a soft, thin
// halo (owner: subtle glow). Drawn on a far camera-facing quad, no fog, no depth write.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.62, 0.38);
uniform float energy = 2.0;

void fragment() {
	float r = length(UV - 0.5) * 2.0 * 6.0;  // 1.0 = disc edge (quad holds 6 radii)
	float disc = 1.0 - smoothstep(0.92, 1.0, r);
	float halo = exp(-max(r - 1.0, 0.0) * 1.6) * 0.22 + exp(-max(r - 1.0, 0.0) * 0.45) * 0.05;
	vec3 c = mix(color, vec3(1.0, 0.92, 0.82), 0.45) * disc * 3.0 + color * halo;
	ALBEDO = c * energy;
	ALPHA = 1.0;
}
