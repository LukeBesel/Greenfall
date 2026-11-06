shader_type spatial;
// Thin glowing rim around the cinematic planet; only the sunlit side glows.
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;
uniform vec3 sun_dir = vec3(1.0, 0.3, 0.0);
uniform vec4 tint : source_color = vec4(0.75, 0.75, 0.85, 1.0);
uniform float strength = 1.2;
varying vec3 wn;

void vertex() {
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 7.0);
	float lit = smoothstep(-0.25, 0.4, dot(normalize(wn), normalize(sun_dir)));
	ALBEDO = tint.rgb * rim * lit * strength;
}
