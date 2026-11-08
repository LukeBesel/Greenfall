shader_type spatial;
// [sgrid] Sphere ground (chunks and far shell). Each vertex carries its (noise-warped) owner cell
// in UV2.x; the per-cell state texture (SphereCells) gives junk left / state / biome, so cleaning
// a hex is one texel write and its border wanders. World-space triplanar texturing (works at any
// point of the sphere). Lifted from the orbit prototype's ground (planet/orbit/orbit_ground).

uniform sampler2D state_tex : filter_nearest;
uniform int state_w = 512;
uniform sampler2D tex_dirt : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_rubble : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_clean : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tex_scale = 0.22;
// 1 on the far shell: coarser texture, no fine detail (it is only seen from far away).
uniform float far_shell = 0.0;
// Debug: tint each LOD (0 = off).
uniform float lod_tint = 0.0;
uniform vec3 lod_color = vec3(1.0);

varying vec4 st;
varying vec3 wpos;
varying vec3 wnrm;
varying float wet;

void vertex() {
	int idx = int(UV2.x + 0.5);
	st = texelFetch(state_tex, ivec2(idx % state_w, idx / state_w), 0);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wet = UV2.y;
}

vec3 tri(sampler2D t, vec3 p, vec3 w) {
	return texture(t, p.yz).rgb * w.x + texture(t, p.xz).rgb * w.y + texture(t, p.xy).rgb * w.z;
}

void fragment() {
	vec3 w = pow(abs(wnrm), vec3(4.0));
	w /= dot(w, vec3(1.0));
	float sc = mix(tex_scale, tex_scale * 0.02, far_shell);
	vec3 p = wpos * sc;
	float junk = st.r;
	float state = floor(st.g * 255.0 / 36.0 + 0.5);
	float biome = floor(st.b * 255.0 / 17.0 + 0.5);
	float n = dot(tri(tex_rubble, wpos * mix(0.031, 0.002, far_shell), w), vec3(0.33));
	float dirty = smoothstep(0.38, 0.62, junk + (n - 0.45) * 0.7);
	vec3 dirt = mix(tri(tex_dirt, p, w), tri(tex_rubble, p * 1.3, w), 0.55) * vec3(0.6, 0.53, 0.46);  // [v1world] grimier (was 0.78, 0.7, 0.62): trashed ground reads dark, as on the flat field
	// [v1world] Past the litter carpet's reach the junk ground still reads as trash: bags, rust and
	// paper mottled from the rubble texture (mipmapped, so stable far off), fading in with distance.
	float far_k = far_shell > 0.5 ? 1.0 : smoothstep(45.0, 95.0, length(VERTEX));
	float tl = dot(tri(tex_rubble, wpos * 0.09, w), vec3(0.333));
	float tl2 = dot(tri(tex_rubble, wpos * 0.23 + 3.7, w), vec3(0.333));
	vec3 trash = mix(vec3(0.07, 0.07, 0.08), vec3(0.4, 0.31, 0.22), smoothstep(0.3, 0.46, tl));
	trash = mix(trash, vec3(0.74, 0.7, 0.6), smoothstep(0.52, 0.62, tl2) * 0.85);
	dirt = mix(dirt, trash, far_k * 0.7);
	vec3 clean = tri(tex_clean, p, w) * vec3(0.95, 0.93, 0.9);
	vec3 grass = tri(tex_grass, p * 0.8, w) * vec3(0.85, 1.0, 0.8);
	float green = smoothstep(1.5, 2.5, state + (n - 0.45));
	vec3 col = mix(mix(clean, grass, green), dirt, dirty);
	// Biome tints (frost, dust, marsh) so regions read from orbit.
	if (abs(biome - 5.0) < 0.5) col = mix(col, vec3(0.86, 0.9, 0.95), 0.55);
	else if (abs(biome - 4.0) < 0.5) col *= vec3(1.12, 0.98, 0.8);
	else if (abs(biome - 3.0) < 0.5) col *= vec3(0.85, 0.95, 0.8);
	float water = far_shell > 0.5 ? step(4.5, state) : smoothstep(0.45, 0.8, wet);  // [v1world] chunks: smooth wetness (UV2.y), not the warped owner's state
	// [v1world] Shore: land near a lake turns to damp mud over the bank (clean shore cells were pale concrete strips).
	float bank = far_shell > 0.5 ? 0.0 : smoothstep(0.04, 0.5, wet);
	col = mix(col, dirt * vec3(0.72, 0.66, 0.58), bank * 0.85);
	col = mix(col, col * 0.42 + vec3(0.015, 0.03, 0.035), water);  // [v1world] wet mud on banks and beds (was a flat blue)
	col = mix(col, col * lod_color, lod_tint);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.6, water);  // [v1world] was 0.12 / 0.6: glossy banks mirrored the sky as a white strip
	SPECULAR = mix(0.35, 0.4, water);
}
