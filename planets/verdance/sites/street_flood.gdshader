shader_type spatial;
// A flooded street (planets/verdance/sites/old_town_burst.gd): a shallow sheet of clear water
// with a ragged edge and a dark wet rim on the paving round it. Rings run out from where the jet
// comes down, small wind ripples cross them, and the surface takes the sky's colour at a low
// angle, so it reads as wet and bright from the yard. UV carries the sheet's own metres.
// `water` 0 leaves only the damp ground (the main shut down).
render_mode blend_mix, cull_back, depth_draw_never, specular_schlick_ggx;

uniform vec2 radii = vec2(11.0, 7.5);
uniform vec2 source = vec2(1.0, -2.5);
uniform float water = 1.0;
uniform vec3 shallow : source_color = vec3(0.3, 0.62, 0.68);
uniform vec3 deep : source_color = vec3(0.07, 0.4, 0.55);
uniform vec3 sky : source_color = vec3(0.6, 0.8, 1.0);
uniform vec3 damp : source_color = vec3(0.13, 0.11, 0.1);

varying vec2 m;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float height(vec2 p) {
	float d = length(p - source);
	float rings = sin(d * 4.2 - TIME * 7.0) * exp(-d * 0.16) * 0.55;
	float wind = noise(p * 1.9 + vec2(TIME * 0.7, TIME * 0.4)) + noise(p * 3.4 - vec2(TIME * 0.5, TIME * 0.8)) - 1.0;
	return rings + wind * 0.5;
}

void vertex() {
	m = UV;
}

void fragment() {
	float ragged = noise(m * 0.33) * 0.4 + noise(m * 0.9) * 0.2 - 0.3;
	float edge = length(m / radii) + ragged;
	float wet = smoothstep(1.3, 0.98, edge);
	if (wet < 0.01) {
		discard;
	}
	float pool = smoothstep(1.0, 0.9, edge) * water;
	float depth = smoothstep(0.95, 0.25, edge);
	float e = 0.12;
	float h0 = height(m);
	vec3 n_local = normalize(vec3((h0 - height(m + vec2(e, 0.0))) * 0.11 * pool, 1.0, (h0 - height(m + vec2(0.0, e))) * 0.11 * pool));
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(n_local, 0.0)).xyz);
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 3.0);
	float d = length(m - source);
	float foam = smoothstep(4.2, 1.0, d + (noise(m * 2.6 - vec2(0.0, TIME * 1.5)) - 0.5) * 2.4) * water;
	vec3 body = mix(shallow, deep, depth);
	body = mix(body, sky, fres * 0.75);
	body = mix(body, vec3(0.94, 0.98, 1.0), foam * 0.75);
	ALBEDO = mix(damp, body, pool);
	ROUGHNESS = mix(0.32, 0.04, pool);
	SPECULAR = mix(0.5, 0.85, pool);
	ALPHA = mix(0.5 * wet, mix(0.62, 0.92, max(depth, fres)), pool);
}
