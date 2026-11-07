shader_type spatial;
// [globes] Atmosphere rim for the planet globes, drawn on a slightly larger shell. Analytic: the
// view ray's closest approach to the planet centre gives the height above the limb, so the glow is
// thickest right at the edge of the disc and fades out into space; only the sunlit limb glows
// (each sun with its own colour), with a forward-scatter brightening when a sun is behind the
// planet. Thin and soft by design.
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

#include "res://art/shaders/planet_lib.gdshaderinc"

uniform vec3 col_ruin = vec3(0.6, 0.45, 0.32);
uniform vec3 col_ok = vec3(0.35, 0.6, 1.0);
uniform float strength_ruin = 0.8;
uniform float strength_ok = 1.0;
uniform float thickness = 0.06;  // shell radius = planet radius * (1 + thickness)
uniform float falloff = 0.32;  // of the thickness
varying vec3 w_p;

void vertex() {
	w_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float sun_glow(vec3 nx, vec3 dir, vec3 l) {
	float g = smoothstep(-0.35, 0.35, dot(nx, l));
	float fwd = pow(clamp(dot(dir, l), 0.0, 1.0), 6.0);
	return g + fwd * 0.6;
}

void fragment() {
	vec3 center = MODEL_MATRIX[3].xyz;
	float rr = length(MODEL_MATRIX[0].xyz) / (1.0 + thickness);
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 dir = normalize(w_p - cam);
	float t = dot(center - cam, dir);
	vec3 x = cam + dir * t;
	float d = length(x - center) / rr;
	vec3 nx = (x - center) / max(length(x - center), 1e-5);
	float g;
	if (d > 1.0) {
		g = exp(-(d - 1.0) / (thickness * falloff)) * (1.0 - smoothstep(1.0 + thickness * 0.7, 1.0 + thickness, d));
	} else {
		// over the disc: a thin rim just inside the limb
		g = pow(d, 10.0) * 0.55;
	}
	vec3 la = normalize(sun_a_dir);
	vec3 lb = normalize(sun_b_dir);
	vec3 light = sun_a_col * sun_glow(nx, dir, la) + sun_b_col * sun_glow(nx, dir, lb);
	vec3 col = mix(col_ruin, col_ok, restoration);
	ALBEDO = col * light * g * mix(strength_ruin, strength_ok, restoration);
}
