shader_type spatial;
// One additive batch for the pickup show (player/pickup_fx.gd builds it as an ImmediateMesh each
// frame): laser ribbons, electric arcs, light motes and glows (UV2.x = 0: soft glow with a hot
// core; ribbons keep UV.x at 0.5 so only the cross profile matters) and the ground lock-on
// reticle (UV2.x = 1, UV2.y = its spin angle). Vertex colour = tint, alpha = strength.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

float aa(float d, float w) {
	float f = max(fwidth(d), 0.0001);
	return clamp(0.5 - (d - w) / f, 0.0, 1.0);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float k;
	float hot;
	if (UV2.x < 0.5) {
		float r = length(p);
		hot = smoothstep(0.42, 0.0, r);
		k = exp(-r * r * 5.0) * 0.55 + hot;
	} else {
		float a = UV2.y;
		vec2 q = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * p;
		float r = length(q);
		float ang = atan(q.y, q.x) / 6.2831853 + 0.5;
		// Outer ring broken into four brackets.
		float brackets = aa(abs(r - 0.84), 0.045) * step(0.32, fract(ang * 4.0 + 0.16));
		// Dashed inner ring, counter-rotating feel from the different dash count.
		float dashes = aa(abs(r - 0.56), 0.022) * step(0.45, fract(ang * 16.0));
		// Four ticks pointing in.
		float ax = min(abs(q.x), abs(q.y));
		float ticks = aa(ax, 0.028) * step(0.64, r) * step(r, 0.98);
		float center = aa(r, 0.07);
		float halo = exp(-r * r * 3.0) * 0.12;
		k = brackets + dashes * 0.8 + ticks * 0.9 + center * 0.6 + halo;
		hot = brackets * 0.4 + center * 0.5;
	}
	ALBEDO = mix(COLOR.rgb, vec3(1.0), clamp(hot, 0.0, 1.0) * 0.7) * 1.4;
	ALPHA = clamp(COLOR.a * k, 0.0, 1.0);
}
