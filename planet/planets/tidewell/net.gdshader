shader_type spatial;
// [planet-tidewell] A floating trash raft's base: tangled ghost net and rope with scum, on a disc
// laid on the water. Alpha-scissored mesh of knotted cords; the edge frays out with noise.
render_mode cull_disabled, diffuse_burley, depth_draw_opaque;

uniform vec3 cord : source_color = vec3(0.32, 0.36, 0.26);
uniform vec3 cord2 : source_color = vec3(0.62, 0.45, 0.22);
uniform vec3 scum : source_color = vec3(0.42, 0.4, 0.3);

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

varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(TIME * 1.3 + wpos.x * 0.7 + wpos.z * 0.5) * 0.01;
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	vec2 p = wpos.xz * 2.6;
	vec2 w = p + vec2(vnoise(p * 0.35), vnoise(p * 0.35 + 7.0)) * 2.2;
	vec2 g = abs(fract(w) - 0.5);
	float mesh = 1.0 - smoothstep(0.035, 0.075, min(g.x, g.y));
	float rope = 1.0 - smoothstep(0.03, 0.09, abs(sin(dot(wpos.xz, vec2(0.7, 0.4)) * 1.7 + vnoise(wpos.xz * 0.6) * 5.0)));
	float blob = smoothstep(0.55, 0.75, vnoise(wpos.xz * 1.3));
	float edge = 1.0 - smoothstep(0.55, 1.0, r + (vnoise(wpos.xz * 1.8) - 0.5) * 0.6);
	float a = max(max(mesh, rope * 0.9), blob) * edge;
	if (a < 0.45) { discard; }
	vec3 c = mix(cord, cord2, step(0.5, rope) * 0.7);
	c = mix(c, scum, blob);
	ALBEDO = c * (0.8 + 0.3 * vnoise(wpos.xz * 4.0));
	ROUGHNESS = mix(0.85, 0.5, blob);
	SPECULAR = 0.3;
}
