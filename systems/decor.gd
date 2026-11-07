class_name Decor
extends Node3D
## [late] Garden Mode decorations in this district (data/decor.json). Pure helpers are static
## (footprints, costs, charm); the live node builds the placed items and saves them in
## GameState.world["decor"] = {"items": [{t, x, z, r}]} (x, z = grid cell of the footprint's
## corner, r = quarter turns). Charm (the sum of every item's charm) is cached in
## GameState.world["decor_charm"] and gives this district a small plant-growth bonus through
## CradleMode.stat_mod -> Decor.stat_mult.
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


## Economy.stat hook (via CradleMode.stat_mod): this district's charm speeds its plants up a little.
static func stat_mult(stat_id: String) -> float:
	if stat_id != "plant_growth":
		return 1.0
	return 1.0 + charm_bonus(float(GameState.world.get("decor_charm", 0.0)))


## What it costs, as {currency: amount}.
static func cost(type_id: String) -> Dictionary:
	return def(type_id).get("cost", {})


static func cost_text(type_id: String) -> String:
	var bits: Array[String] = []
	var c: Dictionary = cost(type_id)
	for k: String in c:
		bits.append(L10nFmt.amount(k, float(c[k])) if L10nFmt.has_count(k) else "%s %s" % [Settings.fmt(BigNum.from_float(float(c[k]))), TranslationServer.translate(k)])  # [i18n2]
	return "  ".join(bits)


## Why it can't be bought ("" = it can).
static func buy_block_reason(type_id: String) -> String:
	var d: Dictionary = def(type_id)
	if d.is_empty():
		return "unknown"
	var finds: int = int(d.get("needs_finds", 0))
	if finds > 0 and Collection.count() < finds:
		return TranslationServer.translate("Needs %d Collection finds (%d so far)") % [finds, Collection.count()]
	var chips: int = int(d.get("needs_chips", 0))  # [extras] Seed of the Week paint chips
	if chips > 0 and WeeklyChallenge.chip_count() < chips:
		return TranslationServer.translate("Needs %d Seed of the Week paint chips (%d so far)") % [chips, WeeklyChallenge.chip_count()]
	var c: Dictionary = cost(type_id)
	for k: String in c:
		if not GameState.can_afford(k, BigNum.from_float(float(c[k]))):
			return TranslationServer.translate("Needs %s") % cost_text(type_id)
	return ""


## Garden Mode is open in this district: after any Cradle finale, or with the base at level 5.
static func unlocked() -> bool:
	return CradleMode.unlocked() or int(GameState.world.get("hub_level", 1)) >= int(cfg().get("unlock_hub_level", 5)) or DevHooks.has("garden")


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
	var st: Variant = GameState.world.get("decor")
	if st is Dictionary:
		for it: Variant in (st as Dictionary).get("items", []):
			if it is Dictionary and not def(str((it as Dictionary).get("t", ""))).is_empty():
				_add((it as Dictionary).duplicate(), false)
	_store()


func persist_save() -> void:
	_store()


func _store() -> void:
	GameState.world["decor"] = {"items": items.duplicate(true)}
	GameState.world["decor_charm"] = charm_of(items)


func charm() -> float:
	return charm_of(items)


## Why a decoration can't go here ("" = it can). Ignores cost.
func place_block_reason(type_id: String, cell: Vector2i, rot: int, ignore_item: int = -1) -> String:
	if world == null or world.get("field") == null:
		return "no field"
	var f: HexField = world.field
	var yard: float = float(cfg().get("yard_radius", 9.0))
	for c: Vector2i in footprint(type_id, cell, rot):
		var p := Vector3((c.x + 0.5) * grid(), 0.0, (c.y + 0.5) * grid())
		if Vector2(p.x, p.z).length() < yard:
			return TranslationServer.translate("Too close to the base machines")
		var h: int = f.hex_at(p)
		if h < 0:
			return TranslationServer.translate("Outside the district")
		if f.is_water(h):
			return TranslationServer.translate("That's water")
		if f.hex_hub[h] == 0 and not f.is_clean(h):
			return TranslationServer.translate("Clean this hex first")
		if f.locked.has(h):
			return TranslationServer.translate("Frozen in")
		if f.layout != null and f.layout.surface_at(p.x, p.z) == CityLayout.Surface.BUILDING:
			return TranslationServer.translate("A building is in the way")
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
		var c: Dictionary = cost(type_id)
		for k: String in c:
			GameState.spend(k, BigNum.from_float(float(c[k])))
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
		var c: Dictionary = cost(str(it["t"]))
		for k: String in c:
			GameState.add_currency(k, BigNum.from_float(float(c[k])))
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
	if world and world.get("layout") != null and world.layout:
		p.y = clampf(world.layout.height_at(p.x, p.z), 0.0, 0.3)
	n.position = p
	n.rotation.y = rot * PI * 0.5
	items.append({"t": t, "x": cell.x, "z": cell.y, "r": rot})
	nodes.append(n)
	_reindex()
	if fx:
		Vfx.burst("sparkle", p + Vector3(0, 0.8, 0), Color(0.75, 1.0, 0.7), 0.8)
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
