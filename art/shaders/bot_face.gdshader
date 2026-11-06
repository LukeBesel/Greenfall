shader_type spatial;
// Screen face for the hover bots: glossy black glass with two glowing eyes drawn procedurally.
// Oval glowing eyes with a small catchlight; happy turns them into ^ ^ arcs;
// blink/sleep squash them.
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 eye_color : source_color = vec4(0.3, 0.9, 1.0, 1.0);
uniform float energy = 4.0;
uniform vec2 look = vec2(0.0);       // -1..1 eye offset
uniform float happy = 0.0;           // 0 = round crescents, 1 = smiling arcs
uniform float blink = 0.0;           // 1 = closed
uniform float half_width = 0.22;     // screen half extents in object space
uniform float half_height = 0.15;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

// Big soft oval eye with two catchlights. Returns (glow, highlight).
vec2 eye(vec2 p, vec2 c, float rx, float ry) {
	vec2 d = p - c;
	float sq = max(1.0 - blink * 0.92, 0.08);
	d.y /= sq;
	float k = length(d / vec2(rx, ry));
	float body = 1.0 - smoothstep(0.92, 1.0, k);
	// Brighter towards the top, a touch darker at the bottom: reads as a glossy pupil.
	float shade = mix(0.8, 1.0, clamp(d.y / ry * 0.5 + 0.5, 0.0, 1.0));
	float hl = 1.0 - smoothstep(0.045, 0.06, length(d - vec2(-rx * 0.28, ry * 0.4)));
	hl *= body * step(0.3, sq);
	// Happy: upper arc only (an upside-down U, like ^ ^).
	vec2 dh = p - c - vec2(0.0, -ry * 0.25);
	float th = 0.1;
	float arc = (1.0 - smoothstep(th * 0.5, th, abs(length(dh) - rx * 1.05))) * smoothstep(-0.05, 0.12, dh.y);
	return vec2(mix(body * shade, arc, happy), hl * (1.0 - happy));
}

void fragment() {
	// Same scale on both axes so the eyes stay round.
	vec2 p = vec2(lp.x, lp.y) / half_height;
	vec2 off = look * vec2(0.12, 0.1);
	vec2 el = eye(p, vec2(-0.58, 0.04) + off, 0.27, 0.36);
	vec2 er = eye(p, vec2(0.58, 0.04) + off, 0.27, 0.36);
	float e = el.x + er.x;
	float hl = clamp(el.y + er.y, 0.0, 1.0);
	// Faint scanline + edge vignette in the glass.
	float scan = 0.03 * sin(lp.y * 900.0 + TIME * 6.0);
	vec3 glass = vec3(0.012, 0.014, 0.018);
	ALBEDO = glass;
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.9;
	vec3 em = eye_color.rgb * energy * 0.6 * clamp(e, 0.0, 1.2) * (1.0 - hl);
	em += vec3(0.9, 0.97, 1.0) * energy * 0.5 * hl;
	EMISSION = em + eye_color.rgb * (0.006 + scan * 0.2) * (1.0 - length(p) * 0.5);
}
