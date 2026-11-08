class_name TideProps
extends RefCounted
## [p_seas] Tidewell's hero props at the art bar (chunky, bevelled, greebled, two states), built
## from  Each builder takes the env (TidewellEnv or TideSite: rng, groups, materials) and
## a local position / yaw, and fills the env's groups:
##   always  the structure (rust follows restoration through the kit paints, see set_rust)
##   ruin    debris, broken bits, spilled junk
##   green   restored: lit windows and lamps, planters, solar, bunting
##   future  white cladding and thin light trims
## Colliders (PROP layer) go under the always group so robots, skimmers and Lumi bump into hulls,
## legs and cabins instead of driving through them.

static var _cache: Dictionary = {}

## The seas palette (kit "paint:<colour>" keys; colour baked per vertex, one paint draw call).
const LEDGER := "#f5b324"     # the Ledger's yellow: utility parts, booms, legs, rails
const NAVY := "navy"
const ANTIFOUL := "#a3301f"   # hull bottoms below the boot-top
const CREAM := "cream"
const TEAL := "teal"
const ORANGE := "orange"
const TIMBER := "#8f6a47"
const TIMBER2 := "#664a33"

## TideProps names -> kit material keys (docs/ART_KIT.md "Material keys").
const KEYS: Dictionary = {
	"hull": "paint:" + NAVY, "navy": "paint:" + NAVY, "antifoul": "paint:" + ANTIFOUL,
	"ledger": "paint:" + LEDGER, "cream": "paint:main", "teal": "paint:accent",
	"orange": "paint:" + ORANGE, "main": "paint:main", "accent": "paint:accent", "red": "paint:red", "white": "paint:white", "sky": "paint:sky",
	"timber": "paint:" + TIMBER, "timber2": "paint:" + TIMBER2, "rope": "paint:#a08a60",
	"rope_line": "paint:#8a7752", "snow": "paint:#eef3fa", "solar": "paint:#1a2a55",
	"steel": "steel", "steel_plain": "steel", "dark": "dark_steel", "dark_rubber": "rubber",
	"ore": "dirt", "soil": "dirt", "leaf": "leaves", "concrete": "concrete", "hazard": "hazard",
	"glass": "glass", "glass_lit": "trim:warm", "lamp_warm": "trim:warm", "bulb": "trim:warm",
	"lamp_cool": "trim:cool", "lamp_red": "trim:red",
}
## Each site group is built in the kit state that matches when it shows.
const GROUP_STATE: Dictionary = {"always": "repaired", "ruin": "broken", "green": "restored", "mid": "repaired", "future": "restored"}


## Kit key for a TideProps material name (env kept for the old call shape).
static func m(_env: Node, key: String) -> String:
	return str(KEYS.get(key, "paint:" + key))


## Planet palettes (docs/ART_KIT.md): main / accent roles; "cream" and "teal" map onto them.
const PALETTES: Dictionary = {
	"tidewell": {"main": "white", "accent": "sky"},
	"rime": {"main": "#e8eef2", "accent": "navy"},
}


## A kit builder for one of the env's groups, with its planet's palette.
static func builder(env: Node, group: String) -> KitMesh.Builder:
	var rng: RandomNumberGenerator = env.get("_rng")
	var pal: Dictionary = PALETTES["rime" if env is RimeSite else "tidewell"]
	return KitMesh.Builder.new(rng.randi(), pal, str(GROUP_STATE.get(group, "repaired")))


## Commits a builder into the group as one MeshInstance3D (kit materials for its state). The
## always group's meshes are remembered: set_rust re-applies their state as the site recovers.
static func flush(env: Node, b: KitMesh.Builder, group: String) -> MeshInstance3D:
	if b.surface_count() == 0:
		return null
	var mi: MeshInstance3D = KitMesh.instance(b, b.state, group != "ruin")
	mi.name = "Kit_" + group
	_g(env, group).add_child(mi)
	# Lamps the props asked for: shadowless pools of light, only in the restored groups (nothing
	# glows while broken). At most 10 per group to stay cheap.
	if group in ["green", "future"]:
		for k: int in mini(b.lights.size(), 10):
			var ld: Dictionary = b.lights[k]
			var ol := OmniLight3D.new()
			ol.light_color = ld.get("color", KitMat.GLOW["warm"])
			ol.omni_range = float(ld.get("range", 6.0))
			ol.light_energy = float(ld.get("energy", 1.2))
			ol.shadow_enabled = false
			ol.position = (env as Node3D).to_local(ld["pos"]) if (env as Node3D).is_inside_tree() else ld["pos"]
			_g(env, group).add_child(ol)
	if group in ["always", "mid"]:
		var mats: Dictionary = env.get("_mats")
		if not mats.has("_kit_always"):
			mats["_kit_always"] = []
		(mats["_kit_always"] as Array).append(mi)
	return mi


## The kit wear state for a site state: broken while ruined, repaired as it recovers, restored.
static func kit_state(stage: int, restore: float) -> String:
	if stage == 0:
		return "broken" if restore < 0.5 else "repaired"
	if stage == 1 and restore < 0.6:
		return "repaired"
	return "restored"


## Re-applies the always-built structures' kit state (rust, wear, lit glass) for a site state.
## (Named for its old job: rust follows restoration.)
static func set_rust(env: Node, stage: int, restore: float) -> void:
	var st: String = kit_state(stage, restore)
	var mats: Dictionary = env.get("_mats")
	for mi: MeshInstance3D in mats.get("_kit_always", []):
		if is_instance_valid(mi):
			KitMat.apply(mi, st, stage >= 1)
	mats["_kit_state"] = st


static func _g(env: Node, g: String) -> Node3D:
	return (env.get("_groups") as Dictionary)[g]


# --- Ore barge --------------------------------------------------------------------------------------

## The Ledger's half-sunk ore barge (about 52 x 12 m) at local p: settled by the stern with a roll,
## hoppers with slid hatch lids, a funnelled wheelhouse aft, a lattice conveyor boom, forecastle
## windlass and anchor chain, a lost container alongside. Restored: lit bridge and lamps, string
## lights, planters in the hoppers, solar on the wheelhouse.
static func barge(env: Node, p: Vector3, yaw: float) -> void:
	var rng: RandomNumberGenerator = env.get("_rng")
	var always: Node3D = _g(env, "always")
	var a := builder(env, "always")
	var ruin := builder(env, "ruin")
	var grn := builder(env, "green")
	var fut := builder(env, "future")
	var bs := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(5.0)) * Basis(Vector3.FORWARD, deg_to_rad(7.0))
	var o := Vector3(p.x, -2.3, p.z)
	var L: float = 52.0
	var W: float = 12.0
	var D: float = 6.0
	var sheer: float = 1.4
	var deck := func(z: float) -> float: return D + sheer * pow(clampf((z + L * 0.5) / L, 0.0, 1.0), 2.2) - 0.02
	add_mesh(a, m(env, "hull"), hull_mesh(L, W, D, 3.0, 11.0, sheer), Transform3D(bs, o), 0)
	add_mesh(a, m(env, "antifoul"), hull_mesh(L, W, D, 3.0, 11.0, sheer), Transform3D(bs, o), 1)
	# Rub rails / strakes along the midbody and a gunwale cap.
	for sd: float in [-1.0, 1.0]:
		for y: float in [2.1, 4.3]:
			box(a, o, bs, Vector3(sd * (W * 0.5 + 0.03), y, -6.0), Vector3(0.14, 0.22, 36.0), m(env, "steel"))
		pipe(a, o, bs, Vector3(sd * W * 0.51, D + 0.06, -25.0), Vector3(sd * W * 0.51, D + 0.18, 12.0), 0.12, m(env, "ledger"))
		# Bulwark posts + rail, with a gap where it tore away.
		var pts: Array[Vector3] = []
		for z: float in [-17.0, -9.0, -1.0]:
			pts.append(Vector3(sd * W * 0.47, deck.call(z), z))
		rail(a, o, bs, pts, 1.0, m(env, "ledger"))
		pts = [Vector3(sd * W * 0.47, deck.call(6.0), 6.0), Vector3(sd * W * 0.45, deck.call(16.0), 16.0)]
		rail(a, o, bs, pts, 1.0, m(env, "ledger"))
		# Hull number + emblem near the bow (image decals).
		decal(a, o, bs, Vector3(sd * (W * 0.5 + 0.08), 4.9, 17.0), Vector3(sd, 0, 0), 2.4, 2.4, "num_03")
		decal(a, o, bs, Vector3(sd * (W * 0.5 + 0.08), 4.6, -2.0), Vector3(sd, 0, 0), 2.2, 2.2, "logo")
	# Hoppers: coamings with hazard caps, ore heaps, hatch lids (some slid off and tilted).
	for k: int in 4:
		var hz: float = -11.0 + k * 7.6
		var y: float = deck.call(hz)
		box(a, o, bs, Vector3(0, y + 0.45, hz), Vector3(8.6, 1.0, 6.2), m(env, "ledger"))
		box(a, o, bs, Vector3(0, y + 0.97, hz), Vector3(8.7, 0.08, 6.3), m(env, "hazard"))
		box(a, o, bs, Vector3(0, y + 0.7, hz), Vector3(7.6, 0.4, 5.2), m(env, "dark"))
		for j: int in 3:
			add_mesh(a, m(env, "ore"), env.call("_lumpy", j + k, 0.4, 2.2), Transform3D(bs * Basis.from_scale(Vector3(2.4, 0.9, 1.8)), o + bs * Vector3(-2.2 + j * 2.2, y + 0.9, hz + rng.randf_range(-1, 1))))
		var lid_x: float = [0.0, 3.5, -2.0, 6.0][k]
		var tilt: Vector3 = [Vector3(0, 0, 0), Vector3(0, 0, -9), Vector3(4, 8, 0), Vector3(0, 12, -24)][k]
		var lid_y: float = y + 1.25 + absf(tilt.z) * 0.04
		if k != 2:
			box(a, o, bs, Vector3(lid_x, lid_y, hz), Vector3(8.4, 0.35, 5.8), m(env, "teal"), tilt)
			for r: int in 4:
				box(a, o, bs, Vector3(lid_x, lid_y + 0.24, hz - 2.1 + r * 1.4), Vector3(8.0, 0.18, 0.22), m(env, "teal"), tilt, 0.04)
	# Conveyor boom: a lattice truss on a slewing turret, pointing at the sky over the bow.
	var tb := Vector3(0, deck.call(16.0), 16.0)
	pipe(a, o, bs, tb, tb + Vector3(0, 1.4, 0), 1.6, m(env, "ledger"), 18)
	pipe(a, o, bs, tb + Vector3(0, 1.4, 0), tb + Vector3(0, 1.7, 0), 1.75, m(env, "steel"), 18)
	var b0: Vector3 = tb + Vector3(0, 2.0, 0)
	var b1: Vector3 = b0 + Vector3(1.6, 13.0, 13.0)
	var ax: Vector3 = (b1 - b0).normalized()
	var side: Vector3 = ax.cross(Vector3.UP).normalized() * 0.8
	var up: Vector3 = side.cross(ax).normalized() * 1.1
	for c: Vector3 in [side, -side, up]:
		pipe(a, o, bs, b0 + c, b1 + c * 0.7, 0.13, m(env, "ledger"), 8)
	var nseg: int = 9
	for k: int in nseg:
		var t0: float = float(k) / nseg
		var t1: float = float(k + 1) / nseg
		var p0: Vector3 = b0.lerp(b1, t0)
		var p1: Vector3 = b0.lerp(b1, t1)
		var s0: float = lerpf(1.0, 0.7, t0)
		var s1: float = lerpf(1.0, 0.7, t1)
		pipe(a, o, bs, p0 + side * s0, p1 - side * s1, 0.06, m(env, "ledger"), 6)
		pipe(a, o, bs, p0 + side * s0, p1 + up * s1, 0.06, m(env, "ledger"), 6)
		pipe(a, o, bs, p0 - side * s0, p1 + up * s1, 0.06, m(env, "ledger"), 6)
		pipe(a, o, bs, p1 + side * s1, p1 - side * s1, 0.05, m(env, "ledger"), 6)
	box(a, o, bs, b0.lerp(b1, 0.5) - up * 0.15, Vector3(1.3, 0.12, b0.distance_to(b1)), m(env, "dark"), Vector3(-rad_to_deg(asin(ax.y)), rad_to_deg(atan2(ax.x, ax.z)), 0))
	pipe(a, o, bs, b1 + side * 0.8, b1 - side * 0.8, 0.45, m(env, "steel"), 14)
	box(a, o, bs, b1 + ax * 0.6 + up * 0.2, Vector3(2.0, 1.6, 1.6), m(env, "ledger"), Vector3(0, rad_to_deg(atan2(ax.x, ax.z)), 0))
	pipe(a, o, bs, tb + Vector3(1.2, 1.6, 0), b0.lerp(b1, 0.55) - up * 0.3, 0.16, m(env, "steel"), 10)  # luffing ram
	pipe(a, o, bs, tb + Vector3(1.2, 1.6, 0), b0.lerp(b1, 0.28) - up * 0.3, 0.26, m(env, "ledger"), 10)
	# Wheelhouse aft: two tiers, a window band, bridge wings, a funnel with the emblem, a mast.
	var wz: float = -19.5
	var wy: float = deck.call(wz)
	box(a, o, bs, Vector3(0, wy + 1.6, wz), Vector3(9.0, 3.2, 6.0), m(env, "cream"))
	box(a, o, bs, Vector3(0, wy + 3.3, wz), Vector3(9.4, 0.25, 6.4), m(env, "teal"))
	box(a, o, bs, Vector3(0, wy + 4.6, wz + 0.4), Vector3(10.6, 2.4, 4.6), m(env, "cream"))
	box(a, o, bs, Vector3(0, wy + 5.9, wz + 0.4), Vector3(11.2, 0.3, 5.2), m(env, "teal"))
	box(a, o, bs, Vector3(0, wy + 4.85, wz + 2.72), Vector3(9.6, 1.0, 0.14), m(env, "glass"), Vector3(-12, 0, 0))
	for sd: float in [-1.0, 1.0]:
		box(a, o, bs, Vector3(sd * 5.15, wy + 4.85, wz + 0.4), Vector3(0.14, 1.0, 3.6), m(env, "glass"))
		for k: int in 4:
			box(a, o, bs, Vector3(sd * (1.2 + k * 1.15), wy + 1.9, wz + 3.02), Vector3(0.8, 0.8, 0.1), m(env, "glass"))
		vent(a, o, bs, Vector3(sd * 4.52, wy + 1.4, wz - 1.2), 1.4, 1.0, Vector3(sd, 0, 0), m(env, "steel"), m(env, "dark"))
		ladder(a, o, bs, Vector3(sd * 4.7, wy, wz + 2.2), Vector3(sd * 4.7, wy + 3.3, wz + 2.2), 0.6, Vector3(sd, 0, 0), m(env, "steel"))
		lamp(a, grn, o, bs, Vector3(sd * 5.2, wy + 5.9, wz + 2.6), Vector3(sd, 0, 0.4).normalized(), m(env, "steel"), m(env, "lamp_warm"))
		box(grn, o, bs, Vector3(sd * 5.2, wy + 4.85, wz + 0.4), Vector3(0.1, 0.9, 3.4), m(env, "glass_lit"))
	box(a, o, bs, Vector3(1.2, wy + 1.1, wz + 3.05), Vector3(1.1, 2.1, 0.14), m(env, "teal"))  # door
	box(grn, o, bs, Vector3(0, wy + 4.85, wz + 2.78), Vector3(9.3, 0.9, 0.06), m(env, "glass_lit"), Vector3(-12, 0, 0))
	rail(a, o, bs, [Vector3(-5.2, wy + 6.05, wz - 1.8), Vector3(-5.2, wy + 6.05, wz + 2.8), Vector3(5.2, wy + 6.05, wz + 2.8), Vector3(5.2, wy + 6.05, wz - 1.8)] as Array[Vector3], 0.9, m(env, "ledger"))
	var fz: float = wz - 2.0
	pipe(a, o, bs, Vector3(0, wy + 5.0, fz), Vector3(0, wy + 9.5, fz - 0.7), 1.0, m(env, "teal"), 16)
	pipe(a, o, bs, Vector3(0, wy + 8.0, fz - 0.46), Vector3(0, wy + 8.8, fz - 0.58), 1.04, m(env, "ledger"), 16)
	pipe(a, o, bs, Vector3(0, wy + 9.4, fz - 0.68), Vector3(0, wy + 9.7, fz - 0.72), 1.08, m(env, "dark"), 16)
	decal(a, o, bs, Vector3(0, wy + 7.0, fz + 1.02), Vector3(0, 0.06, 1).normalized(), 1.4, 1.4, "logo")
	var mb := Vector3(0, wy + 6.0, wz + 0.4)
	pipe(a, o, bs, mb, mb + Vector3(0, 4.5, 0), 0.14, m(env, "cream"), 10)
	pipe(a, o, bs, mb + Vector3(-1.6, 3.4, 0), mb + Vector3(1.6, 3.4, 0), 0.07, m(env, "cream"), 8)
	box(a, o, bs, mb + Vector3(0, 2.6, 0.3), Vector3(2.4, 0.18, 0.4), m(env, "dark"), Vector3(0, 30, 0))  # radar bar
	pipe(grn, o, bs, mb + Vector3(0, 4.5, 0), mb + Vector3(0, 4.75, 0), 0.12, m(env, "lamp_warm"), 10)
	# Forecastle: windlass, bollards, the anchor chain down to the sea.
	var fc: float = 22.0
	var fy: float = deck.call(fc)
	pipe(a, o, bs, Vector3(-1.6, fy + 0.6, fc), Vector3(1.6, fy + 0.6, fc), 0.5, m(env, "red"), 14)
	box(a, o, bs, Vector3(0, fy + 0.3, fc), Vector3(1.0, 0.7, 1.2), m(env, "steel"))
	for sd: float in [-1.0, 1.0]:
		for z: float in [fc - 4.0, -23.0]:
			var by: float = deck.call(z)
			pipe(a, o, bs, Vector3(sd * 4.2, by, z), Vector3(sd * 4.2, by + 0.7, z), 0.24, m(env, "steel"), 10)
			pipe(a, o, bs, Vector3(sd * 4.2, by, z + 0.7), Vector3(sd * 4.2, by + 0.7, z + 0.7), 0.24, m(env, "steel"), 10)
	var ch0: Vector3 = Vector3(2.6, fy - 0.4, fc + 1.8)
	var ch1: Vector3 = Vector3(5.4, -0.3, fc + 6.0)
	for k: int in 22:
		var cp: Vector3 = ch0.lerp(ch1, float(k) / 21.0) + Vector3(0, -sin(float(k) / 21.0 * PI) * 0.8, 0)
		box(a, o, bs, cp, Vector3(0.12, 0.36, 0.5), m(env, "dark"), Vector3(0, 0, 90.0 * (k % 2)), 0.05)
	# A lost container alongside, half drowned.
	var ct := Vector3(W * 0.5 + 3.2, 1.6, -5.0)
	container(a, o, bs, ct, Vector3(2.5, 2.6, 6.1), m(env, "orange"), Vector3(18, 12, -24))
	# Deck clutter: drums, crates, rope coils (always), debris and toppled bits (ruin).
	var pts: Array[Transform3D] = []
	for k: int in 12:
		var z: float = rng.randf_range(-15.0, 20.0)
		var x: float = rng.randf_range(-5.0, 5.0)
		if absf(x) < 4.6 and fmod(absf(z + 11.0 + 3.8), 7.6) < 7.0:
			x = signf(x + 0.01) * rng.randf_range(4.6, 5.2)
		var tip: bool = rng.randf() < 0.4
		pts.append(Transform3D(bs * Basis(Vector3.UP, rng.randf() * TAU) * (Basis(Vector3.RIGHT, PI * 0.5) if tip else Basis()), o + bs * Vector3(x, deck.call(z) + (0.3 if tip else 0.0), z)))
	env.call("_scatter_models", ["Barrel_01", "barrel_03", "wooden_crate_02", "plastic_jerrycan"], pts, always, 200.0)
	for k: int in 3:
		var cz: float = [-14.0, 3.0, 12.0][k]
		var cx: float = [-5.0, 5.1, -5.0][k]
		var ccol: String = ["teal", "orange", "red"][k]
		box(a, o, bs, Vector3(cx, deck.call(cz) + 0.45, cz), Vector3(1.2, 0.9, 1.6), m(env, ccol), Vector3(0, rng.randf_range(-20, 20), 0))
	var coil := TorusMesh.new()
	coil.inner_radius = 0.3
	coil.outer_radius = 0.62
	for k: int in 3:
		var rp := Vector3([3.8, -3.6, 2.0][k], 0, [-23.5, 19.5, 20.5][k])
		for j: int in 3:
			add_mesh(a, m(env, "rope"), coil, Transform3D(bs, o + bs * (rp + Vector3(0, deck.call(rp.z) + 0.1 + j * 0.14, 0))))
	for k: int in 6:
		var dz: float = rng.randf_range(-16.0, 18.0)
		box(ruin, o, bs, Vector3(rng.randf_range(-4.5, 4.5), deck.call(dz) + 0.15, dz), Vector3(rng.randf_range(0.8, 2.0), 0.12, rng.randf_range(0.5, 1.4)), m(env, "steel"), Vector3(rng.randf_range(-15, 15), rng.randf() * 360.0, rng.randf_range(-15, 15)))
	# Restored: planters in the hoppers, solar on the wheelhouse, string lights mast -> bow.
	for k: int in 4:
		var hz: float = -11.0 + k * 7.6
		var y: float = deck.call(hz)
		box(grn, o, bs, Vector3(0, y + 1.0, hz), Vector3(7.6, 0.2, 5.2), m(env, "soil"))
		for j: int in 5:
			var s: float = rng.randf_range(0.7, 1.3)
			add_mesh(grn, m(env, "leaf"), env.call("_lumpy", 5 + j % 3, 0.5, 3.0), Transform3D(bs * Basis.from_scale(Vector3(s * 1.3, s, s * 1.3)), o + bs * Vector3(rng.randf_range(-2.8, 2.8), y + 1.4, hz + rng.randf_range(-1.8, 1.8))))
	for k: int in 3:
		box(grn, o, bs, Vector3(-3.0 + k * 3.0, wy + 6.45, wz - 0.4), Vector3(2.6, 0.08, 3.4), m(env, "solar"), Vector3(-10, 0, 0))
	var bulb := SphereMesh.new()
	bulb.radius = 0.09
	bulb.height = 0.18
	bulb.radial_segments = 8
	bulb.rings = 4
	var top_m: Vector3 = mb + Vector3(0, 4.4, 0)
	for end: Vector3 in [Vector3(0, deck.call(24.0) + 1.0, 24.5), Vector3(0, deck.call(-25.0) + 0.8, -25.5)]:
		for k: int in 16:
			var t: float = (float(k) + 0.5) / 16.0
			var lp: Vector3 = top_m.lerp(end, t) - Vector3(0, sin(t * PI) * 1.2, 0)
			add_mesh(grn, m(env, "bulb"), bulb, Transform3D(bs, o + bs * lp))
		pipe(grn, o, bs, top_m, end, 0.012, m(env, "dark"), 4)
	# Future: white cladding over the wheelhouse and a thin light line at the deck edge.
	box(fut, o, bs, Vector3(0, wy + 3.1, wz + 0.2), Vector3(11.4, 6.4, 6.8), m(env, "white"))
	for sd: float in [-1.0, 1.0]:
		box(fut, o, bs, Vector3(sd * W * 0.51, D + 0.32, -6.0), Vector3(0.05, 0.05, 36.0), m(env, "lamp_cool"), Vector3.ZERO, 0.01)
	flush(env, a, "always")
	flush(env, ruin, "ruin")
	flush(env, grn, "green")
	flush(env, fut, "future")
	# Colliders: the hull in four tilted slices, the wheelhouse, the container, the boom turret.
	for k: int in 4:
		var z: float = -19.5 + k * 13.0
		var hw: float = W * (1.0 if k < 3 else 0.7)
		solid_box(always, o, bs, Vector3(0, D * 0.5 + 0.2, z), Vector3(hw, D + 0.6, 13.0))
	solid_box(always, o, bs, Vector3(0, wy + 3.0, wz), Vector3(10.0, 6.0, 6.0))
	solid_box(always, o, bs, ct, Vector3(2.5, 2.6, 6.1), Vector3(18, 12, -24))
	if env.get("_decks") is Array:
		(env.get("_decks") as Array).append(Vector3(p.x, p.z, 28.0))
	# Junk spilled from the hoppers, floating around the wreck while ruined.
	var fl: Array[Transform3D] = []
	for k: int in 40:
		var ang: float = rng.randf() * TAU
		var d: float = rng.randf_range(10.0, 34.0)
		fl.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(p.x + cos(ang) * d, TidewellEnv.SEA_Y - 0.12, p.z + sin(ang) * d)))
	env.call("_scatter_models", ["Barrel_01", "bleach_bottle", "wooden_crate_02", "plastic_jerrycan", "lifebuoy"], fl, _g(env, "ruin"), 220.0)


# --- Jack-up dredge rig ------------------------------------------------------------------------------

## A Ledger jack-up dredging rig at local p facing yaw (number = hull number): four K-braced
## lattice legs through jack houses, a plated hull with rails, stacked crew quarters, a helideck,
## a derrick, a lattice crane, a bucket-ladder boom into the sea, pipe racks, a lifeboat on davits
## and a stair tower down to a boat landing. Restored: lit windows and lamps; future: white
## quarters, thin light trims, solar.
static func rig(env: Node, p: Vector3, yaw: float, number: int = 7) -> void:
	var rng: RandomNumberGenerator = env.get("_rng")
	var always: Node3D = _g(env, "always")
	var a := builder(env, "always")
	var grn := builder(env, "green")
	var fut := builder(env, "future")
	var ruin := builder(env, "ruin")
	var bs := Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, deg_to_rad(2.5))
	var o := Vector3(p.x, 0.0, p.z)
	var dy: float = 10.0          # hull bottom
	var hx: float = 14.0
	var hz: float = 11.0
	var top: float = dy + 3.4     # main deck
	# Hull: plated box with a chamfer, strakes, hazard band, deck rail.
	box(a, o, bs, Vector3(0, dy + 1.7, 0), Vector3(hx * 2.0, 3.4, hz * 2.0), m(env, "hull"), Vector3.ZERO, 0.45)
	box(a, o, bs, Vector3(0, dy + 0.12, 0), Vector3(hx * 2.0 - 0.6, 0.3, hz * 2.0 - 0.6), m(env, "hazard"), Vector3.ZERO, 0.08)
	for sd: float in [-1.0, 1.0]:
		side_wall(a, o, bs, Vector3(0, dy + 0.3, sd * (hz + 0.05)), Vector3(0, 0, sd), hx * 2.0 - 1.0, 2.8, m(env, "hull"), {"panel": Vector2(2.4, 1.4), "hazard": true})
		side_wall(a, o, bs, Vector3(sd * (hx + 0.05), dy + 0.3, 0), Vector3(sd, 0, 0), hz * 2.0 - 1.0, 2.8, m(env, "hull"), {"panel": Vector2(2.4, 1.4), "hazard": true})
		decal(a, o, bs, Vector3(sd * (hx + 0.05), dy + 1.9, -4.0), Vector3(sd, 0, 0), 2.4, 2.4, "logo")
		decal(a, o, bs, Vector3(sd * (hx + 0.05), dy + 1.9, 4.0), Vector3(sd, 0, 0), 2.2, 2.2, "num_%02d" % clampi(number, 1, 6))
	rail(a, o, bs, [Vector3(-hx + 0.3, top, -hz + 0.3), Vector3(hx - 0.3, top, -hz + 0.3), Vector3(hx - 0.3, top, hz - 0.3), Vector3(-hx + 0.3, top, hz - 0.3), Vector3(-hx + 0.3, top, -hz + 3.0)] as Array[Vector3], 1.1, m(env, "ledger"))
	# Legs: triangular lattice towers with K-bracing, red/white tips, jack houses at the deck.
	for lx: float in [-1.0, 1.0]:
		for lz: float in [-1.0, 1.0]:
			var lc := Vector3(lx * (hx - 2.2), 0, lz * (hz - 2.2))
			tower(a, o, bs, lc, -4.0, top + 13.0, 1.5, 1.5, 3, m(env, "ledger"), 0.24, 2.6, PI * 0.5 * (lx + lz))
			tower(a, o, bs, lc, top + 11.0, top + 13.0, 1.56, 1.56, 3, m(env, "red"), 0.27, 1.0, PI * 0.5 * (lx + lz))
			box(a, o, bs, lc + Vector3(0, top + 1.6, 0), Vector3(4.4, 3.2, 4.4), m(env, "teal"))
			box(a, o, bs, lc + Vector3(0, top + 3.3, 0), Vector3(4.7, 0.25, 4.7), m(env, "steel"))
			vent(a, o, bs, lc + Vector3(0, top + 1.8, 2.25 * lz), 1.4, 0.9, Vector3(0, 0, lz), m(env, "steel"), m(env, "dark"))
			solid_cyl(always, o, bs, lc + Vector3(0, -3.0, 0), lc + Vector3(0, dy, 0), 1.7)
			box(ruin, o, bs, lc + Vector3(0, TidewellEnv.SEA_Y + 0.02, 0), Vector3(5.0, 0.04, 5.0), m(env, "dark"), Vector3(0, rng.randf() * 90.0, 0), 0.01)
	# Crew quarters: three stacked tiers with window rows, doors, AC boxes, dish and antenna.
	var qc := Vector3(-hx + 6.5, top, -hz + 5.5)
	var tiers: Array = [[Vector3(10.0, 3.0, 8.0), "cream"], [Vector3(9.0, 2.8, 7.0), "orange"], [Vector3(7.0, 2.6, 5.6), "cream"]]
	var ty: float = 0.0
	for k: int in tiers.size():
		var sz: Vector3 = tiers[k][0]
		box(a, o, bs, qc + Vector3(0, ty + sz.y * 0.5, 0), sz, m(env, str(tiers[k][1])))
		box(a, o, bs, qc + Vector3(0, ty + sz.y + 0.1, 0), sz + Vector3(0.4, -sz.y + 0.2, 0.4), m(env, "teal"))
		var nw: int = int(sz.x / 1.6)
		for w: int in nw:
			var wx: float = -sz.x * 0.5 + 0.9 + w * (sz.x - 1.8) / maxf(1.0, nw - 1)
			for sd: float in [-1.0, 1.0]:
				box(a, o, bs, qc + Vector3(wx, ty + sz.y * 0.58, sd * sz.z * 0.5), Vector3(0.9, 0.75, 0.12), m(env, "glass"), Vector3.ZERO, 0.03)
				if (w + k) % 3 != 1:
					box(grn, o, bs, qc + Vector3(wx, ty + sz.y * 0.58, sd * (sz.z * 0.5 + 0.05)), Vector3(0.8, 0.65, 0.04), m(env, "glass_lit"), Vector3.ZERO, 0.01)
		box(a, o, bs, qc + Vector3(sz.x * 0.5 + 0.35, ty + sz.y * 0.4, sz.z * 0.2), Vector3(0.7, 0.9, 1.3), m(env, "steel"))
		ladder(a, o, bs, qc + Vector3(sz.x * 0.5 + 0.2, ty, -sz.z * 0.3), qc + Vector3(sz.x * 0.5 + 0.2, ty + sz.y + 0.2, -sz.z * 0.3), 0.6, Vector3(1, 0, 0), m(env, "steel"))
		ty += sz.y + 0.2
	box(a, o, bs, qc + Vector3(1.5, 1.05, 4.06), Vector3(1.1, 2.1, 0.14), m(env, "teal"))
	pipe(a, o, bs, qc + Vector3(-1.5, ty, 0), qc + Vector3(-1.5, ty + 6.0, 0), 0.1, m(env, "steel"), 8)
	pipe(a, o, bs, qc + Vector3(1.6, ty, 1.0), qc + Vector3(1.6, ty + 1.0, 1.0), 0.12, m(env, "steel"), 8)
	pipe(a, o, bs, qc + Vector3(1.6, ty + 1.3, 1.4), qc + Vector3(1.6, ty + 1.5, 0.7), 0.8, m(env, "cream"), 16)
	pipe(grn, o, bs, qc + Vector3(-1.5, ty + 6.0, 0), qc + Vector3(-1.5, ty + 6.3, 0), 0.13, m(env, "lamp_warm"), 8)
	decal(a, o, bs, qc + Vector3(0, 4.4, 4.0), Vector3(0, 0, 1), 1.8, 1.8, "logo")
	# Helideck: an octagon cantilevered past the quarters on a truss, with the H and a net rail.
	var hc := Vector3(-hx - 4.5, ty + top - 0.6, -hz + 5.5)
	box(a, o, bs, hc + Vector3(0, -0.2, 0), Vector3(8.4, 0.5, 8.4), m(env, "steel"), Vector3(0, 22.5, 0), 0.2)
	box(a, o, bs, hc + Vector3(0, -0.2, 0), Vector3(8.4, 0.5, 8.4), m(env, "steel"), Vector3(0, 67.5, 0), 0.2)
	helipad(always, o + bs * (hc + Vector3(0, 0.06, 0)), 7.2)
	for k: int in 3:
		truss(a, o, bs, hc + Vector3(4.2, -0.5, -3.0 + k * 3.0), hc + Vector3(9.2, -ty + 0.5, -2.0 + k * 2.0), 0.6, 0.6, m(env, "ledger"), 0.12)
	# Derrick on its drill floor.
	var dc := Vector3(hx - 6.5, top, hz - 5.0)
	box(a, o, bs, dc + Vector3(0, 1.4, 0), Vector3(7.0, 2.8, 7.0), m(env, "ledger"))
	box(a, o, bs, dc + Vector3(0, 2.9, 0), Vector3(7.4, 0.3, 7.4), m(env, "steel"))
	tower(a, o, bs, dc, 3.0, 24.0, 2.9, 0.8, 4, m(env, "ledger"), 0.18, 2.6, PI * 0.25)
	box(a, o, bs, dc + Vector3(0, 24.6, 0), Vector3(2.0, 1.4, 2.0), m(env, "red"))
	box(a, o, bs, dc + Vector3(0, 15.0, 0), Vector3(3.2, 0.2, 3.2), m(env, "steel"))
	pipe(grn, o, bs, dc + Vector3(0, 25.3, 0), dc + Vector3(0, 25.6, 0), 0.14, m(env, "lamp_warm"), 8)
	# Crane: pedestal, orange cab, lattice boom, hook block.
	var cc := Vector3(hx - 3.0, top, -hz + 3.0)
	pipe(a, o, bs, cc, cc + Vector3(0, 4.0, 0), 1.0, m(env, "ledger"), 16)
	box(a, o, bs, cc + Vector3(0, 5.2, 0), Vector3(2.6, 2.4, 3.2), m(env, "orange"), Vector3(0, -30, 0))
	box(a, o, bs, cc + Vector3(0.6, 5.5, 1.2), Vector3(1.4, 1.0, 0.1), m(env, "glass"), Vector3(0, -30, 0), 0.02)
	var bt0: Vector3 = cc + Vector3(-0.8, 5.0, -0.4)
	var bt1: Vector3 = cc + Vector3(-12.0, 16.0, -7.0)
	truss(a, o, bs, bt0, bt1, 1.2, 1.0, m(env, "ledger"), 0.12, 0.45)
	pipe(a, o, bs, bt1, bt1 + Vector3(0, -9.0, 0), 0.02, m(env, "dark"), 4)
	box(a, o, bs, bt1 + Vector3(0, -9.4, 0), Vector3(0.6, 0.8, 0.4), m(env, "ledger"))
	# Bucket ladder: lattice boom off the bow end down into the sea, a bucket chain, tumbler.
	var la := Vector3(hx + 0.5, dy + 2.4, 1.5)
	var lb := Vector3(hx + 17.0, -3.0, 2.5)
	truss(a, o, bs, la, lb, 2.2, 1.2, m(env, "steel"), 0.22)
	pipe(a, o, bs, la + Vector3(0, 0.6, -1.4), la + Vector3(0, 0.6, 1.4), 0.9, m(env, "red"), 16)
	var lax: Vector3 = (lb - la).normalized()
	for k: int in 14:
		var t: float = float(k) / 13.0
		var bp: Vector3 = la.lerp(lb, t) + Vector3(0, 1.5, 0)
		if bp.y < TidewellEnv.SEA_Y - 0.6:
			continue
		box(a, o, bs, bp, Vector3(1.6, 0.9, 1.3), m(env, "ledger"), Vector3(-rad_to_deg(asin(lax.y)), rad_to_deg(atan2(lax.x, lax.z)), 0), 0.12)
	solid_cyl(always, o, bs, la.lerp(lb, 0.45), lb, 1.6)
	# Pipe rack, tanks, containers along the deck.
	for k: int in 3:
		flanged_pipe(a, o, bs, Vector3(-4.0, top + 0.7 + k * 0.5, 4.0 + k * 0.6), Vector3(8.0, top + 0.7 + k * 0.5, 4.0 + k * 0.6), 0.22, m(env, ["teal", "red", "steel"][k]), m(env, "steel"), 3.0)
	for x: float in [-4.0, 0.0, 4.0, 8.0]:
		box(a, o, bs, Vector3(x, top + 0.7, 4.6), Vector3(0.25, 1.4, 2.4), m(env, "steel"))
	for k: int in 2:
		var tc := Vector3(1.0 + k * 3.2, top + 1.2, -6.5)
		pipe(a, o, bs, tc + Vector3(0, 0, -2.6), tc + Vector3(0, 0, 2.6), 1.2, m(env, "cream" if k == 0 else "teal"), 18)
		for z: float in [-1.6, 1.6]:
			box(a, o, bs, tc + Vector3(0, -0.8, z), Vector3(2.0, 0.8, 0.4), m(env, "steel"))
	var cols: Array[String] = ["orange", "teal", "red", "ledger"]
	for k: int in 4:
		var cpos := Vector3(-1.0 + (k % 2) * 6.4, top + 1.3 + (k / 2) * 2.6, 9.0 - (k / 2) * 0.4)
		container(a, o, bs, cpos, Vector3(6.0, 2.5, 2.4), m(env, cols[k]), Vector3(0, rng.randf_range(-3, 3), 0))
	# Lifeboat on davits over the side, and a stair tower to a boat landing.
	var lbp := Vector3(-6.0, top + 1.5, hz + 1.8)
	add_mesh(a, m(env, "orange"), hull_mesh(6.5, 2.4, 1.3, 0.5, 1.6, 0.2), Transform3D(bs * Basis(Vector3.UP, PI * 0.5), o + bs * lbp))
	box(a, o, bs, lbp + Vector3(0, 1.6, 0), Vector3(5.2, 0.7, 2.0), m(env, "orange"))
	for dx: float in [-2.6, 2.6]:
		pipe(a, o, bs, Vector3(-6.0 + dx, top, hz - 0.6), Vector3(-6.0 + dx, top + 3.4, hz + 1.8), 0.14, m(env, "steel"), 8)
	var st0 := Vector3(6.0, TidewellEnv.SEA_Y + 0.5, hz + 3.0)
	box(a, o, bs, st0, Vector3(5.0, 0.5, 3.0), m(env, "ledger"))
	solid_box(always, o, bs, st0 + Vector3(0, -0.5, 0), Vector3(5.0, 1.6, 3.0))
	tower(a, o, bs, st0 + Vector3(0, 0, 0), -2.0, top, 1.8, 1.8, 4, m(env, "steel"), 0.12, 2.0, PI * 0.25)
	var sy: float = st0.y + 0.3
	var flight: int = 0
	while sy < top - 0.5:
		var dz: float = 1.0 if flight % 2 == 0 else -1.0
		var s0 := st0 + Vector3(-1.2, sy - st0.y, -dz * 0.8)
		var s1 := st0 + Vector3(1.2, minf(sy + 2.4, top) - st0.y, dz * 0.8)
		box(a, o, bs, (s0 + s1) * 0.5, Vector3(1.0, 0.12, s0.distance_to(s1)), m(env, "ledger"), Vector3(-rad_to_deg(atan2(s1.y - s0.y, Vector2(s1.x - s0.x, s1.z - s0.z).length())), rad_to_deg(atan2(s1.x - s0.x, s1.z - s0.z)), 0), 0.03)
		sy += 2.4
		flight += 1
	solid_cyl(always, o, bs, st0 + Vector3(0, -2.0, 0), st0 + Vector3(0, top - st0.y, 0), 1.9)
	# Lamps (lit when restored) round the deck edge, tyres as fenders on the landing.
	for k: int in 6:
		var lp := Vector3(-hx + 2.0 + k * 5.2, top + 1.15, hz - 0.3)
		lamp(a, grn, o, bs, lp, Vector3(0, 0, 1), m(env, "steel"), m(env, "lamp_warm"))
	# Future: white cladding on the quarters, thin light trims, solar on the containers.
	box(fut, o, bs, qc + Vector3(0, ty * 0.5, 0), Vector3(10.4, ty + 0.1, 8.4), m(env, "white"))
	box(fut, o, bs, Vector3(0, top - 0.05, 0), Vector3(hx * 2.0 + 0.1, 0.06, hz * 2.0 + 0.1), m(env, "lamp_cool"), Vector3.ZERO, 0.01)
	for k: int in 4:
		box(fut, o, bs, Vector3(-1.0 + (k % 2) * 6.4, top + 5.3, 8.6 + (k / 2) * 0.1), Vector3(5.6, 0.08, 2.2), m(env, "solar"), Vector3(-8, 0, 0))
	# Ruin: drifting debris under the legs, a toppled container on the deck.
	container(ruin, o, bs, Vector3(-9.0, top + 1.0, 6.0), Vector3(6.0, 2.5, 2.4), m(env, "teal"), Vector3(0, 40, 86), 0.3)
	flush(env, a, "always")
	flush(env, grn, "green")
	flush(env, fut, "future")
	flush(env, ruin, "ruin")


# --- Raft hub ------------------------------------------------------------------------------------------

## A lived-in shack on a deck: bevelled walls with corrugation ribs, a pitched roof with overhang
## and ridge cap, framed door with a step and a lamp, framed windows with sills and shutters, an AC
## box, a stove pipe, a flower box (restored). Colour from `paint` ("cream", "teal", "orange").
static func shack(env: Node, a: KitMesh.Builder, grn: KitMesh.Builder, fut: KitMesh.Builder, o: Vector3, yaw: float, size: Vector3, paint: String, trim: String) -> void:
	var bs := Basis(Vector3.UP, yaw)
	var hx: float = size.x * 0.5
	var hz: float = size.z * 0.5
	box(a, o, bs, Vector3(0, 0.14, 0), Vector3(size.x + 0.3, 0.28, size.z + 0.3), m(env, "steel"))
	box(a, o, bs, Vector3(0, size.y * 0.5 + 0.2, 0), Vector3(size.x, size.y, size.z), m(env, paint))
	for sd: float in [-1.0, 1.0]:
		ribs(a, o, bs, Vector3(-hx + 0.3, size.y * 0.5 + 0.2, sd * hz), Vector3(hx - 0.3, size.y * 0.5 + 0.2, sd * hz), int(size.x / 0.55), size.y - 0.3, Vector3(0, 0, sd), m(env, paint))
	# corner posts
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			box(a, o, bs, Vector3(cx * hx, size.y * 0.5 + 0.2, cz * hz), Vector3(0.26, size.y + 0.1, 0.26), m(env, trim))
	# Pitched roof: two slabs with overhang, a ridge cap, gutters.
	var pitch: float = 20.0
	var rl: float = (hz + 0.5) / cos(deg_to_rad(pitch))
	var rise: float = tan(deg_to_rad(pitch)) * (hz + 0.5)
	for sd: float in [-1.0, 1.0]:
		box(a, o, bs, Vector3(0, size.y + 0.2 + rise * 0.5, sd * (hz + 0.5) * 0.5), Vector3(size.x + 0.9, 0.18, rl), m(env, "red"), Vector3(sd * pitch, 0, 0), 0.06)
		for k: int in int(size.x / 0.6) + 1:
			box(a, o, bs, Vector3(-hx - 0.3 + k * 0.6, size.y + 0.31 + rise * 0.5, sd * (hz + 0.5) * 0.5), Vector3(0.07, 0.08, rl), m(env, "red"), Vector3(sd * pitch, 0, 0), 0.02)
		pipe(a, o, bs, Vector3(-hx - 0.4, size.y + 0.12, sd * (hz + 0.55)), Vector3(hx + 0.4, size.y + 0.12, sd * (hz + 0.55)), 0.08, m(env, "steel"), 8)
	box(a, o, bs, Vector3(0, size.y + 0.25 + rise, 0), Vector3(size.x + 1.0, 0.2, 0.42), m(env, trim))
	# Gable ends.
	for sx: float in [-1.0, 1.0]:
		box(a, o, bs, Vector3(sx * hx, size.y + 0.2 + rise * 0.35, 0), Vector3(0.16, rise * 0.7, size.z * 0.7), m(env, paint))
	# Door (front, +z) with a frame, step, lamp and number board.
	box(a, o, bs, Vector3(hx * 0.4, 1.25, hz + 0.02), Vector3(1.25, 2.2, 0.14), m(env, trim))
	box(a, o, bs, Vector3(hx * 0.4, 1.2, hz + 0.08), Vector3(0.95, 2.0, 0.08), m(env, "timber"), Vector3.ZERO, 0.02)
	box(a, o, bs, Vector3(hx * 0.4, 0.3, hz + 0.45), Vector3(1.4, 0.2, 0.6), m(env, "steel"))
	lamp(a, grn, o, bs, Vector3(hx * 0.4, 2.55, hz + 0.05), Vector3(0, 0, 1), m(env, "steel"), m(env, "lamp_warm"))
	# Windows: frame, glass, sill, shutters; lit glass in the green group.
	var wins: Array = [[Vector3(-hx * 0.4, 1.6, hz), Vector3(0, 0, 1)], [Vector3(-hx * 0.2, 1.6, -hz), Vector3(0, 0, -1)], [Vector3(hx, 1.6, 0), Vector3(1, 0, 0)]]
	for w: Array in wins:
		var wp: Vector3 = w[0]
		var wn: Vector3 = w[1]
		var yaw_d: float = rad_to_deg(atan2(wn.x, wn.z))
		box(a, o, bs, wp + wn * 0.05, Vector3(1.2, 1.0, 0.12), m(env, trim), Vector3(0, yaw_d, 0))
		box(a, o, bs, wp + wn * 0.1, Vector3(0.95, 0.75, 0.06), m(env, "glass"), Vector3(0, yaw_d, 0), 0.01)
		box(grn, o, bs, wp + wn * 0.13, Vector3(0.9, 0.7, 0.03), m(env, "glass_lit"), Vector3(0, yaw_d, 0), 0.01)
		box(a, o, bs, wp + wn * 0.18 + Vector3(0, -0.56, 0), Vector3(1.4, 0.1, 0.28), m(env, trim), Vector3(0, yaw_d, 0))
		var side: Vector3 = wn.cross(Vector3.UP)
		for s2: float in [-1.0, 1.0]:
			box(a, o, bs, wp + wn * 0.1 + side * s2 * 0.82, Vector3(0.42, 1.05, 0.06), m(env, "teal" if paint != "teal" else "orange"), Vector3(0, yaw_d + s2 * 12.0, 0), 0.02)
		box(grn, o, bs, wp + wn * 0.32 + Vector3(0, -0.72, 0), Vector3(1.2, 0.26, 0.3), m(env, "timber"), Vector3(0, yaw_d, 0))
		for k: int in 3:
			add_mesh(grn, m(env, "leaf"), env.call("_lumpy", 5 + k, 0.5, 3.0), Transform3D(bs * Basis.from_scale(Vector3(0.28, 0.24, 0.2)), o + bs * (wp + wn * 0.32 + side * (k - 1) * 0.36 + Vector3(0, -0.5, 0))))
	# AC box, stove pipe with a cap, a little antenna.
	box(a, o, bs, Vector3(-hx - 0.4, 1.0, -hz * 0.3), Vector3(0.7, 0.8, 1.1), m(env, "cream"))
	vent(a, o, bs, Vector3(-hx - 0.76, 1.0, -hz * 0.3), 0.6, 0.6, Vector3(-1, 0, 0), m(env, "steel"), m(env, "dark"))
	pipe(a, o, bs, Vector3(-hx * 0.6, size.y, -hz * 0.4), Vector3(-hx * 0.6, size.y + rise + 1.4, -hz * 0.4), 0.14, m(env, "steel"), 10)
	pipe(a, o, bs, Vector3(-hx * 0.6, size.y + rise + 1.4, -hz * 0.4), Vector3(-hx * 0.6, size.y + rise + 1.55, -hz * 0.4), 0.3, m(env, "dark"), 10)
	pipe(a, o, bs, Vector3(hx * 0.6, size.y + rise, 0), Vector3(hx * 0.6, size.y + rise + 2.2, 0), 0.03, m(env, "steel"), 6)
	box(fut, o, bs, Vector3(0, size.y * 0.5 + 0.2, 0), Vector3(size.x + 0.1, size.y + 0.05, size.z + 0.1), m(env, "white"))
	solid_box(_g(env, "always"), o, bs, Vector3(0, size.y * 0.5 + 0.2, 0), Vector3(size.x + 0.3, size.y + 0.4, size.z + 0.3))


## A rectangular timber platform module centred at local c (size sx x sz, deck top at y): plank
## boards in two tones over a bevelled rim beam, steel corner plates, orange pontoon floats along
## the long sides (with the algae waterline), cleats. Adds a WORLD-layer deck collider.
static func platform(env: Node, a: KitMesh.Builder, o: Vector3, bs: Basis, c: Vector3, sx: float, sz: float, y: float) -> void:
	var rng: RandomNumberGenerator = env.get("_rng")
	var x: float = -sx * 0.5 + 0.3
	var i: int = 0
	while x < sx * 0.5 - 0.35:
		var w: float = 0.5
		var z: float = -sz * 0.5 + 0.3
		while z < sz * 0.5 - 0.35:
			var ln: float = minf(rng.randf_range(2.2, 4.2), sz * 0.5 - 0.3 - z)
			box(a, o, bs, c + Vector3(x + w * 0.5, y - 0.07 + rng.randf_range(-0.01, 0.01), z + ln * 0.5), Vector3(w - 0.05, 0.14, ln - 0.05), m(env, "timber" if (i + int(z)) % 3 != 0 else "timber2"), Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4)), 0.035)
			z += ln
		x += w
		i += 1
	box(a, o, bs, c + Vector3(0, y - 0.3, 0), Vector3(sx - 0.4, 0.3, sz - 0.4), m(env, "dark"), Vector3.ZERO, 0.05)
	for sd: float in [-1.0, 1.0]:
		side_wall(a, o, bs, c + Vector3(0, y - 0.45, sd * (sz * 0.5 - 0.05)), Vector3(0, 0, sd), sx, 0.5, m(env, "timber2"), {"panel": Vector2(2.0, 0.5), "depth": 0.1})
		side_wall(a, o, bs, c + Vector3(sd * (sx * 0.5 - 0.05), y - 0.45, 0), Vector3(sd, 0, 0), sz, 0.5, m(env, "timber2"), {"panel": Vector2(2.0, 0.5), "depth": 0.1})
		var n: int = maxi(2, int(sx / 4.5))
		for k: int in n:
			var px: float = -sx * 0.5 + 1.6 + k * (sx - 3.2) / maxf(1.0, n - 1)
			pipe(a, o, bs, c + Vector3(px, TidewellEnv.SEA_Y + 0.15, sd * (sz * 0.5 - 1.6) - 1.4), c + Vector3(px, TidewellEnv.SEA_Y + 0.15, sd * (sz * 0.5 - 1.6) + 1.4), 0.75, m(env, "orange"), 16)
			pipe(a, o, bs, c + Vector3(px, TidewellEnv.SEA_Y + 0.15, sd * (sz * 0.5 - 1.6) - 1.48), c + Vector3(px, TidewellEnv.SEA_Y + 0.15, sd * (sz * 0.5 - 1.6) - 1.36), 0.85, m(env, "steel"), 16)
			pipe(a, o, bs, c + Vector3(px, TidewellEnv.SEA_Y + 0.15, sd * (sz * 0.5 - 1.6) + 1.36), c + Vector3(px, TidewellEnv.SEA_Y + 0.15, sd * (sz * 0.5 - 1.6) + 1.48), 0.85, m(env, "steel"), 16)
		for k: int in 3:
			var cx: float = -sx * 0.3 + k * sx * 0.3
			box(a, o, bs, c + Vector3(cx, y + 0.1, sd * (sz * 0.5 - 0.15)), Vector3(0.6, 0.12, 0.2), m(env, "steel"), Vector3.ZERO, 0.03)
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			box(a, o, bs, c + Vector3(cx * (sx * 0.5 - 0.35), y + 0.01, cz * (sz * 0.5 - 0.35)), Vector3(0.8, 0.04, 0.8), m(env, "steel"), Vector3.ZERO, 0.015)
			# old tyre fenders hang off the corners
	solid_box(_g(env, "always"), o, bs, c + Vector3(0, y - 0.6, 0), Vector3(sx, 1.2, sz), Vector3.ZERO, PhysLayers.WORLD)


## The anchored raft base: three timber platform modules joined by gangways (workshop, store and
## crane / fuel), a slipway into the water, moorings to buoys. Ruin: junk heaps, a toppled drum
## stack, dark lamps; restored: planters, solar, lit windows and string lights; future: white
## shells and a canopy sail.
static func raft(env: Node) -> void:
	var rng: RandomNumberGenerator = env.get("_rng")
	var always: Node3D = _g(env, "always")
	var a := builder(env, "always")
	var ruin := builder(env, "ruin")
	var grn := builder(env, "green")
	var fut := builder(env, "future")
	var bs := Basis(Vector3.UP, 0.3)
	var o := Vector3.ZERO
	var y: float = 0.75
	var mods: Array = [[Vector3(0, 0, 0), 20.0, 14.0], [Vector3(15.5, 0, -5.0), 9.0, 10.0], [Vector3(-14.0, 0, 3.0), 7.0, 9.0]]
	for md: Array in mods:
		platform(env, a, o, bs, md[0], md[1], md[2], y)
		if env.get("_decks") is Array:
			var wc: Vector3 = o + bs * (md[0] as Vector3)
			(env.get("_decks") as Array).append(Vector3(wc.x, wc.z, maxf(md[1], md[2]) * 0.62 + 1.0))
	# Gangways between the modules (with hand rails).
	for g: Array in [[Vector3(10.0, 0, -3.0), Vector3(11.0, 0, -3.0)], [Vector3(-10.0, 0, 3.0), Vector3(-10.5, 0, 3.0)]]:
		var gc: Vector3 = ((g[0] as Vector3) + (g[1] as Vector3)) * 0.5
		box(a, o, bs, gc + Vector3(0, y - 0.05, 0), Vector3(2.4, 0.16, 2.2), m(env, "timber2"))
		for sd: float in [-1.0, 1.0]:
			rail(a, o, bs, [gc + Vector3(-1.2, y, sd * 1.05), gc + Vector3(1.2, y, sd * 1.05)] as Array[Vector3], 0.95, m(env, "ledger"), 0.035)
	# Slipway off the small module into the sea (Lumi and bots can get up here).
	var sp := Vector3(-14.0, 0, 9.5)
	box(a, o, bs, sp + Vector3(0, (y + TidewellEnv.SEA_Y - 0.3) * 0.5, 1.6), Vector3(3.2, 0.2, 4.2), m(env, "steel"), Vector3(-12, 0, 0))
	for k: int in 8:
		box(a, o, bs, sp + Vector3(0, y - 0.05 - k * 0.11, 0.0 + k * 0.48), Vector3(3.0, 0.06, 0.08), m(env, "hazard"), Vector3(-12, 0, 0), 0.01)
	solid_box(always, o, bs, sp + Vector3(0, (y + TidewellEnv.SEA_Y - 0.3) * 0.5 - 0.2, 1.6), Vector3(3.2, 0.4, 4.4), Vector3(-12, 0, 0), PhysLayers.WORLD)
	# Shacks: workshop and store on the main module, a hut on the crane module.
	shack(env, a, grn, fut, o + bs * Vector3(-4.5, y, -2.5), 0.3, Vector3(6.4, 3.0, 4.6), "cream", "teal")
	shack(env, a, grn, fut, o + bs * Vector3(4.6, y, -3.2), 0.3 - 0.06, Vector3(4.2, 2.7, 3.6), "teal", "cream")
	shack(env, a, grn, fut, o + bs * Vector3(-14.0, y, 0.6), 0.3 + PI * 0.5, Vector3(3.4, 2.5, 3.0), "orange", "cream")
	# Crane + fuel tank on the east module.
	var cc := Vector3(17.0, y, -8.0)
	pipe(a, o, bs, cc, cc + Vector3(0, 3.5, 0), 0.6, m(env, "ledger"), 16)
	box(a, o, bs, cc + Vector3(0, 4.2, 0), Vector3(1.6, 1.4, 2.0), m(env, "orange"), Vector3(0, -20, 0))
	truss(a, o, bs, cc + Vector3(-0.3, 4.0, 0.6), cc + Vector3(-6.5, 9.0, 4.0), 0.9, 0.8, m(env, "ledger"), 0.09, 0.5)
	pipe(a, o, bs, cc + Vector3(-6.5, 9.0, 4.0), cc + Vector3(-6.5, 2.6, 4.0), 0.015, m(env, "dark"), 4)
	box(a, o, bs, cc + Vector3(-6.5, 2.3, 4.0), Vector3(0.45, 0.6, 0.35), m(env, "ledger"))
	solid_cyl(always, o, bs, cc, cc + Vector3(0, 5.0, 0), 0.9)
	var tc := Vector3(15.0, y + 1.3, -2.0)
	pipe(a, o, bs, tc + Vector3(-3.0, 0, 0), tc + Vector3(3.0, 0, 0), 1.15, m(env, "red"), 20)
	pipe(a, o, bs, tc + Vector3(-1.0, 0, 0), tc + Vector3(-0.6, 0, 0), 1.18, m(env, "hazard"), 20)
	for x: float in [-1.8, 1.8]:
		box(a, o, bs, tc + Vector3(x, -0.85, 0), Vector3(0.4, 0.9, 2.0), m(env, "steel"))
	ladder(a, o, bs, tc + Vector3(2.0, -1.3, 1.2), tc + Vector3(2.0, 1.1, 1.2), 0.5, Vector3(0, 0, 1), m(env, "steel"))
	pipe(a, o, bs, tc + Vector3(0, 1.1, 0), tc + Vector3(0, 1.5, 0), 0.25, m(env, "steel"), 10)
	solid_box(always, o, bs, tc, Vector3(6.4, 2.6, 2.6))
	# Rails round the main module's open sides, lamp posts (lit when restored).
	rail(a, o, bs, [Vector3(-9.6, y, 6.6), Vector3(9.6, y, 6.6)] as Array[Vector3], 1.0, m(env, "ledger"))
	rail(a, o, bs, [Vector3(-9.6, y, -6.6), Vector3(3.0, y, -6.6)] as Array[Vector3], 1.0, m(env, "ledger"))
	for lp: Vector3 in [Vector3(-9.0, y, 6.0), Vector3(0.0, y, 6.0), Vector3(9.0, y, 6.0), Vector3(12.0, y, -9.0)]:
		pipe(a, o, bs, lp, lp + Vector3(0, 3.2, 0), 0.07, m(env, "steel"), 8)
		lamp(a, grn, o, bs, lp + Vector3(0, 3.1, 0), Vector3(0, 0, -1), m(env, "steel"), m(env, "lamp_warm"))
	# Workbench corner and clutter: crates, drums, rope coils, nets, tyre fenders.
	box(a, o, bs, Vector3(1.0, y + 0.45, 3.0), Vector3(2.4, 0.12, 1.0), m(env, "timber2"))
	for x: float in [-0.1, 2.1]:
		box(a, o, bs, Vector3(x, y + 0.22, 3.0), Vector3(0.12, 0.44, 0.9), m(env, "steel"))
	var cols: Array[String] = ["teal", "orange", "red", "ledger", "cream"]
	for k: int in 9:
		var cp := Vector3(rng.randf_range(-8.5, 8.5), 0, rng.randf_range(1.5, 5.5))
		var s: float = rng.randf_range(0.6, 1.0)
		box(a, o, bs, cp + Vector3(0, y + s * 0.35, 0), Vector3(s, s * 0.7, s * 1.3), m(env, cols[k % 5]), Vector3(0, rng.randf() * 90.0, 0))
	var pts: Array[Transform3D] = []
	for k: int in 10:
		var dp := Vector3(rng.randf_range(12.5, 18.5), y, rng.randf_range(-9.0, -1.0)) if k < 5 else Vector3(rng.randf_range(-8.0, 8.0), y, rng.randf_range(1.0, 5.5))
		pts.append(Transform3D(bs * Basis(Vector3.UP, rng.randf() * TAU), o + bs * dp))
	env.call("_scatter_models", ["Barrel_01", "barrel_03", "wooden_crate_02", "metal_toolbox", "propane_tank"], pts, always, 200.0)
	var coil := TorusMesh.new()
	coil.inner_radius = 0.25
	coil.outer_radius = 0.55
	for rp: Vector3 in [Vector3(-8.0, y, -5.0), Vector3(8.5, y, 5.5), Vector3(-15.5, y, 6.5)]:
		for j: int in 3:
			add_mesh(a, m(env, "rope"), coil, Transform3D(bs, o + bs * (rp + Vector3(0, 0.1 + j * 0.12, 0))))
	var tyre := TorusMesh.new()
	tyre.inner_radius = 0.25
	tyre.outer_radius = 0.5
	for k: int in 8:
		var md: Array = mods[k % 3]
		var tp: Vector3 = (md[0] as Vector3) + Vector3(rng.randf_range(-0.4, 0.4) * float(md[1]), y - 0.5, (float(md[2]) * 0.5 + 0.15) * (1.0 if k % 2 == 0 else -1.0))
		add_mesh(a, m(env, "dark_rubber"), tyre, Transform3D(bs * Basis(Vector3.RIGHT, PI * 0.5), o + bs * tp))
	# Moorings to two buoys.
	var bpts: Array[Transform3D] = []
	for k: int in 2:
		var ang: float = 2.4 + k * 2.2
		var bp := Vector3(cos(ang) * 30.0, TidewellEnv.SEA_Y - 0.3, sin(ang) * 30.0)
		bpts.append(Transform3D(Basis(Vector3.UP, ang), bp))
		pipe(a, Vector3.ZERO, Basis(), Vector3(cos(ang) * 13.0, y + 0.2, sin(ang) * 10.0), bp + Vector3(0, 0.8, 0), 0.03, m(env, "rope_line"), 5)
	env.call("_scatter_models", ["ocean_buoy"], bpts, always, 300.0)
	# Ruin: junk heaps on the decks, a collapsed net pile, scattered sheet metal.
	var heap: Array[Transform3D] = []
	for k: int in 46:
		var hp := Vector3(rng.randf_range(-9.0, 9.0), y, rng.randf_range(-6.0, 6.0))
		if Vector2(hp.x + 4.5, hp.z + 2.5).length() < 4.2 or Vector2(hp.x - 4.6, hp.z + 3.2).length() < 3.0:
			continue
		heap.append(Transform3D(bs * Basis(Vector3.UP, rng.randf() * TAU).rotated(Vector3.RIGHT, rng.randf_range(-0.4, 0.4)), o + bs * hp))
	env.call("_scatter_models", ["Barrel_01", "old_tyre", "trashbag", "wooden_crate_02", "plastic_jerrycan", "metal_trash_can", "cardboard_box_01", "lifebuoy"], heap, _g(env, "ruin"), 200.0)
	for k: int in 7:
		box(ruin, o, bs, Vector3(rng.randf_range(-9, 9), y + 0.1, rng.randf_range(-6, 6)), Vector3(rng.randf_range(1.0, 2.2), 0.06, rng.randf_range(0.6, 1.2)), m(env, ["red", "steel", "teal"][k % 3]), Vector3(rng.randf_range(-8, 8), rng.randf() * 360.0, rng.randf_range(-8, 8)), 0.02)
	# Restored: planter boxes with greens, solar on the store roof, bunting.
	for k: int in 5:
		var pp := Vector3(-8.0 + k * 4.0, y, 5.6)
		box(grn, o, bs, pp + Vector3(0, 0.3, 0), Vector3(1.6, 0.6, 0.8), m(env, "timber2"))
		box(grn, o, bs, pp + Vector3(0, 0.58, 0), Vector3(1.45, 0.06, 0.66), m(env, "soil"))
		for j: int in 3:
			var s: float = rng.randf_range(0.3, 0.5)
			add_mesh(grn, m(env, "leaf"), env.call("_lumpy", 5 + j, 0.55, 3.0), Transform3D(bs * Basis.from_scale(Vector3(s * 1.2, s, s)), o + bs * (pp + Vector3(-0.5 + j * 0.5, 0.75, 0))))
	var bulb := SphereMesh.new()
	bulb.radius = 0.08
	bulb.height = 0.16
	bulb.radial_segments = 8
	bulb.rings = 4
	for seg: Array in [[Vector3(-9.0, y + 3.3, 6.0), Vector3(0.0, y + 3.3, 6.0)], [Vector3(0.0, y + 3.3, 6.0), Vector3(9.0, y + 3.3, 6.0)], [Vector3(9.0, y + 3.3, 6.0), Vector3(12.0, y + 3.3, -9.0)]]:
		for k: int in 10:
			var t: float = (float(k) + 0.5) / 10.0
			add_mesh(grn, m(env, "lamp_warm"), bulb, Transform3D(bs, o + bs * ((seg[0] as Vector3).lerp(seg[1], t) - Vector3(0, sin(t * PI) * 0.6, 0))))
	# Future: a white canopy sail on slim masts over the main deck.
	for k: int in 3:
		var ang: float = TAU * k / 3.0
		pipe(fut, o, bs, Vector3(cos(ang) * 8.0, y, sin(ang) * 5.5), Vector3(cos(ang) * 8.0, y + 6.5, sin(ang) * 5.5), 0.12, m(env, "white"), 10)
	add_mesh(fut, m(env, "white"), env.call("_blob_slab", 12, 0.12, 1.0, 3), Transform3D(bs * Basis.from_euler(Vector3(4, 30, 0) * (PI / 180.0)) * Basis.from_scale(Vector3(10.0, 0.08, 7.5)), o + bs * Vector3(0, y + 6.6, 0)))
	flush(env, a, "always")
	flush(env, ruin, "ruin")
	flush(env, grn, "green")
	flush(env, fut, "future")


# === Seas building helpers (on top of KitMesh / KitProps; the kit has no hulls, trusses or
# lattice towers, and these place parts in a site frame: origin o + basis bs) ===

## Chunky default bevel for a box of `size` (sites read from far away: a bit more than the kit's).
static func _bev(size: Vector3, b: float) -> float:
	if b >= 0.0:
		return minf(b, minf(size.x, minf(size.y, size.z)) * 0.45)
	return clampf(minf(size.x, minf(size.y, size.z)) * 0.16, 0.008, 0.2)


## Transform placing a +Y unit-axis mesh from a to c.
static func axis_xf(a: Vector3, c: Vector3) -> Transform3D:
	var d: Vector3 = c - a
	var y: Vector3 = d.normalized() if d.length() > 1e-5 else Vector3.UP
	var x: Vector3 = y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
	var z: Vector3 = x.cross(y).normalized()
	return Transform3D(Basis(x, y, z), (a + c) * 0.5)


# --- Framed placement (into a KitMesh.Builder) -------------------------------------------------

## A bevelled box at local `pos` in frame (o, bs) with extra rotation `rot` (degrees, local).
static func box(bt: KitMesh.Builder, o: Vector3, bs: Basis, pos: Vector3, size: Vector3, mat: String, rot: Vector3 = Vector3.ZERO, bev: float = -1.0) -> void:
	var lb: Basis = bs * Basis.from_euler(rot * (PI / 180.0))
	bt.add(mat, KitMesh.bevel_box(size.max(Vector3.ONE * 0.01), _bev(size, bev)), Transform3D(lb, o + bs * pos))


## A bevelled cylinder (pipe, post, tank) between local points a and c, radius r.
static func pipe(bt: KitMesh.Builder, o: Vector3, bs: Basis, a: Vector3, c: Vector3, r: float, mat: String, segs: int = 12) -> void:
	var wa: Vector3 = o + bs * a
	var wc: Vector3 = o + bs * c
	var ln: float = wa.distance_to(wc)
	if ln < 0.001:
		return
	if r < 0.05:
		bt.rod(mat, wa, wc, r, mini(segs, 6))
	else:
		bt.add(mat, KitMesh.bevel_cylinder(r, ln, clampf(minf(r, ln) * 0.2, 0.01, 0.16), segs), KitMesh.look_y(wa, wc - wa))


## A pipe with flanges at both ends (KitProps.pipe_run).
static func flanged_pipe(bt: KitMesh.Builder, o: Vector3, bs: Basis, a: Vector3, c: Vector3, r: float, mat: String, _flange_mat: String = "", _every: float = 4.0) -> void:
	KitProps.pipe_run(bt, Transform3D(bs, o), PackedVector3Array([a, c]), r, mat, true)


## A KitMesh.panel_wall centred at local pos (bottom edge at pos.y), facing `out`, w x h.
static func side_wall(bt: KitMesh.Builder, o: Vector3, bs: Basis, pos: Vector3, out: Vector3, w: float, h: float, key: String, opts: Dictionary = {}) -> void:
	var t: Transform3D = _facing(o, bs, pos, out, 0.0)
	var op: Dictionary = opts.duplicate()
	op["key"] = key
	KitMesh.panel_wall(bt, w, h, t * Transform3D(Basis(), Vector3(-w * 0.5, 0, 0)), op)


## A shipping container from kit panel walls (corrugated panels, corner posts, bolts) round a dark
## core, with a lid; rot in degrees (local). missing > 0 drops panels (wrecked).
static func container(bt: KitMesh.Builder, o: Vector3, bs: Basis, pos: Vector3, size: Vector3, key: String, rot: Vector3 = Vector3.ZERO, missing: float = 0.0) -> void:
	var t := Transform3D(bs * Basis.from_euler(rot * (PI / 180.0)), o + bs * pos)
	var h: Vector3 = size * 0.5
	bt.box("dark_steel", size * Vector3(0.96, 0.96, 0.96), t)
	var op: Dictionary = {"key": key, "panel": Vector2(0.55, size.y - 0.2), "depth": 0.1, "missing": missing}
	var faces: Array = [[0.0, Vector3(-h.x, -h.y, h.z), size.x], [PI, Vector3(h.x, -h.y, -h.z), size.x], [PI * 0.5, Vector3(h.x, -h.y, h.z), size.z], [-PI * 0.5, Vector3(-h.x, -h.y, -h.z), size.z]]
	for f: Array in faces:
		KitMesh.panel_wall(bt, float(f[2]), size.y, t * Transform3D(Basis(Vector3.UP, float(f[0])), f[1]), op)
	bt.box(key, Vector3(size.x + 0.06, 0.1, size.z + 0.06), t * Transform3D(Basis(), Vector3(0, h.y + 0.02, 0)))


## A row of n bolt heads from a to c on a face pointing `nrm` (local).
static func bolts(bt: KitMesh.Builder, o: Vector3, bs: Basis, a: Vector3, c: Vector3, n: int, nrm: Vector3, mat: String, r: float = 0.05) -> void:
	for k: int in n:
		var p: Vector3 = a.lerp(c, (float(k) + 0.5) / n)
		pipe(bt, o, bs, p, p + nrm * r * 0.8, r, mat, 6)


## A railing along local points (KitProps.railing per segment; broken state bends posts).
static func rail(bt: KitMesh.Builder, o: Vector3, bs: Basis, pts: Array[Vector3], hgt: float, mat: String, _r: float = 0.04) -> void:
	for i: int in pts.size() - 1:
		KitProps.railing(bt, Transform3D(bs, o), pts[i], pts[i + 1], hgt, mat, bt.state)


## A ladder from a (bottom) to c (top) on a face pointing `out` (KitProps.ladder).
static func ladder(bt: KitMesh.Builder, o: Vector3, bs: Basis, a: Vector3, c: Vector3, _w: float, out: Vector3, mat: String) -> void:
	KitProps.ladder(bt, _facing(o, bs, a + Vector3(0, 0, 0), out, -0.15), maxf(0.6, c.y - a.y), mat)


## A louvred vent box on a face pointing `out`, centred at pos (KitProps.vent).
static func vent(bt: KitMesh.Builder, o: Vector3, bs: Basis, pos: Vector3, w: float, hgt: float, out: Vector3, frame: String, _dark: String = "") -> void:
	KitProps.vent(bt, _facing(o, bs, pos - Vector3(0, hgt * 0.5, 0), out, 0.0), Vector2(w, hgt), frame)


## Frame at local pos whose +Z points along `out` (local, horizontal), pushed `push` m along it.
static func _facing(o: Vector3, bs: Basis, pos: Vector3, out: Vector3, push: float) -> Transform3D:
	var z: Vector3 = (bs * out)
	z.y = 0.0
	z = z.normalized() if z.length() > 0.001 else Vector3.BACK
	var x: Vector3 = Vector3.UP.cross(z).normalized()
	return Transform3D(Basis(x, Vector3.UP, z), o + bs * pos + z * push)


## Raised plating ribs on a flat face: n vertical strips across a span (a to c), height hgt.
static func ribs(bt: KitMesh.Builder, o: Vector3, bs: Basis, a: Vector3, c: Vector3, n: int, hgt: float, out: Vector3, mat: String) -> void:
	var yaw: float = rad_to_deg(atan2(out.x, out.z))
	for k: int in n:
		var p: Vector3 = a.lerp(c, (float(k) + 0.5) / n) + out * 0.04
		box(bt, o, bs, p, Vector3(0.16, hgt, 0.1), mat, Vector3(0, yaw, 0), 0.03)


## A caged work lamp on a short arm; `lit` adds the lens (warm or cool emissive material).
static func lamp(bt: KitMesh.Builder, lit_bt: KitMesh.Builder, o: Vector3, bs: Basis, pos: Vector3, out: Vector3, body: String, lens: String) -> void:
	pipe(bt, o, bs, pos, pos + out * 0.35, 0.04, body, 6)
	var hp: Vector3 = pos + out * 0.42 + Vector3(0, -0.05, 0)
	pipe(bt, o, bs, hp - Vector3(0, 0.11, 0), hp + Vector3(0, 0.11, 0), 0.14, body, 10)
	if lit_bt:
		pipe(lit_bt, o, bs, hp - Vector3(0, 0.16, 0), hp - Vector3(0, 0.1, 0), 0.11, lens, 10)
		lit_bt.lights.append({"pos": o + bs * (hp - Vector3(0, 0.4, 0)), "color": KitMat.GLOW["warm"] if lens != "trim:cool" else KitMat.GLOW["cool"], "range": 7.0, "energy": 1.4})


# --- Colliders ------------------------------------------------------------------------------------

## A static box collider (frame o, bs; local centre pos, rot degrees) on `layer` (default PROP).
static func solid_box(parent: Node3D, o: Vector3, bs: Basis, pos: Vector3, size: Vector3, rot: Vector3 = Vector3.ZERO, layer: int = PhysLayers.PROP) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	body.transform = Transform3D(bs * Basis.from_euler(rot * (PI / 180.0)), o + bs * pos)
	parent.add_child(body)
	return body


## A static cylinder collider between local points a and c.
static func solid_cyl(parent: Node3D, o: Vector3, bs: Basis, a: Vector3, c: Vector3, r: float, layer: int = PhysLayers.PROP) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = (o + bs * a).distance_to(o + bs * c)
	cs.shape = sh
	body.add_child(cs)
	body.transform = axis_xf(o + bs * a, o + bs * c)
	parent.add_child(body)
	return body


# --- Decals and custom meshes ---------------------------------------------------------------------

## A kit atlas decal (docs/ART_KIT.md: logo, num_01..06, warn, chevrons, arrow, ...) at local pos
## on a face whose outward normal is `out` (local), w x h metres.
static func decal(bt: KitMesh.Builder, o: Vector3, bs: Basis, pos: Vector3, out: Vector3, w: float, hgt: float, name: String) -> void:
	var n: Vector3 = (bs * out).normalized()
	var up: Vector3 = Vector3.UP if absf(n.dot(Vector3.UP)) < 0.95 else bs * Vector3.FORWARD
	var x: Vector3 = up.cross(n).normalized()
	var y: Vector3 = n.cross(x).normalized()
	bt.decal(name, Vector2(w, hgt), Transform3D(Basis(x, y, n), o + bs * pos + n * 0.02))


## The helipad marking (ring and H), an image decal on its own quad (not in the kit atlas).
static func helipad(parent: Node3D, pos: Vector3, size: float, col: Color = Color(0.96, 0.78, 0.2)) -> MeshInstance3D:
	var key: String = "helipad_%s" % col.to_html()
	if not _cache.has(key):
		var img := Image.create(128, 128, true, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		for y: int in 128:
			for x: int in 128:
				var d: float = Vector2(x - 63.5, y - 63.5).length()
				var hh: bool = (absf(x - 44.0) < 6.0 or absf(x - 84.0) < 6.0 or absf(y - 64.0) < 5.0) and absf(x - 64.0) < 26.0 and absf(y - 64.0) < 28.0
				if (d > 52.0 and d < 60.0) or hh:
					img.set_pixel(x, y, col)
		img.generate_mipmaps()
		var m := StandardMaterial3D.new()
		m.albedo_texture = ImageTexture.create_from_image(img)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.roughness = 0.7
		_cache[key] = m
	var q := PlaneMesh.new()
	q.size = Vector2(size, size)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = _cache[key]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos + Vector3(0, 0.03, 0)
	parent.add_child(mi)
	return mi


## Any Mesh (first surface) as kit primitive arrays [v, n, c, uv, idx]: COLOR.r edge (from the
## mesh's own colour if it has one), g = 1 (no extra AO), so it can go into a KitMesh.Builder.
## mask: -1 all triangles, 0 / 1 only triangles whose COLOR.g is below / above 0.5 (hull boot-top).
static func prim_of(mesh: Mesh, mask: int = -1) -> Array:
	var key: String = "prim_%d_%d" % [mesh.get_instance_id(), mask]
	if _cache.has(key):
		return _cache[key]
	var a: Array = mesh.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var c: PackedColorArray = a[Mesh.ARRAY_COLOR] if a[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV] if a[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var src_idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if src_idx.is_empty():
		src_idx.resize(v.size())
		for i: int in v.size():
			src_idx[i] = i
	var cols := PackedColorArray()
	cols.resize(v.size())
	for i: int in v.size():
		cols[i] = Color(c[i].r if c.size() > i else 0.0, 1.0, 0.0)
	if uv.size() != v.size():
		uv.resize(v.size())
	var idx := PackedInt32Array()
	for t: int in range(0, src_idx.size(), 3):
		if mask >= 0 and c.size() > 0:
			var g: float = (c[src_idx[t]].g + c[src_idx[t + 1]].g + c[src_idx[t + 2]].g) / 3.0
			if (g > 0.5) != (mask == 1):
				continue
		idx.append_array([src_idx[t], src_idx[t + 1], src_idx[t + 2]])
	var out: Array = [v, n, cols, uv, idx]
	_cache[key] = out
	return out


## A kit primitive as a plain ArrayMesh (for custom-material batches such as Rime's glassy ice).
static func kit_mesh(prim: Array) -> ArrayMesh:
	var b := KitMesh.Builder.new(1)
	b.add("x", prim)
	return b.commit()


## Adds a Mesh (rock, coil, bulb, hull) to a builder under a kit key.
static func add_mesh(bt: KitMesh.Builder, key: String, mesh: Mesh, xf: Transform3D, mask: int = -1) -> void:
	bt.add(key, prim_of(mesh, mask), xf)


## A lofted ship hull along +Z (bow at +Z), keel at y = 0, deck at `depth` (+ sheer toward the
## bow): flared sides, a round bilge, a raked bow and a flat transom. Below `boot` metres the
## hull carries COLOR.g = 1 (seas_paint paint2: antifouling red); the gunwale is a worn edge.
## Hard edges at the deck line and transom; smooth along the sides.
static func hull_mesh(length: float, beam: float, depth: float, boot: float = -1.0, bow: float = -1.0, sheer: float = -1.0) -> ArrayMesh:
	if boot < 0.0:
		boot = depth * 0.4
	if bow < 0.0:
		bow = length * 0.22
	if sheer < 0.0:
		sheer = depth * 0.25
	var key: String = "hull_%.2f_%.2f_%.2f_%.2f_%.2f_%.2f" % [length, beam, depth, boot, bow, sheer]
	if _cache.has(key):
		return _cache[key]
	var w: float = beam * 0.5
	var br: float = minf(w * 0.4, depth * 0.45)  # bilge radius
	var nsec: int = 28
	var sections: Array = []  # each: Array of [Vector3, edge, boot] starboard half from deck edge to keel
	for i: int in nsec + 1:
		var t: float = float(i) / nsec
		var z: float = -length * 0.5 + t * length
		var zb: float = z - (length * 0.5 - bow)  # >0 inside the bow run
		var ws: float = 1.0
		var keel: float = 0.0
		if zb > 0.0:
			var u: float = clampf(zb / bow, 0.0, 1.0)
			ws = sqrt(maxf(0.0, 1.0 - u * u)) * 0.96 + 0.04
			keel = depth * 0.55 * u * u
		var stern_u: float = clampf((-length * 0.5 + length * 0.08 - z) / (length * 0.08), 0.0, 1.0)
		ws *= 1.0 - stern_u * 0.06
		keel = maxf(keel, depth * 0.25 * stern_u)
		var top: float = depth + sheer * pow(t, 2.2)
		var ww: float = w * ws
		var rr: float = minf(br, ww * 0.9)
		var pts: Array = []
		pts.append([Vector3(ww * 1.03, top, z), 1.0, 0.0])
		pts.append([Vector3(ww, maxf(boot, keel + rr), z), 0.0, 0.0])
		pts.append([Vector3(ww, maxf(boot, keel + rr), z), 0.0, 1.0])
		for k: int in range(0, 5):
			var a: float = PI * 0.5 * float(k) / 4.0
			var p := Vector3(ww - rr + cos(a) * rr, keel + rr - sin(a) * rr, z)
			if k == 0:
				p.y = minf(p.y, maxf(boot, keel + rr) - 0.001)
			pts.append([p, 0.0, 1.0])
		pts.append([Vector3(0.0, keel, z), 0.0, 1.0])
		sections.append(pts)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quad := func(a: Array, b2: Array, c: Array, d: Array, grp: int) -> void:
		st.set_smooth_group(grp)
		for v: Array in [a, c, b2, a, d, c]:
			st.set_color(Color(float(v[1]), float(v[2]), 0))
			st.set_uv(Vector2((v[0] as Vector3).z, (v[0] as Vector3).y))
			st.add_vertex(v[0])
	for side: float in [1.0, -1.0]:
		for i: int in nsec:
			var s0: Array = sections[i]
			var s1: Array = sections[i + 1]
			for k: int in s0.size() - 1:
				if k == 1:
					continue  # zero-width seam between boot-top colours
				var m := func(v: Array) -> Array: return [Vector3((v[0] as Vector3).x * side, (v[0] as Vector3).y, (v[0] as Vector3).z), v[1], v[2]]
				var a: Array = m.call(s0[k])
				var b2: Array = m.call(s0[k + 1])
				var c: Array = m.call(s1[k + 1])
				var d: Array = m.call(s1[k])
				if side > 0.0:
					quad.call(a, b2, c, d, 0)
				else:
					quad.call(a, d, c, b2, 0)
	# Deck (flat, hard edge) and transom.
	for i: int in nsec:
		var s0: Array = sections[i]
		var s1: Array = sections[i + 1]
		var a0: Vector3 = s0[0][0]
		var a1: Vector3 = s1[0][0]
		var dk := func(v: Vector3, sd: float) -> Array: return [Vector3(v.x * sd, v.y - 0.02, v.z), 0.0, 0.0]
		quad.call(dk.call(a0, -1.0), dk.call(a1, -1.0), dk.call(a1, 1.0), dk.call(a0, 1.0), 1)
	var s0: Array = sections[0]
	for k: int in s0.size() - 1:
		if k == 1:
			continue
		var p0: Vector3 = s0[k][0]
		var p1: Vector3 = s0[k + 1][0]
		var col_g: float = float(s0[k + 1][2])
		quad.call([Vector3(-p0.x, p0.y, p0.z), 0.0, col_g], [Vector3(-p1.x, p1.y, p1.z), 0.0, col_g], [p1, 0.0, col_g], [p0, 0.0, col_g], 2)
	st.generate_normals()
	st.generate_tangents()
	var mesh: ArrayMesh = st.commit()
	_cache[key] = mesh
	return mesh


## A triangular lattice truss from a to c (width w, depth hgt), chords r, n bays of braces.
static func truss(bt: KitMesh.Builder, o: Vector3, bs: Basis, a: Vector3, c: Vector3, w: float, hgt: float, mat: String, r: float = 0.1, taper: float = 1.0) -> void:
	var ax: Vector3 = (c - a).normalized()
	var ref: Vector3 = Vector3.UP if absf(ax.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var side: Vector3 = ax.cross(ref).normalized() * w * 0.5
	var up: Vector3 = side.cross(ax).normalized() * hgt
	var chords: Array[Vector3] = [side, -side, up]
	for ch: Vector3 in chords:
		pipe(bt, o, bs, a + ch, c + ch * taper, r, mat, 8)
	var n: int = maxi(2, int(a.distance_to(c) / maxf(w, 1.2)))
	for k: int in n:
		var t0: float = float(k) / n
		var t1: float = float(k + 1) / n
		var p0: Vector3 = a.lerp(c, t0)
		var p1: Vector3 = a.lerp(c, t1)
		var s0: float = lerpf(1.0, taper, t0)
		var s1: float = lerpf(1.0, taper, t1)
		pipe(bt, o, bs, p0 + side * s0, p1 - side * s1, r * 0.5, mat, 6)
		pipe(bt, o, bs, p0 + side * s0, p1 + up * s1, r * 0.5, mat, 6)
		pipe(bt, o, bs, p0 - side * s0, p1 + up * s1, r * 0.5, mat, 6)
		pipe(bt, o, bs, p1 + side * s1, p1 - side * s1, r * 0.45, mat, 6)


## A vertical lattice tower (sides 3 or 4) from base y0 to top y1 at local xz, radius r0 -> r1,
## horizontal rings and X bracing every `step` metres.
static func tower(bt: KitMesh.Builder, o: Vector3, bs: Basis, c: Vector3, y0: float, y1: float, r0: float, r1: float, sides: int, mat: String, chord: float = 0.16, step: float = 2.4, rot: float = 0.0) -> void:
	var corner := func(k: int, y: float) -> Vector3:
		var t: float = (y - y0) / maxf(0.01, y1 - y0)
		var rr: float = lerpf(r0, r1, t)
		var ang: float = TAU * float(k) / sides + rot
		return c + Vector3(cos(ang) * rr, y, sin(ang) * rr)
	for k: int in sides:
		pipe(bt, o, bs, corner.call(k, y0), corner.call(k, y1), chord, mat, 8)
	var y: float = y0
	while y < y1 - 0.1:
		var yn: float = minf(y + step, y1)
		for k: int in sides:
			var k1: int = (k + 1) % sides
			pipe(bt, o, bs, corner.call(k, yn), corner.call(k1, yn), chord * 0.5, mat, 6)
			pipe(bt, o, bs, corner.call(k, y), corner.call(k1, yn), chord * 0.4, mat, 6)
		y = yn
