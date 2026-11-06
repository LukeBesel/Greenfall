shader_type spatial;
// City ground with per-hex restoration. Also used on sidewalk slab tops (works from world XZ).
// Texture2DArray layers: 0 worn asphalt, 1 damaged road, 2 concrete pavement, 3 dirty concrete,
// 4 dry ground + rocks, 5 withered grass, 6 dry decayed leaves, 7 rubble.
// layout_tex: R surface (0 lot, .25 road, .5 sidewalk, .75 building, 1 yard), G lane paint, B gutter.
// state_tex (per hex): R removed fraction, G flip time, B clean flag, A hub flag.
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2DArray albedo_arr : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_arr : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray arm_arr : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D layout_tex : filter_linear;
uniform float layout_size = 280.0;
uniform sampler2D state_tex : filter_nearest;
uniform int grid_radius = 9;
uniform float hex_size = 3.2;
uniform float time_now = 0.0;
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

struct Mat { vec3 alb; vec3 nrm; vec3 arm; };

Mat samp(int i, vec2 p, float tile) {
	float a = float(i) * 1.7;
	mat2 rot = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
	vec2 uv = rot * p / tile + vec2(float(i) * 0.37);
	Mat m;
	m.alb = texture(albedo_arr, vec3(uv, float(i))).rgb;
	m.nrm = texture(normal_arr, vec3(uv, float(i))).rgb;
	m.arm = texture(arm_arr, vec3(uv, float(i))).rgb;
	return m;
}

Mat mixm(Mat a, Mat b, float t) {
	Mat m;
	m.alb = mix(a.alb, b.alb, t);
	m.nrm = mix(a.nrm, b.nrm, t);
	m.arm = mix(a.arm, b.arm, t);
	return m;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	vec4 lay = texture(layout_tex, p / layout_size + 0.5);
	float surf = lay.r;
	bool is_road = surf > 0.15 && surf < 0.35;
	bool is_walk = surf > 0.4 && surf < 0.6;
	bool is_yard = surf > 0.9;

	// Hex lookup.
	vec2 qr = vec2((SQRT3 / 3.0 * p.x - p.y / 3.0) / hex_size, (2.0 / 3.0 * p.y) / hex_size);
	vec2 ax = hex_round(qr);
	vec2 center = vec2(hex_size * (SQRT3 * ax.x + SQRT3 * 0.5 * ax.y), hex_size * 1.5 * ax.y);
	vec2 local = p - center;
	float apothem = hex_size * SQRT3 * 0.5;
	float mx = max(abs(local.x), max(abs(dot(local, vec2(0.5, SQRT3 * 0.5))), abs(dot(local, vec2(0.5, -SQRT3 * 0.5)))));
	float edge_d = apothem - mx;
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
	float reveal = 0.0;
	float wave = 0.0;
	if (is_clean > 0.5) {
		float age = time_now - flip_t;
		float d = length(local);
		float front = age * ripple_speed;
		reveal = clamp((front - d) / 1.6 + fbm(p * 0.8) * 0.6 - 0.3, 0.0, 1.0);
		wave = smoothstep(1.4, 0.0, abs(front - d)) * smoothstep(3.0, 1.0, age);
	}
	if (!inside) {
		reveal = 0.0;
	}

	float n1 = fbm(p * 0.07);
	float n2 = fbm(p * 0.19 + 31.0);
	float n3 = fbm(p * 0.5 + 77.0);
	// --- Clean base surface -----------------------------------------------------------
	Mat base;
	if (is_road) {
		base = mixm(samp(0, p, 4.0), samp(1, p, 5.0), smoothstep(0.45, 0.7, n1));
		// Faded lane paint, broken up.
		float paint = lay.g * smoothstep(0.3, 0.6, fbm(p * 1.3 + 5.0));
		base.alb = mix(base.alb, vec3(0.78, 0.68, 0.42), paint * 0.75);
		base.arm.g = mix(base.arm.g, 0.6, paint);
	} else if (is_walk || is_yard) {
		base = mixm(samp(2, p, 2.5), samp(3, p, 3.0), is_yard ? 0.6 : smoothstep(0.55, 0.75, n1) * 0.6);
	} else {
		base = mixm(samp(4, p, 3.0), samp(5, p, 3.5), smoothstep(0.5, 0.7, n2) * 0.8);
	}
	// --- Dirty overlay: grime, drifts, leaves, rubble --------------------------------
	Mat dirty = base;
	if (reveal < 0.999 && !is_yard) {
		float gutter = lay.b;
		float drift = clamp(smoothstep(0.35, 0.7, n2) * 0.6 + gutter * 0.8, 0.0, 1.0);
		dirty = mixm(dirty, samp(4, p, 3.0), drift * (is_road ? 0.55 : 0.35));
		float leaves = smoothstep(0.5, 0.75, n3) * (0.4 + gutter * 0.6);
		dirty = mixm(dirty, samp(6, p, 2.0), leaves * 0.8);
		float rub = smoothstep(0.62, 0.8, fbm(p * 0.11 + 9.0));
		dirty = mixm(dirty, samp(7, p, 3.0), rub * 0.7);
		float stain = smoothstep(0.55, 0.85, fbm(p * 0.35 + 3.0));
		dirty.alb *= mix(1.0, 0.7, stain * 0.6);
		dirty.alb *= mix(0.9, 0.97, removed);
		
	}
	Mat m = mixm(dirty, base, reveal);
	if (is_hub > 0.5 || is_yard) {
		m = base;
	}
	// Large-scale value variation to hide tiling.
	m.alb *= mix(0.84, 1.06, fbm(p * 0.02 + 3.0));

	vec3 emission = vec3(0.0);
	if (inside && is_hub < 0.5) {
		float line = smoothstep(0.05, 0.0, edge_d);
		if (distance(ax, focus_axial) < 0.5) {
			emission += vec3(1.0, 0.7, 0.25) * line * 0.3;
		}
		emission += vec3(1.0, 0.85, 0.6) * line * show_grid * 0.12;
		emission += vec3(1.0, 0.86, 0.62) * wave * 0.1;
	}
	ALBEDO = m.alb;
	NORMAL_MAP = m.nrm;
	AO = m.arm.r;
	AO_LIGHT_AFFECT = 0.4;
	ROUGHNESS = clamp(m.arm.g, 0.35, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.4;
	EMISSION = emission;
}
