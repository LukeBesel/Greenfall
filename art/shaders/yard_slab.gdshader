shader_type spatial;
// The hub yard surface: cast-in-place concrete slabs (3 m bays) with sawn expansion joints,
// per-slab tone, a couple of slabs replaced by asphalt patches, oil stains and tyre scuffs,
// dust drifting in from the edges, and the painted markings / cracks / moss that
// StreetDressing bakes into `paint` (RGBA), worn by noise. Opaque, so SSR and SSAO work on it.
render_mode cull_back;
// [orbD] Site frame on a walkable globe (identity on the flat game): "world" maths run in the
// nearest hub site's local metres, y up on its pad (planet/sites/site_manager.gd).
global uniform mat4 site_inv;

uniform sampler2D conc_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D conc_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D conc_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asph_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asph_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D paint : source_color, filter_linear_mipmap_anisotropic;
uniform float half_size = 8.5;
uniform float bay = 2.833;
uniform float seed = 0.0;
// Per-base state (StreetDressing): paint fade + extra grime while the base is ruined, wind-blown
// drift (sand, snow, mud) from the edges, and broken-off corners (chamfer size per corner, m).
uniform float fade = 0.0;
uniform float grime = 0.0;
uniform float drift = 0.0;
uniform vec3 drift_col : source_color = vec3(0.86, 0.74, 0.55);
uniform vec4 cut = vec4(0.0);
// Restored (level 3+): cyan light inlaid along the slab seams and a strip just inside the edge.
uniform float glow = 0.0;
uniform vec3 glow_col : source_color = vec3(0.3, 0.9, 1.0);

varying vec3 v_world;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 5; i++) {
		s += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	v_world = (site_inv * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 w = v_world.xz;
	// Broken corners: the slab ends in a ragged chamfer and the ground shows through.
	float cc = w.x < 0.0 ? (w.y < 0.0 ? cut.x : cut.z) : (w.y < 0.0 ? cut.y : cut.w);
	float cut_d = (abs(w.x) + abs(w.y)) - (2.0 * half_size - cc) + (noise(w * 2.3 + seed) - 0.5) * 0.7;
	if (cc > 0.0 && cut_d > 0.0) {
		discard;
	}
	vec2 g = (w + vec2(half_size)) / bay;
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float h = hash(cell + seed);
	// Each slab poured separately: tone and texture offset vary; a few are asphalt patches.
	vec2 uv = w * 0.33 + vec2(h * 7.0, hash(cell + 3.1) * 7.0);
	vec3 alb = texture(conc_alb, uv).rgb;
	vec3 nrm = texture(conc_nrm, uv).rgb;
	vec3 arm = texture(conc_arm, uv).rgb;
	alb *= mix(0.95, 1.2, h) * vec3(0.98, 0.97, 0.95);
	float asphalt = step(0.86, hash(cell + 11.0 + seed));
	if (asphalt > 0.5) {
		vec2 auv = w * 0.4;
		alb = texture(asph_alb, auv).rgb * 0.75;
		nrm = texture(asph_nrm, auv).rgb;
		arm.g = 0.85;
	}
	// Sawn joints: a thin dark groove with a lighter lip, dirt packed in.
	vec2 d = min(f, 1.0 - f) * bay;
	float jd = min(d.x, d.y);
	float joint = smoothstep(0.035, 0.018, jd);
	float lip = smoothstep(0.1, 0.035, jd) * (1.0 - joint);
	alb = mix(alb, alb * 0.82, lip * 0.6);
	alb = mix(alb, vec3(0.035, 0.032, 0.028), joint);
	// Moss / grime creeping along the joints, more near the fence.
	float edge = smoothstep(half_size - 2.5, half_size, max(abs(w.x), abs(w.y)));
	float moss = smoothstep(0.25, 0.0, jd) * smoothstep(0.55, 0.8, fbm(w * 1.3 + seed)) * (0.35 + edge);
	alb = mix(alb, vec3(0.13, 0.17, 0.07), clamp(moss, 0.0, 0.7));
	// Oil stains: soft dark blots with a darker core, and tyre scuffs along the walkway.
	float oil = smoothstep(0.62, 0.78, fbm(w * 0.45 + 13.0 + seed));
	float core = smoothstep(0.7, 0.82, fbm(w * 0.45 + 13.0 + seed) + noise(w * 3.0) * 0.05);
	alb *= 1.0 - oil * 0.45 - core * 0.25;
	float scuff = smoothstep(0.35, 0.0, abs(fract(w.x * 0.9 + noise(w * 0.3) * 0.6) - 0.5)) * smoothstep(0.5, 0.75, noise(vec2(w.x * 0.3, w.y * 2.5)));
	alb *= 1.0 - scuff * 0.12 * (1.0 - asphalt);
	// Wind-blown dust collects toward the fence.
	vec3 dust = vec3(0.47, 0.42, 0.35);
	alb = mix(alb, dust * (0.8 + 0.4 * noise(w * 4.0)), edge * 0.35 * fbm(w * 0.8));
	// Neglect: blotchy dirt and dead leaves over everything.
	float gm = smoothstep(0.35, 0.75, fbm(w * 0.7 + 31.0 + seed)) * grime;
	alb = mix(alb, vec3(0.2, 0.17, 0.13) * (0.7 + 0.6 * noise(w * 6.0)), gm * 0.65);
	// Drift heaped against the fence and in long tongues across the slab.
	float dm = smoothstep(0.4, 0.75, fbm(vec2(w.x * 0.35, w.y * 0.9) + 7.0 + seed) + edge * 0.45) * drift;
	alb = mix(alb, drift_col * (0.85 + 0.25 * noise(w * 5.0)), clamp(dm, 0.0, 1.0));
	// Baked paint, cracks and moss.
	vec4 p = texture(paint, (w + vec2(half_size)) / (2.0 * half_size));
	float big = noise(w * 0.45) * 0.6 + noise(w * 1.7) * 0.4;
	float chip = noise(w * 11.0) * 0.6 + noise(w * 37.0) * 0.4;
	float wear = smoothstep(0.45, 0.8, big * 0.55 + chip * 0.45 + oil * 0.2);
	float is_paint = step(0.3, max(p.r, max(p.g, p.b)));
	float pa = p.a * (1.0 - wear * 0.85 * is_paint) * (0.7 + 0.3 * chip) * (1.0 - joint);
	pa *= 1.0 - clamp(fade * (0.75 + 0.5 * big) * is_paint + dm * 0.8, 0.0, 1.0);
	vec3 painted = p.rgb * (0.78 + 0.2 * chip) * mix(vec3(1.0), alb / max(dot(alb, vec3(0.33)), 0.05) * 0.5 + 0.5, 0.35);
	alb = mix(alb, painted, pa);
	float rough = mix(arm.g * 1.05, 0.7, pa * is_paint);
	rough = mix(rough, 0.95, clamp(dm, 0.0, 1.0));
	rough = mix(rough, 0.35, core * 0.8);
	ALBEDO = alb * 1.22;  // lighter, sun-bleached concrete
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	AO = arm.r;
	NORMAL_MAP = mix(nrm, vec3(0.5, 0.5, 1.0), clamp(pa * is_paint * 0.6 + dm * 0.7, 0.0, 1.0));
	NORMAL_MAP_DEPTH = 1.0;
	if (glow > 0.0) {
		float strip = smoothstep(0.035, 0.01, abs(max(abs(w.x), abs(w.y)) - (half_size - 0.95)));  // a hairline
		float pulse = 0.75 + 0.25 * sin(TIME * 1.6 - length(w) * 0.6);
		float seam = joint * (1.0 - asphalt * 0.7) * pulse;
		EMISSION = glow_col * glow * (seam * 0.3 + strip * 1.4) * (1.0 - dm * 0.8);  // subtle, not a neon grid
		ALBEDO = mix(ALBEDO, glow_col, strip * 0.3);
	}
}
