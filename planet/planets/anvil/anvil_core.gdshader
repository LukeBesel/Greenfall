shader_type spatial;
// [planet-anvil] The depleted core shaft's inner wall (a cylinder seen from inside): dark layered
// rock that warms with depth into a dim ember glow, with thin glowing veins far down. glow_col
// eases from ember red (ruined) to warm white-gold (the core rekindled as Anvil is restored).
render_mode cull_front, diffuse_burley;

uniform vec3 rock_col = vec3(0.3, 0.16, 0.11);
uniform vec3 glow_col = vec3(1.0, 0.36, 0.12);
uniform float glow = 1.0;
uniform float top_y = -60.0;
uniform float depth = 330.0;

varying vec3 wpos;

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

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float d = clamp((top_y - wpos.y) / depth, 0.0, 1.0);
	float ang = atan(wpos.z - NODE_POSITION_WORLD.z, wpos.x - NODE_POSITION_WORLD.x);
	vec2 q = vec2(ang * 18.0, wpos.y * 0.12);
	float band = vnoise(vec2(wpos.y * 0.09, 0.5)) * 0.5 + vnoise(q * vec2(1.0, 3.0)) * 0.5;
	ALBEDO = rock_col * mix(0.5, 1.1, band) * (1.0 - d * 0.6);
	ROUGHNESS = 0.9;
	NORMAL = -NORMAL;
	float vein = 1.0 - smoothstep(0.0, 0.045, abs(vnoise(q * vec2(0.6, 0.35) + 3.0) - 0.5));
	float e = (0.12 + 0.6 * smoothstep(0.0, 0.25, d) + pow(d, 1.4)) * (0.55 + 0.45 * band) + vein * smoothstep(0.05, 0.6, d) * 1.2;
	EMISSION = glow_col * e * glow;
}
