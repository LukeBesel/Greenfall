extends GutTest
## [worlds2] Cradle Mode world looks (systems/world_look.gd, data/world_looks.json), the landmark
## and sky body builders, WREN's world threads (systems/world_story.gd), the title screen world
## picker (ui/world_picker.gd, CradleMode.select_world) and the profile's Steam Cloud stamp.

const TMP_DIR: String = "user://test_world_look"

var _keep: Array
var _profile: Dictionary
var _dir: String
var _slot: int


func before_each() -> void:
	_keep = [GameState.currencies.duplicate(), GameState.flags.duplicate(true), GameState.stats.duplicate(true), GameState.world,
		GameState.districts, GameState.current_hub, Economy.planet.get("name", "Verdance"), CradleMode.persist, CradleMode.path_override]
	_profile = CradleMode.profile.duplicate(true)
	_dir = SaveManager.dev_dir
	_slot = SaveManager.slot
	SaveManager.dev_dir = "worlds2_test"
	DirAccess.make_dir_recursive_absolute(SaveManager.save_dir())
	CradleMode.persist = false
	CradleMode.profile = CradleMode.default_profile()
	WorldLook.override_type = ""
	GameState.currencies = {}
	GameState.flags = {}
	GameState.stats = {}
	GameState.world = {}
	GameState.districts = {0: GameState.world}
	GameState.current_hub = 0


func after_each() -> void:
	for s: int in 12:
		SaveManager.delete_save(s)
	SaveManager.dev_dir = _dir
	SaveManager.slot = _slot
	CradleMode.profile = _profile
	CradleMode.persist = _keep[7]
	CradleMode.path_override = _keep[8]
	WorldLook.override_type = ""
	GameState.currencies = _keep[0]
	GameState.flags = _keep[1]
	GameState.stats = _keep[2]
	GameState.world = _keep[3]
	GameState.districts = _keep[4]
	GameState.current_hub = _keep[5]
	GameState.reload_in_memory = false
	Economy.planet["name"] = _keep[6]
	SteamService.detach()
	if DirAccess.dir_exists_absolute(TMP_DIR):
		for f: String in DirAccess.get_files_at(TMP_DIR):
			DirAccess.remove_absolute(TMP_DIR.path_join(f))
		DirAccess.remove_absolute(TMP_DIR)


# --- Look selection ------------------------------------------------------------------------

func test_every_world_type_has_its_own_look() -> void:
	var landmarks: Array = []
	var styles: Array = []
	var tints: Array = []
	for t: Dictionary in WorldGen.cfg()["world_types"]:
		var lk: Dictionary = WorldLook.look_for(str(t["id"]))
		assert_false(lk.is_empty(), "%s has a look" % t["id"])
		assert_false((lk.get("grade", {}) as Dictionary).is_empty(), "%s has a sky grade" % t["id"])
		assert_ne(WorldLook.landmark(lk), "", "%s has a landmark" % t["id"])
		landmarks.append(WorldLook.landmark(lk))
		styles.append(WorldLook.city_style(lk))
		tints.append(WorldLook.city_tint(lk).to_html())
	for arr: Array in [landmarks, styles]:
		for i: int in arr.size():
			assert_eq(arr.count(arr[i]), 1, "%s is unique to one world type" % str(arr[i]))
	assert_eq(styles, ["frosted", "bleached", "coastal", "overgrown", "corroded"])
	assert_eq(WorldLook.type_ids().size(), (WorldGen.cfg()["world_types"] as Array).size(), "no look without a world type")


func test_verdance_has_no_look() -> void:
	assert_true(WorldLook.look_for("verdance").is_empty())
	assert_true(WorldLook.current().is_empty(), "world 0 keeps the campaign's look")
	assert_eq(WorldLook.city_tint({}), Color.WHITE)


func test_current_follows_the_current_world() -> void:
	for i: int in 5:
		CradleMode._add_world()
	for i: int in range(1, 6):
		CradleMode.profile["current"] = i
		var want: String = str(CradleMode.worlds()[i]["type"])
		assert_eq(str(WorldLook.current().get("type", "")), want, "world %d" % i)
		assert_eq(WorldLook.current().get("mods"), CradleMode.worlds()[i]["modifiers"])


func test_ice_moon_sky_has_a_ringed_planet_and_desert_is_amber() -> void:
	var ice: Dictionary = WorldLook.look_for("ice_moon")
	assert_eq(str(ice["sky_body"]["kind"]), "ringed")
	var desert: Dictionary = WorldLook.look_for("desert_world")
	var mie: Color = WorldLook.col(desert["grade"]["mie"])
	assert_gt(mie.r, mie.b + 0.3, "hot amber haze")
	var rust: Dictionary = WorldLook.look_for("rust_world")
	assert_gt(WorldLook.col(rust["grade"]["rayleigh"]).r, WorldLook.col(rust["grade"]["rayleigh"]).b, "rust-red sky")
	assert_gt(float(rust.get("dust", 0.0)), 0.0, "with dust")
	var ocean: Dictionary = WorldLook.look_for("ocean_world")
	assert_gt(float(ocean["dress"]["puddles"]), 1.0, "more water in the yard")
	assert_eq(float(desert["dress"]["puddles"]), 0.0, "and none in the desert")


func test_modifiers_show_in_the_look() -> void:
	var base: Dictionary = WorldLook.look_for("ocean_world")
	var rain: Dictionary = WorldLook.look_for("ocean_world", ["heavy_rain"])
	assert_almost_eq(float(rain["dress"]["puddles"]), float(base["dress"]["puddles"]) * 2.2, 0.001, "Heavy Rain: more puddles")
	assert_gt(float(rain["grade"]["fog_mult"]), float(base["grade"]["fog_mult"]))
	assert_eq(float(base.get("night_dark", 0.0)), 0.0)
	assert_gt(float(WorldLook.look_for("ocean_world", ["long_nights"]).get("night_dark", 0.0)), 0.3, "Long Nights: darker nights")
	# Junk: Rich Salvage shines (metal, low roughness), even on a world without a coat.
	var plain: Dictionary = WorldLook.junk_coat([], base)
	assert_true(plain.is_empty(), "nothing to coat")
	var rich: Dictionary = WorldLook.junk_coat([], WorldLook.look_for("ocean_world", ["rich_salvage"]))
	assert_gt(float(rich["metal"]), 0.3)
	assert_lt(float(rich["roughness"]), 0.25)
	var ice_coat: Array = WorldGen.world_type("ice_moon")["coat"]
	var ice_rich: Dictionary = WorldLook.junk_coat(ice_coat, WorldLook.look_for("ice_moon", ["rich_salvage"]))
	assert_lt(float(ice_rich["top"]), float(ice_coat[3]), "less frost over the good stuff")
	var wet: Dictionary = WorldLook.junk_coat(ice_coat, WorldLook.look_for("ice_moon", ["heavy_rain"]))
	assert_lt(float(wet["roughness"]), float(ice_coat[5]), "Heavy Rain: wet junk")


func test_the_look_eases_as_the_district_is_restored() -> void:
	assert_eq(WorldLook.progress(1, 0.0), 0.0)
	assert_almost_eq(WorldLook.progress(3, 0.1), 0.5, 0.001)
	assert_almost_eq(WorldLook.progress(1, 0.8), 0.8, 0.001)
	assert_eq(WorldLook.progress(5, 0.0), 1.0)
	for id: String in WorldLook.type_ids():
		var lk: Dictionary = WorldLook.look_for(id)
		assert_eq(WorldLook.grade_amount(lk, 0.0), 1.0)
		var done: float = WorldLook.grade_amount(lk, 1.0)
		assert_lt(done, 1.0, "%s clears up" % id)
		assert_gt(done, 0.45, "%s keeps its identity" % id)
	assert_gt(WorldLook.weather_amount(0.0), WorldLook.weather_amount(1.0))


# --- Builders ------------------------------------------------------------------------------

func test_landmarks_build_with_their_layers() -> void:
	for id: String in WorldLook.type_ids():
		var kind: String = WorldLook.landmark(WorldLook.look_for(id))
		var lm := WorldLandmark.make(kind, Vector3(0, 0, -100), 0.0, 7, 1)
		add_child_autofree(lm)
		for layer: String in ["Base", "Ruin", "Mended", "Glow"]:
			assert_not_null(lm.get_node_or_null(layer), "%s has a %s layer" % [kind, layer])
		assert_true((lm.get_node("Ruin") as Node3D).visible, "ruined at level 1")
		assert_false((lm.get_node("Glow") as Node3D).visible)
		lm.set_level(4)
		assert_false((lm.get_node("Ruin") as Node3D).visible)
		assert_true((lm.get_node("Mended") as Node3D).visible)
		assert_true((lm.get_node("Glow") as Node3D).visible, "thin trim lights once restored")
		var aabb := AABB()
		for mi: Node in lm.get_node("Base").get_children():
			aabb = aabb.merge((mi as MeshInstance3D).get_aabb()) if aabb.size != Vector3.ZERO else (mi as MeshInstance3D).get_aabb()
		assert_gt(aabb.size.y, 18.0, "%s stands tall" % kind)


func test_landmark_spot_is_in_view_and_off_the_field() -> void:
	var p: Vector3 = WorldLandmark.find_spot(null, null, 42)
	assert_lt(p.z, -40.0, "toward the default view")
	assert_between(Vector2(p.x, p.z).length(), WorldLandmark.MIN_D - 1.0, WorldLandmark.MAX_D + 40.0)


func test_sky_bodies() -> void:
	var sd := SkyDirector.new()
	add_child_autofree(sd)
	var ice := SkyBody.make(WorldLook.look_for("ice_moon")["sky_body"], sd)
	add_child_autofree(ice)
	assert_eq(ice.get_child_count(), 1)
	var desert := SkyBody.make(WorldLook.look_for("desert_world")["sky_body"], sd)
	add_child_autofree(desert)
	assert_eq(desert.get_child_count(), 2, "twin moons over the desert")
	var d: Vector3 = WorldLook.sky_dir({"yaw": 180.0, "elev": 30.0})
	assert_almost_eq(d.y, 0.5, 0.001)
	assert_lt(d.z, -0.8)
	assert_false(WorldLook.look_for("fungal_world").has("sky_body"), "the marsh mist hides the sky")


# --- WREN's world thread -------------------------------------------------------------------

func test_story_beats_in_order() -> void:
	assert_eq(WorldStory.next_beat(0.0, 1, false, []), "arrival")
	assert_eq(WorldStory.next_beat(0.1, 1, false, ["arrival"]), "", "memory waits for progress")
	assert_eq(WorldStory.next_beat(0.25, 1, false, ["arrival"]), "memory_1")
	assert_eq(WorldStory.next_beat(0.9, 1, false, ["arrival"]), "memory_1", "one beat at a time, in order")
	assert_eq(WorldStory.next_beat(0.55, 3, false, ["arrival", "memory_1"]), "halfway")
	assert_eq(WorldStory.next_beat(0.75, 4, false, ["arrival", "memory_1", "halfway"]), "memory_2")
	var all4: Array = ["arrival", "memory_1", "halfway", "memory_2"]
	assert_eq(WorldStory.next_beat(0.8, 4, false, all4), "")
	assert_eq(WorldStory.next_beat(0.8, 5, false, all4), "restored", "base level 5 restores")
	assert_eq(WorldStory.next_beat(0.3, 3, true, all4), "restored", "so does the finale")
	assert_eq(WorldStory.next_beat(1.0, 5, true, all4 + ["restored"]), "")


func test_every_world_type_has_wren_lines_for_every_beat() -> void:
	var lines: Dictionary = Economy.planet_table("guide_lines")
	for t: Dictionary in WorldGen.cfg()["world_types"]:
		for b: String in WorldStory.BEATS:
			var pools: Array = lines.get(WorldStory.trigger(str(t["id"]), b), [])
			assert_false(pools.is_empty() or (pools[0] as Array).is_empty(), "%s %s" % [t["id"], b])


func test_planet_ids_map_onto_looks_and_lines() -> void:
	var cfg: Dictionary = WorldLook.cfg()
	var keep: Variant = cfg.get("planets", {})
	cfg["planets"] = {"frost_moon": "ice_moon", "scrap_belt": {"look": "rust_world", "landmark": "cryo_spire"}}
	assert_eq(str(WorldLook.look_for_planet("frost_moon").get("type")), "ice_moon")
	var sb: Dictionary = WorldLook.look_for_planet("scrap_belt", ["long_nights"])
	assert_eq(str(sb["type"]), "rust_world")
	assert_eq(WorldLook.landmark(sb), "cryo_spire", "a planet can override its type's landmark")
	assert_gt(float(sb.get("night_dark", 0.0)), 0.0)
	assert_eq(str(WorldLook.look_for_planet("desert_world")["type"]), "desert_world", "a look type is its own planet id")
	assert_true(WorldLook.look_for_planet("nowhere").is_empty())
	cfg["planets"] = keep
	var lines: Dictionary = {"world_frost_moon_arrival": [["x"]], "world_ice_moon_arrival": [["y"]], "world_ice_moon_halfway": [["z"]]}
	assert_eq(WorldStory.pick_trigger(["frost_moon", "ice_moon"], "arrival", lines), "world_frost_moon_arrival", "a planet's own line first")
	assert_eq(WorldStory.pick_trigger(["frost_moon", "ice_moon"], "halfway", lines), "world_ice_moon_halfway", "then its look's")


func test_a_planet_env_script_is_called() -> void:
	var path: String = "user://test_planet_env.gd"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("extends Node\nvar got: Array = []\nfunc apply(world: Node, field: Variant, kind: String) -> void:\n\tgot = [world.name, field, kind]\n")
	f.close()
	var keep: Dictionary = WorldLook._planets
	WorldLook._planets = {"testp": {"env": path, "look": "ice_moon"}}
	CradleMode._add_world()
	CradleMode.profile["current"] = 1
	(CradleMode.worlds()[1] as Dictionary)["planet"] = "testp"
	assert_eq(WorldLook.planet_id(), "testp")
	assert_eq(str(WorldLook.current().get("type")), "ice_moon", "the registry maps the planet onto a look")
	var slice := Node.new()
	slice.name = "FakeSlice"
	add_child_autofree(slice)
	var v: WorldLookView = WorldLookView.attach(slice)
	assert_not_null(v)
	var env: Node = slice.get_node_or_null("PlanetEnv")
	assert_not_null(env, "the planet's env joins the district")
	assert_eq(str(env.get("got")), str([&"FakeSlice", null, "city"]))
	assert_null(slice.get_node_or_null("WorldLandmark"), "the env owns the planet's art")
	WorldLook._planets = keep
	DirAccess.remove_absolute(path)


func test_wren_speaks_world_lines_clearly() -> void:
	var w := Wren.new()
	add_child_autofree(w)
	GameState.flags["wren_awake"] = true
	GameState.flags["signal_tower"] = 1  # [onboard] WREN talks through the Signal Tower
	var got: Array = []
	w.line_started.connect(func(text: String, st: int) -> void: got.append([text, st]))
	w.say(WorldStory.trigger("rust_world", "memory_1"), 1.0, true, {}, 2)
	w._process(0.1)
	assert_eq(got.size(), 1)
	assert_eq(int(got[0][1]), 2, "the ark relay is clear")
	assert_string_contains(str(got[0][0]), "Ledger")


# --- World picker ----------------------------------------------------------------------------

func test_picker_lists_every_world_and_chains_focus() -> void:
	WorldPicker.dev_sample(3)
	var p := WorldPicker.new()
	add_child_autofree(p)
	assert_eq(p.rows.size(), CradleMode.worlds().size())
	assert_eq(p.rows.size(), 4)
	assert_eq(p.rows[0].get_node(p.rows[0].focus_neighbor_bottom), p.rows[1], "down moves to the next world")
	assert_eq(p.rows[0].get_node(p.rows[0].focus_neighbor_top), p.back, "and wraps to Back")
	var got: Array = []
	p.picked.connect(func(i: int) -> void: got.append(i))
	p.rows[2].pressed.emit()
	assert_eq(got, [2])
	assert_string_contains(WorldPicker.status_line(CradleMode.worlds()[1], 1), "restored")
	assert_eq(WorldPicker.status_line({}, 3), TranslationServer.translate("Not visited yet"))


func test_select_world_points_continue_at_it() -> void:
	CradleMode._add_world()
	CradleMode._add_world()
	# World 1 has a save; world 2 has never been played.
	CradleMode.profile["current"] = 1
	CradleMode.apply_current()
	GameState.flags["achievements"] = {"hex_1": 1.0}
	GameState.flags["marker"] = "w1"
	assert_true(SaveManager.write_dict(SaveManager.slot_path(), GameState.to_dict()))
	assert_true(CradleMode.select_world(2))
	assert_eq(CradleMode.current_index(), 2)
	assert_eq(SaveManager.slot, int(CradleMode.worlds()[2]["slot"]))
	assert_true(GameState.reload_in_memory, "a fresh world starts from a prepared state")
	assert_true(bool(GameState.flags.get("late_new_world", false)), "with its arrival")
	assert_eq(JSON.stringify(GameState.flags.get("achievements")), JSON.stringify({"hex_1": 1.0}), "achievements carry over")
	GameState.reload_in_memory = false
	assert_true(CradleMode.select_world(1))
	assert_eq(SaveManager.slot, int(CradleMode.worlds()[1]["slot"]))
	assert_false(GameState.reload_in_memory, "a world with a save loads it")
	assert_false(CradleMode.select_world(9))


# --- Steam Cloud ---------------------------------------------------------------------------

class FakeCloud:
	extends Object
	var files: Dictionary = {}
	var cloud_on: bool = false
	func isSteamRunning() -> bool: return true
	func setAchievement(_n: String) -> bool: return true
	func getAchievement(_n: String) -> Dictionary: return {"ret": true, "achieved": false}
	func setStatInt(_n: String, _v: int) -> bool: return true
	func setStatFloat(_n: String, _v: float) -> bool: return true
	func storeStats() -> bool: return true
	func isCloudEnabledForAccount() -> bool: return cloud_on
	func isCloudEnabledForApp() -> bool: return cloud_on
	func fileWrite(n: String, data: PackedByteArray, _size: int = 0) -> bool:
		files[n] = data
		return true
	func fileRead(n: String, _size: int) -> Dictionary: return {"ret": files.has(n), "buf": files.get(n, PackedByteArray())}
	func fileExists(n: String) -> bool: return files.has(n)
	func getFileSize(n: String) -> int: return (files.get(n, PackedByteArray()) as PackedByteArray).size()
	func getFileCount() -> int: return files.size()
	func getFileNameAndSize(i: int) -> Dictionary: return {"name": files.keys()[i], "size": 0}


func test_profile_is_stamped_and_synced_to_steam_cloud() -> void:
	var fake := FakeCloud.new()
	assert_true(SteamService.attach(fake, false))
	fake.cloud_on = true  # after attach: its start-up sync never touches the real save folder
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	CradleMode.persist = true
	CradleMode.path_override = TMP_DIR.path_join(CradleMode.PROFILE_FILE)
	CradleMode.profile["starseeds"] = 7.0
	assert_true(CradleMode.save_profile())
	assert_true(fake.files.has("profile.save"), "the profile is uploaded with the world slots")
	var stamp: float = SteamCloud.saved_unix_of_bytes(fake.files["profile.save"])
	assert_gt(stamp, 1.0e9, "it carries a save time, so newest-wins works")
	# A newer profile in the cloud (another PC) wins on the next start-up sync.
	var newer: Dictionary = CradleMode.to_dict()
	newer["saved_unix"] = stamp + 100.0
	newer["starseeds"] = 99.0
	var tmp: String = TMP_DIR.path_join("other.tmp")
	SaveManager.write_dict(tmp, newer)
	fake.files["profile.save"] = FileAccess.get_file_as_bytes(tmp)
	DirAccess.remove_absolute(tmp)
	var res: Dictionary = SteamCloud.new(fake).sync_dir(TMP_DIR)
	assert_eq(res.get("profile.save"), "cloud")
	CradleMode.load_profile()
	assert_almost_eq(CradleMode.starseeds(), 99.0, 0.001)
	SteamService.detach()
	fake.free()


# --- Binary sun ----------------------------------------------------------------------------

func test_binary_sun_defaults_and_geometry() -> void:
	var s: Dictionary = BinarySun.suns_for("verdance")
	assert_lt(float(s["b"]["size"]), float(s["a"]["size"]), "the companion is the smaller star")
	assert_lt(float(s["b"]["energy"]), float(s["a"]["energy"]))
	var cb: Color = BinarySun.color_of(s["b"]["color"], Color.WHITE)
	assert_gt(cb.r, cb.b + 0.3, "and the cooler, orange-red one")
	assert_almost_eq(BinarySun.separation_of(s), 14.0, 0.001)
	assert_almost_eq(BinarySun.separation_of({"a": {"dir": Vector3(1, 0, 0)}, "b": {"dir": Vector3(0, 0, 1)}}), 90.0, 0.01)
	var bs := BinarySun.new()
	bs.separation_deg = 20.0
	var to_a := Vector3(0.3, 0.5, -0.8).normalized()
	var to_b: Vector3 = bs.companion_dir(to_a)
	assert_almost_eq(to_b.y, to_a.y, 0.0001, "same height: they rise and set together")
	assert_almost_eq(rad_to_deg(Vector2(to_a.x, to_a.z).angle_to(Vector2(to_b.x, to_b.z))), -20.0, 0.01)
	bs.free()


func test_every_sky_has_two_suns() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = PhysicalSkyMaterial.new()
	env.sky = sky
	var sun := DirectionalLight3D.new()
	add_child_autofree(sun)
	var sd := SkyDirector.new()
	add_child_autofree(sd)
	sd.setup(env, sun)
	assert_not_null(sd.binary, "Verdance too")
	assert_eq(sd.binary.planet_id, "verdance")
	sd.time_of_day = 0.5
	sd._apply()
	assert_gt(sd.binary.fill.light_energy, 0.0, "the companion's warm fill at noon")
	assert_false(sd.binary.fill.shadow_enabled, "unshadowed (the primary carries shadows)")
	assert_gt(sun.light_energy, sd.binary.fill.light_energy)
	sd.time_of_day = 0.0
	sd._apply()
	assert_false(sd.binary.fill.visible, "both suns are down at midnight")
