shader_type spatial;
// [style] Character Builder chest icon drawn on a small quad over the chest screen (the heart,
// until a modelled acc_icon_heart exists). Glows in the light-strip colour.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 col : source_color = vec4(1.0, 0.4, 0.55, 1.0);
uniform float energy = 3.0;
uniform float pulse = 0.0;

float dot2(vec2 v) { return dot(v, v); }

float sd_heart(vec2 p) {
	p.x = abs(p.x);
	if (p.y + p.x > 1.0)
		return sqrt(dot2(p - vec2(0.25, 0.75))) - sqrt(2.0) / 4.0;
	return sqrt(min(dot2(p - vec2(0.0, 1.0)), dot2(p - 0.5 * max(p.x + p.y, 0.0)))) * sign(p.x - p.y);
}

void fragment() {
	vec2 q = (vec2(UV.x, 1.0 - UV.y) - vec2(0.5, 0.06)) * vec2(1.25, 1.12);
	float sd = sd_heart(q);
	float core = 1.0 - smoothstep(-0.02, 0.02, sd);
	float halo = exp(-max(sd, 0.0) * max(sd, 0.0) * 90.0) * (1.0 - core) * 0.4;
	ALBEDO = (col.rgb * core + col.rgb * halo * 0.5) * energy * (1.0 + pulse);
}
