class_name OrbitCrews
extends Node
## [orbB] The robots' side of a globe (phase A's VerdanceGlobe crew code as its own node; orbC
## ports the real Fleet onto it). Near robots are SphereBots on the hex graph (this node is their
## `graph`: claim_dirty, path, work_cell, junk_left, release); far crews are data only, each
## clearing whole cells nearest its hub at `rate` cells per minute (the shape of Offline.compute).
## [orbC] The real crew is SphereCrew (robots/sphere/), plugged in at the bottom of this file.

var globe: OrbitPlanet
var bots: Array[SphereBot] = []
var crews: Array[Dictionary] = []
var _claimed: Dictionary = {}
signal cell_worked(cell: int, left: float)


func setup(p_globe: OrbitPlanet) -> void:
	globe = p_globe


## Stand-in near crew around a hub (phase A's four bots). Robots proper come with Fleet (orbC).
func spawn_demo_bots(hub: int, n: int, parent: Node) -> void:
	var grid: SphereGrid = globe.grid
	var around: PackedInt32Array = grid.cells_around(hub, 1)
	for i: int in n:
		var b := SphereBot.new()
		b.name = "Bot%d" % i
		parent.add_child(b)
		b.setup(globe.surface, grid.centers[around[(i + 1) % around.size()]])
		b.add_visual(["scoopie", "haulbug", "scoopie", "scoopie"][i % 4])
		b.graph = self
		b.hub_cell = hub
		b.cell = around[(i + 1) % around.size()]
		b.swarm = globe.swarm
		globe.swarm.add(b)
		bots.append(b)


func add_far_crew(hub: int, rate: float) -> void:
	crews.append({"hub": hub, "rate": rate, "acc": 0.0})


func claim_dirty(from: int, hub: int, rings: int) -> int:
	var grid: SphereGrid = globe.grid
	var cells: SphereCells = globe.cells
	var lim: float = (rings + 0.5) * 17.3
	var seen: Dictionary = {from: true}
	var front := PackedInt32Array([from])
	while not front.is_empty():
		var nxt := PackedInt32Array()
		for c: int in front:
			if cells.is_dirty(c) and not _claimed.has(c):
				_claimed[c] = true
				return c
			for j: int in grid.neighbors(c):
				if not seen.has(j) and grid.distance_m(j, hub) < lim:
					seen[j] = true
					nxt.append(j)
		front = nxt
	return -1


func path(from: int, to: int) -> PackedInt32Array:
	if to < 0:
		return PackedInt32Array()
	var grid: SphereGrid = globe.grid
	var prev: Dictionary = {from: -1}
	var front := PackedInt32Array([from])
	var lim: float = grid.distance_m(from, to) + 100.0
	while not front.is_empty() and not prev.has(to):
		var nxt := PackedInt32Array()
		for c: int in front:
			for j: int in grid.neighbors(c):
				if not prev.has(j) and grid.distance_m(j, to) < lim:
					prev[j] = c
					nxt.append(j)
		front = nxt
	var out := PackedInt32Array()
	var cur: int = to
	while cur != -1 and prev.has(cur):
		out.insert(0, cur)
		cur = prev[cur]
	return out


func work_cell(c: int, left: float) -> void:
	var field: SphereField = globe.field
	if field.materialized[c] == 1:
		for pid: int in field.reduce_to(c, left):
			globe.junk_view.hide_piece(pid)
		globe.write_cell(c)
		globe.junk_view.refresh_hex(c)
		if left <= 0.0 and field.hex_clean[c] == 0:
			field.hex_clean[c] = 1
			field.cleaned_count += 1
	else:
		globe.cells.set_junk(c, left)
		field.settle(c)
	if left <= 0.0 and globe.cells.state[c] == 0:
		globe.cells.set_state(c, 1)
	cell_worked.emit(c, left)


func junk_left(c: int) -> float:
	var field: SphereField = globe.field
	return (1.0 - field.removed_fraction(c)) if field and field.materialized[c] == 1 else globe.cells.junk[c]


func release(c: int) -> void:
	_claimed.erase(c)


## Advance far crews by dt seconds (also used to pre-simulate: --orbit-presim=MIN).
func tick(list: Array[Dictionary], dt: float) -> void:
	for cr: Dictionary in list:
		cr["acc"] = float(cr["acc"]) + float(cr["rate"]) * dt / 60.0
		while float(cr["acc"]) >= 1.0:
			cr["acc"] = float(cr["acc"]) - 1.0
			var c: int = claim_dirty(int(cr["hub"]), int(cr["hub"]), 16)
			if c < 0:
				break
			globe.cells.set_junk(c, 0.0)
			globe.cells.set_state(c, 1)
			if globe.field.materialized[c] == 1:
				work_cell(c, 0.0)
			else:
				globe.field.settle(c)
			release(c)


func _process(delta: float) -> void:
	if globe:
		tick(crews, delta)


func cleaned_by_bots() -> int:
	var n: int = 0
	for b: SphereBot in bots:
		n += b.cleaned
	return n


# --- [orbC] The phase C crew (robots/sphere/): near SphereBots, far records, jobs by cell id ---
## SphereCrew does the work; this node plugs it into the slice (scenes/slice_orbit.gd calls
## build_crew, save_crew, restore_crew and on_view): saving in GameState.orbit["robots"]
## (directions, never x/z) and the offline jump on load, per hub region by cell id with the flat
## game's maths (SphereOffline over Offline.compute). The stand-in bots and far crews above stay
## for --orbit-bots only.

var crew: SphereCrew

const AWAY_MIN_S: float = 120.0  # the flat slice's threshold for an offline payout


## Builds the crew into the slice (`so` = SliceOrbit, after Patch and the camera exist).
func build_crew(so: Node) -> SphereCrew:
	var g: Object = so.get("globe")
	var patch: Node3D = (so.get("w") as Node).get("patch")
	crew = SphereCrewDev.install(g, so.get("w"), patch, so.get("cam"), Callable(g, "write_cell"))
	crew.cell_cleaned.connect(func(_c: int) -> void:
		var f: SphereField = g.get("field")
		EventBus.field_progress_changed.emit(f.cleaned_count, f.junk_hex_count))
	return crew


func save_crew() -> Dictionary:
	return crew.to_dict() if crew != null else {}


## Restores the crew from GameState.orbit and, when the game was reopened from disk after a while
## away, runs the offline jump for its robots (grouped by hub) and pays it.
func restore_crew(so: Node, od: Dictionary, from_disk: bool) -> Dictionary:
	if crew == null:
		return {}
	var rd: Dictionary = od.get("robots", {})
	if not rd.is_empty():
		crew.from_dict(rd)
	if not from_disk:
		return {}
	var away: float = Time.get_unix_time_from_system() - GameState.saved_unix
	if GameState.saved_unix <= 0.0 or away <= AWAY_MIN_S or crew.robots().is_empty():
		return {}
	var res: Dictionary = offline(away)
	Offline.apply(res)
	EventBus.toast.emit(Offline.summary_text(res), "info")
	return res


## The offline jump for every hub that has robots. Pieces it removes are hidden in the junk view.
func offline(seconds: float) -> Dictionary:
	var g: OrbitPlanet = globe
	var by_hub: Dictionary = {}
	for u: Dictionary in crew.robots():
		var h: int = int(u["hub"])
		if not by_hub.has(h):
			by_hub[h] = []
		(by_hub[h] as Array).append({"type": u["type"], "tier": u["tier"]})
	var hubs: Array = []
	for h: int in by_hub:
		hubs.append({"cell": h, "robots": by_hub[h]})
	var res: Dictionary = SphereOffline.simulate(g.get("grid"), g.get("cells"), g.get("field"), hubs, seconds, crew.planet_id)
	var jv: Object = g.get("junk_view")
	if jv != null:
		for pid: int in res["pieces"]:
			jv.call("hide_piece", pid)
		if jv.has_method("refresh_hex"):
			for h: Dictionary in res["hubs"]:
				for c: int in SphereOffline.region(g.grid, g.cells, int(h["hub"]), crew.rings):
					if g.field.materialized[c] == 1:
						jv.call("refresh_hex", c)
	return res


## Command view on: free the mouse to paint zones and pick hexes; off: capture it again.
func on_view(so: Node) -> void:
	var cam: SphereCam = so.get("cam")
	var w: Node = so.get("w")
	if cam == null or w.get("bot") or DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if cam.view == "command" else Input.MOUSE_MODE_CAPTURED
