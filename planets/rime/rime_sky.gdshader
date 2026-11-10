shader_type sky;
// [planet-rime] Rime's sky: a thin, cold atmosphere (black-blue zenith, a narrow pale band at the
// horizon), the system's two suns as small distant points with thin halos (primary white-gold,
// companion orange-red), stars that stay out even at noon, a huge ringed gas giant low over the
// horizon (lit by the suns, faint giantshine on its night side, rings with the planet's shadow),
// and a faint aurora at night. Driven by planets/rime/env.gd.

uniform vec3 zenith_col = vec3(0.004, 0.008, 0.026);
uniform vec3 horizon_col = vec3(0.1, 0.19, 0.32);
uniform vec3 night_zenith = vec3(0.004, 0.008, 0.022);
uniform vec3 night_horizon = vec3(0.03, 0.05, 0.095);
uniform float day = 1.0;           // 0 night .. 1 full day
uniform float stars_day = 0.55;    // star strength by day (1 at night)
uniform float haze = 1.0;          // ice-crystal haze near the horizon (ruined) .. 0 restored
uniform float warmth = 0.0;        // restored: the horizon band takes a little warmth
uniform vec3 sun_a_dir = vec3(0.0, 0.7, 0.7);
uniform vec3 sun_a_col = vec3(1.0, 0.95, 0.85);
uniform float sun_a_size = 0.32;   // relative disc size (1 = Verdance's primary)
uniform vec3 sun_b_dir = vec3(0.2, 0.6, 0.75);
uniform vec3 sun_b_col = vec3(1.0, 0.62, 0.38);
uniform float sun_b_size = 0.18;
uniform float sun_b_amt = 0.25;
uniform vec3 giant_dir = vec3(-0.36, 0.38, -0.85);
uniform float giant_r = 0.11;      // sin of the angular radius (data/look.json sky.giant_radius_deg)
uniform float giant_fade = 0.18;   // distance haze over the giant (0 = crisp)
uniform vec3 giant_pole = vec3(0.25, 0.95, 0.18);
uniform float ring_in = 1.3;
uniform float ring_out = 2.15;
uniform vec3 band_a : source_color = vec3(0.86, 0.78, 0.64);
uniform vec3 band_b : source_color = vec3(0.52, 0.66, 0.68);
uniform vec3 band_c : source_color = vec3(0.68, 0.56, 0.62);
uniform float aurora = 0.0;
uniform vec3 aurora_lo : source_color = vec3(0.25, 1.0, 0.72);
uniform vec3 aurora_hi : source_color = vec3(0.55, 0.4, 1.0);

float h31(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

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
		p = p * 2.03 + 17.3;
		a *= 0.5;
	}
	return v;
}

// Point stars on a 3D cell grid around the view direction (no pole pinching).
float stars(vec3 d, float scale, float density) {
	vec3 p = d * scale;
	vec3 i = floor(p);
	vec3 f = fract(p);
	float h = h31(i);
	if (h < 1.0 - density) {
		return 0.0;
	}
	vec3 sp = vec3(h31(i + 1.3), h31(i + 2.7), h31(i + 4.1)) * 0.7 + 0.15;
	float dd = length(f - sp);
	float b = pow((h - (1.0 - density)) / density, 3.0);
	return smoothstep(0.11, 0.0, dd) * (0.25 + 1.6 * b);
}

vec3 sun_disc(vec3 d, vec3 dir, vec3 col, float size, float amt) {
	float c = dot(d, normalize(dir));
	float ang = acos(clamp(c, -1.0, 1.0));
	float r = 0.0046 * size;   // Verdance's primary is ~0.53 deg wide
	float disc = 1.0 - smoothstep(r * 0.8, r, ang);
	// Thin halo only (owner: subtle glow).
	float halo = exp(-ang / (r * 2.2)) * 0.5 + exp(-ang / 0.06) * 0.06;
	return col * (disc * 18.0 + halo * 1.6) * amt;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float el = d.y;
	float dayk = clamp(day, 0.0, 1.0);
	// Thin atmosphere: almost black above, a narrow lit band at the horizon.
	float band = exp(-max(el, 0.0) * 9.0);
	vec3 hz = mix(horizon_col, horizon_col * vec3(1.25, 1.0, 0.82), warmth);
	vec3 col = mix(mix(night_zenith, zenith_col, dayk), mix(night_horizon, hz, dayk), band);
	// Ice-crystal haze: a pale veil low down (thicker while the moon is ruined).
	col += vec3(0.5, 0.6, 0.72) * exp(-max(el, 0.0) * 22.0) * (0.04 + 0.08 * haze) * (0.25 + dayk);
	// Glow around the primary sun in the thin air.
	vec3 sa = normalize(sun_a_dir);
	float sc = max(dot(d, sa), 0.0);
	col += sun_a_col * pow(sc, 60.0) * 0.12 * (0.3 + 0.7 * dayk) * step(-0.05, sa.y);
	if (el < 0.0) {
		col = mix(col, night_horizon * 0.6 + horizon_col * 0.15 * dayk, smoothstep(0.0, -0.08, el));
	}
	float occl = 0.0;   // 1 where the giant (or its rings) hides what is behind
	vec3 front = vec3(0.0);
	// --- Gas giant ----------------------------------------------------------------------
	vec3 gc = normalize(giant_dir);
	vec3 pole = normalize(giant_pole);
	float b = dot(d, gc);
	float disc_ = b * b - (1.0 - giant_r * giant_r);
	float t_planet = 1e9;
	vec3 L = normalize(sa + normalize(sun_b_dir) * 0.1);
	if (disc_ > 0.0 && b > 0.0) {
		t_planet = b - sqrt(disc_);
		vec3 hp = d * t_planet;
		vec3 n = normalize(hp - gc);
		float lat = dot(n, pole);
		vec3 ex = normalize(cross(pole, vec3(0.0, 0.0, 1.0)));
		vec3 ey = cross(pole, ex);
		float lon = atan(dot(n, ey), dot(n, ex));
		float turb = fbm(vec2(lon * 2.0, lat * 14.0)) - 0.5;
		float bands = lat * 9.0 + turb * 0.9 + sin(lat * 31.0 + turb * 3.0) * 0.12;
		float k1 = 0.5 + 0.5 * sin(bands * 3.1);
		float k2 = 0.5 + 0.5 * sin(bands * 1.3 + 1.7);
		vec3 alb = mix(mix(band_a, band_b, k1), band_c, k2 * 0.45);
		alb *= 0.85 + 0.3 * fbm(vec2(lon * 7.0, lat * 40.0));
		// A pale storm oval.
		vec2 so = vec2(lon - 0.6, (lat + 0.32) * 3.0);
		alb = mix(alb, vec3(0.95, 0.9, 0.82), smoothstep(0.32, 0.18, length(so)) * 0.6);
		float ndl = dot(n, L);
		float lit = smoothstep(-0.08, 0.35, ndl);
		float limb = pow(clamp(dot(n, -d), 0.0, 1.0), 0.35);
		vec3 lc = alb * lit * limb * 0.62;
		lc += alb * 0.04;   // faint night side (ringshine)
		// Thin bright atmosphere rim on the lit side.
		lc += vec3(0.7, 0.82, 1.0) * pow(1.0 - clamp(dot(n, -d), 0.0, 1.0), 6.0) * smoothstep(-0.2, 0.4, ndl) * 0.35;
		front = lc;
		occl = 1.0;
		// Its edge melts a little into the horizon haze (it is far beyond the air).
		front = mix(front, col, exp(-max(el, 0.0) * 40.0) * 0.35);
		front = mix(front, col + horizon_col * 0.1 * dayk, giant_fade);
	}
	// --- Rings ---------------------------------------------------------------------------
	// The giant is far away: rays near it are treated as parallel (gnomonic offset v from its
	// centre), so the ring is a clean tilted ellipse instead of sweeping over the viewer.
	float gdot = dot(d, gc);
	float pg = dot(gc, pole);
	if (gdot > 0.2 && abs(pg) > 0.02) {
		vec3 v = d / gdot - gc;
		float s = -dot(v, pole) / pg;
		vec3 toq = v + gc * s;
		float rr = length(toq) / giant_r;
		if (rr > ring_in && rr < ring_out) {
			float u = (rr - ring_in) / (ring_out - ring_in);
			float dens = 0.55 + 0.45 * sin(u * 61.0) * sin(u * 23.0 + 1.0);
			dens *= smoothstep(0.0, 0.04, u) * smoothstep(1.0, 0.93, u);
			dens *= 1.0 - smoothstep(0.52, 0.55, u) * smoothstep(0.6, 0.57, u) * 0.92;   // the gap
			dens = clamp(dens * (0.6 + 0.4 * vnoise(vec2(u * 160.0, 0.5))), 0.0, 1.0) * 0.85;
			// Planet shadow on the rings (cast away from the suns).
			float along = dot(toq, L);
			float perp = length(toq - L * along);
			float shadow = (along < 0.0 && perp < giant_r) ? 0.08 : 1.0;
			float ringlit = 0.35 + 0.65 * abs(dot(L, pole));
			vec3 rc = mix(vec3(0.82, 0.76, 0.66), vec3(0.62, 0.7, 0.74), u) * (0.6 * shadow * ringlit + 0.02);
			float vv = dot(v, v);
			float s_front = -sqrt(max(giant_r * giant_r - vv, 0.0));
			bool on_planet = vv < giant_r * giant_r;
			if (!on_planet || s < s_front) {
				front = mix(front, rc, dens);
				occl = max(occl, dens);
			}
		}
	}
	// --- Stars, suns, aurora (behind the giant) ------------------------------------------
	vec3 back = vec3(0.0);
	if (!AT_CUBEMAP_PASS) {
		float sk = mix(1.0, stars_day, dayk) * smoothstep(-0.02, 0.12, el);
		float s1 = stars(d, 190.0, 0.08);
		float s2 = stars(d, 420.0, 0.05) * 0.55;
		// A faint galactic band.
		float mw = exp(-pow(dot(d, normalize(vec3(0.3, 0.4, -0.86))) * 3.2, 2.0));
		float s3 = stars(d, 700.0, 0.12) * mw * 0.5;
		vec3 sc3 = vec3(0.85, 0.9, 1.0);
		back += sc3 * (s1 + s2 + s3) * sk * 0.9;
		back += vec3(0.05, 0.06, 0.09) * mw * fbm(d.xz * 9.0 + d.y * 3.0) * 0.25 * (1.0 - dayk * 0.7) * smoothstep(0.0, 0.2, el);
		if (aurora > 0.001 && dayk < 0.95) {
			float az = atan(d.x, -d.z);
			float base = 0.08 + 0.06 * sin(az * 2.0 + TIME * 0.02) + 0.04 * fbm(vec2(az * 3.0, TIME * 0.015));
			float hgt = el - base;
			float curtain = fbm(vec2(az * 9.0 + TIME * 0.03, TIME * 0.01));
			float rays = 0.55 + 0.45 * sin(az * 140.0 + curtain * 18.0);
			float prof = smoothstep(0.0, 0.03, hgt) * exp(-max(hgt, 0.0) * 6.5);
			float mask = smoothstep(0.35, 0.75, curtain) * prof * rays;
			vec3 ac = mix(aurora_lo, aurora_hi, smoothstep(0.02, 0.28, hgt));
			back += ac * mask * aurora * (1.0 - dayk) * 0.22;
		}
	}
	back += sun_disc(d, sun_a_dir, sun_a_col, sun_a_size, 1.0) * step(-0.02, sa.y);
	back += sun_disc(d, sun_b_dir, sun_b_col, sun_b_size, sun_b_amt * 2.0) * step(-0.02, normalize(sun_b_dir).y);
	col += back * (1.0 - occl);
	col = mix(col, front, occl);
	COLOR = col;
}
