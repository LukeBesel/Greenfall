shader_type spatial;
// [planet-anvil] Site grass tufts and flower clumps (Meadow's unit-height meshes in a MultiMesh).
// INSTANCE_CUSTOM: rgb = blade colour, a = petal hue pick (0..1). Vertex colour red marks petals.
// Blades darken at the root, lighten at the tip, and sway in a slow wind.
render_mode cull_disabled, diffuse_burley;

uniform float wind = 1.0;

varying vec3 v_col;
varying float v_h;
varying float v_petal;
varying float v_pick;

void vertex() {
	v_col = INSTANCE_CUSTOM.rgb;
	v_pick = INSTANCE_CUSTOM.a;
	v_petal = COLOR.r;
	v_h = clamp(VERTEX.y, 0.0, 1.0);
	vec3 w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float s = sin(TIME * 1.4 + w.x * 0.31 + w.z * 0.23) + 0.4 * sin(TIME * 3.1 + w.x * 1.7);
	VERTEX.x += s * 0.09 * v_h * v_h * wind;
	VERTEX.z += s * 0.05 * v_h * v_h * wind;
}

void fragment() {
	vec3 blade = mix(v_col * 0.45, v_col * 1.15, v_h);
	vec3 petal = v_pick < 0.3 ? vec3(0.95, 0.9, 0.78) : (v_pick < 0.55 ? vec3(1.0, 0.78, 0.18) : (v_pick < 0.8 ? vec3(0.92, 0.3, 0.22) : vec3(0.62, 0.38, 0.85)));
	ALBEDO = mix(blade, petal, step(0.5, v_petal));
	ROUGHNESS = 0.8;
	SPECULAR = 0.3;
	BACKLIGHT = vec3(0.25) * v_h;
}
