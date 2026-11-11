shader_type spatial;
// The start yard's landing pad (planets/<id>/sites: VerdanceSite.clean_pad): one quad of worn
// concrete paving. Everything is drawn from the pad's own metres (VERTEX.xz, origin at the pad
// centre, -z = the way out): slabs with joints and a tone of their own, a few replaced or cracked
// slabs, oil and rust stains, soot round the crashed pod, and worn floor paint (a safety line and
// Lumi's teal line round the edge, a landing ring with a heading arrow, a hatched gate, the bin
// bay's floor and the bench's work zone).
render_mode diffuse_burley, specular_schlick_ggx;

uniform float half_size = 10.5;
uniform float slab = 1.75;
uniform sampler2D tex_concrete : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm_concrete : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 base_tint : source_color = vec3(0.5, 0.49, 0.47);
uniform vec3 paint_safety : source_color = vec3(0.93, 0.66, 0.08);
uniform vec3 paint_lumi : source_color = vec3(0.1, 0.55, 0.6);
uniform vec3 paint_white : source_color = vec3(0.8, 0.78, 0.7);
uniform vec3 paint_work : source_color = vec3(0.9, 0.36, 0.08);
uniform vec3 paint_bay : source_color = vec3(0.1, 0.3, 0.42);
// Rectangles as (centre x, centre z, half x, half z); a zero half size switches one off.
uniform vec4 bay_rect = vec4(0.0);
uniform vec4 work_rect = vec4(0.0);
uniform vec2 ring_at = vec2(0.0, -1.0);
uniform float ring_r = 3.1;
uniform float gate_half = 3.2;
// The crashed pod: where it stands and the direction it came in from (soot streaks that way).
uniform vec2 pod_at = vec2(0.0, 9.8);
uniform vec2 pod_from = vec2(-0.83, 0.55);
uniform float soot = 1.0;
uniform float wear = 0.55;

varying vec2 pp;

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

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.3 + 7.1) * 0.3 + vnoise(p * 5.1 + 3.7) * 0.15;
}

// 1 inside a line of half-width w round distance d = 0, anti-aliased.
float line(float d, float w, float aa) {
	return 1.0 - smoothstep(w - aa, w + aa, abs(d));
}

float box_sd(vec2 p, vec4 r) {
	vec2 q = abs(p - r.xy) - r.zw;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

void vertex() {
	pp = VERTEX.xz;
}

void fragment() {
	vec2 p = pp;
	float aa = max(fwidth(p.x), fwidth(p.y)) * 0.75 + 0.002;

	// --- Concrete slabs ---
	vec2 cell = (p + half_size) / slab;
	vec2 id = floor(cell);
	vec2 f = fract(cell);
	float hs = h21(id + 3.7);
	vec3 tex = texture(tex_concrete, p * 0.3 + id * 0.37).rgb;
	float tl = dot(tex, vec3(0.299, 0.587, 0.114));
	vec3 alb = base_tint * mix(vec3(tl), tex, 0.3) * 2.1;
	// Each slab its own tone; a few were replaced later (lighter, cooler).
	alb *= 0.86 + 0.26 * hs;
	alb = mix(alb, alb * vec3(1.04, 1.0, 0.93), step(0.5, h21(id + 9.1)) * 0.5);
	float renewed = step(0.9, h21(id + 21.3));
	alb = mix(alb, alb * vec3(1.16, 1.18, 1.2), renewed);
	// Joints: a dark gap with dirt in it, the slab edges a little chipped and stained.
	vec2 jd = min(f, 1.0 - f) * slab;
	float jmin = min(jd.x, jd.y);
	float chip = vnoise(p * 9.0) * 0.012;
	float joint = 1.0 - smoothstep(0.012 + chip - aa, 0.014 + chip + aa, jmin);
	float seep = (1.0 - smoothstep(0.0, 0.14, jmin)) * (0.35 + 0.65 * vnoise(p * 2.7 + 5.0));
	alb *= 1.0 - seep * 0.22;
	// A crack across a slab now and then.
	float cr = step(0.86, h21(id + 55.5));
	float cline = f.y - 0.5 - (vnoise(vec2(f.x * 5.0, id.x + id.y * 7.0)) - 0.5) * 0.5 - (f.x - 0.5) * (hs - 0.5);
	float crack = cr * line(cline * slab, 0.006, aa);

	// --- Stains ---
	float grime = fbm(p * 0.42 + 17.0);
	alb *= mix(1.0, 0.86, smoothstep(0.45, 0.8, grime));
	// Oil: dark glossy blots, thick round the bench's work zone and thin elsewhere.
	float near_work = work_rect.z > 0.0 ? 1.0 - smoothstep(0.0, 3.5, box_sd(p, work_rect)) : 0.0;
	float oil_n = fbm(p * 1.9 + 41.0);
	float oil = smoothstep(0.8 - near_work * 0.22, 0.86 - near_work * 0.22, oil_n);
	alb = mix(alb, alb * 0.3, oil * 0.8);
	// Rust runs in from the kerb where water sits.
	float edge_d = half_size - max(abs(p.x), abs(p.y));
	float rust = (1.0 - smoothstep(0.2, 1.5, edge_d)) * smoothstep(0.5, 0.75, vnoise(vec2(p.x + p.y, p.x - p.y) * 1.3));
	alb = mix(alb, vec3(0.42, 0.2, 0.08), rust * 0.45);

	// --- Floor paint (worn through to the concrete) ---
	float chipn = fbm(p * 4.3 + 3.0) * 0.75 + vnoise(p * 23.0) * 0.25;
	float keep = smoothstep(wear * 0.72 - 0.1, wear * 0.72 + 0.12, chipn);
	keep *= 1.0 - joint;
	vec3 base = alb;
	// The bin bay's floor: a blue field, so the bay is a place of its own from across the yard.
	if (bay_rect.z > 0.0) {
		float bd = box_sd(p, bay_rect);
		alb = mix(alb, paint_bay * (0.8 + 0.4 * tl), (1.0 - smoothstep(-aa, aa, bd)) * mix(0.55, 0.92, keep));
	}
	// The bench's work zone: an orange outline with a hatched band on the yard side.
	if (work_rect.z > 0.0) {
		float wd = box_sd(p, work_rect);
		float outline = line(wd + 0.09, 0.07, aa);
		float hatch = step(0.5, fract((p.x + p.y) / 0.5)) * (1.0 - smoothstep(-aa, aa, abs(wd + 0.42) - 0.2));
		alb = mix(alb, paint_work, max(outline, hatch * 0.9) * keep);
	}
	// Safety yellow and Lumi's teal round the edge.
	alb = mix(alb, paint_safety, line(edge_d - 0.42, 0.08, aa) * keep);
	alb = mix(alb, paint_lumi, line(edge_d - 0.72, 0.06, aa) * keep);
	// The gate on the way out: yellow and black chevron hatching across the north edge.
	float gate = (1.0 - smoothstep(gate_half - aa, gate_half + aa, abs(p.x))) * (1.0 - smoothstep(-aa, aa, abs(p.y + half_size - 1.35) - 0.42));
	float chev = step(0.5, fract((abs(p.x) + p.y) / 0.7));
	alb = mix(alb, mix(vec3(0.05, 0.05, 0.05), paint_safety, chev), gate * keep);
	// The landing ring: a double ring, four quadrant ticks and a heading arrow toward the gate.
	vec2 rp = p - ring_at;
	float rr = length(rp);
	float ring = max(line(rr - ring_r, 0.09, aa), line(rr - ring_r + 0.42, 0.035, aa));
	float tick = max(line(rp.x, 0.07, aa), line(rp.y, 0.07, aa)) * step(ring_r - 1.0, rr) * step(rr, ring_r + 0.7);
	vec2 ap = vec2(abs(rp.x), rp.y + ring_r * 0.42);
	float tri = (1.0 - smoothstep(-aa, aa, ap.x - (ap.y + 1.3) * 0.62)) * step(-1.3, ap.y) * step(ap.y, 0.0);
	float stem = (1.0 - smoothstep(-aa, aa, ap.x - 0.2)) * step(0.0, ap.y) * step(ap.y, 1.5);
	float arrow = max(tri, stem);
	alb = mix(alb, paint_white, max(ring, tick) * keep);
	alb = mix(alb, paint_lumi, arrow * keep);

	// --- Soot from the crash: a burnt fan round the pod, streaked along its approach ---
	vec2 sp = p - pod_at;
	vec2 fr = normalize(pod_from);
	float along = dot(sp, fr);
	float across = dot(sp, vec2(-fr.y, fr.x));
	float sd = length(vec2(along, across));
	float streak = 0.6 + 0.4 * vnoise(vec2(atan(sp.y, sp.x) * 5.0, sd * 0.7));
	float burnt = (1.0 - smoothstep(0.9, 3.8, sd)) * streak * soot;
	alb = mix(alb, vec3(0.03, 0.028, 0.026), clamp(burnt, 0.0, 0.85));

	alb = mix(alb, vec3(0.045, 0.04, 0.035), max(joint, crack));
	float paint_amt = clamp(length(alb - base) * 3.0, 0.0, 1.0);
	ALBEDO = clamp(alb, 0.0, 1.0);
	vec3 nm = texture(nrm_concrete, p * 0.3 + id * 0.37).rgb;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = mix(0.9, 0.35, paint_amt);
	ROUGHNESS = mix(mix(0.92, 0.7, paint_amt), 0.28, oil * 0.8);
	SPECULAR = mix(0.35, 0.55, oil);
}
