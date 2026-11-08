shader_type spatial;
// Hand-held survey hologram: vertex-coloured cells with a soft rim and a slow sweep band.
// [v2map] Glitch pass (owner note 40): no strobe flicker; the scan lines are in screen space
// (object-space lines at 140/unit aliased into moire on a small globe); no fog (the world's fog
// washed the hologram out in daylight); depth is written so the grid's far side stays hidden.
render_mode unshaded, blend_mix, depth_draw_always, cull_back, fog_disabled, shadows_disabled;

uniform float brightness = 1.15;
uniform float alpha = 0.9;
uniform vec4 rim_color : source_color = vec4(0.45, 0.9, 1.0, 1.0);
// Screen pixels per scan line (gentle shimmer, never finer than ~3 px).
uniform float scan_px = 4.0;

varying vec3 obj;

void vertex() {
	obj = VERTEX;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	float scan = 0.9 + 0.1 * sin(FRAGCOORD.y * 6.2831 / scan_px - TIME * 2.0);
	float sweep = smoothstep(0.06, 0.0, abs(fract(obj.y * 0.5 + 0.5 - TIME * 0.12) - 0.5));
	vec3 c = COLOR.rgb * brightness * scan;
	c += rim_color.rgb * fres * 0.8;
	c += rim_color.rgb * sweep * 0.25;
	ALBEDO = c;
	ALPHA = clamp(alpha + fres * 0.1, 0.0, 1.0);
}
