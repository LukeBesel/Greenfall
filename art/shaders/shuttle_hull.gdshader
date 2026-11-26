shader_type spatial;
// [art5] Painted hull of the shuttle (art/models/shuttle): a used working craft, not a showroom
// model. Layers, each from the vertex colours baked by build_shuttle.py (R = ambient occlusion,
// G = convex edge, B = seam / cavity, A = grime: dirt from the ground up, soot by the nozzles):
// two-tone base with speckle, dark seams, grime in streaks that run down the hull, paint chipped
// to primer and bare alloy on edges, roughness that follows all of it, a thin clearcoat left only
// where the paint is clean. Uniform names match ship_paint.gdshader (ShipModel sets them).
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 paint_color : source_color = vec4(0.93, 0.93, 0.91, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.42;
uniform float metallic : hint_range(0.0, 1.0) = 0.05;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.9;
uniform float seam_dark : hint_range(0.0, 1.0) = 0.7;
uniform float edge_light : hint_range(0.0, 1.0) = 0.2;
uniform float pearl : hint_range(0.0, 1.0) = 0.1;
uniform float flake : hint_range(0.0, 1.0) = 0.2;
uniform float edge_wear : hint_range(0.0, 1.0) = 0.8;
uniform float grime : hint_range(0.0, 1.5) = 1.0;
uniform float clearcoat_amt : hint_range(0.0, 1.0) = 0.3;
uniform vec4 grime_color : source_color = vec4(0.16, 0.125, 0.095, 1.0);
uniform vec4 primer_color : source_color = vec4(0.47, 0.33, 0.24, 1.0);
uniform vec4 rim_color : source_color = vec4(0.62, 0.85, 1.0, 1.0);
uniform float rim_strength = 0.02;

varying vec3 opos;

float h31(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float n3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h31(i), h31(i + vec3(1, 0, 0)), f.x), mix(h31(i + vec3(0, 1, 0)), h31(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(h31(i + vec3(0, 0, 1)), h31(i + vec3(1, 0, 1)), f.x), mix(h31(i + vec3(0, 1, 1)), h31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	opos = VERTEX;
}

void fragment() {
	float ao = COLOR.r;
	float edge = COLOR.g;
	float cav = COLOR.b;
	float dirt_v = COLOR.a;
	// 1 base: two tones over big patches, then a narrow speckle.
	float tone = n3(opos * 1.3) * 0.65 + n3(opos * 4.1) * 0.35;
	vec3 c = paint_color.rgb * mix(0.86, 1.0, tone);
	c *= mix(0.94, 1.03, n3(opos * 38.0));
	// sun-faded and chalky on top faces is left to the light; a faint pearl stays for the Locker looks.
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	c = mix(c, c * vec3(0.95, 0.98, 1.04), (1.0 - facing) * pearl);
	// 2 seams and cavities.
	float seam = smoothstep(0.12, 0.6, cav);
	c = mix(c, c * 0.22, seam * seam_dark);
	// 3 grime: streaks that run down (noise stretched along Y), thicker low on the hull and by the nozzles;
	// a little creeps out of every seam.
	float streak = n3(vec3(opos.x * 9.0, opos.y * 0.9, opos.z * 9.0)) * 0.6 + n3(vec3(opos.x * 23.0, opos.y * 2.0, opos.z * 23.0)) * 0.4;
	float blot = n3(opos * 2.6 + 7.0);
	float g = clamp(dirt_v * (0.55 + 0.9 * streak) + (blot - 0.62) * 0.5 + cav * 0.25, 0.0, 1.0) * grime;
	g = smoothstep(0.12, 0.85, g);
	c = mix(c, grime_color.rgb * mix(0.7, 1.15, streak), g * 0.78);
	// 4 wear: paint chipped on convex edges, primer first, bare alloy at the very edge.
	float chip_n = n3(opos * 31.0) * 0.6 + n3(opos * 87.0) * 0.4;
	float chip = smoothstep(0.52, 0.72, edge * edge_wear + (chip_n - 0.5) * 0.55 * edge_wear + (blot - 0.5) * 0.12);
	float bare = smoothstep(0.78, 0.95, edge * edge_wear + (chip_n - 0.5) * 0.5 * edge_wear);
	// scattered small chips on open panels (stone hits, boots, tools)
	float pit = smoothstep(0.865, 0.9, n3(opos * 55.0)) * smoothstep(0.45, 0.65, n3(opos * 3.3 + 3.0)) * edge_wear;
	chip = max(chip, pit);
	c = mix(c, primer_color.rgb, chip * 0.85);
	c = mix(c, vec3(0.5, 0.51, 0.53), bare);
	c = mix(c, min(c * 1.06 + 0.01, vec3(1.0)), edge * edge_light * (1.0 - chip));
	ALBEDO = c;
	float fl = n3(opos * 220.0);
	ROUGHNESS = clamp(roughness + (fl - 0.5) * 0.08 * flake + (tone - 0.5) * 0.12 + g * 0.3 + chip * 0.18 - bare * 0.2 + cav * 0.2, 0.1, 1.0);
	METALLIC = mix(metallic, 0.9, bare);
	CLEARCOAT = clearcoat_amt * (1.0 - g) * (1.0 - chip);
	CLEARCOAT_ROUGHNESS = 0.18;
	AO = mix(1.0, ao, ao_strength);
	AO_LIGHT_AFFECT = 0.45;
	EMISSION = rim_color.rgb * pow(1.0 - facing, 3.0) * rim_strength * ao;
}
