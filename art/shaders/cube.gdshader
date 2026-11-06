shader_type spatial;
// Compacted junk cube. Mixed cubes are speckled with up to 3 colors; Perfect cubes get gold edges.
#include "res://art/shaders/toon_lib.gdshaderinc"

uniform vec4 color_a : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform vec4 color_b : source_color = vec4(0.6, 0.6, 0.6, 1.0);
uniform vec4 color_c : source_color = vec4(0.4, 0.4, 0.4, 1.0);
uniform float speckle = 1.0;
uniform float perfect = 0.0;
uniform float pure_shine = 0.0;
uniform float seed = 0.0;
uniform float flash = 0.0;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec3 p = local_pos * 7.0 + vec3(seed);
	float n = gf_noise(p);
	float n2 = gf_noise(p * 1.7 + 11.0);
	vec3 base = color_a.rgb;
	if (speckle > 0.5) {
		base = mix(base, color_b.rgb, step(0.55, n));
		base = mix(base, color_c.rgb, step(0.68, n2));
	}
	// Compressed-layer lines.
	float layers = smoothstep(0.42, 0.5, abs(fract(local_pos.y * 6.0 + n * 0.3) - 0.5));
	base *= mix(1.0, 0.86, layers);
	vec3 a = abs(local_pos) * 2.0;
	float edge = max(min(a.x, a.y), max(min(a.y, a.z), min(a.x, a.z)));
	float edge_band = smoothstep(0.84, 0.9, edge);
	if (perfect > 0.5) {
		base = mix(base, vec3(1.0, 0.82, 0.3), edge_band);
	}
	float shine = pure_shine * smoothstep(0.02, 0.0, abs(fract(local_pos.x + local_pos.y * 0.6 + TIME * 0.25) - 0.5) - 0.06);
	ALBEDO = mix(base + vec3(shine * 0.35), vec3(1.0), flash);
	ROUGHNESS = 0.55;
	SPECULAR = 0.45;
	EMISSION = vec3(1.0, 0.8, 0.3) * edge_band * perfect * 0.35 + vec3(flash * 0.5);
}
