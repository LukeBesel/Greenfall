shader_type spatial;
render_mode cull_disabled, world_vertex_coords, depth_draw_opaque;
// [art7] Every plant of the regrowth kit (art/models/flora, plants/flora_kit.gd): one material.
// Vertex colour: r sway weight, g ambient occlusion, b flutter phase, a kind (0 wood, 0.5 leaf,
// 1 petal). INSTANCE_CUSTOM: rgb petal colour, a a random per plant. No instance colours.
// Wind: a lean downwind that gusts in bands travelling across the land, each plant swinging in
// it at its own phase; leaf cards flutter on top. All of it along the ground at the plant (the
// world is a sphere: up is the plant's own position).

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float wind = 1.0;
uniform float cut = 0.42;
uniform float gain = 1.0;
uniform float leaf_gain = 0.95;
// 0 = this plant's own colours; towards 1 the far crowns sink into the ground's green.
uniform float lush = 1.0;

varying vec4 vc;
varying vec3 tint;
varying float rnd;
varying float patchy;

const vec3 W1 = vec3(0.62, 0.21, 0.76);
const vec3 W2 = vec3(-0.48, 0.55, 0.68);

void vertex() {
	vc = COLOR;
	tint = INSTANCE_CUSTOM.rgb;
	rnd = INSTANCE_CUSTOM.a;
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 up = normalize(origin);
	float sc = length(MODEL_MATRIX[1].xyz);
	vec3 wd = normalize(W1 - up * dot(W1, up));
	vec3 cross_w = cross(up, wd);
	// gust bands, 100-200 m apart, rolling downwind; a slower swell bends their front
	float g = sin(dot(origin, W1) * 0.045 - TIME * 0.85 + 2.2 * sin(dot(origin, W2) * 0.019 - TIME * 0.23));
	g = 0.5 + 0.5 * g;
	float strength = 0.3 + 1.0 * g * sqrt(g);
	float ph = rnd * 6.283 + dot(origin, W1) * 0.35;
	float swing = sin(TIME * (1.5 + 0.9 * rnd) + ph);
	float swing2 = sin(TIME * (2.3 + 0.7 * rnd) + ph * 1.7);
	float w = vc.r * sc * wind;
	float bend = strength * (0.62 + 0.38 * swing);
	VERTEX += wd * (bend * w) + cross_w * (swing2 * 0.22 * strength * w);
	VERTEX -= up * (bend * bend * w * 0.22);
	// leaf flutter: small, quick, each card on its own
	float leaf = step(0.25, vc.a);
	float fl = sin(TIME * (5.5 + 3.0 * vc.b) + vc.b * 37.0 + rnd * 11.0);
	VERTEX += NORMAL * (fl * 0.016 * sc * leaf * strength * wind * min(1.0, vc.r * 12.0));
	// colour patches a few metres across (dry / lush), the same for neighbours
	patchy = sin(dot(origin, W2) * 0.21) * sin(dot(origin, W1.zxy) * 0.17 + 1.3);
}

void fragment() {
	vec4 t = texture(atlas, UV);
	// the normals are the crown's or the clump's own (puffed), the same for both faces of a card:
	// undo the flip the renderer gives a two-sided material's back faces
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ALPHA = t.a;
	// far cards keep their cover as the mipmaps thin the blades out
	ALPHA_SCISSOR_THRESHOLD = mix(cut, 0.16, smoothstep(8.0, 45.0, length(VERTEX)));
	vec3 col = t.rgb;
	float leaf = step(0.25, vc.a);
	float petal = step(0.75, vc.a);
	// petals: the unsaturated (white) pixels take the plant's colour; centres and leaves keep theirs
	float mx = max(col.r, max(col.g, col.b));
	float mn = min(col.r, min(col.g, col.b));
	float white = petal * (1.0 - smoothstep(0.1, 0.32, (mx - mn) / max(mx, 0.001)));
	col = mix(col, col * tint, white);
	// leaves: every plant a little its own green, drier or lusher in patches
	vec3 var_c = mix(vec3(1.08, 1.03, 0.8), vec3(0.82, 0.98, 0.92), clamp(rnd * 0.7 + patchy * 0.4 + 0.15, 0.0, 1.0)) * mix(0.82, 1.12, fract(rnd * 7.3));
	col = mix(col, col * var_c, leaf * (1.0 - white));
	col *= mix(0.5, 1.0, vc.g);
	// leaves are painted at their true (dark) reflectance; the game's ground is graded brighter
	ALBEDO = min(col * mix(mix(gain, leaf_gain, leaf), 1.0, white) * lush, vec3(0.92));
	ROUGHNESS = mix(0.9, 0.62, leaf);
	SPECULAR = mix(0.1, 0.28, leaf);
}

void light() {
	// soft wrap on the puffed normals, and the low sun coming through the leaves from behind
	float ndl = dot(NORMAL, LIGHT);
	float leaf = step(0.25, vc.a);
	float wrap = clamp((ndl + 0.35) / 1.35, 0.0, 1.0);
	float through = (max(-ndl, 0.0) * 0.45 + pow(max(dot(VIEW, -LIGHT), 0.0), 3.0) * 1.1) * leaf * (0.35 + 0.65 * vc.g);
	// a crown is not a wall: a third of the light finds its way through the leaves above
	float att = mix(ATTENUATION, 1.0, 0.34 * leaf * vc.g);
	DIFFUSE_LIGHT += LIGHT_COLOR * att * (vec3(wrap) + through * vec3(1.25, 1.2, 0.42)) / PI;
}
