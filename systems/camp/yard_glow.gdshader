shader_type spatial;
// [yard] Lamp lenses, LEDs and screens on the yard builds. The vertex colour (sRGB) is the light's
// colour. `energy` 0 = dead glass (unpowered), ~1.5-3 = lit. Thin and subtle, never neon.
render_mode diffuse_burley, specular_schlick_ggx;

uniform float energy = 0.0;

void fragment() {
	vec3 c = pow(COLOR.rgb, vec3(2.2));
	float on = clamp(energy, 0.0, 1.0);
	ALBEDO = mix(c * 0.08 + vec3(0.03), c * 0.35, on);
	ROUGHNESS = mix(0.18, 0.35, on);
	METALLIC = 0.1;
	SPECULAR = 0.7;
	EMISSION = c * energy;
}
