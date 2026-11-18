shader_type spatial;
// [green] Living ground cover (plants/meadow.gd): grass tufts, flower clumps and sprouts that
// grow out of the ground wherever the field's life texture says the soil is alive. Every instance
// is placed once; growth, coverage and the natural (warped) border are decided here from the same
// life / warp textures as ground_pbr.gdshader, so the meadow and the green ground always agree and
// nothing is rebuilt on the CPU as hexes come alive.
// INSTANCE_CUSTOM: x = coverage rank (0..1, lower appears first), y = hue jitter, z = palette pick,
// w = size jitter.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D warp_tex : filter_linear;
uniform float warp_size = 280.0;
uniform float warp_amp = 0.0;
uniform sampler2D life_tex : filter_linear;  // R life 0..1, G hex level / 5
uniform int grid_radius = 3;
uniform float hex_size = 10.0;
// 0 grass tufts, 1 flower clumps, 2 sprouts (planted soil), 3 clover / low leaves
uniform int kind = 0;
uniform float height_m = 0.5;
uniform float fade_start = 45.0;
uniform float fade_end = 70.0;
uniform float wind = 1.0;
uniform vec3 grass_tint = vec3(1.0);
uniform float density = 1.0;

varying vec3 v_col;
varying float v_tip;

const float SQRT3 = 1.7320508;

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

vec3 flower_col(float k) {
	// Meadow palette: warm white, butter yellow, coral pink, violet-blue, orange, magenta.
	if (k < 0.22) return vec3(0.92, 0.9, 0.82);
	if (k < 0.44) return vec3(1.0, 0.78, 0.12);
	if (k < 0.6) return vec3(0.98, 0.42, 0.52);
	if (k < 0.74) return vec3(0.48, 0.45, 0.95);
	if (k < 0.88) return vec3(1.0, 0.5, 0.12);
	return vec3(0.85, 0.25, 0.7);
}

void vertex() {
	vec3 o = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec2 p = o.xz;
	vec2 pw = p + texture(warp_tex, p / warp_size + 0.5).rg * warp_amp;
	vec2 qr = vec2((SQRT3 / 3.0 * pw.x - pw.y / 3.0) / hex_size, (2.0 / 3.0 * pw.y) / hex_size);
	float size = float(grid_radius * 2 + 1);
	vec4 lt = texture(life_tex, (qr + vec2(float(grid_radius)) + 0.5) / size);
	float life = lt.r;
	float lvl = lt.g * 5.0;
	float rank = INSTANCE_CUSTOM.x;
	float cov = 0.0;
	float grow = 0.0;
	if (kind == 0) {
		// Grass: first tufts at Growing, a closed sward by Sustained / Thriving.
		// Growing hexes fill in as patches (clumps around the plants), closing into a sward by
		// Sustained / Thriving.
		float patch = vnoise(p * 0.16 + 7.0) * 0.65 + vnoise(p * 0.5) * 0.35;
		cov = clamp(smoothstep(0.15, 0.95, life) * mix(0.35, 1.6, patch) + smoothstep(0.85, 1.0, life), 0.0, 1.0) * density;
		grow = 0.35 + 0.65 * smoothstep(0.2, 0.95, life);
	} else if (kind == 1) {
		// Flowers: a few on Growing hexes, drifts of them once Sustained, a carpet when Thriving.
		cov = (smoothstep(0.45, 0.9, life) * 0.25 + step(3.5, lvl) * 0.35 + step(4.5, lvl) * 0.4) * density;
		grow = 0.55 + 0.45 * smoothstep(0.5, 1.0, life);
	} else if (kind == 2) {
		// Sprouts: freshly planted soil; they give way to the sward as it closes.
		cov = smoothstep(0.01, 0.08, life) * (1.0 - smoothstep(0.45, 0.8, life)) * density;
		grow = 0.6 + 0.6 * smoothstep(0.0, 0.35, life);
	} else {
		cov = smoothstep(0.3, 0.85, life) * density;
		grow = 0.5 + 0.5 * smoothstep(0.4, 1.0, life);
	}
	// Each instance fades in over a short band of coverage, so a hex fills in tuft by tuft.
	float on = clamp((cov - rank) * 8.0, 0.0, 1.0);
	float d = distance(o, CAMERA_POSITION_WORLD);
	float fade = 1.0 - smoothstep(fade_start, fade_end, d);
	float s = on * grow * fade * (0.75 + 0.5 * INSTANCE_CUSTOM.w);
	v_tip = clamp(VERTEX.y, 0.0, 1.0);
	vec3 v = VERTEX * height_m;
	// Wind: tips sway, gusts roll across the meadow.
	float gust = sin(TIME * 0.9 + p.x * 0.11 + p.y * 0.07) * 0.5 + 0.5;
	float sway = (sin(TIME * 2.1 + p.x * 0.7 + p.y * 0.5) * 0.6 + gust * 0.8) * wind * v_tip * v_tip * 0.12 * height_m;
	v.x += sway;
	v.z += sway * 0.4;
	VERTEX = v * s;
	// Soft, sky-facing normals: tufts light like a lawn rather than as single blades.
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.65));
	// Colours.
	float hue = INSTANCE_CUSTOM.y;
	vec3 deep = vec3(0.045, 0.14, 0.025);
	vec3 fresh = vec3(0.12, 0.3, 0.05);
	vec3 sun = vec3(0.24, 0.38, 0.07);
	vec3 base = mix(deep, fresh, hue);
	vec3 tip = mix(fresh, sun, hue * 0.7 + 0.15);
	if (kind == 2) {
		base = vec3(0.14, 0.3, 0.06);
		tip = vec3(0.42, 0.66, 0.18);
	}
	v_col = mix(base, tip, v_tip) * grass_tint;
	if (kind == 1 && COLOR.r > 0.5) {
		// Flower heads are painted red in the mesh: swap in the palette colour.
		v_col = flower_col(INSTANCE_CUSTOM.z) * mix(0.85, 1.0, hue);
	}
	if (kind == 3) {
		v_col = mix(vec3(0.07, 0.2, 0.05), vec3(0.16, 0.36, 0.08), hue) * grass_tint;
		if (COLOR.r > 0.5) {
			v_col = vec3(0.95, 0.93, 0.88);
		}
	}
}

void fragment() {
	ALBEDO = v_col;
	ROUGHNESS = 0.78;
	SPECULAR = 0.25;
	AO = mix(0.55, 1.0, v_tip);
	AO_LIGHT_AFFECT = 0.5;
	BACKLIGHT = v_col * 0.35;
}
