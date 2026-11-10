shader_type spatial;
// [planet-anvil] Rust and soot over Anvil's junk (FieldView.set_junk_overlay): red iron-oxide dust
// on up-facing surfaces, a sooty film streaked down the sides.
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 dust : source_color = vec4(0.6, 0.27, 0.14, 1.0);
uniform vec4 soot : source_color = vec4(0.06, 0.05, 0.045, 1.0);
uniform float top_amt = 0.75;
uniform float film = 0.3;

varying vec3 wn;
varying vec3 wp;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float up = smoothstep(0.25, 0.85, wn.y);
	float n = vnoise(wp.xz * 5.0) * 0.6 + vnoise(wp.xz * 19.0) * 0.4;
	float streak = vnoise(vec2((wp.x + wp.z) * 9.0, wp.y * 1.5));
	float top = up * top_amt * smoothstep(0.25, 0.65, n);
	float sides = film * (1.0 - up) * (0.5 + 0.5 * streak);
	ALBEDO = mix(soot.rgb, dust.rgb * (0.85 + 0.3 * n), step(sides, top));
	ALPHA = clamp(max(top, sides), 0.0, 0.92);
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
