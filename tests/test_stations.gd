extends GutTest
## Bale automation: station building/costs, auto-route, auto-baler pressing, recycler payout,
## the robot dump hook and the station upgrades.

var _cur: Dictionary
var _world: Dictionary
var _stats: Dictionary
var _ups: Dictionary
var _flags: Dictionary


func before_each() -> void:
	_cur = GameState.currencies.duplicate()
	_world = GameState.world
	_stats = GameState.stats.duplicate(true)
	_ups = GameState.upgrades.duplicate()
	_flags = GameState.flags.duplicate(true)
	GameState.flags = {}
	for id: String in ["conveyor", "auto_baler", "recycler"]:
		Research.grant(id)  # stations are research-gated (Stations.block_reason)
	GameState.currencies = {}
	GameState.world = {}
	GameState.upgrades = {}


func after_each() -> void:
	GameState.currencies = _cur
	GameState.world = _world
	GameState.stats = _stats
	GameState.upgrades = _ups
	GameState.flags = _flags


func _rich() -> void:
	for k: String in Currencies.IDS:  # [money]
		GameState.add_currency(k, BigNum.from_float(1.0e6))


func _stations() -> Stations:
	var s := Stations.new()
	add_child_autofree(s)
	return s


func _bale(fill: float = 0.9, dominant: String = "metal") -> JunkCube:
	var c := JunkCube.create(BigNum.from_float(40.0), {"fill": fill, "volume": fill * 12.0, "dominant": dominant, "colors": [Color(0.5, 0.5, 0.5)]})
	add_child_autofree(c)
	return c


func test_conveyor_costs_parts() -> void:
	var s := _stations()
	GameState.add_currency("cubes", BigNum.from_float(10000))
	assert_false(s.build("conveyor"), "needs parts")
	GameState.add_currency("parts", BigNum.from_float(100))
	assert_true(s.build("conveyor"))
	assert_true(s.built("conveyor"))
	assert_true(GameState.world["stations"]["conveyor"])
	assert_lt(GameState.get_currency("cubes").to_float(), 10000.0)
	assert_false(s.build("conveyor"), "only once")


func test_recycler_needs_hub_level_2() -> void:
	var s := _stations()
	_rich()
	assert_string_starts_with(s.block_reason("recycler"), "Requires")
	assert_false(s.build("recycler"))
	GameState.world["hub_level"] = 2
	assert_eq(s.block_reason("recycler"), "")
	assert_true(s.build("recycler"))
	assert_not_null(s.recycler)


func test_auto_route_every_nth() -> void:
	var s := _stations()
	assert_eq(s.next_route(), "depot", "no recycler: always the scale")
	_rich()
	GameState.world["hub_level"] = 2
	s.build("recycler")
	assert_eq(s.next_route(), "depot", "route off by default")
	s.cycle_route()
	assert_eq(s.route_n, 4)
	var to_rec: int = 0
	for i: int in 8:
		if s.next_route() == "recycler":
			to_rec += 1
	assert_eq(to_rec, 2)
	s.cycle_route()
	s.cycle_route()
	assert_eq(s.route_n, 1)
	assert_eq(s.next_route(), "recycler")
	s.cycle_route()
	assert_eq(s.route_n, 0, "wraps back to off")


func test_recycler_destroys_bale_and_pays_parts() -> void:
	var s := _stations()
	_rich()
	GameState.world["hub_level"] = 2
	s.build("recycler")
	var parts0: float = GameState.get_currency("parts").to_float()
	var c := _bale(1.0, "metal")
	var kg: float = c.mass
	var got: Dictionary = s.recycler.recycle(c)
	assert_gt(float(got["parts"]), 0.0)
	assert_almost_eq(GameState.get_currency("parts").to_float() - parts0, float(got["parts"]), 0.001)
	assert_eq(float(GameState.stats.get("bales_recycled", 0.0)), float(_stats.get("bales_recycled", 0.0)) + 1.0)
	assert_almost_eq(float(GameState.stats.get("junk_destroyed_kg", 0.0)) - float(_stats.get("junk_destroyed_kg", 0.0)), kg, 0.01)
	assert_true(c.is_queued_for_deletion(), "gone for good")
	# Recycling beats the scoop salvage rate for the same junk by a wide margin.
	var scoop_rate: float = 12.0 * 0.5 * 0.3
	assert_gt(float(got["parts"]), scoop_rate * 2.0)


func test_recycler_yield_upgrade() -> void:
	var s := _stations()
	_rich()
	GameState.world["hub_level"] = 2
	s.build("recycler")
	var base: Dictionary = s.recycler.recycle(_bale(1.0, "plastic"))
	GameState.upgrades["recycler_yield"] = 4
	var up: Dictionary = s.recycler.recycle(_bale(1.0, "plastic"))
	assert_gt(float(up["parts"]), float(base["parts"]))


func test_upgrade_multipliers() -> void:
	assert_almost_eq(Stations.belt_mult(), 1.0, 0.001)
	assert_almost_eq(Stations.baler_mult(), 1.0, 0.001)
	GameState.upgrades["belt_speed"] = 2
	GameState.upgrades["baler_speed"] = 1
	assert_gt(Stations.belt_mult(), 1.0)
	assert_gt(Stations.baler_mult(), 1.0)
	assert_eq(str(Economy.upgrade_defs["recycler_yield"]["tab"]), "hub")


func test_auto_baler_presses_a_bale() -> void:
	var s := _stations()
	_rich()
	assert_true(s.build("auto_baler"))
	var b: AutoBaler = s.baler
	assert_true(b.is_in_group("baler_station"))
	b.accept({"metal": 9.0, "glass": 6.0}, Vector3.ZERO)
	assert_almost_eq(b.store_fill, 15.0, 0.001)
	b._start_press()
	assert_eq(b.phase, "press")
	assert_almost_eq(b.store_fill, 15.0 - b.bale_cap(), 0.001)
	b._press(b._dur * 0.5)
	assert_not_null(b._bale, "bale strapped at the bottom of the stroke")
	assert_gt(b._bale.value.to_float(), 0.0)
	b._press(b._dur * 0.6)
	assert_eq(b.phase, "idle")


func test_robot_dumps_into_baler() -> void:
	var s := _stations()
	_rich()
	s.build("auto_baler")
	var r := Robot.new()
	r.type_id = "scoopie"
	add_child_autofree(r)
	r.global_position = s.baler.global_position + Vector3(3, 0, 3)
	r.hopper.add("metal", 10.0)
	assert_true(Stations.claim_dump(r))
	assert_true(r.has_meta("dump_to"))
	r.global_position = s.baler.dump_point()
	Stations.dump_step(r)
	assert_true(r.hopper.is_empty())
	assert_false(r.has_meta("dump_to"))
	assert_almost_eq(s.baler.store_fill, 10.0, 0.001)
	r.hopper.add("metal", 10.0)
	r.global_position = s.baler.global_position + Vector3(200, 0, 0)
	assert_false(Stations.claim_dump(r), "out of service range: bale on the spot")


func test_haul_drop_prefers_closer_feeder() -> void:
	var s := _stations()
	var r := Node3D.new()
	add_child_autofree(r)
	var depot_pos := Vector3(0, 0, -1.8)
	r.global_position = Vector3(12, 0, -1)
	assert_eq(Stations.haul_drop(r, depot_pos), depot_pos, "no conveyor yet")
	_rich()
	s.build("conveyor")
	assert_eq(Stations.haul_drop(r, depot_pos), s.conveyor.hopper_pos())
	r.global_position = Vector3(-6, 0, 0)
	assert_eq(Stations.haul_drop(r, depot_pos), depot_pos)


func test_save_state_roundtrip() -> void:
	var s := _stations()
	_rich()
	s.build("auto_baler")
	s.baler.accept({"plastic": 5.0}, Vector3.ZERO)
	s.persist_save()
	var st: Dictionary = GameState.world["stations"]
	assert_true(st.has("baler"))
	s.remove_from_group("stations")
	var s2 := _stations()
	assert_not_null(s2.baler)
	assert_almost_eq(s2.baler.store_fill, 5.0, 0.001)


func test_hub_panel_shows_stations_section() -> void:
	var s := _stations()
	var hub := Hub.new()
	add_child_autofree(hub)
	var hp := HubPanel.new()
	hp.hub = hub
	add_child_autofree(hp)
	var sp: StationsPanel = null
	for c: Node in hp.get_children():
		if c is StationsPanel:
			sp = c
	assert_not_null(sp)
	_rich()
	s.build("conveyor")
	hp.refresh()
	assert_true(sp.visible)
