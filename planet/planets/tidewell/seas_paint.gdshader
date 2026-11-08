shader_type spatial;
// [p_seas] Painted-metal / timber finish for the Tidewell + Rime kit (seas_kit.gd). Chunky and clean:
// a flat paint colour with soft large-scale tone variation, worn bright edges on the bevels
// (vertex COLOR.r = bevel), a grime gradient towards the base, a dark algae waterline on sea
// props, and broad (never streaky) rust blooms whose amount follows `rust` (ruin 1, restored 0).
// Works without UVs (triplanar in object-independent world space).

uniform vec4 paint : source_color = vec4(0.8, 0.5, 0.2, 1.0);
uniform vec4 paint2 : source_color = vec4(0.55, 0.14, 0.1, 1.0);  // COLOR.g = 1 parts (hull bottoms, trims)
uniform vec4 rust_col : source_color = vec4(0.42, 0.2, 0.1, 1.0);
uniform vec4 edge_col : source_color = vec4(0.85, 0.82, 0.76, 1.0);
uniform float rust : hint_range(0.0, 1.0) = 0.0;
uniform float edge_wear : hint_range(0.0, 1.0) = 0.5;
uniform float roughness_v : hint_range(0.0, 1.0) = 0.6;
uniform float metallic_v : hint_range(0.0, 1.0) = 0.15;
uniform float grime : hint_range(0.0, 1.0) = 0.4;
uniform float waterline = -1000.0;   // world y of the sea (sea props: algae band just above it)
uniform float tone_var : hint_range(0.0, 0.5) = 0.08;
uniform float detail_scale = 0.35;
uniform float detail_nrm : hint_range(0.0, 1.0) = 0.25;
uniform float emission_e = 0.0;
uniform vec4 emission_c : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform sampler2D detail_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rust_tex : source_color, filter_linear_mipmap, repeat_enable;

varying vec3 wpos;
varying vec3 wnrm;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 tri_sample(sampler2D t, vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(t, p.zy).rgb * w.x + texture(t, p.xz).rgb * w.y + texture(t, p.xy).rgb * w.z;
}

void fragment() {
	float edge = clamp(COLOR.r, 0.0, 1.0);
	float n1 = vnoise(wpos * 0.18);
	float n2 = vnoise(wpos * 0.9 + 7.0);
	vec3 col = mix(paint.rgb, paint2.rgb, step(0.5, COLOR.g)) * (1.0 - tone_var + tone_var * 2.0 * n1);
	// Rust blooms: broad soft patches, more on edges and low down.
	float low = 1.0 - smoothstep(0.0, 3.0, wpos.y - waterline);
	float rmask = smoothstep(0.55, 0.75, n1 * 0.6 + n2 * 0.4 + edge * 0.25 + low * 0.15 - (1.0 - rust) * 0.6);
	vec3 rt = tri_sample(rust_tex, wpos * 0.25, wnrm) * rust_col.rgb * 2.2;
	col = mix(col, rt, rmask * rust);
	// Worn bright edges (chipped paint) on bevels.
	float chip = smoothstep(0.35, 0.6, n2) * edge;
	col = mix(col, edge_col.rgb * mix(1.0, 0.55, rust), chip * edge_wear);
	// Grime: darker toward the bottom of each surface and in down-facing areas.
	float down = clamp(-wnrm.y, 0.0, 1.0);
	col *= 1.0 - grime * (0.25 * down + 0.2 * low);
	// Algae waterline on sea props.
	float wl = wpos.y - waterline;
	float band = smoothstep(-0.2, 0.15, wl) * (1.0 - smoothstep(0.25, 0.9 + n2 * 0.4, wl));
	col = mix(col, vec3(0.16, 0.22, 0.12), band * 0.75 * step(-999.0, waterline));
	col = mix(col, col * vec3(0.55, 0.65, 0.6), (1.0 - smoothstep(-0.25, 0.0, wl)) * step(-999.0, waterline));
	ALBEDO = col;
	ROUGHNESS = clamp(roughness_v + rmask * rust * 0.3 - chip * 0.15, 0.05, 1.0);
	METALLIC = metallic_v * (1.0 - rmask * rust) + chip * edge_wear * 0.4;
	vec3 dn = tri_sample(detail_tex, wpos * detail_scale, wnrm);
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), dn, detail_nrm);
	EMISSION = emission_c.rgb * emission_e;
}
