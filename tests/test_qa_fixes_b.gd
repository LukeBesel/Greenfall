extends GutTest
## QA fixes (batch B): skimmer / auto-baler dump claim, bale reservations, auto-baler save during a
## press, recalled haulers, research gates, Control Core choice, multibot crew caps, saved bale
## info, idle rescan back-off and the Command view controller focus style.

class FakeView:
	extends RefCounted
	func set_life(_id: int, _life: float) -> void:
		pass

class FakeWorld:
	extends Node3D
	var field: HexField
	var view := FakeView.new()
	var planet: PlanetData
	var slice_cells := PackedInt32Array()
	var garden: Garden
	var depot: Node3D
	var patch: Node3D

var _cur: Dictionary
var _world_state: Dictionary
var _parts: Array
var _flags: Dictionary
var _stats: Dictionary
var _ups: Dictionary


func before_each() -> void:
	_cur = GameState.currencies.duplicate()
	_world_state = GameState.world.duplicate(true)
	_parts = GameState.parts.duplicate(true)
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)
	_ups = GameState.upgrades.duplicate()
	GameState.world = {}
	GameState.flags = {}
	GameState.parts = []
	GameState.currencies = {}
	GameState.upgrades = {}


func after_each() -> void:
	GameState.currencies = _cur
	GameState.world = _world_state
	GameState.parts = _parts
	GameState.flags = _flags
	GameState.stats = _stats
	GameState.upgrades = _ups


func _rich() -> void:
	for k: String in Currencies.IDS:  # [money]
		GameState.add_currency(k, BigNum.from_float(1.0e6))


func _stations() -> Stations:
	var s := Stations.new()
	add_child_autofree(s)
	return s


func _make() -> FakeWorld:
	var w := FakeWorld.new()
	var types: Array = []
	for id: String in Economy.junk_ids:
		types.append(Economy.junk_types[id])
	w.field = HexField.new(2, 6.0, 5)
	w.field.generate(types, Vector2i(5, 8))
	w.planet = PlanetData.new(5, 3, 10.0)
	w.planet.generate()
	w.slice_cells.resize(w.field.hex_count())
	for i: int in w.field.hex_count():
		w.slice_cells[i] = i
	add_child_autofree(w)
	var d := Depot.new()
	w.depot = d
	w.add_child(d)
	var cubes := Node3D.new()
	cubes.name = "Cubes"
	w.add_child(cubes)
	w.patch = Node3D.new()
	w.add_child(w.patch)
	w.garden = Garden.new()
	w.garden.world = w
	w.add_child(w.garden)
	w.garden.setup()
	return w


func _fleet(w: Node) -> Fleet:
	var f := Fleet.new()
	f.world = w
	if w:
		w.add_child(f)
	else:
		add_child_autofree(f)
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


func _bale(fill: float = 0.9) -> JunkCube:
	var c := JunkCube.create(BigNum.from_float(40.0), {"fill": fill, "volume": fill * 12.0, "dominant": "metal", "colors": [Color(0.5, 0.5, 0.5)]})
	add_child_autofree(c)
	return c


# --- #13 Skimmer stuck at the shore ------------------------------------------------------------

func test_skimmer_never_claims_the_auto_baler() -> void:
	for id: String in ["conveyor", "auto_baler", "recycler"]:
		Research.grant(id)
	var s := _stations()
	_rich()
	assert_true(s.build("auto_baler"))
	var r := Robot.new()
	r.type_id = "skimmer"
	add_child_autofree(r)
	r.global_position = s.baler.global_position + Vector3(3, 0, 3)
	r.hopper.add("plastic", 10.0)
	assert_false(Stations.claim_dump(r), "skimmers bale on the shore")
	assert_false(r.has_meta("dump_to"))
	r.type_id = "scoopie"
	assert_true(Stations.claim_dump(r), "cleaners still use the baler")
	r.reset_targets()
	assert_false(r.has_meta("dump_to"), "reset_targets drops a stale claim")


# --- #15 Bale reservations ----------------------------------------------------------------

func test_picking_up_a_bale_clears_its_reservation() -> void:
	var c := _bale()
	c.set_meta("reserved", true)
	c.set_carried(true)
	assert_false(bool(c.get_meta("reserved", false)))
	c.set_carried(false)
	assert_false(bool(c.get_meta("reserved", false)))


func test_hauler_releases_a_bale_patch_grabbed() -> void:
	var w := _make()
	var f := _fleet(w)
	var h := _bot(f, "haulbug", "H", Vector3(5, 0, 5))
	var a := JunkCube.create(BigNum.from_float(10.0), {"fill": 0.8})
	w.get_node("Cubes").add_child(a)
	a.global_position = Vector3(-8, 0.3, 8)
	h._think_haul()
	assert_eq(h._target_bale, a)
	assert_true(bool(a.get_meta("reserved", false)))
	# Patch grabs it and sets it down somewhere else (not the scale): reservation must be gone.
	a.set_carried(true)
	a.set_meta("reserved", true)  # even if something re-reserved it in between
	h._think_haul()
	assert_false(bool(a.get_meta("reserved", false)), "hauler gave up its target and released it")
	a.set_carried(false)
	h._rescan_t = 0.0
	var other := _bot(f, "haulbug", "H2", Vector3(-8, 0, 8))
	assert_eq(other._find_bale(), a, "the bale can be fetched again")


# --- #16 Auto-baler save during a press -----------------------------------------------------

func test_auto_baler_saves_junk_mid_press_and_mid_eject() -> void:
	for id: String in ["conveyor", "auto_baler", "recycler"]:
		Research.grant(id)
	var s := _stations()
	_rich()
	assert_true(s.build("auto_baler"))
	var b: AutoBaler = s.baler
	b.accept({"metal": 9.0, "glass": 6.0}, Vector3.ZERO)
	b._start_press()
	b._press(b._dur * 0.2)
	assert_null(b._bale, "no bale yet early in the stroke")
	var d: Dictionary = b.to_dict()
	assert_almost_eq(float(d["fill"]), 15.0, 0.001, "taken junk saved back into the store")
	var tot: float = 0.0
	for k: String in d["store"]:
		tot += float(d["store"][k])
	assert_almost_eq(tot, 15.0, 0.001)
	assert_almost_eq(b.store_fill, 15.0 - b.bale_cap(), 0.001, "live store unchanged")
	b._press(b._dur * 0.3)
	assert_not_null(b._bale)
	assert_almost_eq(float(b.to_dict()["fill"]), 15.0 - b.bale_cap(), 0.001, "bale exists: no double count")
	assert_eq(b.held_dicts().size(), 1)
	b._press(b._dur * 0.4)  # past 0.86: eject tween running
	assert_null(b._bale)
	assert_eq(b.held_dicts().size(), 1, "the ejecting bale is still saved")


# --- #17 Recalled haulers -------------------------------------------------------------------

func test_recalled_hauler_delivers_without_collecting() -> void:
	var w := _make()
	var f := _fleet(w)
	var h := _bot(f, "haulbug", "H", Vector3(9, 0, 9))
	var carried := JunkCube.create(BigNum.from_float(10.0), {"fill": 0.8})
	h.add_child(carried)
	carried.set_carried(true)
	h.carried.append(carried)
	var loose := JunkCube.create(BigNum.from_float(10.0), {"fill": 0.8})
	w.get_node("Cubes").add_child(loose)
	loose.global_position = Vector3(9.5, 0.3, 9.5)
	f.set_mode("haul", false, "recall")
	assert_eq(f.mode_of(h), "recall")
	var m: Vector3 = h._think(0.016)
	assert_null(h._target_bale, "no new bale fetched while recalled")
	assert_false(bool(loose.get_meta("reserved", false)))
	assert_gt(m.length(), 0.0, "heading for the drop-off")


# --- #5 / #18 Research gates -----------------------------------------------------------------

func test_stations_require_research_but_built_ones_stay() -> void:
	var s := _stations()
	_rich()
	GameState.world["hub_level"] = 5
	for id: String in ["conveyor", "auto_baler", "recycler"]:
		assert_string_starts_with(s.block_reason(id), "Requires research")
		assert_false(s.build(id))
	Research.grant("conveyor")
	assert_eq(s.block_reason("conveyor"), "")
	assert_true(s.build("conveyor"))
	# An older save with a station already built but no research: still "Built.", never locked.
	GameState.flags = {}
	assert_eq(s.block_reason("conveyor"), "Built.")


func test_build_block_reason_shows_research_lock() -> void:
	var f := _fleet(null)
	GameState.world["hub_level"] = 1
	GameState.currencies["cubes"] = BigNum.from_float(1.0e9)
	for k: int in 8:
		GameState.parts.append({"type": k, "rarity": 0})
	var why: String = f.build_block_reason("drip")
	assert_string_starts_with(why, "Locked")
	assert_false(f.can_build("drip"))
	Research.grant(Research.robot_requirement("drip"))
	assert_eq(f.build_block_reason("drip"), "")
	assert_true(f.can_build("drip"))


# --- #7 Control Core choice ----------------------------------------------------------------

func test_scoopie_build_spares_the_tier_up_core() -> void:
	var f := _fleet(null)
	var core: int = Fleet.part_index("core")
	var need: int = int(Economy.robot_tiers[1]["requires_core_rarity"])
	GameState.parts.append({"type": core, "rarity": need})  # the Mk II core
	GameState.parts.append({"type": core, "rarity": 0})
	var pick: Dictionary = {}
	for r: Dictionary in f.recipe_status("scoopie"):
		if r["part_id"] == "core":
			pick = r
	assert_eq(int(pick["rarity"]), 0, "the spare core goes into the robot")
	# Only tier-up cores left: use the weakest one.
	GameState.parts = [{"type": core, "rarity": need + 1}, {"type": core, "rarity": need}]
	for r: Dictionary in f.recipe_status("scoopie"):
		if r["part_id"] == "core":
			pick = r
	assert_eq(int(pick["rarity"]), need)
	# Non-core slots still take the best part.
	var chassis: int = Fleet.part_index("chassis")
	GameState.parts = [{"type": chassis, "rarity": 0}, {"type": chassis, "rarity": 3}]
	for r: Dictionary in f.recipe_status("scoopie"):
		if r["part_id"] == "chassis":
			pick = r
	assert_eq(int(pick["rarity"]), 3)


# --- #19 Multibot crew caps -----------------------------------------------------------------

func test_multibots_respect_crew_caps() -> void:
	var f := _fleet(null)
	GameState.world["hub_level"] = 1
	var cap: int = f.crew_cap()
	for i: int in cap:
		var r := Robot.new()
		r.type_id = "multibot"
		r.robot_name = "M%d" % i
		r.job = "clean"
		f.add_child(r)
	var r2 := Robot.new()
	r2.type_id = "seedling"
	r2.robot_name = "Seed"
	f.add_child(r2)
	assert_eq(f.crew_size("clean"), cap)
	for i: int in cap:
		f.move_job("clean", "plant")
	assert_eq(f.crew_size("plant"), cap, "plant crew stops at the cap")
	assert_eq(f.crew_size("clean"), 1)
	assert_false(f.move_job("clean", "plant"), "plant crew full")
	f.apply_preset(0.0, 1.0)  # everything to planting
	assert_lte(f.crew_size("plant"), cap)
	assert_eq(f.crew_size("clean") + f.crew_size("plant") + f.crew_size("water"), cap + 1)
	# Building: a multibot may join any crew with room, and starts there.
	Research.grant(Research.robot_requirement("multibot"))
	assert_eq(f.join_crew("multibot"), "clean")
	assert_ne(f.build_block_reason("multibot").substr(0, 10), "Crew full ")


# --- #20 Saved bale info --------------------------------------------------------------------

func test_bale_roundtrip_keeps_dominant_and_volume() -> void:
	var c := _bale(0.5)
	c.info["volume"] = 7.5
	var d: Dictionary = JSON.parse_string(JSON.stringify(c.to_dict()))
	var c2: JunkCube = JunkCube.from_dict(d)
	assert_eq(str(c2.info["dominant"]), "metal")
	assert_almost_eq(float(c2.info["volume"]), 7.5, 0.001)
	d.erase("volume")
	d.erase("dominant")
	var c3: JunkCube = JunkCube.from_dict(d)
	assert_false(c3.info.has("volume"), "old saves fall back to fill * 12 in the recycler")
	assert_eq(str(c3.info.get("dominant", "")), "")
	c2.free()
	c3.free()


# --- #36 Idle rescan back-off ------------------------------------------------------------------

func test_idle_drip_backs_off_before_rescanning() -> void:
	var w := _make()
	var f := _fleet(w)
	var d := _bot(f, "drip", "D")
	d.water = d.stat("tank")
	d._think(0.016)
	assert_true(d._idling, "nothing planted: idle")
	assert_gt(d._rescan_t, 0.0, "back-off armed")
	var t: float = d._rescan_t
	d._think(0.016)
	assert_eq(d._rescan_t, t, "no rescan while backing off (timer only ticks in physics)")
	d.reset_targets()
	assert_eq(d._rescan_t, 0.0, "zone / order changes rescan at once")


func test_idle_hauler_backs_off() -> void:
	var w := _make()
	var f := _fleet(w)
	var h := _bot(f, "haulbug", "H")
	h._think(0.016)
	assert_gt(h._rescan_t, 0.0)
	var a := JunkCube.create(BigNum.from_float(10.0), {"fill": 0.8})
	w.get_node("Cubes").add_child(a)
	a.global_position = Vector3(-8, 0.3, 8)  # off the scale pad
	h._think(0.016)
	assert_null(h._target_bale, "waits for the back-off")
	h._rescan_t = 0.0
	h._think(0.016)
	assert_eq(h._target_bale, a)


# --- #3 / #28 Command view controller ----------------------------------------------------------

func test_command_view_buttons_have_a_visible_focus_style() -> void:
	var cv := CommandView.new()
	add_child_autofree(cv)
	var b := Button.new()
	add_child_autofree(b)
	cv._style_button(b, UITheme.GOLD, false)
	var sb: StyleBox = b.get_theme_stylebox("focus")
	assert_true(sb is StyleBoxFlat, "amber focus box, not StyleBoxEmpty")
	assert_gt((sb as StyleBoxFlat).border_width_top, 0)
	assert_eq(cv._focus_id(cv._mode_row.get_child(0)), ["mode", "priority"])
