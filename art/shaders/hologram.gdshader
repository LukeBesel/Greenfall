shader_type spatial;
// Hand-held survey hologram: vertex-coloured cells, additive, with scanlines, a fresnel rim,
// a slow sweep band and a little flicker. Reads as projected light, not a solid object.
render_mode unshaded, blend_mix, depth_draw_opaque, cull_back;

uniform float brightness = 1.15;
uniform float alpha = 0.85;
uniform vec4 rim_color : source_color = vec4(0.45, 0.9, 1.0, 1.0);
uniform float scan_density = 140.0;

varying vec3 obj;

void vertex() {
	obj = VERTEX;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	float scan = 0.82 + 0.18 * sin(obj.y * scan_density + TIME * 4.0);
	float sweep = smoothstep(0.06, 0.0, abs(fract(obj.y * 0.5 + 0.5 - TIME * 0.18) - 0.5));
	float flicker = 0.94 + 0.06 * sin(TIME * 37.0) * sin(TIME * 13.0);
	vec3 c = COLOR.rgb * brightness * scan * flicker;
	c += rim_color.rgb * fres * 0.9;
	c += rim_color.rgb * sweep * 0.35;
	ALBEDO = c;
	ALPHA = clamp(alpha * scan + fres * 0.3, 0.0, 1.0);
}
