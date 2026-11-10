shader_type spatial;
// [planet-ochre] The pit-floor pond: brown tailings sludge with a salt rim while ruined, a clear
// turquoise oasis pool once restored (clean 0..1).
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform float clean = 0.0;
uniform float time_s = 0.0;
uniform vec3 sludge = vec3(0.34, 0.27, 0.16);
uniform vec3 oasis_deep = vec3(0.03, 0.3, 0.33);
uniform vec3 oasis_shallow = vec3(0.2, 0.62, 0.55);
uniform vec3 salt = vec3(0.92, 0.9, 0.82);
varying vec3 wpos;

float h21(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y); }

void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	vec2 p = wpos.xz;
	float edge = UV.x; // 0 centre .. 1 shore
	float t = time_s;
	float w1 = vn(p * 0.35 + vec2(t * 0.15, t * 0.1));
	float w2 = vn(p * 0.9 - vec2(t * 0.22, -t * 0.12));
	vec3 nrm = normalize(vec3((w1 - 0.5) * 0.5 + (w2 - 0.5) * 0.3, 1.0, (w2 - 0.5) * 0.5));
	vec3 dirty = sludge * (0.8 + 0.35 * vn(p * 0.08)) ;
	float crust = smoothstep(0.7, 0.95, edge + (vn(p * 0.5) - 0.5) * 0.25) + smoothstep(0.72, 0.8, vn(p * 0.21 + 3.0)) * 0.6;
	dirty = mix(dirty, salt, clamp(crust, 0.0, 1.0) * 0.85);
	vec3 clear = mix(oasis_deep, oasis_shallow, smoothstep(0.45, 1.0, edge));
	float c = smoothstep(0.0, 1.0, clean);
	ALBEDO = mix(dirty, clear, c);
	ROUGHNESS = mix(mix(0.35, 0.9, clamp(crust, 0.0, 1.0)), 0.03, c);
	METALLIC = 0.0;
	SPECULAR = mix(0.4, 0.7, c);
	NORMAL = normalize((VIEW_MATRIX * vec4(mix(vec3(0.0, 1.0, 0.0), nrm, mix(0.3, 1.0, c)), 0.0)).xyz);
}
