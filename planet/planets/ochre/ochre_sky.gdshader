shader_type sky;
// [planet-ochre] Ochre's sky: the closest planet to the binary star, so both suns are large and
// fierce. A hot white-gold horizon under a bleached, dusty zenith that deepens to blue as the
// planet is restored; a warm yellow-white primary and a smaller orange-red companion, each with
// a soft (thin) halo; stars at night.

uniform vec3 sun_a_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_b_dir = vec3(0.3, 0.9, 0.0);
uniform vec3 sun_a_col = vec3(1.0, 0.95, 0.85);
uniform vec3 sun_b_col = vec3(1.0, 0.62, 0.38);
uniform float sun_a_size = 2.0;   // disc radius, degrees
uniform float sun_b_size = 1.15;
uniform float sun_a_energy = 1.0;
uniform float sun_b_energy = 0.6;
uniform float halo = 0.35;
uniform vec3 horizon = vec3(1.0, 0.88, 0.66);
uniform vec3 zenith = vec3(0.8, 0.72, 0.56);
uniform vec3 haze = vec3(1.0, 0.82, 0.55);
uniform vec3 night_zenith = vec3(0.02, 0.025, 0.06);
uniform vec3 night_horizon = vec3(0.12, 0.07, 0.07);
uniform vec3 ground = vec3(0.45, 0.3, 0.18);
uniform float dust = 1.0;        // 1 ruined (thick haze) .. 0 clear
uniform float energy = 1.0;

float h31(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

vec3 sun_disc(vec3 dir, vec3 sd, vec3 col, float size_deg, float e) {
	float c = dot(dir, normalize(sd));
	float ang = degrees(acos(clamp(c, -1.0, 1.0)));
	// Limb-darkened disc with a crisp edge, a soft corona and a wide faint glare.
	float disc = 1.0 - smoothstep(size_deg * 0.94, size_deg, ang);
	float limb = mix(0.75, 1.0, sqrt(max(0.0, 1.0 - pow(ang / size_deg, 2.0))));
	float corona = exp(-max(ang - size_deg, 0.0) / (size_deg * 0.9)) * 0.55;
	float glare = exp(-ang / 18.0) * 0.18 + exp(-ang / 55.0) * 0.06;
	return col * e * (disc * limb * 14.0 + (corona + glare) * halo * 2.0);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float up = d.y;
	float day_a = smoothstep(-0.12, 0.12, normalize(sun_a_dir).y);
	float day_b = smoothstep(-0.12, 0.12, normalize(sun_b_dir).y);
	float day = max(day_a, day_b * 0.6);
	// Day gradient: hot pale band low down, bleached or blue above.
	float hz = pow(1.0 - clamp(up, 0.0, 1.0), 3.2);
	vec3 day_c = mix(zenith, horizon, hz);
	// Dust: a thick warm haze layer near the horizon; forward scattering toward the suns.
	float fwd = pow(max(dot(d, normalize(sun_a_dir)), 0.0), 6.0);
	day_c = mix(day_c, haze, (pow(1.0 - abs(up), 8.0) * 0.6 + fwd * 0.35) * (0.35 + 0.65 * dust));
	// Sunset: the low suns stain the haze rose-orange.
	float low = 1.0 - smoothstep(0.0, 0.35, normalize(sun_a_dir).y);
	day_c = mix(day_c, vec3(1.0, 0.55, 0.32), low * day * pow(1.0 - clamp(up, 0.0, 1.0), 4.0) * 0.6);
	vec3 night_c = mix(night_zenith, night_horizon, pow(1.0 - clamp(up, 0.0, 1.0), 2.5));
	vec3 col = mix(night_c, day_c, day);
	if (up < 0.0) {
		col = mix(col, ground * mix(0.05, 1.0, day), smoothstep(0.0, -0.08, up));
	}
	if (!AT_CUBEMAP_PASS) {
		// Stars (hidden by day and by the haze near the horizon).
		vec3 sc = floor(d * 260.0);
		float s = h31(sc);
		float star = step(0.9965, s) * (0.4 + 0.6 * h31(sc + 7.0)) * smoothstep(0.0, 0.25, up);
		col += vec3(0.85, 0.88, 1.0) * star * (1.0 - day) * 1.4;
		// The two suns (the companion a fixed angle from the primary).
		if (up > -0.05) {
			float hzb = smoothstep(-0.05, 0.05, up);
			col += sun_disc(d, sun_a_dir, sun_a_col, sun_a_size, sun_a_energy) * hzb;
			col += sun_disc(d, sun_b_dir, sun_b_col, sun_b_size, sun_b_energy) * hzb;
		}
	}
	COLOR = col * energy;
}
