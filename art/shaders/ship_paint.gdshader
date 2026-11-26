shader_type spatial;
// [ship] Satin pearl paint for Lumi's ship (art/models/ship): clean and premium, never dusty. Driven by
// the vertex colours baked in Blender (R = ambient occlusion, G = convex edge, B = cavity): panel
// seams and cavities read as crisp dark lines, convex edges catch a soft satin highlight, a faint
// pearlescent shift (warm to cool) follows the view angle, and a very fine flake breaks up big
// panels. Optional light wear (edge_wear) for a well-travelled look; 0 by default.
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 paint_color : source_color = vec4(0.93, 0.93, 0.91, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.32;
uniform float metallic : hint_range(0.0, 1.0) = 0.05;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.9;
uniform float seam_dark : hint_range(0.0, 1.0) = 0.55;
uniform float edge_light : hint_range(0.0, 1.0) = 0.35;
uniform float pearl : hint_range(0.0, 1.0) = 0.5;
uniform float flake : hint_range(0.0, 1.0) = 0.35;
uniform float edge_wear : hint_range(0.0, 1.0) = 0.0;
uniform float clearcoat_amt : hint_range(0.0, 1.0) = 0.6;
uniform vec4 rim_color : source_color = vec4(0.62, 0.85, 1.0, 1.0);
uniform float rim_strength = 0.06;

varying vec3 opos;
varying vec4 vcol;

float h31(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float n3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h31(i), h31(i + vec3(1, 0, 0)), f.x), mix(h31(i + vec3(0, 1, 0)), h31(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(h31(i + vec3(0, 0, 1)), h31(i + vec3(1, 0, 1)), f.x), mix(h31(i + vec3(0, 1, 1)), h31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	opos = VERTEX;
	vcol = COLOR;
}

void fragment() {
	float ao = vcol.r;
	float edge = vcol.g;
	float cav = vcol.b;
	vec3 c = paint_color.rgb;
	// Big-panel tone variation (very subtle) and fine metallic flake.
	float tone = n3(opos * 1.7);
	c *= mix(0.97, 1.02, tone);
	float fl = n3(opos * 220.0);
	// Pearlescent shift: warm facing the camera, slightly cool at grazing angles.
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	c = mix(c, c * vec3(0.94, 0.98, 1.04), (1.0 - facing) * pearl);
	c = mix(c, c * vec3(1.02, 1.0, 0.97), facing * pearl * 0.5);
	// Satin edge highlight and crisp dark seams.
	c = mix(c, min(c * 1.08 + 0.02, vec3(1.0)), edge * edge_light);
	c = mix(c, c * 0.32, smoothstep(0.15, 0.7, cav) * seam_dark);
	// Optional light wear on edges (bare satin alloy showing through).
	float wear = smoothstep(0.55, 0.85, edge * edge_wear + n3(opos * 18.0) * 0.4 * edge_wear);
	c = mix(c, vec3(0.62, 0.64, 0.67), wear);
	ALBEDO = c;
	ROUGHNESS = clamp(roughness + (fl - 0.5) * 0.08 * flake + cav * 0.2 + wear * 0.15, 0.08, 1.0);
	METALLIC = mix(metallic + fl * 0.08 * flake, 0.85, wear);
	CLEARCOAT = clearcoat_amt * (1.0 - wear);
	CLEARCOAT_ROUGHNESS = 0.12;
	AO = mix(1.0, ao, ao_strength);
	AO_LIGHT_AFFECT = 0.35;
	float fres = pow(1.0 - facing, 3.0);
	EMISSION = rim_color.rgb * fres * rim_strength * ao;
}
