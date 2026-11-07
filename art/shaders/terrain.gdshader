shader_type spatial;
// [biomes2] Frontier terrain beyond the play field (planet/frontier_view.gd builds the heightfield):
// dunes, snowfields, headlands, lawns. World-space planar texturing at two scales (no visible
// tiling at distance), a second material on slopes and/or in hollows, wind ripples on sand,
// frost glints on snow, and grass creeping into the hollows as the district is restored.
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D tex_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm_a : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_b : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm_b : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_g : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint_a = vec3(1.0);
uniform vec3 tint_b = vec3(1.0);
uniform vec3 tint_g = vec3(0.6, 0.75, 0.45);
uniform float scale_a = 0.2;       // texture repeats per metre
uniform float scale_b = 0.15;
uniform float rough_a = 0.9;
uniform float rough_b = 0.85;
// Second material: on slopes (slope_lo..slope_hi of 1 - normal.y) and/or below height low_y.
uniform float slope_lo = 2.0;
uniform float slope_hi = 3.0;
uniform float low_y = -999.0;
uniform float low_soft = 1.5;
uniform float ripple = 0.0;        // wind ripples on sand
uniform vec2 wind = vec2(0.83, 0.56);
uniform float sparkle = 0.0;       // frost glints
uniform float restore = 0.0;       // 0 ruined .. 1 restored
uniform float green_amt = 0.0;     // grass coverage at full restore
uniform float macro = 0.18;        // large-scale brightness variation
// The field ground's biome tint (ground_pbr.gdshader biome_tint) so the two meet without a seam.
uniform vec4 biome_tint = vec4(1.0, 1.0, 1.0, 0.0);

varying vec3 wpos;
varying vec3 wnrm;

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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + 17.3;
		a *= 0.5;
	}
	return v;
}

vec3 two_scale(sampler2D t, vec2 p, float s) {
	vec3 a = texture(t, p * s).rgb;
	vec3 b = texture(t, p * s * 0.21 + vec2(0.37, 0.71)).rgb;
	return mix(a, b, 0.4);
}

vec3 nrm_ws(sampler2D t, vec2 p, float s, vec3 n, float k) {
	vec3 tn = texture(t, p * s).rgb * 2.0 - 1.0;
	return normalize(n * max(tn.z, 0.2) + vec3(1.0, 0.0, 0.0) * tn.x * k + vec3(0.0, 0.0, 1.0) * -tn.y * k);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = wpos.xz;
	vec3 n = normalize(wnrm);
	float slope = 1.0 - clamp(n.y, 0.0, 1.0);
	float n1 = fbm(p * 0.013);
	float n2 = fbm(p * 0.07 + 11.0);
	float mb = smoothstep(slope_lo, slope_hi, slope + (n2 - 0.5) * 0.12);
	mb = max(mb, 1.0 - smoothstep(low_y - low_soft, low_y + low_soft, wpos.y + (n2 - 0.5) * low_soft * 1.5));
	vec3 a = two_scale(tex_a, p, scale_a) * tint_a;
	vec3 b = two_scale(tex_b, p, scale_b) * tint_b;
	// [vqa] Steep faces (mountains, dune lee sides) were textured straight down from above and
	// smeared into vertical streaks: blend in side projections there (triplanar).
	vec3 tw = pow(abs(n), vec3(4.0));
	tw /= (tw.x + tw.y + tw.z);
	if (tw.y < 0.97) {
		vec3 ax_a = two_scale(tex_a, wpos.zy, scale_a) * tint_a;
		vec3 az_a = two_scale(tex_a, wpos.xy, scale_a) * tint_a;
		vec3 ax_b = two_scale(tex_b, wpos.zy, scale_b) * tint_b;
		vec3 az_b = two_scale(tex_b, wpos.xy, scale_b) * tint_b;
		a = a * tw.y + ax_a * tw.x + az_a * tw.z;
		b = b * tw.y + ax_b * tw.x + az_b * tw.z;
	}
	vec3 alb = mix(a, b, mb);
	if (biome_tint.a > 0.001) {
		float lum = dot(alb, vec3(0.3, 0.55, 0.15));
		alb = mix(alb, lum * biome_tint.rgb * 1.9, biome_tint.a);
	}
	float dist = length(CAMERA_POSITION_WORLD - wpos);
	float nk = 0.6 * (1.0 - smoothstep(60.0, 260.0, dist));
	vec3 wn = mix(nrm_ws(nrm_a, p, scale_a, n, nk), nrm_ws(nrm_b, p, scale_b, n, nk), mb);
	float rough = mix(rough_a, rough_b, mb);
	if (ripple > 0.001) {
		// Long wavy ripple crests across the wind; they fade where the slope is steep (avalanche
		// faces) and with distance (they would alias).
		float ph = dot(p, wind) * 2.1 + fbm(p * 0.09) * 9.0;
		float rk = ripple * (1.0 - smoothstep(0.25, 0.45, slope)) * (1.0 - smoothstep(40.0, 180.0, dist)) * (1.0 - mb);
		wn = normalize(wn + vec3(wind.x, 0.0, wind.y) * cos(ph) * 0.22 * rk);
		alb *= 1.0 + sin(ph) * 0.05 * rk;
	}
	// Restored: grass in the hollows and on gentle ground first.
	if (green_amt > 0.001 && restore > 0.001) {
		float gm = smoothstep(0.55, 0.35, n2 + slope * 0.8 - restore * 0.45) * restore * green_amt;
		vec3 g = two_scale(tex_g, p, 0.25) * tint_g;
		alb = mix(alb, g, gm);
		rough = mix(rough, 0.85, gm);
	}
	alb *= mix(1.0 - macro, 1.0 + macro * 0.4, n1);
	vec3 em = vec3(0.0);
	if (sparkle > 0.001) {
		vec2 cell = floor(p * 9.0);
		float s = h21(cell + floor(CAMERA_POSITION_WORLD.xz * 0.6));
		em = vec3(0.9, 0.95, 1.0) * step(0.997, s) * sparkle * (1.0 - smoothstep(10.0, 45.0, dist)) * (1.0 - mb);
	}
	ALBEDO = alb;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ROUGHNESS = rough;
	SPECULAR = 0.4;
	EMISSION = em;
}
