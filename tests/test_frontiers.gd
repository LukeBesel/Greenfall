extends GutTest
## [biomes] Late-game frontier districts: planet hubs, unlock gates, sandstorm re-dust, thawing,
## Sunken City water levels, the Cradle pad hook, species rules and frontier state round trips.

class FakeView:
	extends RefCounted
	var refreshed: Array[int] = []
	func set_life(_id: int, _life: float) -> void:
		pass
	func refresh_hex(id: int, _flip: bool = false) -> void:
		refreshed.append(id)

class FakeWorld:
	extends Node3D
	var field: HexField
	var view := FakeView.new()
	var planet: PlanetData
	var slice_cells := PackedInt32Array()
	var garden: Garden
	var hex_levels: HexLevels
	var hub_index: int = 0
	var patch: Node3D
	var frontier: FrontierDistrict
	var launching: bool = false
	func any_modal_open() -> bool:
		return false

var _saved: Dictionary


func before_each() -> void:
	_saved = GameState.to_dict()
	GameState.new_game()


func after_each() -> void:
	GameState.from_dict(_saved)


func _types() -> Array:
	var types: Array = []
	for id: String in Economy.junk_ids:
		types.append(Economy.junk_types[id])
	return types


## A small frontier world: radius 3 field of the given kind, real Garden and HexLevels.
func _make(kind_id: String, radius: int = 3) -> FakeWorld:
	var k: Dictionary = Frontiers.def(kind_id)
	var w := FakeWorld.new()
	var layout := CityLayout.new(777, 150.0, true)
	w.field = HexField.new(radius, 10.0, 777, layout)
	w.field.biome = str(k["biome"])
	w.field.biome_set = Economy.biome_set(w.field.biome)
	w.field.water_ids = Frontiers.water_ids_for(k, radius, 10.0)
	w.field.generate(_types(), Vector2i(20, 30))
	Frontiers.toughen(w.field, float(k.get("vol_mult", 1.0)))
	w.planet = PlanetData.new(5, 3, 10.0)
	w.planet.generate()
	w.slice_cells.resize(w.field.hex_count())
	for i: int in w.field.hex_count():
		w.slice_cells[i] = i % w.planet.cell_count()
	add_child_autofree(w)
	w.patch = Node3D.new()
	w.add_child(w.patch)
	return w


func _finish(w: FakeWorld) -> FrontierDistrict:
	var fd := FrontierDistrict.new()
	w.add_child(fd)
	fd.prepare(w)
	w.frontier = fd
	w.garden = Garden.new()
	w.garden.world = w
	w.garden.late_hexes = fd.drain_order.duplicate()
	w.add_child(w.garden)
	w.garden.setup()
	w.hex_levels = HexLevels.new()
	w.hex_levels.world = w
	w.hex_levels.celebrate = false
	w.add_child(w.hex_levels)
	w.hex_levels.setup()
	return fd


func _clean(w: FakeWorld, h: int) -> void:
	for pid: int in w.field.hex_pieces[h]:
		if w.field.piece_alive[pid] == 1:
			w.field.remove_piece(pid)


# --- Planet and unlocks ----------------------------------------------------------------------

func test_planet_appends_one_hub_per_frontier() -> void:
	var p := PlanetData.new(4471, 6, 10.0)
	p.generate()
	assert_eq(p.frontier_hubs.size(), 4, "four frontier hubs")
	assert_eq(p.base_hub_count + 4, p.hubs.size(), "appended after the ordinary hubs")
	for k: String in PlanetData.FRONTIER_KINDS:
		var hi: int = int(p.frontier_hubs[k])
		assert_gte(hi, p.base_hub_count)
		assert_eq(p.frontier_kind(hi), k)
		assert_false(Frontiers.def(k).is_empty(), "%s has data" % k)
		assert_eq(PlanetData.BIOMES[p.biome[p.hubs[hi]]], str(Frontiers.def(k)["biome"]), "%s cell painted" % k)
	assert_eq(p.frontier_kind(0), "", "Old Town is not a frontier")


func test_frontier_unlocks_follow_research_and_bases() -> void:
	var p := PlanetData.new(4471, 6, 10.0)
	p.generate()
	var dust: int = int(p.frontier_hubs["dust_flats"])
	assert_false(Frontiers.can_launch(p, dust), "locked on a new game")
	assert_true(Frontiers.can_launch(p, 1), "ordinary hubs always open")
	Research.grant("dune_charts")
	assert_false(bool(Frontiers.unlock_status("dust_flats", p.frontier_hubs)["ok"]), "research alone is not enough")
	GameState.world["hub_level"] = 5
	GameState.districts[3] = {"hub_level": 5}
	var st: Dictionary = Frontiers.unlock_status("dust_flats", p.frontier_hubs)
	assert_true(bool(st["ok"]), str(st["lines"]))
	assert_true(Frontiers.can_launch(p, dust))
	# Frozen Port also needs the Dust Flats base at level 3.
	Research.grant("thermal_lance")
	GameState.districts[4] = {"hub_level": 5}
	assert_false(bool(Frontiers.unlock_status("frozen_port", p.frontier_hubs)["ok"]))
	GameState.districts[dust] = {"hub_level": 3, "frontier": {}}
	assert_true(bool(Frontiers.unlock_status("frozen_port", p.frontier_hubs)["ok"]))
	# The Cradle needs all three frontiers at level 5 and Growing.
	Research.grant("ark_beacon")
	assert_false(bool(Frontiers.unlock_status("cradle_returns", p.frontier_hubs)["ok"]))
	for k: String in ["dust_flats", "frozen_port", "sunken_city"]:
		GameState.districts[int(p.frontier_hubs[k])] = {"hub_level": 5, "frontier": {"growing_frac": 0.6}}
	assert_true(bool(Frontiers.unlock_status("cradle_returns", p.frontier_hubs)["ok"]))


func test_frontier_fields_are_bigger_and_tougher() -> void:
	var cfg: Dictionary = Economy.planet.get("slice_field", {})
	for k: Dictionary in Frontiers.kinds():
		assert_gt(int(k["radius"]), int(cfg.get("radius", 3)), "%s has more hexes" % k["id"])
		assert_gt(float(k["vol_mult"]), 1.0, "%s junk is bulkier" % k["id"])
		assert_gt(float(k["value_mult"]), 1.0)
		assert_true(Economy.biome_sets.has(str(k["biome"])), "%s has a junk set" % k["id"])
		assert_true(Codex.entry("frontiers:" + str(k["id"])).size() > 0, "%s has a codex entry" % k["id"])
		for layer: Variant in k.get("ground_layers", {}).values():
			assert_not_null(AssetLib.tex(str(layer), "diff"), "ground texture %s" % layer)
	var f := HexField.new(2, 10.0, 9, null)
	f.generate(_types(), Vector2i(10, 12))
	var before: float = f.hex_total[3]
	Frontiers.toughen(f, 1.5)
	assert_almost_eq(f.hex_total[3], before * 1.5, 0.01)
	assert_almost_eq(f.hex_left[3], f.hex_total[3], 0.01)


# --- Dust Flats: sandstorm re-dust -----------------------------------------------------------

func test_sandstorm_redusts_bare_unsheltered_hexes() -> void:
	var w := _make("dust_flats")
	var fd := _finish(w)
	for h: int in w.field.hex_count():
		if w.field.hex_hub[h] == 0:
			_clean(w, h)
	var levels: Dictionary = w.hex_levels.levels
	# A Sustained hex at ring 2 shelters its neighbours; a planted hex is never touched.
	var wall: int = int(w.field.axial_to_id[Vector2i(2, 0)])
	levels[wall] = 4
	var planted: int = int(w.field.axial_to_id[Vector2i(-2, 0)])
	GameState.add_currency("seeds", BigNum.from_float(5))
	assert_true(w.garden.plant((w.garden.hex_slots[planted] as PackedInt32Array)[0]))
	var cands: Array[int] = Frontiers.storm_candidates(w.field, levels, fd._is_planted, 4, 1)
	assert_false(wall in cands, "the Sustained hex itself is sheltered")
	for nb: Vector2i in Hex.neighbors(Vector2i(2, 0)):
		var n: int = int(w.field.axial_to_id.get(nb, -1))
		if n >= 0:
			assert_false(n in cands, "neighbour %d of the windbreak is sheltered" % n)
	assert_false(planted in cands, "planted ground holds")
	var far: int = int(w.field.axial_to_id[Vector2i(0, -3)])
	assert_true(far in cands, "bare open ground gets buried")
	var clean_before: int = w.field.cleaned_count
	var hit: Array[int] = fd.storm_hit()
	assert_gt(hit.size(), 0, "the storm buries something")
	assert_lte(hit.size(), Frontiers.storm_count(fd.kind["storm"], clean_before, false))
	for h: int in hit:
		assert_false(w.field.is_clean(h), "hex %d is dirty again" % h)
		assert_true(h in cands)
		assert_true(h in w.view.refreshed)
	assert_eq(w.field.cleaned_count, clean_before - hit.size())
	assert_eq(fd.storms, 1)
	# Dune Fences widen the shelter and cut the storm.
	assert_lt(Frontiers.storm_count(fd.kind["storm"], 40, true), Frontiers.storm_count(fd.kind["storm"], 40, false))
	assert_lt(Frontiers.storm_candidates(w.field, levels, fd._is_planted, 4, 2).size(), cands.size() + 1)


func test_dust_flats_well_is_dry() -> void:
	var w := _make("dust_flats")
	_finish(w)
	var net := WaterNet.new()
	net.world = w
	assert_true(net.barrel_dry(), "the base well is dry here")
	assert_lt(net.tank_regen_mult(), 1.0, "tanks refill slowly in the desert")
	Research.grant("dew_condensers")
	assert_gt(net.tank_regen_mult(), Frontiers.def("dust_flats")["water"]["tank_regen_mult"])
	assert_gt(Frontiers.plant_drain_mult("dust_flats"), 1.0)
	assert_eq(Frontiers.plant_drain_mult(""), 1.0)
	net.free()


# --- Frozen Port: thaw --------------------------------------------------------------------------

func test_ice_locks_junk_until_thawed() -> void:
	var w := _make("frozen_port")
	var fd := _finish(w)
	var iced: Array[int] = []
	for h: int in fd.ice.size():
		if fd.ice[h] > 0.0:
			iced.append(h)
	assert_gt(iced.size(), w.field.hex_count() / 2, "most of the port starts frozen")
	for h: int in w.field.hex_count():
		if w.field.is_water(h):
			assert_gt(fd.ice[h], 0.0, "the harbour is frozen")
	var h0: int = iced[0]
	assert_true(w.field.locked.has(h0))
	var c: Vector3 = w.field.hex_center(h0)
	for pid: int in w.field.pieces_within(c, w.field.hex_size):
		assert_ne(w.field.piece_hex[pid], h0, "no piece of an iced hex is reachable")
	var tgt: int = w.field.find_scoop_target(c, Vector3(0, 0, -1), 4.0, 3.0)
	assert_true(tgt < 0 or w.field.piece_hex[tgt] != h0, "the scoop can't take iced junk")
	# A heater thaws its own hex in thaw_s and warms the neighbours at spread_mult.
	var ice_cfg: Dictionary = fd.kind["ice"]
	var rates: Dictionary = Frontiers.thaw_rates(w.field, ice_cfg, [h0], -1, false, false)
	assert_almost_eq(float(rates[h0]), 1.0 / float(ice_cfg["thaw_s"]), 0.0001)
	var nb: int = int(w.field.axial_to_id.get(Hex.neighbors(w.field.hex_axial[h0])[0], -1))
	if nb >= 0:
		assert_almost_eq(float(rates[nb]), float(rates[h0]) * float(ice_cfg["spread_mult"]), 0.0001)
	var faster: Dictionary = Frontiers.thaw_rates(w.field, ice_cfg, [h0], -1, true, false)
	assert_gt(float(faster[h0]), float(rates[h0]), "Heat Pumps thaw faster")
	GameState.add_currency("cubes", BigNum.from_float(1000))
	var cost: float = fd.heater_cost().to_float()
	assert_true(fd._place_heater(h0, true))
	assert_almost_eq(GameState.get_currency("cubes").to_float(), 1000.0 - cost, 0.01)
	assert_gt(fd.heater_cost().to_float(), cost, "each heater costs more")
	fd._thaw_step(float(ice_cfg["thaw_s"]) * 0.5)
	assert_true(w.field.locked.has(h0), "half way: still frozen")
	fd._thaw_step(float(ice_cfg["thaw_s"]) * 0.55)
	assert_eq(fd.ice[h0], 0.0)
	assert_false(w.field.locked.has(h0), "thawed: the junk is reachable")
	assert_gt(w.field.pieces_within(c, w.field.hex_size * 0.5).size(), 0)


func test_frozen_port_plants_need_greenhouse_or_hardy_seeds() -> void:
	var w := _make("frozen_port")
	var fd := _finish(w)
	fd.ice.fill(0.0)
	fd._update_locks()
	var h: int = int(w.field.axial_to_id[Vector2i(1, 0)])
	_clean(w, h)
	assert_false(fd.slot_plantable(h), "too cold outdoors")
	var slot: int = (w.garden.hex_slots[h] as PackedInt32Array)[0]
	assert_false(w.garden.plantable(slot))
	GameState.add_currency("cubes", BigNum.from_float(5000))
	assert_true(fd._build_greenhouse(h, true))
	assert_true(fd.slot_plantable(h), "a greenhouse keeps it warm")
	assert_gt(float(w.garden.hex_grow_bonus.get(h, 0.0)), 0.0, "and grows faster")
	var other: int = int(w.field.axial_to_id[Vector2i(-1, 0)])
	_clean(w, other)
	Research.grant("cold_hardy_seeds")
	assert_true(fd.slot_plantable(other), "cold-hardy seeds grow outdoors")
	# Outdoors only cold-hardy species; natives stay in their own frontier.
	for sp: Dictionary in w.garden.species:
		var m: float = Frontiers.species_mult(sp, "frozen_port", false)
		if m > 0.0:
			assert_true(bool(sp.get("cold_hardy", false)), "%s is cold-hardy" % sp["id"])
	var ice_plant: Dictionary = {}
	for sp: Dictionary in w.garden.species:
		if sp["id"] == "iceplant":
			ice_plant = sp
	assert_eq(Frontiers.species_mult(ice_plant, "dust_flats"), 1.0)
	assert_eq(Frontiers.species_mult(ice_plant, ""), 0.0, "natives never turn up in old districts")
	assert_eq(Frontiers.species_mult(ice_plant, "frozen_port", true), 0.0)


# --- Sunken City: water levels -----------------------------------------------------------------

func test_draining_reveals_streets_ring_by_ring() -> void:
	var w := _make("sunken_city")
	var fd := _finish(w)
	var fl: Dictionary = fd.kind["flood"]
	var water: int = 0
	for h: int in w.field.hex_count():
		if w.field.is_water(h):
			water += 1
	assert_gt(water, w.field.hex_count() / 2, "mostly water")
	assert_false(Frontiers.drain_ready(w.field, 0, fl), "nothing skimmed yet")
	var ring2: Array[int] = Frontiers.drain_hexes(w.field, 1, fl)
	assert_gt(ring2.size(), 0)
	for h: int in ring2:
		assert_eq(Frontiers.ring_of(w.field, h), int(fl["dry_ring"]) + 1)
	# Skim 80% of the next ring: the pumps can run.
	var need: int = int(ceil(ring2.size() * float(fl["drain_at"])))
	for i: int in need:
		_clean(w, ring2[i])
	assert_true(Frontiers.drain_ready(w.field, 0, fl))
	var slots_before: int = w.garden.slot_pos.size()
	var revealed: Array[int] = fd.drain_next(false)
	assert_eq(revealed, ring2)
	assert_eq(fd.drained, 1)
	for h: int in revealed:
		assert_false(w.field.is_water(h), "hex %d is a street now" % h)
		assert_true(w.garden.hex_slots.has(h), "and has plant slots")
		assert_true(w.hex_levels.levels.has(h), "and a hex level")
	assert_gt(w.garden.slot_pos.size(), slots_before)
	var stranded: int = 0
	for h: int in revealed.slice(0, need):
		if not w.field.is_clean(h):
			stranded += 1
	assert_gt(stranded, 0, "stranded debris on the revealed streets")
	assert_lt(Frontiers.sink_for(1, fl), Frontiers.sink_for(0, fl), "the city rises")
	assert_eq(Frontiers.sink_for(int(fl["stages"]), fl), 0.0)
	# Round trip: a fresh district restores the drained streets and slot order.
	fd.persist_save()
	var saved_slots: int = w.garden.slot_pos.size()
	var w2 := _make("sunken_city")
	var fd2 := _finish(w2)
	assert_eq(fd2.drained, 1)
	assert_eq(fd2.drain_order, fd.drain_order)
	assert_eq(w2.garden.slot_pos.size(), saved_slots)
	for h: int in revealed:
		assert_false(w2.field.is_water(h))
		assert_eq(w2.garden.slot_pos[(w2.garden.hex_slots[h] as PackedInt32Array)[0]], w.garden.slot_pos[(w.garden.hex_slots[h] as PackedInt32Array)[0]])


# --- Cradle Returns -----------------------------------------------------------------------------

func test_cradle_pad_completion_fires_the_finale_hook() -> void:
	var w := _make("cradle_returns", 4)
	var fd := _finish(w)
	var pad: Array[int] = Frontiers.pad_hexes(w.field, fd.kind["pad"])
	assert_eq(pad.size(), 7, "a centre hex and its ring")
	var p0: Dictionary = Frontiers.cradle_progress(w.field, w.hex_levels.levels, fd.kind)
	assert_false(bool(p0["done"]))
	var got: Array = []
	var cb := func(hi: int) -> void: got.append(hi)
	EventBus.cradle_district_complete.connect(cb)
	for h: Variant in w.hex_levels.levels:
		w.hex_levels.levels[h] = 3
	for h: int in pad:
		_clean(w, h)
		w.hex_levels.levels[h] = 3
	var p1: Dictionary = Frontiers.cradle_progress(w.field, w.hex_levels.levels, fd.kind)
	assert_eq(float(p1["pad_clean"]), 1.0)
	assert_false(bool(p1["done"]), "clean is not enough: the pad must be Sustained")
	for h: int in pad:
		w.hex_levels.levels[h] = 4
	fd._cradle_step()
	assert_true(fd.done)
	assert_eq(got, [0], "fires once with the hub index")
	fd._cradle_step()
	fd.complete()
	assert_eq(got.size(), 1, "only once")
	assert_true(GameState.flags.get("cradle_returned", false))
	EventBus.cradle_district_complete.disconnect(cb)


# --- Save state -------------------------------------------------------------------------------

func test_frozen_port_state_round_trip() -> void:
	var w := _make("frozen_port")
	var fd := _finish(w)
	GameState.add_currency("cubes", BigNum.from_float(100000))
	var iced: Array = range(fd.ice.size()).filter(func(h: int) -> bool: return fd.ice[h] > 0.0)
	fd._place_heater(int(iced[0]), true)
	fd._place_heater(int(iced[1]), true)
	fd._thaw_step(20.0)
	fd.ice[int(iced[2])] = 0.0
	fd._update_locks()
	var free_h: int = int(iced[2])
	_clean(w, free_h)
	fd._build_greenhouse(free_h, true)
	fd.storms = 3
	fd.persist_save()
	var saved: Dictionary = (GameState.world["frontier"] as Dictionary).duplicate(true)
	var w2 := _make("frozen_port")
	var fd2 := _finish(w2)
	assert_eq(fd2.heaters, fd.heaters)
	assert_eq(fd2.greenhouses, fd.greenhouses)
	assert_eq(fd2.storms, 3)
	for h: int in fd.ice.size():
		assert_almost_eq(fd2.ice[h], fd.ice[h], 0.0001)
	assert_eq(w2.field.locked.size(), w.field.locked.size())
	assert_eq(str(saved["heaters"]), str(fd2.heaters))
