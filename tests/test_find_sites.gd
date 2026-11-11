extends GutTest
## Wrecks and buried finds standing in the world (task M3-15; design spec section 13;
## systems/find_sites.gd over systems/finds.gd). A wreck of the planet's design is cleared of its
## junk by hand, then salvaged; clearing its hex gives nothing. At most one tease wreck of a later
## design stands on a planet, says its line and can never be salvaged. A buried find lies in the
## cleared soil until Lumi digs it up, and the detector hears it. The found piece is a moment on
## Lumi: light, sound, the piece named, the way to the Locker.

const FIRST: StringName = &"verdance"
const SEED: int = 4471
const TEASE_LINE: String = "Too far gone. Maybe somewhere else."

var _flags: Dictionary
var _stats: Dictionary
var _global: Dictionary
var _orbit: Dictionary
var _planet: StringName
var _fx: DistrictFixture
var _finds: Finds
var _sites: FindSites
var _lumi: Node3D
var _ia: Interactables
var _found: Array = []
var _toasts: Array[String] = []


func before_all() -> void:
	Planets.register_dir(DistrictFixture.FIXTURE_PLANETS)


func before_each() -> void:
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)
	_global = GameState.global.duplicate(true)
	_orbit = GameState.orbit.duplicate(true)
	_planet = Planets.current_id()
	GameState.flags = {}
	GameState.stats = {}
	GameState.global = {}
	Looks.dev_all = false
	_found.clear()
	_toasts.clear()
	EventBus.piece_found.connect(_on_piece_found)
	EventBus.toast.connect(_on_toast)


func after_each() -> void:
	EventBus.piece_found.disconnect(_on_piece_found)
	EventBus.toast.disconnect(_on_toast)
	if _fx:
		_fx.free_systems()
	_fx = null
	_finds = null
	_sites = null
	GameState.flags = _flags
	GameState.stats = _stats
	GameState.global = _global
	GameState.orbit = _orbit
	Planets.set_current(_planet)


func _on_piece_found(piece: String, source: String) -> void:
	_found.append([piece, source])


func _on_toast(text: String, _kind: String) -> void:
	_toasts.append(text)


## The first planet on the fixture globe, its finds, and the world's side of them with a stand-in
## Lumi (no detector: a dig ends at once).
func _world(saved: Dictionary = {}) -> void:
	Planets.set_current(FIRST)
	_fx = DistrictFixture.new(FIRST)
	add_child_autofree(_fx.districts)
	add_child_autofree(_fx.restoration)
	_ia = Interactables.new()
	add_child_autofree(_ia)
	_finds = Finds.new()
	add_child_autofree(_finds)
	_finds.setup(_fx.def, _fx.districts, _fx.cells, _ia)
	_finds.load_state(saved)
	var field := SphereField.new(_fx.grid, SphereTerrain.new(_fx.grid, SEED), _fx.cells, SEED)
	_lumi = Node3D.new()
	add_child_autofree(_lumi)
	_sites = FindSites.new()
	add_child_autofree(_sites)
	_sites.setup(_finds, _fx.districts, field, _ia, func() -> Node3D: return _lumi)


func _first(where: String) -> Dictionary:
	return _finds.entries().filter(func(e: Dictionary) -> bool: return e["where"] == where)[0]


func _clean(cell: int) -> void:
	_fx.set_cell_stage(cell, 1)
	EventBus.hex_cleaned.emit(cell, Vector3.ZERO, BigNum.zero())


## Lumi steps up to a spot and presses use.
func _use_at(at: Vector3) -> bool:
	_lumi.global_position = at
	return _ia.try_use(at + at.normalized().cross(Vector3.UP).normalized() * 0.4)


func _prompt_at(at: Vector3) -> String:
	return _ia.prompt(at + at.normalized().cross(Vector3.UP).normalized() * 0.4)


# --- The table --------------------------------------------------------------------------------

func test_a_planet_has_at_most_one_tease_and_it_is_a_later_design() -> void:
	var def: PlanetDefinition = Planets.by_id(FIRST)
	var teases: Array[Dictionary] = Finds.teases_for(def)
	assert_eq(teases.size(), 1, "one tease on the first planet")
	for t: Dictionary in teases:
		assert_ne(t["design"], Finds.set_for(def), "a tease is of a design this planet does not hand out")
		assert_has(Designs.ids(), t["design"], "and a real design")
		assert_eq(t["line"], TEASE_LINE)
		assert_true(def.table(Finds.TABLE).get("finds", []).filter(func(e: Dictionary) -> bool: return e["id"] == t["id"]).is_empty(),
			"a tease is not a find")
	var wrecks: Array = Finds.entries_for(def).filter(func(e: Dictionary) -> bool: return e["where"] == Finds.WRECK)
	assert_gte(wrecks.size(), 2, "wrecks in some cities")
	var cities: Dictionary = {}
	for e: Dictionary in wrecks:
		cities[e["district"]] = true
	assert_eq(cities.size(), wrecks.size(), "one wreck to a city")


# --- Wrecks -----------------------------------------------------------------------------------

func test_a_wreck_is_the_planets_own_design_worn_by_the_years() -> void:
	_world()
	var id: String = str(_first(Finds.WRECK)["id"])
	assert_not_null(_sites.show_wreck(id))
	var model: WreckModel = _sites.wreck_model(id)
	assert_eq(model.design, "sprout", "the planet's design")
	assert_eq(model.model().preview_variant, "sprout", "built from the hero model itself")
	assert_false(model.ruined)
	assert_true(model.eye_lit(), "one faint eye: the glint that draws Lumi in")
	assert_ne(JSON.stringify(model.style()), JSON.stringify(LumiStyle.preset("sprout")), "worn: its held item is long lost")


func test_clearing_a_wrecks_hex_gives_nothing() -> void:
	_world()
	var e: Dictionary = _first(Finds.WRECK)
	var id: String = str(e["id"])
	_clean(_finds.site_cell(id))
	assert_false(_finds.is_taken(id), "robots or Lumi cleaning the hex do not salvage it")
	assert_eq(_found, [])


func test_a_wreck_is_cleared_by_hand_then_salvaged_once() -> void:
	_world()
	var e: Dictionary = _first(Finds.WRECK)
	var id: String = str(e["id"])
	var at: Vector3 = _sites.show_wreck(id).global_position
	var junk: int = int(_sites.cfg("junk"))
	assert_gt(junk, 0)
	assert_eq(_sites.junk_left(id), junk)
	assert_eq(_prompt_at(at), "E   Pull the junk off the wreck")
	for k: int in junk:
		assert_true(_use_at(at), "pull %d" % (k + 1))
		assert_false(_finds.is_taken(id), "nothing is given while junk lies on it")
	assert_eq(_sites.junk_left(id), 0)
	assert_eq(_prompt_at(at), "E   Salvage the wreck")
	assert_true(_use_at(at))
	assert_true(_finds.is_taken(id))
	for piece: String in e["pieces"]:
		assert_has(_found, [piece, Finds.WRECK], "salvaged: %s" % piece)
	assert_false(_sites.wreck_model(id).eye_lit(), "a stripped wreck is dark")
	assert_eq(_prompt_at(at), "", "a salvaged wreck offers nothing")
	assert_false(_use_at(at))
	assert_eq(_found.size(), (e["pieces"] as Array).size(), "salvaged once")


func test_a_salvaged_wreck_stays_salvaged_after_a_load() -> void:
	_world()
	var e: Dictionary = _first(Finds.WRECK)
	var id: String = str(e["id"])
	var other: String = _sites.wreck_ids()[1]
	_finds.set_cleared(id, int(_sites.cfg("junk")))
	assert_true(_finds.take(id))
	_finds.set_cleared(other, 1)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_finds.save_state()))
	_fx.free_systems()
	_world(saved)
	assert_true(_finds.is_taken(id))
	var at: Vector3 = _sites.show_wreck(id).global_position
	assert_eq(_sites.wreck_model(id).stripped.size(), (e["pieces"] as Array).size(), "its pieces stay off it")
	assert_eq(_sites.junk_left(id), 0)
	assert_eq(_prompt_at(at), "")
	assert_eq(_sites.junk_left(other), int(_sites.cfg("junk")) - 1, "junk already pulled stays pulled")


# --- The tease --------------------------------------------------------------------------------

func test_the_tease_says_its_line_and_can_never_be_salvaged() -> void:
	_world()
	var t: Dictionary = _finds.teases()[0]
	var id: String = str(t["id"])
	assert_true(_sites.is_tease(id))
	assert_ne(_finds.site_cell(id), Finds.NO_CELL, "it stands on a hex of its city")
	var at: Vector3 = _sites.show_wreck(id).global_position
	var model: WreckModel = _sites.wreck_model(id)
	assert_eq(model.design, str(t["design"]))
	assert_true(model.ruined, "further gone than the planet's own wrecks")
	assert_false(model.eye_lit(), "no light: nothing to give")
	assert_eq(_prompt_at(at), "E   Look at the wreck")
	assert_true(_use_at(at))
	assert_has(_toasts, TEASE_LINE)
	assert_eq(_found, [], "it gives nothing")
	assert_false(_finds.take(id), "it cannot be taken")
	assert_false(_finds.is_taken(id))
	assert_eq(_sites.junk_left(id), 0)
	assert_false(_use_at(at), "it does not repeat itself at once")
	assert_false(_sites.nearest_job(at, 10.0).get("id", "") == id, "the bot leaves it alone")


# --- Buried finds -----------------------------------------------------------------------------

func test_a_buried_find_lies_in_the_soil_until_lumi_digs_it_up() -> void:
	_world()
	var e: Dictionary = _first(Finds.BURIED)
	var id: String = str(e["id"])
	var cells: PackedInt32Array = _fx.districts.cells_of(str(e["district"]))
	var at_hex: int = Finds.buried_hex(_fx.def.world_seed, e)
	for i: int in at_hex:
		_clean(cells[i])
	assert_false(_finds.is_taken(id), "not handed over from the hex count")
	assert_true(_finds.surfaced_finds().has(id), "it lies in the cleared soil")
	assert_eq(_finds.surfaced_finds()[id], cells[at_hex - 1], "of the hex that turned it up")
	var node: Node3D = _sites.show_cache(id)
	assert_not_null(node)
	var ping: Dictionary = _sites.nearest_cache(node.global_position + node.global_basis.x * 5.0, 16.0)
	assert_eq(ping.get("id", ""), id, "the detector hears it")
	assert_eq(ping.get("label", ""), "BURIED TIN")
	assert_eq(_sites.nearest_cache(node.global_position, 0.0), {}, "out of range")
	assert_eq(_prompt_at(node.global_position), "E   Dig up the paint tin")
	assert_true(_use_at(node.global_position))
	assert_true(_finds.is_taken(id))
	assert_eq(_found, [[str(e["pieces"][0]), Finds.BURIED]])
	assert_false(_finds.surfaced_finds().has(id))
	assert_eq(_sites.nearest_cache(node.global_position, 16.0), {}, "dug up: silent")


func test_a_lens_chip_pings_as_a_chip() -> void:
	_world()
	var chip: String = ""
	for e: Dictionary in _finds.entries():
		if e["where"] == Finds.BURIED and FindSites.kind_of(str(e["pieces"][0])) == FindProps.CHIP:
			chip = str(e["id"])
			break
	assert_ne(chip, "", "the planet buries a lens chip")
	var cell: int = _fx.districts.cells_of(str(_finds.entry(chip)["district"]))[0]
	assert_true(_finds.surface(chip, cell))
	var node: Node3D = _sites.show_cache(chip)
	assert_eq(_sites.nearest_cache(node.global_position, 16.0).get("label", ""), "LENS CHIP")
	assert_eq(_prompt_at(node.global_position), "E   Dig up the lens chip")


func test_the_detector_pings_a_buried_find_with_its_own_readout() -> void:
	_world()
	var e: Dictionary = _first(Finds.BURIED)
	var id: String = str(e["id"])
	assert_true(_finds.surface(id, _fx.districts.cells_of(str(e["district"]))[0]))
	var node: Node3D = _sites.show_cache(id)
	var det := PartDetector.new()
	_lumi.add_child(det)
	det.patch = _lumi
	det.field = SphereField.new(_fx.grid, SphereTerrain.new(_fx.grid, SEED), _fx.cells, SEED)
	det.cache_fn = _sites.nearest_cache
	var seen: Array = []
	det.readout_changed.connect(func(text: String, _c: Color, s: float) -> void: seen.append([text, s]))
	GameState.flags["tutorial_step"] = Tutorial.STEPS.size()
	_lumi.global_position = node.global_position + node.global_basis.x * 2.0
	det._process(0.1)
	assert_eq(det.cache.get("id", ""), id)
	assert_gt(det.strength, 0.5, "close: a strong signal")
	assert_string_contains(str(seen[-1][0]), "BURIED TIN")
	_lumi.global_position = node.global_position + node.global_basis.x * 60.0
	det._process(0.1)
	assert_true(det.cache.is_empty(), "far: nothing")


func test_saved_finds_lying_in_the_soil_stay_there() -> void:
	_world()
	var e: Dictionary = _first(Finds.BURIED)
	var id: String = str(e["id"])
	var cell: int = _fx.districts.cells_of(str(e["district"]))[0]
	assert_true(_finds.surface(id, cell))
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_finds.save_state()))
	_fx.free_systems()
	_world(saved)
	assert_eq(_finds.surfaced_finds().get(id, Finds.NO_CELL), cell)
	assert_false(_finds.is_taken(id))


# --- The moment -------------------------------------------------------------------------------

func test_a_salvaged_piece_is_a_moment_on_lumi() -> void:
	Planets.set_current(FIRST)
	var stub := GDScript.new()
	stub.source_code = "extends Node3D\nvar patch: Node3D\nvar model: Node3D\n"
	stub.reload()
	var world := Node3D.new()
	world.set_script(stub)
	add_child_autofree(world)
	var player := Node3D.new()
	player.set_script(stub)
	world.add_child(player)
	var model := PatchModel.new()
	player.add_child(model)
	player.set("model", model)
	world.set("patch", player)
	var reveal := PieceReveal.new()
	reveal.world = world
	add_child_autofree(reveal)
	Looks.grant("ears_leaf", Finds.WRECK)
	reveal._process(0.1)
	assert_eq(reveal.showing().get("id", ""), "ears_leaf")
	assert_string_contains(reveal._kind.text, "SALVAGED", "a wreck's piece says it was salvaged")
	assert_eq(reveal._name.text, tr(Looks.name_of("ears_leaf")).to_upper(), "the piece is named")
	assert_string_contains(reveal._line.text, "Locker", "the way to the Locker")
	assert_true(reveal.lit(), "a light in the piece's colour over Lumi")
	assert_lt(reveal._plate.size.y, 200.0, "the plate is as tall as its text, not the screen")
	reveal._process(Finds.reveal_s(Planets.current()) + 0.1)
	assert_false(reveal.lit(), "the light goes with the moment")
	assert_false(reveal._plate.visible)


# --- Seen from afar (M3-14b) ------------------------------------------------------------------

func test_a_wreck_that_holds_pieces_grows_a_young_plant_that_goes_when_salvaged() -> void:
	_world()
	var id: String = str(_first(Finds.WRECK)["id"])
	var node: Node3D = _sites.show_wreck(id)
	var plant: Node3D = node.get_node_or_null(FindProps.SAPLING) as Node3D
	assert_not_null(plant, "a young plant grows out of a wreck that still holds pieces")
	var top: float = 0.0
	for mi: Node in plant.find_children("*", "MeshInstance3D", true, false):
		top = maxf(top, (mi as MeshInstance3D).position.y)
	var want: float = float((Finds.site_cfg(_fx.def)["sapling"] as Dictionary)["height_m"])
	assert_gt(top, want * 0.8, "it stands well above the junk (%.2f m)" % top)
	var tease: String = str(_finds.teases()[0]["id"])
	assert_null(_sites.show_wreck(tease).get_node_or_null(FindProps.SAPLING), "a tease has nothing to give, and no plant")
	assert_true(_finds.take(id))
	assert_true(plant.is_queued_for_deletion(), "salvaged: the plant goes")
	assert_not_null(node.get_node_or_null("Flowers"), "and flowers come up instead")
	assert_null(_sites.show_wreck(id).get_node_or_null(FindProps.SAPLING), "a salvaged wreck stands again without it")


func test_the_tease_sits_up_so_it_reads_as_a_robot() -> void:
	var tease := WreckModel.new()
	tease.design = "bolt"
	tease.ruined = true
	add_child_autofree(tease)
	var own := WreckModel.new()
	own.design = "sprout"
	add_child_autofree(own)
	var t_tilt: Node3D = tease.get_node("Tilt") as Node3D
	var o_tilt: Node3D = own.get_node("Tilt") as Node3D
	assert_lt(t_tilt.rotation.x, 0.0, "slumped forward, not on its back")
	assert_gt(o_tilt.rotation.x, 0.0, "the planet's own wreck lies back, face to the sky")
	assert_lt(-t_tilt.position.y, -o_tilt.position.y, "sunk less than a wreck on its back")
	assert_lt(WreckModel.RUINED_COVERAGE_LOSS, 0.25, "enough of its paint left to say which design it is")


func test_the_found_moment_has_a_glow_that_shows_in_sunlight() -> void:
	Planets.set_current(FIRST)
	var script_stub := GDScript.new()
	script_stub.source_code = "extends Node3D\nvar patch: Node3D\nvar model: Node3D\n"
	script_stub.reload()
	var world := Node3D.new()
	world.set_script(script_stub)
	add_child_autofree(world)
	var player := Node3D.new()
	player.set_script(script_stub)
	world.add_child(player)
	var model := PatchModel.new()
	player.add_child(model)
	player.set("model", model)
	world.set("patch", player)
	var reveal := PieceReveal.new()
	reveal.world = world
	add_child_autofree(reveal)
	Looks.grant("ears_leaf", Finds.WRECK)
	reveal._process(0.1)
	assert_true(reveal.lit())
	var light: Node3D = player.get_node("FoundLight") as Node3D
	for part: String in ["FoundRing", "FoundColumn"]:
		var mi: MeshInstance3D = light.get_node_or_null(part) as MeshInstance3D
		assert_not_null(mi, part)
		var mat: StandardMaterial3D = mi.material_override as StandardMaterial3D
		assert_eq(mat.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED, "%s glows by itself, the sun does not wash it out" % part)
		var c: Color = mat.albedo_color
		assert_gt(c.g, c.r, "%s is in the colour of Sprout's light, the piece's set" % part)
	reveal._process(Finds.reveal_s(Planets.current()) + 0.1)
	assert_false(reveal.lit(), "it goes with the moment")
