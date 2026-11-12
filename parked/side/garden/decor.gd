class_name Decor
extends Node3D
## [late] Garden Mode decorations in this district (data/decor.json). Pure helpers are static
## (footprints, costs, charm); the live node builds the placed items and saves them in
## GameState.world["decor"] = {"items": [{t, x, z, r}]} (x, z = grid cell of the footprint's
## corner, r = quarter turns). Charm (the sum of every item's charm) is cached in
## GameState.world["decor_charm"] and gives this district a small plant-growth bonus through
## Economy.stat -> Decor.stat_mult.
##
## Wildlife hook (no dependency either way): every placed item is a Node3D in group "decor" with
##   meta "decor_type" (String) and meta "decor_wildlife" (Array of animal kinds that like it,
##   e.g. "cat", "bird", "deer"), plus group "decor_<type>". `Decor.liked_by(tree, kind)` lists them.

const PATH: String = "res://data/decor.json"

static var _cfg: Dictionary = {}

var world: Node
var items: Array = []           # [{t, x, z, r}]
var nodes: Array[Node3D] = []   # parallel to items
var _occupied: Dictionary = {}  # Vector2i cell -> item index


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = Economy.read_json(PATH)
	return _cfg


static func types() -> Array:
	return cfg().get("types", [])


static func type_ids() -> Array[String]:
	var out: Array[String] = []
	for t: Dictionary in types():
		out.append(str(t["id"]))
	return out


static func def(id: String) -> Dictionary:
	for t: Dictionary in types():
		if str(t["id"]) == id:
			return t
	return {}


static func grid() -> float:
	return float(cfg().get("grid", 1.0))


## Cells a decoration covers (pure). Odd quarter turns swap width and depth.
static func footprint(type_id: String, cell: Vector2i, rot: int) -> Array[Vector2i]:
	var sz: Array = def(type_id).get("size", [1, 1])
	var w: int = int(sz[0])
	var d: int = int(sz[1])
	if rot % 2 == 1:
		var tmp: int = w
		w = d
		d = tmp
	var out: Array[Vector2i] = []
	for i: int in w:
		for j: int in d:
			out.append(cell + Vector2i(i, j))
	return out


## World position of a footprint's centre (y = 0).
static func center_of(type_id: String, cell: Vector2i, rot: int) -> Vector3:
	var cells: Array[Vector2i] = footprint(type_id, cell, rot)
	var s := Vector2.ZERO
	for c: Vector2i in cells:
		s += Vector2(c) + Vector2(0.5, 0.5)
	s /= float(cells.size())
	return Vector3(s.x, 0.0, s.y) * grid()


static func cell_at(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / grid())), int(floor(p.z / grid())))


static func charm_of(item_list: Array) -> float:
	var c: float = 0.0
	for it: Dictionary in item_list:
		c += float(def(str(it.get("t", ""))).get("charm", 0.0))
	return c


## Plant-growth bonus from a charm score (pure): charm_growth per point, capped.
static func charm_bonus(charm: float) -> float:
	return minf(charm * float(cfg().get("charm_growth", 0.004)), float(cfg().get("charm_cap", 0.08)))


## Economy.stat hook: this district's charm speeds its plants up a little.
static func stat_mult(stat_id: String) -> float:
	if stat_id != "plant_growth":
		return 1.0
	return 1.0 + charm_bonus(float(GameState.world.get("decor_charm", 0.0)))


## What it costs, as {currency: amount}.
static func cost(type_id: String) -> Dictionary:
	return def(type_id).get("cost", {})


static func cost_text(type_id: String) -> String:
	return Currencies.cost_text(cost(type_id))  # [money]


## Why it can't be bought ("" = it can).
static func buy_block_reason(type_id: String) -> String:
	var d: Dictionary = def(type_id)
	if d.is_empty():
		return "unknown"
	var finds: int = int(d.get("needs_finds", 0))
	if finds > 0 and Collection.count() < finds:
		return TranslationServer.translate("Needs %d Collection finds (%d so far)") % [finds, Collection.count()]
	if not GameState.can_afford_all(cost(type_id)):  # [money]
		return TranslationServer.translate("Needs %s") % cost_text(type_id)
	return ""


## Garden Mode is open in this district: after the finale, or with the base at level 5.
static func unlocked() -> bool:
	return bool(GameState.flags.get("bloom_finale_seen", false)) or int(GameState.world.get("hub_level", 1)) >= int(cfg().get("unlock_hub_level", 5)) or DevHooks.has("garden")


## Animals of `kind` can find the decorations they like through this (wildlife hook).
static func liked_by(tree: SceneTree, kind: String) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n: Node in tree.get_nodes_in_group("decor"):
		if n is Node3D and kind in (n.get_meta("decor_wildlife", []) as Array):
			out.append(n)
	return out


# --- Live node ---------------------------------------------------------------------------

func setup(p_world: Node) -> void:
	world = p_world
	name = "Decor"
	add_to_group("persist")
	var st: Variant = _state()
	if st is Dictionary:
		for it: Variant in (st as Dictionary).get("items", []):
			if it is Dictionary and not def(str((it as Dictionary).get("t", ""))).is_empty():
				_add((it as Dictionary).duplicate(), false)
	_store()


func persist_save() -> void:
	_store()


func _store() -> void:
	if hub_index != 0:  # another hub's garden: its own list in the start site's dict
		if not GameState.world.get("orbit_decor") is Dictionary:
			GameState.world["orbit_decor"] = {}
		(GameState.world["orbit_decor"] as Dictionary)[str(hub_index)] = {"items": items.duplicate(true)}
	else:
		GameState.world["decor"] = {"items": items.duplicate(true)}
	GameState.world["decor_charm"] = charm_of(items)  # the charm of the hub Lumi is at


func charm() -> float:
	return charm_of(items)


## Why a decoration can't go here ("" = it can). Ignores cost.
func place_block_reason(type_id: String, cell: Vector2i, rot: int, ignore_item: int = -1) -> String:
	if world == null or world.get("field") == null:
		return "no field"
	var f: SphereField = world.field
	for c: Vector2i in footprint(type_id, cell, rot):
		var p := Vector3((c.x + 0.5) * grid(), 0.0, (c.y + 0.5) * grid())
		p.y = ground_y(p)  # the site's yard has its machines at anchors, and buildings with colliders
		if _near_anchor(p):
			return TranslationServer.translate("Too close to the base machines")
		if _solid_at(p):
			return TranslationServer.translate("Something is already here")
		var h: int = f.hex_at(to_global(p))
		if f.is_water(h):
			return TranslationServer.translate("That's water")
		if f.hex_hub[h] == 0 and not f.is_clean(h):
			return TranslationServer.translate("Clean this hex first")
		if f.locked.has(h):
			return TranslationServer.translate("Frozen in")
		if _occupied.has(c) and int(_occupied[c]) != ignore_item:
			return TranslationServer.translate("Something is already here")
	return ""


func item_at(cell: Vector2i) -> int:
	return int(_occupied.get(cell, -1))


## Buys and places a decoration. Returns false (nothing spent) if it can't go there.
func place(type_id: String, cell: Vector2i, rot: int, pay: bool = true, fx: bool = true) -> bool:
	if place_block_reason(type_id, cell, rot) != "":
		return false
	if pay:
		if buy_block_reason(type_id) != "":
			return false
		GameState.spend_all(cost(type_id))  # [money]
	_add({"t": type_id, "x": cell.x, "z": cell.y, "r": rot % 4}, fx)
	GameState.inc_stat("decor_placed")
	var kinds: Array = GameState.flags.get("decor_kinds", [])
	if not (type_id in kinds):
		kinds.append(type_id)
	GameState.flags["decor_kinds"] = kinds
	GameState.stats["decor_kinds"] = float(kinds.size())
	GameState.stats["decor_charm_best"] = maxf(float(GameState.stats.get("decor_charm_best", 0.0)), charm())
	_store()
	return true


## Takes a decoration back (everything it cost is returned). Returns its item, or {}.
func remove(index: int, refund: bool = true) -> Dictionary:
	if index < 0 or index >= items.size():
		return {}
	var it: Dictionary = items[index]
	if refund:
		GameState.add_all(cost(str(it["t"])))  # [money]
	nodes[index].queue_free()
	items.remove_at(index)
	nodes.remove_at(index)
	_reindex()
	_store()
	return it


func _add(it: Dictionary, fx: bool) -> void:
	var t: String = str(it["t"])
	var cell := Vector2i(int(it["x"]), int(it["z"]))
	var rot: int = int(it.get("r", 0))
	var n: Node3D = DecorProps.build(t)
	n.name = "Decor_%s_%d" % [t, items.size()]
	n.add_to_group("decor")
	n.add_to_group("decor_" + t)
	n.set_meta("decor_type", t)
	n.set_meta("decor_wildlife", (def(t).get("wildlife", []) as Array).duplicate())
	add_child(n)
	var p: Vector3 = center_of(t, cell, rot)
	p.y = ground_y(p)  # frame-local, on the ground's own up
	n.transform = Transform3D(up_basis(p) * Basis(Vector3.UP, rot * PI * 0.5), p)
	items.append({"t": t, "x": cell.x, "z": cell.y, "r": rot})
	nodes.append(n)
	_reindex()
	if fx:
		Vfx.burst("sparkle", n.to_global(Vector3(0, 0.8, 0)), Color(0.75, 1.0, 0.7), 0.8)
		Audio.play("pop", 1.0, -6.0)
		var s0: Vector3 = n.scale
		n.scale = s0 * 0.6
		n.create_tween().tween_property(n, "scale", s0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _reindex() -> void:
	_occupied.clear()
	for i: int in items.size():
		var it: Dictionary = items[i]
		for c: Vector2i in footprint(str(it["t"]), Vector2i(int(it["x"]), int(it["z"])), int(it.get("r", 0))):
			_occupied[c] = i


# --- A garden per hub, in the hub frame (planet/orbit/hub_frame.gd) -----------------------------
# Grid cells are hub-frame metres (site-local, +Y up). Hub 0 keeps GameState.world["decor"];
# other hubs keep GameState.world["orbit_decor"][hub].

var hub_index: int = 0  # set by the frame host


func _state() -> Variant:
	if hub_index != 0:
		return (GameState.world.get("orbit_decor", {}) as Dictionary).get(str(hub_index))
	return GameState.world.get("decor")


## Frame-local ground height at p (x, z).
func ground_y(p: Vector3) -> float:
	return to_local((world.field as SphereField).terrain.ground(to_global(Vector3(p.x, 0.0, p.z)).normalized())).y


## Frame-local basis whose +Y is the ground's own up at p.
func up_basis(p: Vector3) -> Basis:
	var up: Vector3 = (global_basis.inverse() * (world.field as SphereField).up_at(to_global(p))).normalized()
	return Basis(Quaternion(Vector3.UP, up))


func _near_anchor(p: Vector3) -> bool:
	if hub_index != 0:
		return false
	var so: Node = world.orbit
	for nm: String in LedgerArc.YARD_ANCHORS:
		var a: Vector3 = to_local(so.call("yard_point", nm))
		if Vector2(a.x - p.x, a.z - p.z).length() < 2.2:
			return true
	return false


func _solid_at(p: Vector3) -> bool:
	if not is_inside_tree() or get_world_3d() == null:
		return false
	var sh := CylinderShape3D.new()
	sh.radius = grid() * 0.42
	sh.height = 1.6
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	q.transform = Transform3D(global_basis.orthonormalized(), to_global(p + Vector3(0, 1.15, 0)))
	q.collision_mask = 1 | PhysLayers.PROP  # the static world and props (the site prefabs' structures)
	q.exclude = _own_bodies()
	return not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _own_bodies() -> Array[RID]:
	var out: Array[RID] = []
	for n: Node3D in nodes:
		for sb: Node in n.find_children("*", "StaticBody3D", true, false):
			out.append((sb as StaticBody3D).get_rid())
	return out
