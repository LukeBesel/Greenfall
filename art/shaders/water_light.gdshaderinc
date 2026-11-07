// [vqa] Shared light() for open water (water.gdshader, flood.gdshader).
// Water's colour is mostly reflected sky and scattered light, so a building's shadow only dims it a
// little. The stock lighting turned sun shadows on the near water into near-black slabs that ended
// abruptly at the shadow distance ("dark patches near the camera"). Sun shadows here keep
// (1 - water_shadow_soft) of their strength; lamps and other local lights are unchanged.
uniform float water_shadow_soft : hint_range(0.0, 1.0) = 0.7;

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float att = ATTENUATION;
	if (LIGHT_IS_DIRECTIONAL) {
		att = mix(att, 1.0, water_shadow_soft);
	}
	DIFFUSE_LIGHT += ndl * att * LIGHT_COLOR / PI;
	// GGX specular (Schlick fresnel, Smith visibility), dielectric.
	vec3 h = normalize(VIEW + LIGHT);
	float ndh = clamp(dot(NORMAL, h), 0.0, 1.0);
	float ndv = clamp(dot(NORMAL, VIEW), 1e-4, 1.0);
	float ldh = clamp(dot(LIGHT, h), 0.0, 1.0);
	float a = max(ROUGHNESS * ROUGHNESS, 0.002);
	float a2 = a * a;
	float dd = ndh * ndh * (a2 - 1.0) + 1.0;
	float d = a2 / (PI * dd * dd);
	float vis = 0.5 / max(ndl * sqrt(ndv * ndv * (1.0 - a2) + a2) + ndv * sqrt(ndl * ndl * (1.0 - a2) + a2), 1e-4);
	float f0 = 0.03;  // water
	float f = f0 + (1.0 - f0) * pow(1.0 - ldh, 5.0);
	// Direct sun glints still vanish in full shadow (only the diffuse is softened).
	SPECULAR_LIGHT += LIGHT_COLOR * d * vis * f * ndl * ATTENUATION * SPECULAR_AMOUNT * 2.0;  // light's specular (0.5 default)
}
