shader_type spatial;
// [sgrid] Sphere ground (chunks and far shell). Each vertex carries its (noise-warped) owner cell
// in UV2.x; the per-cell state texture (SphereCells) gives junk left / state / biome, so cleaning
// a hex is one texel write and its border wanders. World-space triplanar texturing (works at any
// point of the sphere). Lifted from the orbit prototype's ground (planet/orbit/orbit_ground).

uniform sampler2D state_tex : filter_nearest;
uniform int state_w = 512;
uniform sampler2D tex_dirt : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_rubble : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_clean : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tex_scale = 0.22;
// [v7planet] Per-planet ground colour (data/planets.json look.ground, PlanetCfg.look): multipliers on
// the trashed ground, the cleaned ground and the grass. 1 = as is (Verdance).
uniform vec3 tint_dirt = vec3(1.0);
uniform vec3 tint_clean = vec3(1.0);
uniform vec3 tint_grass = vec3(1.0);
// 1 on the far shell: coarser texture, no fine detail (it is only seen from far away).
uniform float far_shell = 0.0;
// Debug: tint each LOD (0 = off).
uniform float lod_tint = 0.0;
uniform vec3 lod_color = vec3(1.0);
// [v4world] The sky the far water mirrors (SphereWater.sync_sky feeds these, as for the lake surface).
uniform vec3 sky_zen : source_color = vec3(0.18, 0.38, 0.75);
uniform vec3 sky_hor : source_color = vec3(0.62, 0.66, 0.66);
uniform float sky_day = 1.0;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_col : source_color = vec3(1.0, 0.95, 0.85);
uniform float sun_vis = 1.0;

varying vec4 st;
varying vec3 wpos;
varying vec3 wnrm;
varying float wet;
varying float verd;  // [v6life] how green a clean cell is (state_tex R on clean land; junk left on junk and water)

void vertex() {
	int idx = int(UV2.x + 0.5);
	st = texelFetch(state_tex, ivec2(idx % state_w, idx / state_w), 0);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wet = UV2.y;
	// [v6life] Split R per vertex (junk on junk and water cells, green on clean ones), so the two
	// never blend into each other across a cell border.
	float s_id = floor(st.g * 255.0 / 36.0 + 0.5);
	bool junky = s_id < 0.5 || s_id > 4.5;
	verd = junky ? 0.0 : st.r;
	st.r = junky ? st.r : 0.0;
}

// [v6life] The grass mask: integer-hash value noise, the same on the CPU (CellVerdure.mask), so
// the tufts stand in the green patches.
float vhash(ivec3 c) {
	uint h = (uint(c.x + 4096) * 73856093u) ^ (uint(c.y + 4096) * 19349663u) ^ (uint(c.z + 4096) * 83492791u);
	h ^= h >> 13u;
	h *= 1274126177u;
	h ^= h >> 16u;
	return float(h & 0xffffu) / 65535.0;
}

float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = p - i;
	f = f * f * (3.0 - 2.0 * f);
	ivec3 c = ivec3(i);
	float a = mix(mix(vhash(c), vhash(c + ivec3(1, 0, 0)), f.x), mix(vhash(c + ivec3(0, 1, 0)), vhash(c + ivec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(vhash(c + ivec3(0, 0, 1)), vhash(c + ivec3(1, 0, 1)), f.x), mix(vhash(c + ivec3(0, 1, 1)), vhash(c + ivec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

float verd_mask(vec3 p) {
	return vnoise3(p * 0.11) * 0.7 + vnoise3(p * 0.47) * 0.3;
}

vec3 tri(sampler2D t, vec3 p, vec3 w) {
	return texture(t, p.yz).rgb * w.x + texture(t, p.xz).rgb * w.y + texture(t, p.xy).rgb * w.z;
}

void fragment() {
	vec3 w = pow(abs(wnrm), vec3(4.0));
	w /= dot(w, vec3(1.0));
	float sc = mix(tex_scale, tex_scale * 0.02, far_shell);
	vec3 p = wpos * sc;
	float junk = st.r;
	float state = floor(st.g * 255.0 / 36.0 + 0.5);
	float biome = floor(st.b * 255.0 / 17.0 + 0.5);
	float n = dot(tri(tex_rubble, wpos * mix(0.031, 0.002, far_shell), w), vec3(0.33));
	float dirty = smoothstep(0.38, 0.62, junk + (n - 0.45) * 0.7);
	vec3 dirt = mix(tri(tex_dirt, p, w), tri(tex_rubble, p * 1.3, w), 0.55) * vec3(0.6, 0.53, 0.46);  // [v1world] grimier (was 0.78, 0.7, 0.62): trashed ground reads dark, as on the flat field
	// [v1world] Past the litter carpet's reach the junk ground still reads as trash: bags, rust and
	// paper mottled from the rubble texture (mipmapped, so stable far off), fading in with distance.
	float far_k = far_shell > 0.5 ? 1.0 : smoothstep(45.0, 95.0, length(VERTEX));
	float tl = dot(tri(tex_rubble, wpos * 0.09, w), vec3(0.333));
	float tl2 = dot(tri(tex_rubble, wpos * 0.23 + 3.7, w), vec3(0.333));
	vec3 trash = mix(vec3(0.07, 0.07, 0.08), vec3(0.4, 0.31, 0.22), smoothstep(0.3, 0.46, tl));
	trash = mix(trash, vec3(0.74, 0.7, 0.6), smoothstep(0.52, 0.62, tl2) * 0.85);
	dirt = mix(dirt, trash, far_k * 0.7) * tint_dirt;
	vec3 clean = tri(tex_clean, p, w) * vec3(0.95, 0.93, 0.9) * tint_clean;
	vec3 grass = tri(tex_grass, p * 0.8, w) * vec3(0.85, 1.0, 0.8) * tint_grass;
	float green = smoothstep(1.5, 2.5, state + (n - 0.45));
	// [v6life] Clean ground greens over time (plants/cell_verdure.gd): grass creeps in from patches
	// (a soft low-frequency mask, finer breakup near), thin and yellow-green at its edge, with moss
	// darkening the soil just ahead of it. The tufts and flowers are CellVerdure's.
	float gcov = 0.0;
	vec3 gcol = grass;
	if (verd > 0.004) {
		float dist = length(VERTEX);
		float near_k = 1.0 - smoothstep(110.0, 200.0, dist);
		float m = verd_mask(wpos);
		float k = verd * 1.5 - 0.05 - m;
		gcov = mix(smoothstep(0.2, 0.75, verd * 1.5 - 0.05), smoothstep(-0.03, 0.09, k), near_k);
		// Our own greens over the grass texture's light and dark (the texture itself is a dry yellow).
		float gl = dot(grass, vec3(0.3, 0.5, 0.2));
		float lush = smoothstep(0.02, 0.3, k) * smoothstep(0.3, 0.9, verd);
		gcol = mix(vec3(0.3, 0.4, 0.13), vec3(0.11, 0.27, 0.07), lush) * (0.35 + 1.6 * gl) * (0.8 + 0.5 * n) * tint_grass;
		// [v7look] Break the lawn up (it rendered as one flat lime carpet, which the owner has rejected
		// before): darker clumps and sunlit dry tips at two scales, a little warmer where it is thin.
		float clump = vnoise3(wpos * 1.9) * 0.6 + vnoise3(wpos * 5.3) * 0.4;
		float fine = vnoise3(wpos * 13.0);
		gcol *= mix(0.55, 1.15, clump) * mix(0.85, 1.08, fine) * 0.9;
		gcol = mix(gcol, gcol * vec3(1.3, 1.12, 0.62), smoothstep(0.55, 0.85, clump) * (1.0 - lush * 0.3));
		clean = mix(clean, clean * vec3(0.78, 0.86, 0.7), smoothstep(-0.25, 0.0, k) * (1.0 - gcov) * 0.7);
	}
	green = max(green, gcov);
	vec3 col = mix(mix(clean, gcol, green), dirt, dirty);
	// Biome tints (frost, dust, marsh) so regions read from orbit.
	if (abs(biome - 5.0) < 0.5) col = mix(col, vec3(0.86, 0.9, 0.95), 0.55);
	else if (abs(biome - 4.0) < 0.5) col *= vec3(1.12, 0.98, 0.8);
	else if (abs(biome - 3.0) < 0.5) col *= vec3(0.85, 0.95, 0.8);
	float water = far_shell > 0.5 ? step(4.5, state) : smoothstep(0.45, 0.8, wet);  // [v1world] chunks: smooth wetness (UV2.y), not the warped owner's state
	// [v1world] Shore: land near a lake turns to damp mud over the bank (clean shore cells were pale concrete strips).
	float bank = far_shell > 0.5 ? 0.0 : smoothstep(0.04, 0.5, wet);
	col = mix(col, dirt * vec3(0.72, 0.66, 0.58), bank * 0.85);
	col = mix(col, col * 0.42 + vec3(0.015, 0.03, 0.035), water);  // [v1world] wet mud on banks and beds (was a flat blue)
	// [v3city] Open water past the near ring, where SphereWater lays no lake surface (QA: the far
	// lake read as a flat grey plane): murky green-teal, clearer as it is cleaned, slow ripple
	// mottling and a sky sheen toward grazing angles. Near the camera the lake surface covers it.
	float open_k = far_shell > 0.5 ? 1.0 : smoothstep(50.0, 75.0, length(VERTEX));
	float ow = water * open_k;
	// [v4world] Owner playtest 3 #53: the far water as the lake surface (sphere_water.gdshader):
	// dark olive-brown murky water, deep blue-green once clean, slow swell and ripple mottling, our
	// own fresnel sky reflection (blue-leaning, capped so far lakes don't turn into pale slabs) and
	// sun glints; the renderer's own reflection is off over water (it read cyan on opengl3).
	vec3 wem = vec3(0.0);
	if (ow > 0.001) {
		vec3 up = normalize(wpos);
		float rip = dot(tri(tex_rubble, wpos * 0.045 + vec3(TIME * 0.01, 0.0, TIME * 0.007), w), vec3(0.333));
		float clear_w = 1.0 - smoothstep(0.1, 0.6, junk);
		vec3 wcol = mix(vec3(0.05, 0.058, 0.032), vec3(0.01, 0.055, 0.075), clear_w);  // murky olive -> deep blue-green
		wcol *= mix(0.85, 1.12, smoothstep(0.35, 0.65, rip));
		vec3 g = vec3(0.0);
		g += vec3(0.71, 0.12, 0.69) * 0.05 * cos(dot(wpos, vec3(0.71, 0.12, 0.69)) * 0.7 - TIME * 0.9);
		g += vec3(-0.35, 0.62, 0.70) * 0.05 * cos(dot(wpos, vec3(-0.35, 0.62, 0.70)) * 1.1 - TIME * 1.2);
		g += vec3(0.88, -0.45, 0.15) * 0.04 * cos(dot(wpos, vec3(0.88, -0.45, 0.15)) * 1.9 - TIME * 1.6);
		g += (vec3(rip) - 0.5) * 0.12;
		g -= up * dot(g, up);
		vec3 nw = normalize(up - g * mix(0.6, 1.0, clear_w));
		vec3 vw = normalize(CAMERA_POSITION_WORLD - wpos);
		float fres = 0.02 + 0.98 * pow(1.0 - clamp(dot(nw, vw), 0.0, 1.0), 5.0);
		vec3 rv = reflect(-vw, nw);
		vec3 sky = mix(sky_hor, sky_zen, 0.3 + 0.7 * smoothstep(0.0, 0.45, clamp(dot(rv, up), 0.0, 1.0)));
		wem = sky * min(fres, 0.55) * mix(0.32, 0.6, clear_w) * mix(0.25, 1.0, sky_day);
		vec3 hv = normalize(sun_dir + vw);
		float nh = clamp(dot(nw, hv), 0.0, 1.0);
		wem += sun_col * (pow(nh, mix(140.0, 700.0, clear_w)) * mix(0.25, 5.0, clear_w) + pow(nh, 50.0) * mix(0.04, 0.08, clear_w)) * sun_vis;
		col = mix(col, wcol, ow);
	}
	col = mix(col, col * lod_color, lod_tint);
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.95, 0.6, water), 1.0, ow);  // [v1world] was 0.12 / 0.6: glossy banks mirrored the sky as a white strip
	SPECULAR = mix(mix(0.35, 0.4, water), 0.0, ow);  // [v4world] open water: the sky is our own (wem)
	EMISSION = wem * ow;
}
