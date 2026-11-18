shader_type spatial;
// [kit] Emissive trims/lenses with their glow colour per vertex (CUSTOM0.rgb, set by KitMesh.Builder),
// so every trim on a building is one draw call. powered = 0 gives dark frosted plastic.
render_mode diffuse_burley, specular_schlick_ggx;
uniform float powered = 1.0;
uniform float energy = 2.2;
varying vec3 glow;

void vertex() {
	glow = CUSTOM0.rgb;
}

void fragment() {
	vec3 off = mix(glow * 0.22, vec3(0.11), 0.55);
	ALBEDO = mix(off, mix(glow, vec3(1.0), 0.4), powered);
	ROUGHNESS = mix(0.5, 0.3, powered);
	EMISSION = glow * energy * powered;
}
