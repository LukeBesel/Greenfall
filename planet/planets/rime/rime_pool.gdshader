shader_type spatial;
// [planet-rime] Hot-spring pools (planet/planets/rime/env.gd: flattened discs). Per instance
// `thaw`: 0 = frozen over (white-blue ice with a milky rim), 1 = open warm water, turquoise in
// the middle, mineral sinter (cream to rust) at the rim, slow ripples.
render_mode diffuse_burley, specular_schlick_ggx;

instance uniform float thaw = 0.0;
uniform vec3 deep : source_color = vec3(0.05, 0.42, 0.5);
uniform vec3 shallow : source_color = vec3(0.35, 0.8, 0.78);
uniform vec3 sinter : source_color = vec3(0.86, 0.76, 0.6);
uniform vec3 sinter_rust : source_color = vec3(0.74, 0.44, 0.24);
uniform vec3 ice : source_color = vec3(0.72, 0.86, 0.96);

varying vec3 lpos;
varying vec3 wpos;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	lpos = VERTEX;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// The disc is a unit cylinder: radius 0.5 in local xz.
	float r = length(lpos.xz) * 2.0;
	float edge = r + (vnoise(wpos.xz * 0.6) - 0.5) * 0.25;
	float water = 1.0 - smoothstep(0.62, 0.72, edge);
	vec3 rim = mix(sinter, sinter_rust, smoothstep(0.7, 0.95, edge) * (0.5 + 0.5 * vnoise(wpos.xz * 2.0)));
	vec3 wcol = mix(shallow, deep, smoothstep(0.65, 0.0, edge));
	float t = clamp(thaw, 0.0, 1.0);
	vec3 col = mix(rim, wcol, water * t);
	vec3 frozen = mix(ice, vec3(0.93, 0.96, 1.0), smoothstep(0.3, 0.9, edge) + vnoise(wpos.xz * 1.5) * 0.2);
	col = mix(frozen, col, t);
	float rp = sin(length(wpos.xz - NODE_POSITION_WORLD.xz) * 4.0 - TIME * 1.2) * 0.5 + 0.5;
	vec3 nm = vec3(0.5 + (vnoise(wpos.xz * 1.7 + TIME * 0.3) - 0.5) * 0.25 * water * t, 0.5 + (rp - 0.5) * 0.12 * water * t, 1.0);
	ALBEDO = col;
	NORMAL_MAP = nm;
	ROUGHNESS = mix(mix(0.5, 0.12, 1.0 - smoothstep(0.5, 0.9, edge)), mix(0.75, 0.04, water), t);
	SPECULAR = 0.6;
	EMISSION = wcol * 0.06 * water * t;
}
