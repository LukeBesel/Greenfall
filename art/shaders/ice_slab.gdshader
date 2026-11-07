shader_type spatial;
// [biomes2] Frozen Port ice sheet over the locked hexes (planet/frontier_view.gd: one dense plane
// over the field). Natural borders: the per-hex ice amount is looked up at the same noise-warped
// position the junk placement and the ground use (HexField.border_warp_image), so the sheet's
// margin wanders across hexes instead of tracing them. The sheet domes up inside a frozen area
// and thins to a clear, glassy lip at its edge; as a hex thaws, melt holes open in it.
// ice_tex: R = thickness 0..1 (0 = no ice), G = water hex (the sheet sits on the water surface).
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D ice_n : filter_nearest;   // the same image twice: exact per-hex value...
uniform sampler2D ice_l : filter_linear;    // ...and a smooth blend between hex centres
uniform sampler2D warp_tex : filter_linear;
uniform float warp_size = 280.0;
uniform float warp_amp = 0.0;
uniform int grid_radius = 4;
uniform float hex_size = 10.0;
uniform float water_y = 0.14;

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
		p = p * 2.1 + 7.7;
		a *= 0.5;
	}
	return v;
}

// Distance to the nearest Voronoi edge (crack network).
float cracks(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(h21(i + g), h21(i + g + 17.0));
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return d2 - d1;
}

vec2 hex_round(vec2 qr) {
	vec3 c = vec3(qr.x, qr.y, -qr.x - qr.y);
	vec3 r = round(c);
	vec3 d = abs(r - c);
	if (d.x > d.y && d.x > d.z) { r.x = -r.y - r.z; } else if (d.y > d.z) { r.y = -r.x - r.z; }
	return r.xy;
}

// x = exact ice of the (warped) hex, y = smooth ice, z = water (smooth). Outside the grid: 0.
vec3 ice_at(vec2 p) {
	vec2 pw = p + textureLod(warp_tex, p / warp_size + 0.5, 0.0).rg * warp_amp;
	vec2 qr = vec2((SQRT3 / 3.0 * pw.x - pw.y / 3.0) / hex_size, (2.0 / 3.0 * pw.y) / hex_size);
	vec2 ax = hex_round(qr);
	float r = float(grid_radius);
	if ((abs(ax.x) + abs(ax.y) + abs(ax.x + ax.y)) * 0.5 > r) {
		return vec3(0.0);
	}
	float size = r * 2.0 + 1.0;
	float vn = textureLod(ice_n, (ax + r + 0.5) / size, 0.0).r;
	vec2 sl = textureLod(ice_l, (qr + r + 0.5) / size, 0.0).rg;
	return vec3(vn, sl.x, sl.y);
}

// 0 at the sheet's margin (where the smooth value has fallen to half the hex's own), 1 inside.
float edge_of(vec3 s) {
	return smoothstep(0.5, 0.9, s.y / max(s.x, 0.001));
}

float sheet_h(vec2 p) {
	vec3 s = ice_at(p);
	float base = mix(0.015, water_y + 0.01, s.z);
	if (s.x <= 0.0) {
		return base - 0.06;
	}
	float e = edge_of(s);
	return base + (0.05 + 0.28 * s.x) * e * (0.85 + 0.3 * vnoise(p * 0.3));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = wpos.xz;
	float h = sheet_h(p);
	float e = 0.35;
	float hx = sheet_h(p + vec2(e, 0.0));
	float hz = sheet_h(p + vec2(0.0, e));
	VERTEX.y += h;
	wpos.y += h;
	NORMAL = normalize(vec3(h - hx, e, h - hz));  // the plane is unrotated and unscaled
}

void fragment() {
	vec2 p = wpos.xz;
	vec3 s = ice_at(p);
	if (s.x <= 0.001) {
		discard;
	}
	// Melt holes open as the hex thaws (organic, never hex-shaped).
	float melt = 1.0 - s.x;
	if (fbm(p * 0.28 + 5.0) < melt * 0.85 - 0.25) {
		discard;
	}
	float e = edge_of(s);
	float rim = 1.0 - smoothstep(0.0, 0.3, e);
	float frost = smoothstep(0.38, 0.72, fbm(p * 0.33) + s.x * 0.2 - rim * 0.3);
	float drift = smoothstep(0.55, 0.75, fbm(vec2(p.x * 0.6 + p.y * 0.4, p.y * 0.12) * 0.5 + 3.0));
	float cr = 1.0 - smoothstep(0.0, 0.05, cracks(p * 0.38));
	float cr2 = 1.0 - smoothstep(0.0, 0.03, cracks(p * 1.25 + 9.0));
	vec3 deep = vec3(0.24, 0.42, 0.52);
	vec3 clear = vec3(0.62, 0.78, 0.86);
	vec3 snow = vec3(0.93, 0.96, 1.0);
	float cover = clamp(frost * 0.45 + drift * 0.5, 0.0, 1.0) * (1.0 - rim);
	vec3 alb = mix(deep, clear, 0.35 + 0.4 * fbm(p * 0.9) + rim * 0.2);
	alb = mix(alb, snow, cover);
	alb = mix(alb, vec3(0.97, 0.99, 1.0), max(cr, cr2 * 0.6) * (1.0 - rim * 0.7));
	float a = mix(0.42, 0.9, cover) * mix(0.8, 1.0, s.x);
	a = mix(a, 0.9, max(cr, cr2 * 0.5));
	a *= mix(1.0, 0.5, rim);
	// Fine frost bumps; glassy where it is clear.
	vec2 g = vec2(0.12, 0.0);
	vec2 gr = vec2(fbm((p + g.xy) * 1.4) - fbm((p - g.xy) * 1.4), fbm((p + g.yx) * 1.4) - fbm((p - g.yx) * 1.4));
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wn = normalize(wn + vec3(-gr.x, 0.0, -gr.y) * mix(0.3, 1.4, frost));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ALBEDO = alb;
	ALPHA = a;
	ROUGHNESS = mix(0.05, 0.55, cover);
	SPECULAR = 0.65;
	RIM = 0.2;
	RIM_TINT = 0.7;
}
