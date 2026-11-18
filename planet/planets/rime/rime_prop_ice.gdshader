shader_type spatial;
// [planet-rime] Solid glassy ice for props (frozen geysers, spires, arches, pressure-ridge slabs,
// the ice that grips the derricks). Opaque (no sorting): deep blue facing the camera, milky white
// at grazing angles and on top, world-space fracture lines and trapped bubbles.
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 ice_col : source_color = vec3(0.42, 0.66, 0.84);
uniform vec3 ice_deep : source_color = vec3(0.07, 0.24, 0.46);
uniform vec3 frost : source_color = vec3(0.9, 0.95, 1.0);
uniform float snow_top = 0.6;
uniform float rough_add = 0.0;     // frosted surfaces (round shapes glint less)
uniform float glow = 0.0;          // faint inner light (night crevasse blue / restored warmth)
uniform vec3 glow_col : source_color = vec3(0.3, 0.7, 1.0);

varying vec3 wpos;
varying vec3 wnrm;

float h31(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float vn3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h31(i), h31(i + vec3(1, 0, 0)), f.x), mix(h31(i + vec3(0, 1, 0)), h31(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h31(i + vec3(0, 0, 1)), h31(i + vec3(1, 0, 1)), f.x), mix(h31(i + vec3(0, 1, 1)), h31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wnrm);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	float a = vn3(wpos * 0.35);
	float b = vn3(wpos * 1.3 + 7.0);
	float crack = 1.0 - smoothstep(0.0, 0.035, abs(vn3(wpos * 0.6 + 3.0) - 0.5));
	vec3 col = mix(ice_deep, ice_col, 0.35 + 0.4 * a);
	col = mix(col, frost, fres * 0.7 + crack * 0.5);
	float top = smoothstep(0.55, 0.9, n.y + (b - 0.5) * 0.3) * snow_top;
	col = mix(col, frost, top);
	ALBEDO = col * (0.92 + 0.12 * b);
	ROUGHNESS = mix(0.2 + rough_add + crack * 0.2, 0.6, top);
	SPECULAR = 0.5;
	// Fake light scattering through thick ice: a little of the deep colour shines back.
	EMISSION = ice_deep * 0.05 * (1.0 - fres) + glow_col * glow * (1.0 - fres) * (0.4 + 0.6 * a);
}
