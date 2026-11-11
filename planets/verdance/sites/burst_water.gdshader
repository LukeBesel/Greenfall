shader_type spatial;
// Water under pressure (planets/verdance/sites/old_town_burst.gd): the burst main's jet and the
// curtain of water falling back round it. A surface of revolution (UV.x round it, UV.y from its
// start to its end) carrying torn streaks of white water that race along it; soft where the
// surface turns away from the eye, so the column has no hard outline.
render_mode blend_mix, cull_disabled, unshaded, depth_draw_never;

uniform float speed = 2.4;        // streaks per second along UV.y (the mesh runs the way the water goes)
uniform float density = 0.75;     // 0: a few torn streaks, 1: a solid column
uniform float opacity = 0.95;
uniform vec2 grain = vec2(9.0, 3.0);  // streak count round the surface, and along it
uniform vec3 bright : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 shade : source_color = vec3(0.56, 0.78, 0.92);
uniform float fade_in = 0.04;     // share of the length over which it appears
uniform float fade_out = 0.3;     // ... and breaks up at the end

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p, float wrap) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float x0 = mod(i.x, wrap);
	float x1 = mod(i.x + 1.0, wrap);
	return mix(mix(hash(vec2(x0, i.y)), hash(vec2(x1, i.y)), u.x), mix(hash(vec2(x0, i.y + 1.0)), hash(vec2(x1, i.y + 1.0)), u.x), u.y);
}

void vertex() {
	float w = UV.y * UV.y;
	VERTEX.x += sin(TIME * 5.3 + UV.y * 9.0) * 0.12 * w;
	VERTEX.z += cos(TIME * 4.1 + UV.y * 7.0) * 0.12 * w;
}

void fragment() {
	float run = TIME * speed;
	float coarse = noise(vec2(UV.x * grain.x, UV.y * grain.y - run), grain.x);
	float fine = noise(vec2(UV.x * grain.x * 3.0, UV.y * grain.y * 2.5 - run * 1.6), grain.x * 3.0);
	float streak = coarse * 0.62 + fine * 0.38;
	float body = smoothstep(1.0 - density - 0.18, 1.0 - density + 0.22, streak);
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float soft = smoothstep(0.02, 0.5, facing);
	float ends = smoothstep(0.0, fade_in, UV.y) * (1.0 - smoothstep(1.0 - fade_out, 1.0, UV.y + (fine - 0.5) * 0.25));
	ALBEDO = mix(shade, bright, smoothstep(0.35, 0.8, streak));
	ALPHA = clamp(body * soft * ends * opacity, 0.0, 1.0);
}
