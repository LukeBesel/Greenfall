shader_type spatial;
// Future layer holograms: small way-signs with an icon, big text billboards and sky ads.
// Additive projected light on a quad (UV 0..1): scanlines, frame, a sweep, a soft flicker,
// and a flicker-on when born. Instance COLOR = (tint, width/height), INSTANCE_CUSTOM = (seed, icon,
// energy, born).
// icon 0 = text panel (frame only; text is a Label3D in front), 1 leaf, 2 drop, 3 sun, 4 heart,
// 5 chevrons, 6 planet ring.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform float t_now = 0.0;
uniform float energy = 1.0;

varying vec4 v_c;

void vertex() {
	v_c = INSTANCE_CUSTOM;
}

float h11(float x) {
	return fract(sin(x * 91.345 + 7.13) * 47453.5453);
}

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// Signed-ish distance of a few friendly glyphs in a -1..1 box (negative = inside).
float glyph(vec2 p, float id) {
	if (id < 1.5) {
		vec2 q = mat2(vec2(0.7071, 0.7071), vec2(-0.7071, 0.7071)) * p;
		float d = max(length(q - vec2(0.42, 0.0)) - 0.78, length(q + vec2(0.42, 0.0)) - 0.78);
		return min(abs(d) - 0.06, seg(p, vec2(-0.55, -0.55), vec2(0.3, 0.3)) - 0.04);
	} else if (id < 2.5) {
		float c = length(p - vec2(0.0, -0.2)) - 0.5;
		float t = max(abs(p.x) * 1.4 + (p.y - 0.75) * 0.75, -p.y - 0.1);
		return abs(min(c, t)) - 0.06;
	} else if (id < 3.5) {
		float r = length(p);
		float a = atan(p.y, p.x);
		float rays = max(abs(sin(a * 4.0)) - 0.25, abs(r - 0.72) - 0.16);
		return min(abs(r - 0.32) - 0.07, rays * 0.5);
	} else if (id < 4.5) {
		vec2 q = vec2(abs(p.x), p.y + 0.15);
		float d = length(q - vec2(0.3, 0.25)) - 0.33;
		float t = seg(q, vec2(0.0, -0.6), vec2(0.55, 0.12));
		return abs(min(d, t - 0.06)) - 0.06;
	} else if (id < 5.5) {
		float d1 = seg(vec2(abs(p.x), p.y), vec2(0.0, 0.45), vec2(0.6, -0.05)) - 0.08;
		float d2 = seg(vec2(abs(p.x), p.y), vec2(0.0, -0.05), vec2(0.6, -0.55)) - 0.08;
		return min(d1, d2);
	}
	float pl = abs(length(p) - 0.4) - 0.07;
	vec2 q = vec2(p.x, p.y * 3.2);
	float ring = abs(length(q) - 0.85) - 0.12;
	return min(pl, max(ring, -(length(p) - 0.45) + step(0.0, p.y) * 9.0));
}

void fragment() {
	float seed = v_c.r;
	float icon = v_c.g;
	float e = energy * v_c.b;
	float age = t_now - v_c.a;
	vec3 tint = COLOR.rgb;
	// Panel space in "heights": x spans the aspect (COLOR.a = width / height), y spans 1, up = +y.
	float asp = max(COLOR.a, 0.05);
	vec2 uv = UV;
	vec2 q = vec2((uv.x - 0.5) * asp, 0.5 - uv.y);
	float ex = asp * 0.5 - abs(q.x);
	float ey = 0.5 - abs(q.y);
	float edge = min(ex, ey);
	float border = smoothstep(0.022, 0.0, edge);
	float bracket = smoothstep(0.045, 0.0, edge) * step(ex, 0.12) * step(ey, 0.12);
	float fill = 0.12 + 0.05 * step(0.5, fract(q.y * 30.0 - TIME * 0.6));
	float scan = 0.82 + 0.18 * sin(uv.y * 220.0 + TIME * 5.0);
	float sweep = smoothstep(0.06, 0.0, abs(fract(uv.y * 0.6 - TIME * 0.22 + seed) - 0.5)) * 0.6;
	float g = 0.0;
	if (icon > 0.5) {
		// Icon near the top, then a column of short "text" lines.
		float r = 0.3 * min(asp, 1.0);
		vec2 ic = vec2(0.0, asp < 1.0 ? 0.5 - r * 1.5 : 0.13);
		float d = glyph((q - ic) / r, icon);
		g = smoothstep(0.08, 0.0, d) + smoothstep(0.5, 0.0, d) * 0.25;
		float ytop = ic.y - r * 1.3;
		float lp = asp < 1.0 ? 0.045 : 0.11;
		float ly = (ytop - q.y) / lp;
		float li = floor(ly);
		float lf = fract(ly);
		float len = (0.35 + 0.55 * h11(li + seed * 7.0)) * asp * 0.42;
		float line = step(abs(q.x), len) * step(0.4, lf) * step(lf, 0.72) * step(q.y, ytop) * step(-0.42, q.y);
		g += line * 0.7;
	}
	float light = fill * scan + border * 1.1 + bracket * 1.4 + g * 1.5 + sweep * 0.25;
	// Flicker: always a faint shimmer, a hard flicker-on for the first ~0.8 s after birth.
	float k = floor(TIME * 18.0);
	float on = age > 0.8 ? 1.0 : step(0.35, h11(k + seed * 13.0)) * smoothstep(0.0, 0.8, age);
	on = age < 0.0 ? 0.0 : on;
	float flick = 0.93 + 0.07 * sin(TIME * 31.0 + seed * 9.0) * sin(TIME * 7.0);
	vec3 col = mix(tint, vec3(1.0), clamp(g * 0.35 + bracket * 0.3, 0.0, 1.0));
	ALBEDO = col * light * e * on * flick;
}
