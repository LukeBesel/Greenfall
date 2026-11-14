shader_type spatial;
// Future layer light: glowing seams, strips, orbs and beacons (planet/future_layer.gd).
// Everything is one MultiMesh instance each; no script runs per instance per frame.
// Instance COLOR = hue (linear), INSTANCE_CUSTOM = (seed, kind, energy, born time).
// kind 0 = line with a data pulse flowing along it, 1 = calm line, 2 = bobbing orb,
// 3 = blinking beacon, 4 = drifting lantern (bob + sway), 5 = steady orb, 6 = floating line
// (pulse + a slow bob; pieces of one ring share a seed so they float together).
// Lines "draw in" from their start (unit box x = -0.5) when born; orbs swell in.
render_mode unshaded, cull_back, shadows_disabled;
// [orbD] Site frame on a walkable globe (identity on the flat game): "world" maths run in the
// nearest hub site's local metres, y up on its pad (planet/sites/site_manager.gd).
global uniform mat4 site_inv;

uniform float t_now = 0.0;       // the layer's clock (seconds), matches `born`
uniform float reveal_s = 1.1;    // how long a new piece takes to draw in
uniform float energy = 1.0;
uniform float pulse = 1.0;

varying float v_along;
varying float v_seed;
varying float v_kind;
varying float v_energy;
varying float v_born;
varying vec3 v_world;

void vertex() {
	v_along = VERTEX.x + 0.5;
	v_seed = INSTANCE_CUSTOM.r;
	v_kind = INSTANCE_CUSTOM.g;
	v_energy = INSTANCE_CUSTOM.b;
	v_born = INSTANCE_CUSTOM.a;
	float rv = clamp((t_now - v_born) / reveal_s, 0.0, 1.0);
	float sc = max(length(MODEL_MATRIX[1].xyz), 0.001);
	if (v_kind > 1.5 && v_kind < 2.5) {
		VERTEX *= smoothstep(0.0, 1.0, rv);
		VERTEX.y += sin(TIME * (0.7 + fract(v_seed * 7.1) * 0.6) + v_seed * 31.0) * 0.12 / sc;
	} else if (v_kind > 3.5 && v_kind < 4.5) {
		VERTEX *= smoothstep(0.0, 1.0, rv);
		float t = TIME * (0.5 + fract(v_seed * 3.3) * 0.5) + v_seed * 17.0;
		VERTEX += vec3(sin(t * 0.7) * 0.18, sin(t) * 0.22, cos(t * 0.6) * 0.18) / sc;
	} else if (v_kind > 5.5) {
		VERTEX.y += sin(TIME * 0.8 + v_seed * 13.0) * 0.18 / sc;
	} else if (v_kind > 2.5) {
		VERTEX *= smoothstep(0.0, 1.0, rv);  // beacons and steady orbs swell in
	}
	v_world = (site_inv * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float rv = clamp((t_now - v_born) / reveal_s, 0.0, 1.0);
	vec3 c = COLOR.rgb;
	float e = energy * v_energy;
	if (v_kind < 1.5 || v_kind > 5.5) {
		// Draw-in: discard past the reveal front, with a white-hot head while it travels.
		if (v_along > rv * 1.02) {
			discard;
		}
		float head = (1.0 - rv) * smoothstep(0.12, 0.0, rv - v_along);
		c = mix(c, vec3(1.0), head * 0.8);
		e *= 1.0 + head * 3.0;
		if (v_kind < 0.5 || v_kind > 5.5) {
			float ph = fract((v_world.x * 0.73 + v_world.z * 0.61 + v_world.y * 0.5) * 0.08 - TIME * 0.35 + v_seed);
			float p = smoothstep(0.93, 1.0, ph) * pulse;
			c = mix(c, vec3(1.0), p * 0.55);
			e *= 1.0 + p * 1.6;
		}
		e *= 0.92 + 0.08 * sin(TIME * 1.3 + v_seed * 11.0);
	} else if (v_kind < 2.5 || v_kind > 3.5) {
		e *= 0.85 + 0.15 * sin(TIME * 2.1 + v_seed * 23.0);
	} else {
		float b = fract(TIME * 0.55 + v_seed);
		e *= 0.35 + 1.4 * smoothstep(0.0, 0.05, b) * smoothstep(0.35, 0.1, b);
	}
	// Bright core facing the camera so tubes and orbs read round.
	float core = pow(clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.5);
	ALBEDO = mix(c, mix(c, vec3(1.0), 0.5), core * 0.6) * e;
}
