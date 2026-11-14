shader_type spatial;
// Rain puddle with an oil sheen. Opaque (alpha-tested outline) so screen-space reflections pick
// it up; near-zero roughness in the middle, a dark wet rim, and a thin-film rainbow where oil
// floats on top. Shape and sheen come from world-space noise, so every puddle differs.
render_mode cull_back;
// [orbD] Site frame on a walkable globe (identity on the flat game): "world" maths run in the
// nearest hub site's local metres, y up on its pad (planet/sites/site_manager.gd).
global uniform mat4 site_inv;

uniform float oil = 1.0;

varying vec3 v_world;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	v_world = (site_inv * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float shape = length(q) + (fbm(v_world.xz * 0.8) - 0.5) * 0.9;
	if (shape > 0.92) {
		discard;
	}
	float water = smoothstep(0.86, 0.66, shape);
	float film = fbm(v_world.xz * 1.9 + vec2(TIME * 0.015, -TIME * 0.01));
	float oil_mask = smoothstep(0.55, 0.75, fbm(v_world.xz * 0.55 + vec2(3.0, 7.0))) * oil * water;
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 rainbow = 0.5 + 0.5 * cos(6.2831 * (film * 2.6 + ndv * 0.9 + vec3(0.0, 0.33, 0.67)));
	// [qafix] QA #9: without screen-space reflections (Low, Medium, High, the Compatibility and
	// Mobile renderers) a near-black puddle read as a hole in the ground. Damp-ground colours plus a
	// cheap sky sheen at grazing angles keep it reading as water on every preset.
	vec3 wet = vec3(0.16, 0.14, 0.12);
	vec3 deep = vec3(0.085, 0.09, 0.1);
	float fres = pow(1.0 - ndv, 3.0);
	vec3 sheen = vec3(0.32, 0.36, 0.42) * fres * water * 0.7;
	ALBEDO = mix(mix(wet, deep, water), rainbow * 0.12 + deep, oil_mask * 0.6) + sheen;
	ROUGHNESS = mix(0.45, 0.02, water);
	METALLIC = 0.0;
	SPECULAR = 0.6;
	
}
