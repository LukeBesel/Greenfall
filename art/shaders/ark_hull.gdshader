shader_type spatial;
// [v11film] The ark Cradle's skin (story/cradle_ship.gd). The hull is a few big smooth shapes, so
// the shader gives it what tells the eye "this is a huge ship": hull plates (a brick grid with a
// thin dark seam, each plate a touch lighter or darker), and rows of small lit windows.
// UV is in metres (x round the shape, y along it). COLOR.rgb is the paint (pearl, graphite,
// tangerine), COLOR.a marks where windows may be (a deck band).
// power 0..1: how many windows are lit (the storm puts half the ship in the dark);
// alarm 0..1: lit windows and seams pulse red. No screen-space tricks: the same on Forward+ and
// Compatibility.
uniform vec2 plate = vec2(2.6, 1.3);
uniform vec2 window_cell = vec2(0.9, 0.62);
uniform vec4 window_col : source_color = vec4(1.0, 0.86, 0.6, 1.0);
uniform float window_energy = 2.6;
uniform float power : hint_range(0.0, 1.0) = 1.0;
uniform float alarm : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.42;
uniform float metallic : hint_range(0.0, 1.0) = 0.25;
uniform float seam_dark : hint_range(0.0, 1.0) = 0.26;
// Window decks by height on the shape (object space y): (centre, half height) twice. A half
// height of 0 = no deck there; with both 0 the windows go wherever COLOR.a says.
uniform vec4 decks = vec4(0.0);
varying float ly;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	ly = VERTEX.y;
}

void fragment() {
	float gate = COLOR.a;
	if (decks.y + decks.w > 0.0) {
		gate *= max(step(abs(ly - decks.x), decks.y), step(abs(ly - decks.z), decks.w));
	}
	// Plates: every other row is shifted half a plate, like bricks.
	vec2 pu = UV / plate;
	float row = floor(pu.y);
	pu.x += 0.5 * mod(row, 2.0);
	vec2 cell = floor(pu);
	vec2 f = fract(pu);
	vec2 w = fwidth(pu) * 1.2 + vec2(0.01, 0.018);
	float seam = 1.0 - min(smoothstep(0.0, w.x, f.x) * smoothstep(0.0, w.x, 1.0 - f.x),
			smoothstep(0.0, w.y, f.y) * smoothstep(0.0, w.y, 1.0 - f.y));
	// Far away the seams melt into the paint instead of shimmering.
	seam *= 1.0 - smoothstep(0.25, 0.9, max(fwidth(pu.x), fwidth(pu.y)));
	float tone = 0.95 + 0.08 * hash2(cell);
	vec3 col = COLOR.rgb * tone;
	col *= 1.0 - seam * seam_dark;
	// Windows: small rounded rectangles on the deck bands.
	vec2 wu = UV / window_cell;
	vec2 wc = floor(wu);
	vec2 wf = fract(wu);
	float lit = step(0.38, hash2(wc + 7.0));
	// The ones that stay on when the power drops are always the same ones.
	lit *= step(hash2(wc + 31.0), power * 1.02);
	vec2 d = abs(wf - 0.5);
	vec2 aw = fwidth(wu) * 0.9;
	float shape = (1.0 - smoothstep(0.24 - aw.x, 0.24 + aw.x, d.x)) * (1.0 - smoothstep(0.17 - aw.y, 0.17 + aw.y, d.y));
	float win = shape * gate;
	float frame = (1.0 - smoothstep(0.3, 0.34, d.x)) * (1.0 - smoothstep(0.23, 0.27, d.y)) * gate;
	col = mix(col, vec3(0.035, 0.04, 0.05), max(frame * 0.8, win));
	float pulse = 0.55 + 0.45 * sin(TIME * 9.0 + hash2(wc) * 3.0);
	vec3 wcol = mix(window_col.rgb, vec3(1.0, 0.16, 0.1), alarm * pulse);
	float flick = 1.0 - alarm * 0.6 * step(0.7, hash2(wc + floor(TIME * 7.0)));
	ALBEDO = col;
	ROUGHNESS = mix(roughness + 0.12 * hash2(cell + 3.0), 0.08, win);
	METALLIC = metallic;
	EMISSION = wcol * win * lit * flick * window_energy * (0.75 + 0.5 * hash2(wc + 13.0));
}
