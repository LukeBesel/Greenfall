shader_type spatial;
// [art3] Ivy over the kit facades of a town's inner blocks (planet/city_view.gd, BuildingDetail.ivy_card):
// two flat cards a hand's width off the wall, cut out leaf by leaf. The same growth as the ivy the
// city shader paints on the procedural walls (art/shaders/building_city.gdshader), so a block reads
// as one planting.
//   UV    metres along the facade, metres above its foot
//   UV2   metres below the facade's top, layer (0 against the wall, 1 the outer, sparser one)
//   COLOR.r  seed (0..1 per building)
render_mode diffuse_burley, specular_disabled;

uniform float alive = 0.45;  // 0 dry brown .. 1 all in leaf

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

// Nearest leaf: x distance to its middle (0..~0.7 of a cell), y its own random number.
vec2 leaves(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float best = 9.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			float hh = h21(i + o);
			vec2 c = o + vec2(hh, fract(hh * 57.3)) - f;
			float d = dot(c, c);
			if (d < best) {
				best = d;
				id = fract(hh * 13.7);
			}
		}
	}
	return vec2(sqrt(best), id);
}

void fragment() {
	vec2 p = UV + vec2(COLOR.r * 97.0, 0.0);
	float layer = UV2.y;
	float h_base = UV.y;
	float h_top = UV2.x;
	float k = COLOR.r;
	float reach = 1.5 + 12.0 * smoothstep(0.42, 0.9, vnoise(vec2(p.x * 0.16, 5.0 + k * 9.0)));
	float body = vnoise(p * 0.4 + 13.0) * 0.7 + vnoise(p * 1.9 + 3.0) * 0.3;
	float iv = (1.0 - smoothstep(reach * 0.45, reach, h_base)) * smoothstep(0.4, 0.58, body - layer * 0.08);
	float hang = 0.5 + 2.4 * vnoise(vec2(p.x * 0.45, 8.0));
	iv = max(iv, (1.0 - smoothstep(hang * 0.5, hang, h_top)) * smoothstep(0.5, 0.62, vnoise(vec2(p.x * 0.3, 21.0 + k)) - layer * 0.05));
	// Shop windows and doors stay clear: growth keeps to columns on the ground floor.
	iv *= mix(smoothstep(0.55, 0.7, vnoise(vec2(p.x * 0.35, 31.0))), 1.0, smoothstep(2.6, 3.6, h_base));
	vec2 lf = leaves(p * (7.0 + layer * 1.5) + layer * 11.0);
	float cut = smoothstep(0.25, 0.5, iv) + (0.38 - lf.x) * 0.6;
	if (cut < 0.5) {
		discard;
	}
	vec3 green = mix(vec3(0.06, 0.11, 0.035), vec3(0.2, 0.29, 0.085), lf.y);
	vec3 dry = mix(vec3(0.2, 0.16, 0.07), vec3(0.4, 0.32, 0.13), lf.y);
	float dead = smoothstep(0.45, 0.8, vnoise(p * 0.25 + 40.0)) * (1.0 - alive) + step(0.93, lf.y) * 0.6;
	vec3 c = mix(green, dry, clamp(dead, 0.0, 1.0));
	c *= mix(1.0, 0.68, smoothstep(0.15, 0.5, lf.x));  // each leaf darker toward its edge
	c *= 0.8 + 0.3 * layer;                             // the inner layer sits in the outer one's shade
	ALBEDO = c;
	ROUGHNESS = 0.8;
}
