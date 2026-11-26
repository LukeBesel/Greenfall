shader_type spatial;
// [art6] A worker robot seen from far away (robots/robot_visual.gd, beyond FAR_M): one mesh of
// rounded blocks, one draw. Vertex colour R = baked occlusion, G = which paint (0 shell, 0.33 the
// type's accent, 0.66 dark mechanics, 0.9 rubber, 1 the visor). The visor keeps a little of the
// robot's glow so the face still reads as a point of light.
render_mode diffuse_burley;

uniform vec4 paint : source_color = vec4(0.88, 0.85, 0.75, 1.0);
uniform vec4 accent : source_color = vec4(1.0, 0.72, 0.06, 1.0);
uniform vec4 dark : source_color = vec4(0.1, 0.105, 0.115, 1.0);
uniform vec4 glow : source_color = vec4(1.0, 0.72, 0.25, 1.0);

void fragment() {
	float k = COLOR.g;
	vec3 c = k < 0.17 ? paint.rgb : (k < 0.5 ? accent.rgb : (k < 0.78 ? dark.rgb : vec3(0.025)));
	ALBEDO = c * mix(0.5, 1.0, COLOR.r);
	ROUGHNESS = k > 0.78 ? 0.4 : 0.6;
	METALLIC = (k > 0.5 && k < 0.78) ? 0.5 : 0.0;
	EMISSION = glow.rgb * (k > 0.95 ? 0.9 : 0.0);
}
