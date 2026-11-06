shader_type spatial;
// Screen face for the hover bots: glossy black glass with two thick glowing "C" eyes (both open
// to the same side, like the concept art), a soft glow halo, ^ ^ when happy, blink/sleep squash.
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 eye_color : source_color = vec4(0.3, 0.9, 1.0, 1.0);
uniform float energy = 4.0;
uniform vec2 look = vec2(0.0);       // -1..1 eye offset
uniform float happy = 0.0;           // 0 = C eyes, 1 = smiling arcs
uniform float blink = 0.0;           // 1 = closed
uniform float half_width = 0.22;
uniform float half_height = 0.15;

varying vec3 lp;
varying vec3 ln;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

// Returns (core, halo).
vec2 eye(vec2 p, vec2 c, float r, float th) {
	vec2 d = p - c;
	d.y /= max(1.0 - blink * 0.9, 0.1);
	float dist = abs(length(d) - r);
	float ring = 1.0 - smoothstep(th * 0.5 - 0.02, th * 0.5 + 0.02, dist);
	// Gap on the viewer's right (object -x, since the face looks down -Z), like the letter C.
	float ang = abs(atan(d.y, -d.x));
	float gap = smoothstep(0.55, 0.75, ang);
	float core = ring * gap;
	float halo = exp(-dist * dist * 40.0) * gap * 0.5;
	// Happy: upper arc (an upside-down U) like ^ ^.
	vec2 dh = p - c - vec2(0.0, -r * 0.45);
	float dah = abs(length(dh) - r);
	float arc = (1.0 - smoothstep(th * 0.5 - 0.02, th * 0.5 + 0.02, dah)) * smoothstep(-0.02, 0.1, dh.y);
	float arc_halo = exp(-dah * dah * 40.0) * smoothstep(-0.05, 0.1, dh.y) * 0.5;
	return vec2(mix(core, arc, happy), mix(halo, arc_halo, happy));
}

void fragment() {
	vec2 p = vec2(lp.x, lp.y) / half_height;
	vec2 off = look * vec2(0.12, 0.1);
	vec2 a = eye(p, vec2(-0.6, 0.02) + off, 0.37, 0.21);
	vec2 b = eye(p, vec2(0.6, 0.02) + off, 0.37, 0.21);
	// Only on the flat front of the visor, never smeared over its rounded sides.
	float front = smoothstep(0.55, 0.85, abs(ln.z));
	float core = clamp(a.x + b.x, 0.0, 1.0) * front;
	float halo = clamp(a.y + b.y, 0.0, 1.0) * front;
	float scan = 0.02 * sin(lp.y * 900.0 + TIME * 6.0);
	ALBEDO = vec3(0.01, 0.012, 0.016);
	ROUGHNESS = 0.05;
	METALLIC = 0.0;
	SPECULAR = 0.9;
	vec3 hot = mix(eye_color.rgb, vec3(1.0), 0.2);
	EMISSION = hot * energy * 0.65 * core + eye_color.rgb * energy * 0.18 * halo
		+ eye_color.rgb * (0.006 + scan * 0.2) * (1.0 - length(p) * 0.45);
}
