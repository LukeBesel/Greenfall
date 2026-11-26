shader_type spatial;
// [art3] A junk piece in the field (planet/junk_looks.gd): the scans' and the junk kit's maps, plus
// what makes a piece sit in the ground instead of on it, whatever pose it lies in:
// - `v_h` is the height of each point above the piece's lowest point along the planet's up
//   (the model box and the instance transform give it; no per-instance data needed);
// - contact darkening low on the piece, dirt climbing from the ground with a ragged edge, a damp
//   dark band at the very bottom (lower roughness), and a slight sink into the ground;
// - age: colour pulled toward a dusty neutral (per model, data/junk_looks.json "tone").
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float normal_scale = 1.0;
uniform float roughness_mul = 1.0;
uniform float metallic_mul = 1.0;
uniform float ao_mix = 0.0;  // 1: the ORM map's red channel is ambient occlusion
uniform vec3 box_center = vec3(0.0);
uniform vec3 box_half = vec3(0.25);
uniform float sat = 0.8;  // tone: saturation kept
uniform float val = 0.9;  // tone: value kept
uniform vec3 dust : source_color = vec3(0.34, 0.31, 0.27);
uniform float dust_amt = 0.12;
uniform vec3 dirt : source_color = vec3(0.09, 0.08, 0.07);
uniform float dirt_h = 0.10;  // metres the dirt climbs
uniform float sink = 0.012;  // metres into the ground
uniform vec3 far_mean : source_color = vec3(0.17, 0.155, 0.135);  // far away the colour leans to the field's mean
uniform float far_from = 30.0;
uniform float far_to = 110.0;
uniform float far_amt = 0.45;

varying float v_h;
varying vec3 v_lp;
varying float v_far;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 up_w = dot(origin, origin) > 1.0 ? normalize(origin) : vec3(0.0, 1.0, 0.0);  // off the globe (previews): plain up
	mat3 m3 = mat3(MODEL_MATRIX);
	float sc = length(m3[0]);
	vec3 up_l = normalize(up_w * m3);  // transpose(m3) * up_w
	v_h = (dot(VERTEX - box_center, up_l) + dot(abs(up_l), box_half)) * sc;
	v_lp = VERTEX;
	v_far = smoothstep(far_from, far_to, distance(origin, CAMERA_POSITION_WORLD)) * far_amt;
	VERTEX -= up_l * (sink / max(sc, 0.001));
}

float h31(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h31(i), h31(i + vec3(1, 0, 0)), f.x), mix(h31(i + vec3(0, 1, 0)), h31(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h31(i + vec3(0, 0, 1)), h31(i + vec3(1, 0, 1)), f.x), mix(h31(i + vec3(0, 1, 1)), h31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	vec4 a = texture(albedo_tex, UV) * albedo;
	vec3 orm = texture(orm_tex, UV).rgb;
	vec3 c = a.rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, sat) * val;
	c = mix(c, dust, dust_amt * (0.6 + 0.8 * vnoise(v_lp * 9.0)));
	// dirt from the ground up, ragged; damp and dark at the very bottom
	float n = vnoise(v_lp * 23.0) * 0.6 + vnoise(v_lp * 61.0) * 0.4;
	float climb = 1.0 - smoothstep(0.0, dirt_h, v_h + (n - 0.5) * dirt_h * 0.9);
	float damp = 1.0 - smoothstep(0.0, dirt_h * 0.35, v_h + (n - 0.5) * dirt_h * 0.3);
	c = mix(c, dirt * (0.8 + 0.5 * n), climb * 0.72);
	c *= mix(0.45, 1.0, smoothstep(-0.01, 0.07, v_h));  // contact darkening
	ALBEDO = mix(c, far_mean, v_far);
	float rough = orm.g * roughness_mul;
	rough = mix(rough, 0.9, climb * 0.6);
	ROUGHNESS = mix(rough, 0.32, damp * 0.7);
	METALLIC = orm.b * metallic_mul * (1.0 - climb * 0.8);
	AO = mix(1.0, orm.r, ao_mix) * mix(0.55, 1.0, smoothstep(0.0, 0.09, v_h));
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_scale;
}
