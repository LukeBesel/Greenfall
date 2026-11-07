shader_type spatial;
// Neon tubes and string-light bulbs. Colour comes from the vertex/instance colour (sRGB), the
// glow from an HDR emission above the glow threshold. Flicker is computed here from TIME so no
// script runs per frame: a faint mains buzz on everything, a slow breathing, and drop-outs on
// tubes flagged as failing (UV.y = 1) or dead (UV.y = 2). Per-sign / per-bulb phase comes from
// UV.x (signs, merged meshes) or INSTANCE_ID (bulbs in a MultiMesh).
render_mode unshaded, cull_back;

uniform float energy = 4.0;
uniform float twinkle = 0.0;     // 0 = neon buzz, 1 = soft bulb twinkle
uniform bool instance_seed = false;

varying float v_seed;
varying float v_state;

float hash11(float x) {
	return fract(sin(x * 12.9898 + 4.1414) * 43758.5453);
}

void vertex() {
	v_seed = instance_seed ? float(INSTANCE_ID) * 0.6180339 + UV.x : UV.x;
	v_state = UV.y;
}

void fragment() {
	vec3 c = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
	float t = TIME;
	float s = v_seed;
	float buzz = 0.95 + 0.05 * sin(t * 113.0 + s * 41.0) * sin(t * 7.3 + s * 3.0);
	float breathe = 0.9 + 0.1 * sin(t * (0.6 + hash11(s) * 0.9) + s * 17.0);
	float k = floor(t * 9.0 + s * 13.0);
	float r = hash11(k + s * 7.77);
	float drop = 0.0;
	if (v_state > 1.5) {
		drop = 0.97;                                        // dead tube: cold glass
	} else if (v_state > 0.5) {
		// failing: bursts of stutter every few seconds
		float burst = step(0.72, hash11(floor(t * 0.45 + s * 5.0) + 3.1));
		drop = burst * step(0.45, r) * 0.9;
	} else {
		drop = step(0.997, r) * 0.6;                         // the odd blink
	}
	float f = mix(buzz * breathe, 0.85 + 0.15 * sin(t * (1.1 + hash11(s * 3.1) * 1.7) + s * 29.0), twinkle);
	f *= 1.0 - drop;
	// Tube body: pale core, saturated rim, so it reads as glass with gas in it.
	float core = pow(clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	vec3 lit = mix(c, mix(c, vec3(1.0), 0.45), core * (1.0 - twinkle * 0.5));
	vec3 glass = c * 0.08 + vec3(0.02);
	ALBEDO = mix(glass, lit * energy * f, smoothstep(0.0, 0.15, f));
}
