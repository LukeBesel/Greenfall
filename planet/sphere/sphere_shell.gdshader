shader_type spatial;
// [orbit] Far shell as a hex map (SphereShell): one flat colour per big hex from the aggregated
// shares of its fine hexes (junk / cleaned / green / water), a per-biome palette, cities and hub
// sites, and a thin outline on every big hex that fades when the hexes get too small on screen.

uniform sampler2D shell_a : filter_nearest;
uniform sampler2D shell_b : filter_nearest;
uniform int shell_w = 512;
uniform sampler2D tex_noise : source_color, filter_linear_mipmap, repeat_enable;
uniform float outline = 0.38;
uniform float glow = 1.0;

varying flat vec4 sa;
varying flat vec4 sb;
varying vec3 wpos;
varying vec3 wnrm;

// Junk-covered ground per biome (PlanetData.BIOMES order).
const vec3 BIOME[12] = vec3[12](
	vec3(0.60, 0.30, 0.15),  // rustlands
	vec3(0.42, 0.39, 0.40),  // sprawl
	vec3(0.52, 0.28, 0.55),  // neon_coast
	vec3(0.42, 0.40, 0.20),  // fungal_marsh
	vec3(0.84, 0.64, 0.36),  // dust_dunes
	vec3(0.86, 0.90, 0.97),  // frostcap
	vec3(0.36, 0.30, 0.46),  // old_capital
	vec3(0.20, 0.30, 0.36),  // lake
	vec3(0.76, 0.60, 0.42),  // dust_flats
	vec3(0.70, 0.80, 0.90),  // frozen_port
	vec3(0.28, 0.44, 0.46),  // sunken_city
	vec3(0.56, 0.60, 0.38)   // cradle_landing
);

void vertex() {
	int idx = int(UV2.x + 0.5);
	ivec2 px = ivec2(idx % shell_w, idx / shell_w);
	sa = texelFetch(shell_a, px, 0);
	sb = texelFetch(shell_b, px, 0);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(VERTEX, 0.0)).xyz);
}

vec3 tri(sampler2D t, vec3 p, vec3 w) {
	return texture(t, p.yz).rgb * w.x + texture(t, p.xz).rgb * w.y + texture(t, p.xy).rgb * w.z;
}

void fragment() {
	float junk = sa.r;
	float clean = sa.g;
	float green = sa.b;
	float water = sa.a;
	int bi = clamp(int(sb.r * 255.0 / 17.0 + 0.5), 0, 11);
	float city = sb.g;
	float site = sb.b;
	float land = max(1.0 - water, 1e-3);

	vec3 w = pow(abs(wnrm), vec3(4.0));
	w /= dot(w, vec3(1.0));
	float n = dot(tri(tex_noise, wpos * 0.004, w), vec3(0.333));
	float n2 = dot(tri(tex_noise, wpos * 0.017, w), vec3(0.333));

	vec3 base = BIOME[bi];
	vec3 dirt = base * (0.92 + 0.25 * (n - 0.45));
	vec3 cleaned = mix(base, vec3(0.56, 0.54, 0.40), 0.7);  // fresh cleared soil
	// Greener the further it got: planted (light) -> restored (lush).
	float gl = green / land;
	vec3 grass = mix(vec3(0.50, 0.66, 0.26), vec3(0.14, 0.50, 0.20), smoothstep(0.3, 0.9, gl));
	grass *= 0.95 + 0.2 * (n2 - 0.45);
	vec3 urban = mix(vec3(0.22, 0.23, 0.33), vec3(0.38, 0.44, 0.62), clean / land);  // slate -> clean blue-grey
	urban *= 0.85 + 0.35 * step(0.5, fract(n2 * 9.0));  // block speckle
	vec3 ground = (dirt * junk + cleaned * clean + grass * green) / land;
	float cs = smoothstep(0.0, 0.4, city);
	ground = mix(ground, mix(urban, ground, 0.1 + 0.35 * gl), cs);
	vec3 sea = mix(vec3(0.07, 0.26, 0.44), vec3(0.11, 0.36, 0.52), n2);
	if (bi == 5 || bi == 9) sea = mix(sea, vec3(0.80, 0.88, 0.95), 0.6);  // frozen
	vec3 col = mix(ground, sea, smoothstep(0.25, 0.75, water));

	// Big-hex outline: UV.x is 1 at the hex centre and 0 on its rim.
	float e = UV.x;
	float fw = max(fwidth(e), 1e-4);
	float line = 1.0 - smoothstep(0.0, fw * 1.6, e);
	float fade = 1.0 - smoothstep(0.35, 0.8, fw);  // gone when a hex is only a couple of pixels
	float lw = min(line * fade * outline * (1.0 - 0.6 * water) * (1.0 + 1.4 * cs), 1.0);
	vec3 line_col = mix(col * 0.45, vec3(1.0, 0.72, 0.3), cs);
	line_col = mix(line_col, vec3(0.4, 0.95, 1.0), site);
	col = mix(col, line_col, lw);

	ALBEDO = col;
	ROUGHNESS = mix(0.92, 0.15, water);
	SPECULAR = mix(0.3, 0.65, water);
	// City lights (warm speckle) and hub sites (cyan) so both read from orbit.
	float lights = cs * smoothstep(0.55, 0.7, n2 + 0.15 * n) * (1.0 - 0.5 * gl);
	EMISSION = glow * (vec3(1.0, 0.68, 0.3) * (lights * 0.7 + cs * 0.04) + vec3(0.3, 0.9, 1.0) * site * 0.55);
}
