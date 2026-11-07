shader_type spatial;
// [planet-rime] Rime's land beyond the field (planet/planets/rime/env.gd builds the heightfield):
// glassy blue ice sheets with fracture lines, soft snow drifts, shattered pressure ridges, deep
// crevasses with a cold blue light inside, ice cliffs on the crater rim. Vertex COLOR carries
// the masks from the CPU heightfield: r crevasse, g snow drift, b ridge, a hollow.
// Ruined: drill spoil (grey-brown tailings) stains the ice around the old derricks and the
// borehole. Restored: the stains fade and moss carpets creep out of the hollows.
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D snow_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 ice_col : source_color = vec3(0.42, 0.66, 0.84);
uniform vec3 ice_deep : source_color = vec3(0.06, 0.2, 0.42);
uniform vec3 snow_tint : source_color = vec3(0.93, 0.96, 1.0);
uniform vec3 crev_col : source_color = vec3(0.3, 0.7, 1.0);
uniform vec3 moss_col : source_color = vec3(0.3, 0.42, 0.17);
uniform vec3 spoil_col : source_color = vec3(0.34, 0.31, 0.29);
uniform float restore = 0.0;
uniform float night = 0.0;
uniform float moss_r = 120.0;      // moss reaches this far out from the base at full restore
uniform vec4 hole = vec4(0.0, 0.0, -1.0, 0.0);   // borehole x, z, radius (fragments inside are cut)
uniform vec4 sites[8];             // drill spoil: x, z, radius, strength

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 vmask;

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

// Thin wandering fracture lines (noise iso-lines, not a cell grid).
float fracture(vec2 p, float w) {
	float n = fbm(p) - 0.5;
	return 1.0 - smoothstep(0.0, w, abs(n));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vmask = COLOR;
}

void fragment() {
	vec2 p = wpos.xz;
	if (hole.z > 0.0 && length(p - hole.xy) < hole.z) {
		discard;
	}
	vec3 n = normalize(wnrm);
	float slope = 1.0 - clamp(n.y, 0.0, 1.0);
	float dist = length(CAMERA_POSITION_WORLD - wpos);
	float n1 = fbm(p * 0.011);
	float n2 = fbm(p * 0.06 + 11.0);
	float n3 = fbm(p * 0.33 + 5.0);
	float crev = vmask.r;
	float drift = vmask.g;
	float ridge = vmask.b;
	float hollow = vmask.a;
	// --- Ice: glassy, deep blue where thick, milky where it is fractured -----------------
	float depth = smoothstep(0.25, 0.75, n1 + (n2 - 0.5) * 0.4);
	vec3 ice = mix(ice_col, ice_deep, depth * 0.55 + crev * 0.4);
	float fr1 = fracture(p * 0.045, 0.018);
	float fr2 = fracture(p * 0.19 + 3.0, 0.022) * (1.0 - smoothstep(30.0, 140.0, dist));
	ice = mix(ice, vec3(0.86, 0.93, 1.0), fr1 * 0.55 + fr2 * 0.35);
	// Trapped bubbles and dust in the ice.
	ice *= 0.92 + 0.12 * n3;
	float ice_rough = 0.06 + 0.12 * fr1 + 0.1 * n3;
	// --- Snow ---------------------------------------------------------------------------
	vec3 snow = mix(texture(snow_tex, p * 0.11).rgb, texture(snow_tex, p * 0.023 + 0.3).rgb, 0.45) * snow_tint;
	float snow_amt = clamp(drift * 1.1 + smoothstep(0.58, 0.8, n2) * 0.45 - slope * 1.8 - ridge * 0.5 - 0.15, 0.0, 1.0);
	snow_amt = max(snow_amt, smoothstep(0.66, 0.9, n2 + (1.0 - slope) * 0.15) * 0.5 * (1.0 - crev));
	vec3 alb = mix(ice, snow, snow_amt);
	float rough = mix(ice_rough, 0.62, snow_amt);
	// Steep faces (ridges, cliffs) are bare blue ice with banding.
	float steep = smoothstep(0.35, 0.7, slope);
	vec3 cliff = mix(ice_col * 0.9, ice_deep * 1.4, 0.5 + 0.5 * sin(wpos.y * 1.7 + n2 * 6.0)) * (0.9 + 0.2 * n3);
	alb = mix(alb, cliff, steep * (1.0 - snow_amt * 0.5));
	rough = mix(rough, 0.12, steep);
	// --- Ruin: drill spoil ---------------------------------------------------------------
	float spoil = 0.0;
	for (int i = 0; i < 8; i++) {
		vec4 s = sites[i];
		if (s.z > 0.0) {
			float dd = length(p - s.xy) / s.z;
			spoil = max(spoil, (1.0 - smoothstep(0.35, 1.0, dd + (n2 - 0.5) * 0.5)) * s.w);
		}
	}
	spoil *= (1.0 - restore * 0.9) * (0.6 + 0.4 * n3);
	alb = mix(alb, spoil_col * (0.8 + 0.4 * n2), spoil * 0.75);
	rough = mix(rough, 0.85, spoil);
	// --- Restored: moss carpets out of the hollows ---------------------------------------
	float r = length(p);
	if (restore > 0.001) {
		float reach = 1.0 - smoothstep(moss_r * restore * 0.6, moss_r * restore, r - 60.0);
		float m = smoothstep(0.55, 0.3, n2 - hollow * 0.45 + slope * 1.2 + crev - restore * 0.25) * reach * restore;
		m *= 1.0 - steep;
		vec3 mc = texture(moss_tex, p * 0.21).rgb * moss_col * 2.2;
		mc *= mix(vec3(1.0), vec3(1.25, 0.85, 0.7), smoothstep(0.6, 0.8, n3) * 0.5);   // rusty-red moss patches
		alb = mix(alb, mc, m);
		rough = mix(rough, 0.9, m);
	}
	alb *= mix(0.9, 1.04, n1);
	// --- Crevasse light: cold blue from deep inside (stronger at night) -------------------
	vec3 em = crev_col * smoothstep(0.35, 1.0, crev) * (0.16 + 0.5 * night) * (1.0 - restore * 0.3);
	// Frost glints near the camera.
	vec2 cell = floor(p * 8.0);
	float g = h21(cell + floor(CAMERA_POSITION_WORLD.xz * 0.5));
	em += vec3(0.9, 0.95, 1.0) * step(0.997, g) * snow_amt * (1.0 - smoothstep(8.0, 40.0, dist)) * 0.8;
	vec3 tn = texture(snow_nrm, p * 0.11).rgb * 2.0 - 1.0;
	float nk = snow_amt * 0.6 * (1.0 - smoothstep(40.0, 200.0, dist));
	vec3 wn = normalize(n * max(tn.z, 0.2) + vec3(1.0, 0.0, 0.0) * tn.x * nk + vec3(0.0, 0.0, 1.0) * -tn.y * nk);
	ALBEDO = alb;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ROUGHNESS = rough;
	SPECULAR = mix(0.7, 0.4, snow_amt);
	EMISSION = em;
}
