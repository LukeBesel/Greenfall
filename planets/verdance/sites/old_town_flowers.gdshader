shader_type spatial;
// Old Town's bedding flowers (planets/verdance/sites/old_town_flowers.gd): a low leafy mound with
// blossoms standing on it. The instance colour is the petals' colour; the leaves keep their own
// green. UV2.x: 1 on a blossom, 0 on a leaf. UV2.y: 1 at a blossom's middle. UV.x: leaf shade.
render_mode cull_disabled, diffuse_burley;

uniform vec3 leaf : source_color = vec3(0.16, 0.36, 0.1);
uniform vec3 heart : source_color = vec3(0.98, 0.76, 0.12);

varying vec2 v_part;

void vertex() {
	v_part = UV2;
	vec3 o = MODEL_MATRIX[3].xyz;
	float ph = dot(o, vec3(0.41, 0.17, 0.33));
	VERTEX.xz += vec2(sin(TIME * 1.6 + ph), cos(TIME * 1.3 + ph * 1.4)) * 0.012 * UV2.x;
}

void fragment() {
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;  // lit as the mound's top from both sides
	}
	vec3 petal = mix(COLOR.rgb, heart, smoothstep(0.62, 0.8, v_part.y));
	ALBEDO = mix(leaf * (0.7 + 0.6 * UV.x), petal, step(0.5, v_part.x));
	ROUGHNESS = 0.8;
	SPECULAR = 0.2;
	BACKLIGHT = ALBEDO * 0.3 * step(0.5, v_part.x);
}
