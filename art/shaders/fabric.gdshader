shader_type spatial;
// Hanging cloth: bunting pennants and laundry. Instance colour (sRGB) is the dye; the cloth
// sways in a breeze from TIME (no script), more the further a vertex hangs below its line
// (model-space -Y). Light shines through thin fabric (backlight) and the hem collects grime.
render_mode cull_disabled, depth_draw_opaque;
// [orbD] Site frame on a walkable globe (identity on the flat game): "world" maths run in the
// nearest hub site's local metres, y up on its pad (planet/sites/site_manager.gd).
global uniform mat4 site_inv;

uniform float sway = 0.09;
uniform float grime = 0.35;

varying vec3 v_obj;
varying vec3 v_world;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	v_obj = VERTEX;
	vec3 origin = (site_inv * MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float ph = origin.x * 0.37 + origin.z * 0.29;
	float hang = max(-VERTEX.y, 0.0);
	float gust = 0.6 + 0.4 * sin(TIME * 0.35 + ph * 0.2);
	VERTEX.z += sin(TIME * 2.1 + ph + VERTEX.x * 3.0) * sway * hang * gust;
	VERTEX.x += sin(TIME * 1.3 + ph * 1.7) * sway * 0.35 * hang * gust;
	v_world = origin;
}

void fragment() {
	vec3 dye = pow(COLOR.rgb, vec3(2.2));
	// Weave and blotchy fading.
	float weave = 0.93 + 0.07 * sin(v_obj.x * 420.0) * sin(v_obj.y * 420.0);
	float blot = hash21(floor(v_obj.xy * 9.0) + v_world.xz);
	vec3 faded = mix(dye, vec3(dot(dye, vec3(0.33))), 0.12 + blot * 0.1);
	float hem = smoothstep(-0.25, -0.75, v_obj.y);
	ALBEDO = faded * weave * (1.0 - grime * hem * 0.6);
	ROUGHNESS = 0.92;
	BACKLIGHT = faded * 0.55;
}
