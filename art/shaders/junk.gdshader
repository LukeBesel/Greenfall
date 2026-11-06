shader_type spatial;
// Junk pieces in MultiMeshes. INSTANCE_CUSTOM.rgb = tint; vertex color alpha = how much the tint applies.
#include "res://art/shaders/toon_lib.gdshaderinc"

varying vec4 tint;
varying vec3 local_pos;

void vertex() {
	tint = INSTANCE_CUSTOM;
	local_pos = VERTEX;
}

void fragment() {
	vec3 base = mix(COLOR.rgb, COLOR.rgb * tint.rgb, COLOR.a);
	// A little grime so junk reads as old, but stays candy-bright.
	float g = gf_noise(local_pos * 9.0);
	base *= mix(0.82, 1.05, g);
	ALBEDO = base;
	ROUGHNESS = 0.6;
	SPECULAR = 0.4;
}
