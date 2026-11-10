shader_type spatial;
// [planet-ochre] Palms and succulents (vertex-coloured procedural meshes, MultiMesh): a gentle
// sway weighted by COLOR.a (0 at the root), phase from the instance position.
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform float sway = 0.06;
uniform float time_s = 0.0;
uniform float rough = 0.7;
uniform vec3 tint = vec3(1.0);

void vertex() {
	vec3 o = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float ph = o.x * 0.13 + o.z * 0.09;
	float w = COLOR.a * COLOR.a;
	VERTEX.x += sin(time_s * 1.3 + ph) * sway * w * (1.0 + VERTEX.y * 0.15);
	VERTEX.z += sin(time_s * 1.7 + ph * 1.3) * sway * 0.6 * w;
}

void fragment() {
	ALBEDO = pow(COLOR.rgb, vec3(2.2)) * tint;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
	BACKLIGHT = vec3(0.08, 0.1, 0.03) * COLOR.a;
}
