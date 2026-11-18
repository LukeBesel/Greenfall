class_name OrbitBeaconCheck
extends RefCounted
## [v2guide] Owner 2026-11-08 playtest 2 #33: the purple beacon stood on an empty road cell while the
## step said "Empty your chest into the trash bin". On the globe, every step's beacon target must be
## the real position of its object: the bin, the bench, the tower spot, the greenhouse.
## Run from OrbitRoundtrip.run (save_roundtrip.tscn -- --fresh --orbit).

## Ground distance (m) a target may sit from its object and still count as "on it".
const TOL_M: float = 0.6


static func _near(a: Variant, b: Variant) -> bool:
	return a is Vector3 and b is Vector3 and (a as Vector3).distance_to(b as Vector3) < TOL_M


static func _fmt(v: Variant) -> String:
	return "(%.1f, %.1f, %.1f)" % [(v as Vector3).x, (v as Vector3).y, (v as Vector3).z] if v is Vector3 else str(v)


static func run(s: Node, so: SliceOrbit, check: Callable) -> void:
	var ob: Objectives = s.get("objectives") as Objectives
	var tut: Tutorial = s.get("tutorial") as Tutorial
	var depot: Node3D = s.get("depot") as Node3D
	var p: Patch = s.get("patch") as Patch
	if ob == null or depot == null or p == null:
		check.call("beacon_systems", true, false)
		return
	var bin_pos: Vector3 = Objectives.bin_point(s)
	var bench_obj: Vector3 = so.bench_position()
	var bits: Variant = s.get("_ruin_bits")
	var bench_model: Node3D = (bits as Dictionary).get("bench") as Node3D if bits is Dictionary else null
	if bench_model:
		bench_obj = bench_model.global_position
	print("[beacon] depot %s  bin %s  bin anchor %s  bench %s" % [_fmt(depot.global_position), _fmt(bin_pos), _fmt(so.yard_point("bin")), _fmt(bench_obj)])
	# The bin: the depot's chute (the bin body Lumi empties into), on the start site.
	var fill1: float = p.compartment.fill
	p.compartment.fill = p.capacity()  # a full chest: "Fill the trash bin" points at the bin
	check.call("beacon_bin_on_bin_body", true, _near(ob.step_target({"id": "dump3"}).get("pos"), bin_pos))
	check.call("beacon_dump_goal_on_bin", true, _near(ob.step_target({"_goal": 0, "type": "stat", "key": "junk_dumps"}).get("pos"), bin_pos))
	p.compartment.fill = fill1
	check.call("beacon_bin_near_depot", true, bin_pos.distance_to(depot.global_position) < 4.0)
	check.call("beacon_bench_on_bench", true, _near(ob._resolve({"to": "bench"}).get("pos"), bench_obj))
	# The restart checklist's dump step points at the same bin.
	if tut:
		var saved: int = tut.step
		tut.step = 2  # "dump"
		var t: Dictionary = {}
		var fill0: float = p.compartment.fill
		p.compartment.fill = maxf(fill0, 1.0)
		t = tut.target()
		print("[beacon] tutorial dump target %s" % _fmt(t.get("pos", null)))
		check.call("beacon_tutorial_dump_on_bin", true, _near(t.get("pos", null), bin_pos))
		check.call("beacon_follows_the_card_step", true, _near(ob.waypoint_target(), bin_pos))
		p.compartment.fill = 0.0
		check.call("beacon_none_on_pieces", "<null>", str(ob.waypoint_target()))  # #37: empty chest -> junk, no beam
		tut.step = 0
		check.call("beacon_tutorial_repair_on_bench", true, _near(tut.target().get("pos", null), bench_obj))
		tut.step = saved
		p.compartment.fill = fill0
	# #37: cleaning a hex needs no beam (the outline shows it).
	check.call("beacon_none_on_hex_steps", "<null>", str(ob.step_target({"id": "hex"}).get("pos", null)))
	# Every story step's target sits on the globe's surface near the yard (no flat-world leftovers).
	var r: float = so.globe.grid.radius_m
	var bad: Array = []
	for i: int in ob.chain.size():
		var def: Dictionary = ob.chain[i]
		var tp: Variant = ob.step_target(def).get("pos", null)
		if not (tp is Vector3):
			continue
		var h: float = absf((tp as Vector3).length() - r) if r > 0.0 else 0.0
		if h > 8.0 or OrbitUp.ground_dist(tp as Vector3, bench_obj) > 150.0:
			bad.append("%s %s" % [def.get("id", i), _fmt(tp)])
	check.call("beacon_every_step_on_globe", "[]", str(bad))
