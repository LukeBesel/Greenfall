shader_type spatial;
// [biomes2] Frozen Port ice sheets over junk hexes (planet/frontier_view.gd, one MultiMesh).
// Instance colour: rgb tint, a = thickness (0..1). Frosted, snow-dusted top with crack lines and
// bubbles; the junk shows through the clearer patches as dark shapes; blue, glassy sides.
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

varying vec3 wpos;
varying vec3 lnrm;
varying float thick;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.1 + 7.7;
		a *= 0.5;
	}
	return v;
}

// Distance to the nearest Voronoi edge (crack network).
float cracks(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(h21(i + g), h21(i + g + 17.0));
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return d2 - d1;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	lnrm = NORMAL;
	thick = COLOR.a;
}

void fragment() {
	vec2 p = wpos.xz;
	float top = step(0.5, lnrm.y);
	float frost = smoothstep(0.35, 0.75, fbm(p * 0.35) + thick * 0.25);
	float cr = 1.0 - smoothstep(0.0, 0.06, cracks(p * 0.42));
	float cr2 = 1.0 - smoothstep(0.0, 0.035, cracks(p * 1.3 + 9.0));
	vec3 deep = vec3(0.32, 0.5, 0.62) * COLOR.rgb;
	vec3 snow = vec3(0.92, 0.95, 0.99);
	vec3 alb = mix(deep, vec3(0.72, 0.84, 0.92), 0.45 + 0.3 * fbm(p * 1.1));
	alb = mix(alb, snow, frost * 0.85 * top);
	alb = mix(alb, vec3(0.96, 0.98, 1.0), max(cr, cr2 * 0.6) * top);
	float a = mix(0.55, 0.92, frost) * mix(0.75, 1.0, thick);
	a = mix(a, 0.98, max(cr, cr2 * 0.5) * top);
	a = mix(0.45, a, top);  // glassy sides
	// Bumpy frost on top (world-space gradient of the frost noise).
	vec2 e = vec2(0.15, 0.0);
	vec2 gr = vec2(fbm((p + e.xy) * 0.9) - fbm((p - e.xy) * 0.9), fbm((p + e.yx) * 0.9) - fbm((p - e.yx) * 0.9));
	vec3 wn = normalize(vec3(-gr.x * 1.2 * top, 1.0, -gr.y * 1.2 * top));
	if (top > 0.5) {
		NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	}
	ALBEDO = alb;
	ALPHA = a;
	ROUGHNESS = mix(0.06, 0.55, frost * top);
	SPECULAR = 0.6;
	RIM = 0.25;
	RIM_TINT = 0.6;
}
