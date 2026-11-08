shader_type spatial;
// [style] Character Builder eye shapes, drawn as a next_pass over the visor's face material
// (art/shaders/bot_face.gdshader keeps the glass, its own eyes are hidden with eye_radius < 0).
// shape: 1 round dots, 2 one visor bar, 3 hearts. Mirrors bot_face's look / blink / wink / happy
// (player/lumi_style_rig.gd copies them every frame), so blinks and the happy ^ ^ arcs still play.
// Same object space as bot_face: visor vertices, front = normal toward -Z.
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec4 eye_color : source_color = vec4(0.3, 0.9, 1.0, 1.0);
uniform float energy = 4.0;
uniform vec2 look = vec2(0.0);
uniform float happy = 0.0;
uniform float blink = 0.0;
uniform float wink = 0.0;
uniform float half_height = 0.17;
uniform float eye_spacing = 0.7;
uniform float eye_radius = 0.52;
uniform int shape = 1;

varying vec3 lp;
varying vec3 ln;

float dot2(vec2 v) { return dot(v, v); }

// Inigo Quilez's heart SDF (point up at y = 1, tip at y = 0).
float sd_heart(vec2 p) {
	p.x = abs(p.x);
	if (p.y + p.x > 1.0)
		return sqrt(dot2(p - vec2(0.25, 0.75))) - sqrt(2.0) / 4.0;
	return sqrt(min(dot2(p - vec2(0.0, 1.0)), dot2(p - 0.5 * max(p.x + p.y, 0.0)))) * sign(p.x - p.y);
}

float sd_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Returns (core, halo, glint) for one eye shape at c, squashed by open (0..1).
vec3 eye_shape(vec2 p, vec2 c, float R, float open) {
	float aa = 0.02;
	vec2 d = p - c;
	d.y /= max(open, 0.04);
	float sd;
	if (shape == 3) {
		vec2 q = d / (R * 1.05);
		q.y = q.y + 0.55;
		sd = sd_heart(q) * R * 1.05;
	} else {
		sd = length(d) - R * 0.62;
	}
	float core = (1.0 - smoothstep(-aa, aa, sd)) * step(0.04, open);
	float halo = exp(-max(sd, 0.0) * max(sd, 0.0) * 160.0) * (1.0 - core) * 0.5 * step(0.04, open);
	float glint = 1.0 - smoothstep(0.07 * R, 0.11 * R, length(d - vec2(-0.22, 0.22) * R));
	return vec3(core, halo, glint * core * step(0.3, open));
}

// Happy ^ arc (as in bot_face).
vec2 arc(vec2 p, vec2 c, float R, float a_open) {
	float aa = 0.02;
	vec2 dh = p - c - vec2(0.0, -R * 0.5);
	dh.y /= max(a_open, 0.04);
	float dah = abs(length(dh) - R * 0.85);
	float th = R * 0.2;
	float on_a = step(0.04, a_open);
	float a = (1.0 - smoothstep(th - aa, th + aa, dah)) * smoothstep(-0.05, 0.12, dh.y) * on_a;
	float h = exp(-max(dah - th, 0.0) * max(dah - th, 0.0) * 160.0) * smoothstep(-0.1, 0.12, dh.y) * 0.5 * (1.0 - a) * on_a;
	return vec2(a, h);
}

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

void fragment() {
	vec2 p = vec2(lp.x, lp.y) / half_height;
	vec2 off = look * vec2(0.1, 0.06);
	float hp = clamp(happy, 0.0, 1.0);
	float s_open = (1.0 - smoothstep(0.0, 0.5, hp));
	float a_open = smoothstep(0.5, 1.0, hp);
	float open_r = max((1.0 - blink * 0.94) * s_open, 0.0);
	float open_l = max((1.0 - max(blink, wink) * 0.94) * s_open, 0.0);
	vec2 cr = vec2(eye_spacing, 0.02) + off;
	vec2 cl = vec2(-eye_spacing, 0.02) + off;
	vec3 e;
	if (shape == 2) {
		// One visor bar across both eyes, with a brighter scan line drifting along it.
		vec2 d = p - vec2(0.0, 0.02) - off;
		d.y /= max(open_r, 0.04);
		float sd = sd_box(d, vec2(eye_spacing + eye_radius * 0.55, eye_radius * 0.24), eye_radius * 0.2);
		float core = (1.0 - smoothstep(-0.02, 0.02, sd)) * step(0.04, open_r);
		float halo = exp(-max(sd, 0.0) * max(sd, 0.0) * 160.0) * (1.0 - core) * 0.5 * step(0.04, open_r);
		float scan = exp(-pow((d.x - sin(TIME * 0.9) * eye_spacing) * 3.0, 2.0)) * core * 0.6;
		e = vec3(core, halo, scan);
	} else {
		vec3 a = eye_shape(p, cr, eye_radius, open_r);
		vec3 b = eye_shape(p, cl, eye_radius, open_l);
		e = clamp(a + b, 0.0, 1.0);
	}
	vec2 ar = arc(p, cr, eye_radius, a_open * (1.0 - blink * 0.9));
	vec2 al = arc(p, cl, eye_radius, a_open * (1.0 - max(blink, wink) * 0.9));
	float core = clamp(e.x + ar.x + al.x, 0.0, 1.0);
	float halo = clamp(e.y + ar.y + al.y, 0.0, 1.0);
	float front = smoothstep(0.55, 0.8, -ln.z);
	vec3 c = eye_color.rgb;
	vec3 col = mix(c * 0.9, mix(c, vec3(1.0), 0.3), 0.5) * core * energy * 0.6
		+ c * halo * energy * 0.1
		+ vec3(1.0) * e.z * energy * 0.5;
	ALBEDO = col * front;
}
