shader_type spatial;
// Old Town's street-tree foliage (planets/verdance/sites/old_town_trees.gd): leaf cards with a
// cut-out leaf texture round a dark core, lit as one soft round mass (the mesh carries normals
// that point out of the cluster, not off each card), tinted per instance and swaying a little.
// UV2.x: how much a vertex sways. UV2.y: 1 on the opaque core.
render_mode cull_disabled, diffuse_burley;

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float sway = 1.0;
uniform float cut = 0.38;

varying float v_core;

void vertex() {
	v_core = UV2.y;
	vec3 o = MODEL_MATRIX[3].xyz;
	float ph = dot(o, vec3(0.37, 0.21, 0.29)) + VERTEX.y * 1.7 + VERTEX.x * 0.9;
	float w = UV2.x * sway * 0.035;
	VERTEX += vec3(sin(TIME * 1.3 + ph), sin(TIME * 0.9 + ph * 1.7) * 0.4, cos(TIME * 1.1 + ph * 1.3)) * w;
}

void fragment() {
	vec4 t = texture(leaf_tex, UV);
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;  // the engine flipped it for the back face; the cluster's own normal is wanted
	}
	ALBEDO = COLOR.rgb * mix(t.rgb, vec3(0.62), v_core);
	ALPHA = mix(t.a, 1.0, v_core);
	ALPHA_SCISSOR_THRESHOLD = cut;
	ROUGHNESS = 0.82;
	SPECULAR = 0.22;
	BACKLIGHT = ALBEDO * 0.55;
}
