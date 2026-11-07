shader_type spatial;
// [planet-tidewell] Tidewell's ocean: one opaque surface from the raft base to the horizon. It
// replaces WaterView's lake plane on this planet (built on art/shaders/water.gdshader and
// flood.gdshader: same per-hex state texture, same warped natural shoreline, same light()).
//   - gentle swell (vertex), damped to a few cm over the play field so floating junk sits right
//   - depth from a baked bed-height map: turquoise shallows and lagoons, deep blue offshore
//   - a virtual seabed seen through the surface (one-step refracted parallax): sand ripples,
//     caustics, coral and kelp beds once restored, big fish / whale shadows gliding below
//   - dirty water: murky, oily slicks with a thin-film sheen; each hex clears to blue with the
//     rolling clear-water wave when it is cleaned (state texture), the open sea with restoration
//   - shore foam, sparse whitecaps, hover wakes (Lumi and skimmers) as foam rings and ripples
// Opaque: no sorting cost, and the submerged half of floating junk is hidden like real water.
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D state_tex : filter_nearest;
uniform sampler2D wave_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform int grid_radius = 4;
uniform float hex_size = 10.0;
uniform float time_now = 0.0;
uniform float clarity_bonus = 0.0;
uniform sampler2D warp_tex : filter_linear;
uniform float warp_size = 280.0;
uniform float warp_amp = 0.0;
// Bed height (metres, R) and reef mask (G): near map around the field, far map to the horizon.
uniform sampler2D near_tex : filter_linear;
uniform float near_size = 220.0;
uniform sampler2D far_tex : filter_linear;
uniform float far_size = 2400.0;
uniform float sea_y = 0.14;
uniform float field_r = 48.0;      // swell fades in past here
uniform float swell_amp = 0.32;
uniform float restore = 0.0;       // 0 ruined .. 1 restored (open sea clarity, kelp, coral)
uniform float future = 0.0;        // 0 .. 1 futuristic stage
uniform float detail = 1.0;        // 0 on Low: no kelp/fish/caustic extras
uniform vec3 deep_col : source_color = vec3(0.02, 0.16, 0.24);
uniform vec3 shallow_col : source_color = vec3(0.12, 0.68, 0.66);
uniform vec3 lagoon_col : source_color = vec3(0.42, 0.9, 0.82);
uniform vec3 murky_col : source_color = vec3(0.13, 0.16, 0.13);
uniform vec3 oil_col : source_color = vec3(0.05, 0.045, 0.04);
uniform vec3 sand_col : source_color = vec3(0.86, 0.79, 0.62);
uniform vec4 wakes[8];             // x, z, strength 0..1, radius
uniform vec4 fish[6];
uniform int debug_view = 0;          // dev: 1 clarity, 2 depth/10, 3 state rgb              // x, z, heading, length (0 = none)

#include "res://art/shaders/water_light.gdshaderinc"

varying vec3 wpos;
varying float swell_h;
varying float swell_k;
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

float fbm3(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.07 + 13.1) * 0.3 + vnoise(p * 4.3 + 7.7) * 0.15;
}

vec2 hex_round(vec2 qr) {
	vec3 c = vec3(qr.x, qr.y, -qr.x - qr.y);
	vec3 r = round(c);
	vec3 d = abs(r - c);
	if (d.x > d.y && d.x > d.z) { r.x = -r.y - r.z; } else if (d.y > d.z) { r.y = -r.x - r.z; }
	return r.xy;
}

vec2 to_axial(vec2 p) {
	return hex_round(vec2((SQRT3 / 3.0 * p.x - p.y / 3.0) / hex_size, (2.0 / 3.0 * p.y) / hex_size));
}

// Bed height and reef mask: the near map where it covers, else the far map.
vec2 bed(vec2 p) {
	vec2 un = p / near_size + 0.5;
	vec2 uf = p / far_size + 0.5;
	vec2 f = texture(far_tex, uf).rg;
	if (un.x > 0.02 && un.x < 0.98 && un.y > 0.02 && un.y < 0.98) {
		vec2 n = texture(near_tex, un).rg;
		float edge = smoothstep(0.38, 0.48, max(abs(un.x - 0.5), abs(un.y - 0.5)));
		return mix(n, f, edge);
	}
	return f;
}

// Three long swells (Gerstner-ish heights only; normals from the derivative).
vec3 swell(vec2 p, float amp) {
	vec2 d1 = normalize(vec2(0.8, 0.6));
	vec2 d2 = normalize(vec2(0.3, 0.95));
	vec2 d3 = normalize(vec2(-0.6, 0.8));
	float k1 = 0.09, k2 = 0.16, k3 = 0.27;
	float t = TIME;
	float a1 = amp, a2 = amp * 0.45, a3 = amp * 0.2;
	float ph1 = dot(p, d1) * k1 + t * sqrt(9.8 * k1);
	float ph2 = dot(p, d2) * k2 + t * sqrt(9.8 * k2) + 1.3;
	float ph3 = dot(p, d3) * k3 + t * sqrt(9.8 * k3) + 4.1;
	float h = a1 * sin(ph1) + a2 * sin(ph2) + a3 * sin(ph3);
	vec2 g = d1 * (a1 * k1 * cos(ph1)) + d2 * (a2 * k2 * cos(ph2)) + d3 * (a3 * k3 * cos(ph3));
	return vec3(h, g);
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float r = length(w.xz);
	float amp = mix(0.025, swell_amp, smoothstep(field_r, field_r + 80.0, r));
	vec3 s = swell(w.xz, amp);
	VERTEX.y += s.x;
	swell_h = s.x / max(amp, 0.001);
	swell_k = amp;
	NORMAL = normalize(vec3(-s.y, 1.0, -s.z));
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Cheap caustic web: a few rounds of domain warping on a sine lattice.
float caustic(vec2 p, float t) {
	vec2 q = p;
	float c = 0.0;
	for (int i = 0; i < 3; i++) {
		q += vec2(sin(q.y * 1.3 + t), cos(q.x * 1.1 - t * 0.8)) * 0.55;
		c += 1.0 / (1.0 + 18.0 * abs(sin(q.x) * sin(q.y)));
	}
	return pow(c / 3.0, 1.6);
}

void fragment() {
	vec2 p = wpos.xz;
	float r = length(p);
	float clarity = clamp(restore, 0.0, 1.0);
	float in_field = 0.0;
	vec4 st_dbg = vec4(0.0);
	float size = float(grid_radius * 2 + 1);
	// --- Play field: per-hex state (WaterView/FieldView state texture), natural borders.
	vec2 ax = to_axial(p);
	float hd0 = (abs(ax.x) + abs(ax.y) + abs(ax.x + ax.y)) * 0.5;
	if (warp_amp > 0.0 && hd0 <= float(grid_radius)
			&& texture(state_tex, (ax + vec2(float(grid_radius)) + 0.5) / size).a > 0.6) { discard; }  // yard slab
	vec2 pw = p + (warp_amp > 0.0 ? texture(warp_tex, p / warp_size + 0.5).rg * warp_amp : vec2(0.0));
	ax = to_axial(pw);
	float hd = (abs(ax.x) + abs(ax.y) + abs(ax.x + ax.y)) * 0.5;
	if (hd <= float(grid_radius)) {
		vec4 st = texture(state_tex, (ax + vec2(float(grid_radius)) + 0.5) / size);
		if (st.a < 0.4 || st.a > 0.6) { discard; }  // land hex: the ground shows
		in_field = 1.0;
		st_dbg = st;
		clarity = st.b > 0.5 ? 1.0 : st.r * 0.55;
		vec2 center = vec2(hex_size * (SQRT3 * ax.x + SQRT3 * 0.5 * ax.y), hex_size * 1.5 * ax.y);
		if (st.b > 0.5) {
			clarity = clamp(((time_now - st.g) * 6.0 - length(p - center)) / 3.0, 0.12, 1.0);
		}
		clarity = clamp(clarity + clarity_bonus * (st.b > 0.5 ? 1.0 : 0.4), 0.0, 1.0);
	} else {
		// Open sea: patches clear first near the field and the islands as the planet heals.
		float patchy = fbm3(p * 0.004 + 3.0);
		clarity = clamp(restore * 1.25 - patchy * 0.35 - smoothstep(200.0, 1400.0, r) * 0.15 * (1.0 - restore), 0.0, 1.0);
	}
	vec2 bd = bed(p);
	float depth = max(sea_y - bd.x, 0.02);
	float reef = bd.y;

	// --- Surface normal: swell + two scrolling detail layers + wakes.
	vec3 V = normalize(wpos - CAMERA_POSITION_WORLD);
	float cam_d = length(wpos - CAMERA_POSITION_WORLD);
	vec2 uv1 = p * 0.11 + vec2(TIME * 0.018, TIME * 0.011);
	vec2 uv2 = p * 0.19 - vec2(TIME * 0.014, -TIME * 0.009);
	vec3 dn = mix(texture(wave_nrm, uv1).rgb, texture(wave_nrm, uv2).rgb, 0.5);
	float oil = 0.0;
	// Oil slicks on dirty water: smooth dark film patches drifting slowly.
	float slick_n = fbm3(p * 0.045 + vec2(TIME * 0.004, -TIME * 0.003));
	oil = (1.0 - clarity) * smoothstep(0.5, 0.66, slick_n) * mix(0.6, 1.0, in_field);
	float foam = 0.0;
	vec2 ripple = vec2(0.0);
	for (int i = 0; i < 8; i++) {
		vec4 wk = wakes[i];
		if (wk.z <= 0.001) { continue; }
		vec2 dv = p - wk.xy;
		float dl = length(dv);
		if (dl > wk.w * 3.0) { continue; }
		float rad = wk.w;
		// A soft foam ring at the hover skirt, broken up by noise, and rings spreading out.
		float ring = smoothstep(rad * 0.45, rad * 0.8, dl) * (1.0 - smoothstep(rad * 0.85, rad * 1.25, dl));
		float brk = vnoise(dv * 3.0 + TIME * 2.0) * 0.6 + vnoise(dv * 7.0 - TIME * 3.0) * 0.4;
		foam += ring * smoothstep(0.3, 0.7, brk) * wk.z;
		float rings = sin(dl * 7.0 - TIME * 9.0) * exp(-dl / (rad * 1.4)) * wk.z;
		ripple += normalize(dv + 0.0001) * rings * 0.35;
		// The downwash darkens and smooths the water right under the hover ring.
		foam += (1.0 - smoothstep(0.0, rad * 0.5, dl)) * 0.12 * wk.z * brk;
	}
	float calm = mix(1.0, 0.25, oil);
	float nd = (0.55 - 0.25 * smoothstep(80.0, 600.0, cam_d)) * calm;

	// --- Seabed seen through the surface (refracted one-step parallax).
	vec3 rd = refract(V, vec3(0.0, 1.0, 0.0), 0.752);
	float tdn = max(-rd.y, 0.18);
	float L = depth / tdn;
	vec2 hit = p + rd.xz * L;
	float hdepth = max(sea_y - bed(hit).x, 0.02);
	vec3 bed_c = sand_col * (0.75 + 0.25 * fbm3(hit * 0.35));
	bed_c *= 1.0 + 0.08 * sin(dot(hit, vec2(0.9, 0.4)) * 3.0 + fbm3(hit * 0.2) * 6.0);  // sand ripples
	float rock = smoothstep(0.62, 0.72, fbm3(hit * 0.09 + 31.0));
	bed_c = mix(bed_c, vec3(0.32, 0.33, 0.3), rock * 0.8);
	// Dirty: silt and sunk junk shadows on the bed.
	bed_c = mix(bed_c, vec3(0.2, 0.2, 0.16), (1.0 - clarity) * 0.6);
	float life = clamp(restore * 1.4 - 0.2, 0.0, 1.0) * clarity;
	if (detail > 0.5) {
		// Coral on the reefs and the shallows round the islands.
		float cm = reef * smoothstep(5.5, 1.0, hdepth) * life;
		if (cm > 0.01) {
			float cn = fbm3(hit * 0.8);
			vec3 coral = mix(vec3(0.95, 0.45, 0.42), vec3(0.98, 0.72, 0.32), vnoise(hit * 0.3));
			coral = mix(coral, vec3(0.55, 0.42, 0.85), smoothstep(0.6, 0.8, vnoise(hit * 0.21 + 9.0)));
			bed_c = mix(bed_c, coral * (0.6 + 0.6 * cn), smoothstep(0.45, 0.6, cn) * cm);
		}
		// Caustics dance on the bed in clear, shallow water.
		float ca = caustic(hit * 0.55, TIME * 0.9);
		bed_c *= 1.0 + ca * 0.8 * clarity * exp(-hdepth * 0.22) * (1.0 - smoothstep(60.0, 180.0, cam_d));
		// Kelp beds in deeper water: a canopy layer of swaying dark fronds halfway up.
		if (life > 0.01 && hdepth > 2.2) {
			float kd = min(hdepth * 0.5, 4.0);
			vec2 kh = p + rd.xz * (kd / tdn);
			kh += vec2(sin(TIME * 0.6 + kh.y * 0.2), cos(TIME * 0.5 + kh.x * 0.2)) * 0.35;
			float kz = smoothstep(0.55, 0.72, fbm3(kh * 0.035 + 50.0)) * smoothstep(2.2, 4.0, hdepth) * (1.0 - reef);
			float fr = smoothstep(0.35, 0.75, vnoise(vec2(kh.x * 1.4, kh.y * 0.5)) * 0.6 + vnoise(kh * 2.5) * 0.4);
			bed_c = mix(bed_c, vec3(0.16, 0.22, 0.07) * (0.7 + 0.5 * fr), kz * fr * life * 0.9);
			L = mix(L, kd / tdn, kz * fr * life * 0.7);
		}
		// Big fish / whale shadows gliding over the bed.
		for (int i = 0; i < 6; i++) {
			vec4 f = fish[i];
			if (f.w <= 0.0) { continue; }
			vec2 q = hit - f.xy;
			float c = cos(f.z), s = sin(f.z);
			q = vec2(c * q.x + s * q.y, -s * q.x + c * q.y);
			float tail = 1.0 + 0.25 * sin(TIME * 2.0 + q.x * 0.4);
			float e = length(vec2(q.x / f.w, q.y / (f.w * 0.22 * tail)));
			float fin = length(vec2((q.x - f.w * 0.15) / (f.w * 0.18), abs(q.y) / (f.w * 0.55) - 0.6));
			float sh = (1.0 - smoothstep(0.7, 1.0, e)) + (1.0 - smoothstep(0.6, 1.0, fin)) * 0.6;
			bed_c *= 1.0 - clamp(sh, 0.0, 1.0) * 0.55 * clarity;
		}
	}

	// --- Water body: absorption along the path, scattering colour by depth.
	// Per-channel absorption: clear sea loses red first (turquoise shallows, blue depths).
	vec3 absorb = mix(vec3(1.9), vec3(0.42, 0.11, 0.08), clarity);
	vec3 T = exp(-absorb * L);
	vec3 body = mix(deep_col, shallow_col, exp(-hdepth * 0.28));
	body = mix(body, lagoon_col, exp(-hdepth * 1.1) * 0.6);
	vec3 murk = mix(murky_col, deep_col * 0.7 + vec3(0.05, 0.06, 0.06), smoothstep(40.0, 400.0, r) * (1.0 - in_field) * 0.8);
	body = mix(murk + vec3(0.03, 0.02, 0.0) * fbm3(p * 0.02), body, clarity);
	vec3 col = mix(body, bed_c, T) * 0.82;

	// Oil film: dark, glossy, with a faint thin-film rainbow at grazing angles.
	float fres = pow(1.0 - clamp(dot(-V, vec3(0.0, 1.0, 0.0)), 0.0, 1.0), 3.0);
	vec3 film = 0.5 + 0.5 * cos(6.2831 * (slick_n * 3.0 + fres * 1.2 + vec3(0.0, 0.33, 0.67)));
	vec3 oil_c = oil_col + film * 0.022 * (0.25 + fres);
	col = mix(col, oil_c, oil * 0.85);
	// Scum lines (bubbles and grime) where the slicks gather.
	float scum = (1.0 - clarity) * smoothstep(0.008, 0.0, abs(slick_n - 0.5)) * 0.22 * (1.0 - smoothstep(15.0, 60.0, cam_d)) * vnoise(p * 1.7);

	// --- Foam: shoreline bands, whitecaps on swell crests offshore.
	float shore = smoothstep(1.1, 0.05, depth);
	float bands = 0.5 + 0.5 * sin(depth * 9.0 - TIME * 1.6 + vnoise(p * 0.3) * 4.0);
	float fnoise = fbm3(p * 0.6 + vec2(TIME * 0.15, 0.0));
	foam += shore * smoothstep(0.45, 0.85, bands * 0.6 + fnoise * 0.6) * 0.8;
	foam += smoothstep(0.25, 0.0, depth) * 0.5 * fnoise;
	float cap = smoothstep(0.8, 1.0, swell_h) * smoothstep(0.6, 0.85, fnoise) * smoothstep(0.1, 0.3, swell_k);
	foam += cap * 0.55;
	foam += scum;
	foam = clamp(foam * (1.0 - oil * 0.7), 0.0, 1.0);
	vec3 foam_c = mix(vec3(0.94, 0.97, 0.98), vec3(0.62, 0.6, 0.52), (1.0 - clarity) * 0.6);
	col = mix(col, foam_c, foam);

	ALBEDO = col;
	if (debug_view == 1) { ALBEDO = vec3(0.0); EMISSION = vec3(clarity, st_dbg.b, st_dbg.r); }
	if (debug_view == 2) { ALBEDO = vec3(0.0); EMISSION = vec3(depth / 10.0, reef, clamp((time_now - st_dbg.g) / 200.0, 0.0, 1.0)); }
	ROUGHNESS = mix(mix(0.12, 0.035, clarity), 0.02, oil) + foam * 0.5;
	METALLIC = 0.0;
	SPECULAR = mix(0.55, 0.7, oil) * (1.0 - foam * 0.6);
	vec3 tn = normalize(vec3((dn.xy * 2.0 - 1.0) * nd + ripple, 1.0));
	NORMAL_MAP = tn * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
	// A faint cool lift in the future stage (clean lagoons glow a touch at dusk): thin, not neon.
	if (debug_view == 0) EMISSION = lagoon_col * 0.015 * future * exp(-hdepth * 0.6) * clarity;
}
