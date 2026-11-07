shader_type spatial;
// [worlds2] A body in a Cradle Mode world's sky (planet/sky_body.gd): a big moon, a ringed gas
// giant or a shattered moon with a debris ring, drawn on a camera-facing quad far out. Lit from
// the sun side with a soft terminator, a thin atmosphere rim, and washed toward the sky by day
// (a daytime moon is pale, not pasted on).
render_mode unshaded, fog_disabled, depth_draw_never, cull_disabled, blend_mix, shadows_disabled;

uniform vec4 body_col : source_color = vec4(0.86, 0.82, 0.72, 1.0);
uniform vec4 band_col : source_color = vec4(0.6, 0.68, 0.76, 1.0);
uniform vec4 ring_col : source_color = vec4(0.92, 0.9, 0.84, 1.0);
uniform float ring = 0.0;        // 1 = rings
uniform float grain = 0.0;       // 1 = a ring of debris (shattered moon), cracks on the disc
uniform float bands = 0.0;       // 1 = gas giant bands, 0 = craters
uniform float disc_r = 0.3;      // disc radius in quad units (quad spans -1..1)
uniform float tilt = 0.32;       // ring tilt (radians)
uniform vec2 light_dir = vec2(-0.55, 0.45);
uniform float day = 1.0;         // 1 = full daylight (pale), 0 = night
uniform float opacity = 0.9;
uniform float seed = 1.0;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21) + seed);
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
	return vnoise(p) * 0.55 + vnoise(p * 2.1) * 0.28 + vnoise(p * 4.3) * 0.17;
}

void fragment() {
	vec2 p = (UV * 2.0 - 1.0) * vec2(1.0, -1.0);
	float d = length(p) / disc_r;
	vec3 col = vec3(0.0);
	float a = 0.0;
	float litv = 1.0;
	// Disc: a sphere normal, lambert from the sun side, a soft terminator.
	if (d < 1.0) {
		vec3 n = vec3(p / disc_r, sqrt(max(1.0 - d * d, 0.0)));
		vec3 l = normalize(vec3(light_dir, 0.55));
		float lit = smoothstep(-0.12, 0.35, dot(n, l));
		vec3 surf;
		if (bands > 0.5) {
			float y = n.y + 0.06 * fbm(n.xy * vec2(3.0, 9.0));
			float b = 0.5 + 0.5 * sin(y * 15.0 + 2.0 * fbm(n.xy * 4.0));
			surf = mix(body_col.rgb, band_col.rgb, b * 0.7);
		} else {
			float cr = fbm(n.xy * 5.0 + seed);
			float maria = smoothstep(0.45, 0.7, fbm(n.xy * 1.6 + 3.0));
			surf = mix(body_col.rgb, band_col.rgb, maria * 0.75) * (0.85 + 0.3 * cr);
			if (grain > 0.5) {
				float crack = smoothstep(0.03, 0.0, abs(fbm(n.xy * 3.0 + 7.0) - 0.5));
				surf *= 1.0 - 0.6 * crack;
			}
		}
		col = surf * (0.04 + 0.96 * lit);
		litv = lit;
		a = smoothstep(1.0, 0.985, d);
		// Thin atmosphere rim on the lit side (gas giants and the big moons only: barely there).
		col += body_col.rgb * 0.18 * smoothstep(0.82, 1.0, d) * lit;
	}
	// Rings: an ellipse in the tilted frame; the near half passes in front of the disc.
	if (ring > 0.5) {
		float cs = cos(tilt);
		float sn = sin(tilt);
		vec2 q = vec2(cs * p.x + sn * p.y, -sn * p.x + cs * p.y);
		vec2 e = vec2(q.x, q.y / 0.2) / disc_r;
		float rr = length(e);
		float band = smoothstep(1.3, 1.36, rr) * smoothstep(2.25, 2.1, rr);
		float gaps = 0.65 + 0.35 * sin(rr * 38.0) * sin(rr * 11.0 + 1.0);
		if (grain > 0.5) {
			gaps = step(0.62, h21(floor(e * 46.0))) * (0.6 + 0.4 * vnoise(e * 9.0));
			band = smoothstep(1.15, 1.3, rr) * smoothstep(2.6, 2.0, rr);
		}
		float ra = band * gaps * 0.85;
		bool behind = q.y > 0.0 && d < 1.0;
		if (!behind && ra > 0.0) {
			// The planet's shadow falls across the far side of the ring.
			float lit_r = 0.55 + 0.45 * smoothstep(-0.3, 0.6, dot(normalize(q), normalize(light_dir)));
			col = mix(col, ring_col.rgb * lit_r, ra);
			a = max(a, ra);
			litv = max(litv, ra);
		}
	}
	// Daylight washes it pale and softer; at night it reads clearly.
	float wash = mix(0.5, 1.0, 1.0 - day);
	ALBEDO = mix(vec3(0.75, 0.82, 0.92) * 0.9, col, wash) * mix(1.0, 0.85, day);
	ALPHA = clamp(a * opacity * mix(0.72, 1.0, 1.0 - day) * mix(1.0, 0.2 + 0.8 * litv, day), 0.0, 1.0);
}
