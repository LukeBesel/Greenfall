shader_type spatial;
// Shared PBR-ish material for the street dressing (awnings, sign boards, poles, frames, wires,
// plastic crates, barrels, pots). Base colour is vertex colour x instance colour (sRGB); vertex
// alpha picks the material class:
//   1.0 canvas (weave, sun-bleach, translucent)   0.5 painted steel (chips, rust, streaks)
//   0.25 plastic (scuffs, sheen)                  0.0 painted wood / board (grain, flaking)
// Everything gets triplanar grime from a real texture, rain streaks and ground splash dirt.
render_mode cull_disabled;
// [orbD] Site frame on a walkable globe (identity on the flat game): "world" maths run in the
// nearest hub site's local metres, y up on its pad (planet/sites/site_manager.gd).
global uniform mat4 site_inv;

uniform sampler2D grime_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grime_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float grime_scale = 0.6;

varying vec3 v_world;
varying vec3 v_wn;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	v_world = (site_inv * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((site_inv * MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 tri_sample(sampler2D t, vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z + 1e-4);
	return texture(t, p.zy).rgb * w.x + texture(t, p.xz).rgb * w.y + texture(t, p.xy).rgb * w.z;
}

void fragment() {
	vec3 base = pow(COLOR.rgb, vec3(2.2));
	float cls = COLOR.a;
	vec3 p = v_world * grime_scale;
	vec3 g = tri_sample(grime_tex, p, v_wn);
	float gl = dot(g, vec3(0.33));
	// Rain streaks run down vertical faces; dirt splashes up from the ground.
	float vert = 1.0 - abs(v_wn.y);
	float streak = noise(vec2((v_world.x + v_world.z) * 9.0, v_world.y * 0.6)) * vert;
	float splash = smoothstep(0.9, 0.0, v_world.y) * (0.6 + 0.4 * noise(v_world.xz * 6.0));
	float big = noise(v_world.xz * 0.7 + v_world.y * 0.5);
	vec3 dirt = vec3(0.16, 0.13, 0.1);
	vec3 col = base * mix(0.72, 1.08, gl);
	float rough = 0.85;
	float metal = 0.0;
	if (cls > 0.75) {
		// Canvas: weave, bleached toward grey-cream, dusty top.
		float weave = 0.92 + 0.08 * sin(v_world.x * 300.0 + v_world.z * 300.0) * sin(v_world.y * 300.0);
		col = mix(col, vec3(dot(col, vec3(0.33))) * 1.1 + 0.03, 0.18 + big * 0.12) * weave;
		col = mix(col, dirt, max(v_wn.y, 0.0) * 0.18 * gl);
		BACKLIGHT = col * 0.45;
		rough = 0.95;
	} else if (cls > 0.4) {
		// Painted steel: chipped paint showing rust underneath.
		float chip = smoothstep(0.62, 0.7, noise(v_world.xz * 3.0 + v_world.y * 3.0) * 0.7 + gl * 0.5);
		vec3 rust = vec3(0.3, 0.13, 0.05) * mix(0.6, 1.2, gl);
		col = mix(col, rust, chip);
		rough = mix(0.55, 0.9, chip);
		metal = mix(0.35, 0.1, chip);
	} else if (cls > 0.1) {
		// Plastic: sun-faded, scuffed, a little sheen.
		col = mix(col, vec3(dot(col, vec3(0.33))) + 0.04, 0.12 + 0.15 * big);
		col *= 1.0 - 0.15 * smoothstep(0.5, 0.9, noise(v_world.xz * 14.0 + v_world.y * 14.0));
		rough = 0.5 + gl * 0.25;
	} else {
		// Painted wood / board: grain and flaking.
		float grain = 0.9 + 0.1 * sin(v_world.y * 40.0 + noise(v_world.xz * 3.0) * 6.0);
		float flake = smoothstep(0.66, 0.72, noise(v_world.xy * 4.0 + v_world.zy * 4.0));
		col = mix(col * grain, g * 0.55, flake);
		rough = 0.9;
	}
	col = mix(col, dirt, clamp(streak * 0.35 + splash * 0.5, 0.0, 0.75));
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	NORMAL_MAP = tri_sample(grime_nrm, p * 1.7, v_wn);
	NORMAL_MAP_DEPTH = 0.6;
}
