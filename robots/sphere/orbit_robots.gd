class_name OrbitRobots
extends RefCounted
## [orbC] The robots' side of the slice on the globe (scenes/slice_orbit.gd calls these): the
## SphereCrew (near SphereBots, far records, jobs by cell id), the Command-view picker, saving the
## crew in GameState.orbit["robots"] (directions, never x/z) and the offline jump on load, per hub
## region by cell id with the flat game's maths (SphereOffline over Offline.compute).

const AWAY_MIN_S: float = 120.0  # the flat slice's threshold for an offline payout


## Builds the crew into the slice (`so` = SliceOrbit, after Patch and the camera exist).
static func build(so: Node) -> SphereCrew:
	var g: Object = so.get("globe")
	var patch: Node3D = (so.get("w") as Node).get("patch")
	var crew: SphereCrew = SphereCrewDev.install(g, so.get("w"), patch, so.get("cam"), Callable(g, "write_cell"))
	crew.cell_cleaned.connect(func(_c: int) -> void:
		var f: SphereField = g.get("field")
		EventBus.field_progress_changed.emit(f.cleaned_count, f.junk_hex_count))
	return crew


static func save(crew: SphereCrew) -> Dictionary:
	return crew.to_dict() if crew != null else {}


## Restores the crew from GameState.orbit and, when the game was reopened from disk after a while
## away, runs the offline jump for its robots (grouped by hub) and pays it.
static func restore(so: Node, crew: SphereCrew, od: Dictionary, from_disk: bool) -> Dictionary:
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
	var res: Dictionary = offline(so.get("globe"), crew, away)
	Offline.apply(res)
	EventBus.toast.emit(Offline.summary_text(res), "info")
	return res


## The offline jump for every hub that has robots. Pieces it removes are hidden in the junk view.
static func offline(g: Object, crew: SphereCrew, seconds: float) -> Dictionary:
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
	return res


## Command view on: free the mouse to paint zones and pick hexes; off: capture it again.
static func on_view(so: Node) -> void:
	var cam: SphereCam = so.get("cam")
	var w: Node = so.get("w")
	if cam == null or w.get("bot") or DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if cam.view == "command" else Input.MOUSE_MODE_CAPTURED
