shader_type spatial;
// [wild] Animals (fauna/fauna.gd, meshes from fauna/fauna_models.gd), drawn as MultiMeshes.
// Cheap rig in the vertex shader: every vertex carries CUSTOM0 = (pivot.xyz, part id) and each
// instance passes INSTANCE_CUSTOM = (cycle phase, gait/flap amount, packed head yaw+pitch,
// packed coat index + tail amount). Parts: 0 body, 1-4 legs FL FR BL BR (trot), 5 head/neck,
// 6 tail, 7/8 wings L/R, 9 fish body flex, 12 hind pair, 13 front pair (hoppers).
// UV.x = how much the coat tint applies, UV.y = gloss (eyes, noses, wet beaks).
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

uniform vec3 coats[8];
uniform float fur_rim = 0.35;
uniform float roughness_base = 0.82;
uniform float sss_amt = 0.15;

varying float v_ao;
varying vec2 v_mask;
varying vec3 v_tint;

vec3 rot_x(vec3 v, float a) { float c = cos(a); float s = sin(a); return vec3(v.x, c * v.y - s * v.z, s * v.y + c * v.z); }
vec3 rot_y(vec3 v, float a) { float c = cos(a); float s = sin(a); return vec3(c * v.x + s * v.z, v.y, -s * v.x + c * v.z); }
vec3 rot_z(vec3 v, float a) { float c = cos(a); float s = sin(a); return vec3(c * v.x - s * v.y, s * v.x + c * v.y, v.z); }

void vertex() {
	vec3 piv = CUSTOM0.xyz;
	int part = int(CUSTOM0.w + 0.5);
	float phase = INSTANCE_CUSTOM.x;
	float gait = INSTANCE_CUSTOM.y;
	float hz = INSTANCE_CUSTOM.z;
	float head_yaw = floor(hz) / 50.0 - 2.0;
	float head_pitch = fract(hz) / 0.99 * 2.5 - 1.0;
	float w = INSTANCE_CUSTOM.w;
	float tail = mod(w, 2.0);
	vec3 p = VERTEX - piv;
	vec3 n = NORMAL;
	if (part >= 1 && part <= 4) {
		float off = (part == 2 || part == 3) ? 3.14159 : 0.0;
		float a = sin(phase + off) * gait;
		p = rot_x(p, a); n = rot_x(n, a);
	} else if (part == 12 || part == 13) {
		float a = sin(phase + (part == 13 ? 3.14159 : 0.0)) * gait;
		p = rot_x(p, a); n = rot_x(n, a);
	} else if (part == 5) {
		p = rot_x(p, -head_pitch); n = rot_x(n, -head_pitch);
		p = rot_y(p, head_yaw); n = rot_y(n, head_yaw);
	} else if (part == 6) {
		float a = sin(TIME * 5.0 + float(INSTANCE_ID) * 1.7) * tail;
		p = rot_y(p, a); n = rot_y(n, a);
	} else if (part == 7 || part == 8) {
		float side = part == 7 ? -1.0 : 1.0;
		float a = (sin(phase) * gait + tail * 0.35) * side;
		p = rot_z(p, a); n = rot_z(n, a);
	} else if (part == 9) {
		float k = max(p.z, 0.0);
		p.x += sin(phase - p.z * 9.0) * gait * k * 0.35;
	}
	VERTEX = p + piv;
	NORMAL = normalize(n);
	// Cheap baked occlusion: undersides and the belly line sit in shadow.
	v_ao = mix(0.62, 1.0, smoothstep(-0.7, 0.5, NORMAL.y));
	v_mask = UV;
	int coat = int(floor(w / 2.0) + 0.5);
	v_tint = coats[clamp(coat, 0, 7)];
}

void fragment() {
	vec3 alb = mix(COLOR.rgb, COLOR.rgb * v_tint, v_mask.x);
	ALBEDO = alb * v_ao;
	ROUGHNESS = mix(roughness_base, 0.12, v_mask.y);
	SPECULAR = mix(0.3, 0.7, v_mask.y);
	// Soft fur/feather sheen at grazing angles, coloured by the coat.
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	RIM = fur_rim * (1.0 - v_mask.y);
	RIM_TINT = 0.6;
	BACKLIGHT = vec3(sss_amt) * alb;
	EMISSION = alb * rim * 0.04;
}
