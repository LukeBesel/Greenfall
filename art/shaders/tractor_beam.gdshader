shader_type spatial;
// Tractor beam cone (Patch's claw and the Mk III/IV helpers). Additive light: bright fresnel
// edges, energy rings that scroll from the target toward the emitter, a twisting noise swirl,
// a fast flicker, and soft fades at both ends. Mesh: an uncapped cylinder whose local +Y end
// (y = +0.5) sits at the emitter and -Y end at the target; `beam_length` is the world length so
// the rings keep a constant spacing however far the beam reaches.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 beam_color : source_color = vec4(0.3, 0.88, 1.0, 1.0);
uniform float intensity = 1.0;
uniform float beam_length = 1.0;
uniform float ring_spacing = 0.17;  // metres between energy rings
uniform float ring_speed = 2.6;     // metres per second, toward the emitter
uniform float swirl = 1.0;          // 0 = plain rings (light version)
uniform float flicker = 1.0;

varying vec3 obj;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	obj = VERTEX;
}

void fragment() {
	// s: 0 at the emitter, 1 at the target. ang: around the beam, 0..1.
	float s = clamp(0.5 - obj.y, 0.0, 1.0);
	float ang = atan(obj.z, obj.x) / 6.2831853 + 0.5;
	float dist = s * beam_length;
	float ndv = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 1.6);
	// Energy rings travelling up the beam (sharp leading edge, soft tail).
	float ph = fract(dist / ring_spacing + TIME * ring_speed / ring_spacing);
	float rings = smoothstep(0.0, 0.12, ph) * smoothstep(0.55, 0.12, ph);
	// Twisting noise swirl (two octaves) so the field looks alive.
	vec2 nuv = vec2(ang * 6.0 + dist * 2.5 - TIME * 1.7, dist * 5.0 + TIME * 6.0);
	float n = vnoise(nuv) * 0.65 + vnoise(nuv * 2.3 + 7.1) * 0.35;
	float streaks = smoothstep(0.55, 0.95, n) * swirl;
	float flick = mix(1.0, 0.82 + 0.18 * sin(TIME * 53.0) * sin(TIME * 21.0 + s * 9.0), flicker);
	// Brighter, tighter near the emitter; fades in at the claw and out just past the target.
	float ends = smoothstep(0.0, 0.07, s) * smoothstep(1.02, 0.82, s);
	// Back faces get only a faint echo of the rings so the cone never reads as a zig-zag.
	float face = FRONT_FACING ? 1.0 : 0.3;
	float body = 0.08 + fres * 0.8 + (rings * (0.3 + 0.4 * fres) + streaks * 0.4) * face;
	float k = body * ends * flick * intensity;
	vec3 hot = mix(beam_color.rgb, vec3(1.0), 0.35 * rings + 0.25 * fres);
	ALBEDO = hot * (1.0 + 0.6 * rings);
	ALPHA = clamp(k * beam_color.a, 0.0, 1.0);
}
