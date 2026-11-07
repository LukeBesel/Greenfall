class_name ShardSystem
extends Node3D
## Places Memory Shards in hexes; a shard surfaces (a small glowing recorder) when its hex is
## cleaned. Walk up and press E to read it. Found shards persist and also restore WREN's memory.

var world: Node
var docs: Array = []
var _placed: Dictionary = {}  # hex id -> shard index
var _visible: Dictionary = {}  # hex id -> Node3D


func setup() -> void:
	docs = Economy.read_json("res://data/shards.json").get("shards", [])
	var rng := RandomNumberGenerator.new()
	rng.seed = world.field.seed_value + 77
	var candidates: Array[int] = []
	for id: int in world.field.hex_count():
		if world.field.hex_hub[id] == 0:
			candidates.append(id)
	# Act 1 shards near the hub first; deterministic shuffle by distance + noise.
	candidates.sort_custom(func(a: int, b: int) -> bool:
		return world.field.hex_center(a).length() + rng.randf() * 0.0 < world.field.hex_center(b).length())
	for i: int in docs.size():
		var pick: int = mini(1 + i * 3 + rng.randi_range(0, 2), candidates.size() - 1)
		_placed[candidates[pick]] = i
	EventBus.hex_cleaned.connect(func(hid: int, _p: Vector3, _b: BigNum) -> void: _reveal(hid, true))
	for hid: int in _placed:
		if world.field.is_clean(hid):
			_reveal(hid, false)


func found(i: int) -> bool:
	return str(docs[i]["id"]) in GameState.flags.get("shards_found", [])


func _reveal(hid: int, fresh: bool) -> void:
	if not _placed.has(hid) or found(int(_placed[hid])) or _visible.has(hid):
		return
	var pos: Vector3 = world.field.hex_center(hid) + Vector3(1.2, 0.0, 0.8)
	var node := Node3D.new()
	add_child(node)
	node.global_position = pos
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
		Vfx.burst("sparkle", pos + Vector3(0, 0.4, 0), Color(0.5, 0.85, 1.0))
		EventBus.toast.emit(tr("Something surfaced in the cleared ground. A memory shard."), "story")


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
