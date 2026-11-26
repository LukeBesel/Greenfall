shader_type spatial;
// [planet-anvil] Riveted plate shells (stacks, furnace, pots): UV is metres (x around, y up), UV2.x
// is 0..1 up the shell. Staggered plate courses with seams, per-plate rust in bands, scraps of old
// dark paint, rivet rows along every course seam, and soot pouring down from the lip in runs.
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D rust_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rust_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 rust_a : source_color = vec3(0.46, 0.17, 0.07);
uniform vec3 rust_b : source_color = vec3(0.3, 0.1, 0.05);
uniform vec3 paint : source_color = vec3(0.13, 0.12, 0.12);
uniform vec3 soot_col : source_color = vec3(0.025, 0.022, 0.02);
uniform float course = 2.4;
uniform float plate_w = 3.2;
uniform float soot = 1.0;
uniform float seed = 0.0;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21) + seed);
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 m = UV;
	float row = floor(m.y / course);
	float off = mod(row, 2.0) * 0.5 * plate_w;
	float colm = floor((m.x + off) / plate_w);
	vec2 cell = vec2(fract((m.x + off) / plate_w), fract(m.y / course));
	float dy = min(cell.y, 1.0 - cell.y) * course;
	float dx = min(cell.x, 1.0 - cell.x) * plate_w;
	float id = h21(vec2(row, colm));
	float seam = 1.0 - smoothstep(0.012, 0.035, min(dx, dy));
	// Rivets: a row 9 cm in from each horizontal seam and each vertical seam, 22 cm apart.
	vec2 rh = vec2((fract(m.x / 0.22) - 0.5) * 0.22, dy - 0.09);
	vec2 rv = vec2(dx - 0.09, (fract(m.y / 0.22) - 0.5) * 0.22);
	float rivet = max(1.0 - smoothstep(0.014, 0.024, length(rh)), 1.0 - smoothstep(0.014, 0.024, length(rv)));
	vec3 tex = texture(rust_alb, m * 0.45).rgb;
	float lt = dot(tex, vec3(0.3, 0.55, 0.15));
	vec3 rust = mix(rust_a, rust_b, id) * lt * 2.2;
	// Scraps of the old dark paint, worn off at plate edges.
	float pn = vn(m * vec2(1.3, 0.9) + id * 9.0);
	float keep_paint = smoothstep(0.55, 0.62, pn) * smoothstep(0.08, 0.3, min(dx, dy));
	vec3 alb = mix(rust, paint * (0.8 + 0.4 * lt), keep_paint);
	// Rust bleeding down from each seam and rivet row.
	float bleed = smoothstep(0.35, 0.0, cell.y * course) * vn(vec2(m.x * 6.0, m.y * 0.4)) * (1.0 - keep_paint);
	alb = mix(alb, rust_a * 1.15, bleed * 0.5);
	// Soot from the lip, running down in long streaks.
	float runs = vn(vec2(m.x * 2.4, m.y * 0.05)) * 0.6 + vn(vec2(m.x * 7.0, m.y * 0.12)) * 0.4;
	float s = smoothstep(0.45, 0.95, UV2.x + (runs - 0.5) * 0.55) * soot;
	alb = mix(alb, soot_col, s * 0.92);
	alb *= 1.0 - seam * 0.55;
	alb = mix(alb, alb * 1.5 + vec3(0.03), rivet * (1.0 - s * 0.7));
	ALBEDO = alb;
	ROUGHNESS = mix(0.82, 0.55, keep_paint) + s * 0.1;
	METALLIC = mix(0.25, 0.5, rivet);
	NORMAL_MAP = texture(rust_nrm, m * 0.45).rgb;
	NORMAL_MAP_DEPTH = 1.0 + seam * 2.0 + rivet * 2.5;
}
