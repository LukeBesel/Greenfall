shader_type spatial;
// [vqa] Premium curtain-wall glass for the Cradle's launch-city towers.
// The wall meshes carry metres in UV (x along the facade, y up), so the panel grid stays square on
// every tower and tier: deep blue-green mirror glass, hair-thin satin mullions, a darker spandrel
// at each floor slab, a faint per-panel tint and tilt (real curtain walls never reflect as one
// flat sheet) and the odd lit office at night. No white grid, no glow lines.
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 glass_col : source_color = vec3(0.36, 0.5, 0.6);
uniform vec3 spandrel_col : source_color = vec3(0.16, 0.2, 0.24);
uniform vec3 mullion_col : source_color = vec3(0.66, 0.69, 0.72);
uniform float panel_w = 1.6;
uniform float floor_h = 3.8;
uniform float mullion_w = 0.05;
uniform float spandrel_h = 0.55;
uniform float night = 0.0;  // 0 day .. 1 night: a few warm offices glow

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 m = UV;
	vec2 cell = floor(vec2(m.x / panel_w, m.y / floor_h));
	vec2 f = vec2(fract(m.x / panel_w) * panel_w, fract(m.y / floor_h) * floor_h);
	// Anti-aliased masks (fwidth keeps the lines hair-thin but stable far away).
	vec2 fw = max(fwidth(m), vec2(1e-4));
	float mx = min(f.x, panel_w - f.x);
	float mull = 1.0 - smoothstep(mullion_w * 0.5 - fw.x, mullion_w * 0.5 + fw.x, mx);
	float spand = 1.0 - smoothstep(spandrel_h - fw.y, spandrel_h + fw.y, f.y);
	float slab = 1.0 - smoothstep(0.03 - fw.y, 0.03 + fw.y, min(f.y, floor_h - f.y));
	// Far away the lines would shimmer: fade them into the average colour.
	float far = smoothstep(0.08, 0.35, max(fw.x, fw.y));
	mull *= 1.0 - far;
	slab *= 1.0 - far;
	float r = h21(cell + vec2(17.0, 3.0));
	vec3 g = glass_col * (0.92 + 0.16 * r);
	vec3 col = mix(g, spandrel_col, spand * (1.0 - far * 0.6));
	col = mix(col, mullion_col, max(mull, slab * 0.7));
	ALBEDO = col;
	float glassy = (1.0 - spand) * (1.0 - max(mull, slab));
	METALLIC = mix(0.55, 0.85, glassy);
	ROUGHNESS = mix(0.32, 0.035 + 0.03 * r, glassy);
	SPECULAR = 0.6;
	// Slight per-panel tilt (wavy reflections across the facade).
	vec2 tilt = (vec2(h21(cell), h21(cell + 9.1)) - 0.5) * 0.06 * glassy;
	NORMAL_MAP = vec3(0.5 + tilt.x, 0.5 + tilt.y, 1.0);
	// Night: some offices stay lit, warm and low.
	float lit = step(0.82, h21(cell * 1.7 + 4.0)) * glassy * night;
	EMISSION = vec3(1.0, 0.86, 0.66) * lit * 0.6;
}
