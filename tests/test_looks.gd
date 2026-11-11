extends GutTest
## Looks from found pieces (design spec section 13; tasks M3-14 and M3-16): the piece list
## (systems/looks.gd, data/cosmetics.json), where a planet hides pieces (systems/finds.gd, the
## planet's `finds` table), the pace rules, the save, and the Locker as the one place looks are
## edited. Tests that can run on any planet take the planet id: the first planet and the dummy
## planet (which hides nothing).

const FIRST: StringName = &"verdance"
const DUMMY: StringName = &"testworld"
const PLANETS: Array[StringName] = [FIRST, DUMMY]
const OLD_SAVE: String = "res://tests/fixtures/saves/looks_v4.json"
const LATER_DESIGNS: Array[String] = ["bolt", "pixel", "nova", "patch"]
const FORBIDDEN_KEYS: Array[String] = ["unlock", "cost", "cond", "lumi_level", "achievement", "requires_level"]

var _flags: Dictionary
var _stats: Dictionary
var _global: Dictionary
var _orbit: Dictionary
var _world: Dictionary
var _planet: StringName
var _fx: DistrictFixture
var _finds: Finds
var _found: Array = []
var _sets: Array = []


func before_all() -> void:
	Planets.register_dir(DistrictFixture.FIXTURE_PLANETS)


func after_all() -> void:
	Planets.unregister(DUMMY)


func before_each() -> void:
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)
	_global = GameState.global.duplicate(true)
	_orbit = GameState.orbit.duplicate(true)
	_world = GameState.world.duplicate(true)
	_planet = Planets.current_id()
	GameState.flags = {}
	GameState.stats = {}
	GameState.global = {}
	GameState.world.clear()
	Looks.dev_all = false
	_found.clear()
	_sets.clear()
	EventBus.piece_found.connect(_on_piece_found)
	EventBus.set_completed.connect(_on_set_completed)


func after_each() -> void:
	EventBus.piece_found.disconnect(_on_piece_found)
	EventBus.set_completed.disconnect(_on_set_completed)
	if _fx:
		_fx.free_systems()
	_fx = null
	_finds = null
	GameState.flags = _flags
	GameState.stats = _stats
	GameState.global = _global
	GameState.orbit = _orbit
	GameState.world.clear()
	GameState.world.merge(_world)
	Planets.set_current(_planet)


func _on_piece_found(piece: String, source: String) -> void:
	_found.append([piece, source])


func _on_set_completed(design: String) -> void:
	_sets.append(design)


## A planet on the fixture globe with its Districts and a Finds node on top.
func _play(planet_id: StringName, interactables: Interactables = null) -> Finds:
	Planets.set_current(planet_id)
	_fx = DistrictFixture.new(planet_id)
	add_child_autofree(_fx.districts)
	add_child_autofree(_fx.restoration)
	_finds = Finds.new()
	add_child_autofree(_finds)
	_finds.setup(_fx.def, _fx.districts, _fx.cells, interactables)
	_finds.load_state({})
	return _finds


func _clean(cell: int) -> void:
	_fx.set_cell_stage(cell, 1)
	EventBus.hex_cleaned.emit(cell, Vector3.ZERO, BigNum.zero())


func _found_ids() -> Array:
	return _found.map(func(f: Array) -> String: return str(f[0]))


func _has_key(v: Variant, keys: Array[String]) -> String:
	if v is Dictionary:
		for k: Variant in (v as Dictionary):
			if str(k) in keys:
				return str(k)
			var inner: String = _has_key((v as Dictionary)[k], keys)
			if inner != "":
				return inner
	elif v is Array:
		for e: Variant in (v as Array):
			var inner2: String = _has_key(e, keys)
			if inner2 != "":
				return inner2
	return ""


# --- The piece list ---------------------------------------------------------------------------

func test_every_piece_names_one_real_thing_in_one_slot() -> void:
	var seen: Dictionary = {}
	var slots: Array[String] = Looks.slot_ids()
	assert_eq(slots, ["paint", "pattern", "eye_shape", "glow", "head", "ears", "shoulders", "chest", "held", "hip", "companion"] as Array[String],
		"the spec's eleven slots, in order")
	for s: Dictionary in Looks.slot_defs():
		assert_ne(str(s.get("name", "")), "", str(s["id"]))
		assert_ne(str(s.get("hint", "")), "", "%s has a hint line" % s["id"])
	for p: Dictionary in Looks.defs():
		var id: String = str(p["id"])
		assert_false(seen.has(id), "%s is listed once" % id)
		seen[id] = true
		assert_has(slots, str(p["slot"]), id)
		assert_ne(str(p.get("name", "")), "", id)
		assert_ne(Looks.hint(id), "", "%s has a hint" % id)
		var kinds: int = int(p.has("option")) + int(p.has("swatch")) + int(p.has("design"))
		assert_eq(kinds, 1, "%s is exactly one of option / swatch / design" % id)
		if p.has("option"):
			assert_false(LumiStyle.option(str(p["slot"]), str(p["option"])).is_empty(), "%s: the option exists" % id)
		if p.has("swatch"):
			assert_false(LumiStyle.swatch(str(p["swatch"])).is_empty(), "%s: the colour exists" % id)
			assert_has(["paint", "glow"], str(p["slot"]), "%s: a tin or a chip" % id)
		if p.has("design"):
			assert_true(PatchModel.VARIANTS.has(str(p["design"])), id)
		if p.has("set"):
			assert_false(Designs.def(str(p["set"])).is_empty(), "%s: its set is a design" % id)
	# Every option that is not an empty slot is a piece, so nothing is wearable without one.
	for slot: String in LumiStyle.PART_SLOTS:
		var opts: Array = LumiStyle.options(slot)
		for i: int in opts.size():
			var oid: String = str((opts[i] as Dictionary)["id"])
			if i == 0 and oid in ["none", "plain"]:
				continue
			assert_ne(Looks.piece_for(slot, "option", oid), "", "%s:%s is a piece" % [slot, oid])


func test_a_design_is_a_set_of_pieces_with_its_own_paint() -> void:
	for id: String in Designs.ids():
		var pieces: Array[String] = Looks.set_ids(id)
		assert_between(pieces.size(), 5, 8, "%s: %d pieces" % [id, pieces.size()])
		assert_ne(Looks.piece_for("paint", "design", id), "", "%s has a paint set" % id)
		var slots: Dictionary = {}
		for piece: String in pieces:
			assert_false(slots.has(Looks.slot_of(piece)), "%s: one piece per slot (%s)" % [id, piece])
			slots[Looks.slot_of(piece)] = true
	assert_between(Looks.set_ids("sprout").size(), 6, 8, "the first planet's set is 6 to 8 pieces")


func test_nothing_cosmetic_carries_an_unlock_rule_or_a_price() -> void:
	for path: String in [Looks.PATH, Designs.PATH, LumiStyle.PATH]:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		data.erase("_doc")
		if path == Looks.PATH:  # `legacy` is read by the save migration alone
			for p: Dictionary in data["pieces"]:
				p.erase("legacy")
		assert_eq(_has_key(data, FORBIDDEN_KEYS), "", "%s holds no unlock rule" % path)
	for gone: String in ["buy", "unlock_met", "option_unlocked", "swatch_unlocked", "advanced_unlocked"]:
		assert_false(_has_static(LumiStyle, gone), "LumiStyle.%s is gone" % gone)
	for gone: String in ["check_unlocks", "met", "conds", "progress"]:
		assert_false(_has_static(Designs, gone), "Designs.%s is gone" % gone)


func _has_static(script: Script, method: String) -> bool:
	for m: Dictionary in script.get_script_method_list():
		if str(m["name"]) == method:
			return true
	return false


func test_a_new_game_holds_only_the_starting_pieces() -> void:
	for id: String in Looks.ids():
		assert_eq(Looks.has(id), Looks.is_starter(id), id)
		if Looks.is_starter(id):
			assert_eq(Looks.set_of(id), Designs.DEFAULT, "%s: the starting pieces are Aurora's" % id)
	assert_eq(Looks.found_count(), 0)
	assert_false(GameState.flags.get(Looks.FIRST_FLAG, false))


func test_finding_a_piece_is_an_event_and_the_last_one_completes_the_set() -> void:
	assert_true(Looks.grant("tin_sky", "buried"))
	assert_false(Looks.grant("tin_sky", "buried"), "found once")
	assert_false(Looks.grant("no_such_piece", "buried"))
	assert_false(Looks.grant("head_fin", "buried"), "a starting piece is not a find")
	assert_eq(_found, [["tin_sky", "buried"]])
	assert_true(GameState.flags.get(Looks.FIRST_FLAG, false), "the first find offers the Locker")
	assert_eq(int(GameState.stats.get(Looks.STAT_FOUND, 0)), 1)
	var sprout: Array[String] = Looks.set_ids("sprout")
	for i: int in sprout.size():
		assert_eq(_sets, [], "not complete with %d of %d" % [i, sprout.size()])
		Looks.grant(sprout[i], "wreck")
	assert_eq(_sets, ["sprout"], "set_completed fires once, on the last piece")
	assert_true(Looks.set_collected("sprout"))
	assert_eq(Looks.set_progress("sprout"), [sprout.size(), sprout.size()] as Array[int])
	assert_eq(Looks.display_name("head_catears"), "???", "an unfound piece keeps its name")
	assert_eq(Looks.display_name("tin_sky"), "Sky tin")


# --- Where a planet hides pieces ----------------------------------------------------------------

func test_every_find_names_real_pieces_and_no_piece_is_hidden_twice(planet_id: StringName = use_parameters(PLANETS)) -> void:
	var def: PlanetDefinition = Planets.by_id(planet_id)
	var seen: Dictionary = {}
	var ids: Dictionary = {}
	for e: Dictionary in Finds.entries_for(def):
		assert_false(ids.has(e["id"]), "%s: find id %s is used once" % [planet_id, e["id"]])
		ids[e["id"]] = true
		assert_has([Finds.BURIED, Finds.WRECK, Finds.SOURCE, Finds.SECRET], e["where"], str(e["id"]))
		for piece: String in e["pieces"]:
			assert_true(Looks.exists(piece), "%s: %s" % [e["id"], piece])
			assert_false(Looks.is_starter(piece), "%s: a starting piece is not hidden" % piece)
			assert_false(seen.has(piece), "%s: %s is hidden once" % [planet_id, piece])
			seen[piece] = true
	var raw: Array = def.table(Finds.TABLE).get("finds", [])
	assert_eq(Finds.entries_for(def).size(), raw.size(), "%s: every entry of the table is usable" % planet_id)


func test_a_planet_without_the_table_hides_nothing() -> void:
	var f: Finds = _play(DUMMY)
	assert_eq(f.entries().size(), 0)
	assert_eq(Finds.set_for(_fx.def), "")
	for c: int in _fx.districts.cells_of(_fx.districts.ids()[0]).slice(0, 60):
		_clean(c)
	f.shut_source(_fx.districts.ids()[0])
	f.catch_up()
	assert_eq(_found, [], "no pieces on a planet with no finds table")
	assert_eq(f.hexes_cleaned(_fx.districts.ids()[0]), 60)


func test_the_first_planet_offers_sprout_alone_spread_over_its_cities() -> void:
	var def: PlanetDefinition = Planets.by_id(FIRST)
	var specs: Array[Dictionary] = Districts.specs_for(def)
	var order: Array = specs.map(func(s: Dictionary) -> String: return str(s["id"]))
	assert_eq(Finds.set_for(def), "sprout")
	var placed: Dictionary = {}
	var cities: Dictionary = {}
	for e: Dictionary in Finds.entries_for(def):
		for piece: String in e["pieces"]:
			placed[piece] = e
			var design: String = Looks.set_of(piece)
			assert_does_not_have(LATER_DESIGNS, design, "%s belongs to a later planet" % piece)
			if design == "sprout":
				assert_has([Finds.WRECK, Finds.SOURCE], e["where"], "%s: a design piece comes from a wreck or a source" % piece)
				cities[e["district"]] = true
		if e["district"] != Finds.OPEN_GROUND:
			assert_has(order, e["district"], "%s names a city of this planet" % e["id"])
	for piece: String in Looks.set_ids("sprout"):
		assert_true(placed.has(piece), "%s has a find" % piece)
	assert_gte(cities.size(), 4, "Sprout is spread over the cities")
	var last_city: String = order[-1]
	assert_true(cities.has(last_city), "a Sprout piece waits in the last city")
	var in_last: Array = Finds.entries_for(def).filter(func(e: Dictionary) -> bool:
		return e["district"] == last_city and Looks.set_of(str((e["pieces"] as Array)[0])) == "sprout")
	assert_eq(in_last.size(), 1)
	assert_eq(in_last[0]["where"], Finds.SOURCE, "and it comes from shutting down that city's source")
	# Sources give one find per city at most.
	var per_city: Dictionary = {}
	for e: Dictionary in Finds.entries_for(def):
		if e["where"] == Finds.SOURCE:
			assert_false(per_city.has(e["district"]), "%s: one source find" % e["district"])
			per_city[e["district"]] = true
			assert_eq((e["pieces"] as Array).size(), 1)
		if e["where"] == Finds.WRECK:
			assert_between((e["pieces"] as Array).size(), 1, 2, "%s: a wreck gives 1 or 2 pieces" % e["id"])


func test_the_first_planet_buries_about_eight_colours_one_in_forty_hexes() -> void:
	var def: PlanetDefinition = Planets.by_id(FIRST)
	var buried: Array = Finds.entries_for(def).filter(func(e: Dictionary) -> bool: return e["where"] == Finds.BURIED)
	assert_between(buried.size(), 7, 10, "about eight loose colours and light tints")
	var first_city: String = str(Districts.specs_for(def)[0]["id"])
	var rest: Array = []
	for e: Dictionary in buried:
		var piece: Dictionary = Looks.def(str((e["pieces"] as Array)[0]))
		assert_true(piece.has("swatch"), "%s: buried finds are single colours" % e["id"])
		assert_eq(Looks.set_of(str(piece["id"])), "", "%s belongs to no design" % piece["id"])
		assert_gt(int(e["by_hex"]), 0)
		if e["district"] != Finds.OPEN_GROUND:
			var land: int = Districts.hexes_for_rings(int(_spec(def, str(e["district"]))["rings"]))
			assert_lt(float(e["by_hex"]), land * 0.7, "%s: found for certain well inside its city" % e["id"])
		if not (e["district"] == first_city and int(e["from_hex"]) < 20):
			rest.append(e)
	for e: Dictionary in rest:
		if e["district"] != Finds.OPEN_GROUND:
			assert_almost_eq(float(e["chance_per_hex"]), 1.0 / 40.0, 0.005, "%s: about one in 40 hexes" % e["id"])
		else:
			assert_lt(float(e["chance_per_hex"]), 1.0 / 40.0, "%s: open ground is very rare" % e["id"])


func _spec(def: PlanetDefinition, district: String) -> Dictionary:
	for s: Dictionary in Districts.specs_for(def):
		if s["id"] == district:
			return s
	return {}


func test_pieces_no_planet_hides_yet_are_not_part_of_the_first_planets_offer() -> void:
	# Every piece is a starting piece, or hidden on a registered planet, or waits for a later
	# planet. The ones that wait are listed so a new one is a decision, not an accident.
	var hidden: Dictionary = {}
	for def: PlanetDefinition in Planets.all():
		for e: Dictionary in Finds.entries_for(def):
			for piece: String in e["pieces"]:
				hidden[piece] = true
	var waiting: Array[String] = []
	for id: String in Looks.ids():
		if Looks.is_starter(id) or hidden.has(id):
			continue
		waiting.append(id)
		assert_ne(Looks.set_of(id), "sprout", "%s: every Sprout piece is hidden on the first planet" % id)
	var loose_waiting: Array = waiting.filter(func(id: String) -> bool: return Looks.set_of(id) == "")
	loose_waiting.sort()
	assert_eq(loose_waiting, ["chest_heart", "chip_bloom", "chip_gold", "chip_orange", "companion_drone", "eyes_bar", "eyes_heart", "eyes_round",
		"head_antenna", "head_halo", "held_medkit", "held_watering_can", "tin_chalk", "tin_graphite", "tin_slate"],
		"the loose pieces that wait for a later planet")


# --- Finding them in play -------------------------------------------------------------------------

func test_a_buried_tin_turns_up_at_a_fixed_cleaned_hex() -> void:
	var f: Finds = _play(FIRST)
	var first: Dictionary = f.entries()[0]
	assert_eq(first["where"], Finds.BURIED)
	var at: int = Finds.buried_hex(_fx.def.world_seed, first)
	assert_between(at, 12, 14, "the first piece: near the bot's minute 12 to 16")
	assert_eq(Finds.buried_hex(_fx.def.world_seed, first), at, "the same hex every time")
	var cells: PackedInt32Array = _fx.districts.cells_of(str(first["district"]))
	for i: int in at - 1:
		_clean(cells[i])
	assert_eq(_found, [], "nothing before hex %d" % at)
	_clean(cells[at - 1])
	assert_eq(_found, [[str(first["pieces"][0]), Finds.BURIED]])
	assert_true(f.is_taken(str(first["id"])))
	assert_true(GameState.flags.get(Looks.FIRST_FLAG, false))
	# A save and a load do not hand it out again, and the count carries on.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(f.save_state()))
	f.load_state(saved)
	assert_true(f.is_taken(str(first["id"])))
	assert_eq(f.hexes_cleaned(str(first["district"])), at)
	_clean(cells[at])
	assert_eq(_found.size(), 1)


func test_a_wreck_gives_its_pieces_when_its_hex_is_cleared() -> void:
	var f: Finds = _play(FIRST)
	var wreck: Dictionary = f.entries().filter(func(e: Dictionary) -> bool: return e["where"] == Finds.WRECK)[0]
	var cell: int = f.site_cell(str(wreck["id"]))
	assert_ne(cell, Finds.NO_CELL)
	assert_eq(f.site_cell(str(wreck["id"])), cell, "the wreck stays on its hex")
	var cells: PackedInt32Array = _fx.districts.cells_of(str(wreck["district"]))
	var at: int = cells.find(cell)
	var rings: int = int(_fx.districts.spec_of(str(wreck["district"]))["rings"])
	assert_gte(at, Districts.hexes_for_rings(int(rings * 0.5)), "off the main path: in the outer half of the city")
	_clean(cells[0])
	assert_false(f.is_taken(str(wreck["id"])))
	_clean(cell)
	assert_true(f.is_taken(str(wreck["id"])))
	for piece: String in wreck["pieces"]:
		assert_has(_found, [piece, Finds.WRECK])
	# The hex is in the save, so a reload keeps the wreck where it was.
	var f2 := Finds.new()
	add_child_autofree(f2)
	f2.setup(_fx.def, _fx.districts, _fx.cells)
	f2.load_state(JSON.parse_string(JSON.stringify(f.save_state())))
	assert_eq(f2.site_cell(str(wreck["id"])), cell)
	assert_true(f2.is_taken(str(wreck["id"])))


func test_a_placed_wreck_is_taken_by_using_it() -> void:
	var ia := Interactables.new()
	add_child_autofree(ia)
	var f: Finds = _play(FIRST, ia)
	var wreck: Dictionary = f.entries().filter(func(e: Dictionary) -> bool: return e["where"] == Finds.WRECK)[0]
	var id: String = str(wreck["id"])
	var anchor := Node3D.new()
	add_child_autofree(anchor)
	anchor.global_position = Vector3(40, 0, 0)
	assert_true(f.register_site(id, anchor, "E   salvage the wreck"))
	assert_false(f.register_site("no_such_find", anchor, ""))
	_clean(f.site_cell(id))
	assert_false(f.is_taken(id), "with a wreck standing there, clearing the hex is not enough")
	assert_eq(ia.prompt(Vector3(41, 0, 0)), "E   salvage the wreck")
	assert_eq(ia.prompt(Vector3(60, 0, 0)), "", "out of reach")
	assert_true(ia.try_use(Vector3(41, 0, 0)))
	assert_true(f.is_taken(id))
	assert_eq(_found.size(), (wreck["pieces"] as Array).size())
	assert_eq(ia.prompt(Vector3(41, 0, 0)), "", "a taken wreck offers nothing")
	assert_false(ia.try_use(Vector3(41, 0, 0)))
	assert_false(f.take(id), "taken once")


func test_shutting_down_a_source_gives_its_piece() -> void:
	var f: Finds = _play(FIRST)
	var source: Dictionary = f.entries().filter(func(e: Dictionary) -> bool: return e["where"] == Finds.SOURCE)[0]
	EventBus.source_shut_down.emit("no_such_city")
	assert_eq(_found, [])
	EventBus.source_shut_down.emit(str(source["district"]))
	assert_eq(_found, [[str(source["pieces"][0]), Finds.SOURCE]])
	EventBus.source_shut_down.emit(str(source["district"]))
	assert_eq(_found.size(), 1, "once")


func test_until_sources_are_jobs_the_city_stage_shuts_them() -> void:
	var f: Finds = _play(FIRST)
	var stage: int = int(_fx.def.table(Finds.TABLE)["source_shut_at_stage"])
	var source: Dictionary = f.entries().filter(func(e: Dictionary) -> bool: return e["where"] == Finds.SOURCE)[0]
	var city: String = str(source["district"])
	f.load_state({"hexes": {city: 100000}})  # past every buried find: only the source is watched here
	_fx.set_district_stage(city, stage - 1)
	assert_false(f.is_taken(str(source["id"])), "not below stage %d" % stage)
	_fx.set_district_stage(city, stage)
	assert_true(f.is_taken(str(source["id"])))
	assert_has(_found, [str(source["pieces"][0]), Finds.SOURCE])
	# A save whose city is already past that stage gets it on load.
	_found.clear()
	var f2 := Finds.new()
	add_child_autofree(f2)
	f2.setup(_fx.def, _fx.districts, _fx.cells)
	f2.load_state({})
	Looks.found().clear()
	f2.catch_up()
	assert_has(_found, [str(source["pieces"][0]), Finds.SOURCE])


func test_a_secret_gives_its_piece() -> void:
	var f: Finds = _play(FIRST)
	var secret: Dictionary = f.entries().filter(func(e: Dictionary) -> bool: return e["where"] == Finds.SECRET)[0]
	var eggs: Array = (_fx.def.table("eggs").get("eggs", []) as Array).map(func(e: Dictionary) -> String: return str(e["id"]))
	assert_has(eggs, secret["egg"], "the secret is one of this planet's curiosities")
	EventBus.easter_egg_found.emit("no_such_egg")
	assert_eq(_found, [])
	EventBus.easter_egg_found.emit(str(secret["egg"]))
	assert_eq(_found, [[str(secret["pieces"][0]), Finds.SECRET]])


# --- Pace: the whole first planet, played in order ------------------------------------------------

func test_playing_the_first_planet_completes_sprout_alone_and_only_in_the_last_city() -> void:
	var f: Finds = _play(FIRST)
	var order: Array[String] = _fx.districts.ids()
	var stage: int = int(_fx.def.table(Finds.TABLE)["source_shut_at_stage"])
	var first_piece_hex: int = -1
	var cleaned: int = 0
	for i: int in order.size():
		var city: String = order[i]
		var last: bool = i == order.size() - 1
		for c: int in _fx.districts.cells_of(city):
			if Districts.cell_stage(_fx.cells, c) != 0:
				continue
			_clean(c)
			cleaned += 1
			if first_piece_hex < 0 and not _found.is_empty():
				first_piece_hex = cleaned
		assert_eq(_sets, [], "%s: clearing every hex does not complete the set" % city)
		if last:
			assert_eq(Looks.set_progress("sprout")[0], Looks.set_ids("sprout").size() - 1, "one piece short until the last source is shut")
		_fx.set_district_stage(city, stage)
		if not last:
			assert_eq(_sets, [], "Sprout is not complete after %s" % city)
			assert_false(Looks.set_collected("sprout"))
	assert_eq(_sets, ["sprout"], "exactly one design is completed, in the last city")
	assert_between(first_piece_hex, 12, 14, "the first piece comes with the 12th to 14th cleaned hex")
	assert_eq(str(_found[0][1]), Finds.BURIED, "and it is a colour")
	for design: String in LATER_DESIGNS:
		assert_eq(Looks.set_progress(design)[0], 0, "no piece of %s on this planet" % design)
	var colours: Array = _found.filter(func(x: Array) -> bool: return x[1] == Finds.BURIED)
	assert_between(colours.size(), 7, 9, "about eight loose colours by the end")
	for e: Dictionary in f.entries():
		if e["where"] in [Finds.WRECK, Finds.SOURCE] or (e["where"] == Finds.BURIED and e["district"] != Finds.OPEN_GROUND):
			assert_true(f.is_taken(str(e["id"])), "%s was found on the way" % e["id"])
	# Design pieces arrive city by city, never two cities' worth at once.
	var seen_sets: int = _found.filter(func(x: Array) -> bool: return Looks.set_of(str(x[0])) == "sprout").size()
	assert_eq(seen_sets, Looks.set_ids("sprout").size())


# --- The save -------------------------------------------------------------------------------------

func test_found_pieces_live_in_the_global_section_of_the_save() -> void:
	Looks.grant("tin_sky", "buried")
	Looks.grant("head_sprout", "source")
	var d: Dictionary = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	assert_eq(int(d["version"]), 5)
	assert_eq(d["global"][Looks.KEY], ["tin_sky", "head_sprout"])
	assert_false(JSON.stringify(d["flags"]).contains("tin_sky"), "not in the per-save flags")
	assert_false(JSON.stringify(d.get("orbit", {})).contains("tin_sky"), "not in the planet's section")
	var keep: Dictionary = GameState.to_dict()
	GameState.from_dict(SaveManager.migrate(d))
	assert_true(Looks.has("tin_sky") and Looks.has("head_sprout"))
	assert_eq(Looks.found(), ["tin_sky", "head_sprout"], "in the order found")
	GameState.from_dict(keep)


func test_an_old_save_keeps_what_it_had() -> void:
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OLD_SAVE))
	old.erase("_doc")
	assert_eq(int(old["version"]), 4)
	var keep: Dictionary = GameState.to_dict()
	var m: Dictionary = SaveManager.migrate(old)
	assert_eq(int(m["version"]), GameState.SAVE_VERSION)
	GameState.from_dict(m)
	for piece: String in Looks.set_ids("bolt"):
		assert_true(Looks.has(piece), "the unlocked design's %s" % piece)
	for piece: String in ["tin_copper", "companion_drone", "tin_sky", "eyes_round", "head_halo", "tin_seaglass", "eyes_heart",
			"tin_graphite", "tin_slate", "chip_orange", "head_antenna"]:
		assert_true(Looks.has(piece), "%s: its old rule was met" % piece)
	for piece: String in ["tin_chalk", "chip_coral", "chip_mint", "companion_firefly", "tin_midnight", "paint_sprout", "head_catears"]:
		assert_false(Looks.has(piece), "%s: never earned, not given" % piece)
	assert_false(GameState.flags.has("skins_unlocked"), "the old unlock list is gone")
	assert_false(GameState.flags.has("style_bought"))
	assert_true(GameState.flags.get(Looks.FIRST_FLAG, false), "so the Locker is on offer")
	# The look it wore is still worn and still wearable, mixed colours and all.
	var worn: Dictionary = LumiStyle.current()
	assert_eq(Designs.current(), "bolt")
	assert_eq(worn["head"], "halo")
	assert_eq(worn["companion"], "drone")
	assert_eq(LumiStyle.piece_in(worn, "paint"), "tin_copper")
	assert_eq(LumiStyle.piece_in(worn, "glow"), "", "its own mix of light colours is no piece")
	assert_true(LumiStyle.allowed(worn), "but it had it, so it keeps it")
	assert_eq(LumiStyle.looks().size(), 5, "and its fifth saved look")
	assert_eq(LumiStyle.look(4)["eye_shape"], "heart")
	assert_eq(Designs.worn_set(), "", "a mixed look: no bonus")
	# Migrating twice changes nothing.
	var again: Dictionary = SaveManager.migrate(JSON.parse_string(JSON.stringify(GameState.to_dict())))
	assert_eq(again["global"][Looks.KEY], m["global"][Looks.KEY])
	GameState.from_dict(keep)


# --- The Locker -----------------------------------------------------------------------------------

func test_the_locker_is_offered_after_the_first_find() -> void:
	Planets.set_current(FIRST)
	YardBuilds._drop_planet_cache()
	assert_eq(str(YardBuilds.def("locker").get("requires_flag", "")), Looks.FIRST_FLAG)
	assert_false(YardBuilds.listed("locker", 5), "not in the Build tab before a piece is found, whatever the base level")
	assert_false(YardBuilds.unlocked("locker", 5))
	Looks.grant("tin_sky", "buried")
	assert_true(YardBuilds.listed("locker", 1))
	assert_true(YardBuilds.unlocked("locker", 1), "no base level needed")
	assert_gt(float((YardBuilds.def("locker").get("cost", {}) as Dictionary).get("cubes", 0)), 0.0, "a build, paid in cubes")


func test_the_goal_chain_brings_the_locker_once_a_piece_is_found() -> void:
	Planets.set_current(FIRST)
	var g := Goals.new()
	add_child_autofree(g)
	var ids: Array = g.chain.map(func(x: Dictionary) -> String: return str(x["id"]))
	var build: int = ids.find("locker_build")
	var wear: int = ids.find("locker_wear")
	assert_gt(build, -1)
	assert_gt(wear, -1)
	assert_does_not_have(g.current(), build, "not offered before a piece is found")
	assert_does_not_have(g.current(), wear)
	Looks.grant("tin_sky", "buried")
	assert_eq(g.current()[0], build, "then it is the next step")
	assert_eq(g.current()[1], wear)
	GameState.flags[LockerCabinet.BUILT_FLAG] = true
	assert_gte(g.value_of(build), g.target_of(build))
	GameState.stats[LumiBuilder.WORN_STAT] = 1
	assert_gte(g.value_of(wear), g.target_of(wear))


func test_the_turntable_shows_lumi_and_gives_the_view_back() -> void:
	var world := _World.new()
	add_child_autofree(world)
	world.patch = Node3D.new()
	world.add_child(world.patch)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.make_current()
	var stage := LockerStage.new()
	world.add_child(stage)
	assert_false(stage.is_open())
	assert_not_null(stage.get_node_or_null("Turntable"), "the turntable stands by the Locker")
	stage.begin(world, LumiStyle.preset("aurora"))
	assert_true(stage.is_open())
	assert_not_null(stage.model(), "Lumi stands on it")
	assert_true(stage.get_node("Pivot").is_ancestor_of(stage.model()))
	assert_false(world.patch.visible, "the real Lumi is out of sight meanwhile")
	assert_ne(get_viewport().get_camera_3d(), cam, "the view moves to the turntable")
	var yaw0: float = (stage.get_node("Pivot") as Node3D).rotation.y
	var cam0: Vector3 = get_viewport().get_camera_3d().global_position
	stage._idle = LockerStage.IDLE_S
	stage._process(1.0)
	assert_ne((stage.get_node("Pivot") as Node3D).rotation.y, yaw0, "the turntable turns")
	assert_ne(get_viewport().get_camera_3d().global_position, cam0, "and the camera swings round it")
	var s: Dictionary = LumiStyle.preset("aurora")
	LumiStyle.wear_piece(s, "head_halo")
	stage.show_style(s)
	assert_eq((stage.model().get_meta("lumi_style") as Dictionary)["head"], "halo", "the look being edited is on the turntable")
	stage.end()
	assert_false(stage.is_open())
	assert_eq(get_viewport().get_camera_3d(), cam, "the player's camera is back")
	assert_true(world.patch.visible, "and so is Lumi")


class _World extends Node3D:
	var patch: Node3D


func test_the_locker_panel_docks_beside_the_turntable_and_pauses_the_world() -> void:
	YardBuilds.mark_built("locker")
	var world := Node3D.new()
	add_child_autofree(world)
	var cl: CanvasLayer = LockerPanel.open_overlay(world)
	assert_true(get_tree().paused, "the world stands still while the Locker is open")
	get_tree().paused = false  # the test itself must keep running
	await wait_frames(3)
	var lp: LockerPanel = null
	var builder: LumiBuilder = null
	for n: Node in cl.find_children("*", "", true, false):
		if n is LockerPanel:
			lp = n
		elif n is LumiBuilder:
			builder = n
	assert_not_null(lp)
	assert_not_null(builder, "Lumi's page is the first thing shown")
	assert_eq(lp.editing(), LockerPanel.LUMI)
	assert_gt(cl.find_children("*", "FieldPlate", true, false).size(), 1, "on field-instrument plates")
	var vp: Vector2 = get_viewport().get_visible_rect().size
	assert_lt(lp.get_global_rect().size.x, vp.x * 0.7, "the panel leaves the turntable in view")
	assert_gt(lp.get_global_rect().position.x, vp.x * 0.25)
	get_tree().paused = true
	(cl.get_meta("shut") as Callable).call()
	assert_false(get_tree().paused, "closing gives the world back")
	await wait_frames(2)
	assert_false(is_instance_valid(cl))


func test_the_locker_is_the_only_place_looks_are_edited() -> void:
	for gone: String in ["res://ui/cosmetics_panel.gd", "res://ui/design_toast.gd", "res://ui/lumi_preview.gd", "res://scenes/style_builder_shot.tscn"]:
		assert_false(ResourceLoader.exists(gone), "%s is gone" % gone)
	assert_false(_has_static(LumiBuilder, "open"), "the builder no longer opens on its own")
	# Only the Locker's page (and the dev hooks) may change what Lumi wears.
	var allowed: Array[String] = ["res://ui/lumi_builder.gd", "res://systems/lumi_style.gd", "res://systems/designs.gd"]
	var callers: Array[String] = []
	_scan("res://", callers)
	assert_has(callers, "res://ui/lumi_builder.gd")
	for path: String in callers:
		assert_has(allowed, path, "%s changes what Lumi wears outside the Locker" % path)
	for t: Dictionary in UpgradesScreen.TABS:
		assert_does_not_have(["cosmetics", "locker", "designs"], str(t["id"]), "no workbench tab edits looks")


func _scan(dir_path: String, out: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		if sub.begins_with(".") or sub in ["addons", "tests", "tools", "parked", "screenshots", "docs"]:
			continue
		_scan(dir_path.path_join(sub), out)
	for file: String in dir.get_files():
		if not file.ends_with(".gd"):
			continue
		var path: String = dir_path.path_join(file)
		var text: String = FileAccess.get_file_as_string(path)
		if text.contains("LumiStyle.set_current(") or text.contains("LumiStyle.wear_set(") or text.contains("flags[\"lumi_style\"] ="):
			out.append(path)


func test_a_found_piece_is_a_moment_that_points_to_the_locker() -> void:
	Planets.set_current(FIRST)
	var reveal := PieceReveal.new()
	add_child_autofree(reveal)
	Looks.grant("tin_sky", "buried")
	assert_eq(reveal.queued(), 1)
	reveal._process(0.1)
	assert_eq(reveal.showing().get("id", ""), "tin_sky")
	assert_true(reveal._plate.visible)
	assert_eq(reveal._name.text, "SKY TIN", "the piece is named")
	assert_string_contains(reveal._kind.text, "PAINT")
	assert_string_contains(reveal._line.text, "Locker", "with the way to the Locker")
	assert_string_contains(reveal._line.text, "Build", "which is still to be built")
	reveal._process(Finds.reveal_s(Planets.current()) + 0.1)
	assert_false(reveal._plate.visible, "a short moment")
	YardBuilds.mark_built("locker")
	for piece: String in Looks.set_ids("sprout"):
		Looks.grant(piece, "wreck")
	assert_eq(reveal.queued(), Looks.set_ids("sprout").size() + 1, "each piece, then the set")
	reveal._process(1.0)
	assert_string_contains(reveal._line.text, "Wear it at the Locker")
	for i: int in Looks.set_ids("sprout").size():
		reveal._process(Finds.reveal_s(Planets.current()) + 0.1)
		reveal._process(1.0)
	assert_eq(reveal.showing().get("kind", ""), "set")
	assert_eq(reveal._name.text, "SPROUT")
	assert_string_contains(reveal._line.text, Designs.buff_text("sprout"))
