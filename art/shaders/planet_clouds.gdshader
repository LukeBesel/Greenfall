shader_type spatial;
// [globes] Cloud layer for the planet globes: domain-warped FBM weather, optional cyclones (the
// sample point is spun around each storm centre by an angle that falls off with distance, which
// winds the noise into spiral arms with a clear eye), lit by both suns with a soft terminator and
// a little relief from the density itself. Ruined -> restored blends colour, cover and opacity
// (Verdance: brown smog -> crisp white weather).
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

#include "res://art/shaders/planet_lib.gdshaderinc"

uniform vec3 col_ruin = vec3(0.6, 0.5, 0.4);
uniform vec3 col_ok = vec3(0.95, 0.96, 0.98);
uniform float cover_ruin = 0.5;
uniform float cover_ok = 0.45;
uniform float opacity_ruin = 0.6;
uniform float opacity_ok = 0.92;
uniform float sharp = 0.14;
uniform float scale = 2.2;
uniform float band = 0.0;  // zonal stretching (east-west streaks)
uniform int storms = 0;
uniform float storm_size = 0.32;
uniform float swirl = 1.0;
uniform float drift = 0.004;  // slow change in the weather itself
varying vec3 o_p;
varying vec3 w_n;
varying vec3 w_p;

void vertex() {
	o_p = VERTEX;
	w_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	w_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 p = normalize(o_p);
	int oct = octaves;
	vec3 sp = p;
	float storm = 0.0;
	float eye = 0.0;
	for (int i = 0; i < 4; i++) {
		if (i >= storms) {
			break;
		}
		vec3 c = normalize(pl_hash3(vec3(float(i) * 7.13 + seed, 3.7, 1.9)) * 2.0 - 1.0);
		c.y *= 0.7;  // storms stay out of the poles
		c = normalize(c);
		float sz = storm_size * (0.6 + 0.6 * pl_hash(vec3(float(i), seed, 9.0)));
		float d = acos(clamp(dot(p, c), -1.0, 1.0));
		float f = exp(-(d * d) / (sz * sz));
		float dir = c.y >= 0.0 ? 1.0 : -1.0;  // spin with the hemisphere
		sp = pl_rotate(sp, c, dir * swirl * 5.0 * f * (0.85 + 0.3 * pl_noise(p * 6.0)));
		storm += f;
		eye = max(eye, 1.0 - smoothstep(sz * 0.05, sz * 0.13, d));
	}
	vec3 q = sp * vec3(scale, scale * (1.0 + band * 2.5), scale) + vec3(seed * 1.7, 0.0, TIME * drift);
	q += pl_warp(q * 1.3, min(oct, 4)) * 1.4;
	float d = pl_fbm(q, oct);
	float wisps = pl_fbm(q * 3.0 + 5.0, max(oct - 3, 2));
	d = d * 0.82 + wisps * 0.18;
	float cover = mix(cover_ruin, cover_ok, restoration);
	float dens = smoothstep(1.0 - cover - sharp, 1.0 - cover + sharp, d + clamp(storm, 0.0, 1.0) * 0.22);
	dens *= 1.0 - eye;
	dens *= 1.0 - smoothstep(0.93, 1.0, abs(p.y)) * 0.5;

	vec3 ng = normalize(w_n);
	vec3 nb = pl_dd_normal(w_p, ng, dens * 0.004);
	vec3 lit = pl_light2(ng, nb, 0.16, 0.85);
	vec3 col = mix(col_ruin, col_ok, restoration);
	col *= 0.78 + 0.22 * smoothstep(0.0, 0.8, dens);  // thin edges a touch darker (less scattering)
	ALBEDO = col * (lit + vec3(0.01, 0.012, 0.016));
	ALPHA = clamp(dens * mix(opacity_ruin, opacity_ok, restoration), 0.0, 1.0);
}
