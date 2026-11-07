shader_type spatial;
// Soft, wispy vapour puff for CPUParticles3D quads (rocket billows, steam, the climb trail).
// Billboarded in the vertex shader keeping the particle's scale (particles not yet emitted have a
// zero scale and vanish). Noise-textured soft disc with alpha erosion: as the particle ages
// (INSTANCE_CUSTOM.y) the low-density parts eat away first, so puffs break into wisps and fade
// instead of shrinking as round balls. Faked top light and noise shading give it some volume.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.95, 0.97, 1.0, 1.0);
uniform vec4 shade : source_color = vec4(0.72, 0.76, 0.84, 1.0);
uniform float brightness = 1.25;
uniform float softness = 0.32;
uniform float erosion = 0.75;   // how much of the density is eaten away by the end of life
uniform float density = 1.0;

varying float v_seed;
varying float v_age;
varying float v_rot;

void vertex() {
	mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	bb = bb * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * bb;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	v_seed = fract(float(INSTANCE_ID) * 0.6180339 + INSTANCE_CUSTOM.z * 3.7);
	v_age = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	v_rot = v_seed * 6.2831;
}

void fragment() {
	vec2 uv = UV - 0.5;
	float r = length(uv) * 2.0;
	float c = cos(v_rot);
	float s = sin(v_rot);
	vec2 ruv = vec2(c * uv.x - s * uv.y, s * uv.x + c * uv.y);
	vec2 off = vec2(v_seed * 7.3, v_seed * 3.1);
	float n1 = texture(noise_tex, ruv * 0.55 + off + vec2(0.0, v_age * 0.12)).r;
	float n2 = texture(noise_tex, ruv * 1.4 - off * 1.7 + vec2(v_age * 0.2, 0.0)).r;
	float n = n1 * 0.65 + n2 * 0.35;
	// Soft disc pushed around by the noise (lumpy edges, never a clean circle).
	float body = 1.0 - smoothstep(0.25, 1.0, r + (n - 0.5) * 0.55);
	float d = body * (0.3 + 1.0 * n * n * 1.3);
	float cut = v_age * erosion;
	float a = smoothstep(cut, cut + softness, d - 0.12) * COLOR.a * density;
	// Fake volume: lit from above, darker underside and in the noise valleys.
	float top = clamp(0.5 - uv.y * 1.2, 0.0, 1.0);
	vec3 col = mix(shade.rgb, tint.rgb, clamp(top * 0.7 + n * 0.5, 0.0, 1.0));
	ALBEDO = col * brightness * COLOR.rgb;
	ALPHA = clamp(a, 0.0, 1.0);
}
