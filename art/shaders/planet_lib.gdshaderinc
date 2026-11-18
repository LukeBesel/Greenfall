// [globes] Shared maths for the planet globes (ui/planet_globe.gd): 3D value noise with analytic
// derivatives, FBM / ridged / eroded FBM that also return their gradient (real relief normals in
// one pass), a derivative bump for the non-smooth features (terraces, cracks, dunes), cellular
// noise, and the binary-sun lighting (two directions, the companion's warm tint, a soft terminator).
// Surfaces are unshaded: the globe sets the sun uniforms itself, so a globe looks the same in any
// 3D view, whatever lights that view has.

uniform vec3 sun_a_dir = vec3(-0.6, 0.35, 0.72);  // world space, towards the primary
uniform vec3 sun_a_col = vec3(1.0, 0.95, 0.85);
uniform vec3 sun_b_dir = vec3(-0.45, 0.3, 0.84);  // towards the companion
uniform vec3 sun_b_col = vec3(0.26, 0.16, 0.1);
uniform float restoration : hint_range(0.0, 1.0) = 0.0;
uniform int octaves : hint_range(2, 9) = 7;  // LOD: fewer when small on screen
uniform float seed = 0.0;

float pl_hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.11, 0.17, 0.13));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

vec3 pl_hash3(vec3 p) {
	return vec3(pl_hash(p), pl_hash(p + vec3(31.7, 7.3, 19.1)), pl_hash(p + vec3(5.9, 43.3, 11.7)));
}

// Value noise in -1..1 with its gradient (Inigo Quilez), quintic fade.
vec4 pl_noised(vec3 x) {
	vec3 i = floor(x);
	vec3 w = fract(x);
	vec3 u = w * w * w * (w * (w * 6.0 - 15.0) + 10.0);
	vec3 du = 30.0 * w * w * (w * (w - 2.0) + 1.0);
	float a = pl_hash(i);
	float b = pl_hash(i + vec3(1.0, 0.0, 0.0));
	float c = pl_hash(i + vec3(0.0, 1.0, 0.0));
	float d = pl_hash(i + vec3(1.0, 1.0, 0.0));
	float e = pl_hash(i + vec3(0.0, 0.0, 1.0));
	float f = pl_hash(i + vec3(1.0, 0.0, 1.0));
	float g = pl_hash(i + vec3(0.0, 1.0, 1.0));
	float h = pl_hash(i + vec3(1.0, 1.0, 1.0));
	float k0 = a;
	float k1 = b - a;
	float k2 = c - a;
	float k3 = e - a;
	float k4 = a - b - c + d;
	float k5 = a - c - e + g;
	float k6 = a - b - e + f;
	float k7 = -a + b + c - d + e - f - g + h;
	float v = k0 + k1 * u.x + k2 * u.y + k3 * u.z + k4 * u.x * u.y + k5 * u.y * u.z + k6 * u.z * u.x + k7 * u.x * u.y * u.z;
	vec3 dv = du * vec3(k1 + k4 * u.y + k6 * u.z + k7 * u.y * u.z,
			k2 + k5 * u.z + k4 * u.x + k7 * u.z * u.x,
			k3 + k6 * u.x + k5 * u.y + k7 * u.x * u.y);
	return vec4(-1.0 + 2.0 * v, 2.0 * dv);
}

float pl_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(pl_hash(i), pl_hash(i + vec3(1, 0, 0)), f.x),
				mix(pl_hash(i + vec3(0, 1, 0)), pl_hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(pl_hash(i + vec3(0, 0, 1)), pl_hash(i + vec3(1, 0, 1)), f.x),
				mix(pl_hash(i + vec3(0, 1, 1)), pl_hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

const mat3 PL_ROT = mat3(vec3(0.00, 0.80, 0.60), vec3(-0.80, 0.36, -0.48), vec3(-0.60, -0.48, 0.64));

// Cheap value FBM (0..1), for warps and masks.
float pl_fbm(vec3 p, int oct) {
	float v = 0.0;
	float a = 0.5;
	float n = 0.0;
	for (int i = 0; i < 9; i++) {
		if (i >= oct) {
			break;
		}
		v += a * pl_noise(p);
		n += a;
		p = PL_ROT * p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v / max(n, 1e-4);
}

// Domain warp: a vector field from three cheap FBMs.
vec3 pl_warp(vec3 p, int oct) {
	return vec3(pl_fbm(p + vec3(1.7, 9.2, 0.0), oct), pl_fbm(p + vec3(8.3, 2.8, 5.1), oct), pl_fbm(p + vec3(3.1, 6.4, 7.7), oct)) - 0.5;
}

// FBM with gradient. Returns (value ~-1..1, d/dp). erosion > 0 damps octaves on slopes, which
// gives smooth valleys and sharp, branching mountain ridges (IQ's derivative-damped FBM).
vec4 pl_fbmd(vec3 p, int oct, float gain, float erosion) {
	float v = 0.0;
	vec3 d = vec3(0.0);
	vec3 dsum = vec3(0.0);
	float a = 0.5;
	mat3 jt = mat3(1.0);
	for (int i = 0; i < 9; i++) {
		if (i >= oct) {
			break;
		}
		vec4 n = pl_noised(p);
		vec3 g = jt * n.yzw;
		dsum += g;
		float damp = 1.0 / (1.0 + erosion * dot(dsum, dsum));
		v += a * n.x * damp;
		d += a * g * damp;
		p = PL_ROT * p * 2.03 + vec3(1.7, 9.2, 3.1);
		jt = jt * transpose(PL_ROT) * 2.03;
		a *= gain;
	}
	return vec4(v, d);
}

// Ridged FBM with gradient (0..~1, sharp crests at 1).
vec4 pl_ridged(vec3 p, int oct) {
	float v = 0.0;
	vec3 d = vec3(0.0);
	float a = 0.5;
	float prev = 1.0;
	mat3 jt = mat3(1.0);
	for (int i = 0; i < 9; i++) {
		if (i >= oct) {
			break;
		}
		vec4 n = pl_noised(p);
		float r = 1.0 - abs(n.x);
		float s = n.x >= 0.0 ? -1.0 : 1.0;
		float r2 = r * r;
		v += a * r2 * prev;
		d += a * prev * 2.0 * r * s * (jt * n.yzw);
		prev = clamp(r2 * 1.6, 0.0, 1.0);
		p = PL_ROT * p * 2.03 + vec3(1.7, 9.2, 3.1);
		jt = jt * transpose(PL_ROT) * 2.03;
		a *= 0.5;
	}
	return vec4(v, d);
}

// Cellular: (F1, F2, cell id hash). 3x3x3 search.
vec3 pl_cells(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	float id = 0.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 o = vec3(float(x), float(y), float(z));
				vec3 c = o + pl_hash3(i + o) * 0.9 + 0.05;
				float dd = length(c - f);
				if (dd < f1) {
					f2 = f1;
					f1 = dd;
					id = pl_hash(i + o + 3.3);
				} else if (dd < f2) {
					f2 = dd;
				}
			}
		}
	}
	return vec3(f1, f2, id);
}

// Normal from a 3D height gradient on the unit sphere (object space).
vec3 pl_grad_normal(vec3 n, vec3 grad, float k) {
	vec3 t = grad - n * dot(grad, n);
	return normalize(n - k * t);
}

// Bump from screen-space derivatives of any height (Mikkelsen surface gradient).
vec3 pl_dd_normal(vec3 pos, vec3 n, float h) {
	vec3 dpdx = dFdx(pos);
	vec3 dpdy = dFdy(pos);
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	if (abs(det) < 1e-12) {
		return n;
	}
	vec3 g = (dFdx(h) * r1 + dFdy(h) * r2) / det;
	return normalize(n - g);
}

// Tangent coordinates of p around a unit axis c (for scars, craters, storms).
vec2 pl_tangent_xy(vec3 p, vec3 c) {
	vec3 up = abs(c.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 tx = normalize(cross(up, c));
	vec3 ty = cross(c, tx);
	return vec2(dot(p, tx), dot(p, ty));
}

// Rotate v around unit axis k by angle a (Rodrigues).
vec3 pl_rotate(vec3 v, vec3 k, float a) {
	float c = cos(a);
	float s = sin(a);
	return v * c + cross(k, v) * s + k * dot(k, v) * (1.0 - c);
}

// One sun's diffuse on a surface: ng = geometric (sphere) normal, nb = bumped normal. The soft
// terminator comes from the sphere normal, the relief from the bumped one, so mountains catch light
// right up to the edge of night and throw long dark slopes there.
float pl_diffuse(vec3 ng, vec3 nb, vec3 l, float soft) {
	float geo = dot(ng, l);
	float term = smoothstep(-soft, soft * 1.6, geo);
	float d = clamp(dot(nb, l), 0.0, 1.0);
	return mix(d, d * 0.7 + 0.3 * clamp(geo, 0.0, 1.0), 0.25) * term;
}

// Both suns on a surface with an optional warm reddening along the terminator (atmosphere).
vec3 pl_light2(vec3 ng, vec3 nb, float soft, float redden) {
	vec3 la = normalize(sun_a_dir);
	vec3 lb = normalize(sun_b_dir);
	float ga = dot(ng, la);
	float gb = dot(ng, lb);
	vec3 ca = mix(sun_a_col * vec3(1.0, 0.62, 0.42), sun_a_col, mix(1.0, smoothstep(-0.05, 0.35, ga), redden));
	vec3 cb = mix(sun_b_col * vec3(1.0, 0.7, 0.5), sun_b_col, mix(1.0, smoothstep(-0.05, 0.35, gb), redden));
	return ca * pl_diffuse(ng, nb, la, soft) + cb * pl_diffuse(ng, nb, lb, soft);
}

// How much of either sun reaches this point (0 night .. 1 day), from the sphere normal.
float pl_daylight(vec3 ng) {
	float a = smoothstep(-0.12, 0.2, dot(ng, normalize(sun_a_dir)));
	float b = smoothstep(-0.12, 0.2, dot(ng, normalize(sun_b_dir)));
	float lb = clamp(dot(sun_b_col, vec3(0.333)) / max(dot(sun_a_col, vec3(0.333)), 1e-3), 0.0, 1.0);
	return clamp(max(a, b * lb), 0.0, 1.0);
}

// Blinn-Phong glints from both suns (water, ice). n = bumped world normal, v = to camera.
vec3 pl_spec2(vec3 ng, vec3 n, vec3 v, float power, float strength) {
	vec3 la = normalize(sun_a_dir);
	vec3 lb = normalize(sun_b_dir);
	vec3 ha = normalize(la + v);
	vec3 hb = normalize(lb + v);
	float norm = (power + 8.0) / 25.0;
	float sa = pow(clamp(dot(n, ha), 0.0, 1.0), power) * norm * smoothstep(-0.02, 0.15, dot(ng, la));
	float sb = pow(clamp(dot(n, hb), 0.0, 1.0), power) * norm * smoothstep(-0.02, 0.15, dot(ng, lb));
	return (sun_a_col * sa + sun_b_col * sb) * strength;
}

// Planet shadow on rings/debris: 1 lit .. 0 in the planet's shadow for direction l.
float pl_planet_shadow(vec3 p, vec3 center, float r, vec3 l) {
	vec3 oc = center - p;
	float b = dot(oc, l);
	if (b <= 0.0) {
		return 1.0;
	}
	float d2 = dot(oc, oc) - b * b;
	return smoothstep(r * r * 0.86, r * r * 1.08, d2);
}

vec3 pl_ring_light(vec3 p, vec3 center, float r) {
	return sun_a_col * pl_planet_shadow(p, center, r, normalize(sun_a_dir)) + sun_b_col * pl_planet_shadow(p, center, r, normalize(sun_b_dir));
}
