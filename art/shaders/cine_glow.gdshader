shader_type spatial;
// Story cinematics: a soft glowing ball (flashes, meteor heads, heat). Drawn on a sphere mesh:
// bright in the middle, fading to nothing at the silhouette, so it never shows a hard edge.
// Additive, unshaded: the same on Forward+ and Compatibility.
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.7, 0.35, 1.0);
uniform float power = 2.2;
uniform float strength = 1.0;
// 1 = a halo instead: clear in the middle, glowing toward the edge (the pod's heat-shield glow, seen
// from behind, must not white out the pod itself).
uniform float rim = 0.0;

void fragment() {
	float f = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float a = mix(pow(f, power), pow(1.0 - f, power) * smoothstep(0.0, 0.3, f) * 2.2, rim);
	ALBEDO = tint.rgb * a * strength * tint.a;
}
