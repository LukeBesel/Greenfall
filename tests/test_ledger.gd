extends GutTest
## The Ledger arc (story/ledger.gd) and easter eggs (story/eggs.gd): act progression, small and
## safe drops, jammers, persistence through the field's save bits, egg placement and rewards.

var _cur: Dictionary
var _flags: Dictionary
var _world: Dictionary
var _stats: Dictionary
var field: HexField


func before_each() -> void:
	_cur = GameState.currencies.duplicate()
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)
	_world = GameState.world
	GameState.flags = {}
	GameState.currencies = {}
	GameState.world = {}
	var types: Array = []
	for id: String in Economy.junk_ids:
		types.append(Economy.junk_types[id])
	field = HexField.new(3, 10.0, 4471, CityLayout.new(4471, 150.0, false))
	field.clean_threshold = 0.97
	field.generate(types, Vector2i(60, 90))
	field.place_landmarks(Economy.landmarks)


func after_each() -> void:
	GameState.currencies = _cur
	GameState.flags = _flags
	GameState.world = _world
	GameState.stats = _stats


func _clean_hex(id: int) -> void:
	for pid: int in field.hex_pieces[id]:
		field.remove_piece(pid)


func _first_junk_hex() -> int:
	for id: int in field.hex_count():
		if field.hex_hub[id] == 0 and not field.is_water(id) and field.hex_pieces[id].size() > 20:
			return id
	return -1


func _new_ledger() -> LedgerArc:
	var lg := LedgerArc.new()
	lg.cfg = Economy.read_json("res://data/ledger.json")
	add_child_autofree(lg)
	return lg


func test_acts_follow_progress_in_order() -> void:
	assert_eq(LedgerArc.next_act(0, 2, false, 1), 0, "quiet before 3 hexes")
	assert_eq(LedgerArc.next_act(0, 3, false, 1), 1, "intercepts after 3 hexes")
	assert_eq(LedgerArc.next_act(1, 3, false, 5), 1, "drones need the first sprout")
	assert_eq(LedgerArc.next_act(1, 3, true, 1), 2, "drones after the first sprout")
	assert_eq(LedgerArc.next_act(2, 9, true, 2), 2, "relay needs hub level 3")
	assert_eq(LedgerArc.next_act(2, 9, true, 3), 3)
	assert_eq(LedgerArc.next_act(0, 9, true, 3), 3, "catches up through every act at once")
	assert_eq(LedgerArc.next_act(4, 0, false, 1), 4, "never goes backwards")


func test_drop_is_small_and_dirties_a_clean_hex() -> void:
	var hid: int = _first_junk_hex()
	assert_gt(hid, -1)
	_clean_hex(hid)
	assert_true(field.is_clean(hid))
	var cleaned_before: int = field.cleaned_count
	var r := RandomNumberGenerator.new()
	r.seed = 5
	var pids: PackedInt32Array = LedgerArc.pick_drop_pieces(field, hid, r, 0.045, 3, 14)
	assert_between(pids.size(), 3, 14)
	var vol: float = 0.0
	for pid: int in pids:
		assert_eq(field.piece_hex[pid], hid)
		vol += field.piece_vol[pid]
	assert_lt(vol / field.hex_total[hid], 0.25, "a drop only brings back a small share of the hex")
	assert_true(field.revive_pieces(pids))
	assert_false(field.is_clean(hid))
	assert_eq(field.cleaned_count, cleaned_before - 1)
	# Cleaning the dropped pieces flips it clean again.
	var flipped: bool = false
	for pid: int in pids:
		flipped = field.remove_piece(pid) or flipped
	assert_true(flipped)
	assert_eq(field.cleaned_count, cleaned_before)


func test_drop_candidates_skip_planted_water_hub_and_dirty() -> void:
	var a: int = -1
	var b: int = -1
	for id: int in field.hex_count():
		if field.hex_hub[id] == 0 and not field.is_water(id) and field.hex_pieces[id].size() > 5:
			if a < 0:
				a = id
			elif b < 0:
				b = id
	_clean_hex(a)
	_clean_hex(b)
	var planted := func(id: int) -> bool: return id == b
	var c: Array[int] = LedgerArc.drop_candidates(field, planted)
	assert_true(a in c)
	assert_false(b in c, "planted hexes are never touched")
	for id: int in c:
		assert_eq(field.hex_hub[id], 0)
		assert_false(field.is_water(id))
		assert_true(field.is_clean(id))


func test_dropped_state_survives_save_and_load() -> void:
	var hid: int = _first_junk_hex()
	_clean_hex(hid)
	var r := RandomNumberGenerator.new()
	r.seed = 9
	var pids: PackedInt32Array = LedgerArc.pick_drop_pieces(field, hid, r)
	field.revive_pieces(pids)
	var saved: Dictionary = field.to_dict()
	var types: Array = []
	for id: String in Economy.junk_ids:
		types.append(Economy.junk_types[id])
	var g := HexField.new(3, 10.0, 4471, CityLayout.new(4471, 150.0, false))
	g.clean_threshold = 0.97
	g.generate(types, Vector2i(60, 90))
	assert_true(g.apply_dict(saved))
	assert_false(g.is_clean(hid))
	assert_eq(g.cleaned_count, field.cleaned_count)
	for pid: int in pids:
		assert_eq(g.piece_alive[pid], 1)


func test_jammer_needs_drones_scales_and_persists_per_district() -> void:
	var lg := _new_ledger()
	for k: String in ["cubes", "sheet_metal", "glass_cullet"]:
		GameState.add_currency(k, BigNum.from_float(1.0e7))
	assert_false(lg.jammer_visible())
	assert_false(lg.build_jammer(), "nothing to jam before act 2")
	GameState.flags["ledger_act"] = 2
	assert_true(lg.jammer_visible())
	assert_eq(lg.jammer_radius(), 0.0)
	var i0: float = lg.drop_interval()
	var m0: float = lg.jammer_cost_mult()
	assert_true(lg.build_jammer())
	assert_eq(int(GameState.world.get("ledger_jammers", 0)), 1, "stored in the district's world blob")
	assert_gt(lg.jammer_radius(), 10.0)
	assert_gt(lg.jammer_cost_mult(), m0)
	assert_true(lg.build_jammer())
	assert_true(lg.build_jammer())
	assert_false(lg.build_jammer(), "max 3")
	assert_gt(lg.jammer_radius(), 40.0)
	assert_gt(lg.drop_interval(), i0 * 0.9, "drones come less often with jammers")
	assert_string_contains(lg.jammer_text(), "3 / 3")


func test_relay_spot_is_deterministic_and_on_open_ground() -> void:
	var a: Dictionary = LedgerArc.relay_spot(field)
	var b: Dictionary = LedgerArc.relay_spot(field)
	assert_eq(a["pos"], b["pos"])
	var p: Vector3 = a["pos"]
	assert_ne(field.layout.surface_at(p.x, p.z), CityLayout.Surface.BUILDING)
	assert_gt(Vector2(p.x, p.z).length(), 15.0, "out in the district, not at the base")
	assert_eq(LedgerArc.compass(Vector3(0, 0, -10)), "north")
	assert_eq(LedgerArc.compass(Vector3(10, 0, 0)), "east")


func test_relay_visible_only_in_its_district_from_act_3() -> void:
	var lg := _new_ledger()
	GameState.flags["ledger_act"] = 2
	assert_false(lg.relay_visible())
	GameState.flags["ledger_act"] = 3
	GameState.flags["ledger_relay_hub"] = GameState.current_hub
	assert_true(lg.relay_visible())
	GameState.flags["ledger_relay_hub"] = GameState.current_hub + 1
	assert_false(lg.relay_visible())


func test_flags_survive_gamestate_roundtrip() -> void:
	var keep: Array = [GameState.upgrades.duplicate(true), GameState.parts.duplicate(true), GameState.districts, GameState.current_hub, GameState.planet_state, GameState.created_unix, GameState.saved_unix]
	GameState.flags["ledger_act"] = 3
	GameState.flags["ledger_relay_hub"] = 0
	GameState.flags["egg_duck"] = true
	GameState.flags["eggs_found"] = ["duck"]
	GameState.world["ledger_jammers"] = 2
	var d: Dictionary = GameState.to_dict()
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(d))
	GameState.from_dict(snapshot)
	assert_eq(LedgerArc.act(), 3)
	assert_eq(LedgerArc.jammer_count(), 2)
	assert_true(EasterEggs.is_found("duck"))
	assert_eq(EasterEggs.found_count(), 1)
	GameState.upgrades = keep[0]
	GameState.parts = keep[1]
	GameState.districts = keep[2]
	GameState.current_hub = keep[3]
	GameState.planet_state = keep[4]
	GameState.created_unix = keep[5]
	GameState.saved_unix = keep[6]


func test_egg_data_has_enough_original_secrets() -> void:
	var data: Dictionary = Economy.read_json("res://data/eggs.json")
	var eggs: Array = data.get("eggs", [])
	assert_gte(eggs.size(), 15)
	var wren: Dictionary = Economy.read_json("res://data/wren_lines.json")
	var seen: Dictionary = {}
	for e: Dictionary in eggs:
		var id: String = str(e["id"])
		assert_false(seen.has(id), "unique id " + id)
		seen[id] = true
		assert_false((e.get("reward", {}) as Dictionary).is_empty(), id + " has a reward")
		assert_ne(str(e.get("lore", "")), "", id + " has a reason to exist")
		assert_true(wren.has("egg_" + id), id + " has WREN lines")
	for k: String in ["ledger_intercept", "ledger_drop", "ledger_jammed", "jammer_built", "ledger_relay", "ledger_resolved", "ledger_seeds", "egg_found"]:
		assert_true(wren.has(k), "WREN reacts to " + k)
		assert_eq((wren[k] as Array).size(), 3, k + " has all three memory stages")


func test_egg_placement_deterministic_and_clear_of_buildings() -> void:
	var data: Dictionary = Economy.read_json("res://data/eggs.json")
	var defs: Dictionary = {}
	var order: Array[String] = []
	for e: Dictionary in data["eggs"]:
		defs[str(e["id"])] = e
		order.append(str(e["id"]))
	var ids: Array[String] = EasterEggs.district_eggs(order, defs, 0, field.seed_value, 9)
	assert_gte(ids.size(), 10, "Old Town has the starter set")
	var avoid: Array[Vector3] = [Vector3.ZERO]
	var a: Array[Dictionary] = EasterEggs.plan_spots(field, ids, defs, avoid)
	var b: Array[Dictionary] = EasterEggs.plan_spots(field, ids, defs, avoid)
	assert_eq(a.size(), b.size())
	assert_gte(a.size(), ids.size(), "every egg (and every part) got a spot")
	for i: int in a.size():
		assert_eq(a[i]["pos"], b[i]["pos"])
		var p: Vector3 = a[i]["pos"]
		assert_ne(field.layout.surface_at(p.x, p.z), CityLayout.Surface.BUILDING)
		assert_eq(field.hex_hub[field.hex_at(p)], 0)
	var other: Array[String] = EasterEggs.district_eggs(order, defs, 2, 9999, 9)
	assert_eq(other.size(), 9)
	assert_eq(other, EasterEggs.district_eggs(order, defs, 2, 9999, 9))


func test_finding_an_egg_rewards_once() -> void:
	var eggs := EasterEggs.new()
	var data: Dictionary = Economy.read_json("res://data/eggs.json")
	for e: Dictionary in data["eggs"]:
		eggs.defs[str(e["id"])] = e
	add_child_autofree(eggs)
	var watcher: Array = []
	var cb := func(id: String) -> void: watcher.append(id)
	EventBus.easter_egg_found.connect(cb)
	var before: float = float(GameState.stats.get("eggs_found", 0.0))
	eggs.found("vending")
	eggs.found("vending")
	EventBus.easter_egg_found.disconnect(cb)
	assert_true(EasterEggs.is_found("vending"))
	assert_eq(watcher, ["vending"])
	assert_almost_eq(float(GameState.stats.get("eggs_found", 0.0)) - before, 1.0, 0.001)
	assert_almost_eq(GameState.get_currency("cubes").to_float(), 150.0, 0.01)
	assert_almost_eq(GameState.get_currency("trinkets").to_float(), 1.0, 0.01)


func test_interactables_pick_nearest_enabled() -> void:
	var reg := Interactables.new()
	add_child_autofree(reg)
	var a := Node3D.new()
	var b := Node3D.new()
	add_child_autofree(a)
	add_child_autofree(b)
	a.position = Vector3(1, 0, 0)
	b.position = Vector3(2, 0, 0)
	var used: Array = []
	var gate: Array = [true]
	reg.register(a, 3.0, "E   a", func() -> void: used.append("a"), func() -> bool: return gate[0])
	reg.register(b, 3.0, func() -> String: return "E   b", func() -> void: used.append("b"))
	assert_eq(reg.prompt(Vector3.ZERO), "E   a")
	gate[0] = false
	assert_eq(reg.prompt(Vector3.ZERO), "E   b", "disabled entries are skipped")
	assert_true(reg.try_use(Vector3.ZERO))
	assert_eq(used, ["b"])
	assert_false(reg.try_use(Vector3(50, 0, 0)))


func test_every_egg_prop_and_the_drone_build() -> void:
	var data: Dictionary = Economy.read_json("res://data/eggs.json")
	for e: Dictionary in data["eggs"]:
		for kind: String in [str(e.get("kind", "")), str(e.get("final", ""))]:
			if kind == "":
				continue
			var n: Node3D = EggProps.build(kind, 1)
			assert_gt(n.get_child_count(), 0, kind + " has visuals")
			n.free()
	var d := LedgerDrone.new()
	add_child_autofree(d)
	assert_not_null(d.cargo)
	d.set_friendly(true)
	assert_true(d.friendly)
