shader_type spatial;
// [planet-rime] The inside of the giant borehole: banded walls (blue ice near the top, then grey
// strata, dark rock) falling into darkness, and a light far down. Ruined: a cold blue glimmer;
// restored: geothermal warmth returns and the depths glow amber.
render_mode cull_disabled, diffuse_burley;

uniform float top_y = 4.0;
uniform float depth_m = 160.0;
uniform float warm = 0.0;
uniform vec3 cold_col : source_color = vec3(0.25, 0.6, 1.0);
uniform vec3 warm_col : source_color = vec3(1.0, 0.55, 0.22);

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
	float d = clamp((top_y - wpos.y) / depth_m, 0.0, 1.0);
	float ang = atan(wpos.x - NODE_POSITION_WORLD.x, wpos.z - NODE_POSITION_WORLD.z);
	float wob = vnoise(vec2(ang * 6.0, wpos.y * 0.05)) * 2.0;
	float strata = 0.5 + 0.5 * sin(wpos.y * 0.9 + wob) * sin(wpos.y * 0.23 + 1.3);
	vec3 ice = mix(vec3(0.5, 0.72, 0.88), vec3(0.12, 0.3, 0.52), strata);
	vec3 rock = mix(vec3(0.24, 0.24, 0.26), vec3(0.4, 0.36, 0.32), strata);
	vec3 col = mix(ice, rock, smoothstep(0.06, 0.2, d));
	// Drill scoring: fine vertical grooves.
	col *= 0.85 + 0.15 * vnoise(vec2(ang * 90.0, wpos.y * 0.02));
	col *= mix(1.0, 0.03, smoothstep(0.0, 0.7, d));
	ALBEDO = col;
	ROUGHNESS = mix(0.15, 0.9, smoothstep(0.05, 0.2, d));
	vec3 gl = mix(cold_col * 0.35, warm_col * 1.2, warm);
	EMISSION = gl * smoothstep(0.45, 1.0, d) * (0.4 + 0.6 * vnoise(vec2(ang * 3.0, wpos.y * 0.03)));
}
