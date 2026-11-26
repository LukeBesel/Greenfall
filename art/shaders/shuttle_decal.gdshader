shader_type spatial;
// [art5] Painted marks and soot on the shuttle (art/models/shuttle/shuttle_decals.png): thin
// quads a few millimetres off the hull. The paint is worn: noise eats holes in it.
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx, shadows_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float wear : hint_range(0.0, 1.0) = 0.6;

varying vec3 opos;

float h31(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float n3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h31(i), h31(i + vec3(1, 0, 0)), f.x), mix(h31(i + vec3(0, 1, 0)), h31(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(h31(i + vec3(0, 0, 1)), h31(i + vec3(1, 0, 1)), f.x), mix(h31(i + vec3(0, 1, 1)), h31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	opos = VERTEX;
}

void fragment() {
	vec4 t = texture(atlas, UV);
	float n = n3(opos * 26.0) * 0.6 + n3(opos * 70.0) * 0.4;
	float keep = smoothstep(wear * 0.62 - 0.12, wear * 0.62 + 0.1, n);
	ALBEDO = t.rgb * mix(0.75, 1.0, n);
	ALPHA = t.a * keep;
	ROUGHNESS = 0.75;
	METALLIC = 0.0;
	SPECULAR = 0.3;
}
