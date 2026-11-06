shader_type spatial;
// Realistic restoration ground. Layers come from Texture2DArrays (albedo / normal / ARM):
//   0 cracked dry mud, 1 dry ground with rocks, 2 withered grass, 3 damaged asphalt, 4 rubble,
//   5 dirt (clean), 6 farm soil (clean), 7 worn concrete (hub).
// Per-hex state texture: R removed fraction, G flip time, B clean flag, A hub flag.
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2DArray albedo_arr : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_arr : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray arm_arr : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D state_tex : filter_nearest;
uniform int grid_radius = 9;
uniform float hex_size = 3.2;
uniform float time_now = 0.0;
uniform float tile_m = 3.2;
uniform vec2 focus_axial = vec2(9999.0);
uniform float ripple_speed = 5.0;
uniform float show_grid = 0.0;

varying vec3 wpos;

const float SQRT3 = 1.7320508;

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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.07 + 13.1;
		a *= 0.5;
	}
	return v;
}

vec2 hex_round(vec2 qr) {
	vec3 c = vec3(qr.x, qr.y, -qr.x - qr.y);
	vec3 r = round(c);
	vec3 d = abs(r - c);
	if (d.x > d.y && d.x > d.z) {
		r.x = -r.y - r.z;
	} else if (d.y > d.z) {
		r.y = -r.x - r.z;
	}
	return r.xy;
}

// Samples one layer with a per-layer rotation/offset to hide tiling.
void layer(int i, vec2 p, float w, inout vec3 alb, inout vec3 nrm, inout vec3 arm) {
	if (w <= 0.001) {
		return;
	}
	float a = float(i) * 1.7;
	mat2 rot = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
	vec2 uv = rot * p / tile_m + vec2(float(i) * 0.37);
	alb += texture(albedo_arr, vec3(uv, float(i))).rgb * w;
	nrm += texture(normal_arr, vec3(uv, float(i))).rgb * w;
	arm += texture(arm_arr, vec3(uv, float(i))).rgb * w;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 qr = vec2((SQRT3 / 3.0 * p.x - p.y / 3.0) / hex_size, (2.0 / 3.0 * p.y) / hex_size);
	vec2 ax = hex_round(qr);
	vec2 center = vec2(hex_size * (SQRT3 * ax.x + SQRT3 * 0.5 * ax.y), hex_size * 1.5 * ax.y);
	vec2 local = p - center;
	float apothem = hex_size * SQRT3 * 0.5;
	float m = max(abs(local.x), max(abs(dot(local, vec2(0.5, SQRT3 * 0.5))), abs(dot(local, vec2(0.5, -SQRT3 * 0.5)))));
	float edge_d = apothem - m;
	float hex_dist = (abs(ax.x) + abs(ax.y) + abs(ax.x + ax.y)) * 0.5;
	bool inside = hex_dist <= float(grid_radius);

	float removed = 0.0;
	float is_clean = 0.0;
	float is_hub = 0.0;
	float flip_t = -100.0;
	if (inside) {
		float size = float(grid_radius * 2 + 1);
		vec4 st = texture(state_tex, (ax + vec2(float(grid_radius)) + 0.5) / size);
		removed = st.r;
		flip_t = st.g;
		is_clean = st.b;
		is_hub = st.a;
	}

	// Dirty layer weights from large-scale noise.
	float n1 = fbm(p * 0.06);
	float n2 = fbm(p * 0.11 + 31.0);
	float n3 = fbm(p * 0.23 + 77.0);
	float w_crack = smoothstep(0.35, 0.65, n1);
	float w_rocks = 1.0 - w_crack;
	float w_grass = smoothstep(0.55, 0.7, n2) * 0.9;
	float w_asph = smoothstep(0.62, 0.72, fbm(p * 0.035 + 5.0));
	float w_rub = smoothstep(0.6, 0.75, n3) * 0.8;
	vec4 wd = vec4(w_crack, w_rocks, w_grass, w_asph);
	float sum_d = wd.x + wd.y + wd.z + wd.w + w_rub + 0.0001;

	// Clean layer weights.
	float w_dirt = smoothstep(0.3, 0.7, n2);
	float w_soil = 1.0 - w_dirt;

	float reveal = 0.0;
	float wave = 0.0;
	if (is_clean > 0.5) {
		float age = time_now - flip_t;
		float d = length(local);
		float front = age * ripple_speed;
		reveal = clamp((front - d) / 1.6 + fbm(p * 0.8) * 0.6 - 0.3, 0.0, 1.0);
		wave = smoothstep(1.4, 0.0, abs(front - d)) * smoothstep(3.0, 1.0, age);
	}

	vec3 alb_d = vec3(0.0);
	vec3 nrm_d = vec3(0.0);
	vec3 arm_d = vec3(0.0);
	vec3 alb_c = vec3(0.0);
	vec3 nrm_c = vec3(0.0);
	vec3 arm_c = vec3(0.0);
	if (reveal < 0.999) {
		layer(0, p, wd.x / sum_d, alb_d, nrm_d, arm_d);
		layer(1, p, wd.y / sum_d, alb_d, nrm_d, arm_d);
		layer(2, p, wd.z / sum_d, alb_d, nrm_d, arm_d);
		layer(3, p, wd.w / sum_d, alb_d, nrm_d, arm_d);
		layer(4, p, w_rub / sum_d, alb_d, nrm_d, arm_d);
		// Grime: oily dark stains and a hazy violet cast where junk sits.
		float stain = smoothstep(0.55, 0.8, fbm(p * 0.4 + 9.0)) * (1.0 - removed * 0.6);
		alb_d *= mix(1.0, 0.55, stain);
		alb_d = mix(alb_d, alb_d * vec3(0.92, 0.88, 0.98), 0.5);
		alb_d *= 0.85;
		// Partially cleaned hexes lose some grime.
		alb_d = mix(alb_d, alb_d * 1.12, removed * 0.5);
	}
	if (reveal > 0.001) {
		layer(5, p, w_dirt, alb_c, nrm_c, arm_c);
		layer(6, p, w_soil, alb_c, nrm_c, arm_c);
		alb_c *= 1.05;
	}
	vec3 alb = mix(alb_d, alb_c, reveal);
	vec3 nrm = mix(nrm_d, nrm_c, reveal);
	vec3 arm = mix(arm_d, arm_c, reveal);
	if (is_hub > 0.5) {
		alb = vec3(0.0);
		nrm = vec3(0.0);
		arm = vec3(0.0);
		layer(7, p, 1.0, alb, nrm, arm);
		alb *= mix(0.8, 1.0, fbm(p * 0.3));
	}
	// Large-scale value variation so the field doesn't read as a tiled carpet.
	alb *= mix(0.82, 1.08, fbm(p * 0.02 + 3.0));

	vec3 emission = vec3(0.0);
	if (inside && is_hub < 0.5) {
		float line = smoothstep(0.06, 0.0, edge_d);
		// Focused hex: a thin surveyor's outline.
		if (distance(ax, focus_axial) < 0.5) {
			emission += vec3(1.0, 0.7, 0.25) * line * 0.35;
		}
		emission += vec3(1.0, 0.85, 0.6) * line * show_grid * 0.15;
		// Clean flip: a soft sunlit wash rolling across the hex.
		emission += vec3(1.0, 0.86, 0.62) * wave * 0.12;
	}

	ALBEDO = alb;
	NORMAL_MAP = nrm;
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.4;
	ROUGHNESS = clamp(arm.g, 0.4, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.35;
	EMISSION = emission;
}
