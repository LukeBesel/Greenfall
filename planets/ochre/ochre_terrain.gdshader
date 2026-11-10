shader_type spatial;
// [planet-ochre] Ochre's pit, plateau and mesas. Vertex COLOR: r = bench level (0 floor .. 1 rim),
// g = flat bench (1) or wall (0), b = across the bench (0 crest .. 1 toe) / up the wall (0 .. 1),
// a = inside the pit. UV = (arc length along the bench, pit radius).
// Layered sediment bands by world height (shared by pit walls and mesas, so the strata line up),
// quarried rock on walls, red gravel on benches, ochre sand and salt pans on the plateau.
// Restored: terraced farms climb the benches from the floor up (crop rows along the contours,
// a water channel at the foot of each wall, vines down the walls); futuristic: a thin light seam
// along each bench crest.
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D tex_wall : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm_wall : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_bench : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm_bench : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_sand : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_crack : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_leaf : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_soil : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 c_ochre = vec3(0.8, 0.56, 0.27);
uniform vec3 c_terra = vec3(0.66, 0.34, 0.2);
uniform vec3 c_cream = vec3(0.9, 0.8, 0.62);
uniform vec3 c_plum = vec3(0.46, 0.29, 0.26);
uniform vec3 c_salt = vec3(0.95, 0.93, 0.87);
uniform vec3 c_water = vec3(0.07, 0.36, 0.38);
uniform vec3 c_line = vec3(0.78, 0.94, 1.0);
uniform float restore = 0.0;   // 0 ruined .. 1 restored (hex levels)
uniform float stage = 1.0;     // base level 1..5
uniform float night = 0.0;
uniform float time_s = 0.0;
uniform float pan_amt = 1.0;
// Local frame for strata and slopes (a site placed on a globe passes its own up and origin).
uniform vec3 local_up = vec3(0.0, 1.0, 0.0);
uniform vec3 local_origin = vec3(0.0);  // salt pans on open ground (sites turn them down)

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

// Cell distance (salt-crust polygons).
float cells(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 9.0;
	float d2 = 9.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(h21(i + g), h21(i + g + 19.7));
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return d2 - d1;
}

vec3 two_scale(sampler2D t, vec2 p, float s) {
	vec3 a = texture(t, p * s).rgb;
	vec3 b = texture(t, p * s * 0.23 + vec2(0.37, 0.71)).rgb;
	return mix(a, b, 0.4);
}

// Sediment band colour at height y (gently dipping, wavy, a few thin pale beds).
vec3 strata(vec3 w, float h) {
	float u = h * 0.16 + w.x * 0.0035 - w.z * 0.002 + (fbm(w.xz * 0.004) - 0.5) * 1.6;
	float k = fract(u / 5.0) * 5.0;
	vec3 c = c_ochre * 1.05;
	c = mix(c, c_terra, smoothstep(0.8, 1.05, k) - smoothstep(1.9, 2.15, k));
	c = mix(c, c_cream, smoothstep(2.15, 2.3, k) - smoothstep(2.6, 2.75, k));
	c = mix(c, c_plum * 0.9, smoothstep(3.0, 3.2, k) - smoothstep(3.55, 3.75, k));
	c = mix(c, c_terra * 1.1, smoothstep(3.75, 3.9, k) - smoothstep(4.5, 4.7, k));
	float thin = smoothstep(0.03, 0.0, abs(fract(u * 1.7) - 0.5) - 0.44);
	return mix(c, c_cream * 1.05, thin * 0.5);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = wpos.xz;
	vec3 n = normalize(wnrm);
	vec3 up = normalize(local_up);
	float lh = dot(wpos - local_origin, up);
	float slope = 1.0 - clamp(dot(n, up), 0.0, 1.0);
	float lvl = COLOR.r;
	float flat_b = COLOR.g;
	float across = COLOR.b;
	float pit = COLOR.a;
	float dist = length(CAMERA_POSITION_WORLD - wpos);
	float n1 = fbm(p * 0.011);
	float n2 = fbm(p * 0.07 + 11.0);
	float n3 = fbm(p * 0.33 + 5.0);
	// Rock: quarry wall, projected from the side it faces.
	vec3 tw = pow(abs(n), vec3(4.0));
	tw /= (tw.x + tw.y + tw.z);
	vec3 rock = two_scale(tex_wall, wpos.zy, 0.07) * tw.x + two_scale(tex_wall, wpos.xy, 0.07) * tw.z + two_scale(tex_wall, p, 0.07) * tw.y;
	float rl = dot(rock, vec3(0.33));
	vec3 st = strata(wpos, lh);
	vec3 wall_c = st * (0.55 + rl * 0.55);
	// Benches: red gravel and haul dust, ochre sand drifting against the toe.
	vec3 grav = two_scale(tex_bench, p, 0.22);
	vec3 bench_c = mix(grav * vec3(1.05, 0.78, 0.62), c_terra * (0.8 + 0.5 * dot(grav, vec3(0.33))), 0.55 + 0.3 * n2);
	vec3 sand = two_scale(tex_sand, p, 0.12) * vec3(1.0, 0.72, 0.46);
	bench_c = mix(bench_c, sand, smoothstep(0.6, 0.95, across) * 0.35 * pit + (1.0 - pit) * (0.78 + 0.12 * n1));
	float wallness = smoothstep(0.35, 0.6, slope + (n2 - 0.5) * 0.15);
	vec3 alb = mix(bench_c, wall_c, wallness);
	// Cheap occlusion: wall feet and the inner corner of each bench sit in shade.
	float occ = pit > 0.5 ? (flat_b > 0.5 ? mix(1.0, 0.68, smoothstep(0.78, 1.0, across)) : mix(0.62, 1.0, smoothstep(0.0, 0.7, across))) : 1.0;
	alb *= occ;
	float rough = mix(0.93, 0.88, wallness);
	// Plateau salt pans (flat ground beyond the rim) and the dried floor of the pit.
	float flatness = 1.0 - smoothstep(0.05, 0.14, slope);
	float pan = smoothstep(0.62, 0.67, fbm(p * 0.0026 + 3.0)) * (1.0 - pit) * flatness * pan_amt;
	pan = max(pan, (1.0 - step(0.02, lvl)) * flat_b * pit * (1.0 - restore * 1.4));
	if (pan > 0.001) {
		float cr = cells(p * 0.55);
		vec3 crack = two_scale(tex_crack, p, 0.18);
		vec3 salt = c_salt * (0.72 + 0.2 * dot(crack, vec3(0.33)));
		salt *= mix(0.78, 1.0, smoothstep(0.02, 0.09, cr));
		alb = mix(alb, salt, clamp(pan, 0.0, 1.0));
		rough = mix(rough, 0.75, pan);
	}
	// Tailings stains: grey-yellow streaks running down the walls from the benches.
	float streak = smoothstep(0.62, 0.8, fbm(vec2(p.x * 0.09 + p.y * 0.09, lh * 0.02) + 4.0)) * wallness * pit * (1.0 - restore);
	alb = mix(alb, vec3(0.7, 0.66, 0.5), streak * 0.35);

	// --- Restoration: terraces green from the floor up --------------------------------------
	vec3 em = vec3(0.0);
	float wet = 0.0;
	if (restore > 0.001 && pit > 0.5) {
		float reach = restore * 1.15 + (n1 - 0.5) * 0.08;
		float g = smoothstep(lvl - 0.02, lvl + 0.06, reach);
		if (flat_b > 0.5 && g > 0.001) {
			// Plots along the bench; each its own crop. Rows follow the contours.
			float plot = floor(UV.x / 26.0 + n2 * 0.6);
			float kind = h21(vec2(plot, floor(lvl * 40.0 + 0.5)));
			float row = sin(UV.y * 6.2831 / 1.35);
			vec3 leaf = two_scale(tex_leaf, p, 0.3);
			vec3 soil = mix(two_scale(tex_soil, p, 0.25) * vec3(0.72, 0.56, 0.42), two_scale(tex_leaf, p, 0.3) * vec3(0.7, 0.85, 0.5), 0.35);
			vec3 crop = leaf * vec3(0.85, 1.05, 0.62);
			crop = mix(crop, leaf * vec3(1.35, 1.12, 0.45), step(0.55, kind) * (1.0 - step(0.78, kind)));  // grain
			crop = mix(crop, leaf * vec3(0.55, 0.82, 0.45), step(0.78, kind));                          // dark greens
			crop = mix(crop, vec3(0.62, 0.32, 0.22) * (0.8 + 0.4 * n3), step(0.93, kind));              // sorghum red
			float rows = mix(0.72, smoothstep(-0.25, 0.35, row), 0.38);
			vec3 farm = mix(soil, crop, mix(rows, 0.9, step(0.55, kind) * (1.0 - step(0.78, kind))));
			// Paths between plots, a crest strip of succulents and gravel, the channel at the toe.
			float edge = smoothstep(0.0, 0.04, abs(fract(UV.x / 26.0 + n2 * 0.6) - 0.5) - 0.47);
			farm = mix(farm, bench_c * 0.95, edge);
			float crest = 1.0 - smoothstep(0.14, 0.2, across);
			farm = mix(farm, mix(bench_c, leaf * vec3(0.7, 0.9, 0.55), 0.35 * smoothstep(0.5, 0.7, n3)), crest);
			// Field bench: only a green verge, the play field ground takes over.
			float big = step(0.17, lvl) * (1.0 - step(0.19, lvl));
			farm = mix(farm, mix(bench_c, leaf * vec3(0.72, 0.92, 0.5), 0.8 * smoothstep(0.3, 0.55, n2 + n1 * 0.3)), big);
			alb = mix(alb, farm, g);
			float chan = smoothstep(0.84, 0.86, across) * (1.0 - smoothstep(0.92, 0.94, across)) * (1.0 - big);
			wet = chan * g;
			float lip = (smoothstep(0.81, 0.84, across) - smoothstep(0.84, 0.85, across) + smoothstep(0.93, 0.94, across) - smoothstep(0.94, 0.97, across)) * (1.0 - big);
			alb = mix(alb, c_cream * 0.85, lip * g);
			rough = mix(rough, 0.85, g);
		} else if (g > 0.001) {
			// Vines hanging from the crest down the wall.
			float len = 0.25 + 0.6 * fbm(vec2(UV.x * 0.35, 3.0));
			float vine = smoothstep(1.0 - len, 1.0 - len + 0.15, across) * smoothstep(0.35, 0.6, fbm(vec2(UV.x * 0.9, lh * 0.3)));
			vec3 leaf = two_scale(tex_leaf, wpos.xy + wpos.zy, 0.35) * vec3(0.8, 1.0, 0.6);
			alb = mix(alb, leaf, vine * g * 0.9);
		}
	}
	if (wet > 0.001) {
		float rip = fbm(vec2(UV.x * 0.6 - time_s * 0.8, UV.y * 2.0));
		alb = mix(alb, c_water * (0.8 + 0.4 * rip), wet);
		rough = mix(rough, 0.06, wet);
	}
	// Futuristic: a thin seam of light along each bench crest (stronger at night, never neon).
	if (stage >= 3.5 && pit > 0.5 && flat_b > 0.5 && lvl > 0.02) {
		float seam = smoothstep(0.012, 0.0, abs(across - 0.03)) * (1.0 - smoothstep(60.0, 420.0, dist) * 0.6);
		em += c_line * seam * mix(0.35, 1.2, night) * clamp(stage - 3.5, 0.0, 1.0);
	}
	alb *= mix(0.78, 1.08, n1);
	// Normal detail: rock on walls, gravel on benches (faded with distance).
	float nk = 0.55 * (1.0 - smoothstep(50.0, 240.0, dist));
	vec3 tn = (texture(nrm_wall, (tw.x > tw.z ? wpos.zy : wpos.xy) * 0.07).rgb * 2.0 - 1.0) * wallness
		+ (texture(nrm_bench, p * 0.22).rgb * 2.0 - 1.0) * (1.0 - wallness);
	vec3 t1 = normalize(cross(n, vec3(0.0, 0.0, 1.0)) + vec3(0.0001));
	vec3 b1 = normalize(cross(t1, n));
	vec3 wn = normalize(n + (t1 * tn.x + b1 * tn.y) * nk * (1.0 - wet));
	ALBEDO = alb;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ROUGHNESS = rough;
	SPECULAR = mix(0.35, 0.6, wet);
	EMISSION = em;
}
