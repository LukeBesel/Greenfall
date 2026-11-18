shader_type spatial;
// [planet-tidewell] Lumi's reflection on the ocean: a mirrored copy of his model (flipped about
// the water plane) drawn after the opaque pass with no depth test. Each fragment finds where
// its view ray crosses the water and keeps itself only if (a) the water is what the camera sees
// there (depth texture: junk, decks or Lumi in front hide it) and (b) that point is open water
// (bed map below the surface). Cheap stand-in for planar reflections on every preset.
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(0.8);
uniform float glow = 0.0;          // emissive parts (eyes, hover ring) stay bright
uniform float strength = 0.45;
uniform float sea_y = 0.14;
uniform vec3 water_col : source_color = vec3(0.1, 0.4, 0.45);
uniform sampler2D near_tex : filter_linear;
uniform float near_size = 220.0;
uniform sampler2D state_tex : filter_nearest;
uniform int grid_radius = 4;
uniform float hex_size = 10.0;
uniform float lit = 1.0;           // daylight on the real model
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying vec3 wpos;
const float SQRT3 = 1.7320508;

vec2 hex_round(vec2 qr) {
	vec3 c = vec3(qr.x, qr.y, -qr.x - qr.y);
	vec3 r = round(c);
	vec3 d = abs(r - c);
	if (d.x > d.y && d.x > d.z) { r.x = -r.y - r.z; } else if (d.y > d.z) { r.y = -r.x - r.z; }
	return r.xy;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 dir = wpos - cam;
	if (dir.y >= -0.0001 || wpos.y > sea_y) { discard; }
	float t = (sea_y - cam.y) / dir.y;
	vec3 ps = cam + dir * t;  // where the reflected ray leaves the water surface
	// Open water only (the bed map is below the surface; land hexes are not water).
	if (texture(near_tex, ps.xz / near_size + 0.5).r > sea_y - 0.05) { discard; }
	float size = float(grid_radius * 2 + 1);
	vec2 ax = hex_round(vec2((SQRT3 / 3.0 * ps.x - ps.z / 3.0) / hex_size, (2.0 / 3.0 * ps.z) / hex_size));
	if ((abs(ax.x) + abs(ax.y) + abs(ax.x + ax.y)) * 0.5 <= float(grid_radius)) {
		float a = texture(state_tex, (ax + vec2(float(grid_radius)) + 0.5) / size).a;
		if (a < 0.4 || a > 0.6) { discard; }
	}
	// Occlusion: the scene depth at this pixel must be the water surface, not something nearer.
	float raw = texture(depth_tex, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	raw = raw * 2.0 - 1.0;
#endif
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	vec4 vp = INV_PROJECTION_MATRIX * ndc;
	float scene_d = -vp.z / vp.w;
	float surf_d = -(VIEW_MATRIX * vec4(ps, 1.0)).z;
	if (scene_d < surf_d - 0.35) { discard; }
	float fade = smoothstep(2.6, 0.0, sea_y - wpos.y);  // reflection fades with distance below
	float fres = 0.35 + 0.65 * pow(1.0 - clamp(abs(normalize(dir).y), 0.0, 1.0), 2.0);
	vec3 c = mix(water_col, tint * lit, 0.75) + tint * glow;
	ALBEDO = c;
	ALPHA = strength * fade * fres;
}
