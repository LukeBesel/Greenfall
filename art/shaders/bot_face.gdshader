shader_type spatial;
// Screen face for the hero bot: glossy black convex glass with two big glowing "C" eyes like the
// concept sheet: a cyan disc with a dark pupil pushed to the upper right (so a thick crescent is
// left at the lower left), a white-hot inner edge, a soft bloom halo and a small glint in the
// pupil. Happy = ^ ^ arcs. Blink / sleep squash vertically. Drawn only on the flat front of the
// visor (object-space normal facing -Z), never smeared over its rounded edges.
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 eye_color : source_color = vec4(0.3, 0.9, 1.0, 1.0);
uniform float energy = 4.0;
uniform vec2 look = vec2(0.0);       // -1..1 eye offset (kept small: the eyes face forward)
uniform float happy = 0.0;           // 0 = C eyes, 1 = smiling arcs
uniform float blink = 0.0;           // 1 = closed
uniform float wink = 0.0;            // [photo] closes only the left eye (photo mode expressions)
uniform float half_width = 0.29;
uniform float half_height = 0.17;
uniform float eye_spacing = 0.7;    // eye centre offset from the middle (in half-heights)
uniform float eye_radius = 0.52;

varying vec3 lp;
varying vec3 ln;

// Returns (core, hot, halo, glint).
// [v10ui] happy never shows two shapes at once: the round eye shuts over 0..0.5 and the ^ arc
// opens over 0.5..1 (as art/shaders/lumi_eyes does). The old cross-fade drew the arc over the
// disc at any value in between ("his eyes on starter messed up", the title rested at 0.75).
vec4 eye(vec2 p, vec2 c, float R, float bl) {
	float hp = clamp(happy, 0.0, 1.0);
	float s_open = 1.0 - smoothstep(0.0, 0.5, hp);
	float a_open = smoothstep(0.5, 1.0, hp);
	float s_on = smoothstep(0.0, 0.2, s_open);
	float a_on = smoothstep(0.0, 0.2, a_open);
	vec2 d = p - c;
	d.y /= max((1.0 - bl * 0.92) * s_open, 0.08);
	float r = length(d);
	float aa = 0.02;
	float disc = 1.0 - smoothstep(R - aa, R + aa, r);
	// [main] One solid glowing eye per side (owner: the old C-ring + pupil ring read as two sets of
	// eyes). A filled disc, brighter toward the middle, a soft outer halo and one small glint.
	// [art2] Owner's concept sheet (26 Nov, "this is endgoal for characters"): a thick glowing C, one
	// shape per side (a disc with an off-centre bite toward the nose side and up), and one small
	// dot in the bite. Still one eye per side: no inner ring.
	// A ring with a gap toward the upper right and one dot floating in the gap (both eyes alike).
	float ring = disc * smoothstep(R * 0.5 - aa, R * 0.5 + aa, r);
	vec2 gap_dir = normalize(vec2(-0.78, 0.62));
	float ang = dot(normalize(d + vec2(1e-5)), gap_dir);
	float gap = smoothstep(0.86, 0.9, ang);
	float bite = gap;
	float core = ring * (1.0 - gap) * s_on;
	float hot = core * (1.0 - smoothstep(0.0, R * 0.12, abs(r - R * 0.75))) * 0.35;
	float halo = exp(-max(r - R, 0.0) * max(r - R, 0.0) * 55.0) * (1.0 - disc) * 0.6 * s_on * (1.0 - bite);
	float glint = 1.0 - smoothstep(0.11 * R, 0.15 * R, length(d - gap_dir * R * 0.78));
	glint *= step(0.5, s_open) * s_on;
	// Happy: an upper arc (an upside-down U) like ^ ^.
	vec2 dh = p - c - vec2(0.0, -R * 0.5);
	dh.y /= max(a_open * (1.0 - bl * 0.9), 0.08);
	float dah = abs(length(dh) - R * 0.85);
	float th = R * 0.2;
	float arc = (1.0 - smoothstep(th - aa, th + aa, dah)) * smoothstep(-0.05, 0.12, dh.y) * a_on;
	float arc_hot = arc * (1.0 - smoothstep(0.0, th, dah)) * 0.6;
	float arc_halo = exp(-max(dah - th, 0.0) * max(dah - th, 0.0) * 55.0) * smoothstep(-0.1, 0.12, dh.y) * 0.6 * (1.0 - arc) * a_on;
	return vec4(core + arc, hot + arc_hot, halo + arc_halo, glint);
}

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

void fragment() {
	vec2 p = vec2(lp.x, lp.y) / half_height;
	vec2 off = look * vec2(0.1, 0.06);
	vec4 a = eye(p, vec2(eye_spacing, 0.02) + off, eye_radius, blink);
	vec4 b = eye(p, vec2(-eye_spacing, 0.02) + off, eye_radius, max(blink, wink));
	float front = smoothstep(0.8, 0.95, -ln.z);
	float core = clamp(a.x + b.x, 0.0, 1.0) * front;
	float hot = clamp(a.y + b.y, 0.0, 1.0) * front;
	float halo = clamp(a.z + b.z, 0.0, 1.0) * front;
	float glint = clamp(a.w + b.w, 0.0, 1.0) * front;
	float scan = 0.5 + 0.5 * sin(lp.y * 1100.0);
	// Glossy convex glass: a soft reflection band across the upper left and a fresnel sheen.
	vec2 q = vec2(lp.x / half_width, lp.y / half_height);
	float streak = (1.0 - smoothstep(0.0, 0.22, abs(q.y - 0.68 + q.x * 0.25))) * smoothstep(-0.1, 0.8, q.x) * front;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 glass = vec3(0.008, 0.01, 0.014);
	ALBEDO = glass * (1.0 - core) + eye_color.rgb * 0.15 * core;
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.8;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.05;
	vec3 cyan = eye_color.rgb;
	vec3 white = mix(cyan, vec3(1.0), 0.7);
	vec3 eye_e = mix(cyan * 0.7, white, hot) * core * (0.9 + 0.1 * scan);
	EMISSION = eye_e * energy * 0.45
		+ cyan * halo * energy * 0.16
		+ vec3(1.0) * glint * energy * 0.6
		+ cyan * 0.01 * (1.0 - length(q) * 0.5)
		+ vec3(0.5, 0.56, 0.62) * streak * 0.07
		+ vec3(0.35, 0.45, 0.55) * fres * 0.1;
}
