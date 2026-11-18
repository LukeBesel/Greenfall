shader_type spatial;
// Story cinematics: a streaming trail of fire or light on an open cone / cylinder (meteor tails,
// the pod's re-entry fire). Brightest at the head (UV.y = head), fading to nothing at the tail and
// at the silhouette, with streaks running down its length. Additive, unshaded, both renderers.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 hot : source_color = vec4(1.0, 0.95, 0.8, 1.0);
uniform vec4 cool : source_color = vec4(1.0, 0.4, 0.1, 1.0);
uniform float strength = 1.0;
// 1 = the head is at UV.y 0 (the mesh's top), 0 = at UV.y 1.
uniform float head_at_top = 0.0;
uniform float speed = 3.0;
uniform float streaks = 7.0;
// A CylinderMesh's side UVs run 0..0.5 in V: 2 stretches them to 0..1.
uniform float v_scale = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 x) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float v = clamp(UV.y * v_scale, 0.0, 1.0);
	float along = mix(1.0 - v, v, head_at_top);  // 0 at the head, 1 at the tail
	float face = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge = smoothstep(0.0, 0.55, face);
	// Round the mesh by angle (cos, sin), so the streaks have no seam where UV.x wraps.
	vec2 ring = vec2(cos(UV.x * TAU), sin(UV.x * TAU)) * streaks * 0.3;
	float flow = noise(ring + vec2(along * 3.0 - TIME * speed, 0.0));
	float flow2 = noise(ring * 2.3 + vec2(4.0, along * 7.0 - TIME * speed * 1.7));
	float body = pow(1.0 - along, 1.7) * smoothstep(0.0, 0.06, along);
	float a = body * edge * mix(0.45, 1.0, flow) * mix(0.7, 1.0, flow2);
	vec3 col = mix(hot.rgb, cool.rgb, smoothstep(0.0, 0.55, along + (1.0 - flow) * 0.2));
	ALBEDO = col * a * strength;
}
