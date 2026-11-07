shader_type spatial;
// City ground with per-hex restoration. Also used on sidewalk slab tops (works from world XZ).
// Texture2DArray layers: 0 worn asphalt, 1 damaged road, 2 concrete pavement, 3 dirty concrete,
// 4 dry ground + rocks, 5 withered grass, 6 dry decayed leaves, 7 rubble.
// layout_tex: R surface (0 lot, .25 road, .5 sidewalk, .75 building, 1 yard), G lane paint, B gutter.
// state_tex (per hex): R removed fraction, G flip time, B clean flag, A hub flag.
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2DArray albedo_arr : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_arr : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray arm_arr : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D layout_tex : filter_linear;
uniform float layout_size = 280.0;
uniform sampler2D state_tex : filter_nearest;
// Natural borders: offset (RG, metres / warp_amp) baked by HexField.border_warp_image().
uniform sampler2D warp_tex : filter_linear;
uniform float warp_size = 280.0;
uniform float warp_amp = 0.0;
uniform sampler2D life_tex : filter_linear;
uniform int grid_radius = 9;
uniform float hex_size = 3.2;
uniform float time_now = 0.0;
uniform vec2 focus_axial = vec2(9999.0);
uniform float ripple_speed = 5.0;
uniform float show_grid = 0.0;
// Wilderness biome look (data/junk.json "biomes"): rgb = colour the bare ground leans to, a = amount.
uniform vec4 biome_tint = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec3 grass_tint = vec3(1.0);
// [biomes] Frontier ground extras: x = wind-rippled sand, y = frost/snow, z = wet silt, w unused.
uniform vec4 frontier_fx = vec4(0.0);
// [biomes2] Frontiers: the ground stops here and the terrain mesh (frontier_view.gd) takes over.
uniform float clip_r = 0.0;
// [biomes2] Frontiers: the lakebed follows the warped (natural) shoreline like water.gdshader.
uniform float lake_warp = 0.0;

varying vec3 wpos;
const float SQRT3 = 1.7320508;

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
		p = p * 2.07 + 13.1;
		a *= 0.5;
	}
	return v;
}

vec2 hex_round(vec2 qr) {
	vec3 c = vec3(qr.x, qr.y, -qr.x - qr.y);
	vec3 r = round(c);
	vec3 d = abs(r - c);
	if (d.x > d.y && d.x > d.z) {
		r.x = -r.y - r.z;
	} else if (d.y > d.z) {
		r.y = -r.x - r.z;
	}
	return r.xy;
}

struct Mat { vec3 alb; vec3 nrm; vec3 arm; };

Mat samp(int i, vec2 p, float tile) {
	float a = float(i) * 1.7;
	mat2 rot = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
	vec2 uv = rot * p / tile + vec2(float(i) * 0.37);
	Mat m;
	m.alb = texture(albedo_arr, vec3(uv, float(i))).rgb;
	m.nrm = texture(normal_arr, vec3(uv, float(i))).rgb;
	m.arm = texture(arm_arr, vec3(uv, float(i))).rgb;
	return m;
}

Mat mixm(Mat a, Mat b, float t) {
	Mat m;
	m.alb = mix(a.alb, b.alb, t);
	m.nrm = mix(a.nrm, b.nrm, t);
	m.arm = mix(a.arm, b.arm, t);
	return m;
}

// [green] Living sward: the photo grass textures recoloured into rich greens (on their own they
// read dry and brown), lighter and patchier while young, deep and even when lush.
Mat grass_mat(vec2 p, float life) {
	Mat grass = mixm(samp(8, p, 3.0), samp(9, p, 3.5), 0.5 + 0.3 * smoothstep(0.35, 0.8, life));
	float gl = dot(grass.alb, vec3(0.3, 0.59, 0.11));
	float hn = fbm(p * 0.09 + 50.0);
	vec3 deep = vec3(0.07, 0.17, 0.035);
	vec3 fresh = vec3(0.16, 0.3, 0.05);
	vec3 sunlit = vec3(0.27, 0.34, 0.07);
	vec3 green = mix(deep, fresh, smoothstep(0.3, 0.7, hn));
	green = mix(green, sunlit, smoothstep(0.62, 0.85, fbm(p * 0.33 + 9.0)) * 0.55);
	green = mix(green * vec3(1.2, 1.15, 1.0), green, smoothstep(0.4, 0.95, life));
	grass.alb = mix(green * clamp(gl / 0.32, 0.55, 1.5), grass.alb * 0.6, 0.12) * grass_tint;
	grass.arm.g = clamp(grass.arm.g, 0.75, 1.0);
	return grass;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	// The seam wanders (fbm) so the field never reads as a disc set into the land.
	if (clip_r > 0.0 && length(p) > clip_r + (fbm(p * 0.035) - 0.5) * 16.0 + (fbm(p * 0.21 + 7.0) - 0.5) * 3.0) {
		discard;
	}
	vec4 lay = texture(layout_tex, p / layout_size + 0.5);
	float surf = lay.r;
	bool is_road = surf > 0.15 && surf < 0.35;
	bool is_walk = surf > 0.4 && surf < 0.6;
	bool is_yard = surf > 0.9;

	// Hex lookup.
	vec2 qr = vec2((SQRT3 / 3.0 * p.x - p.y / 3.0) / hex_size, (2.0 / 3.0 * p.y) / hex_size);
	vec2 ax = hex_round(qr);
	vec2 center = vec2(hex_size * (SQRT3 * ax.x + SQRT3 * 0.5 * ax.y), hex_size * 1.5 * ax.y);
	vec2 local = p - center;
	float apothem = hex_size * SQRT3 * 0.5;
	float mx = max(abs(local.x), max(abs(dot(local, vec2(0.5, SQRT3 * 0.5))), abs(dot(local, vec2(0.5, -SQRT3 * 0.5)))));
	float edge_d = apothem - mx;
	float hex_dist = (abs(ax.x) + abs(ax.y) + abs(ax.x + ax.y)) * 0.5;
	bool inside = hex_dist <= float(grid_radius);
	// Natural borders: the ground state is looked up at a noise-warped position, so the line
	// between clean / green / junk ground wanders organically instead of following hex edges.
	// (Selection outline and grid lines still use the true hex.)
	// Same warp the junk placement used (so ground and junk edges agree), plus a little fine wobble.
	vec2 warp = texture(warp_tex, p / warp_size + 0.5).rg * warp_amp
		+ (vec2(fbm(p * 0.9 + 3.0), fbm(p * 0.9 + 91.0)) - 0.5) * hex_size * 0.18 * step(0.001, warp_amp);
	vec2 pw = p + warp;
	vec2 qr_w = vec2((SQRT3 / 3.0 * pw.x - pw.y / 3.0) / hex_size, (2.0 / 3.0 * pw.y) / hex_size);
	vec2 ax_s = hex_round(qr_w);
	vec2 center_s = vec2(hex_size * (SQRT3 * ax_s.x + SQRT3 * 0.5 * ax_s.y), hex_size * 1.5 * ax_s.y);
	bool inside_s = (abs(ax_s.x) + abs(ax_s.y) + abs(ax_s.x + ax_s.y)) * 0.5 <= float(grid_radius);
	float removed = 0.0;
	float is_clean = 0.0;
	float is_hub = 0.0;
	float flip_t = -100.0;
	float life = 0.0;
	float row_a = 0.0;  // [green] planting-row angle (life_tex.b)
	float size = float(grid_radius * 2 + 1);
	if (inside) {
		// Hub/lake flag stays on the true hex (the yard slab and lake water are hex-shaped meshes).
		is_hub = texture(state_tex, (ax + vec2(float(grid_radius)) + 0.5) / size).a;
	}
	if (lake_warp > 0.5 && is_hub < 0.75) {
		float wl = inside_s ? texture(state_tex, (ax_s + vec2(float(grid_radius)) + 0.5) / size).a : 0.0;
		is_hub = (wl > 0.4 && wl < 0.6) ? wl : 0.0;
	}
	if (inside_s) {
		vec4 st = texture(state_tex, (ax_s + vec2(float(grid_radius)) + 0.5) / size);
		removed = st.r;
		flip_t = st.g;
		is_clean = st.b;
		// Greenery fades smoothly between neighbouring hexes (linear filter at the warped spot).
		vec4 lt = texture(life_tex, (qr_w + vec2(float(grid_radius)) + 0.5) / size);
		life = lt.r;
		row_a = lt.b * 3.14159;
	}
	float reveal = 0.0;
	float wave = 0.0;
	if (is_clean > 0.5) {
		float age = time_now - flip_t;
		float d = length(pw - center_s);
		float front = age * ripple_speed;
		reveal = clamp((front - d) / 1.6 + fbm(p * 0.8) * 0.6 - 0.3, 0.0, 1.0);
		wave = (1.0 - smoothstep(0.0, 1.4, abs(front - d))) * (1.0 - smoothstep(1.0, 3.0, age));
	}
	if (!inside) {
		reveal = 0.0;
	}

	float n1 = fbm(p * 0.07);
	float n2 = fbm(p * 0.19 + 31.0);
	float n3 = fbm(p * 0.5 + 77.0);
	// --- Clean base surface -----------------------------------------------------------
	Mat base;
	if (is_road) {
		base = mixm(samp(0, p, 4.0), samp(1, p, 5.0), smoothstep(0.45, 0.7, n1));
		// Faded lane paint, broken up.
		float paint = lay.g * smoothstep(0.3, 0.6, fbm(p * 1.3 + 5.0));
		base.alb = mix(base.alb, vec3(0.78, 0.68, 0.42), paint * 0.75);
		base.arm.g = mix(base.arm.g, 0.6, paint);
	} else if (is_walk || is_yard) {
		base = mixm(samp(2, p, 2.5), samp(3, p, 3.0), is_yard ? 0.6 : smoothstep(0.55, 0.75, n1) * 0.6);
	} else {
		base = mixm(samp(4, p, 3.0), samp(5, p, 3.5), smoothstep(0.5, 0.7, n2) * 0.8);
	}
	// --- Dirty overlay: grime, drifts, leaves, rubble --------------------------------
	Mat dirty = base;
	if (reveal < 0.999 && !is_yard) {
		float gutter = lay.b;
		float drift = clamp(smoothstep(0.35, 0.7, n2) * 0.6 + gutter * 0.8, 0.0, 1.0);
		dirty = mixm(dirty, samp(4, p, 3.0), drift * (is_road ? 0.55 : 0.35));
		float leaves = smoothstep(0.5, 0.75, n3) * (0.4 + gutter * 0.6);
		dirty = mixm(dirty, samp(6, p, 2.0), leaves * 0.8);
		float rub = smoothstep(0.62, 0.8, fbm(p * 0.11 + 9.0));
		dirty = mixm(dirty, samp(7, p, 3.0), rub * 0.7);
		float stain = smoothstep(0.55, 0.85, fbm(p * 0.35 + 3.0));
		dirty.alb *= mix(1.0, 0.7, stain * 0.6);
		dirty.alb *= mix(0.9, 0.97, removed);
		
	}
	if (biome_tint.a > 0.001 && !is_road && !is_walk) {
		float lum_b = dot(base.alb, vec3(0.3, 0.55, 0.15));
		base.alb = mix(base.alb, lum_b * biome_tint.rgb * 1.9, biome_tint.a);
		float lum_d = dot(dirty.alb, vec3(0.3, 0.55, 0.15));
		dirty.alb = mix(dirty.alb, lum_d * biome_tint.rgb * 1.9, biome_tint.a * (0.7 + 0.3 * n2));
	}
	Mat m = mixm(dirty, base, reveal);
	// [biomes] Frontier ground extras (off roads and sidewalks).
	if (frontier_fx.x > 0.001 && !is_road && !is_walk && !is_yard) {
		// Wind ripples: long parallel crests that wander, crisp on the lit side.
		float ph = dot(p, vec2(0.83, 0.56)) * 2.6 + fbm(p * 0.18) * 7.0;
		float crest = sin(ph);
		float amt = frontier_fx.x * (0.6 + 0.4 * smoothstep(0.3, 0.7, n2));
		m.alb *= 1.0 + crest * 0.08 * amt;
		m.nrm.x = clamp(m.nrm.x + cos(ph) * 0.2 * amt, 0.0, 1.0);
		m.alb = mix(m.alb, m.alb * vec3(1.05, 0.98, 0.9), amt * 0.4);
		// [biomes2] Wind-scoured streaks: long darker lanes of coarse grit between paler drifts.
		vec2 ws = vec2(dot(p, vec2(0.83, 0.56)), dot(p, vec2(-0.56, 0.83)));
		float streak = fbm(vec2(ws.x * 0.012, ws.y * 0.05) + 5.0);
		m.alb *= mix(0.9, 1.06, smoothstep(0.3, 0.7, streak) * amt + (1.0 - amt) * 0.6);
	}
	if (frontier_fx.y > 0.001 && !is_yard) {
		// Frost and old snow: patchy, heavier on dirty ground and in hollows, thin on clean.
		float fr = smoothstep(0.32, 0.62, fbm(p * 0.21 + 17.0) + n3 * 0.25) * frontier_fx.y;
		fr *= mix(1.0, 0.7, reveal);
		vec3 snow = vec3(0.88, 0.92, 0.98) * (0.92 + 0.08 * n1);
		m.alb = mix(m.alb, snow, fr * 0.85);
		m.arm.g = mix(m.arm.g, 0.42, fr);
		m.nrm = mix(m.nrm, vec3(0.5, 0.5, 1.0), fr * 0.6);
	}
	if (frontier_fx.z > 0.001 && !is_yard) {
		// Wet silt left by the flood: darker, glossy, puddled in the low spots.
		float wet = frontier_fx.z * (0.55 + 0.45 * smoothstep(0.4, 0.7, fbm(p * 0.33 + 41.0)));
		m.alb *= mix(1.0, 0.6, wet);
		m.alb = mix(m.alb, m.alb * vec3(0.92, 0.96, 0.95), wet);
		m.arm.g = mix(m.arm.g, 0.18, wet);
	}
	// [green] Life: freshly planted ground is dark tilled soil in rows; it greens over into a rich,
	// living sward (the photo textures are recoloured: on their own they read dry and brown).
	if (life > 0.001 && !is_road) {
		float g = smoothstep(0.12, 0.8, life + (fbm(p * 0.6) - 0.5) * 0.3);
		// Tilled soil with furrows across the hex's planting rows; fades as the grass closes in.
		vec2 rdir = vec2(cos(row_a), sin(row_a));
		float rows = sin(dot(p, vec2(-rdir.y, rdir.x)) * 6.2832 / 0.8);
		float till = smoothstep(0.0, 0.06, life) * (1.0 - smoothstep(0.35, 0.85, life)) * (is_walk ? 0.0 : 1.0);
		Mat soil = samp(4, p, 2.0);
		float sl = dot(soil.alb, vec3(0.3, 0.59, 0.11));
		soil.alb = vec3(0.13, 0.085, 0.055) * (0.6 + 0.8 * sl) * mix(1.0, 0.72, (1.0 - smoothstep(-0.9, -0.2, rows)) * till);
		soil.nrm = vec3(clamp(0.5 + cos(dot(p, vec2(-rdir.y, rdir.x)) * 6.2832 / 0.8) * 0.3 * till, 0.0, 1.0), 0.5, 1.0);
		soil.arm = vec3(0.85, 0.92, 0.0);
		Mat grass = grass_mat(p, life);
		Mat ground = mixm(m, soil, smoothstep(0.0, 0.08, life) * (is_walk ? 0.25 : 1.0));
		m = mixm(ground, grass, g * (is_walk ? 0.6 : 1.0));
	} else if (life > 0.2 && is_road) {
		// Restored streets: the asphalt is swept to a cleaner grey, grass verges grow in from the
		// kerbs (wider as the hex thrives) and moss creeps out of the cracks. The middle stays road.
		float lum = dot(m.alb, vec3(0.3, 0.59, 0.11));
		m.alb = mix(m.alb, vec3(lum) * vec3(0.93, 0.96, 1.0), 0.55 * smoothstep(0.2, 0.7, life));
		float vr = mix(1.2, 3.4, smoothstep(0.35, 1.0, life));
		float edge = 0.0;
		for (int i = 0; i < 8; i++) {
			float a = float(i) * 0.7854;
			float sr = texture(layout_tex, (p + vec2(cos(a), sin(a)) * vr) / layout_size + 0.5).r;
			edge += (sr > 0.15 && sr < 0.35) ? 0.0 : 1.0;
		}
		edge /= 8.0;
		float verge = smoothstep(0.08, 0.3, edge + (fbm(p * 0.7 + 13.0) - 0.5) * 0.25) * smoothstep(0.3, 0.75, life);
		float crack = smoothstep(0.66, 0.74, fbm(p * 1.9 + 21.0)) * smoothstep(0.5, 1.0, life) * 0.8;
		m = mixm(m, grass_mat(p, life), clamp(max(verge, crack), 0.0, 1.0));
	}
	if (is_hub > 0.75 || is_yard) {
		m = base;
	}
	// Lakebed: dark silty mud that turns to clean wet sand as the water is cleared.
	if (is_hub > 0.4 && is_hub < 0.6) {
		Mat mud = samp(4, p, 2.0);
		mud.alb *= vec3(0.32, 0.3, 0.28);
		Mat sand = samp(4, p, 2.5);
		sand.alb *= vec3(0.95, 0.88, 0.7);
		m = mixm(mud, sand, smoothstep(0.2, 1.0, removed));
		m.arm.g = 0.25;
	}
	// Large-scale value variation to hide tiling.
	m.alb *= mix(0.84, 1.06, fbm(p * 0.02 + 3.0));

	vec3 emission = vec3(0.0);
	if (inside && is_hub < 0.4) {
		float line = (1.0 - smoothstep(0.0, 0.05, edge_d));
		if (distance(ax, focus_axial) < 0.5) {
			emission += vec3(1.0, 0.7, 0.25) * line * 0.3;
		}
		emission += vec3(1.0, 0.85, 0.6) * line * show_grid * 0.12;
		emission += vec3(1.0, 0.86, 0.62) * wave * 0.1;
	}
	ALBEDO = m.alb;
	NORMAL_MAP = m.nrm;
	AO = m.arm.r;
	AO_LIGHT_AFFECT = 0.4;
	ROUGHNESS = clamp(m.arm.g, 0.35, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.4;
	EMISSION = emission;
}
