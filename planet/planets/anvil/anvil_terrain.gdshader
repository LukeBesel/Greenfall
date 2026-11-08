shader_type spatial;
// [planet-anvil] Anvil terrain beyond the field (env.gd builds the heightfield), the core pit's
// benches and the slag heaps. Any texture is recoloured to the planet palette from its luminance:
// iron-oxide dust on the flats, layered sediment strata with dark desert-varnish streaks on mesa
// walls and pit risers. Restoring spreads crusty lichen first, then red-leaf groundcover, then
// green in the hollows; slag = 1 makes it dark glassy foundry slag (which greens over too).
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D tex_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm_a : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_b : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm_b : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_g : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 dust_col = vec3(0.78, 0.4, 0.24);
uniform vec3 rock_col = vec3(0.52, 0.27, 0.17);
uniform vec3 band_col = vec3(0.86, 0.56, 0.38);
uniform vec3 lichen_col = vec3(0.44, 0.54, 0.3);
uniform vec3 redleaf_col = vec3(0.62, 0.12, 0.1);
uniform vec3 green_col = vec3(0.3, 0.52, 0.2);
uniform float scale_a = 0.14;
uniform float scale_b = 0.07;
uniform float restore = 0.0;
uniform float slag = 0.0;
uniform float strata = 1.0;
uniform float ripple = 0.6;
uniform vec3 ember_col = vec3(1.0, 0.32, 0.08);
uniform float ember = 0.0;      // glowing cracks in slag (fades as restored)

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

float lum(vec3 c) {
	return dot(c, vec3(0.3, 0.55, 0.15));
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
	float n1 = fbm(p * 0.011);
	float n2 = fbm(p * 0.06 + 11.0);
	float n3 = fbm(p * 0.23 + 5.0);
	float dist = length(CAMERA_POSITION_WORLD - wpos);
	// Dust: the texture's detail, recoloured.
	float la = lum(two_scale(tex_a, p, scale_a));
	vec3 dust = dust_col * la * 1.9 * mix(0.86, 1.1, n2);
	// Rock: triplanar so cliffs don't smear.
	vec3 tw = pow(abs(n), vec3(4.0));
	tw /= (tw.x + tw.y + tw.z);
	float lb = lum(two_scale(tex_b, p, scale_b)) * tw.y + lum(two_scale(tex_b, wpos.zy, scale_b)) * tw.x + lum(two_scale(tex_b, wpos.xy, scale_b)) * tw.z;
	float by = wpos.y + (fbm(p * 0.018) - 0.5) * 9.0;
	float layer = smoothstep(0.3, 0.75, fbm(vec2(by * 0.21, n1 * 2.0)));
	float fine = sin(by * 2.3 + n3 * 2.0) * 0.5 + 0.5;
	vec3 rock = mix(rock_col, band_col, layer * strata) * lb * 1.9 * mix(0.9, 1.05, fine * strata);
	float varnish = smoothstep(0.55, 0.85, vnoise(vec2((wpos.x + wpos.z) * 0.3, wpos.y * 0.025 + n1)));
	rock *= mix(1.0, 0.68, varnish * strata * slope);
	float mb = smoothstep(0.3, 0.55, slope + (n2 - 0.5) * 0.16);
	vec3 alb = mix(dust, rock, mb);
	float rough = mix(0.95, 0.88, mb);
	float spec = 0.35;
	// Wind-scoured streaks and faint ripples on the flats.
	vec2 ws = vec2(dot(p, vec2(0.83, 0.56)), dot(p, vec2(-0.56, 0.83)));
	float st = fbm(vec2(ws.x * 0.01, ws.y * 0.045) + 5.0);
	alb *= mix(0.88, 1.08, smoothstep(0.3, 0.7, st) * (1.0 - mb));
	float ph = ws.x * 2.0 + fbm(p * 0.09) * 9.0;
	float rk = ripple * (1.0 - mb) * (1.0 - smoothstep(30.0, 140.0, dist));
	alb *= 1.0 + sin(ph) * 0.04 * rk;
	if (slag > 0.001) {
		vec3 sl = vec3(0.07, 0.055, 0.05) * (0.7 + 0.7 * n3) + rock_col * 0.1 * la;
		alb = mix(alb, sl, slag * (1.0 - 0.35 * smoothstep(0.6, 0.9, n2) * (1.0 - slope)));
		rough = mix(rough, 0.32, slag * (0.4 + 0.6 * n3));
		spec = mix(spec, 0.6, slag);
	}
	vec3 em = vec3(0.0);
	if (slag > 0.001 && ember > 0.001) {
		// Still-warm slag: thin glowing cracks, brighter low on the heap, dim by distance.
		float cr = 1.0 - smoothstep(0.0, 0.035, abs(fbm(p * 0.35 + wpos.y * 0.2) - 0.5));
		float low = 1.0 - smoothstep(0.0, 9.0, wpos.y - (fbm(p * 0.05) * 4.0));
		em = ember_col * cr * (0.35 + 0.65 * low) * ember * (1.0 - restore);
	}
	float flat_ = 1.0 - smoothstep(0.25, 0.6, slope);
	if (restore > 0.001) {
		float lg = lum(two_scale(tex_g, p, 0.25));
		float lich = smoothstep(0.62, 0.42, n3 * 0.6 + n2 * 0.6 - restore * 0.6) * smoothstep(0.0, 0.3, restore);
		alb = mix(alb, lichen_col * (0.7 + 0.6 * n3), lich * 0.8 * mix(0.55, 1.0, flat_));
		float red = smoothstep(0.62, 0.4, n2 + slope * 0.9 - restore * 0.55 + (n1 - 0.5) * 0.4) * smoothstep(0.15, 0.55, restore) * flat_;
		alb = mix(alb, redleaf_col * lg * 2.8, red * 0.85);
		float green = smoothstep(0.56, 0.36, (1.0 - n2) * 0.8 + slope * 0.9 - restore * 0.6 + (n1 - 0.5) * 0.5) * smoothstep(0.4, 0.95, restore) * flat_;
		alb = mix(alb, green_col * lg * 2.5, green);
		rough = mix(rough, 0.82, max(red, green));
	}
	alb *= mix(0.84, 1.06, n1);
	float nk = 0.6 * (1.0 - smoothstep(60.0, 260.0, dist));
	vec3 wn = mix(nrm_ws(nrm_a, p, scale_a, n, nk), nrm_ws(nrm_b, p, scale_b, n, nk * tw.y), mb);
	ALBEDO = alb;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ROUGHNESS = rough;
	SPECULAR = spec;
	EMISSION = em;
}
