extends GutTest
## [late] Garden Mode (systems/decor.gd, data/decor.json): footprints and rotation, placement
## rules, paying and refunds (so moving is free), charm and its growth bonus, persistence through
## GameState.world["decor"], and the "decor" group hook wildlife can use.

class FakeOrbit extends Node:
	var yard: Vector3

	func yard_point(_anchor: String) -> Vector3:
		return yard


class FakeWorld extends Node3D:
	var field: SphereField
	var orbit: FakeOrbit


var _cur: Dictionary
var _flags: Dictionary
var _stats: Dictionary
var _world: Dictionary
var w: FakeWorld
var _globe: GlobeFixture


func before_each() -> void:
	_cur = GameState.currencies.duplicate()
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)
	_world = GameState.world
	GameState.currencies = {}
	GameState.flags = {}
	GameState.stats = {}
	GameState.world = {}
	_globe = GlobeFixture.new()
	w = FakeWorld.new()
	w.field = _globe.field
	w.orbit = FakeOrbit.new()
	w.orbit.yard = _globe.frame_transform().origin  # every base machine stands at the hub's centre
	w.add_child(w.orbit)
	add_child_autofree(w)


func after_each() -> void:
	GameState.currencies = _cur
	GameState.flags = _flags
	GameState.stats = _stats
	GameState.world = _world


func _clean_all() -> void:
	for h: int in _globe.region():
		_globe.clean(h)


func _decor() -> Decor:
	var d := Decor.new()
	w.add_child(d)
	d.global_transform = _globe.frame_transform()  # the hub frame the slice hosts it in
	d.setup(w)
	return d


func _open_cell() -> Vector2i:
	return Vector2i(0, 32)


func test_every_type_has_a_builder_and_sane_data() -> void:
	assert_gte(Decor.types().size(), 9)
	for t: Dictionary in Decor.types():
		var id: String = str(t["id"])
		assert_true((t.get("size", []) as Array).size() == 2, "%s has a size" % id)
		assert_gt(float(t.get("charm", 0.0)), 0.0, "%s adds charm" % id)
		assert_true((t.get("cost", {}) as Dictionary).has("cubes"), "%s costs cubes" % id)
		var n: Node3D = DecorProps.build(id)
		assert_gt(n.get_child_count(), 0, "%s builds a prop" % id)
		n.free()
	for id: String in ["bench", "lamp", "fountain", "statue", "planter", "flower_bed", "path", "lumi_sculpture"]:
		assert_false(Decor.def(id).is_empty(), "the catalogue has %s" % id)


func test_footprint_rotates() -> void:
	assert_eq(Decor.footprint("bench", Vector2i(2, 3), 0), [Vector2i(2, 3), Vector2i(3, 3)] as Array[Vector2i])
	assert_eq(Decor.footprint("bench", Vector2i(2, 3), 1), [Vector2i(2, 3), Vector2i(2, 4)] as Array[Vector2i])
	assert_eq(Decor.footprint("fountain", Vector2i(0, 0), 3).size(), 4)
	assert_eq(Decor.center_of("path", Vector2i(1, 2), 0), Vector3(1.5, 0, 2.5) * Decor.grid())
	assert_eq(Decor.cell_at(Vector3(1.4, 0, -0.2)), Vector2i(1, -1))


func test_placement_rules() -> void:
	var d: Decor = _decor()
	assert_ne(d.place_block_reason("bench", _open_cell(), 0), "", "dirty ground can't be decorated")
	_clean_all()
	assert_eq(d.place_block_reason("bench", _open_cell(), 0), "")
	assert_ne(d.place_block_reason("bench", Vector2i(0, 1), 0), "", "not on top of the base machines")
	assert_true(d.place("fountain", _open_cell(), 0, false))
	assert_ne(d.place_block_reason("path", _open_cell() + Vector2i(1, 1), 0), "", "cells are taken")
	assert_eq(d.place_block_reason("path", _open_cell() + Vector2i(2, 0), 0), "")


func test_buying_and_refunds_make_moving_free() -> void:
	_clean_all()
	var d: Decor = _decor()
	assert_false(d.place("bench", _open_cell(), 0), "can't afford it")
	var cost: float = float(Decor.cost("bench")["cubes"])
	GameState.add_currency("cubes", BigNum.from_float(cost))
	assert_true(d.place("bench", _open_cell(), 1))
	assert_almost_eq(GameState.get_currency("cubes").to_float(), 0.0, 0.01)
	var i: int = d.item_at(_open_cell())
	assert_eq(i, 0)
	var it: Dictionary = d.remove(i)
	assert_eq(str(it["t"]), "bench")
	assert_almost_eq(GameState.get_currency("cubes").to_float(), cost, 0.01, "picked up: everything back")
	assert_eq(d.items.size(), 0)
	assert_eq(d.item_at(_open_cell()), -1)
	assert_true(d.place("bench", _open_cell() + Vector2i(3, 0), 1), "put down elsewhere for the same price")
	assert_eq(int(GameState.stats["decor_placed"]), 2)


func test_collection_gate() -> void:
	GameState.add_currency("cubes", BigNum.from_float(1e7))
	assert_ne(Decor.buy_block_reason("lumi_sculpture"), "", "needs Collection finds first")
	var need: int = int(Decor.def("lumi_sculpture")["needs_finds"])
	var found: Array = []
	for t: Dictionary in Collection.defs().slice(0, need):
		found.append(str(t["id"]))
	GameState.flags["trinkets"] = found
	assert_eq(Decor.buy_block_reason("lumi_sculpture"), "")


func test_charm_bonus_is_small_and_capped() -> void:
	assert_almost_eq(Decor.charm_bonus(0.0), 0.0, 0.0001)
	assert_almost_eq(Decor.charm_bonus(5.0), 5.0 * float(Decor.cfg()["charm_growth"]), 0.0001)
	assert_almost_eq(Decor.charm_bonus(1000.0), float(Decor.cfg()["charm_cap"]), 0.0001)
	_clean_all()
	var d: Decor = _decor()
	var g0: float = Economy.stat("plant_growth")
	d.place("fountain", _open_cell(), 0, false)
	d.place("bench", _open_cell() + Vector2i(3, 0), 0, false)
	assert_almost_eq(d.charm(), float(Decor.def("fountain")["charm"]) + float(Decor.def("bench")["charm"]), 0.001)
	assert_gt(Economy.stat("plant_growth"), g0, "charm speeds plants up")
	assert_lt(Economy.stat("plant_growth"), g0 * 1.09, "a little")
	assert_almost_eq(Decor.stat_mult("capacity"), 1.0, 0.0001, "only plant growth")


func test_decorations_persist() -> void:
	_clean_all()
	var d: Decor = _decor()
	d.place("fountain", _open_cell(), 0, false)
	d.place("bench", _open_cell() + Vector2i(3, 0), 1, false)
	d.place("lamp", _open_cell() + Vector2i(-2, 0), 2, false)
	d.persist_save()
	var saved: String = JSON.stringify(GameState.world["decor"])
	var charm: float = d.charm()
	d.free()
	GameState.world = JSON.parse_string(JSON.stringify(GameState.world))  # through JSON, like a save file
	var d2: Decor = _decor()
	assert_eq(JSON.stringify({"items": d2.items}), saved)
	assert_almost_eq(d2.charm(), charm, 0.001)
	assert_eq(d2.item_at(_open_cell() + Vector2i(3, 1)), 1, "the rotated bench still covers its cells")
	assert_eq(d2.nodes.size(), 3)


func test_wildlife_hook_groups() -> void:
	_clean_all()
	var d: Decor = _decor()
	d.place("bench", _open_cell(), 0, false)
	d.place("bird_bath", _open_cell() + Vector2i(4, 0), 0, false)
	var cats: Array[Node3D] = Decor.liked_by(get_tree(), "cat")
	assert_eq(cats.size(), 2, "cats like benches and bird baths")
	assert_eq(Decor.liked_by(get_tree(), "deer").size(), 0)
	var n: Node3D = d.nodes[0]
	assert_true(n.is_in_group("decor"))
	assert_true(n.is_in_group("decor_bench"))
	assert_eq(str(n.get_meta("decor_type")), "bench")
