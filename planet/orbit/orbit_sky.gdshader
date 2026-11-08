shader_type sky;
// [orbit] Sky for a round planet. Everything is in world space (no sky_rotation): the zenith is the
// local up under the camera, the two suns are fixed in space, so the sky always matches the lit
// side. Day: Rayleigh-ish blue to a warm dusty horizon; sunrise/sunset glow toward the suns;
// below the horizon a haze (the planet curves away) instead of black; night: deep blue with stars
// that turn with the suns, never pitch black (shared vision: nights stay readable).
// [orbE] Driven by SkyDirector's sphere mode (planet/sky_director.gd): haze (dust that lifts as the
// planet is cleaned), a cloud deck anchored to the planet (3D noise on a shell above the ground,
// so clouds stay put as you walk and drift with the wind), a full moon opposite the suns, the
// binary companion's size and colour from the solar system data, storms and Long Nights.

uniform vec3 up_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 eye_pos = vec3(0.0, 1840.0, 0.0);  // camera, planet frame (centre = origin)
uniform float planet_r = 1840.0;
uniform vec3 sun1_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 sun2_dir = vec3(0.3, 0.9, 0.0);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform float day = 1.0;          // 0 night .. 1 full day (at the camera)
uniform float sun2_strength = 0.6;
uniform float sun2_size = 0.55;   // companion disc, relative to the primary
uniform float star_phi = 0.0;     // planet rotation phase: stars turn with the suns
uniform float space = 0.0;        // 1 = seen from orbit: black space, stars and suns only
uniform float haze = 1.0;         // 1 dusty (Act 1) .. 0 clear
uniform float clouds = 0.35;      // cloud cover 0..1
uniform float cloud_t = 0.0;      // seconds (wind drift)
uniform float storm = 0.0;        // dust storm 0..1
uniform float night_lift = 1.0;   // brighter early nights (SkyDirector.night_lift)
uniform float night_dark = 0.0;   // Long Nights
uniform vec3 zenith_day : source_color = vec3(0.2, 0.42, 0.82);
uniform vec3 zenith_clear : source_color = vec3(0.12, 0.38, 0.9);
uniform vec3 horizon_day : source_color = vec3(0.78, 0.74, 0.66);
uniform vec3 horizon_clear : source_color = vec3(0.68, 0.8, 0.93);
uniform vec3 haze_day : source_color = vec3(0.55, 0.52, 0.48);
uniform vec3 zenith_night : source_color = vec3(0.03, 0.05, 0.11);
uniform vec3 horizon_night : source_color = vec3(0.09, 0.12, 0.21);
uniform vec3 dusk : source_color = vec3(1.0, 0.52, 0.26);
uniform vec3 dust : source_color = vec3(0.78, 0.6, 0.4);
uniform vec3 sun1_color : source_color = vec3(1.0, 0.94, 0.82);
uniform vec3 sun2_color : source_color = vec3(1.0, 0.7, 0.48);
uniform vec3 moon_color : source_color = vec3(0.86, 0.9, 1.0);

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s;
}

vec3 star_dir(vec3 d) {
	float cp = cos(-star_phi);
	float sp = sin(-star_phi);
	return vec3(cp * d.x + sp * d.z, d.y, -sp * d.x + cp * d.z);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float e = dot(d, up_dir);  // elevation of the view ray
	float h = clamp(e, 0.0, 1.0);
	// Vivid even in Act 1 (owner): the dust only warms the low sky, the zenith stays blue.
	vec3 zen = mix(zenith_clear, zenith_day, haze * 0.4);
	vec3 hor = mix(horizon_clear, horizon_day, haze * 0.6);
	vec3 day_col = mix(hor, zen, pow(h, 0.55));
	float lift = 1.0 + 0.7 * night_lift - 0.5 * night_dark;
	vec3 night_col = mix(horizon_night, zenith_night, pow(h, 0.7)) * lift;
	vec3 col = mix(night_col, day_col, day);
	// Low sun: warm glow toward it along the horizon.
	float s1e = dot(sun1_dir, up_dir);
	float low1 = (1.0 - smoothstep(0.0, 0.35, abs(s1e))) * smoothstep(-0.2, 0.0, s1e);
	float toward1 = pow(max(dot(d, normalize(sun1_dir - up_dir * s1e + up_dir * 0.001)), 0.0), 3.0);
	col += dusk * low1 * toward1 * (1.0 - h) * 0.8;
	// Moonlit night: a faint cool glow around the moon.
	float cm = dot(d, moon_dir);
	float vism = smoothstep(-0.03, 0.03, dot(moon_dir, up_dir));
	col += moon_color * pow(max(cm, 0.0), 24.0) * 0.08 * (1.0 - day) * vism;
	// Dust storm: the whole dome goes ochre.
	col = mix(col, dust * mix(0.25, 1.0, day), storm * 0.75);
	// Sun disks and halos (only above the local horizon).
	float c1 = dot(d, sun1_dir);
	float c2 = dot(d, sun2_dir);
	float vis1 = smoothstep(-0.02, 0.02, s1e);
	float vis2 = smoothstep(-0.02, 0.02, dot(sun2_dir, up_dir));
	float clear_sky = 1.0 - storm * 0.8;
	col += sun1_color * (smoothstep(0.9994, 0.9997, c1) * 14.0 + pow(max(c1, 0.0), 220.0) * 1.2 + pow(max(c1, 0.0), 12.0) * 0.12) * vis1 * clear_sky;
	float r2 = 0.0006 * sun2_size * sun2_size;  // 1 - cos(radius), radius ~ sun2_size of the primary
	col += sun2_color * (smoothstep(1.0 - r2 * 1.2, 1.0 - r2 * 0.8, c2) * 9.0 * sun2_strength + pow(max(c2, 0.0), 300.0) * 0.8 * sun2_strength) * vis2 * clear_sky;
	// The moon: a pale disc with soft maria, bright at night, a ghost by day.
	float md = smoothstep(0.99972, 0.99978, cm);
	if (md > 0.0) {
		float maria = fbm(star_dir(d) * 900.0);
		col = mix(col, moon_color * mix(0.5, 1.6, smoothstep(0.35, 0.65, maria)) * mix(1.6, 0.35, day), md * vism * clear_sky);
	}
	// Stars, fixed in space (they turn with the suns).
	if (day < 0.6 && !AT_CUBEMAP_PASS) {
		vec3 cell = floor(star_dir(d) * 260.0);
		float st = step(0.9975, hash3(cell));
		col += vec3(0.85, 0.9, 1.0) * st * (1.0 - day / 0.6) * smoothstep(0.0, 0.15, e) * (0.5 + hash3(cell + 7.0)) * clear_sky;
	}
	// Clouds: a deck 700 m up, sampled where the view ray meets it, anchored to the planet.
	if (clouds > 0.01 && e > -0.02 && space < 0.5) {
		float rc = planet_r + 700.0;
		float b = dot(eye_pos, d);
		float c = dot(eye_pos, eye_pos) - rc * rc;
		float disc = b * b - c;
		if (disc > 0.0) {
			float t = -b + sqrt(disc);
			vec3 hit = eye_pos + d * t;
			vec3 wind = vec3(cloud_t * 3.0, 0.0, cloud_t * 1.4);
			float n = fbm((hit + wind) / 520.0);
			float cover = mix(0.72, 0.38, clouds);
			float a = smoothstep(cover, cover + 0.16, n);
			a *= smoothstep(-0.02, 0.12, e) * (1.0 - smoothstep(1800.0, 5200.0, t) * 0.7);
			// Lit side: warm white by day, pink-orange at dusk, moon-grey at night; denser = darker underside.
			float thick = smoothstep(cover, cover + 0.35, n);
			vec3 lit_day = mix(vec3(1.0, 0.98, 0.95), vec3(0.62, 0.64, 0.7), thick * 0.6);
			lit_day = mix(lit_day, dusk * 1.1, low1 * 0.55);
			vec3 lit_night = vec3(0.16, 0.19, 0.27) * lift;
			vec3 cc = mix(lit_night, lit_day, day);
			cc = mix(cc, dust * mix(0.3, 0.9, day), storm * 0.6);
			// Silver lining toward a sun.
			cc += sun1_color * pow(max(c1, 0.0), 18.0) * (1.0 - thick) * 0.6 * vis1;
			col = mix(col, cc, a * 0.92);
		}
	}
	// Below the horizon: the planet curves away; show haze, never black.
	vec3 below = mix(horizon_night * 1.2 * lift, mix(horizon_clear * 0.75, haze_day, haze), day);
	below = mix(below, dust * mix(0.3, 0.8, day), storm * 0.7);
	col = mix(below, col, smoothstep(-0.06, 0.01, e));
	if (space > 0.5) {
		vec3 cell = floor(star_dir(d) * 260.0);
		col = vec3(0.004, 0.006, 0.014) + vec3(0.85, 0.9, 1.0) * step(0.9975, hash3(cell)) * (0.5 + hash3(cell + 7.0))
			+ sun1_color * smoothstep(0.9994, 0.9997, c1) * 14.0 + sun2_color * smoothstep(1.0 - r2 * 1.2, 1.0 - r2 * 0.8, c2) * 9.0 * sun2_strength
			+ moon_color * md * 1.2;
	}
	COLOR = col;
}
