extends Node
## Hex-stick probe (bug B3): can a hex near the start stay below the clean rule with nothing left to
## pick up? Run: godot --headless --path . res://tools/hex_stick_probe.tscn -- --fresh [--probe-m=160] [--probe-verbose]
## Loads the default game, materializes every cell within --probe-m metres of the start cell and
## reports, per dirty land cell: cells with junk on the ledger but no pieces; pieces whose volume does
## not add up to the ledger; and the share of volume in pieces Lumi cannot stand next to (every spot
## within scoop reach is inside a solid collider or on a water cell). A cell is STUCK when what can
## never be scooped is more than the part the clean rule sweeps away. Exit code 1 when any is.

## Lumi's base scoop reach (data/patch.json): a piece needs a free standing spot this close.
const RING_M: Array[float] = [0.8, 1.6, 2.2]
const RING_STEPS: int = 12
const BODY_R: float = 0.3
const BODY_UP: float = 0.9
const SETTLE_FRAMES: int = 180

var _slice: Node


func _ready() -> void:
	_slice = (load("res://scenes/slice.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_slice)
	_run.call_deferred()


func _ready_world() -> bool:
	return is_instance_valid(_slice) and _slice.is_inside_tree() and _slice.get("orbit") != null and (_slice.get("orbit") as SliceOrbit).globe != null \
		and (_slice.get("orbit") as SliceOrbit).globe.field != null and _slice.get("patch") != null


func _run() -> void:
	while not _ready_world():
		await get_tree().process_frame
	for i: int in SETTLE_FRAMES:
		await get_tree().physics_frame
	var g: OrbitPlanet = (_slice.get("orbit") as SliceOrbit).globe
	var f: SphereField = g.field
	var c0: int = g.start_cell()
	var radius: float = DevHooks.get_f("probe-m", 160.0)
	var space: PhysicsDirectSpaceState3D = (_slice as Node3D).get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = BODY_R
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.collision_mask = PhysLayers.WORLD | PhysLayers.PROP
	var stats: Dictionary = {"cells": 0, "dirty_land": 0, "water": 0, "no_pieces": 0, "ledger_off": 0, "stuck": 0, "pieces": 0, "blocked_pieces": 0, "worst_blocked_share": 0.0}
	var allowed: float = 1.0 - f.clean_threshold
	for c: int in g.grid.cells_within(g.grid.centers[c0], radius, c0):
		stats["cells"] += 1
		f.materialize(c)
		if f.is_water(c):
			stats["water"] += 1
			stats["nearest_water_m"] = minf(float(stats.get("nearest_water_m", INF)), g.grid.distance_m(c, c0))
			continue
		if f.hex_hub[c] == 1 or f.is_clean(c) or f.locked.has(c):
			continue
		stats["dirty_land"] += 1
		var alive_vol: float = 0.0
		var blocked_vol: float = 0.0
		var n_alive: int = 0
		for pid: int in f.pieces_in(c):
			if f.piece_alive[pid] == 0:
				continue
			n_alive += 1
			alive_vol += f.piece_vol[pid]
			if not _reachable(f, space, q, f.piece_pos[pid]):
				blocked_vol += f.piece_vol[pid]
				stats["blocked_pieces"] += 1
				if DevHooks.has("probe-verbose"):
					print("[b3]   blocked piece %d (%s, vol %.1f) in cell %d at %s: inside_solid=%s nearest_free_spot=%.2f m; %s" % [pid, f.piece_model[pid], f.piece_vol[pid], c,
							str(f.piece_pos[pid].snappedf(0.1)), str(_inside_solid(space, f.piece_pos[pid])), _nearest_free_m(f, space, q, f.piece_pos[pid]), _what_blocks(f, space, q, f.piece_pos[pid])])
		stats["pieces"] += n_alive
		var total: float = f.hex_total[c]
		var share: float = blocked_vol / total
		stats["worst_blocked_share"] = maxf(float(stats["worst_blocked_share"]), share)
		var dist: float = g.grid.distance_m(c, c0)
		if n_alive == 0:
			stats["no_pieces"] += 1
			print("[b3] STUCK cell %d at %.0f m: ledger left %.1f of %.1f but no pieces" % [c, dist, f.hex_left[c], total])
		if absf(alive_vol - f.hex_left[c]) > allowed * total:
			stats["ledger_off"] += 1
			print("[b3] LEDGER cell %d at %.0f m: pieces hold %.1f, ledger says %.1f left of %.1f" % [c, dist, alive_vol, f.hex_left[c], total])
		var never: float = blocked_vol + maxf(0.0, f.hex_left[c] - alive_vol)
		if never > allowed * total + 0.001:
			stats["stuck"] += 1
			print("[b3] STUCK cell %d at %.0f m: %.1f%% of its junk can never be scooped (rule sweeps %.0f%%); blocked pieces %.1f%%" % [c, dist, never / total * 100.0, allowed * 100.0, share * 100.0])
	print("[b3] %s within %.0f m of the start: %s" % ["FAIL" if int(stats["stuck"]) > 0 else "PASS", radius, JSON.stringify(stats)])
	get_tree().quit(1 if int(stats["stuck"]) > 0 else 0)


## Whether Lumi has a free spot (no solid collider, not a water cell) within scoop reach of `pos`.
func _reachable(f: SphereField, space: PhysicsDirectSpaceState3D, q: PhysicsShapeQueryParameters3D, pos: Vector3) -> bool:
	var u: Vector3 = pos.normalized()
	var b: Basis = SphereGrid.frame(u)
	for r: float in RING_M:
		for k: int in RING_STEPS:
			var a: float = TAU * float(k) / float(RING_STEPS)
			var d: Vector3 = (pos + (b.x * cos(a) + b.z * sin(a)) * r).normalized()
			if f.is_water(f.hex_at(d)):
				continue
			q.transform = Transform3D(Basis.IDENTITY, f.terrain.ground(d) + d * BODY_UP)
			if space.intersect_shape(q, 1).is_empty():
				return true
	return false


## What stands on the free-spot ring of a blocked piece: collider names, or "water".
func _what_blocks(f: SphereField, space: PhysicsDirectSpaceState3D, q: PhysicsShapeQueryParameters3D, pos: Vector3) -> String:
	var seen: Dictionary = {}
	var b: Basis = SphereGrid.frame(pos.normalized())
	for k: int in RING_STEPS:
		var a: float = TAU * float(k) / float(RING_STEPS)
		var d: Vector3 = (pos + (b.x * cos(a) + b.z * sin(a)) * RING_M[1]).normalized()
		if f.is_water(f.hex_at(d)):
			seen["water"] = true
			continue
		q.transform = Transform3D(Basis.IDENTITY, f.terrain.ground(d) + d * BODY_UP)
		for hit: Dictionary in space.intersect_shape(q, 2):
			var n: Node = hit["collider"] as Node
			seen[str(n.get_path()).right(70) if n else "?"] = true
	return ", ".join(seen.keys())


## Whether the piece's own spot is inside a solid collider (junk laid under a building or a prop).
func _inside_solid(space: PhysicsDirectSpaceState3D, pos: Vector3) -> bool:
	var pq := PhysicsPointQueryParameters3D.new()
	pq.position = pos + pos.normalized() * 0.3
	pq.collision_mask = PhysLayers.WORLD | PhysLayers.PROP
	return not space.intersect_point(pq, 1).is_empty()


## Ground distance (m) from `pos` to the nearest spot Lumi's body fits, searched out to 12 m (-1: none).
func _nearest_free_m(f: SphereField, space: PhysicsDirectSpaceState3D, q: PhysicsShapeQueryParameters3D, pos: Vector3) -> float:
	var b: Basis = SphereGrid.frame(pos.normalized())
	for step: int in range(1, 49):
		var r: float = 0.25 * float(step)
		for k: int in 24:
			var a: float = TAU * float(k) / 24.0
			var d: Vector3 = (pos + (b.x * cos(a) + b.z * sin(a)) * r).normalized()
			if f.is_water(f.hex_at(d)):
				continue
			q.transform = Transform3D(Basis.IDENTITY, f.terrain.ground(d) + d * BODY_UP)
			if space.intersect_shape(q, 1).is_empty():
				return r
	return -1.0
