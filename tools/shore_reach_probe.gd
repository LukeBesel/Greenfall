extends Node
## Shore-reach probe (bug B6): which places can Lumi walk to from the start without Hover Jets?
## Run: godot --headless --path . res://tools/shore_reach_probe.tscn -- --fresh [--probe-m=300]
## Lumi stops at the shore of every water cell until Hover Jets (Patch.shore_clamp), so the land he
## can reach is the start cell's connected group of non-water cells. Prints that group's size, the
## land cells within --probe-m metres that are cut off from it (islands and far shores), and whether
## each place the early game sends him to (bench, bin and scale, the seed tin, the greenhouse) is in
## it. Exit code 1 when a required place is cut off.

const SETTLE_FRAMES: int = 120
## The walk stops counting here: enough to show the start is on open land, not on an island.
const GROUP_CAP: int = 20000

var _slice: Node


func _ready() -> void:
	_slice = (load("res://scenes/slice.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_slice)
	_run.call_deferred()


func _ready_world() -> bool:
	return is_instance_valid(_slice) and _slice.is_inside_tree() and _slice.get("orbit") != null and (_slice.get("orbit") as SliceOrbit).globe != null \
		and (_slice.get("orbit") as SliceOrbit).globe.field != null and _slice.get("patch") != null and _slice.get("first_seed") != null


func _run() -> void:
	while not _ready_world():
		await get_tree().process_frame
	for i: int in SETTLE_FRAMES:
		await get_tree().process_frame
	var g: OrbitPlanet = (_slice.get("orbit") as SliceOrbit).globe
	var f: SphereField = g.field
	var c0: int = g.start_cell()
	var radius: float = DevHooks.get_f("probe-m", 300.0)
	var group: Dictionary = _land_group(g, f, c0)
	var land: int = 0
	var water: int = 0
	var cut: int = 0
	var cut_near: Array[String] = []
	for c: int in g.grid.cells_within(g.grid.centers[c0], radius, c0):
		if f.is_water(c):
			water += 1
			continue
		land += 1
		if not group.has(c):
			cut += 1
			if cut_near.size() < 12:
				cut_near.append("%d@%.0fm" % [c, g.grid.distance_m(c, c0)])
	print("[b6] start cell %d: land group of %s%d cells; within %.0f m: %d land, %d water, %d land cells cut off by water %s" % [c0,
		">=" if group.size() >= GROUP_CAP else "", group.size(), radius, land, water, cut, str(cut_near)])
	var all_water: int = 0
	for c: int in f.hex_count():
		if f.is_water(c):
			all_water += 1
	print("[b6] planet: %d of %d cells are water (%.0f%%); around the start: %.0f%%" % [all_water, f.hex_count(), 100.0 * all_water / f.hex_count(), 100.0 * water / maxi(1, land + water)])
	var places: Dictionary = {"bench": _slice.call("bench_pos"), "lumi_spawn": (_slice.get("patch") as Patch).global_position,
		"seed_tin": (_slice.get("first_seed") as FirstSeed).tin_point(), "greenhouse": (_slice.get("first_seed") as FirstSeed).greenhouse_point()}
	var depot: Variant = _slice.get("depot")
	if depot is Node3D:
		places["scale"] = (depot as Node3D).global_position
		places["bin"] = Objectives.bin_point(_slice)
	var bad: int = 0
	for k: String in places:
		var pos: Variant = places[k]
		if not pos is Vector3:
			print("[b6] %s: no position" % k)
			continue
		var c: int = f.hex_at(pos)
		var ok: bool = group.has(c)
		if not ok:
			bad += 1
		print("[b6] %s %s: cell %d, %.0f m from the start cell, %s" % ["OK" if ok else "CUT_OFF", k, c, g.grid.distance_m(c, c0), "water" if f.is_water(c) else "land"])
	print("[b6] %s (%d required places cut off)" % ["PASS" if bad == 0 else "FAIL", bad])
	get_tree().quit(1 if bad > 0 else 0)


## The non-water cells joined to `from` by land, breadth first, up to GROUP_CAP.
func _land_group(g: OrbitPlanet, f: SphereField, from: int) -> Dictionary:
	var seen: Dictionary = {from: true}
	var queue: Array[int] = [from]
	var head: int = 0
	while head < queue.size() and seen.size() < GROUP_CAP:
		var c: int = queue[head]
		head += 1
		for n: int in g.grid.neighbors(c):
			if not seen.has(n) and not f.is_water(n):
				seen[n] = true
				queue.append(n)
	return seen
