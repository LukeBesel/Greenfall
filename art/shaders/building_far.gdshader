shader_type spatial;
// Cheap distant building: textured wall with a procedural grid of windows (some lit-dark, some
// broken/boarded), floor bands, and grime streaks. Object-space so any box works.
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D wall_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wall_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(0.8, 0.76, 0.72, 1.0);
uniform float floor_h = 3.0;
uniform float bay_w = 3.0;
uniform float seed = 0.0;

varying vec3 wp;
varying vec3 wn;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21) + seed);
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	bool side_x = abs(wn.x) > 0.5;
	bool top = wn.y > 0.5;
	vec2 fp = side_x ? vec2(wp.z, wp.y) : vec2(wp.x, wp.y);
	if (top) {
		fp = wp.xz;
	}
	// Texture for detail only: desaturate it (some source textures are green paint) and take the
	// colour from the tint. Roofs get their own grey membrane look.
	vec3 tx = texture(wall_alb, fp * 0.25).rgb;
	float tl = dot(tx, vec3(0.299, 0.587, 0.114));
	vec3 alb = mix(vec3(tl), tx, 0.2) * tint.rgb * 1.45;
	if (top) {
		alb = vec3(tl) * vec3(0.95, 0.93, 0.9) * 1.1;
	}
	vec3 nrm = texture(wall_nrm, fp * 0.25).rgb;
	float rough = 0.9;
	if (!top) {
		vec2 cell = vec2(fp.x / bay_w, fp.y / floor_h);
		vec2 id = floor(cell);
		vec2 f = fract(cell);
		float win = step(0.22, f.x) * step(f.x, 0.78) * step(0.3, f.y) * step(f.y, 0.82);
		float r = h21(id);
		vec3 glass = mix(vec3(0.03, 0.035, 0.04), vec3(0.18, 0.2, 0.22), step(0.85, r));
		if (r < 0.12) {
			glass = alb * 0.55;  // boarded up
		}
		if (id.y < 0.5) {
			win *= step(0.4, h21(id + 7.0));
		}
		alb = mix(alb, glass, win);
		rough = mix(rough, 0.25, win * step(0.12, r));
		// Floor band and grime streaks under windows.
		float band = (1.0 - smoothstep(0.0, 0.03, abs(f.y - 0.02)));
		alb *= 1.0 - band * 0.3;
		float streak = step(0.25, f.x) * step(f.x, 0.75) * (1.0 - smoothstep(0.0, 0.3, f.y)) * 0.35 * h21(id + 3.0);
		alb *= 1.0 - streak;
		// Darker toward the ground.
		alb *= mix(0.7, 1.0, smoothstep(0.0, 6.0, wp.y));
	}
	ALBEDO = alb;
	NORMAL_MAP = nrm;
	ROUGHNESS = rough;
	SPECULAR = 0.4;
}
