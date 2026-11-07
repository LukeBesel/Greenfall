shader_type spatial;
// Big procedural street mural, painted on a wall: bold flat shapes in teal / coral / mustard /
// cobalt with heavy ink outlines (a rising sun, a giant flower, rolling hills, diagonal colour
// bands), then weathered: sun-faded, peeled back to the wall in patches, rain streaks, drips
// and grime along the bottom. variant 0 = wall mural, 1 = billboard poster (paper sheets,
// torn edges). Original composition; all from noise and SDFs, no texture art.
render_mode cull_back;

uniform float variant = 0.0;
uniform vec2 size = vec2(10.0, 8.0);
uniform float seed = 0.0;
uniform sampler2D wall_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 wall_tint : source_color = vec3(0.8, 0.77, 0.72);

const vec3 TEAL = vec3(0.0, 0.6, 0.58);
const vec3 CORAL = vec3(0.98, 0.38, 0.3);
const vec3 MUSTARD = vec3(0.97, 0.72, 0.1);
const vec3 COBALT = vec3(0.1, 0.25, 0.78);
const vec3 PINK = vec3(0.96, 0.42, 0.66);
const vec3 LEAF = vec3(0.2, 0.68, 0.28);
const vec3 CREAM = vec3(0.97, 0.92, 0.8);
const vec3 INK = vec3(0.05, 0.045, 0.06);

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
	for (int i = 0; i < 4; i++) {
		s += a * noise(p);
		p = p * 2.07 + vec2(3.1, 1.7);
		a *= 0.5;
	}
	return s;
}

vec3 pal(float i) {
	float k = mod(floor(i), 4.0);
	return k < 0.5 ? TEAL : (k < 1.5 ? CORAL : (k < 2.5 ? MUSTARD : COBALT));
}

// Fill a shape (signed distance d, metres) with colour c and give it a hand-painted ink outline.
void layer(inout vec3 col, float d, vec3 c, float ink) {
	float aa = 0.025;
	col = mix(col, c, smoothstep(aa, -aa, d));
	col = mix(col, INK, smoothstep(ink + aa, ink - aa, abs(d)) * step(0.001, ink));
}

float sd_ellipse(vec2 p, vec2 c, vec2 r, float ang) {
	vec2 q = p - c;
	float cs = cos(ang);
	float sn = sin(ang);
	q = vec2(cs * q.x + sn * q.y, -sn * q.x + cs * q.y);
	return (length(q / r) - 1.0) * min(r.x, r.y);
}

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = vec2(UV.x * size.x, (1.0 - UV.y) * size.y);
	float W = size.x;
	float H = size.y;
	float ink = 0.07;
	// Wobble everything a little so edges look brushed, not vector-perfect.
	vec2 pw = p + (vec2(noise(p * 2.3 + seed), noise(p * 2.3 + 7.0 + seed)) - 0.5) * 0.08;
	float rot = seed * 1.7;
	vec3 col;
	// Background: wide diagonal bands.
	float band = (pw.x + pw.y * 0.55) / (H * 0.32);
	col = pal(band + rot);
	float bd = abs(fract(band) - 0.5) * H * 0.32 - H * 0.16;
	col = mix(col, INK, smoothstep(ink, ink * 0.5, abs(bd)));
	vec2 sun_c = variant < 0.5 ? vec2(W * 0.68, H * 0.62) : vec2(W * 0.8, H * 0.55);
	float sun_r = min(W, H) * (variant < 0.5 ? 0.24 : 0.3);
	// Sun rays: alternating wedges in an annulus.
	vec2 sq = pw - sun_c;
	float ang = atan(sq.y, sq.x);
	float ray = step(0.5, fract(ang / 6.2831 * 14.0 + seed));
	float ring_d = max(length(sq) - sun_r * 1.75, sun_r * 1.12 - length(sq));
	if (ray > 0.5) {
		layer(col, ring_d, MUSTARD, ink);
	} else {
		layer(col, ring_d, CREAM, ink);
	}
	layer(col, length(sq) - sun_r, CORAL, ink);
	layer(col, length(sq) - sun_r * 0.68, MUSTARD, ink);
	layer(col, length(sq - vec2(-sun_r * 0.18, sun_r * 0.18)) - sun_r * 0.22, CREAM, 0.0);
	// Hills.
	float h1 = pw.y - (H * 0.3 + sin(pw.x * 0.55 + seed * 3.0) * H * 0.07);
	layer(col, h1, TEAL, ink);
	float h2 = pw.y - (H * 0.17 + sin(pw.x * 0.9 + 1.3 + seed) * H * 0.05);
	layer(col, h2, COBALT, ink);
	// Giant flower: stem, leaves, petals, centre.
	vec2 fc = variant < 0.5 ? vec2(W * 0.26, H * 0.62) : vec2(W * 0.3, H * 0.6);
	float fr = min(W, H) * 0.2;
	float stem = max(abs(pw.x - fc.x - sin(pw.y * 0.7) * 0.15) - fr * 0.09, pw.y - fc.y);
	layer(col, stem, LEAF, ink);
	layer(col, sd_ellipse(pw, vec2(fc.x + fr * 0.75, fc.y - fr * 1.6), vec2(fr * 0.85, fr * 0.32), 0.55), LEAF, ink);
	layer(col, sd_ellipse(pw, vec2(fc.x - fr * 0.75, fc.y - fr * 2.2), vec2(fr * 0.8, fr * 0.3), -0.5), LEAF, ink);
	float petals = 1e5;
	for (int i = 0; i < 7; i++) {
		float a = float(i) / 7.0 * 6.2831 + seed;
		petals = min(petals, length(pw - fc - vec2(cos(a), sin(a)) * fr * 0.72) - fr * 0.42);
	}
	layer(col, petals, PINK, ink);
	layer(col, length(pw - fc) - fr * 0.42, MUSTARD, ink);
	layer(col, length(pw - fc) - fr * 0.18, CORAL, 0.0);
	// Polka dots in the sky and a few sparkles.
	vec2 cell = floor(pw / 0.9);
	vec2 cp = (cell + 0.5) * 0.9 + (vec2(hash(cell), hash(cell + 3.3)) - 0.5) * 0.4;
	float dot_d = length(pw - cp) - 0.11;
	float sky = step(0.0, h1) * step(fr * 1.6, length(pw - fc)) * step(sun_r * 1.9, length(sq));
	col = mix(col, CREAM, smoothstep(0.02, -0.02, dot_d) * step(0.72, hash(cell + seed)) * sky);
	// Drips running down from the shapes.
	float dcol = floor(pw.x / 0.23);
	float dr = hash(vec2(dcol, seed));
	float dtop = H * (0.25 + 0.6 * hash(vec2(dcol, 2.0 + seed)));
	float dlen = 0.4 + dr * 1.6;
	float drip = step(0.86, dr) * step(abs(fract(pw.x / 0.23) - 0.5), 0.13) * step(pw.y, dtop) * step(dtop - dlen, pw.y);
	col = mix(col, pal(dcol + 1.0), drip);
	// Billboard: pasted paper sheets with seams and torn-off patches.
	float paper = 1.0;
	if (variant > 0.5) {
		float sx = fract(p.x / (W / 6.0));
		float sy = fract(p.y / (H / 3.0));
		float seam = smoothstep(0.012, 0.0, min(min(sx, 1.0 - sx), min(sy, 1.0 - sy)) * 0.5);
		col *= 1.0 - seam * 0.35;
		vec2 sheet = floor(vec2(p.x / (W / 6.0), p.y / (H / 3.0)));
		float torn = step(0.78, hash(sheet + 9.0)) * step(0.45 + 0.2 * noise(p * 4.0), fract(p.y / (H / 3.0)));
		paper = 1.0 - torn;
	}
	// Weathering.
	float fade = fbm(p * 0.35 + seed);
	col = mix(col, mix(col, CREAM, 0.5), smoothstep(0.35, 0.75, fade) * 0.45);
	col = mix(col, vec3(dot(col, vec3(0.3, 0.55, 0.15))), 0.12);
	float peel = smoothstep(0.66, 0.7, fbm(p * 0.9 + 11.0 + seed) + noise(p * 9.0) * 0.08);
	float coverage = (1.0 - peel) * paper;
	// Paint thins out toward the ground and the top edge (out of reach of the ladder).
	coverage *= smoothstep(0.05, 0.35, p.y) * smoothstep(H, H - 0.4 - noise(p * 3.0) * 0.6, p.y);
	vec3 wall = texture(wall_tex, v_world.xy * 0.35 + v_world.zy * 0.35).rgb * wall_tint;
	vec3 o = mix(wall, col, coverage);
	float streak = noise(vec2(p.x * 7.0, p.y * 0.25 + seed)) * noise(vec2(p.x * 2.0, p.y * 0.1));
	o *= 1.0 - streak * 0.35;
	o *= 1.0 - smoothstep(1.4, 0.0, p.y) * 0.4 * (0.5 + fbm(p * 2.0));
	ALBEDO = o;
	ROUGHNESS = mix(0.95, 0.7, coverage);
}
