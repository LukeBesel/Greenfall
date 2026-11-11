extends GutTest
## Glim's and the crew's looks follow Lumi's rule (design spec section 13; task M3-14b): every look
## is a piece found in the world (systems/crew_looks.gd, data/cosmetics.json targets), worn only
## once found, edited only at the Locker; nothing is bought or opened by a counter; a save from
## before keeps what it had. Tests that can run on any planet take the planet id.

const FIRST: StringName = &"verdance"
const DUMMY: StringName = &"testworld"
const PLANETS: Array[StringName] = [FIRST, DUMMY]
const OLD_SAVE: String = "res://tests/fixtures/saves/crew_looks_v5.json"
## Planet 1 keeps these looks rare: a few of Glim's and the crew's, the rest wait for later planets.
const FIRST_PLANET_MIN: int = 2
const FIRST_PLANET_MAX: int = 5

var _flags: Dictionary
var _stats: Dictionary
var _global: Dictionary
var _cur: Dictionary
var _planet: StringName
var _fx: DistrictFixture


func before_all() -> void:
	Planets.register_dir(DistrictFixture.FIXTURE_PLANETS)


func after_all() -> void:
	Planets.unregister(DUMMY)


func before_each() -> void:
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)
	_global = GameState.global.duplicate(true)
	_cur = GameState.currencies.duplicate()
	_planet = Planets.current_id()
	GameState.flags = {}
	GameState.stats = {}
	GameState.global = {}
	Glim.dev_all = false
	Looks.dev_all = false


func after_each() -> void:
	if _fx:
		_fx.free_systems()
	_fx = null
	GameState.flags = _flags
	GameState.stats = _stats
	GameState.global = _global
	GameState.currencies = _cur
	Planets.set_current(_planet)


# --- The pieces -----------------------------------------------------------------------------------

func test_every_glim_look_and_crew_look_is_a_piece() -> void:
	var slot_ids: Dictionary = {}
	for s: Dictionary in Looks.slot_defs():
		slot_ids[str(s["id"])] = true
	for t: String in [CrewLooks.GLIM, CrewLooks.CREW]:
		assert_has(Looks.target_ids(), t)
		for s: Dictionary in Looks.target_slots(t):
			assert_false(slot_ids.has(str(s["id"])), "%s: slot ids are unique across targets" % s["id"])
			slot_ids[str(s["id"])] = true
			assert_ne(str(s.get("hint", "")), "", "%s has a hint line" % s["id"])
		for p: Dictionary in Looks.target_defs(t):
			assert_eq(Looks.target_of(str(p["id"])), t)
			assert_eq(Looks.set_of(str(p["id"])), "", "%s belongs to no set" % p["id"])
	for slot: String in Glim.SLOTS:
		for l: Variant in Glim.looks(slot):
			assert_ne(Glim.piece_of(slot, str((l as Dictionary)["id"])), "", "Glim %s:%s" % [slot, (l as Dictionary)["id"]])
	for p: Dictionary in RobotBuilder.all_parts():
		assert_ne(CrewLooks.piece(CrewLooks.CREW, str(p["slot"]), str(p["id"])), "", "part %s" % p["id"])
	for key: String in [CrewLooks.LIVERY, CrewLooks.GLOW]:
		var pieces: Array[String] = CrewLooks.pieces_of(CrewLooks.CREW, key)
		assert_gt(pieces.size(), 3, key)
		for id: String in pieces:
			assert_ne(CrewLooks.color_of(id, Color(0, 0, 0, 0)), Color(0, 0, 0, 0), "%s has its colour" % id)
	var mark: Node3D = Liveries.build("livery_neon")
	assert_not_null(mark, "a fleet mark builds from its piece")
	if mark:
		mark.free()
	assert_eq(RobotDesign.glow_color("mint"), CrewLooks.color_of("crew_glow_mint"))


func test_a_new_game_holds_only_glims_first_looks() -> void:
	for t: String in [CrewLooks.GLIM, CrewLooks.CREW]:
		for p: Dictionary in Looks.target_defs(t):
			var id: String = str(p["id"])
			assert_eq(Looks.has(id), Looks.is_starter(id), id)
	for p: Dictionary in Looks.target_defs(CrewLooks.CREW):
		assert_false(Looks.is_starter(str(p["id"])), "%s: the crew's stock look needs no piece" % p["id"])


func test_nothing_buys_or_counts_open_a_crew_or_glim_look() -> void:
	GameState.currencies = {"cubes": BigNum.from_float(1.0e9), "parts": BigNum.from_float(1.0e9), "seeds": BigNum.from_float(1.0e6)}
	GameState.stats = {"hexes_cleaned": 99999.0, "contracts_done": 999.0, "builder_parts_got": 999.0}
	for t: Variant in Glim.tracks():
		(Glim.st()["tiers"] as Dictionary)[str((t as Dictionary)["id"])] = Glim.max_tier(str((t as Dictionary)["id"]))
	var c := Contracts.new()
	c.count_done(40)
	c.free()
	for t: String in [CrewLooks.GLIM, CrewLooks.CREW]:
		for p: Dictionary in Looks.target_defs(t):
			assert_eq(Looks.has(str(p["id"])), Looks.is_starter(str(p["id"])), "%s: not held without being found" % p["id"])
	for path: String in ["res://data/glim.json", RobotBuilder.PATH]:
		var raw: String = FileAccess.get_file_as_string(path)
		var data: Dictionary = JSON.parse_string(raw)
		data.erase("_doc")
		var text: String = JSON.stringify(data)
		for word: String in ["\"unlock\"", "\"source\"", "\"haggle\"", "\"cost\": {\"cubes\""]:
			if path == "res://data/glim.json" and word == "\"cost\": {\"cubes\"":
				continue  # Glim's upgrade tracks are bought; his looks are not
			assert_false(text.contains(word), "%s holds no %s" % [path, word])
	for gone: String in ["buy_look", "unlock_hint", "key_of"]:
		assert_false(_has_static(load("res://systems/glim/glim.gd") as Script, gone), "Glim.%s is gone" % gone)
	for gone: String in ["shop", "shop_item", "owned", "buy", "block_reason"]:
		assert_false(_has_static(load("res://systems/contracts.gd") as Script, gone), "Contracts.%s is gone" % gone)


func _has_static(script: Script, method: String) -> bool:
	for m: Dictionary in script.get_script_method_list():
		if str(m["name"]) == method:
			return true
	return false


# --- Wearing --------------------------------------------------------------------------------------

func test_only_found_crew_looks_can_be_put_on() -> void:
	Research.grant("salvage_logic")
	var f := Fleet.new()
	add_child_autofree(f)
	f.spawn("scoopie", 0, Vector3.ZERO, 0.0, "Wear-01")
	for p: Dictionary in RobotBuilder.all_parts():
		var id: String = str(p["id"])
		if not RobotBuilder.fits(id, "scoopie"):
			continue
		assert_ne(RobotDesign.set_part(f, "scoopie", str(p["slot"]), id), "", "%s before it is found" % id)
		Looks.grant(CrewLooks.piece(CrewLooks.CREW, str(p["slot"]), id), "buried", true)
		assert_eq(RobotDesign.set_part(f, "scoopie", str(p["slot"]), id), "", "%s once found" % id)
	for key: String in [CrewLooks.LIVERY, CrewLooks.GLOW]:
		for piece: String in CrewLooks.pieces_of(CrewLooks.CREW, key):
			var opt: String = CrewLooks.option_of(piece)
			assert_false(RobotDesign.set_look(f, "scoopie", key, opt), "%s before it is found" % piece)
			Looks.grant(piece, "buried", true)
			assert_true(RobotDesign.set_look(f, "scoopie", key, opt), "%s once found" % piece)
		assert_true(RobotDesign.set_look(f, "scoopie", key, ""), "stock is always there")
	for slot: String in Glim.SLOTS:
		for l: Variant in Glim.looks(slot):
			var id: String = str((l as Dictionary)["id"])
			var piece: String = Glim.piece_of(slot, id)
			assert_eq(Glim.wear(slot, id), Looks.is_starter(piece), "Glim %s:%s before it is found" % [slot, id])
			Looks.grant(piece, "buried", true)
			assert_true(Glim.wear(slot, id), "Glim %s:%s once found" % [slot, id])


func test_the_locker_gives_glim_and_each_robot_type_a_tab() -> void:
	GlimDirector.register_cosmetics()
	Glim.set_found(true)
	YardBuilds.mark_built("locker")
	Research.grant("salvage_logic")
	var f := Fleet.new()
	add_child_autofree(f)
	f.spawn("scoopie", 0, Vector3.ZERO, 0.0, "Tab-01")
	var lp := LockerPanel.new()
	lp.fleet = f
	add_child_autofree(lp)
	await wait_frames(2)
	var whos: Array[String] = []
	for b: Button in lp._who_btns:
		whos.append(str(b.get_meta("who")))
	assert_has(whos, "target:glim")
	for rid: String in LockerEditors.bot_types(f):
		assert_has(whos, LockerPanel.BOTS_PREFIX + rid, "a tab for %s" % rid)
	lp.set_editing(LockerPanel.BOTS_PREFIX + "scoopie")
	assert_true(lp._editor is LockerEditors.BotEditor)
	lp.set_editing("target:glim")
	var ed: GlimPanel.GlimLooksEditor = lp._editor as GlimPanel.GlimLooksEditor
	assert_not_null(ed)
	for b: Button in ed.find_children("*", "Button", true, false):
		assert_false(b.text.contains("cubes") or b.text.contains("parts"), "no price on a Glim look: %s" % b.text)


func test_the_glim_panel_points_to_the_locker() -> void:
	var gp := GlimPanel.new()
	add_child_autofree(gp)
	await wait_frames(1)
	assert_false(gp._looks.visible, "Glim's looks are not edited at his panel")


# --- Where a planet hides them --------------------------------------------------------------------

func test_a_planet_hides_crew_and_glim_looks_only_through_its_finds(planet_id: StringName = use_parameters(PLANETS)) -> void:
	var def: PlanetDefinition = Planets.by_id(planet_id)
	var here: Array[String] = []
	for piece: String in Finds.pieces_for(def):
		if Looks.target_of(piece) != Looks.LUMI:
			here.append(piece)
			assert_has([CrewLooks.GLIM, CrewLooks.CREW], Looks.target_of(piece))
	for t: String in [CrewLooks.GLIM, CrewLooks.CREW]:
		for s: Dictionary in Looks.target_slots(t):
			var list: Dictionary = CrewLooks.listing(t, str(s["key"]), def)
			var total: int = (list["found"] as Array).size() + (list["hidden"] as Array).size() + int(list["elsewhere"])
			assert_eq(total, CrewLooks.pieces_of(t, str(s["key"])).size(), "%s: every piece is listed, hinted or counted" % s["id"])
			for piece: String in list["hidden"]:
				assert_has(here, piece)
				assert_ne(Finds.hint_for(def, piece), "", piece)
	if planet_id == FIRST:
		assert_between(here.size(), FIRST_PLANET_MIN, FIRST_PLANET_MAX, "a few on the first planet, the rest wait")
		var glim: int = here.filter(func(p: String) -> bool: return Looks.target_of(p) == CrewLooks.GLIM).size()
		assert_gt(glim, 0, "Glim has something to find")
		assert_gt(here.size() - glim, 0, "and so does the crew")
	else:
		assert_eq(here.size(), 0, "the dummy planet hides nothing")


func test_a_light_lies_buried_as_a_chip_and_a_shell_as_a_tin() -> void:
	assert_eq(FindSites.kind_of("glim_glow_leaf"), FindProps.CHIP)
	assert_eq(FindSites.kind_of("crew_glow_mint"), FindProps.CHIP)
	assert_eq(FindSites.kind_of("glim_shell_moss"), FindProps.TIN)
	assert_eq(CrewLooks.tint_of("glim_shell_moss"), Color.html(str(Glim.look("shells", "moss")["color"])))
	assert_eq(CrewLooks.tint_of("crew_glow_mint"), CrewLooks.color_of("crew_glow_mint"))


func test_playing_the_first_planet_finds_its_crew_and_glim_looks() -> void:
	Planets.set_current(FIRST)
	_fx = DistrictFixture.new(FIRST)
	add_child_autofree(_fx.districts)
	add_child_autofree(_fx.restoration)
	var finds := Finds.new()
	add_child_autofree(finds)
	finds.setup(_fx.def, _fx.districts, _fx.cells, null)
	finds.load_state({})
	for city: String in _fx.districts.ids():
		for c: int in _fx.districts.cells_of(city):
			if Districts.cell_stage(_fx.cells, c) == 0:
				_fx.set_cell_stage(c, 1)
				EventBus.hex_cleaned.emit(c, Vector3.ZERO, BigNum.zero())
	for piece: String in Finds.pieces_for(_fx.def):
		if Looks.target_of(piece) != Looks.LUMI:
			assert_true(Looks.has(piece), "%s turns up while the cities are cleaned" % piece)


func test_a_found_crew_piece_is_a_moment_that_says_whose_it_is() -> void:
	var reveal := PieceReveal.new()
	add_child_autofree(reveal)
	Looks.grant("glim_shell_moss", "buried")
	reveal._process(0.1)
	assert_eq(reveal.showing().get("id", ""), "glim_shell_moss")
	assert_string_contains(reveal._kind.text, "GLIM")
	assert_eq(reveal._name.text, "MOSS SHELL")
	assert_string_contains(reveal._line.text, "Locker")


# --- Old saves ------------------------------------------------------------------------------------

func test_an_old_save_keeps_its_crew_and_glim_looks() -> void:
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OLD_SAVE))
	old.erase("_doc")
	assert_eq(int(old["version"]), 5)
	var keep: Dictionary = GameState.to_dict()
	var m: Dictionary = SaveManager.migrate(old)
	assert_eq(int(m["version"]), GameState.SAVE_VERSION)
	GameState.from_dict(m)
	for piece: String in ["tin_sky", "glim_shell_sunset", "glim_top_beanie", "glim_glow_ember", "glim_top_sprout",
			"crew_treads", "crew_top_hat", "crew_livery_neon"]:
		assert_true(Looks.has(piece), "%s: it had it" % piece)
	for piece: String in CrewLooks.pieces_of(CrewLooks.CREW, CrewLooks.GLOW):
		assert_true(Looks.has(piece), "%s: robot lights were free before" % piece)
	for piece: String in ["glim_shell_moss", "glim_glow_leaf", "glim_shell_graphite", "glim_top_halo", "crew_big_eye", "crew_livery_halo"]:
		assert_false(Looks.has(piece), "%s: never earned, not given" % piece)
	assert_false((GameState.flags.get("glim", {}) as Dictionary).has("owned"), "the old bought list is gone")
	assert_false(GameState.flags.has("shop_owned"))
	# What it wore is still worn and still allowed.
	assert_eq(Glim.worn("shells"), "sunset")
	assert_eq(Glim.worn("glows"), "ember")
	assert_eq(Glim.worn("tops"), "sprout")
	assert_true(Glim.wear("tops", "beanie"), "a bought look can be put on")
	assert_eq(str(RobotDesign.parts("scoopie").get("mobility", "")), "treads")
	assert_eq(RobotDesign.livery_for("scoopie"), "livery_neon")
	assert_true(RobotBuilder.owned("top_hat"))
	assert_true(CrewLooks.has(CrewLooks.CREW, CrewLooks.LIVERY, "livery_neon"))
	# Migrating again changes nothing.
	var again: Dictionary = SaveManager.migrate(JSON.parse_string(JSON.stringify(GameState.to_dict())))
	assert_eq(again["global"][Looks.KEY], m["global"][Looks.KEY])
	GameState.from_dict(keep)
