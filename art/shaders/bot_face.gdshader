shader_type spatial;
// Screen face for the hover bots: glossy black glass with two glowing eyes drawn procedurally.
// Eyes are "C"-shaped crescents; happy turns them into smiling arcs; blink/sleep squash them.
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

float eye(vec2 p, vec2 c, float r, float th) {
	vec2 d = p - c;
	d.y /= max(1.0 - blink * 0.92, 0.08);
	float ring = 1.0 - smoothstep(th * 0.55, th, abs(length(d) - r));
	// Crescent gap on the inner side of the ring (like a "C").
	// Both eyes are "C" shapes opening to the same side (like the concept art).
	float gap = smoothstep(r * 0.45, r * 0.75, length(d - vec2(r * 1.0, 0.0)));
	float round_eye = ring * gap;
	// Happy: upper arc only (an upside-down U), slightly raised.
	vec2 dh = p - c - vec2(0.0, -r * 0.35);
	float arc = (1.0 - smoothstep(th * 0.5, th, abs(length(dh) - r))) * smoothstep(-0.2 * r, 0.25 * r, dh.y);
	return mix(round_eye, arc, happy);
}

void fragment() {
	// Same scale on both axes so the eyes stay round.
	vec2 p = vec2(lp.x, lp.y) / half_height;
	vec2 off = look * vec2(0.12, 0.1);
	float r = 0.4;
	float th = 0.11;
	float e = eye(p, vec2(-0.6, 0.0) + off, r, th) + eye(p, vec2(0.6, 0.0) + off, r, th);
	// Faint scanline + edge vignette in the glass.
	float scan = 0.03 * sin(lp.y * 900.0 + TIME * 6.0);
	vec3 glass = vec3(0.012, 0.014, 0.018);
	ALBEDO = glass;
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.9;
	EMISSION = eye_color.rgb * energy * 0.6 * clamp(e, 0.0, 1.0) + eye_color.rgb * (0.006 + scan * 0.2) * (1.0 - length(p) * 0.5);
}
