shader_type spatial;
// Overlay for a piece of junk caught in a tractor beam: an emissive fresnel rim, a fast scan
// band climbing the object and a crackle of noise; `heat` drives it to a white-hot core as the
// piece is compressed into light. Applied as material_overlay, so it adds on top of the
// object's own materials.
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec4 glow_color : source_color = vec4(0.35, 0.9, 1.0, 1.0);
uniform float amount = 0.0;
uniform float heat = 0.0;
uniform float seed = 0.0;

varying vec3 wpos;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float ndv = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 2.2);
	float scan = smoothstep(0.82, 1.0, sin(wpos.y * 70.0 - TIME * 22.0 + seed) * 0.5 + 0.5);
	float crackle = step(0.93, hash(floor(wpos * 38.0) + floor(TIME * 24.0 + seed)));
	vec3 c = glow_color.rgb * (fres * 1.4 + scan * 0.4 + crackle * 0.6 + 0.04) * amount;
	c += mix(glow_color.rgb, vec3(1.0), 0.65) * heat * (0.55 + fres * 0.9);
	ALBEDO = c;
	ALPHA = 1.0;
}
