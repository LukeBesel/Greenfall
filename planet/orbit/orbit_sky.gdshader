shader_type sky;
// [orbit] Sky for a round planet. Everything is in world space (no sky_rotation): the zenith is the
// local up under the camera, the two suns are fixed in space, so the sky always matches the lit
// side. Day: Rayleigh-ish blue to a warm dusty horizon; sunrise/sunset glow toward the suns;
// below the horizon a haze (the planet curves away) instead of black; night: deep blue with stars
// that turn with the suns, never pitch black (shared vision: nights stay readable).

uniform vec3 up_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 sun1_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 sun2_dir = vec3(0.3, 0.9, 0.0);
uniform float day = 1.0;          // 0 night .. 1 full day (at the camera)
uniform float sun2_strength = 0.6;
uniform float star_phi = 0.0;     // planet rotation phase: stars turn with the suns
uniform float space = 0.0;        // 1 = seen from orbit: black space, stars and suns only
uniform vec3 zenith_day : source_color = vec3(0.24, 0.42, 0.78);
uniform vec3 horizon_day : source_color = vec3(0.78, 0.74, 0.66);
uniform vec3 haze_day : source_color = vec3(0.55, 0.52, 0.48);
uniform vec3 zenith_night : source_color = vec3(0.02, 0.035, 0.08);
uniform vec3 horizon_night : source_color = vec3(0.07, 0.09, 0.16);
uniform vec3 dusk : source_color = vec3(1.0, 0.52, 0.26);
uniform vec3 sun1_color : source_color = vec3(1.0, 0.94, 0.82);
uniform vec3 sun2_color : source_color = vec3(1.0, 0.7, 0.48);

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float e = dot(d, up_dir);  // elevation of the view ray
	float h = clamp(e, 0.0, 1.0);
	vec3 day_col = mix(horizon_day, zenith_day, pow(h, 0.55));
	vec3 night_col = mix(horizon_night, zenith_night, pow(h, 0.7));
	vec3 col = mix(night_col, day_col, day);
	// Low sun: warm glow toward it along the horizon.
	float s1e = dot(sun1_dir, up_dir);
	float low1 = (1.0 - smoothstep(0.0, 0.35, abs(s1e))) * smoothstep(-0.2, 0.0, s1e);
	float toward1 = pow(max(dot(d, normalize(sun1_dir - up_dir * s1e + up_dir * 0.001)), 0.0), 3.0);
	col += dusk * low1 * toward1 * (1.0 - h) * 0.8;
	// Sun disks and halos (only above the local horizon).
	float c1 = dot(d, sun1_dir);
	float c2 = dot(d, sun2_dir);
	float vis1 = smoothstep(-0.02, 0.02, s1e);
	float vis2 = smoothstep(-0.02, 0.02, dot(sun2_dir, up_dir));
	col += sun1_color * (smoothstep(0.9994, 0.9997, c1) * 14.0 + pow(max(c1, 0.0), 220.0) * 1.2 + pow(max(c1, 0.0), 12.0) * 0.12) * vis1;
	col += sun2_color * (smoothstep(0.99975, 0.9999, c2) * 9.0 * sun2_strength + pow(max(c2, 0.0), 300.0) * 0.8 * sun2_strength) * vis2;
	// Stars, fixed in space (they turn with the suns).
	if (day < 0.6 && !AT_CUBEMAP_PASS) {
		float cp = cos(-star_phi);
		float sp = sin(-star_phi);
		vec3 sd = vec3(cp * d.x + sp * d.z, d.y, -sp * d.x + cp * d.z);
		vec3 cell = floor(sd * 260.0);
		float st = step(0.9975, hash3(cell));
		col += vec3(0.85, 0.9, 1.0) * st * (1.0 - day / 0.6) * smoothstep(0.0, 0.15, e) * (0.5 + hash3(cell + 7.0));
	}
	// Below the horizon: the planet curves away; show haze, never black.
	vec3 below = mix(horizon_night * 1.2, haze_day, day);
	col = mix(below, col, smoothstep(-0.06, 0.01, e));
	if (space > 0.5) {
		float cp = cos(-star_phi);
		float sp = sin(-star_phi);
		vec3 sd = vec3(cp * d.x + sp * d.z, d.y, -sp * d.x + cp * d.z);
		vec3 cell = floor(sd * 260.0);
		col = vec3(0.004, 0.006, 0.014) + vec3(0.85, 0.9, 1.0) * step(0.9975, hash3(cell)) * (0.5 + hash3(cell + 7.0))
			+ sun1_color * smoothstep(0.9994, 0.9997, c1) * 14.0 + sun2_color * smoothstep(0.99975, 0.9999, c2) * 9.0 * sun2_strength;
	}
	COLOR = col;
}
