shader_type spatial;
// [fauna2] Fur for the skinned animals (art/models/fauna/*.glb, fauna/fauna_rig.gd). The model's
// vertex colours are coat masks: R white areas (muzzle, bib, belly, socks), G tabby stripes,
// B low-frequency patches (calico), A soft occlusion. Per-instance coat colours make every
// animal its own (ginger tabby, tuxedo, grey, calico...). Soft look: fine strand grain, a warm
// subsurface-ish backlight, a fuzzy sheen at grazing angles. `shell` > 0 draws one fur shell
// (pushed out along the normal; strands discarded by a hash), used as next_pass layers.
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

uniform vec3 coat_base : source_color = vec3(0.86, 0.52, 0.24);
uniform vec3 coat_stripe : source_color = vec3(0.52, 0.25, 0.09);
uniform vec3 coat_white : source_color = vec3(0.93, 0.89, 0.82);
uniform vec3 coat_patch : source_color = vec3(0.12, 0.1, 0.09);
uniform float stripe_amt = 1.0;
uniform float white_amt = 0.5;
uniform float patch_amt = 0.0;

uniform float shell = 0.0;
uniform bool baked = false;  // vendor models: the vertex colour is the albedo (no coat masks)
uniform float fur_len = 0.007;
uniform float density = 900.0;
uniform float sheen = 0.06;

varying vec4 vc;
varying vec3 lp;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	vc = COLOR;
	lp = VERTEX;
	if (shell > 0.0) {
		// Shorter fur on the face, paws and tail tip would need a mask; occlusion is a fair proxy.
		VERTEX += NORMAL * fur_len * shell * (0.5 + 0.5 * COLOR.a) - vec3(0.0, fur_len * 0.35 * shell * shell, 0.0);
	}
}

void fragment() {
	if (baked) {
		vec3 bc = vc.rgb;
		float grain0 = vnoise(lp * vec3(density * 0.35, density, density * 0.35));
		vec3 alb0 = bc * (0.9 + 0.2 * grain0);
		if (shell > 0.0) {
			if (hash13(floor(lp * density)) < shell * 0.95 + 0.05) {
				discard;
			}
			alb0 *= mix(0.8, 1.05, shell);
		}
		ALBEDO = alb0;
		ROUGHNESS = 0.85;
		SPECULAR = 0.25;
		RIM = sheen;
		RIM_TINT = 0.7;
		BACKLIGHT = alb0 * 0.1;
	} else {
	float t = mix(1.1, 0.3, white_amt);
	float white = smoothstep(t - 0.12, t + 0.12, vc.r);
	float stripe = smoothstep(0.25, 0.75, vc.g) * stripe_amt;
	float patch = smoothstep(0.62, 0.7, vc.b) * patch_amt;
	vec3 c = mix(coat_base, coat_stripe, stripe);
	c = mix(c, coat_patch, patch);
	c = mix(c, coat_white, white);
	// Strand grain: fine streaks in the coat.
	float grain = vnoise(lp * vec3(density * 0.35, density, density * 0.35));
	c *= 0.9 + 0.2 * grain;
	if (shell > 0.0) {
		float strand = hash13(floor(lp * density));
		if (strand < shell * 0.95 + 0.05) {
			discard;
		}
		c *= mix(0.78, 1.05, shell);
	}
	vec3 alb = c * mix(0.55, 1.0, vc.a);
	ALBEDO = alb;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	RIM = sheen;
	RIM_TINT = 0.7;
	BACKLIGHT = alb * 0.1;
	ALBEDO = alb * (1.0 - 0.12 * fres);
	}
}
