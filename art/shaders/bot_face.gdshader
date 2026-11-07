shader_type spatial;
// Screen face for the hero bot (and the rocket): glossy black convex glass with two oversized cyan
// crescent ("C") eyes like the owner's Aurora portrait: ONE solid cyan disc with a dark round centre
// pushed to the viewer's upper right (a thick crescent is left at the lower left, the C opening at
// the upper right), a tight soft glow just outside the outer edge and ONE small catchlight in the
// dark centre. No inner hot ring and no pupil halo: those read as a second pair of eyes (owner,
// title screen). Happy = ^ ^ arcs: the C eye squashes shut first, THEN the arc opens, so the two
// shapes never show at the same time (a crossfade at happy ~0.75 drew both = "two sets of eyes").
// Blink / sleep squash vertically. Drawn only on the front of the visor (object-space normal
// facing -Z); the visor's back and side walls carry another material.
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
uniform float pupil_radius = 0.6;   // dark centre radius (in eye radii)
uniform vec2 pupil_offset = vec2(-0.3, 0.26); // dark centre offset (in eye radii; -x = viewer's right)

varying vec3 lp;
varying vec3 ln;

// Returns (core, shade, halo, glint). shade = 0 outer rim .. 1 next to the dark centre.
vec4 eye(vec2 p, vec2 c, float R, float bl, float hp) {
	float aa = 0.018;
	// C eye: squashes shut over the first half of the happy morph.
	float c_open = max((1.0 - bl * 0.94) * (1.0 - smoothstep(0.0, 0.5, hp)), 0.0);
	vec2 d = p - c;
	d.y /= max(c_open, 0.04);
	float r = length(d);
	float disc = 1.0 - smoothstep(R - aa, R + aa, r);
	vec2 pc = pupil_offset * R;
	float Rp = pupil_radius * R;
	float rp = length(d - pc);
	float pupil = 1.0 - smoothstep(Rp - aa, Rp + aa, rp);
	float on_c = step(0.04, c_open);
	float core = disc * (1.0 - pupil) * on_c;
	float shade = clamp(1.0 - (r - (Rp - length(pc))) / max(R - Rp + length(pc), 0.01), 0.0, 1.0);
	float halo = exp(-max(r - R, 0.0) * max(r - R, 0.0) * 160.0) * (1.0 - disc) * 0.5 * on_c;
	float glint = 1.0 - smoothstep(0.085 * R, 0.13 * R, length(d - pc - vec2(-0.3, 0.34) * Rp));
	glint *= pupil * disc * step(0.3, c_open);
	// Happy: an upper arc (^) that opens over the second half of the morph.
	float a_open = smoothstep(0.5, 1.0, hp) * (1.0 - bl * 0.9);
	float on_a = step(0.04, a_open);
	vec2 dh = p - c - vec2(0.0, -R * 0.5);
	dh.y /= max(a_open, 0.04);
	float dah = abs(length(dh) - R * 0.85);
	float th = R * 0.2;
	float arc = (1.0 - smoothstep(th - aa, th + aa, dah)) * smoothstep(-0.05, 0.12, dh.y) * on_a;
	float arc_halo = exp(-max(dah - th, 0.0) * max(dah - th, 0.0) * 160.0) * smoothstep(-0.1, 0.12, dh.y) * 0.5 * (1.0 - arc) * on_a;
	return vec4(max(core, arc), mix(shade, 0.5, arc), max(halo, arc_halo), glint);
}

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

void fragment() {
	vec2 p = vec2(lp.x, lp.y) / half_height;
	vec2 off = look * vec2(0.1, 0.06);
	vec4 a = eye(p, vec2(eye_spacing, 0.02) + off, eye_radius, blink, happy);
	vec4 b = eye(p, vec2(-eye_spacing, 0.02) + off, eye_radius, max(blink, wink), happy);
	float front = smoothstep(0.55, 0.8, -ln.z);
	float core = clamp(a.x + b.x, 0.0, 1.0) * front;
	float shade = clamp(a.y * a.x + b.y * b.x, 0.0, 1.0);
	float halo = clamp(a.z + b.z, 0.0, 1.0) * front;
	float glint = clamp(a.w + b.w, 0.0, 1.0) * front;
	// Glossy convex glass: a soft reflection band across the upper left and a fresnel sheen.
	vec2 q = vec2(lp.x / half_width, lp.y / half_height);
	float streak = (1.0 - smoothstep(0.0, 0.2, abs(q.y - 0.66 + q.x * 0.28))) * smoothstep(-0.2, 0.7, q.x) * front;
	float streak2 = (1.0 - smoothstep(0.0, 0.07, abs(q.y + 0.62 - q.x * 0.1))) * smoothstep(0.1, -0.6, q.x) * front;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 glass = vec3(0.006, 0.008, 0.011);
	ALBEDO = glass * (1.0 - core) + eye_color.rgb * 0.12 * core;
	ROUGHNESS = 0.04;
	METALLIC = 0.0;
	SPECULAR = 0.85;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.03;
	vec3 cyan = eye_color.rgb;
	// One solid crescent: even cyan, a touch lighter toward the dark centre (no separate ring).
	vec3 eye_e = mix(cyan * 0.85, mix(cyan, vec3(1.0), 0.35), shade * shade) * core;
	EMISSION = eye_e * energy * 0.6
		+ cyan * halo * energy * 0.1
		+ vec3(1.0) * glint * energy * 0.7
		+ vec3(0.5, 0.56, 0.62) * (streak * 0.08 + streak2 * 0.04)
		+ vec3(0.35, 0.45, 0.55) * fres * 0.1;
}
