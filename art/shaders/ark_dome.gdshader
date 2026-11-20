shader_type spatial;
// [v11film] The glass of the ark's garden dome (story/cradle_ship.gd; the same dome seen from
// inside in the seed vault set). Thin clear glass with white ribs drawn on it (UV.x round the
// dome 0..1, UV.y 0 at the rim .. 1 at the top), a soft rim sheen, and damage: `breach` 0..1
// opens a jagged hole round `hole_dir` (object space) with white cracks running out from it.
render_mode blend_mix, cull_disabled, depth_draw_opaque, specular_schlick_ggx;
uniform vec4 glass : source_color = vec4(0.62, 0.86, 0.92, 0.1);
uniform vec4 rib : source_color = vec4(0.9, 0.91, 0.9, 1.0);
uniform float ribs_round = 12.0;
uniform float ribs_up = 3.0;
uniform float rib_w = 0.035;
uniform float breach : hint_range(0.0, 1.0) = 0.0;
uniform vec3 hole_dir = vec3(0.7, 0.6, 0.3);
uniform float hole_size = 0.5;
varying vec3 lp;

float hash1(float x) {
	return fract(sin(x * 127.1) * 43758.5453);
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec2 g = vec2(UV.x * ribs_round, UV.y * ribs_up);
	vec2 f = abs(fract(g) - 0.5);
	vec2 aw = fwidth(g);
	// Ribs keep their width on screen as the meridians close in toward the top.
	float wx = rib_w * ribs_round * 0.16 / max(0.12, 1.0 - UV.y * 0.9);
	float wy = rib_w * 1.4;
	float mer = 1.0 - smoothstep(wx, wx + aw.x, 0.5 - f.x);
	float par = 1.0 - smoothstep(wy, wy + aw.y, 0.5 - f.y);
	float r = max(mer, par) * step(UV.y, 0.985);
	// The hole: a jagged edge round hole_dir, cracks beyond it.
	vec3 n = normalize(lp);
	vec3 hd = normalize(hole_dir);
	float ang = acos(clamp(dot(n, hd), -1.0, 1.0));
	vec3 side = normalize(cross(hd, vec3(0.0, 1.0, 0.0)));
	float az = atan(dot(n, cross(hd, side)), dot(n, side));
	float jag = 0.78 + 0.22 * hash1(floor(az * 5.0)) + 0.12 * sin(az * 9.0);
	float edge = hole_size * breach * jag;
	if (breach > 0.001 && ang < edge) {
		discard;
	}
	// The glass is nearly clear, so the damage has to be drawn: a bright broken edge round the
	// hole, long white cracks running out of it, and frosted glass between them.
	float crack_zone = breach * (1.0 - smoothstep(edge, edge + hole_size * 1.9, ang));
	float spoke = abs(fract(az * 3.3 + 0.25 * sin(ang * 14.0)) - 0.5);
	float crack = crack_zone * (1.0 - smoothstep(0.0, 0.05 + fwidth(az) * 2.5, spoke));
	float lip = breach * (1.0 - smoothstep(0.0, 0.03 + fwidth(ang) * 1.5, abs(ang - edge)));
	crack = max(crack, lip);
	float frost = crack_zone * 0.42;
	float fres = pow(1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 3.0);
	vec3 col = mix(glass.rgb, rib.rgb, r);
	col = mix(col, vec3(0.95, 0.98, 1.0), max(crack, frost));
	ALBEDO = col;
	ALPHA = clamp(max(max(r, crack), glass.a + fres * 0.35 + frost), 0.0, 1.0);
	ROUGHNESS = mix(0.05, 0.4, r);
	METALLIC = 0.1;
	SPECULAR = 0.6;
}
