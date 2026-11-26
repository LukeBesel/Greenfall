shader_type spatial;
// One material for all procedural city buildings (planet/building_detail.gd): merged meshes of
// facades, roofs, parapets, cornices, balconies, fire escapes, awnings and rooftop props.
// Vertex data picks the look:
//   COLOR.rgb  tint            COLOR.a  kind / 16 (see BuildingDetail.K_*)
//   UV.x       bay-grid offset of this face, so windows line up with the building's corner
//   UV.y       metres above the foot of this wall (dirt and ivy from the ground up; 100 = not a wall)
//   UV2.x      metres below the top of this wall (staining from the top down; 100 = not a wall)
//   UV2.y      flag bits (BuildingDetail.F_*) + wall material * 256 (0 red brick, 1 pale brick,
//              2 stone / render, 3 composite panels, 4 dark alloy panels, 5 weathered metal sheet)
// Everything else (windows, shopfronts, roof membrane, gravel, solar cells) is procedural from
// world position, so one draw call covers a whole block.
// [art3] Windows are openings with depth: the view ray is carried into the wall, so each window
// shows its reveal (jamb, sill, soffit), a frame and dark glass that mirrors the sky, or a broken
// hole with a room behind it, a metal sheet or louvres. Walls weather from the top, under the
// sills and from the ground up, and ivy climbs some of them (dry in a dirty town, green in a clean one).
render_mode diffuse_burley, specular_schlick_ggx;
// [orbD] Site frame on a walkable globe (identity on the flat game): "world" maths run in the
// nearest hub site's local metres, y up on its pad (planet/sites/site_manager.gd).
global uniform mat4 site_inv;
// [v3city] Town outskirts on the globe (planet/sites/town_outskirts.gd): each tile's mesh is built
// in its own ground frame (y up there), so the maths run in object space instead.
uniform bool local_space = false;

uniform sampler2D tex_red_brick : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_brick : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_concrete : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm_brick : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm_concrete : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_roof : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_roof2 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

// [v6life] Streets wake up per block (planet/sites/town_life.gd): one texel per city block, R share
// of windows lit at dusk, G how clean the block is (grime fades, colour returns), B stage / 3
// (1: shop windows lit too). life_flat is used where there is no block map (the outskirts).
uniform sampler2D life_tex : filter_nearest;
uniform float life_on = 0.0;
uniform vec3 life_flat = vec3(0.0);
uniform float life_night = 0.0;

const float FLOOR_H = 3.0;
const float BAY = 3.0;

varying vec3 wp;
varying vec3 wn;
varying vec3 vray;  // [art3] camera to surface, in the space of wp
varying flat float v_salt;  // [art3] one whole number per building face (set per vertex, not interpolated)

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

// [art3] Nearest ivy leaf: x distance to its middle (0..~0.7 of a cell), y its own random number.
vec2 leaves(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float best = 9.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			float hh = h21(i + o);
			vec2 c = o + vec2(hh, fract(hh * 57.3)) - f;
			float d = dot(c, c);
			if (d < best) {
				best = d;
				id = fract(hh * 13.7);
			}
		}
	}
	return vec2(sqrt(best), id);
}

// Anti-aliased "inside [a, b]" for a cell coordinate.
float band(float x, float a, float b, float w) {
	return smoothstep(a - w, a + w, x) * (1.0 - smoothstep(b - w, b + w, x));
}

float lum(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void vertex() {
	vec3 camw = INV_VIEW_MATRIX[3].xyz;
	v_salt = mod(floor(UV.x * 7.3 + 0.37), 61.0);
	wp = (site_inv * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((site_inv * MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vray = wp - (site_inv * vec4(camw, 1.0)).xyz;
	if (local_space) {
		wp = VERTEX;
		wn = NORMAL;
		vec3 d = camw - MODEL_MATRIX[3].xyz;
		vec3 mx = MODEL_MATRIX[0].xyz;
		vec3 my = MODEL_MATRIX[1].xyz;
		vec3 mz = MODEL_MATRIX[2].xyz;
		vray = VERTEX - vec3(dot(mx, d) / dot(mx, mx), dot(my, d) / dot(my, my), dot(mz, d) / dot(mz, mz));
	}
	// Tangent frame matching the world-projected texture coordinates used below.
	if (abs(NORMAL.y) > 0.7) {
		TANGENT = vec3(1.0, 0.0, 0.0);
		BINORMAL = vec3(0.0, 0.0, 1.0);
	} else if (abs(NORMAL.x) > abs(NORMAL.z)) {
		TANGENT = vec3(0.0, 0.0, sign(NORMAL.x));
		BINORMAL = vec3(0.0, -1.0, 0.0);
	} else {
		TANGENT = vec3(-sign(NORMAL.z), 0.0, 0.0);
		BINORMAL = vec3(0.0, -1.0, 0.0);
	}
}

// [art3] The wall behind the windows. p in metres on the face; far 0..1 fades fine lines out
// (a seam under a pixel wide only shimmers).
vec3 wall_albedo(int id, vec2 p, vec3 tint, float far, out vec3 nm, out float rough, out float metal) {
	vec3 c;
	rough = 0.9;
	metal = 0.0;
	nm = vec3(0.5, 0.5, 1.0);
	if (id == 0) {
		c = texture(tex_red_brick, p * 0.85).rgb;
		c = mix(vec3(lum(c)), c, 0.8) * 0.84 * tint;  // [art3] real brick size; old brick, not fresh orange
		nm = texture(nrm_brick, p * 0.85).rgb;
	} else if (id == 1) {
		c = texture(tex_brick, p * 0.8).rgb;
		c = mix(vec3(lum(c)), c, 0.45) * 0.98 * tint;
		nm = texture(nrm_brick, p * 0.8).rgb;
	} else if (id == 2) {
		// Stone or render: coursed blocks with a pour line every 0.75 m, each block its own tone.
		c = texture(tex_concrete, p * 0.2).rgb;
		c = mix(vec3(lum(c)), c, 0.15) * 1.25 * tint;
		nm = texture(nrm_concrete, p * 0.2).rgb;
		vec2 q = vec2(p.x / 1.5, p.y / 0.75);
		q.x += 0.5 * mod(floor(q.y), 2.0);
		vec2 pw = fwidth(q) + vec2(0.006, 0.012);
		float joint = 1.0 - band(fract(q.x), 0.0, 1.0, pw.x) * band(fract(q.y), 0.0, 1.0, pw.y);
		c *= 1.0 - joint * 0.3 * (1.0 - far);
		c *= 0.9 + 0.2 * h21(floor(q));
	} else {
		// Cladding: composite panels (3), dark alloy panels (4) or standing-seam metal sheet (5).
		vec2 ps = id == 5 ? vec2(0.6, 3.0) : (id == 4 ? vec2(1.0, 1.5) : vec2(1.5, 1.0));
		vec2 q = p / ps;
		if (id == 3) {
			q.x += 0.5 * mod(floor(q.y), 2.0);
		}
		vec2 pid = floor(q);
		vec2 pf = fract(q);
		vec2 pw = fwidth(q) + vec2(0.006) / ps;
		float seam = 1.0 - band(pf.x, 0.0, 1.0, pw.x * 1.2) * band(pf.y, 0.0, 1.0, pw.y * 1.2);
		float hp = h21(pid + 17.3);
		float grain = lum(texture(tex_concrete, p * 0.37).rgb);
		c = tint * (0.9 + 0.2 * hp) * (0.72 + 0.6 * grain);
		// A few panels were swapped for primer-grey ones, a few have dropped off (dark substrate, rails).
		float odd = step(0.93, hp) * float(id != 5);
		c = mix(c, vec3(0.42, 0.43, 0.44) * (0.75 + 0.5 * grain), odd * 0.8);
		float gone = step(hp, 0.035) * float(id != 5);
		float rail = step(0.5, fract(pf.y * 3.0 + 0.25));
		c = mix(c, vec3(0.07, 0.065, 0.06) + vec3(0.1, 0.085, 0.07) * rail * (1.0 - far), gone);
		rough = mix(id == 3 ? 0.62 : 0.42, 0.78, hp * hp);
		metal = id == 3 ? 0.0 : (id == 4 ? 0.55 : 0.35);
		if (id == 5) {
			// Sheet metal: streaks down the sheet, rust blooming from the seams.
			float st = vnoise(vec2(p.x * 7.0, p.y * 0.35));
			c *= 0.82 + 0.3 * st;
			float rust = smoothstep(0.6, 0.9, vnoise(p * vec2(1.3, 0.5) + 31.0) * (0.8 + 0.5 * seam));
			c = mix(c, vec3(0.33, 0.17, 0.09) * (0.7 + 0.6 * grain), rust * 0.75);
			rough = mix(rough, 0.92, rust);
			metal *= 1.0 - rust;
		}
		c *= 1.0 - seam * 0.5 * (1.0 - far);
		rough = mix(rough, 0.95, max(seam * (1.0 - far), gone));
		metal *= 1.0 - gone;
		nm = mix(vec3(0.5, 0.5, 1.0), texture(nrm_concrete, p * 0.37).rgb, 0.35);
	}
	return c;
}

// [art3] A dark room seen through a hole: the ray carried on to the floor, the ceiling or the back wall.
vec3 room(vec2 f, vec2 slope, vec2 cs, float seedv) {
	vec2 g = f + slope * 2.6 / cs;
	vec3 c = vec3(0.028, 0.026, 0.024);
	c = mix(c, vec3(0.085, 0.075, 0.065), step(g.y, 0.04));  // dusty floor
	c = mix(c, vec3(0.045, 0.043, 0.04), step(0.9, g.y));   // ceiling
	c *= 0.6 + 0.8 * h21(vec2(seedv, 3.3));
	return c;
}

void fragment() {
	int kind = int(COLOR.a * 16.0);
	int flags = int(UV2.y + 0.5);
	int tex_id = (flags >> 8) & 7;
	vec3 tint = COLOR.rgb;
	vec3 n = normalize(wn);
	bool top = n.y > 0.7;
	bool side_x = abs(n.x) > abs(n.z);
	vec2 fp = top ? wp.xz : vec2((side_x ? wp.z : wp.x) + UV.x, wp.y);
	float h_base = UV.y;   // metres above the wall's foot
	float h_top = UV2.x;   // metres below the wall's top
	float dist = length(vray);
	vec2 fwp = fwidth(fp);
	float far = smoothstep(0.012, 0.06, max(fwp.x, fwp.y));  // 0 near .. 1 where a 3 cm line is under a pixel
	vec3 alb = tint;
	vec3 nm = vec3(0.5, 0.5, 1.0);
	float rough = 0.9;
	float metal = 0.0;
	float spec = 0.4;
	vec3 life = life_flat;  // [v6life]
	if (life_on > 0.5) {
		life = texture(life_tex, (floor(wp.xz / 36.0 + 0.5) + 8.5) / 16.0).rgb;
	}
	float dirty = 1.0 - 0.75 * life.g;
	vec3 emi = vec3(0.0);

	if (kind == 0 || kind == 1) {
		// Facade (with windows) or plain wall.
		alb = wall_albedo(tex_id, fp, tint, far, nm, rough, metal);
		// [art3] One whole number per building face. The hashes below only ever see whole numbers:
		// fed the interpolated UV itself they flipped from pixel to pixel (the old "dithered" windows).
		float salt = v_salt;
		float bh = h21(vec2(salt, 7.7));
		if (!top) {
			// Large soft patches and a mid speckle: no wall is one colour.
			alb *= mix(0.82 + 0.3 * vnoise(fp * vec2(0.35, 0.15)), 1.0, life.g * 0.6);
			alb *= 0.94 + 0.12 * vnoise(fp * 2.7 + 5.0);
		}
		vec3 wall = alb;
		float glass_m = 0.0;  // how much of this fragment is the window pane
		if (kind == 0 && !top) {
			bool shop = (flags & 1) != 0 && fp.y < FLOOR_H;
			bool ribbon = (flags & 2) != 0;
			bool curtain = (flags & 128) != 0;
			bool ruin = (flags & 2048) != 0;
			bool pairs = !shop && !ribbon && !curtain && bh < 0.38;
			vec2 cs = vec2(pairs ? BAY * 0.5 : BAY, FLOOR_H);
			vec2 cell = fp / cs;
			vec2 id = floor(cell);
			vec2 f = fract(cell);
			vec2 aa = fwidth(cell) * 0.75;
			float r = h21(id + salt);
			// The opening in the wall (cell units) and how deep the pane sits (metres).
			vec2 o0 = vec2(0.2, 0.27);
			vec2 o1 = vec2(0.8, 0.83);
			float depth = 0.32;
			if (shop) {
				o0 = vec2(0.07, 0.04);
				o1 = vec2(0.93, 0.72);
				depth = 0.45;
			} else if (curtain) {
				o0 = vec2(-1.0, 0.2);
				o1 = vec2(2.0, 0.97);
				depth = 0.1;
			} else if (ribbon) {
				o0 = vec2(-1.0, 0.4);
				o1 = vec2(2.0, 0.84);
				depth = 0.24;
			} else if (pairs) {
				o0 = vec2(0.24, 0.2);
				o1 = vec2(0.76, 0.86);
			} else if (bh > 0.72) {
				o0 = vec2(0.12, 0.3);
				o1 = vec2(0.88, 0.8);
			}
			// A ruined building has lost whole bays of its skin: the frame and the rooms show.
			float blown = 0.0;
			if (ruin && !shop && h21(floor(cell / vec2(pairs ? 2.0 : 1.0, 1.0)) * 0.37 + salt + 2.0) < 0.2) {
				o0 = vec2(pairs ? -1.0 : 0.07, 0.1);
				o1 = vec2(pairs ? 2.0 : 0.93, 0.98);
				depth = 0.5;
				blown = 1.0;
			}
			if (fp.y < FLOOR_H && !shop && !ribbon && !curtain && h21(id + 7.0) < 0.4) {
				o1 = o0;  // some ground-floor bays are blank wall
			}
			// The view ray carried `depth` into the wall.
			vec3 e = normalize(vray);
			vec3 tng = side_x ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
			vec2 slope = vec2(dot(e, tng), e.y) / max(-dot(e, n), 0.22);
			vec2 f2 = f + slope * depth / cs;
			float open_m = band(f.x, o0.x, o1.x, aa.x) * band(f.y, o0.y, o1.y, aa.y);
			float pane = band(f2.x, o0.x, o1.x, aa.x) * band(f2.y, o0.y, o1.y, aa.y);
			glass_m = open_m * pane;
			float reveal = open_m * (1.0 - pane);
			// Reveal: soffit in shade, jambs half lit, the sill's top dusty and bright.
			float rs = f2.y > o1.y ? 0.36 : (f2.y < o0.y ? 1.0 : 0.6);
			vec3 rev = wall * rs;
			if (f2.y < o0.y) {
				rev = mix(rev, vec3(0.5, 0.47, 0.42), 0.45 * dirty);
			}
			alb = mix(alb, rev, reveal);
			// Stone sill (a pale lip with its shadow under it) and a lintel over the head.
			vec2 px = vec2(0.03, 0.03) / cs;
			float in_x = band(f.x, o0.x - px.x * 2.0, o1.x + px.x * 2.0, aa.x) * (1.0 - blown);
			float sill = in_x * band(f.y, o0.y - px.y * 3.0, o0.y, aa.y);
			float sill_sh = in_x * band(f.y, o0.y - px.y * 6.0, o0.y - px.y * 3.0, aa.y);
			float lintel = in_x * band(f.y, o1.y, o1.y + px.y * (tex_id <= 2 ? 6.0 : 2.0), aa.y) * float(!curtain);
			vec3 trim_c = mix(wall, vec3(0.6, 0.58, 0.54), 0.7) * (0.85 + 0.25 * vnoise(fp * 5.0));
			float trim_m = max(sill, lintel) * (1.0 - open_m);
			alb = mix(alb, trim_c, trim_m);
			alb *= 1.0 - 0.45 * sill_sh * (1.0 - open_m) * (1.0 - sill);
			// The pane plane: frame, mullions, then what fills the hole.
			vec2 span = o1 - o0;
			vec2 u = (f2 - o0) / span;  // 0..1 over the opening
			float strip = 0.0;
			if (ribbon || curtain) {
				float k = curtain ? 2.0 : 3.0;
				strip = floor(f2.x * k);
				u.x = fract(f2.x * k);
				span.x = 1.0 / k;
			}
			vec2 um = u * span * cs;  // metres from the opening's corner
			vec2 sm = span * cs;
			vec2 aam = aa * cs;
			float fw = shop ? 0.08 : 0.06;
			float inner = band(um.x, fw, sm.x - fw, aam.x) * band(um.y, fw, sm.y - fw, aam.y);
			float mull = 0.0;
			bool cross = !ribbon && !curtain && !shop && sm.x > 1.2;
			if (cross) {
				mull = 1.0 - smoothstep(0.02, 0.03 + aam.x, abs(um.x - sm.x * 0.5));
			}
			float bar_y = sm.y * (curtain ? 0.35 : 0.62);
			if (!shop) {
				mull = max(mull, 1.0 - smoothstep(0.018, 0.028 + aam.y, abs(um.y - bar_y)));
			}
			float frame_m = max(1.0 - inner, mull * inner) * (1.0 - blown);
			vec3 frame_c = h21(vec2(bh, 5.0)) < 0.55 ? vec3(0.085, 0.09, 0.095) : vec3(0.5, 0.49, 0.45);
			// Per pane.
			vec2 pid = id * 4.0 + vec2((cross ? step(sm.x * 0.5, um.x) : 0.0) + strip * 0.37, step(bar_y, um.y));
			float hpn = h21(pid + salt + 1.3);
			// Glass: dark, mirror-like, dust settled low on the pane; each pane tilts a little.
			vec3 g = mix(vec3(0.23, 0.28, 0.33), vec3(0.34, 0.36, 0.33), hpn);
			float gr = 0.06;
			float gm = 0.82;
			vec3 gn = vec3(0.5 + (h21(pid + 1.7) - 0.5) * 0.09, 0.5 + (h21(pid + 2.9) - 0.5) * 0.07, 1.0);
			float dust = (1.0 - smoothstep(0.0, 0.9, u.y)) * (0.35 + 0.65 * vnoise(um * 3.0 + id * 3.1)) * dirty;
			dust = max(dust, smoothstep(0.55, 0.9, vnoise(um * 1.3 + id * 5.7)) * 0.55 * dirty);
			g = mix(g, vec3(0.36, 0.34, 0.3), dust * 0.75);
			gr = mix(gr, 0.55, dust);
			gm = mix(gm, 0.15, dust);
			float alive = 1.0;  // can light up at night
			float rr = ruin ? r * 0.55 : r;
			if (shop) {
				// Shopfront: some bays have a roller shutter down.
				float shutter = step(0.62, r);
				vec3 sl = vec3(0.34, 0.35, 0.35) * (0.72 + 0.28 * step(0.45, fract(um.y / 0.11))) * (0.85 + 0.3 * vnoise(um * vec2(0.6, 4.0) + id));
				sl = mix(sl, vec3(0.3, 0.17, 0.1), smoothstep(0.55, 0.8, vnoise(um * vec2(1.5, 0.6) + id * 9.0)) * 0.6);
				g = mix(g, sl, shutter);
				gr = mix(gr, 0.7, shutter);
				gm = mix(gm, 0.3, shutter);
				gn = mix(gn, vec3(0.5, 0.5, 1.0), shutter);
				alive = 1.0 - shutter;
			} else if (blown > 0.5) {
				g = room(f, slope, cs, r);
				// The frame of the building: a slab edge in the gap.
				g = mix(g, wall * 0.55, 1.0 - smoothstep(0.05, 0.07 + aa.y, u.y));
				gr = 1.0;
				gm = 0.0;
				gn = vec3(0.5, 0.5, 1.0);
				alive = 0.0;
			} else if (rr < 0.17) {
				// Broken: shards cling to the frame, the room behind is dark.
				float ed = min(min(um.x, sm.x - um.x), min(um.y, sm.y - um.y));
				float hole = smoothstep(-0.03, 0.03, ed - 0.04 - 0.5 * vnoise(um * 3.1 + id * 7.0) * (0.4 + r * 4.0));
				g = mix(g, room(f, slope, cs, r), hole);
				gr = mix(gr, 1.0, hole);
				gm *= 1.0 - hole;
				alive = 0.0;
			} else if (rr < 0.3) {
				// Boarded or sheeted over: weathered planks on old walls, metal plate on new ones.
				bool planks = tex_id <= 1;
				float lines = planks ? fract(um.x / 0.22) : fract(um.y / (sm.y * 0.5));
				float gap = 1.0 - band(lines, 0.04, 0.96, planks ? aam.x / 0.22 + 0.01 : aam.y / sm.y * 2.0 + 0.005);
				vec3 pl = vec3(0.36, 0.28, 0.2) * (0.7 + 0.5 * h21(vec2(floor(um.x / 0.22), id.x + id.y * 7.0))) * (0.8 + 0.3 * vnoise(um * vec2(9.0, 1.2)));
				vec3 sh = mix(vec3(0.33, 0.33, 0.32), vec3(0.26, 0.29, 0.31), h21(id + 9.0)) * (0.8 + 0.4 * vnoise(um * 2.2 + id));
				sh = mix(sh, vec3(0.34, 0.18, 0.1), smoothstep(0.45, 0.8, vnoise(um * vec2(2.5, 0.9) + id * 3.0)) * 0.7);
				g = planks ? pl : sh;
				g *= 1.0 - gap * 0.55 * (1.0 - far);
				gr = planks ? 0.92 : 0.75;
				gm = planks ? 0.0 : 0.25;
				gn = vec3(0.5, 0.5, 1.0);
				alive = 0.0;
			} else if (rr > 0.88) {
				// Louvred shutters closed.
				float slat = fract(um.y / 0.09);
				g = mix(vec3(0.3, 0.36, 0.33), vec3(0.4, 0.38, 0.33), h21(vec2(bh, 9.1))) * mix(1.0, 0.62 + 0.5 * slat, 1.0 - far) * (0.85 + 0.25 * hpn);
				gr = 0.7;
				gm = 0.0;
				gn = vec3(0.5, 0.5, 1.0);
				alive = 0.5;
			}
			// The head of the reveal shades the top of the pane.
			g *= mix(0.55, 1.0, smoothstep(0.0, 0.14, 1.0 - u.y));
			g = mix(g, frame_c, frame_m);
			gr = mix(gr, 0.5, frame_m);
			gm = mix(gm, 0.3, frame_m);
			if (shop) {
				// The sign band: a painted board, faded and peeling.
				float sign_b = band(f.x, 0.03, 0.97, aa.x) * band(f.y, 0.78, 0.94, aa.y);
				vec3 sign_c = mix(vec3(0.12, 0.17, 0.2), vec3(0.34, 0.13, 0.1), step(0.5, h21(id + 3.1)));
				sign_c = mix(sign_c, vec3(0.5, 0.46, 0.36), step(0.75, h21(id + 5.7)));
				sign_c = mix(sign_c, wall * 0.7, smoothstep(0.45, 0.75, vnoise(fp * vec2(2.0, 6.0))) * 0.7 * dirty);
				alb = mix(alb, sign_c, sign_b);
				// [v6life] An awake, planted block: the open shops are lit inside and their sign bands glow.
				float open_k = smoothstep(0.8, 1.0, life.b) * life_night;
				emi += vec3(1.0, 0.8, 0.52) * glass_m * alive * (1.0 - frame_m) * open_k * (0.55 + 0.35 * smoothstep(0.1, 0.6, f.y));
				emi += sign_c * 2.0 * sign_b * open_k * 0.5;
			} else {
				// [v6life] Windows glow at dusk, more of them as the block wakes (each has its own
				// threshold, so they come on one by one); broken and boarded ones stay dark.
				float lit = step(1.0 - life.r, h21(id + 11.0 + salt)) * alive * life_night;
				vec3 wc = mix(vec3(1.0, 0.72, 0.36), vec3(0.75, 0.86, 1.0), step(0.86, h21(id + 4.4)));
				emi += wc * glass_m * (1.0 - frame_m) * lit * (0.75 + 0.25 * smoothstep(0.0, 0.3, 1.0 - u.y));
				g = mix(g, g * 0.3, lit * (1.0 - frame_m));
				gm *= 1.0 - 0.7 * lit;
			}
			alb = mix(alb, g, glass_m);
			rough = mix(rough, gr, glass_m);
			metal = mix(metal, gm, glass_m);
			spec = mix(spec, 0.7, glass_m);
			nm = mix(nm, gn, max(glass_m, reveal));
			// Streaks under the sill: strongest at its ends, washing out a floor down.
			float below = (o0.y - f.y) * FLOOR_H;
			float col = vnoise(vec2(fp.x * 11.0, id.y * 3.0 + 1.0));
			float ends = max(1.0 - smoothstep(0.0, 0.08, abs(f.x - o0.x)), 1.0 - smoothstep(0.0, 0.08, abs(f.x - o1.x)));
			float streak = band(f.x, o0.x - 0.02, o1.x + 0.02, aa.x + 0.01) * step(0.0, below) * exp(-below * 1.6) * (0.25 + 0.75 * col) * (0.5 + 0.9 * ends);
			streak *= (0.3 + 0.7 * h21(id + 3.0)) * dirty * (1.0 - open_m) * (1.0 - sill) * float(o1.x > o0.x);
			alb *= 1.0 - 0.5 * min(streak, 1.0);
			rough = mix(rough, 0.95, min(streak, 1.0) * 0.6);
			// A shadow line at each floor (slab edge) on masonry.
			if (tex_id <= 2 && !curtain) {
				alb *= 1.0 - (1.0 - smoothstep(0.0, aa.y * 2.0 + 0.012, abs(f.y - 0.012))) * 0.2 * (1.0 - glass_m);
			}
		}
		if (!top) {
			float keep = 1.0 - glass_m;
			// Rain has run down from the parapet for a lifetime: long dark tongues, short pale ones.
			float c1 = vnoise(vec2(fp.x * 1.3, 3.0));
			float c2 = vnoise(vec2(fp.x * 6.5, 9.0));
			float run = (1.0 - smoothstep(0.0, 0.6 + 7.0 * c1 * c1, h_top)) * (0.45 + 0.55 * c2);
			run += (1.0 - smoothstep(0.0, 0.35, h_top)) * 0.5;
			run = min(run, 1.0) * dirty * keep;
			alb = mix(alb, alb * vec3(0.5, 0.49, 0.44), run * 0.75);
			// Dirt climbs from the ground (and from every ledge a wall stands on).
			float gh = 0.5 + 2.6 * vnoise(vec2(fp.x * 0.7, 1.0));
			float grime = (1.0 - smoothstep(0.0, gh, h_base)) * dirty;
			grime = max(grime, (1.0 - smoothstep(0.0, 0.3, h_base)) * 0.9 * dirty);
			alb = mix(alb, vec3(0.17, 0.14, 0.11) * (0.7 + 0.6 * c2), grime * 0.6 * mix(1.0, 0.45, glass_m));
			rough = mix(rough, 0.97, max(run, grime) * 0.7);
			metal *= 1.0 - 0.7 * grime;
			// Ivy: climbs from the foot of some walls and hangs over some parapets. Mostly dry and
			// brown-green in a dirty town; a clean block's ivy is in leaf.
			if (tex_id <= 2 && h_base < 99.0) {
				float wall_k = h21(vec2(salt, 3.1));
				float reach = 1.0 + 13.0 * smoothstep(0.42, 0.9, vnoise(vec2(fp.x * 0.16, 5.0 + wall_k * 9.0))) * step(0.45, wall_k);
				float body = vnoise(fp * 0.4 + 13.0) * 0.7 + vnoise(fp * 1.9 + 3.0) * 0.3;
				float iv = (1.0 - smoothstep(reach * 0.45, reach, h_base)) * smoothstep(0.38, 0.56, body);
				float hang = 0.6 + 3.2 * vnoise(vec2(fp.x * 0.45, 8.0)) * step(0.5, fract(wall_k * 7.0));
				iv = max(iv, (1.0 - smoothstep(hang * 0.5, hang, h_top)) * smoothstep(0.42, 0.56, vnoise(vec2(fp.x * 0.3, 21.0 + wall_k))));
				if (iv > 0.02) {
					// Leaf by leaf up close (each its own green, darker at its edge); a soft mass far off.
					vec2 lf = leaves(fp * 7.0);
					float lmix = 1.0 - smoothstep(25.0, 70.0, dist);
					// A solid mass with a leafy edge (thinned leaf by leaf everywhere, it read as a veil).
					iv = smoothstep(0.25, 0.5, iv);
					iv = smoothstep(0.42, 0.58, iv + (0.38 - lf.x) * 0.55 * lmix);
					float tone = mix(0.5, lf.y, lmix);
					vec3 green = mix(vec3(0.06, 0.11, 0.035), vec3(0.2, 0.29, 0.085), tone);
					vec3 dry = mix(vec3(0.2, 0.16, 0.07), vec3(0.4, 0.32, 0.13), tone);
					float dead = smoothstep(0.45, 0.8, vnoise(fp * 0.25 + 40.0)) * (0.6 - 0.6 * life.g) + step(0.93, lf.y) * 0.6 * lmix;
					vec3 ivc = mix(green, dry, clamp(dead, 0.0, 1.0));
					ivc *= mix(1.0, 0.68, smoothstep(0.15, 0.5, lf.x) * lmix);
					alb = mix(alb, ivc, iv);
					rough = mix(rough, 0.8, iv);
					metal *= 1.0 - iv;
					emi *= 1.0 - iv * 0.8;
					nm = mix(nm, vec3(0.5 + (lf.y - 0.5) * 0.4 * lmix, 0.5 + (fract(lf.y * 7.0) - 0.5) * 0.4 * lmix, 1.0), iv);
				}
			}
		}
	} else if (kind == 2) {
		// Roof membrane: tar or gravel ballast with seams, patches and ponding stains.
		vec2 p = wp.xz;
		vec3 a = (flags & 4) != 0 ? texture(tex_roof2, p * 0.12).rgb : texture(tex_roof, p * 0.16).rgb;
		a = vec3(lum(a)) * 2.0;
		float big = vnoise(p * 0.22);
		float patch = step(0.72, vnoise(floor(p * 0.5) * 0.71 + 2.0));
		a *= mix(0.8, 1.08, big);
		a *= 1.0 - patch * 0.18;
		vec2 fw = fwidth(p);
		float fade = 1.0 - smoothstep(0.02, 0.08, max(fw.x, fw.y));
		float speck = (h21(floor(p * 22.0)) - 0.5) * 0.35 * fade;
		a *= 1.0 + speck;
		float seam_w = max(fw.x * 1.5, 0.015);
		float ln = band(fract(((flags & 8) != 0 ? p.x : p.y) * 0.9), 0.49, 0.51, seam_w);
		a *= 1.0 - ln * 0.22 * (1.0 - step(0.5, float(flags & 4)));
		float pv = vnoise(p * 0.3 + 11.0);
		float pond = smoothstep(0.55, 0.7, pv) * (1.0 - smoothstep(0.7, 0.85, pv));
		a *= 1.0 - pond * 0.4;
		alb = a * tint;
		// Moss and silt where water stood.
		alb = mix(alb, vec3(0.2, 0.21, 0.13), smoothstep(0.6, 0.85, pv) * 0.5 * dirty);
		rough = 0.95;
		spec = 0.3;
	} else if (kind == 3) {
		// Painted / galvanised metal: streaked, chalky paint, rust creeping from the top edge and the foot.
		float nz = vnoise(fp * 3.0 + wp.y);
		alb = tint * (0.8 + 0.3 * nz) * (0.85 + 0.3 * vnoise(vec2(fp.x * 9.0, fp.y * 0.6)));
		if ((flags & 16) != 0) {
			float hoop = band(fract(wp.y / 0.55), 0.45, 0.55, fwidth(wp.y / 0.55) + 0.01);
			alb *= 1.0 - hoop * 0.5;
		}
		if ((flags & 4096) != 0 && !top) {
			// Louvred plant screen.
			float sl = fract(fp.y / 0.22);
			alb *= mix(1.0, 0.45 + 0.75 * sl, 1.0 - far);
		}
		float rust = smoothstep(0.55, 0.85, vnoise(fp * 1.7 + 4.0)) * 0.6 * float((flags & 32) != 0);
		rust = max(rust, (1.0 - smoothstep(0.0, 0.25 + 0.5 * nz, min(h_base, h_top))) * 0.55);
		rust *= dirty;
		alb = mix(alb, vec3(0.3, 0.16, 0.09) * (0.7 + 0.6 * nz), rust);
		rough = mix(0.5, 0.9, rust);
		metal = 0.45 * (1.0 - rust);
	} else if (kind == 4) {
		// Solar skin: dark blue cells in a silver frame, on roofs and as wall cladding; dust-dulled.
		vec2 c = (top ? wp.xz : fp) / 0.55;
		vec2 aa2 = fwidth(c);
		float cell = band(fract(c.x), 0.06, 0.94, aa2.x) * band(fract(c.y), 0.06, 0.94, aa2.y);
		float hc = h21(floor(c));
		alb = mix(vec3(0.4, 0.41, 0.42), vec3(0.03, 0.05, 0.11) * (0.8 + 0.5 * hc), cell);
		alb = mix(alb, vec3(0.02), step(0.93, hc) * cell);  // dead cells
		float dust2 = vnoise(c * 0.35 + 3.0) * dirty;
		alb = mix(alb, vec3(0.33, 0.3, 0.26), dust2 * 0.45);
		rough = mix(mix(0.4, 0.1, cell), 0.7, dust2);
		metal = 0.5 * cell * (1.0 - dust2);
		spec = 0.7;
	} else if (kind == 5) {
		// Dry planter soil with leaf litter.
		alb = tint * (0.7 + 0.5 * vnoise(wp.xz * 9.0)) * (0.85 + 0.3 * h21(floor(wp.xz * 30.0)));
		rough = 1.0;
	} else if (kind == 6) {
		// Flat colour (fabric, plastic, wood, dead plants); optional awning stripes, sun-faded.
		alb = tint * (0.8 + 0.3 * vnoise(fp * 4.0));
		if ((flags & 64) != 0) {
			float s = step(0.5, fract(fp.x / 0.5));
			alb = mix(alb, vec3(0.62, 0.6, 0.54), s * 0.7);
		}
		alb = mix(alb, vec3(lum(alb)) * vec3(1.0, 0.97, 0.9), 0.3 * dirty);
		alb *= 1.0 - 0.35 * smoothstep(0.5, 0.85, vnoise(fp * 1.6 + 8.0)) * dirty;
		rough = 0.85;
	} else if (kind == 7) {
		// Coping / cornice: cast stone, weathered grey with dark runs from its top.
		vec3 c = texture(tex_concrete, fp * 0.3).rgb;
		alb = vec3(lum(c)) * 1.25 * tint;
		nm = texture(nrm_concrete, fp * 0.3).rgb;
		if (!top) {
			float c2 = vnoise(vec2(fp.x * 5.0, 2.0));
			alb *= 1.0 - (0.2 + 0.4 * c2) * (1.0 - smoothstep(0.0, 0.5, h_top)) * dirty;
			alb *= 1.0 - 0.3 * (1.0 - smoothstep(0.0, 0.08, h_base));
		} else {
			alb *= 0.8 + 0.25 * vnoise(wp.xz * 1.3);
		}
		rough = 0.88;
	} else if (kind == 8) {
		alb = tint;
		rough = 0.8;
	} else if (kind == 10) {
		// [art3] A lamp or beacon lens (masts, rooftop plant): glows after dark.
		alb = tint * 0.5;
		emi = tint * (0.25 + 2.4 * life_night);
		rough = 0.3;
	} else {
		// Skylight glass.
		alb = vec3(0.2, 0.25, 0.3) + tint * 0.05;
		rough = 0.12;
		metal = 0.7;
		spec = 0.7;
	}
	// [v6life] A clean block gets its colour back (facades, awnings, roofs a little).
	alb = mix(alb, mix(vec3(lum(alb)), alb, 1.3) * 1.07, life.g * (kind == 2 ? 0.3 : 0.85));
	ALBEDO = clamp(alb, 0.0, 1.0);
	EMISSION = emi;
	NORMAL_MAP = nm;
	// [art3] The wall's relief fades out with distance: far off it only made the walls sparkle.
	NORMAL_MAP_DEPTH = 0.8 * (1.0 - smoothstep(60.0, 180.0, dist));
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
}
