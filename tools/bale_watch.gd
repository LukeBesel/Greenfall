class_name BaleWatch
extends Node
## [v10pace] Bales in the start yard (play-tester, 15 Nov: about a hundred bales heaped six metres
## high by the bench and the bin, some hanging in the air, Lumi standing inside them). Every
## EVERY_S game seconds it counts the bales (JunkCube) on the pad: how many, whose (a crew's parked
## bale or a loose one), how many are off the ground, the highest, how many lie where Lumi presses E
## (YardKeepOut.E_ANCHORS), and the crew's bale records there. Lines: "[bales] ..."; a breach of the
## rules prints "[bales] WARN ...": more than CAP on the pad, one in the air, one on an E spot.
## Dev: --bale-watch (also on with --soak). The last line is "[bales] PASS" or "[bales] FAIL (N warnings)".
## BaleWatch.count(so) / breaches(r) are what tools/walk_home.gd's bale part checks.

const EVERY_S: float = 30.0
const PAD_M: float = 13.0
## The most bales that may lie on the pad at once.
const CAP: int = 12
const AIR_M: float = 1.3
const E_SPOT_M: float = 1.6

static var warns: int = 0

var so: SliceOrbit
var _t: float = 0.0
var _next: float = EVERY_S


static func attach(p_so: SliceOrbit) -> BaleWatch:
	var b := BaleWatch.new()
	b.name = "BaleWatch"
	b.so = p_so
	p_so.w.add_child(b)
	p_so.w.tree_exiting.connect(func() -> void: print("[bales] %s (%d warnings)" % ["PASS" if warns == 0 else "FAIL", warns]))
	return b


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	_t += delta
	if _t < _next:
		return
	_next = _t + EVERY_S
	var r: Dictionary = BaleWatch.count(so)
	if r.is_empty():
		return
	var bad: Array[String] = BaleWatch.breaches(r)
	var pressed: int = int(float(GameState.stats.get("robot_bales", 0.0)))
	print("[bales] %.1f min  pad %d (crew %d, loose %d)  in air %d  top %.1f m  on E spots %d  records %d  robots pressed %d, still lying %d, sold or carried %d%s" % [
		float(GameState.stats.get("time_played", 0.0)) / 60.0, int(r["pad"]), int(r["crew"]), int(r["loose"]), int(r["air"]), float(r["top"]),
		int(r["e_spots"]), int(r["records"]), pressed, int(r["all_records"]), maxi(pressed - int(r["all_records"]), 0), ("  near: " + str(r["where"])) if int(r["pad"]) > 0 else ""])
	if not bad.is_empty():
		warns += 1
		print("[bales] WARN %s" % "; ".join(bad))


static func breaches(r: Dictionary) -> Array[String]:
	var bad: Array[String] = []
	if int(r["pad"]) > CAP:
		bad.append("%d bales on the pad (cap %d)" % [int(r["pad"]), CAP])
	if int(r["air"]) > 0:
		bad.append("%d bales in the air (top %.1f m)" % [int(r["air"]), float(r["top"])])
	if int(r["e_spots"]) > 0:
		bad.append("%d bales on an E spot" % int(r["e_spots"]))
	return bad


## What lies on the start yard's pad now ({} off the start site or before the world stands).
static func count(p_so: SliceOrbit) -> Dictionary:
	if p_so == null or p_so.globe == null or p_so.globe.site_manager == null or p_so.globe.site_manager.prefab(0) == null:
		return {}
	var sp: SitePrefab = p_so.globe.site_manager.prefab(0)
	if not sp.is_built or not sp.is_inside_tree():
		return {}
	var centre: Vector3 = sp.global_position
	var inv: Transform3D = sp.global_transform.affine_inverse()
	var out: Dictionary = {"pad": 0, "crew": 0, "loose": 0, "air": 0, "top": 0.0, "e_spots": 0, "records": 0, "all_records": 0, "where": {}}
	var spots: Array[Vector3] = []
	for nm: String in YardKeepOut.E_ANCHORS + (["bench"] as Array[String]):
		if sp.anchor_names().has(nm):
			spots.append(sp.anchor_local(nm).origin)
	var bales_node: Variant = p_so.crews.crew.bale_view if p_so.crews != null and p_so.crews.crew != null else null
	for n: Node in p_so.w.get_tree().get_nodes_in_group("junk_cube"):
		var c: JunkCube = n as JunkCube
		if c == null or c.carried or c.claimed or c.is_queued_for_deletion() or c.global_position.distance_to(centre) > PAD_M:
			continue
		out["pad"] = int(out["pad"]) + 1
		var mine: bool = bales_node is Node and c.get_parent() == bales_node
		out["crew" if mine else "loose"] = int(out["crew" if mine else "loose"]) + 1
		var h: float = c.global_position.length() - p_so.globe.terrain.ground(c.global_position.normalized()).length()
		out["top"] = maxf(float(out["top"]), h)
		if h > AIR_M and c.linear_velocity.length() < 0.3:
			out["air"] = int(out["air"]) + 1
		var l: Vector3 = inv * c.global_position
		var best: String = ""
		var bd: float = INF
		for nm: String in YardKeepOut.E_ANCHORS + (["bench"] as Array[String]):
			if not sp.anchor_names().has(nm):
				continue
			var d: float = Vector2(l.x, l.z).distance_to(Vector2(sp.anchor_local(nm).origin.x, sp.anchor_local(nm).origin.z))
			if d < bd:
				bd = d
				best = nm
		(out["where"] as Dictionary)[best] = int((out["where"] as Dictionary).get(best, 0)) + 1
		if bd < E_SPOT_M and c.linear_velocity.length() < 0.3:
			out["e_spots"] = int(out["e_spots"]) + 1
	var crew: Variant = p_so.crews.crew if p_so.crews != null else null
	if crew is SphereCrew:
		out["all_records"] = (crew as SphereCrew).bales.size()
		for b: Dictionary in (crew as SphereCrew).bales:
			var d: Vector3 = b.get("dir", Vector3.ZERO)
			if d != Vector3.ZERO and d.angle_to(centre.normalized()) * centre.length() < PAD_M:
				out["records"] = int(out["records"]) + 1
	return out
