class_name ShardSystem
extends Node3D
## Places Memory Shards in hexes; a shard surfaces (a small glowing recorder) when its hex is
## cleaned. Walk up and press E to read it. Found shards persist and also restore WREN's memory.

var world: Node
var docs: Array = []
var _placed: Dictionary = {}  # hex id -> shard index
var _visible: Dictionary = {}  # hex id -> Node3D
var _globe: bool = false  # [orbB] on the walkable globe: the start hub's region (slice_orbit.gd)


func setup() -> void:
	docs = Economy.read_json("res://data/shards.json").get("shards", [])
	var rng := RandomNumberGenerator.new()
	rng.seed = world.field.seed_value + 77
	var candidates: Array[int] = []
	var so: Node = world.get("orbit")
	_globe = so != null  # [orbB] the globe: the start hub's region, nearest the hub first
	var cells: Variant = (so.get("globe") as OrbitPlanet).grid.cells_around((so.get("globe") as OrbitPlanet).start_cell(), SiteManager.REGION_RINGS) if _globe else range(world.field.hex_count())
	var f: HexField = world.field
	for id: int in cells:
		if f.hex_hub[id] == 0 and not f.is_water(id) and not (_globe and (f as SphereField).cells.has_flag(id, SphereCells.F_SITE)):
			candidates.append(id)
	var hub_c: Vector3 = (so.get("globe") as OrbitPlanet).field.hex_center((so.get("globe") as OrbitPlanet).start_cell()) if _globe else Vector3.ZERO
	# Act 1 shards near the hub first; deterministic shuffle by distance + noise.
	candidates.sort_custom(func(a: int, b: int) -> bool:
		return f.hex_center(a).distance_to(hub_c) + rng.randf() * 0.0 < f.hex_center(b).distance_to(hub_c))
	for i: int in docs.size():
		var pick: int = mini(1 + i * 3 + rng.randi_range(0, 2), candidates.size() - 1)
		_placed[candidates[pick]] = i
	EventBus.hex_cleaned.connect(func(hid: int, _p: Vector3, _b: BigNum) -> void: _reveal(hid, true))
	for hid: int in _placed:
		if world.field.is_clean(hid):
			_reveal(hid, false)


## Where the shard in hex hid surfaces (and the beacon stands before it does).
## [v4world] Owner playtest 3 #55: on the globe, the nearest reachable open ground to the hex's
## spot (TargetReach: not in a building, a lake, on steep ground or walled in); re-checked when
## more footprints are known (YardKeepOut.version).
var _spots: Dictionary = {}  # hex id -> [keep-out version, Vector3]


func spot(hid: int) -> Vector3:
	if not _globe:
		return world.field.hex_center(hid) + Vector3(1.2, 0.0, 0.8)
	var t: TargetReach = TargetReach.for_world(world, true)
	var ver: int = t.keep_out.version if t.keep_out else 0
	var c: Variant = _spots.get(hid)
	if c is Array and int(c[0]) == ver:
		return c[1]
	var fr: Basis = SphereGrid.frame(world.field.hex_center(hid).normalized())
	var p: Vector3 = t.open_spot((world.field.hex_center(hid) + fr.x * 1.2 + fr.z * 0.8).normalized())
	_spots[hid] = [ver, p]
	return p


## [v4world] #55: surfaced shards move when more building footprints become known (a town that
## finished building after they surfaced), so none is left inside a building.
var _ko_ver: int = -1
var _ko_t: float = 0.0


func _process(delta: float) -> void:
	_ko_t -= delta
	if not _globe or _ko_t > 0.0 or _visible.is_empty():
		return
	_ko_t = 2.0
	var t: TargetReach = TargetReach.for_world(world)
	var ver: int = t.keep_out.version if t and t.keep_out else 0
	if ver == _ko_ver:
		return
	_ko_ver = ver
	for hid: int in _visible:
		var pos: Vector3 = spot(hid)
		(_visible[hid] as Node3D).global_transform = Transform3D(SphereGrid.frame(pos.normalized()), pos)


func found(i: int) -> bool:
	return str(docs[i]["id"]) in GameState.flags.get("shards_found", [])


func _reveal(hid: int, fresh: bool) -> void:
	if not _placed.has(hid) or found(int(_placed[hid])) or _visible.has(hid):
		return
	var pos: Vector3 = spot(hid)
	var node := Node3D.new()
	add_child(node)
	node.global_position = pos
	if _globe:  # [orbB] the same offset in the cell's own frame, on the ground, upright
		node.global_transform = Transform3D(SphereGrid.frame(pos.normalized()), pos)
	var mi := MeshInstance3D.new()
	mi.mesh = AssetLib.model_mesh_lite("portable_cassette_player" if AssetLib.has_model("portable_cassette_player") else "boombox", 2000)
	mi.scale = Vector3.ONE * 0.6
	node.add_child(mi)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.5, 0.85, 1.0)
	glow.light_energy = 1.2
	glow.omni_range = 2.0
	glow.position = Vector3(0, 0.4, 0)
	node.add_child(glow)
	_visible[hid] = node
	if fresh:
		Vfx.burst("sparkle", pos + OrbitUp.up(pos) * 0.4, Color(0.5, 0.85, 1.0))
		EventBus.toast.emit(tr("Something surfaced in the cleared ground. A memory shard."), "story")


## [onboard] Where the next unread shard is, for the purple waypoint: a surfaced one (read it), else
## the nearest hex still hiding one (clean it). {pos, surfaced} or {}.
func waypoint(from: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var bd: float = INF
	for hid: int in _visible:
		var n: Node3D = _visible[hid]
		var d: float = n.global_position.distance_to(from)
		if d < bd:
			bd = d
			best = {"pos": n.global_position, "surfaced": true}
	if not best.is_empty():
		return best
	for hid: int in _placed:
		if found(int(_placed[hid])) or world.field.is_clean(hid):
			continue
		var c: Vector3 = world.field.hex_center(hid)
		var d2: float = c.distance_to(from)
		if d2 < bd:
			bd = d2
			best = {"pos": spot(hid) if _globe else c, "surfaced": false, "hex": hid}  # [v4world] #55: where it will surface, on open ground
	return best


## Returns the shard index within reach of a position, or -1.
func nearby(pos: Vector3) -> int:
	for hid: int in _visible:
		var n: Node3D = _visible[hid]
		if n.global_position.distance_to(pos) < 2.0:
			return int(_placed[hid])
	return -1


func take(pos: Vector3) -> Dictionary:
	for hid: int in _visible:
		var n: Node3D = _visible[hid]
		if n.global_position.distance_to(pos) < 2.0:
			var i: int = int(_placed[hid])
			var list: Array = GameState.flags.get("shards_found", [])
			list.append(str(docs[i]["id"]))
			GameState.flags["shards_found"] = list
			GameState.inc_stat("shards_found")
			n.queue_free()
			_visible.erase(hid)
			Audio.play("ding", 0.8, -6.0)
			return docs[i]
	return {}
