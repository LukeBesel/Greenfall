shader_type spatial;
// Old Town's restored paving (planets/verdance/sites/old_town_ground.gd): clay pavers laid in a
// running bond, each its own shade of terracotta, buff or sand, with sunk joints, crossed every
// few metres by a band of pale stone. UV carries site metres. Past a few dozen metres the pavers
// melt into their mean colour, so the pattern never shimmers.
render_mode cull_back, diffuse_burley;

uniform vec2 paver = vec2(0.3, 0.15);
uniform float band_every = 5.45;
uniform float band_w = 0.32;
uniform vec3 clay : source_color = vec3(0.76, 0.43, 0.3);
uniform vec3 buff : source_color = vec3(0.84, 0.68, 0.46);
uniform vec3 sand : source_color = vec3(0.78, 0.72, 0.6);
uniform vec3 stone : source_color = vec3(0.86, 0.83, 0.76);
uniform vec3 joint : source_color = vec3(0.36, 0.3, 0.25);
uniform float fresh = 1.0;  // 0: just laid over swept ground (dusty, pale); 1: washed and bright

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 m = UV;
	float px = max(fwidth(m.x), fwidth(m.y));
	float detail = 1.0 - smoothstep(0.03, 0.12, px);
	vec2 p = m / paver;
	p.x += 0.5 * mod(floor(p.y), 2.0);
	vec2 id = floor(p);
	vec2 f = fract(p);
	float pick = hash(id);
	vec3 one = pick < 0.5 ? clay : (pick < 0.82 ? buff : sand);
	one *= 0.9 + 0.2 * hash(id + 7.3);
	vec3 mean = clay * 0.5 + buff * 0.32 + sand * 0.18;
	vec2 e = min(f, 1.0 - f) * paver;
	float gap = 1.0 - smoothstep(0.004, 0.014, min(e.x, e.y));
	vec3 col = mix(mean, mix(one, joint, gap), detail);
	// Bands of pale stone both ways: the plaza's grid.
	vec2 b = abs(mod(m + band_every * 0.5, band_every) - band_every * 0.5);
	float band = 1.0 - smoothstep(band_w * 0.5, band_w * 0.5 + max(px, 0.01), min(b.x, b.y));
	float slab = hash(floor(m / 0.6));
	col = mix(col, stone * (0.94 + 0.1 * slab), band);
	float wear = hash(floor(m * 0.37)) * 0.5 + hash(floor(m * 1.3)) * 0.5;
	col *= mix(0.9, 1.04, wear);
	col = mix(mix(col, vec3(0.8, 0.74, 0.64), 0.35), col, fresh);
	ALBEDO = col;
	ROUGHNESS = mix(0.9, 0.72, fresh);
	SPECULAR = 0.3;
}
