shader_type spatial;
// [orbD] Lake surface on the walkable globe (planet/sites/sphere_water.gd), one mesh per water cell.
// [v4world] Owner playtest 3 #53 ("the water still doesn't look like water": flat light-cyan or dull
// blue slabs). Rewritten so it reads as water and looks the same on every renderer:
//  - body: a dark blue-green that deepens away from the shore (vertex COLOR.g: 0 at the bank,
//    1 a few cells out), lighter and see-through over the shallows (COLOR.r: 1 at the waterline);
//    cloudy green-blue and nearly opaque before cleaning, clear after (`clarity`, per cell);
//  - waves: a sum of travelling sine waves in WORLD space (seamless across cells, no texture),
//    bending the normal; calmer and oilier while polluted;
//  - the sky: our own fresnel reflection of the sky's zenith/horizon colours and sun glints
//    (uniforms fed each moment from the sky material by SphereWater), added as emission. The
//    renderer's own reflection is off (SPECULAR 0): on opengl3 its radiance probe mirrored the pale
//    horizon and the lakes read as grey or cyan slabs, unlike Forward+;
//  - soft foam along the waterline, dirty scum before cleaning.
render_mode blend_mix, depth_draw_always, cull_back, diffuse_lambert, specular_disabled;

instance uniform float clarity = 0.0;
uniform vec3 sky_zen : source_color = vec3(0.18, 0.38, 0.75);
uniform vec3 sky_hor : source_color = vec3(0.62, 0.66, 0.66);
uniform float sky_day = 1.0;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_col : source_color = vec3(1.0, 0.95, 0.85);
uniform float sun_vis = 1.0;

const vec3 CLEAR_DEEP = vec3(0.008, 0.05, 0.07);
const vec3 CLEAR_SHALLOW = vec3(0.03, 0.16, 0.15);
// Dirty water is a cloudy algae green-teal (greener and paler than the clean deep blue), not olive mud: the scum, film and floating junk say "polluted".
const vec3 MURKY_DEEP = vec3(0.045, 0.1, 0.075);
const vec3 MURKY_SHALLOW = vec3(0.09, 0.17, 0.115);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.11, 0.17, 0.13));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// Gradient of the wave height field (world space). calm: 0 crisp .. 1 sluggish (polluted).
vec3 wave_grad(vec3 p, float t, float calm) {
	vec3 g = vec3(0.0);
	// direction (any 3D: its part along the ground sets the heading), wavelength m, slope
	vec3 D[7] = vec3[](vec3(0.71, 0.12, 0.69), vec3(-0.35, 0.62, 0.70), vec3(0.88, -0.45, 0.15),
		vec3(-0.6, -0.5, 0.62), vec3(0.2, 0.93, -0.3), vec3(0.55, 0.4, -0.73), vec3(-0.82, 0.21, -0.53));
	float L[7] = float[](9.0, 5.7, 3.4, 2.1, 1.3, 0.83, 0.53);
	float S[7] = float[](0.05, 0.05, 0.045, 0.04, 0.035, 0.028, 0.02);
	for (int i = 0; i < 7; i++) {
		float k = 6.2831853 / L[i];
		float sp = sqrt(9.8 / k) * mix(1.0, 0.45, calm);
		float ph = dot(p, D[i]) * k - t * sp * k + float(i) * 1.7;
		float a = S[i] * mix(1.0, i < 3 ? 0.7 : 0.25, calm);  // polluted water: the small ripples die
		g += D[i] * a * cos(ph);
	}
	return g;
}

void fragment() {
	float c = clamp(clarity, 0.0, 1.0);
	float shore = COLOR.r;
	float deep = COLOR.g;
	vec3 up = normalize(wpos);
	vec3 g = wave_grad(wpos, TIME, 1.0 - c);
	// Irregular chop on top (value noise, finite differences along the ground): the sines alone
	// lined the sun's glitter up in stripes.
	vec3 tx = normalize(cross(up, vec3(0.0, 0.0, 1.0) + up.yzx * 0.1));
	vec3 tz = cross(tx, up);
	vec3 q = wpos * 1.1 + vec3(TIME * 0.21, TIME * 0.17, -TIME * 0.19);
	float n0 = vnoise(q);
	g += (tx * (vnoise(q + tx * 0.35) - n0) + tz * (vnoise(q + tz * 0.35) - n0)) * mix(0.12, 0.3, c);
	g -= up * dot(g, up);
	vec3 nw = normalize(up - g);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	vec3 vw = normalize(CAMERA_POSITION_WORLD - wpos);
	float ndv = clamp(dot(nw, vw), 0.0, 1.0);
	float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);

	// Body: shallow -> deep, murky -> clear.
	vec3 shallow = mix(MURKY_SHALLOW, CLEAR_SHALLOW, c);
	vec3 deep_c = mix(MURKY_DEEP, CLEAR_DEEP, c);
	vec3 col = mix(shallow, deep_c, smoothstep(0.0, 1.0, deep));
	// Polluted: blotchy scum and an oily brown film drifting on the surface.
	float scum = smoothstep(0.5, 0.85, vnoise(wpos * 0.6 + vec3(TIME * 0.03, 0.0, TIME * 0.02))) * (1.0 - c);
	col = mix(col, vec3(0.12, 0.11, 0.06), scum * 0.4);
	// Foam along the waterline: a soft band that breathes with the waves.
	float fn = vnoise(wpos * 1.7 + vec3(0.0, TIME * 0.25, 0.0));
	float foam = smoothstep(0.62, 0.95, shore + (fn - 0.5) * 0.35 + 0.06 * sin(TIME * 1.3 + dot(wpos, vec3(0.4, 0.3, 0.5))));
	vec3 foam_c = mix(vec3(0.42, 0.39, 0.3), vec3(0.78, 0.85, 0.84), c);
	ALBEDO = mix(col, foam_c, foam * mix(0.5, 0.6, c));
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;

	// The sky in the water (our own, so every renderer shows the same): zenith overhead, the
	// horizon colour at grazing angles, dimmed by night; murky water mirrors less.
	vec3 rv = reflect(-vw, nw);
	float el = clamp(dot(rv, up), 0.0, 1.0);
	vec3 sky = mix(sky_hor, sky_zen, 0.3 + 0.7 * smoothstep(0.0, 0.45, el));  // blue-leaning: the dusty horizon alone read as concrete
	float refl = min(fres, 0.6) * mix(0.55, 0.62, c) * (1.0 - foam * 0.8);
	vec3 em = sky * refl * mix(0.25, 1.0, sky_day);
	// Sun glints on the wave facets (and a broad sheen), only with the sun up.
	vec3 h = normalize(sun_dir + vw);
	float nh = clamp(dot(nw, h), 0.0, 1.0);
	float glint = pow(nh, mix(140.0, 600.0, c)) * mix(0.3, 4.0, c) + pow(nh, 60.0) * mix(0.05, 0.12, c);
	em += sun_col * glint * sun_vis * (1.0 - foam);
	EMISSION = em;

	// See-through over the shallows once it is clean; murky water stays nearly opaque.
	float a_sh = mix(0.86, 0.42, c);
	float a_dp = mix(0.97, 0.9, c);
	ALPHA = clamp(mix(a_sh, a_dp, smoothstep(0.0, 0.7, deep)) + fres * 0.25 + foam * 0.4, 0.0, 1.0);
}
