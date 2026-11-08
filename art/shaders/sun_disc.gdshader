shader_type spatial;
// [worlds2] A sun disc with a soft, thin halo on a camera-facing quad far out (planet/binary_sun.gd):
// the binary system's companion star (the primary is the PhysicalSky's own sun disc). Additive and
// unshaded; the halo stays small (the owner's "thin, subtle glow").
render_mode unshaded, fog_disabled, depth_draw_never, cull_disabled, blend_add, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.62, 0.38, 1.0);
uniform float disc_r = 0.12;     // disc radius in quad units (quad spans -1..1)
uniform float energy = 1.0;      // disc brightness
uniform float halo = 0.35;       // halo strength
uniform float fade = 1.0;        // 0 below the horizon

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float core = smoothstep(disc_r, disc_r * 0.82, d);
	float h = exp(-max(d - disc_r, 0.0) * 9.0) * (1.0 - smoothstep(0.7, 1.0, d));
	vec3 c = color.rgb * (core * 2.4 * energy + h * halo);
	ALBEDO = c * fade;
	ALPHA = clamp((core + h * halo) * fade, 0.0, 1.0);
}
