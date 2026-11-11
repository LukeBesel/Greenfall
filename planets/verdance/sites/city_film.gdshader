shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// A flat soft-edged film (CityKit.film): an oil slick on water, a chemical stain on the ground, or
// a smog layer seen from below. Two colours in slow drifting patches, an oil-sheen rainbow over
// them, and a ragged edge that fades to nothing at the quad's rim.

uniform vec4 colour_a : source_color = vec4(0.5, 0.2, 0.6, 0.7);
uniform vec4 colour_b : source_color = vec4(0.2, 0.7, 0.6, 0.5);
uniform float rainbow = 0.0;
uniform float patch_scale = 0.12;
uniform float drift = 0.02;
uniform float strength = 1.0;
uniform bool under_only = false;

varying vec2 lp;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.1 + 3.7) * 0.3 + vnoise(p * 4.3 + 9.1) * 0.15;
}

void vertex() {
	lp = VERTEX.xz;
}

void fragment() {
	if (under_only && FRONT_FACING) {
		discard;
	}
	vec2 p = lp * patch_scale + TIME * drift * vec2(0.6, 0.35);
	float n = fbm(p);
	float r = length(UV * 2.0 - 1.0);
	float a = smoothstep(1.0, 0.5, r + (n - 0.5) * 0.7);
	vec3 col = mix(colour_a.rgb, colour_b.rgb, smoothstep(0.35, 0.65, n));
	vec3 sheen = 0.5 + 0.5 * cos(6.2831 * (n * 2.6 + fbm(p * 2.3 + 7.0) + vec3(0.0, 0.33, 0.67)));
	col = mix(col, sheen, rainbow * smoothstep(0.3, 0.7, fbm(p * 1.7 + 13.0)));
	ALBEDO = col;
	ALPHA = a * mix(colour_a.a, colour_b.a, smoothstep(0.35, 0.65, n)) * strength;
}
