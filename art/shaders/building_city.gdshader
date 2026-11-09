shader_type spatial;
// One material for all procedural city buildings (planet/building_detail.gd): merged meshes of
// facades, roofs, parapets, cornices, balconies, fire escapes, awnings and rooftop props.
// Vertex data picks the look:
//   COLOR.rgb  tint            COLOR.a  kind / 16 (see BuildingDetail.K_*)
//   UV         bay-grid offsets so windows line up with each building's corner (x faces, z faces)
//   UV2.x      wall texture (0 red brick, 1 pale brick, 2 concrete)   UV2.y  flag bits
// Everything else (windows, shopfronts, roof membrane, gravel, solar cells) is procedural from
// world position, so one draw call covers a whole block.
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

const float FLOOR_H = 3.0;
const float BAY = 3.0;

varying vec3 wp;
varying vec3 wn;

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

// Anti-aliased "inside [a, b]" for a cell coordinate.
float band(float x, float a, float b, float w) {
	return smoothstep(a - w, a + w, x) * (1.0 - smoothstep(b - w, b + w, x));
}

float lum(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void vertex() {
	wp = (site_inv * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((site_inv * MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (local_space) {
		wp = VERTEX;
		wn = NORMAL;
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

vec3 wall_albedo(int id, vec2 p, out vec3 nm) {
	vec3 c;
	if (id == 0) {
		c = texture(tex_red_brick, p * 0.25).rgb * 1.08;
		nm = texture(nrm_brick, p * 0.25).rgb;
	} else if (id == 1) {
		c = texture(tex_brick, p * 0.25).rgb;
		c = mix(vec3(lum(c)), c, 0.35) * 1.3;
		nm = texture(nrm_brick, p * 0.25).rgb;
	} else {
		c = texture(tex_concrete, p * 0.2).rgb;
		c = mix(vec3(lum(c)), c, 0.12) * 1.45;
		nm = texture(nrm_concrete, p * 0.2).rgb;
	}
	return c;
}

void fragment() {
	int kind = int(COLOR.a * 16.0);
	int flags = int(UV2.y + 0.5);
	int tex_id = int(UV2.x + 0.5);
	vec3 tint = COLOR.rgb;
	vec3 n = normalize(wn);
	bool top = n.y > 0.7;
	bool side_x = abs(n.x) > abs(n.z);
	vec2 fp = top ? wp.xz : vec2(side_x ? wp.z + UV.y : wp.x + UV.x, wp.y);
	vec3 alb = tint;
	vec3 nm = vec3(0.5, 0.5, 1.0);
	float rough = 0.9;
	float metal = 0.0;
	float spec = 0.4;

	if (kind == 0 || kind == 1) {
		// Facade (with windows) or plain wall.
		alb = wall_albedo(tex_id, fp, nm) * tint;
		if (kind == 0 && !top) {
			vec2 cell = vec2(fp.x / BAY, fp.y / FLOOR_H);
			vec2 id = floor(cell);
			vec2 f = fract(cell);
			vec2 aa = fwidth(cell) * 0.75;
			float r = h21(id + vec2(UV.x, UV.y) * 0.013);
			bool shop = (flags & 1) != 0 && id.y < 0.5;
			bool ribbon = (flags & 2) != 0;
			vec3 frame = mix(alb, vec3(0.86, 0.84, 0.8), 0.55);
			if (shop) {
				// Shopfront: wide dark glass between pilasters, a painted sign band, some shutters.
				float glass = band(f.x, 0.07, 0.93, aa.x) * band(f.y, 0.04, 0.7, aa.y);
				float sign_b = band(f.x, 0.03, 0.97, aa.x) * band(f.y, 0.76, 0.93, aa.y);
				vec3 sign_c = mix(vec3(0.16, 0.2, 0.26), vec3(0.62, 0.22, 0.16), step(0.5, h21(id + 3.1)));
				sign_c = mix(sign_c, vec3(0.86, 0.8, 0.66), step(0.75, h21(id + 5.7)));
				vec3 g = vec3(0.02, 0.025, 0.03);
				float shutter = step(0.7, r);
				g = mix(g, vec3(0.42, 0.42, 0.4) * (0.8 + 0.2 * step(0.5, fract(f.y * 18.0))), shutter);
				alb = mix(alb, frame * 0.7, band(f.x, 0.05, 0.95, aa.x) * band(f.y, 0.02, 0.72, aa.y));
				alb = mix(alb, g, glass);
				alb = mix(alb, sign_c, sign_b);
				rough = mix(rough, mix(0.08, 0.6, shutter), glass);
				spec = mix(spec, 0.6, glass * (1.0 - shutter));
			} else {
				float wx0 = ribbon ? 0.03 : 0.24;
				float wx1 = ribbon ? 0.97 : 0.76;
				float wy0 = ribbon ? 0.42 : 0.26;
				float wy1 = ribbon ? 0.84 : 0.8;
				float win = band(f.x, wx0, wx1, aa.x) * band(f.y, wy0, wy1, aa.y);
				if (id.y < 0.5 && !ribbon) {
					win *= step(0.4, h21(id + 7.0));
				}
				float sill = band(f.x, wx0 - 0.03, wx1 + 0.03, aa.x) * band(f.y, wy0 - 0.05, wy0, aa.y);
				float lintel = band(f.x, wx0 - 0.02, wx1 + 0.02, aa.x) * band(f.y, wy1, wy1 + 0.04, aa.y);
				alb = mix(alb, frame, max(sill, lintel * 0.6));
				// Glass: reflective dark, some with pale curtains, a few boarded or blown out.
				vec3 g = mix(vec3(0.045, 0.055, 0.07), vec3(0.11, 0.13, 0.16), h21(id + 1.3));
				float gr = 0.08;
				if (r > 0.8) {
					g = mix(vec3(0.55, 0.5, 0.42), vec3(0.42, 0.44, 0.48), h21(id + 9.0));
					gr = 0.5;
				} else if (r < 0.08) {
					g = vec3(0.4, 0.31, 0.21) * (0.85 + 0.3 * vnoise(fp * 6.0));
					gr = 0.9;
				} else if (r < 0.13) {
					g = vec3(0.012);
					gr = 1.0;
				}
				if (ribbon) {
					float mull = 1.0 - band(fract(f.x * 4.0), 0.06, 0.94, aa.x * 4.0);
					g = mix(g, vec3(0.22, 0.23, 0.24), mull);
				}
				// Reveal shadow under the lintel.
				g *= mix(0.5, 1.0, smoothstep(0.0, 0.12, wy1 - f.y));
				alb = mix(alb, g, win);
				rough = mix(rough, gr, win);
				spec = mix(spec, 0.65, win * step(gr, 0.2));
				// Grime streaks under windows.
				float streak = band(f.x, wx0 + 0.04, wx1 - 0.04, aa.x) * (1.0 - smoothstep(0.0, 0.26, f.y)) * 0.3 * h21(id + 3.0);
				alb *= 1.0 - streak * (1.0 - win);
			}
			// Floor band and darker toward the street.
			alb *= 1.0 - (1.0 - smoothstep(0.0, aa.y * 2.0 + 0.02, abs(f.y - 0.01))) * 0.25;
		}
		if (!top) {
			alb *= mix(0.72, 1.0, smoothstep(0.0, 5.0, wp.y));
			// Weathering: large soft stains.
			alb *= 0.9 + 0.14 * vnoise(fp * vec2(0.35, 0.15));
		}
	} else if (kind == 2) {
		// Roof membrane: tar or gravel ballast with seams, patches and ponding stains.
		vec2 p = wp.xz;
		vec3 a = (flags & 4) != 0 ? texture(tex_roof2, p * 0.12).rgb : texture(tex_roof, p * 0.16).rgb;
		a = vec3(lum(a)) * 2.0;
		float big = vnoise(p * 0.22);
		float patch = step(0.72, vnoise(floor(p * 0.5) * 0.71 + 2.0));
		a *= mix(0.86, 1.08, big);
		a *= 1.0 - patch * 0.18;
		vec2 fw = fwidth(p);
		float fade = 1.0 - smoothstep(0.02, 0.08, max(fw.x, fw.y));
		float speck = (h21(floor(p * 22.0)) - 0.5) * 0.35 * fade;
		a *= 1.0 + speck;
		float seam_w = max(fw.x * 1.5, 0.015);
		float ln = band(fract(((flags & 8) != 0 ? p.x : p.y) * 0.9), 0.49, 0.51, seam_w);
		a *= 1.0 - ln * 0.22 * (1.0 - step(0.5, float(flags & 4)));
		float pond = smoothstep(0.62, 0.7, vnoise(p * 0.3 + 11.0)) * (1.0 - smoothstep(0.7, 0.8, vnoise(p * 0.3 + 11.0)));
		a *= 1.0 - pond * 0.25;
		alb = a * tint;
		rough = 0.95;
		spec = 0.3;
	} else if (kind == 3) {
		// Painted / galvanised metal with a little rust.
		float nz = vnoise(fp * 3.0 + wp.y);
		alb = tint * (0.9 + 0.15 * nz);
		if ((flags & 16) != 0) {
			float hoop = band(fract(wp.y / 0.55), 0.45, 0.55, fwidth(wp.y / 0.55) + 0.01);
			alb *= 1.0 - hoop * 0.5;
		}
		float rust = smoothstep(0.55, 0.85, vnoise(fp * 1.7 + 4.0)) * 0.6;
		alb = mix(alb, vec3(0.36, 0.2, 0.11), rust * float((flags & 32) != 0));
		rough = 0.55;
		metal = 0.35;
	} else if (kind == 4) {
		// Solar panel: dark blue cells in a silver frame.
		if (top) {
			vec2 c = wp.xz / 0.55;
			vec2 aa2 = fwidth(c);
			float cell = band(fract(c.x), 0.06, 0.94, aa2.x) * band(fract(c.y), 0.06, 0.94, aa2.y);
			alb = mix(vec3(0.62, 0.64, 0.66), vec3(0.04, 0.07, 0.15) * (0.85 + 0.3 * h21(floor(c))), cell);
			rough = mix(0.4, 0.12, cell);
			spec = 0.7;
		} else {
			alb = vec3(0.55, 0.57, 0.6);
			rough = 0.5;
		}
	} else if (kind == 5) {
		// Dry planter soil with leaf litter.
		alb = tint * (0.7 + 0.5 * vnoise(wp.xz * 9.0)) * (0.85 + 0.3 * h21(floor(wp.xz * 30.0)));
		rough = 1.0;
	} else if (kind == 6) {
		// Flat colour (fabric, plastic, wood, dead plants); optional awning stripes.
		alb = tint * (0.88 + 0.2 * vnoise(fp * 4.0));
		if ((flags & 64) != 0) {
			float s = step(0.5, fract(fp.x / 0.5));
			alb = mix(alb, vec3(0.9, 0.87, 0.8), s * 0.85);
		}
		rough = 0.85;
	} else if (kind == 7) {
		// Coping / cornice: pale cast concrete.
		vec3 c = texture(tex_concrete, fp * 0.3).rgb;
		alb = vec3(lum(c)) * 1.7 * tint;
		nm = texture(nrm_concrete, fp * 0.3).rgb;
		rough = 0.85;
	} else if (kind == 8) {
		alb = tint;
		rough = 0.8;
	} else {
		// Skylight glass.
		alb = vec3(0.1, 0.13, 0.16) + tint * 0.05;
		rough = 0.1;
		spec = 0.7;
	}
	ALBEDO = clamp(alb, 0.0, 1.0);
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = 0.8;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
}
