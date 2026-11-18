shader_type spatial;
// [biomes2] Frontier weathering over the junk pieces (FieldView.set_junk_overlay, as a material
// overlay): sand, frost or silt settles on up-facing surfaces and a thin film mutes the rest, so
// bright plastics read as old, weathered things lying in that land rather than fresh confetti.
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;
// [orbD] Site frame on a walkable globe (identity on the flat game): "world" maths run in the
// nearest hub site's local metres, y up on its pad (planet/sites/site_manager.gd).
global uniform mat4 site_inv;

uniform vec4 coat : source_color = vec4(0.86, 0.72, 0.52, 1.0);
uniform float top_amt = 0.8;    // cover on faces pointing up
uniform float film = 0.25;      // thin film everywhere
uniform float roughness = 0.95;
uniform float metal = 0.0;      // [worlds2] Rich Salvage: a clean metallic glint
uniform float spec = 0.3;

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
	wn = normalize((site_inv * MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wp = (site_inv * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float up = smoothstep(0.2, 0.8, normalize(wn).y);
	float n = vnoise(wp.xz * 6.0 + wp.y * 3.0) * 0.6 + vnoise(wp.xz * 19.0) * 0.4;
	float a = film + up * top_amt * smoothstep(0.25, 0.6, n);
	ALBEDO = coat.rgb * (0.9 + 0.2 * n);
	ALPHA = clamp(a, 0.0, 0.95);
	ROUGHNESS = roughness;
	METALLIC = metal;
	SPECULAR = spec;
}
