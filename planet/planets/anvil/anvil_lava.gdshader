shader_type spatial;
// [planet-anvil] Molten slag in Anvil's forge channels and pools. UV.x runs along the flow (metres),
// UV.y across (0..1). Dark crust plates drift on a glowing melt; the melt is hottest mid-channel
// and in the cracks. `heat` 1 = ruined forge running wild, cooling with restoration to a dark
// glassy crust with a thin, contained warm seam (geothermal).
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 hot_col = vec3(1.0, 0.26, 0.04);
uniform vec3 core_col = vec3(1.0, 0.55, 0.16);
uniform vec3 crust_col = vec3(0.05, 0.035, 0.03);
uniform float heat = 1.0;
uniform float flow = 0.35;      // m/s
uniform float glow = 1.7;

vec2 h22(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// Distance to the nearest cell edge (Voronoi): crust plates and their glowing seams.
float edge(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = h22(i + g);
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return d2 - d1;
}

float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = h22(i).x;
	float b = h22(i + vec2(1, 0)).x;
	float c = h22(i + vec2(0, 1)).x;
	float d = h22(i + vec2(1, 1)).x;
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 p = vec2(UV.x - TIME * flow, UV.y * 4.0);
	float across = 1.0 - abs(UV.y - 0.5) * 2.0;           // 1 mid-channel, 0 at the banks
	float e = edge(p * 0.55 + vec2(vn(p * 0.3) * 1.5, 0.0));
	float e2 = edge(p * 1.6 + 7.0);
	float crust_amt = mix(0.6, 0.95, 1.0 - heat) + (1.0 - across) * 0.4;
	float seam = 1.0 - smoothstep(0.0, mix(0.05, 0.24, 1.0 - crust_amt * 0.8), e);
	float plate = smoothstep(0.05, 0.25, e) * step(vn(p * 0.8 + 3.0), crust_amt + 0.15);
	float melt = clamp(1.0 - plate + seam * 0.8, 0.0, 1.0);
	float hot = melt * (0.6 + 0.4 * across) * (0.75 + 0.25 * sin(TIME * 1.3 + p.x * 0.7));
	vec3 crust = crust_col * (0.7 + 0.6 * vn(p * 3.0)) + vec3(0.06, 0.02, 0.01) * (1.0 - smoothstep(0.0, 0.12, e2));
	ALBEDO = mix(crust, vec3(0.12, 0.025, 0.01), melt * heat);
	ROUGHNESS = mix(0.35, 0.8, plate);
	SPECULAR = 0.5;
	vec3 em = mix(hot_col, core_col, smoothstep(0.6, 1.0, hot * across)) * hot * heat * glow;
	// Restored: one thin warm seam stays alight down the channel.
	em += hot_col * (1.0 - smoothstep(0.0, 0.06, abs(UV.y - 0.5) + (vn(p * 2.0) - 0.5) * 0.08)) * (1.0 - heat) * 0.8;
	EMISSION = em;
}
