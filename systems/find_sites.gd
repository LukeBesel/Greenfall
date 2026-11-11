class_name FindSites
extends Node3D
## The world's side of the finds (systems/finds.gd; design spec section 13): the things that
## hold pieces of Lumi's looks stand in the world, and Lumi takes them with her own hands.
##
##   Wrecks   an old robot of the planet's design, half buried on its hex off the main path,
##            under a heap of junk. Lumi pulls the heap off piece by piece (use, a short dig each),
##            then salvages the wreck (use, a longer dig): its pieces are given and the found
##            moment plays (ui/piece_reveal.gd). Until then a young plant grows up out of it
##            (the table's `sapling`), the tell that shows it from across a hex. The wreck stays,
##            stripped, and flowers come up round it. Robots cannot do any of this: clearing the hex gives nothing.
##   Teases   a wreck of a design this planet does not hand out. Using it only says its line
##            ("Too far gone. Maybe somewhere else."). It can never be salvaged.
##   Caches   a buried paint tin or lens chip whose hex has come up lies in that hex's cleared
##            soil. The detector pings it (player/detector.gd, cache_fn); Lumi digs it up by
##            using the spot.
##
## Models are built only while Lumi is near (show_within_m) and freed when she is far
## (hide_beyond_m). Every spot is reachable open ground (planet/sites/target_reach.gd); it is
## looked at again when the buildings round it change, while Lumi is not there to see it move.
## Which wrecks exist, their design and all numbers are the planet's `finds` table (`sites`).
##
## Nothing here decides what is found: Finds does. This node shows it and tells Finds when Lumi
## has used a spot. Use: var s := FindSites.new(); world.add_child(s);
## s.setup(finds, districts, field, interactables, player_fn)

signal junk_cleared(find_id: String, left: int)
signal wreck_salvaged(find_id: String)
signal tease_read(tease_id: String)
signal cache_dug(find_id: String)

const CHECK_S: float = 0.5
const GLINT_NEAR_M: float = 90.0
const GLINT_PULSE_RATE: float = 2.4
## Lumi must be at least this far for a spot to be moved to better ground.
const MOVE_UNSEEN_M: float = 30.0
const TOSS_S: float = 0.45
const LIFT_S: float = 0.5
const LIFT_HOLD_S: float = 1.6
## Offsets (m, in the hex's own ground frame) so a wreck and a buried find do not sit dead
## centre on a hex, where the hex's ring and beacon stand.
const WRECK_OFFSET := Vector2(1.6, -1.2)
const CACHE_OFFSET := Vector2(-1.3, 0.9)
const DEFAULTS: Dictionary = {
	"junk": 3, "clear_s": 0.7, "salvage_s": 1.4, "reach_m": 2.6, "dig_reach_m": 1.7, "dig_s": 1.3,
	"show_within_m": 150.0, "hide_beyond_m": 210.0, "glint_s": [5.0, 9.0], "tease_again_s": 3.0,
}

var _finds: Finds
var _districts: Districts
var _field: SphereField
var _interactables: Interactables
var _player_fn: Callable
var _cfg: Dictionary = {}
## Wreck or tease id -> {node, model, junk: Array[Node3D], tease: bool, busy: bool, glint_t, cool}.
var _wrecks: Dictionary[String, Dictionary] = {}
## Buried find id -> {node, kind, tint, busy}.
var _caches: Dictionary[String, Dictionary] = {}
var _check_t: float = 0.0
var _t: float = 0.0
var _keep_out_seen: int = -1
var _rng := RandomNumberGenerator.new()


## `player_fn` returns Lumi's Node3D (or null before she exists).
func setup(finds: Finds, districts: Districts, field: SphereField, interactables: Interactables, player_fn: Callable) -> void:
	_finds = finds
	_districts = districts
	_field = field
	_interactables = interactables
	_player_fn = player_fn
	_cfg = DEFAULTS.duplicate()
	_cfg.merge(Finds.site_cfg(Planets.current()), true)
	_rng.seed = hash("find_sites")
	finds.world_places()
	finds.surfaced.connect(_on_surfaced)
	finds.taken.connect(_on_taken)


func _exit_tree() -> void:
	if _finds and _finds.surfaced.is_connected(_on_surfaced):
		_finds.surfaced.disconnect(_on_surfaced)
	if _finds and _finds.taken.is_connected(_on_taken):
		_finds.taken.disconnect(_on_taken)


func _process(delta: float) -> void:
	_t += delta
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = CHECK_S
		refresh()
	_glint(delta)


# --- Queries ----------------------------------------------------------------------------------

func cfg(key: String) -> float:
	return float(_cfg.get(key, DEFAULTS.get(key, 0.0)))


## Every wreck this planet stands in the world: the wreck finds, then the teases.
func wreck_ids() -> Array[String]:
	var out: Array[String] = []
	if _finds == null:
		return out
	for e: Dictionary in _finds.entries():
		if e["where"] == Finds.WRECK:
			out.append(str(e["id"]))
	for e: Dictionary in _finds.teases():
		out.append(str(e["id"]))
	return out


func is_tease(id: String) -> bool:
	return _finds != null and not _finds.tease(id).is_empty()


## The design a wreck is: the planet's own set, or the tease's.
func design_of(id: String) -> String:
	var t: Dictionary = _finds.tease(id) if _finds else {}
	return str(t["design"]) if not t.is_empty() else Finds.set_for(Planets.current())


## The city a wreck (or tease) lies in.
func district_of(id: String) -> String:
	var e: Dictionary = _finds.tease(id) if is_tease(id) else _finds.entry(id)
	return str(e.get("district", ""))


## Junk pieces still on a wreck (0 for a tease and for a salvaged wreck).
func junk_left(id: String) -> int:
	if _finds == null or is_tease(id) or _finds.is_taken(id):
		return 0
	return maxi(0, int(cfg("junk")) - _finds.cleared(id))


## The model standing for a wreck now (null while Lumi is far).
func wreck_node(id: String) -> Node3D:
	var v: Variant = _wrecks.get(id, {}).get("node")
	return v as Node3D if is_instance_valid(v) else null


func wreck_model(id: String) -> WreckModel:
	var v: Variant = _wrecks.get(id, {}).get("model")
	return v as WreckModel if is_instance_valid(v) else null


func cache_node(id: String) -> Node3D:
	var v: Variant = _caches.get(id, {}).get("node")
	return v as Node3D if is_instance_valid(v) else null


## Where a wreck stands (or will stand): reachable open ground on its hex. Vector3.ZERO when it
## has no hex on this globe.
func spot(id: String) -> Vector3:
	var n: Node3D = wreck_node(id)
	if n:
		return n.global_position
	var cell: int = _finds.site_cell(id) if _finds else Finds.NO_CELL
	return _open_spot(cell, WRECK_OFFSET, null) if cell != Finds.NO_CELL else Vector3.ZERO


## Where a surfaced buried find lies.
func cache_spot(id: String) -> Vector3:
	var n: Node3D = cache_node(id)
	if n:
		return n.global_position
	var cell: int = _finds.surfaced_finds().get(id, Finds.NO_CELL) if _finds else Finds.NO_CELL
	return _open_spot(cell, CACHE_OFFSET, null) if cell != Finds.NO_CELL else Vector3.ZERO


## The detector's question (PartDetector.cache_fn): the nearest buried find lying within
## `range_m` of `pos`, as {id, pos, label, color}; {} when there is none.
func nearest_cache(pos: Vector3, range_m: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = range_m
	for id: String in _caches:
		var n: Node3D = cache_node(id)
		if n == null or bool(_caches[id].get("busy", false)):
			continue
		var d: float = OrbitUp.ground_dist(pos, n.global_position)
		if d < best_d:
			best_d = d
			best = {"id": id, "pos": n.global_position, "label": cache_label(str(_caches[id]["kind"])), "color": _caches[id]["tint"]}
	return best


## The detector's name for a buried find of a kind, translated.
func cache_label(kind: String) -> String:
	return tr("LENS CHIP") if kind == FindProps.CHIP else tr("BURIED TIN")


## A paint tin holds a colour for the body; a lens chip holds a light colour.
static func kind_of(piece: String) -> String:
	return FindProps.CHIP if CrewLooks.is_light(piece) else FindProps.TIN


## Something Lumi can do with her hands within `within_m` of `pos` (the unattended bot asks):
## {id, pos, reach} of the nearest cache to dig or wreck to clear or salvage; {} when none.
func nearest_job(pos: Vector3, within_m: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = within_m
	for id: String in _caches:
		var n: Node3D = cache_node(id)
		if n and OrbitUp.ground_dist(pos, n.global_position) < best_d:
			best_d = OrbitUp.ground_dist(pos, n.global_position)
			best = {"id": id, "pos": n.global_position, "reach": cfg("dig_reach_m")}
	for id: String in _wrecks:
		var n: Node3D = wreck_node(id)
		if n == null or is_tease(id) or _finds.is_taken(id):
			continue
		if OrbitUp.ground_dist(pos, n.global_position) < best_d:
			best_d = OrbitUp.ground_dist(pos, n.global_position)
			best = {"id": id, "pos": n.global_position, "reach": cfg("reach_m")}
	return best


# --- Building and freeing ---------------------------------------------------------------------

## Builds what Lumi is near and frees what she has left behind. Runs twice a second.
func refresh() -> void:
	if _finds == null or _field == null:
		return
	var lumi: Node3D = _lumi()
	if lumi == null:
		return
	var at: Vector3 = lumi.global_position
	for id: String in wreck_ids():
		var cell: int = _finds.site_cell(id)
		if cell == Finds.NO_CELL:
			continue
		var d: float = at.distance_to(_field.hex_center(cell))
		if wreck_node(id) == null and d < cfg("show_within_m"):
			show_wreck(id)
		elif wreck_node(id) != null and d > cfg("hide_beyond_m") and not bool(_wrecks[id].get("busy", false)):
			_drop_wreck(id)
	var lying: Dictionary[String, int] = _finds.surfaced_finds()
	for id: String in lying:
		var d: float = at.distance_to(_field.hex_center(lying[id]))
		if cache_node(id) == null and d < cfg("show_within_m"):
			show_cache(id)
		elif cache_node(id) != null and d > cfg("hide_beyond_m") and not bool(_caches[id].get("busy", false)):
			_drop_cache(id)
	_reseat(at)


## Stands a wreck's model on its hex now (refresh does this when Lumi comes near).
func show_wreck(id: String) -> Node3D:
	_drop_wreck(id)
	var cell: int = _finds.site_cell(id)
	if cell == Finds.NO_CELL:
		return null
	var tease: bool = is_tease(id)
	var node := Node3D.new()
	node.name = "Wreck_" + id
	add_child(node)
	var pos: Vector3 = _open_spot(cell, WRECK_OFFSET, null)
	_place(node, pos, Finds.roll(Planets.current().world_seed, id, 1) * TAU)
	var model := WreckModel.new()
	model.name = "Model"
	model.design = design_of(id)
	model.pose_seed = hash(id)
	model.ruined = tease
	if not tease and _finds.is_taken(id):
		model.stripped.assign(_finds.entry(id)["pieces"])
	node.add_child(model)
	var st: Dictionary = {"node": node, "model": model, "junk": [] as Array[Node3D], "tease": tease, "busy": false,
		"glint_t": _rng.randf_range(1.0, 4.0), "cool": 0.0}
	_wrecks[id] = st
	var body: StaticBody3D = PropColliders.body(node, "WreckBody")
	PropColliders.add_box(body, Transform3D(node.global_basis, node.global_position + node.global_basis.y * 0.3), Vector3(0.8, 0.6, 0.8))
	if not tease and _finds.is_taken(id):
		node.add_child(FindProps.flowers(hash(id), model.glow()))
	elif not tease:
		_grow_sapling(node, id)
		var heap: Array[Dictionary] = FindProps.junk(hash(id), int(cfg("junk")))
		for k: int in range(_finds.cleared(id), heap.size()):
			var piece: Node3D = heap[k]["node"]
			node.add_child(piece)
			(st["junk"] as Array[Node3D]).append(piece)
	if _interactables:
		_interactables.register(node, cfg("reach_m"), _wreck_prompt.bind(id), use_wreck.bind(id), _wreck_usable.bind(id))
	return node


## Stands a surfaced buried find in the soil of its hex now.
func show_cache(id: String) -> Node3D:
	_drop_cache(id)
	var cell: int = _finds.surfaced_finds().get(id, Finds.NO_CELL)
	var e: Dictionary = _finds.entry(id)
	if cell == Finds.NO_CELL or e.is_empty():
		return null
	var piece: String = str((e["pieces"] as Array)[0])
	var kind: String = kind_of(piece)
	var tint: Color = CrewLooks.tint_of(piece, FieldPlate.CYAN)
	var node: Node3D = FindProps.cache(kind, tint)
	add_child(node)
	_place(node, _open_spot(cell, CACHE_OFFSET, null), Finds.roll(Planets.current().world_seed, id, 2) * TAU)
	_caches[id] = {"node": node, "kind": kind, "tint": tint, "busy": false}
	if _interactables:
		_interactables.register(node, cfg("dig_reach_m"), _cache_prompt.bind(id), dig_cache.bind(id), _cache_usable.bind(id))
	return node


func _drop_wreck(id: String) -> void:
	var n: Node3D = wreck_node(id)
	if n:
		if _interactables:
			_interactables.unregister(n)
		n.queue_free()
	_wrecks.erase(id)


func _drop_cache(id: String) -> void:
	var n: Node3D = cache_node(id)
	if n:
		if _interactables:
			_interactables.unregister(n)
		n.queue_free()
	_caches.erase(id)


## Upright on the round ground, turned by `yaw`.
func _place(node: Node3D, pos: Vector3, yaw: float) -> void:
	var up: Vector3 = pos.normalized()
	node.global_transform = Transform3D(Basis(up, yaw) * SphereGrid.frame(up), pos)


## Reachable open ground for a thing on `cell`, `off` metres from the hex's middle in its own
## ground frame: never in a building, a lake, a collider or on a steep bank.
func _open_spot(cell: int, off: Vector2, ignore: Node) -> Vector3:
	var c: Vector3 = _field.hex_center(cell)
	var fr: Basis = SphereGrid.frame(c.normalized())
	var want: Vector3 = (c + fr.x * off.x + fr.z * off.y).normalized()
	var t: TargetReach = _reach(ignore)
	return t.open_spot(want) if t else _field.terrain.ground(want)


func _reach(ignore: Node) -> TargetReach:
	if _field == null or _field.terrain == null:
		return null
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state if is_inside_tree() else null
	return TargetReach.for_field(_field, space, ignore)


## Buildings are registered as towns and their outskirts are built: when that changes, a wreck or
## cache that now stands somewhere unreachable moves to open ground, unless Lumi is there.
func _reseat(lumi_at: Vector3) -> void:
	var t: TargetReach = _reach(null)
	var version: int = t.keep_out.version if t and t.keep_out else 0
	if t == null or version == _keep_out_seen:
		return
	_keep_out_seen = version
	for id: String in _wrecks.keys():
		var n: Node3D = wreck_node(id)
		if n == null or lumi_at.distance_to(n.global_position) < MOVE_UNSEEN_M:
			continue
		if _reach(n).reach(n.global_position) != "":
			show_wreck(id)
	for id: String in _caches.keys():
		var n: Node3D = cache_node(id)
		if n and lumi_at.distance_to(n.global_position) >= MOVE_UNSEEN_M and _reach(n).reach(n.global_position) != "":
			show_cache(id)


# --- Wrecks -----------------------------------------------------------------------------------

func _wreck_usable(id: String) -> bool:
	var st: Dictionary = _wrecks.get(id, {})
	if st.is_empty() or bool(st["busy"]):
		return false
	if bool(st["tease"]):
		return float(st["cool"]) <= 0.0
	return not _finds.is_taken(id)


func _wreck_prompt(id: String) -> String:
	if is_tease(id):
		return tr("E   Look at the wreck")
	return tr("E   Pull the junk off the wreck") if junk_left(id) > 0 else tr("E   Salvage the wreck")


## Lumi uses a wreck: a tease says its line; a wreck under junk loses one piece of it; a clear
## wreck is salvaged. False when nothing happened (busy, taken, not built).
func use_wreck(id: String) -> bool:
	if not _wreck_usable(id):
		return false
	var st: Dictionary = _wrecks[id]
	var node: Node3D = st["node"]
	if bool(st["tease"]):
		_read_tease(id)
		return true
	var clearing: bool = junk_left(id) > 0
	st["busy"] = true
	var done: Callable = _junk_pulled.bind(id) if clearing else _salvaged.bind(id)
	if not _dig(node.global_position, cfg("clear_s") if clearing else cfg("salvage_s"), done, Color(0.62, 0.5, 0.36)):
		st["busy"] = false
		return false
	return true


func _junk_pulled(id: String) -> void:
	var st: Dictionary = _wrecks.get(id, {})
	if st.is_empty():
		return
	st["busy"] = false
	var heap: Array[Node3D] = st["junk"]
	_finds.set_cleared(id, _finds.cleared(id) + 1)
	if not heap.is_empty():
		_toss(heap.pop_front(), st["node"] as Node3D)
	Audio.play("clunk", randf_range(0.9, 1.1), -7.0)
	junk_cleared.emit(id, junk_left(id))
	if junk_left(id) == 0:
		var model: WreckModel = st["model"]
		Vfx.burst("sparkle", model.eye_point(), model.glow(), 0.6)
		Audio.play("blip", 0.8, -10.0)


## A pulled piece is dragged clear of the wreck, tips over and sinks out of the way.
func _toss(piece: Node3D, wreck: Node3D) -> void:
	if not is_instance_valid(piece):
		return
	var out: Vector3 = piece.position
	out.y = 0.0
	out = out.normalized() if out.length() > 0.05 else Vector3(1, 0, 0)
	Vfx.burst("dust", wreck.to_global(piece.position) + wreck.global_basis.y * 0.3, Color(0.75, 0.68, 0.55))
	if Settings.reduced_motion or not piece.is_inside_tree():
		piece.queue_free()
		return
	var tw: Tween = piece.create_tween()
	tw.set_parallel(true)
	tw.tween_property(piece, "position", piece.position + out * 1.1 + Vector3(0, 0.25, 0), TOSS_S * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(piece, "rotation:x", piece.rotation.x + 0.9, TOSS_S)
	tw.chain().tween_property(piece, "position", piece.position + out * 1.5 + Vector3(0, -0.9, 0), TOSS_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(piece.queue_free)


func _salvaged(id: String) -> void:
	var st: Dictionary = _wrecks.get(id, {})
	if not st.is_empty():
		st["busy"] = false
	if _finds.take(id):  # the pieces are given: the found moment plays (ui/piece_reveal.gd)
		Audio.play("servo", 1.0, -8.0)
		wreck_salvaged.emit(id)


func _read_tease(id: String) -> void:
	var st: Dictionary = _wrecks[id]
	st["cool"] = cfg("tease_again_s")
	var model: WreckModel = st["model"]
	Vfx.burst("bits", model.eye_point(), model.glow(), 0.5)
	Audio.play("groan", 1.1, -12.0)
	EventBus.toast.emit(tr(str(_finds.tease(id).get("line", ""))), "hint")
	tease_read.emit(id)


# --- Caches -----------------------------------------------------------------------------------

func _cache_usable(id: String) -> bool:
	return _caches.has(id) and not bool(_caches[id]["busy"]) and not _finds.is_taken(id)


func _cache_prompt(id: String) -> String:
	return tr("E   Dig up the lens chip") if str(_caches.get(id, {}).get("kind", "")) == FindProps.CHIP else tr("E   Dig up the paint tin")


## Lumi digs a buried find out of the soil. False when nothing happened.
func dig_cache(id: String) -> bool:
	if not _cache_usable(id):
		return false
	var st: Dictionary = _caches[id]
	st["busy"] = true
	if not _dig((st["node"] as Node3D).global_position, cfg("dig_s"), _cache_out.bind(id), PartDetector.SOIL):
		st["busy"] = false
		return false
	return true


## The find comes out of the ground: it lifts and turns in its own light, and its piece is given.
func _cache_out(id: String) -> void:
	var st: Dictionary = _caches.get(id, {})
	var node: Node3D = cache_node(id)
	if node:
		if _interactables:
			_interactables.unregister(node)
		_caches.erase(id)
		var thing: Node3D = node.get_node_or_null("Thing") as Node3D
		Vfx.burst("sparkle", node.global_position + node.global_basis.y * 0.4, st["tint"], 0.8)
		if thing and not Settings.reduced_motion:
			var tw: Tween = node.create_tween()
			tw.set_parallel(true)
			tw.tween_property(thing, "position", Vector3(0, 0.75, 0), LIFT_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(thing, "rotation_degrees", Vector3(0, 200, 0), LIFT_S + LIFT_HOLD_S)
			tw.chain().tween_callback(node.queue_free)
		else:
			node.queue_free()
	if _finds.take(id):
		cache_dug.emit(id)


func _on_surfaced(id: String, cell: int) -> void:
	var lumi: Node3D = _lumi()
	var near: bool = lumi != null and lumi.global_position.distance_to(_field.hex_center(cell)) < cfg("show_within_m")
	if near:
		var n: Node3D = show_cache(id)
		if n:
			Vfx.burst("sparkle", n.global_position + n.global_basis.y * 0.3, _caches[id]["tint"], 0.5)
			Audio.play("detector", 1.25, -16.0)
	var close: bool = lumi != null and lumi.global_position.distance_to(_field.hex_center(cell)) < PartDetector.NEAR_M * 5.0
	if close:
		if Once.take("toast_cache_surfaced"):
			EventBus.toast.emit(tr("Something is buried in the cleared soil. Follow the detector and dig."), "hint")
	else:  # a robot turned it up somewhere else: say where, so no colour is missed
		var district: String = str(_finds.entry(id).get("district", ""))
		var where: String = tr(_districts.name_of(district)) if _districts and district != "" else tr("open ground")
		EventBus.toast.emit(tr("Your crew uncovered something buried in %s. The detector will find it.") % where, "hint")


## A find was given by other means than Lumi's hands here (a load, a dev hook): the world follows.
func _on_taken(id: String) -> void:
	if _caches.has(id) and not bool(_caches[id]["busy"]):
		_drop_cache(id)
	var model: WreckModel = wreck_model(id)
	if model and model.stripped.is_empty():
		var node: Node3D = wreck_node(id)
		for piece: Node3D in _wrecks[id]["junk"] as Array[Node3D]:
			if is_instance_valid(piece):
				piece.queue_free()
		(_wrecks[id]["junk"] as Array[Node3D]).clear()
		var pieces: Array[String] = []
		pieces.assign(_finds.entry(id)["pieces"])
		model.strip(pieces)
		var plant: Node = node.get_node_or_null(FindProps.SAPLING)
		if plant:
			plant.queue_free()
		node.add_child(FindProps.flowers(hash(id), model.glow()))


# --- Shared -----------------------------------------------------------------------------------

## The young plant growing out of a wreck that still holds pieces (the table's `sapling`:
## height_m, leaf colour); none when the planet's table has no `sapling`.
func _grow_sapling(node: Node3D, id: String) -> void:
	var sp: Variant = _cfg.get("sapling", {})
	if not (sp is Dictionary) or (sp as Dictionary).is_empty():
		return
	var plant: Node3D = FindProps.sapling(hash(id), float(sp.get("height_m", 1.0)), Color.html(str(sp.get("leaf", "#7cc84a"))))
	plant.position = Vector3(0.0, -WreckModel.SINK_M * 0.5, 0.0)
	node.add_child(plant)


func _lumi() -> Node3D:
	var v: Variant = _player_fn.call() if _player_fn.is_valid() else null
	return v as Node3D if is_instance_valid(v) else null


## Lumi's short dig at a spot (the detector's own: sound, soil, her shudder), then `done`. With
## no Lumi or no detector (tests) `done` runs at once. False when she is already digging.
func _dig(pos: Vector3, seconds: float, done: Callable, soil: Color) -> bool:
	var lumi: Node3D = _lumi()
	var det: Variant = lumi.get("detector") if lumi else null
	if det is PartDetector and (det as PartDetector).is_inside_tree():
		return (det as PartDetector).dig_at(pos, seconds, done, soil)
	done.call()
	return true


## The faint glint that gives a wreck away: a few sparks of its eye colour now and then while
## Lumi is within sight of it, and the slow pulse of a buried find's light.
func _glint(delta: float) -> void:
	var lumi: Node3D = _lumi()
	for id: String in _wrecks:
		var st: Dictionary = _wrecks[id]
		st["cool"] = maxf(0.0, float(st["cool"]) - delta)
		var model: WreckModel = wreck_model(id)
		if model == null or not model.eye_lit() or lumi == null:
			continue
		st["glint_t"] = float(st["glint_t"]) - delta
		if float(st["glint_t"]) > 0.0:
			continue
		var gap: Array = _cfg.get("glint_s", DEFAULTS["glint_s"])
		st["glint_t"] = _rng.randf_range(float(gap[0]), float(gap[1]))
		if lumi.global_position.distance_to(model.global_position) < GLINT_NEAR_M:
			Vfx.burst("sparkle", model.eye_point() + model.global_basis.y * 0.15, model.glow().lightened(0.3), 0.3)
	for id: String in _caches:
		var n: Node3D = cache_node(id)
		var light: OmniLight3D = n.get_node_or_null("Glint") as OmniLight3D if n else null
		if light:
			light.light_energy = 0.35 + 0.4 * maxf(0.0, sin(_t * GLINT_PULSE_RATE + float(id.length())))
