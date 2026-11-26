shader_type spatial;
// [art5] Heat-shield tiles under the shuttle (art/models/shuttle): a grid of dark ceramic tiles
// laid along the hull (object X / Z), each its own tone, a few pale replacements, gap filler
// between them, soot and re-entry scorch from the vertex grime (A), chipped corners.
render_mode diffuse_burley, specular_schlick_ggx;

uniform float tile_size = 0.11;
uniform vec4 tile_color : source_color = vec4(0.055, 0.058, 0.066, 1.0);
uniform vec4 new_color : source_color = vec4(0.34, 0.33, 0.31, 1.0);
uniform float ao_strength = 0.9;

varying vec3 opos;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	opos = VERTEX;
}

void fragment() {
	vec2 q = opos.xz / tile_size;
	q.x += floor(q.y) * 0.5;                     // running bond
	vec2 id = floor(q);
	vec2 f = fract(q);
	float gap = 1.0 - smoothstep(0.0, 0.05, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
	float r = h21(id);
	float r2 = h21(id + 17.3);
	vec3 c = tile_color.rgb * mix(0.65, 1.5, r);
	c = mix(c, new_color.rgb * mix(0.8, 1.1, r2), step(0.93, r2));          // replaced tiles
	// chipped corner: a pale bite at one corner of some tiles
	float corner = smoothstep(0.24, 0.14, length(f - step(0.5, vec2(r, r2)))) * step(0.82, r);
	c = mix(c, vec3(0.42, 0.4, 0.37), corner);
	c = mix(c, vec3(0.012), gap);
	// scorch: brown-grey heat stain, strongest where the grime is baked in
	float s = COLOR.a * mix(0.6, 1.0, r);
	c = mix(c, vec3(0.16, 0.11, 0.085), smoothstep(0.55, 1.0, s) * 0.5);
	ALBEDO = c;
	ROUGHNESS = mix(mix(0.5, 0.82, r), 0.95, gap);
	METALLIC = 0.0;
	SPECULAR = 0.35;
	AO = mix(1.0, COLOR.r, ao_strength);
	AO_LIGHT_AFFECT = 0.4;
}
