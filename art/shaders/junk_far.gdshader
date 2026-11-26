shader_type spatial;
// [art3] A junk piece in the far band (JunkFarSingle): one colour per surface in the vertex colours,
// no texture reads. The same grounding as junk_piece.gdshader (contact darkening and dirt low on the
// piece along the planet's up) and the same tone, and the colour leans to the field's mean with
// distance, so a far field reads as heaps of the same stuff, not as sparks.
uniform vec3 box_center = vec3(0.0);
uniform vec3 box_half = vec3(0.25);
uniform float sat = 0.8;
uniform float val = 0.9;
uniform vec3 dust : source_color = vec3(0.34, 0.31, 0.27);
uniform float dust_amt = 0.12;
uniform vec3 dirt : source_color = vec3(0.09, 0.08, 0.07);
uniform float dirt_h = 0.10;
uniform vec3 far_mean : source_color = vec3(0.17, 0.155, 0.135);
uniform float far_from = 30.0;
uniform float far_to = 110.0;
uniform float far_amt = 0.45;
uniform float rough = 0.8;

varying float v_h;
varying float v_far;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 up_w = dot(origin, origin) > 1.0 ? normalize(origin) : vec3(0.0, 1.0, 0.0);
	mat3 m3 = mat3(MODEL_MATRIX);
	float sc = length(m3[0]);
	vec3 up_l = normalize(up_w * m3);
	v_h = (dot(VERTEX - box_center, up_l) + dot(abs(up_l), box_half)) * sc;
	v_far = smoothstep(far_from, far_to, distance(origin, CAMERA_POSITION_WORLD)) * far_amt;
}

void fragment() {
	vec3 c = pow(COLOR.rgb, vec3(2.2));  // stored sRGB (JunkFarSingle)
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, sat) * val;
	c = mix(c, dust, dust_amt);
	float climb = 1.0 - smoothstep(0.0, dirt_h, v_h);
	c = mix(c, dirt, climb * 0.72);
	c *= mix(0.45, 1.0, smoothstep(-0.01, 0.07, v_h));
	ALBEDO = mix(c, far_mean, v_far);
	ROUGHNESS = rough;
	AO = mix(0.55, 1.0, smoothstep(0.0, 0.09, v_h));
}
