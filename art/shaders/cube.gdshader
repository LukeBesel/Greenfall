shader_type spatial;
// Compacted junk bale. Voronoi chunks colored by contents (crushed cans, plastic, paper, rubber),
// with crumple normals, grime, and glints of bare metal. Object space, unit cube.
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 color_a : source_color = vec4(0.55, 0.52, 0.5, 1.0);
uniform vec4 color_b : source_color = vec4(0.45, 0.43, 0.4, 1.0);
uniform vec4 color_c : source_color = vec4(0.35, 0.33, 0.3, 1.0);
uniform vec4 fleck : source_color = vec4(0.7, 0.4, 0.2, 1.0);
uniform float mix_b = 0.35;
uniform float mix_c = 0.15;
uniform float metal_share = 0.3;
uniform float perfect = 0.0;
uniform float seed = 0.0;
uniform float flash = 0.0;
uniform sampler2D detail_nrm : hint_normal, filter_linear_mipmap, repeat_enable;

varying vec3 lp;
varying vec3 ln;

vec3 h33(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453);
}

// Returns (cell distance, edge distance, cell random).
vec3 voronoi(vec3 x) {
	vec3 n = floor(x);
	vec3 f = fract(x);
	float d1 = 8.0;
	float d2 = 8.0;
	float rid = 0.0;
	for (int k = -1; k <= 1; k++)
	for (int j = -1; j <= 1; j++)
	for (int i = -1; i <= 1; i++) {
		vec3 g = vec3(float(i), float(j), float(k));
		vec3 o = h33(n + g);
		vec3 r = g + o - f;
		float d = dot(r, r);
		if (d < d1) {
			d2 = d1;
			d1 = d;
			rid = o.x;
		} else if (d < d2) {
			d2 = d;
		}
	}
	return vec3(sqrt(d1), sqrt(d2) - sqrt(d1), rid);
}

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

void fragment() {
	// Squashed cells: flatter vertically, like layers pressed by the ram.
	vec3 q = lp * vec3(7.0, 12.0, 7.0) + vec3(seed);
	vec3 v = voronoi(q);
	float r = fract(v.z + seed * 0.13);
	vec3 col = color_a.rgb;
	if (r < mix_b) {
		col = color_b.rgb;
	} else if (r < mix_b + mix_c) {
		col = color_c.rgb;
	}
	col *= mix(0.7, 1.08, fract(r * 7.13));
	// Bare metal glints and labels on some chunks.
	float is_metal = step(1.0 - metal_share, fract(r * 3.7));
	col = mix(col, fleck.rgb, step(0.93, fract(r * 11.3)) * 0.8);
	// Crevices between chunks are dark.
	float crev = smoothstep(0.08, 0.0, v.y);
	col *= 1.0 - crev * 0.65;
	// Grime toward the bottom.
	col *= mix(0.65, 1.0, smoothstep(-0.5, 0.2, lp.y));
	vec3 w = pow(abs(ln), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 nrm = texture(detail_nrm, lp.zy * 1.3 + seed).rgb * w.x + texture(detail_nrm, lp.xz * 1.3 + seed).rgb * w.y + texture(detail_nrm, lp.xy * 1.3 + seed).rgb * w.z;
	ALBEDO = mix(col, vec3(1.0), flash * 0.6);
	NORMAL_MAP = nrm;
	METALLIC = is_metal * 0.7;
	ROUGHNESS = mix(0.85, 0.4, is_metal) + crev * 0.1;
	EMISSION = vec3(1.0, 0.8, 0.45) * perfect * 0.04 + vec3(flash * 0.3);
}
