shader_type spatial;
// General toon material. Optional rust patches (object space) and scrolling stripes (treads).
#include "res://art/shaders/toon_lib.gdshaderinc"

uniform vec4 albedo : source_color = vec4(1.0);
uniform float vertex_color_mix = 1.0;
uniform float rust_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 rust_color : source_color = vec4(0.78, 0.4, 0.18, 1.0);
uniform vec4 rust_dark : source_color = vec4(0.45, 0.22, 0.12, 1.0);
uniform float rust_scale = 3.5;
uniform float rust_seed = 0.0;
uniform float stripe_freq = 0.0;
uniform float stripe_offset = 0.0;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_strength = 0.0;
uniform float flash = 0.0;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec3 base = albedo.rgb * mix(vec3(1.0), COLOR.rgb, vertex_color_mix);
	float rough = 0.75;
	if (rust_amount > 0.0) {
		vec3 p = local_pos * rust_scale + vec3(rust_seed);
		float n = gf_fbm(p);
		float mask = smoothstep(1.0 - rust_amount - 0.04, 1.0 - rust_amount + 0.04, n);
		vec3 rust = mix(rust_color.rgb, rust_dark.rgb, smoothstep(0.35, 0.75, gf_fbm(p * 3.1)));
		// Tiny pitting everywhere so even "clean" paint looks old.
		float pit = step(0.86, gf_noise(local_pos * 40.0 + vec3(rust_seed)));
		base = mix(base, rust, max(mask, pit * 0.6 * rust_amount));
		rough = mix(rough, 0.95, mask);
	}
	if (stripe_freq > 0.0) {
		float st = step(0.5, fract(local_pos.z * stripe_freq + stripe_offset));
		base *= mix(0.62, 1.0, st);
	}
	ALBEDO = mix(base, vec3(1.0), flash);
	ROUGHNESS = rough;
	SPECULAR = 0.3;
	EMISSION = emission_color.rgb * emission_strength + vec3(flash * 0.4);
}
