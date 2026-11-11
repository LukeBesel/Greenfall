shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_front, shadows_disabled, fog_disabled;
// Coloured air over one district (CityKit.haze): a box round the town whose inside is filled with
// a haze that thickens with the distance looked through it and thins with height, so the street
// ahead fades into colour while the sky overhead stays blue. Drawn on the box's far faces over
// what is behind them; the scene's depth gives the length of each sight line inside the haze.
// The model's own space: y up from the box's middle, the haze a cylinder of `radius` round y.

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec4 colour_near : source_color = vec4(0.98, 0.4, 0.7, 1.0);
uniform vec4 colour_far : source_color = vec4(1.0, 0.56, 0.42, 1.0);
uniform float density = 0.012;      // per metre at street level
uniform float strength = 1.0;       // 0 clears it
uniform float radius = 220.0;
uniform float ground_y = 0.0;       // the street's height in the model's space
uniform float scale_height = 30.0;  // the haze is 1/e as thick this far up
uniform float max_alpha = 0.68;     // never a wall: what is behind always shows through

varying mat4 to_model;

void vertex() {
	to_model = inverse(MODELVIEW_MATRIX);
}

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).x;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
	vec4 mid = INV_PROJECTION_MATRIX * vec4(ndc.xy, 0.0, 1.0);
	bool sky = depth >= 0.999999;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	vec4 mid = INV_PROJECTION_MATRIX * vec4(ndc.xy, 0.5, 1.0);
	bool sky = depth <= 0.0000001;
#endif
	vec3 ray_view = normalize(mid.xyz / mid.w);
	float reach = 100000.0;
	if (!sky) {
		vec4 hit = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		reach = (hit.z / hit.w) / ray_view.z;
	}
	vec3 cam = (to_model * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 dir = normalize((to_model * vec4(ray_view, 0.0)).xyz);
	// The part of the sight line inside the cylinder.
	float t0 = 0.0;
	float t1 = reach;
	float a = dot(dir.xz, dir.xz);
	float c = dot(cam.xz, cam.xz) - radius * radius;
	if (a > 0.000001) {
		float b = dot(cam.xz, dir.xz);
		float disc = b * b - a * c;
		if (disc <= 0.0) {
			discard;
		}
		float s = sqrt(disc);
		t0 = max(t0, (-b - s) / a);
		t1 = min(t1, (-b + s) / a);
	} else if (c > 0.0) {
		discard;
	}
	if (t1 <= t0) {
		discard;
	}
	// Haze that thins with height, summed along the line.
	float y0 = max(cam.y + dir.y * t0 - ground_y, -10.0) / scale_height;
	float y1 = max(cam.y + dir.y * t1 - ground_y, -10.0) / scale_height;
	float dy = y1 - y0;
	float mean = abs(dy) > 0.001 ? (exp(-y0) - exp(-y1)) / dy : exp(-y0);
	float fog = 1.0 - exp(-density * strength * (t1 - t0) * mean);
	ALBEDO = mix(colour_near.rgb, colour_far.rgb, smoothstep(0.25, 0.95, fog));
	ALPHA = min(fog, max_alpha);
}
