shader_type spatial;
// [fauna2] Glossy animal eyes. The eye mesh's UV is its own front disc (centre 0.5, 0.5): a deep
// iris with a darker rim, a pupil (round or a cat's soft vertical slit), a wet clearcoat and a
// catchlight. eye_closed draws a lid in the coat colour with a dark lash line (sleeping).
render_mode specular_schlick_ggx;

uniform vec3 iris : source_color = vec3(0.65, 0.68, 0.18);
uniform float pupil_w = 0.42;   // 1 = round, smaller = slit
uniform float pupil_r = 0.42;   // pupil size (cute = big)
uniform float eye_closed = 0.0;
uniform vec3 coat_base : source_color = vec3(0.86, 0.52, 0.24);

void fragment() {
	vec2 d = (UV - vec2(0.5)) * 2.0;
	float r = length(d);
	vec3 col = iris * (1.15 - 0.45 * smoothstep(0.35, 0.95, r));
	col = mix(col, iris * 1.35, smoothstep(0.5, 0.0, r) * 0.35);
	col = mix(col, vec3(0.03, 0.025, 0.02), smoothstep(0.8, 0.98, r));
	vec2 pd = vec2(d.x / max(pupil_w, 0.05), d.y);
	float pupil = 1.0 - smoothstep(pupil_r - 0.06, pupil_r + 0.02, length(pd));
	col = mix(col, vec3(0.01, 0.008, 0.006), pupil);
	float glint = smoothstep(0.2, 0.1, length(d - vec2(-0.32, 0.38))) + smoothstep(0.1, 0.04, length(d - vec2(0.3, -0.3))) * 0.5;
	float closed = step(0.5, eye_closed);
	col = mix(col, coat_base * 0.8, closed);
	float lash = closed * (1.0 - smoothstep(0.03, 0.08, abs(d.y + 0.05)));
	col = mix(col, vec3(0.05, 0.04, 0.03), lash);
	ALBEDO = col;
	ROUGHNESS = mix(0.04, 0.8, closed);
	SPECULAR = mix(0.9, 0.2, closed);
	CLEARCOAT = 1.0 - closed;
	CLEARCOAT_ROUGHNESS = 0.05;
	EMISSION = vec3(1.0) * glint * 1.6 * (1.0 - closed);
}
