extends GutTest
## Watering robots, refill points (barrel / Water Tank / clean lake), Skimmer, crew caps.

class FakeWorld:
	extends Node3D
	var field: HexField
	var depot: Node3D
	var patch: Node3D


## The planted globe (tests/support/globe_world.gd) with the yard nodes robots look for.
class GardenWorld:
	extends GlobeWorld
	var depot: Node3D
	var patch: Node3D

const LAKE: int = 18

var _cur: Dictionary
var _world_state: Dictionary
var _parts: Array


func before_each() -> void:
	_cur = GameState.currencies.duplicate()
	_world_state = GameState.world.duplicate(true)
	_parts = GameState.parts.duplicate(true)
	GameState.world = {}


func after_each() -> void:
	GameState.currencies = _cur
	GameState.world = _world_state
	GameState.parts = _parts


func _make() -> FakeWorld:
	var w := FakeWorld.new()
	var types: Array = []
	for id: String in Economy.junk_ids:
		types.append(Economy.junk_types[id])
	w.field = HexField.new(2, 6.0, 5)
	w.field.water_ids[LAKE] = true
	w.field.generate(types, Vector2i(5, 8))
	add_child_autofree(w)
	w.depot = Node3D.new()
	w.add_child(w.depot)
	w.patch = Node3D.new()
	w.add_child(w.patch)
	return w


func _make_garden() -> GardenWorld:
	var w := GardenWorld.new(5)
	add_child_autofree(w)
	w.depot = Node3D.new()
	w.add_child(w.depot)
	w.patch = Node3D.new()
	w.add_child(w.patch)
	w.add_garden()
	return w


func _clean(w: FakeWorld, hid: int) -> void:
	for pid: int in w.field.hex_pieces[hid]:
		w.field.remove_piece(pid)


func _fleet(w: Node) -> Fleet:
	var f := Fleet.new()
	f.world = w
	w.add_child(f)
	return f


func _bot(f: Fleet, type_id: String, rname: String, at: Vector3 = Vector3.ZERO) -> Robot:
	var r := Robot.new()
	r.type_id = type_id
	r.robot_name = rname
	r.world = f.world
	f.add_child(r)
	r.global_position = at
	r.set_physics_process(false)
	return r


func test_skimmer_defined_and_in_crews() -> void:
	assert_true(Economy.robots.has("skimmer"))
	assert_eq(str(Economy.robots["skimmer"]["role"]), "skim")
	assert_true(Fleet.ROLES.has("skim"))
	assert_eq(Fleet.types_for_role("skim"), ["skimmer"] as Array[String])
	assert_true(CommandView.ROLE_NAMES.has("skim") and CommandView.ROLE_COLORS.has("skim"))
	for s: String in ["tank", "spray_radius", "refill_rate", "speed"]:
		assert_gt(Economy.robot_stat("drip", s), 0.0, "drip has stat " + s)


func test_crew_cap_follows_base_level() -> void:
	var f := Fleet.new()
	add_child_autofree(f)
	var cc: Dictionary = Economy.robot_cfg.get("crew_cap", {})
	var base: int = int(cc.get("base", 3))
	var per: int = int(cc.get("per_level", 3))
	GameState.world["hub_level"] = 1
	assert_eq(f.crew_cap(), base + per)
	GameState.world["hub_level"] = 3
	assert_eq(f.crew_cap(), base + 3 * per)
	GameState.world["hub_level"] = 1
	for i: int in base + per:
		var r := Robot.new()
		r.type_id = "scoopie"
		r.robot_name = "S%d" % i
		f.add_child(r)
	GameState.currencies["cubes"] = BigNum.from_float(1.0e9)
	GameState.currencies["parts"] = BigNum.from_float(1.0e6)  # [ui2] builds cost Parts
	var fl: Variant = (GameState.flags["research"] as Dictionary).duplicate(true) if GameState.flags.get("research") is Dictionary else null
	Research.grant("salvage_logic")  # [pace] helpers need Salvage Logic first
	Research.unlock_story("haul_rig")  # [v4bots] the Skimmer's plans come after the Haul Bug's
	Research.unlock_story("scoopie_rig")  # task M3-21: the Scoopie's plans follow the Haul Bug's
	Research.unlock_story("skimmer_rig")
	assert_false(f.can_build("scoopie"), "cleaner crew is full at level 1")
	assert_string_contains(f.build_block_reason("scoopie"), "Crew full")
	assert_true(f.can_build("skimmer"), "other crews still have room")
	GameState.world["hub_level"] = 2
	assert_true(f.can_build("scoopie"), "a hub level raises the cap")
	if fl is Dictionary:
		GameState.flags["research"] = fl
	else:
		GameState.flags.erase("research")


func test_tier_scales_water_gear() -> void:
	var w := _make()
	var f := _fleet(w)
	var a := _bot(f, "drip", "A")
	var b := _bot(f, "drip", "B")
	b.tier = 2
	assert_gt(b.stat("tank"), a.stat("tank"))
	assert_gt(b.stat("spray_radius"), a.stat("spray_radius"))
	assert_gt(b.stat("refill_rate"), a.stat("refill_rate"))


func test_waterer_picks_thirstiest_and_skips_taken() -> void:
	var w := _make_garden()
	var f := _fleet(w)
	var hid: int = w.land_cell()
	w.clean(hid)
	GameState.currencies["seeds"] = BigNum.from_float(10)
	var slots: PackedInt32Array = w.garden.hex_slots[hid]
	var near: int = slots[0]
	var far: int = slots[slots.size() - 1]
	assert_true(w.garden.plant(near) and w.garden.plant(far))
	var sp_s: float = float(w.garden.species[w.garden.slot_species[near]]["water_s"])
	w.garden.slot_water[near] = sp_s * 0.4
	w.garden.slot_water[far] = sp_s * 0.05
	var r := _bot(f, "drip", "A", w.garden.slot_pos[near])
	assert_eq(r._find_thirsty(w.garden), far, "the driest plant wins even when farther")
	var other := _bot(f, "drip", "B")
	other._target_slot = far
	assert_eq(r._find_thirsty(w.garden), near, "slots another waterer is heading for are skipped")
	w.garden.slot_water[near] = sp_s
	other._target_slot = -1
	w.garden.slot_water[far] = sp_s
	assert_eq(r._find_thirsty(w.garden), -1, "nothing thirsty")


func test_zone_first_for_waterers() -> void:
	var w := _make_garden()
	var f := _fleet(w)
	var ha: int = w.land_cell(0)
	var hb: int = w.land_cell(1)
	w.clean(ha)
	w.clean(hb)
	GameState.currencies["seeds"] = BigNum.from_float(10)
	var a: int = (w.garden.hex_slots[ha] as PackedInt32Array)[0]
	var b: int = (w.garden.hex_slots[hb] as PackedInt32Array)[0]
	w.garden.plant(a)
	w.garden.plant(b)
	w.garden.slot_water[a] = 0.0
	w.garden.slot_water[b] = 1.0
	var r := _bot(f, "drip", "A")
	assert_eq(r._find_thirsty(w.garden), a)
	f.toggle_zone_hex("water", false, hb, true)
	assert_eq(r._find_thirsty(w.garden), b, "zone plants come first")


func test_spray_waters_several_plants_in_radius() -> void:
	var w := _make_garden()
	var f := _fleet(w)
	var hid: int = w.land_cell()
	w.clean(hid)
	GameState.currencies["seeds"] = BigNum.from_float(50)
	var slots: PackedInt32Array = w.garden.hex_slots[hid]
	for s: int in slots:
		w.garden.plant(s)
		w.garden.slot_water[s] = 1.0
	var at: Vector3 = w.garden.slot_pos[slots[0]]
	var radius: float = 3.8
	var inside: Array[int] = []
	var outside: int = -1
	for s: int in slots:
		if w.garden.slot_pos[s].distance_to(at) <= radius:
			inside.append(s)
		elif outside < 0:
			outside = s
	assert_gt(inside.size(), 1, "test layout has neighbours in range")
	var r := _bot(f, "drip", "A", at + Vector3(0.5, 0, 0))
	r.water = 50.0
	r._spray_at(w.garden, at, radius)
	for s: int in inside:
		assert_gt(w.garden.slot_water[s], 20.0, "slot %d in the spray got water" % s)
	if outside >= 0:
		assert_eq(w.garden.slot_water[outside], 1.0, "slots outside the radius are untouched")
	assert_eq(r.water, 50.0 - inside.size(), "one unit of water per plant")
	assert_eq(int(r.log_stats["watered"]), inside.size())


func test_refill_points_and_tanks() -> void:
	var w := _make()
	var f := _fleet(w)
	var net: WaterNet = f.water_net
	assert_not_null(net)
	var kinds: Array = net.refill_points().map(func(p: Dictionary) -> String: return p["kind"])
	assert_eq(kinds, ["barrel"], "a dirty lake is no refill point")
	_clean(w, LAKE)
	assert_true(w.field.is_clean(LAKE))
	kinds = net.refill_points().map(func(p: Dictionary) -> String: return p["kind"])
	assert_true(kinds.has("lake"), "a clean lake is")
	var near_lake: Vector3 = w.field.hex_center(LAKE) * 1.3
	assert_eq(str(net.nearest_refill(near_lake)["kind"]), "lake")
	assert_eq(str(net.nearest_refill(net.barrel_pos())["kind"]), "barrel")
	# Tanks: on clean land only, cost cubes, spaced apart, hold a limited reserve.
	var land: int = 9
	var spot: Vector3 = w.field.hex_center(land)
	GameState.currencies["cubes"] = BigNum.from_float(10000)
	assert_eq(net.place_block_reason(spot), "Clean this hex first")
	_clean(w, land)
	assert_eq(net.place_block_reason(w.field.hex_center(LAKE)), "Not on the lake")
	var cost: float = net.tank_cost().to_float()
	assert_true(net.place_tank(spot))
	assert_almost_eq(GameState.get_currency("cubes").to_float(), 10000.0 - cost, 0.5)
	assert_gt(net.tank_cost().to_float(), cost, "each tank costs more")
	assert_eq(net.place_block_reason(spot + Vector3(1, 0, 0)), "Too close to another tank")
	var tp: Dictionary = net.nearest_refill(spot + Vector3(1.5, 0, 0))
	assert_eq(str(tp["kind"]), "tank")
	var cap: float = float(WaterNet.cfg()["capacity"])
	assert_eq(net.draw(tp, cap + 50.0), cap, "a tank gives what it holds")
	assert_eq(net.draw(tp, 5.0), 0.0)
	assert_false(net.refill_points().any(func(p: Dictionary) -> bool: return p["kind"] == "tank"), "an empty tank is skipped")
	net.persist_save()
	assert_eq((GameState.world["water_tanks"] as Array).size(), 1)


func test_skimmer_works_the_lake_and_finds_shore() -> void:
	var w := _make()
	var f := _fleet(w)
	var sk := _bot(f, "skimmer", "Sk", w.field.hex_center(9))
	var sc := _bot(f, "scoopie", "Sc", w.field.hex_center(9))
	assert_eq(sk.role(), "skim")
	assert_eq(sk._pick_work_hex(), LAKE, "skimmers work lake hexes")
	assert_false(w.field.is_water(sc._pick_work_hex()), "cleaners stay on land")
	assert_true(sk.visual.floats, "skimmers float")
	var shore: Vector3 = Robot.shore_point(w.field, w.field.hex_center(LAKE))
	var sh: int = w.field.hex_at(shore)
	assert_true(sh >= 0 and not w.field.is_water(sh), "bales go on land")
	assert_true(w.field.hexes_near(w.field.hex_center(LAKE), 1).has(sh), "right next to the lake")
	# [beat] A blocked shore point is avoided next time (skimmers no longer circle one forever).
	var other: Vector3 = Robot.shore_point(w.field, w.field.hex_center(LAKE), [shore])
	assert_gt(other.distance_to(shore), 3.9, "another bit of shore")


func test_idle_status_and_park() -> void:
	var w := _make()
	var f := _fleet(w)
	for id: int in w.field.hex_count():
		if not w.field.is_water(id):
			_clean(w, id)
	var r := _bot(f, "scoopie", "A")
	r._idling = false
	r._think(0.1)
	assert_true(r.status_text().begins_with("idle"), "nothing to clean: idle (%s)" % r.status_text())
	f.toggle_zone_hex("clean", false, 9, true)
	f.set_mode("clean", false, "stay")
	var spot: Vector3 = r._idle_spot()
	assert_lt(spot.distance_to(w.field.hex_center(9)), w.field.hex_size, "parks near its zone")
