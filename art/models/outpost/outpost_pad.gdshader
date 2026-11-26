shader_type spatial;
// [art4] The start pad: a wet concrete quay painted in code (art/models/outpost/build_pad_maps.py).
// One picture of the whole 21 m pad (colour, normal, occlusion/roughness/metal) plus a small
// tiling micro tile that only shows up close (it fades out with distance, so wides do not shimmer).
// Puddles are in the roughness map (0.04 = a mirror for the sky); the micro tile stays out of them.
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D alb_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D nrm_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_tex : filter_linear_mipmap_anisotropic;
uniform sampler2D detail_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float detail_scale = 0.85;      // repeats per metre
uniform float detail_normal = 0.55;
uniform float detail_fade = 20.0;       // metres at which the micro tile is gone
uniform float normal_strength = 1.0;
uniform float brightness = 1.0;
uniform float spec = 0.5;

varying vec3 opos;
varying vec3 onrm;

void vertex() {
	opos = VERTEX;
	onrm = NORMAL;
}

void fragment() {
	vec3 a = texture(alb_tex, UV).rgb;
	vec3 orm = texture(orm_tex, UV).rgb;
	vec3 n = texture(nrm_tex, UV).xyz;
	float upright = 1.0 - smoothstep(0.35, 0.7, abs(onrm.y));
	vec2 duv = mix(opos.xz, vec2(opos.x + opos.z, opos.y * 1.7), upright) * detail_scale;
	vec4 d = texture(detail_tex, duv);
	vec4 d2 = texture(detail_tex, duv * 0.19 + vec2(0.37, 0.11));
	float near = 1.0 - smoothstep(detail_fade * 0.35, detail_fade, -VERTEX.z);
	float water = 1.0 - smoothstep(0.06, 0.3, orm.g);
	float k = near * (1.0 - water);
	a *= mix(1.0, 0.84 + 0.32 * d.a, k) * (0.92 + 0.16 * d2.a);
	a *= mix(1.0, 0.72, upright * smoothstep(0.1, -0.25, opos.y));  // the quay face darkens toward the ground
	n.xy = (n.xy - 0.5) * normal_strength + (d.xy - 0.5) * detail_normal * k + 0.5;
	ALBEDO = a * brightness;
	ROUGHNESS = clamp(orm.g + (d.b - 0.5) * 0.3 * k, 0.04, 1.0);
	METALLIC = orm.b;
	SPECULAR = spec;
	NORMAL_MAP = n;
	NORMAL_MAP_DEPTH = 1.0;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.45;
}
