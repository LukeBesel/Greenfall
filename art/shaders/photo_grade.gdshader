shader_type canvas_item;
// [photo] Photo mode grade: runs over the photo camera's own viewport (so captures include it).
// Gentle, filmic controls: contrast, saturation, warmth/tint, split toning, a soft highlight
// glow and diffusion (mist), fade (lifted blacks), mono, vignette, fine grain and a 2.39:1
// letterbox. Neutral values leave the image untouched.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float contrast = 1.0;
uniform float saturation = 1.0;
uniform float warmth = 0.0;      // -1 cool .. 1 warm
uniform float tint = 0.0;        // -1 green .. 1 magenta
uniform float vignette = 0.0;    // 0..1
uniform float grain = 0.0;       // 0..1
uniform float fade = 0.0;        // 0..1 lifted blacks
uniform float mono = 0.0;        // 0..1
uniform vec3 shadow_col = vec3(0.5);
uniform vec3 high_col = vec3(0.5);
uniform float split = 0.0;       // split-tone strength
uniform float bloom = 0.0;       // soft glow around highlights
uniform float soft = 0.0;        // lighten-blend diffusion (mist / dreamy)
uniform float letterbox = 0.0;   // 1 = 2.39:1 bars
uniform float target_aspect = 2.39;

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 c = textureLod(screen_tex, uv, 0.0).rgb;
	if (bloom > 0.001 || soft > 0.001) {
		vec3 b1 = textureLod(screen_tex, uv, 3.0).rgb;
		vec3 b2 = textureLod(screen_tex, uv, 4.5).rgb;
		vec3 b = b1 * 0.55 + b2 * 0.45;
		vec3 bright = max(b - vec3(0.6), vec3(0.0)) / 0.4;
		c += bright * bright * bloom * 0.6;
		c = mix(c, max(c, b * 0.92), soft);
	}
	// White balance (in display space: small, gentle shifts).
	c *= vec3(1.0 + warmth * 0.09, 1.0 - abs(warmth) * 0.01 - tint * 0.045, 1.0 - warmth * 0.11);
	c.rb *= 1.0 + tint * 0.025;
	// Contrast with a soft S around mid grey.
	c = clamp((c - 0.5) * contrast + 0.5, 0.0, 1.2);
	float l = luma(c);
	c = mix(vec3(l), c, saturation);
	// Split toning: shadows toward shadow_col, highlights toward high_col (0.5 = neutral).
	vec3 tone = mix(shadow_col, high_col, smoothstep(0.1, 0.85, l)) * 2.0;
	c = mix(c, c * tone, split);
	c = mix(c, vec3(luma(c)), mono);
	// Fade: lift the blacks and roll off the whites a touch.
	c = c * (1.0 - fade * 0.12) + vec3(fade * 0.075);
	// Vignette (round, aspect-correct, very soft).
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 q = (uv - 0.5) * vec2(aspect, 1.0);
	float r = length(q) / (0.5 * sqrt(aspect * aspect + 1.0));
	c *= 1.0 - vignette * 0.7 * smoothstep(0.35, 1.05, r);
	// Fine, luminance-weighted grain (changes 24 times a second).
	float n = hash(floor(uv / SCREEN_PIXEL_SIZE) + floor(TIME * 24.0) * 17.0) - 0.5;
	c += n * grain * 0.11 * (1.0 - luma(c) * 0.6);
	c = clamp(c, 0.0, 1.0);
	if (letterbox > 0.5) {
		float bar = max(0.0, (1.0 - aspect / target_aspect) * 0.5);
		if (uv.y < bar || uv.y > 1.0 - bar) {
			c = vec3(0.0);
		}
	}
	COLOR = vec4(c, 1.0);
}
