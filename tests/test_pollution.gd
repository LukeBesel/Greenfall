extends GutTest
## Pollution kinds (systems/pollution.gd): where each kind spawns, the tool it needs, what it pays
## and the events it sends; the hex ledger with several kinds on it; robots; saving. The first
## planet's five kinds come from its table, and the dummy planet's table holds a kind no shipped
## planet has, to prove a new kind is data only.

const FIRST: StringName = &"verdance"
const DUMMY: StringName = &"testworld"
const PLANETS: Array[StringName] = [FIRST, DUMMY]
const LEVEL: int = 6
const SEED: int = 4471
const WATER_CELLS: int = 12

var _saved: Dictionary = {}
var _nodes: Array[Node] = []
var _events: Array[Array] = []
var def: PlanetDefinition
var grid: SphereGrid
var cells: SphereCells
var field: SphereField
var site_cells := PackedInt32Array()
var pol: Pollution
var rigs: Rigs


func before_all() -> void:
	Planets.register_dir(DistrictFixture.FIXTURE_PLANETS)


func after_all() -> void:
	Planets.unregister(DUMMY)


func before_each() -> void:
	_saved = {"currencies": GameState.currencies, "flags": GameState.flags, "upgrades": GameState.upgrades}
	GameState.currencies = {}
	GameState.flags = {}
	GameState.upgrades = {}
	_events.clear()
	EventBus.pollution_cleared.connect(_on_cleared)


func after_each() -> void:
	EventBus.pollution_cleared.disconnect(_on_cleared)
	for n: Node in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	pol = null
	rigs = null
	GameState.currencies = _saved["currencies"]
	GameState.flags = _saved["flags"]
	GameState.upgrades = _saved["upgrades"]


func _on_cleared(kind: String, amount: float, by_player: bool) -> void:
	_events.append([kind, amount, by_player])


## A globe of junk with the planet's sites on it. `lakes`: turn a few hexes of that district into
## water before the kinds are worked out.
func _world(planet_id: StringName, lakes: String = "") -> void:
	def = Planets.by_id(planet_id)
	grid = SphereGrid.cached(LEVEL)
	grid.radius_m = SphereGrid.radius_for(LEVEL, 10.0)
	cells = SphereCells.new(grid.cell_count())
	cells.junk.fill(1.0)
	site_cells = DistrictFixture.face_centre_cells(grid, def.hub_count)
	if lakes != "":
		var list: PackedInt32Array = _district_cells(lakes)
		for i: int in WATER_CELLS:
			cells.state[list[list.size() - 1 - i]] = PlanetData.State.WATER
	field = SphereField.new(grid, SphereTerrain.new(grid, SEED), cells, SEED)
	field.worth = HexWorth.for_planet(def, grid, site_cells)
	pol = _pollution({})


## Fits rig modules (the tools the kinds are gated by since M3-08).
func _fit(ids: Array[String]) -> void:
	for id: String in ids:
		rigs.grant(id)
	pol.refresh_gates()


func _pollution(saved: Dictionary) -> Pollution:
	var p := Pollution.new()
	_nodes.append(p)
	p.setup(def, grid, cells, field, site_cells, saved)
	if rigs == null or not is_instance_valid(rigs):
		rigs = Rigs.new()
		_nodes.append(rigs)
		rigs.setup(def, {})
	p.set_rigs(rigs)
	return p


func _district_cells(id: String) -> PackedInt32Array:
	for spec: Dictionary in Districts.specs_for(def):
		if str(spec["id"]) == id:
			return Districts.region_cells(grid, site_cells[int(spec["site"])], int(spec["rings"]))
	return PackedInt32Array()


## The first hex of a district that holds exactly these kinds.
func _hex_with(district: String, kinds: Array[String]) -> int:
	for c: int in _district_cells(district):
		var here: Array[String] = pol.kinds_left(c)
		here.sort()
		var want: Array[String] = kinds.duplicate()
		want.sort()
		if here == want:
			return c
	return -1


## Scoops every piece Lumi may take, then works the held kinds with `tool`, the way Lumi cleans a
## hex by hand. Returns the cubes her loads were worth.
func _hand_clean(cell: int, tool: String = "") -> float:
	field.materialize(cell)
	var cubes: float = 0.0
	for pid: int in field.pieces_in(cell):
		if field.piece_alive[pid] == 0 or not field.piece_open(pid):
			continue
		cubes += field.worth.share(cell, field.piece_vol[pid], field.hex_left[cell], field.hex_total[cell], field.clean_threshold) * pol.piece_yield(pid)
		pol.piece_taken(pid, field.piece_vol[pid])
		field.remove_piece(pid)
		cells.set_junk(cell, 0.0 if field.hex_clean[cell] == 1 else 1.0 - field.removed_fraction(cell))
	for _i: int in 400:
		var take: Dictionary = pol.hand_work(tool, cell, 1.0, 1000.0) if tool != "" else {}
		if take.is_empty() or take.has("blocked"):
			break
		cubes += float(take["cubes"])
	return cubes


# --- Data -------------------------------------------------------------------------------------

func test_every_kind_has_its_rules(planet_id: StringName = use_parameters(PLANETS)) -> void:
	_world(planet_id)
	var ids: Array[String] = pol.ids()
	assert_gt(ids.size(), 1, "%s has kinds beside the base kind" % planet_id)
	assert_eq(ids[0], pol.base_id(), "the base kind comes first")
	assert_eq(str(pol.kind(ids[0])["work"]), Pollution.WORK_PIECES)
	for id: String in ids:
		var kd: Dictionary = pol.kind(id)
		assert_ne(str(kd.get("name", "")), "", "%s has a name" % id)
		assert_true(kd.has("yield") and (kd["yield"] as Dictionary).has("cubes"), "%s has a payout weight" % id)
		assert_false((kd.get("robot_roles", []) as Array).is_empty(), "%s names the robots that work it" % id)
		if id == ids[0]:
			continue
		assert_true(str(kd["work"]) in [Pollution.WORK_HEAVY, Pollution.WORK_FLOAT, Pollution.WORK_HELD], "%s: a known way of working it" % id)
		assert_false((kd.get("gate", {}) as Dictionary).is_empty(), "%s has a tool gate" % id)
		assert_true(kd.has("spawn"), "%s has a spawn rule" % id)
		assert_ne(str(kd.get("hint", "")), "", "%s says how it is worked" % id)
		assert_ne(str(kd.get("prompt", "")), "", "%s says what it needs" % id)
		assert_gte(float(kd["share"]), Pollution.MIN_SHARE, "%s cannot sweep away untouched" % id)
		if str(kd["work"]) == Pollution.WORK_HELD:
			assert_true(str(kd.get("tool", "")) in ["water", "plant"], "%s names Lumi's tool" % id)


func test_the_first_planet_has_the_five_kinds() -> void:
	_world(FIRST)
	assert_eq(pol.ids(), ["litter", "wrecks", "slick", "smog", "blight"] as Array[String])


# --- Spawn ------------------------------------------------------------------------------------

func test_each_city_holds_the_kinds_it_lists_and_no_other() -> void:
	_world(FIRST, "kettle_bay")
	for spec: Dictionary in Districts.specs_for(def):
		var id: String = str(spec["id"])
		var count: Dictionary = pol.census(id)
		for kind: String in pol.ids():
			if kind in (spec["pollution"] as Array) and (kind != "slick" or id == "kettle_bay"):
				assert_gt(int(count.get(kind, 0)), 0, "%s holds %s" % [id, kind])
			elif not kind in (spec["pollution"] as Array):
				assert_eq(int(count.get(kind, 0)), 0, "%s holds no %s" % [id, kind])
	assert_eq(pol.census("old_town"), {"litter": Districts.hexes_for_rings(6)}, "the first city is litter and nothing else")
	assert_eq(int(pol.census("kettle_bay")["slick"]), WATER_CELLS, "every lake hex of a slick city is slick")


func test_a_kind_spawns_at_about_its_density_and_keeps_off_the_first_rings() -> void:
	_world(FIRST)
	for pair: Array in [["scrapyard", "wrecks"], ["highreach", "smog"], ["lowmeadow", "blight"]]:
		var spawn: Dictionary = pol.kind(pair[1])["spawn"]
		var list: PackedInt32Array = _district_cells(pair[0])
		var share: float = float(pol.census(pair[0])[pair[1]]) / float(list.size())
		assert_between(share, float(spawn["density"]) * 0.5, float(spawn["density"]) * 1.5, "%s in %s" % [pair[1], pair[0]])
		for c: int in grid.cells_around(list[0], int(spawn["min_ring"]) - 1):
			assert_false(pair[1] in pol.kinds_left(c), "%s keeps off ring %d" % [pair[1], int(spawn["min_ring"]) - 1])


func test_the_same_seed_lays_the_same_kinds() -> void:
	_world(FIRST)
	var again: Pollution = _pollution({})
	for c: int in _district_cells("old_capital"):
		assert_eq(again.kinds_at(c), pol.kinds_at(c))


func test_a_hex_can_hold_several_kinds_and_they_share_its_waste() -> void:
	_world(FIRST)
	var c: int = _hex_with("old_capital", ["litter", "wrecks", "smog", "blight"])
	assert_gt(c, -1, "the last city has hexes with four kinds")
	var total: float = 0.0
	for id: String in pol.kinds_left(c):
		total += pol.share_of(c, id)
	assert_almost_eq(total, 1.0, 0.0001, "the kinds' shares are the whole hex")
	assert_almost_eq(cells.hold[c], pol.share_of(c, "smog") + pol.share_of(c, "blight"), 0.0001, "the held kinds' share is out of a scoop's reach")


# --- The first city is untouched -------------------------------------------------------------

func test_a_litter_hex_is_laid_out_as_before_the_kinds_existed() -> void:
	_world(FIRST)
	var c: int = _district_cells("old_town")[40]
	var plain := SphereField.new(grid, SphereTerrain.new(grid, SEED), cells, SEED)
	plain.worth = field.worth
	var a: PackedInt32Array = field.materialize(c)
	var b: PackedInt32Array = plain.materialize(c)
	assert_eq(a.size(), b.size(), "same pieces")
	assert_eq(field.piece_model.slice(a[0], a[-1] + 1), plain.piece_model.slice(b[0], b[-1] + 1), "same models")
	assert_almost_eq(field.hex_left[c], plain.hex_left[c], 0.001)
	assert_eq(cells.floor_of(c), 0.0)
	assert_almost_eq(_hand_clean(c), field.worth.cubes(c), field.worth.cubes(c) * 0.001, "a litter hex pays its cube value")
	assert_false(cells.is_dirty(c))


# --- Wrecks -----------------------------------------------------------------------------------

func test_wrecks_are_heavy_pieces_gated_by_the_cutter() -> void:
	_world(FIRST)
	var c: int = _hex_with("scrapyard", ["litter", "wrecks"])
	field.materialize(c)
	var heavy_vol: float = 0.0
	var heavy: int = 0
	for pid: int in field.pieces_in(c):
		if pol.ids()[field.piece_kind[pid]] == "wrecks":
			heavy += 1
			heavy_vol += field.piece_vol[pid]
			assert_eq(int(field.piece_size[pid]), Pace.SIZE_LARGE, "a wreck is in the large size class")
	assert_eq(heavy, int(pol.kind("wrecks")["spawn"]["pieces"]))
	assert_almost_eq(heavy_vol, pol.share_of(c, "wrecks") * field.worth.work(c), 0.01, "wrecks hold their share of the hex")
	assert_almost_eq(field.hex_left[c], field.worth.work(c), 0.01, "the hex still holds its city's work")
	GameState.upgrades["lift_strength"] = 2
	pol.refresh_gates()
	assert_false(pol.can_work("wrecks"), "Lift Strength alone does not open wrecks any more")
	assert_true(pol.hex_blocked(c))
	assert_eq(pol.hex_note(c), str(pol.kind("wrecks")["prompt"]), "the readout says what the wrecks need")
	_hand_clean(c)
	assert_true(cells.is_dirty(c), "litter alone does not clean a wreck hex")
	assert_eq(pol.kinds_left(c), ["wrecks"] as Array[String])
	GameState.upgrades["lift_strength"] = 0
	_fit(["plate_cutter"])
	assert_true(pol.can_work("wrecks"))
	assert_eq(pol.hex_note(c), str(pol.kind("wrecks")["hint"]))
	_hand_clean(c)
	assert_false(cells.is_dirty(c), "with the Plate Cutter fitted the hex comes clean")


func test_a_wreck_hex_pays_its_citys_hex_value() -> void:
	_world(FIRST)
	_fit(["plate_cutter"])
	var c: int = _hex_with("scrapyard", ["litter", "wrecks"])
	assert_almost_eq(_hand_clean(c), field.worth.cubes(c), field.worth.cubes(c) * 0.03)


# --- Slick ------------------------------------------------------------------------------------

func test_slick_is_the_lake_hexes_and_needs_the_skirt() -> void:
	_world(FIRST, "kettle_bay")
	var list: PackedInt32Array = _district_cells("kettle_bay")
	var c: int = list[list.size() - 1]
	assert_eq(pol.kinds_left(c), ["slick"] as Array[String])
	assert_eq(pol.share_of(c, "slick"), 1.0)
	assert_false(pol.can_work("slick"))
	assert_eq(pol.hex_note(c), str(pol.kind("slick")["prompt"]))
	GameState.upgrades["hover_jets"] = 1
	pol.refresh_gates()
	assert_false(pol.can_work("slick"), "Hover Jets alone do not skim")
	field.materialize(c)
	var pid: int = field.pieces_in(c)[0]
	assert_false(field.piece_open(pid), "what floats on a slick hex cannot be scooped without the skirt")
	_fit(["skim_skirt"])
	assert_true(pol.can_work("slick"))
	assert_true(field.piece_open(pid))
	assert_true("skim" in (pol.kind("slick")["robot_roles"] as Array))
	pol.piece_taken(pid, 1.0)
	assert_eq(_events[-1], ["slick", 1.0, true], "skimming a lake hex counts as slick")


# --- Smog and blight ---------------------------------------------------------------------------

func test_smog_keeps_a_hex_dirty_until_it_is_misted() -> void:
	_world(FIRST)
	var c: int = _hex_with("highreach", ["litter", "smog"])
	var share: float = pol.share_of(c, "smog")
	assert_almost_eq(cells.floor_of(c), share, 0.0001)
	_hand_clean(c)
	assert_true(cells.is_dirty(c), "scooping cannot clear smog")
	assert_false(cells.workable(c), "and nothing is left for a scoop")
	assert_eq(pol.kinds_left(c), ["smog"] as Array[String])
	assert_eq(pol.hand_work("plant", c, 1.0, 100.0), {}, "the planter does nothing to smog")
	assert_true(pol.hand_work("water", c, 1.0, 100.0).has("blocked"), "no watering can yet")
	GameState.flags["seeds_unlocked"] = true
	assert_true(pol.hand_work("water", c, 1.0, 100.0).has("blocked"), "the can alone does not scrub smog")
	_fit(["mist_scrubber"])
	var chest: float = Economy.stat("capacity")
	rigs.unfit("chest")
	assert_lt(chest, Economy.stat("capacity"), "the scrubber's drum takes chest room")
	_fit(["mist_scrubber"])
	var take: Dictionary = pol.hand_work("water", c, 1.0, 100.0)
	assert_eq(str(take["kind"]), "smog")
	assert_almost_eq(float(take["vol"]), 0.9 * Pace.pulse_volume() * maxf(Economy.stat("scoop_rate"), 0.5), 0.001, "one second of misting at the hand factor")
	assert_gt(float(take["tool_use"]), 0.0, "misting uses water")
	assert_true(Economy.junk_types.has(str(take["type_id"])), "what she takes goes in the chest as a known material")
	assert_eq(_events[-1], ["smog", float(take["vol"]), true])
	assert_true(pol.hand_work("water", c, 1.0, 0.0).has("blocked"), "a full chest takes nothing")
	_hand_clean(c, "water")
	assert_false(cells.is_dirty(c), "misted clean")
	assert_eq(cells.floor_of(c), 0.0)
	assert_eq(pol.kinds_left(c), [] as Array[String])
	assert_eq(field.hex_clean[c], 1)


func test_a_smog_hex_pays_its_citys_hex_value() -> void:
	_world(FIRST)
	GameState.flags["seeds_unlocked"] = true
	_fit(["mist_scrubber"])
	var c: int = _hex_with("highreach", ["litter", "smog"])
	assert_almost_eq(_hand_clean(c, "water"), field.worth.cubes(c), field.worth.cubes(c) * 0.03)


func test_blight_is_cleared_with_cleansing_plants_that_cost_seeds() -> void:
	_world(FIRST)
	GameState.flags["seeds_unlocked"] = true
	GameState.add_currency("seeds", BigNum.from_float(1.0))
	var first: int = _hex_with("lowmeadow", ["litter", "blight"])
	assert_true(pol.hand_work("plant", first, 1.0, 100.0).has("blocked"), "the planter alone does not treat blight")
	GameState.spend("seeds", BigNum.from_float(1.0))
	_fit(["soil_doser"])
	var done: int = 0
	var paid: float = 0.0
	var worth: float = 0.0
	for c: int in _district_cells("lowmeadow"):
		if done == 4:
			break
		var here: Array[String] = pol.kinds_left(c)
		here.sort()
		var mixed: Array[String] = ["blight", "litter"]
		if here != mixed:
			continue
		if done == 0:
			assert_true(pol.hand_work("plant", c, 1.0, 100.0).has("blocked"), "no seeds, no cleansing plants")
			GameState.add_currency("seeds", BigNum.from_float(3.0))
		paid += _hand_clean(c, "plant")
		worth += field.worth.cubes(c)
		assert_false(cells.is_dirty(c), "planted clean")
		done += 1
	assert_eq(done, 4)
	# Four hexes at 0.35 seeds a hex, less the last 5% of each that sweeps away: 1.17, one whole seed.
	assert_almost_eq(GameState.get_currency("seeds").to_float(), 2.0, 0.001)
	assert_almost_eq(paid, worth, worth * 0.03, "blight hexes pay their city's hex value")


# --- Robots -----------------------------------------------------------------------------------

func test_cleaner_robots_cannot_take_held_waste() -> void:
	_world(FIRST)
	var c: int = _hex_with("highreach", ["litter", "smog"])
	SphereOffline.write_cell(cells, field, c, 0.0)
	assert_true(cells.is_dirty(c), "a cleaner leaves the smog")
	assert_almost_eq(cells.junk[c], pol.share_of(c, "smog"), 0.0001)
	assert_false(cells.workable(c))
	assert_eq(cells.state[c], PlanetData.State.JUNK)
	var region := PackedInt32Array([c])
	assert_eq(SphereOffline.units_left(cells, region), 0.0, "and the offline crew sees no work there")


func test_a_released_hex_cleans_outright_and_holds_nothing_after() -> void:
	_world(FIRST)
	var c: int = _hex_with("highreach", ["litter", "smog"])
	cells.release_hold(c)
	SphereOffline.write_cell(cells, field, c, 0.0)
	assert_false(cells.is_dirty(c), "the dev stage flag cleans a smog hex")
	assert_eq(pol.kinds_left(c), [] as Array[String])
	assert_eq(pol.held_left(c, "smog"), 0.0)


func test_the_watering_robot_mists_smog_and_the_planter_sets_cleansing_plants() -> void:
	_world(FIRST)
	GameState.add_currency("seeds", BigNum.from_float(5.0))
	for pair: Array in [["highreach", "smog", "water", "plant"], ["lowmeadow", "blight", "plant", "water"]]:
		var c: int = _hex_with(pair[0], ["litter", pair[1]])
		assert_true(pol.robot_wants(pair[2], c), "%s is work for a %s robot" % [pair[1], pair[2]])
		assert_false(pol.robot_wants(pair[3], c))
		assert_false(pol.robot_wants("clean", c))
		SphereOffline.write_cell(cells, field, c, 0.0)
		var before: float = pol.held_left(c, pair[1])
		assert_false(pol.robot_work(pair[2], c, true), "one action does not finish the hex")
		assert_lt(pol.held_left(c, pair[1]), before)
		var cleaned: bool = false
		for _i: int in 200:
			if pol.robot_work(pair[2], c, true):
				cleaned = true
				break
		assert_true(cleaned, "the robot clears the %s" % pair[1])
		assert_false(cells.is_dirty(c))
		assert_false(pol.robot_wants(pair[2], c))
	_events.clear()
	pol.flush_robot_events()
	assert_eq(_events.size(), 2, "robot work arrives as one event per kind")
	for e: Array in _events:
		assert_false(e[2], "not by the player")
	assert_between(float(pol.save_state()["debt"]["seeds"]), 0.2, 0.36, "the planting robot's cleansing plants are owed in seeds")


func test_a_robot_scoop_is_counted_for_the_kinds_of_the_hex() -> void:
	_world(FIRST)
	var c: int = _hex_with("scrapyard", ["litter", "wrecks"])
	pol.robot_scooped(c, 0.5)
	pol.flush_robot_events()
	var by_kind: Dictionary = {}
	for e: Array in _events:
		by_kind[e[0]] = e[1]
	assert_almost_eq(float(by_kind["wrecks"]), 0.5 * field.worth.work(c) * pol.share_of(c, "wrecks"), 0.01)
	assert_almost_eq(float(by_kind["litter"]) + float(by_kind["wrecks"]), 0.5 * field.worth.work(c), 0.01)


# --- Saving -----------------------------------------------------------------------------------

func test_part_cleared_kinds_round_trip_and_old_saves_load() -> void:
	_world(FIRST)
	GameState.flags["seeds_unlocked"] = true
	GameState.add_currency("seeds", BigNum.from_float(2.0))
	_fit(["mist_scrubber", "soil_doser"])
	var smog: int = _hex_with("highreach", ["litter", "smog"])
	var blight: int = _hex_with("lowmeadow", ["litter", "blight"])
	pol.hand_work("water", smog, 2.0, 1000.0)
	pol.hand_work("plant", blight, 2.0, 1000.0)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(pol.save_state()))
	var cells_saved: Dictionary = cells.to_dict()
	var left_smog: float = pol.held_left(smog, "smog")
	var left_blight: float = pol.held_left(blight, "blight")
	assert_between(left_smog, 0.01, 0.99)
	# A load: fresh cells from the save, a fresh field, the kinds restored.
	cells = SphereCells.new(grid.cell_count())
	cells.apply_dict(cells_saved)
	field = SphereField.new(grid, SphereTerrain.new(grid, SEED), cells, SEED)
	field.worth = HexWorth.for_planet(def, grid, site_cells)
	var loaded: Pollution = _pollution(saved)
	assert_almost_eq(loaded.held_left(smog, "smog"), left_smog, 0.001)
	assert_almost_eq(loaded.held_left(blight, "blight"), left_blight, 0.001)
	assert_almost_eq(cells.floor_of(smog), left_smog * loaded.share_of(smog, "smog"), 0.001)
	assert_eq(loaded.save_state()["held"], saved["held"], "saving again gives the same state")
	assert_almost_eq(float(loaded.save_state()["debt"]["seeds"]), float(saved["debt"]["seeds"]), 0.0001)
	# A save from before the kinds existed: no section. Dirty hexes hold their kinds in full, hexes
	# already cleaned stay clean, and a hex with less waste left than its kinds keeps what it has.
	cells.set_junk(blight, 0.0)
	cells.set_state(blight, PlanetData.State.CLEAN)
	var low: int = _hex_with("old_capital", ["litter", "smog"])
	cells.set_junk(low, 0.1)
	var old: Pollution = _pollution({})
	assert_eq(old.held_left(smog, "smog"), 1.0)
	assert_eq(old.kinds_left(blight), [] as Array[String])
	assert_eq(cells.floor_of(blight), 0.0)
	assert_almost_eq(cells.floor_of(low), 0.1, 0.0001)


# --- A sixth kind from data alone -------------------------------------------------------------

func test_the_dummy_planets_own_kind_works_from_its_table_alone() -> void:
	_world(DUMMY)
	assert_eq(pol.ids(), ["dross", "spores"] as Array[String])
	var kd: Dictionary = pol.kind("spores")
	var region: PackedInt32Array = Districts.region_cells(grid, site_cells[0], Districts.FALLBACK_RINGS)
	var count: Dictionary = pol.census(String(DUMMY))
	assert_between(float(count["spores"]) / float(region.size()), 0.3, 0.6, "spores on about half the hexes")
	for c: int in grid.cells_around(site_cells[0], int(kd["spawn"]["min_ring"]) - 1):
		assert_eq(pol.kinds_left(c), ["dross"] as Array[String], "none by the site")
	var hex: int = -1
	for c: int in region:
		if "spores" in pol.kinds_left(c):
			hex = c
			break
	assert_almost_eq(cells.floor_of(hex), float(kd["spawn"]["share"]), 0.0001)
	assert_eq(pol.hex_note(hex), str(kd["prompt"]))
	_hand_clean(hex, "water")
	assert_true(cells.is_dirty(hex), "gated: the flag is not set")
	GameState.flags[str(kd["gate"]["flag"])] = true
	assert_eq(pol.hex_note(hex), str(kd["hint"]))
	assert_true(pol.hand_work("water", hex, 1.0, 100.0).has("blocked"), "its cost is in seeds")
	GameState.add_currency("seeds", BigNum.from_float(2.0))
	var take: Dictionary = pol.hand_work("water", hex, 1.0, 100.0)
	assert_almost_eq(float(take["vol"]), float(kd["hand_factor"]) * Pace.pulse_volume() * maxf(Economy.stat("scoop_rate"), 0.5), 0.001)
	assert_almost_eq(float(take["tool_use"]), float(take["vol"]) * float(kd["tool_use_per_unit"]), 0.0001)
	# Spores weigh double in the hex's value: a unit of them pays twice a unit of dross.
	var per_unit: float = float(take["cubes"]) / float(take["vol"])
	var mean: float = 0.7 + 0.3 * float(kd["yield"]["cubes"])
	assert_almost_eq(per_unit, field.worth.cubes(hex) / (field.worth.work(hex) * 0.95) * float(kd["yield"]["cubes"]) / mean, 0.001)
	_hand_clean(hex, "water")
	assert_false(cells.is_dirty(hex), "clean once every kind on it is cleared")
	var other: int = -1
	for c: int in region:
		if "spores" in pol.kinds_left(c):
			other = c
			break
	assert_true(pol.robot_wants("water", other))
	pol.robot_work("water", other, false)
	assert_almost_eq(pol.held_left(other, "spores"), 1.0 - float(kd["robot_units"]) / (float(kd["spawn"]["share"]) * field.worth.work(other)), 0.001)


func test_a_planet_without_a_kinds_table_has_one_implicit_kind() -> void:
	def = Planets.by_id(&"ochre")
	grid = SphereGrid.cached(LEVEL)
	grid.radius_m = SphereGrid.radius_for(LEVEL, 10.0)
	cells = SphereCells.new(grid.cell_count())
	site_cells = DistrictFixture.face_centre_cells(grid, def.hub_count)
	field = SphereField.new(grid, SphereTerrain.new(grid, SEED), cells, SEED)
	var bare: PlanetDefinition = def.duplicate()
	bare.tables = def.tables.duplicate()
	bare.tables.erase(Pollution.TABLE)
	var none := Pollution.new()
	_nodes.append(none)
	none.setup(bare, grid, cells, field, site_cells)
	assert_eq(none.ids(), [Pollution.IMPLICIT_KIND] as Array[String])
	assert_eq(none.kinds_left(site_cells[0]), [Pollution.IMPLICIT_KIND] as Array[String])
	assert_true(cells.hold.is_empty(), "nothing is held on a planet with no held kind")
