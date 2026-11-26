shader_type spatial;
// [art5] Bare alloy on the shuttle (art/models/shuttle): struts, piston rods, hinges, vanes and
// the engine bells. Vertex colour R = ambient occlusion, G = edge, B = cavity, A = heat: 0 is
// plain machined alloy; rising A runs through the tempering colours of hot metal (straw, bronze,
// purple, blue) to sooty grey at the lip. `glow` (set by ShipModel from the engines' heat) makes
// the hottest metal shine dull red.
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 metal_color : source_color = vec4(0.56, 0.57, 0.6, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.36;
uniform float glow : hint_range(0.0, 1.0) = 0.0;
uniform float ao_strength = 0.9;

varying vec3 opos;

float h31(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float n3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h31(i), h31(i + vec3(1, 0, 0)), f.x), mix(h31(i + vec3(0, 1, 0)), h31(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(h31(i + vec3(0, 0, 1)), h31(i + vec3(1, 0, 1)), f.x), mix(h31(i + vec3(0, 1, 1)), h31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	opos = VERTEX;
}

void fragment() {
	float n = n3(opos * 24.0);
	float big = n3(opos * 5.0);
	float heat = clamp(COLOR.a + (big - 0.5) * 0.16 * step(0.02, COLOR.a), 0.0, 1.0);
	vec3 c = metal_color.rgb * mix(0.82, 1.06, n);
	// tempering colours
	vec3 t = c;
	t = mix(t, vec3(0.62, 0.5, 0.3), smoothstep(0.1, 0.3, heat));
	t = mix(t, vec3(0.45, 0.27, 0.2), smoothstep(0.3, 0.48, heat));
	t = mix(t, vec3(0.3, 0.2, 0.36), smoothstep(0.48, 0.62, heat));
	t = mix(t, vec3(0.17, 0.24, 0.42), smoothstep(0.62, 0.76, heat));
	t = mix(t, vec3(0.085, 0.08, 0.08), smoothstep(0.8, 1.0, heat));
	c = t;
	// oil and dirt in the cavities, a brighter rubbed edge
	c = mix(c, c * 0.3, smoothstep(0.15, 0.7, COLOR.b) * 0.8);
	c = mix(c, min(c * 1.25, vec3(1.0)), COLOR.g * 0.3);
	c *= mix(0.8, 1.0, smoothstep(0.25, 0.6, big));
	ALBEDO = c;
	float soot = smoothstep(0.8, 1.0, heat);
	ROUGHNESS = clamp(roughness + (n - 0.5) * 0.22 + soot * 0.4 + COLOR.b * 0.25, 0.08, 1.0);
	METALLIC = mix(0.95, 0.35, soot);
	AO = mix(1.0, COLOR.r, ao_strength);
	AO_LIGHT_AFFECT = 0.5;
	EMISSION = vec3(1.0, 0.24, 0.05) * glow * glow * smoothstep(0.35, 1.0, heat) * 1.6;
}
