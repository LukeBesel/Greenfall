shader_type spatial;
// The cinematic planet's air: a soft glow that is brightest right at the planet's edge and thins
// out into space, plus a thin veil over the disc that thickens toward the edge. Only the sunlit
// side glows. Drawn on a shell `shell` times the planet's radius.
// [v9intro] It was a rim glow on the shell's own edge, which left a dark gap between the planet
// and a detached grey ring. Now the glow is measured from the planet's limb.
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;
uniform vec3 sun_dir = vec3(0.72, 0.41, 0.56);
uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.6, 1.0);
uniform float strength = 1.0;
uniform float shell = 1.07;
varying vec3 wn;

void vertex() {
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float c = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	// How close this line of sight passes to the planet's centre, in planet radii.
	float d = sqrt(max(0.0, 1.0 - c * c)) * shell;
	float outside = exp(-max(d - 1.0, 0.0) / (shell - 1.0) * 4.0) * smoothstep(shell, mix(1.0, shell, 0.55), d);
	float veil = pow(clamp(d, 0.0, 1.0), 9.0) * 0.55 + 0.03;
	float g = d > 1.0 ? outside : veil;
	float lit = smoothstep(-0.3, 0.35, dot(normalize(wn), normalize(sun_dir)));
	ALBEDO = tint.rgb * g * lit * strength;
}
