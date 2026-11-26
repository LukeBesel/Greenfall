shader_type spatial;
render_mode cull_disabled;
// [art3] The litter carpet (planet/sites/sphere_litter.gd): one quad-ish sheet per piece, its kind
// (paper, cardboard, film, leaves, grit ...) picked from a 4 x 4 painted atlas by the instance
// colour's alpha, its outline cut by the atlas alpha. Instance colour rgb is the piece's tint.
// Distance: pieces drop out one by one (each by its own number) while the ones that stay grow and
// lean to the carpet's mean colour, so the far carpet is a quiet drift and its range ends without
// a line or sparkle. A dropped piece collapses in the vertex stage (no pixels are spent on it).
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_atlas : hint_normal, filter_linear_mipmap;
uniform float fade_from = 24.0;
uniform float fade_to = 60.0;
uniform float thin = 0.72;  // share of the pieces gone at the far end
uniform float grow = 0.9;   // how much the rest grow there
uniform vec3 far_mean : source_color = vec3(0.19, 0.165, 0.13);
uniform float far_amt = 0.5;
uniform float normal_depth = 0.9;

varying vec3 v_tint;
varying float v_far;

void vertex() {
	float kind = floor(COLOR.a * 16.0);
	UV = (vec2(mod(kind, 4.0), floor(kind * 0.25)) + UV) * 0.25;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float d = distance(origin, CAMERA_POSITION_WORLD);
	float f = smoothstep(fade_from, fade_to, d);
	float h = fract(sin(dot(origin, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	float end = smoothstep(fade_to * 0.9, fade_to, d);
	if (h < f * thin || h < end) {
		VERTEX = vec3(0.0);
	} else {
		VERTEX.xz *= 1.0 + f * grow;
	}
	v_tint = COLOR.rgb;
	v_far = f;
}

void fragment() {
	vec4 a = texture(atlas, UV);
	if (a.a < mix(0.5, 0.22, v_far)) {
		discard;
	}
	vec3 c = a.rgb * v_tint;
	ALBEDO = mix(c, far_mean, v_far * far_amt);
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	ROUGHNESS = mix(0.5, 0.92, smoothstep(0.02, 0.25, l));  // dark = damp or film: a little sheen
	NORMAL_MAP = texture(normal_atlas, UV).rgb;
	NORMAL_MAP_DEPTH = normal_depth * (1.0 - v_far);
}
