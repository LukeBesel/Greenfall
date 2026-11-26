class_name SharedRoundtrip
extends RefCounted
## [v6flat] The shared-state half of the save round trip, on the globe. These checks used to run
## on the flat district (tools/save_roundtrip.gd before the flat world went): contracts and the
## Requests board, collectibles and livery, Lumi's designs and Character Builder look, the robot
## builder's bin and presets, robot and ship designs, Glim, the Telescope, the camp (bench, bin,
## yard builds, radio), extras (radio, CDs, album, nursery), onboarding flags, Lumi Level, animals,
## eggs and the Museum, the Bloom Core and Bloom milestones. OrbitRoundtrip.run calls setup() on
## the live globe before it saves and snap() before and after the reload; run_state() covers the
## parts that need no scene (old save versions, Homeward, save profiles).
## Robot-tied checks (per-robot builds, names, traits) live in the globe's crew round trip.

static func _style_sig(st: Dictionary) -> String:
	var n: Dictionary = LumiStyle.normalize(st)
	var bits: Array[String] = [str(n["bonus"]), str(n.get("name", ""))]
	for k: String in LumiStyle.COLOR_SLOTS:
		bits.append(LumiStyle.col(n, k).to_html(false))
	for k: String in LumiStyle.PART_SLOTS:
		bits.append(str(n[k]))
	bits.append("%.2f" % float(n["wear"]))
	return ",".join(bits)


static func _sorted(d: Dictionary) -> Dictionary:
	var keys: Array = d.keys()
	keys.sort()
	var out: Dictionary = {}
	for k: Variant in keys:
		out[k] = int(d[k])
	return out


static func _sorted_keys(d: Dictionary) -> Array:
	var k: Array = d.keys().map(func(x: Variant) -> String: return str(x))
	k.sort()
	return k


## Sets up mid-game shared state on the live globe slice `s`.
static func setup(s: Node, check: Callable) -> void:
	GameState.add_currency("cubes", BigNum.from_float(20000))
	GameState.add_currency("bolts", BigNum.from_float(60))
	Composter.add_hopper(12.0)  # [money] the press hopper
	GameState.flags["rocket_tier"] = 3
	CoreCharge.store(0.31)  # Bloom Core charge + its 25% milestone
	Bloom.done_list().append("first_meadow")  # [beat]
	GameState.flags["credits_seen"] = true
	# [events] An accepted contract, a finished one, collectibles and a livery.
	var cst: Dictionary = Contracts.state()
	cst["slots"] = [Contracts.make_offer(Contracts.template("perfect_bales"), 1), Contracts.make_offer(Contracts.template("scoop"), 0), Contracts.wait_slot(500.0)]
	Contracts.accept_slot(cst["slots"][0], 3.0)
	cst["slots"][1]["state"] = "done"
	cst["done_total"] = 4
	cst["track_done"] = 4
	Collection.grant("golden_bolt", true)
	Collection.grant("photo_moss_deer", true)
	Contracts.owned().append("livery_halo")
	GameState.flags["livery"] = "livery_halo"
	EggCollect.add("gnomes", 3)  # [eggs2] two gnomes brought home
	EggCollect.add("gnomes", 0)
	GameState.flags["museum_built"] = true
	WorldEvents.persist_state()["recent"] = ["supply_drop", "rain_shower"]
	# [onboard] Past the brief, detector explained, board open, a line WREN couldn't send.
	GameState.flags["onboard_brief"] = true
	GameState.flags["signal_explained"] = true
	GameState.flags["requests_unlocked"] = true
	GameState.flags["signal_tower"] = 2
	GameState.flags["wren_backlog"] = ["A line WREN couldn't send."]
	# [hud] Lumi XP across a couple of levels.
	if s.get("lumi_level") != null:
		s.lumi_level.add("dev", LumiLevel.need(1) + LumiLevel.need(2) + 37)
	else:
		check.call("shared_lumi_level_node", true, false)
	# [wild] Animals: a sighting and a photo.
	var fa: Fauna = s.get("fauna") as Fauna
	if fa:
		fa.mark_seen("deer")
		fa.record_photo("pigeon")
	else:
		check.call("shared_fauna_node", true, false)
	# [drones] Builder: parts in the bin, fragments, a preset, a type design.
	for id: String in ["treads", "big_eye", "rotor", "long_forks", "top_hat", "mist_sprayer"]:
		RobotBuilder.add_part(id, 2)
	RobotBuilder.add_fragments(3)
	RobotBuilder.save_preset("clean", {"mobility": "treads", "head": "big_eye", "topper": "top_hat"})
	var fl: Variant = s.get("fleet")
	if fl is Fleet:
		RobotDesign.set_field(fl as Fleet, "scoopie", "glow", "amber")  # [ui7]
	# [skins] Two designs unlocked, Nova worn, bonuses off.
	Designs.unlocked().append_array(["bolt", "nova"])
	Designs.select("nova")
	Designs.set_looks_only(true)
	# [style] A custom look on Nova's bonus, a saved look, a bought swatch.
	var look: Dictionary = LumiStyle.preset("nova")
	LumiStyle.set_value(look, "paint", Color("#3d63ff"))
	LumiStyle.set_value(look, "laser", Color("#ff5480"))
	LumiStyle.set_value(look, "hover", Color("#85ff5c"))
	look["eye_shape"] = "heart"
	look["head"] = "halo"
	look["companion"] = "drone"
	look["held"] = "medkit"
	LumiStyle.set_current(look)
	LumiStyle.save_look(1, LumiStyle.preset("bolt"), "Hazard")
	LumiStyle.bought().append("swatch:copper")
	LumiStyle.refresh_player(s)
	# [scope] The Telescope's first sighting and use stats.
	Research.grant("observatory")
	Codex.unlock("sightings:first_light")
	GameState.inc_stat("telescope_uses", 2.0)
	# [camp] The bin raised, the radio and Blink built.
	TrashBin.set_level(3)
	YardBuilds.mark_built("radio")
	YardBuilds.mark_built(CameraBot.ID)  # [camp3]
	ExtrasRoundtrip.setup(s)  # [extras] radio song, album records, a CD
	var hb: Variant = s.get("hub")
	if hb is Hub:  # the radio notes the base's level every few seconds: note it now, as the reload will
		Radio.note_planet(Audio.get_planet_theme(), (hb as Hub).level)
	# [buddy] Glim found, upgrade tiers, a bought shell and a top.
	Glim.set_found(true)
	(Glim.st()["tiers"] as Dictionary)["light"] = 2
	(Glim.st()["tiers"] as Dictionary)["scan"] = 1
	Glim.buy_look("shells", "sunset")
	Glim.wear("shells", "sunset")
	GameState.stats["hexes_cleaned"] = maxf(float(GameState.stats.get("hexes_cleaned", 0.0)), 4.0)
	Glim.wear("tops", "sprout")


## The shared state, comparable before the save and after the reload.
static func snap(s: Node) -> Dictionary:
	var patch: Node = s.get("patch")
	var model: Node = patch.get("model") if patch else null
	var parts: Array = EggCollect.parts("gnomes").duplicate()
	parts.sort()
	return {
		"press_hopper": snappedf(Composter.hopper(), 0.01),
		"currency_ids": JSON.stringify(_sorted_keys(GameState.currencies)),
		"research": JSON.stringify(Research.done_list()),
		"goals": JSON.stringify(GameState.flags.get("goals_done", [])),
		"rocket_tier": RocketTiers.tier(),
		"intro_done": GameState.flags.get("intro_done", false),
		"bloom": JSON.stringify([Bloom.done_list(), GameState.flags.get("bloom_finale_seen", false), GameState.flags.get("credits_seen", false), Bloom.ark_state()]),
		"core_charge": "%.3f %s" % [float(GameState.flags.get("core_charge", 0.0)), str(CoreCharge.beats_done())],
		"requests_done": Contracts.done_total(),
		"track_done": int(Contracts.state().get("track_done", 0)),
		"contracts": JSON.stringify(Contracts.slots().map(func(c: Dictionary) -> String: return "%s:%s:%d:%d" % [c.get("state", ""), c.get("tpl", ""), int(c.get("n", 0)), int(c.get("base", 0))])),
		"contracts_done": int(Contracts.state().get("done_total", 0)),
		"trinkets": JSON.stringify(Collection.found_list()),
		"livery": Liveries.equipped(),
		"robot_designs": JSON.stringify(GameState.flags.get("robot_designs", {})),
		"ship_style": JSON.stringify(GameState.flags.get("ship_style", {})),
		"shop_owned": JSON.stringify(Contracts.owned()),
		"events_recent": JSON.stringify(WorldEvents.persist_state().get("recent", [])),
		"lumi": "L%d xp%d total%d" % [int(LumiLevel.state()["level"]), int(LumiLevel.state()["xp"]), int(LumiLevel.state()["total"])],
		"builder_inv": JSON.stringify(_sorted(RobotBuilder.inv())),
		"builder_fragments": RobotBuilder.fragments(),
		"builder_presets": JSON.stringify(RobotBuilder.st().get("presets", {})),
		"fauna": "%s %s" % [str(GameState.flags.get("fauna_seen", [])), str(GameState.flags.get("fauna_photos", []))],
		"design": "%s %s looks_only=%s model=%s" % [Designs.current(), JSON.stringify(Designs.unlocked()), str(Designs.looks_only()), (model as PatchModel).variant if model is PatchModel else "-"],
		"lumi_style": _style_sig(LumiStyle.current()),
		"lumi_model": (_style_sig(LumiStyle.style_for_model(model)) + " laser=" + LumiStyle.laser_of(model).to_html(false) + " rig=" + str(model.get_node_or_null("LumiStyleRig") != null)) if model else "-",
		"lumi_looks": JSON.stringify(LumiStyle.looks().map(func(l: Variant) -> String: return _style_sig(l) if l is Dictionary and not (l as Dictionary).is_empty() else "-")),
		"style_bought": JSON.stringify(LumiStyle.bought()),
		"onboard": "tower=%d backlog=%d brief=%s signal=%s requests=%s" % [SignalTower.tier(), (GameState.flags.get("wren_backlog", []) as Array).size(), str(GameState.flags.get("onboard_brief", false)), str(GameState.flags.get("signal_explained", false)), str(GameState.flags.get("requests_unlocked", false))],
		"telescope": "%s uses=%d" % [str(Codex.is_unlocked("sightings:first_light")), int(GameState.stats.get("telescope_uses", 0))],
		"extras": JSON.stringify(ExtrasRoundtrip.snap(s)),
		"camera_bot": str(CameraBot.available()),
		"camp": "bench=%s bin=L%d built=%s" % [str(Camp.bench_ok()), TrashBin.level(), JSON.stringify(YardBuilds.state().get("built", {}))],
		"glim": JSON.stringify({"state": JSON.parse_string(JSON.stringify(Glim.st())), "range": snappedf(Glim.value("light", "range"), 0.01),
			"worn": [Glim.worn("shells"), Glim.worn("glows"), Glim.worn("tops")], "bot": GlimDirector.of(s) != null and GlimDirector.of(s).bot != null}),
		"egg_collect": "%s museum=%s full=%d" % [str(parts), str(Museum.built()), Museum.filled()],
	}


# --- Scene-free round trips: old save versions, Homeward, save profiles ---------------------

static func run_state(check: Callable) -> void:
	_homeward_roundtrip(check)  # [home] the system campaign's profile state
	_profiles_roundtrip(check)  # [worlds2] save profiles: migration into p1, profiles kept apart
	_old_save_migration(check)  # [money] a v1 save with the old currencies loads into the three
	_v2_save_migration(check)  # [ui2] robot part items -> Parts


## [money] A v1 save (nine currencies) loads into the three.
static func _old_save_migration(check: Callable) -> void:
	GameState.new_game()
	var d: Dictionary = GameState.to_dict()
	d["version"] = 1
	var old: Dictionary = {"cubes": 2000.0, "seeds": 15.0, "bolts": 40.0, "sheet_metal": 120.0, "plastic_stock": 60.0,
		"glass_cullet": 30.0, "data": 75.0, "compost": 9.0, "tokens": 11.0, "trinkets": 3.0}
	var cur: Dictionary = {}
	for k: String in old:
		cur[k] = BigNum.from_float(float(old[k])).serialize()
	d["currencies"] = cur
	d["flags"]["builder"] = {"inv": {"treads": 1}, "fragments": 2}
	d["parts"] = [{"type": 0, "rarity": 0}, {"type": 3, "rarity": 3}]  # [ui2] robot part items -> Parts (v3)
	SaveManager.write_dict(SaveManager.slot_path(), d)
	Currencies.warn_legacy = false
	var ok: bool = SaveManager.load_game()
	Currencies.warn_legacy = true
	check.call("old_save_loads", true, ok)
	check.call("old_save_version", GameState.SAVE_VERSION, int(GameState.to_dict()["version"]))
	check.call("old_save_ids", JSON.stringify(["cubes", "parts", "seeds"]), JSON.stringify(_sorted_keys(GameState.currencies)))
	check.call("old_save_cubes", 2000.0 + 75.0 * 10.0 + 3.0 * 150.0, snappedf(GameState.get_currency("cubes").to_float(), 0.01))
	check.call("old_save_parts", 40.0 * 5.0 + 120.0 + 60.0 + 30.0 + 11.0 * 5.0 + 2.0 * 25.0 + 10.0 + 150.0, snappedf(GameState.get_currency("parts").to_float(), 0.01))
	check.call("old_save_no_part_items", 0, GameState.parts.size())  # [ui2]
	check.call("old_save_seeds", 15.0, snappedf(GameState.get_currency("seeds").to_float(), 0.01))
	check.call("old_save_hopper", 9.0, snappedf(Composter.hopper(), 0.01))
	check.call("old_save_builder_inv", 1, RobotBuilder.count("treads"))
	check.call("old_save_pace_baler", true, Pace.baler_unlocked())  # [pace] old saves keep their bale press
	check.call("old_save_pace_lift", Pace.SIZE_LARGE, Pace.lift_class())
	check.call("old_save_pace_chest", true, Economy.stat("capacity") >= 30.0)


## [ui2] A v2 save (three currencies, robot part items in storage) -> v4 (via pace v3): the items become Parts
## at their rarity's value; nothing else changes.
static func _v2_save_migration(check: Callable) -> void:
	GameState.new_game()
	var d: Dictionary = GameState.to_dict()
	d["version"] = 2
	d["currencies"]["parts"] = BigNum.from_float(100.0).serialize()
	d["parts"] = [{"type": 0, "rarity": 0}, {"type": 1, "rarity": 1}, {"type": 3, "rarity": 2}, {"type": 3, "rarity": 4}]
	d["flags"]["tier_scoopie"] = 1
	SaveManager.write_dict(SaveManager.slot_path(), d)
	var ok: bool = SaveManager.load_game()
	check.call("v3_save_loads", true, ok)
	check.call("v4_save_version", GameState.SAVE_VERSION, int(GameState.to_dict()["version"]))
	check.call("v3_parts_from_items", 100.0 + 10.0 + 25.0 + 60.0 + 450.0, snappedf(GameState.get_currency("parts").to_float(), 0.01))
	check.call("v3_no_items_left", 0, GameState.parts.size())
	check.call("v3_tier_kept", 1, int(GameState.flags.get("tier_scoopie", 0)))


## [home] Homeward: the system campaign lives in the profile.
static func _homeward_roundtrip(check: Callable) -> void:
	var keep_profile: Dictionary = CradleMode.profile.duplicate(true)
	var keep_persist: bool = CradleMode.persist
	var keep_slot: int = SaveManager.slot
	CradleMode.path_override = SaveManager.save_dir().path_join("roundtrip_homeward.save")
	CradleMode.persist = true
	CradleMode.profile = CradleMode.default_profile()
	var hs: Dictionary = Homeward.state()
	hs["answered"] = true
	hs["drive"] = 6
	hs["picks"] = 2
	hs["rocket_tier"] = 4
	(hs["pct"] as Dictionary)["verdance"] = 1.0
	(hs["pct"] as Dictionary)["ochre"] = 1.0
	(hs["pct"] as Dictionary)["tidewell"] = 0.62
	hs["relics"] = ["ochre_glass"]
	hs["beats"] = ["ochre_arrive", "ochre_half", "ochre_restored"]
	hs["seen"] = ["rime"]  # [sysmap2] spotted by the telescope
	var w: Dictionary = Homeward.make_planet_world(2)
	CradleMode.save_profile()
	var before: String = JSON.stringify(CradleMode.to_dict())
	CradleMode.profile = {}
	CradleMode.load_profile()
	check.call("home_profile_roundtrip", str(JSON.parse_string(before)), str(JSON.parse_string(JSON.stringify(CradleMode.to_dict()))))
	check.call("home_answered", true, Homeward.answered())
	check.call("home_drive", 6, Homeward.drive())
	check.call("home_picks", 2, Homeward.picks())
	check.call("home_relics", ["ochre_glass"], Homeward.relics())
	check.call("home_beat", true, Homeward.beat_done("ochre_half"))
	check.call("home_seen", ["rime"], Homeward.state().get("seen", []))
	check.call("home_rime_discovered", true, Homeward.discovered(3))
	check.call("home_pct_tidewell", 0.62, snappedf(Homeward.stored_pct(2), 0.01))
	check.call("home_system_pct", snappedf((1.0 + 1.0 + 0.62) / 5.0, 0.001), snappedf(Homeward.system_pct(), 0.001))
	check.call("home_planet_world", 1, Homeward.world_of(2))
	CradleMode.profile["current"] = Homeward.world_of(2)
	check.call("home_planet_current", 2, Homeward.current_planet())
	check.call("home_planet_name", "Tidewell", CradleMode.world_name())
	check.call("home_planet_seed", int(Homeward.planet_def(2)["seed"]), CradleMode.world_seed())
	check.call("home_planet_type_mix", JSON.stringify(WorldGen.world_type("ocean_world").get("mix", {}).get("water_fraction")), JSON.stringify(CradleMode.planet_mix().get("water_fraction")))
	check.call("home_planet_slot", int(w["slot"]), int(CradleMode.current_world()["slot"]))
	DirAccess.remove_absolute(CradleMode.profile_path())
	CradleMode.path_override = ""
	CradleMode.persist = keep_persist
	CradleMode.profile = keep_profile
	SaveManager.slot = keep_slot


## Old flat saves migrate into profile 1 intact; a second profile's world, profile and slot stay
## apart from the first's; both load back as they were.
static func _profiles_roundtrip(check: Callable) -> void:
	var root: String = "user://roundtrip_profiles"
	var keep: Array = [SaveManager.dev_dir, SaveManager.profile_slot, SaveManager.slot, CradleMode.profile.duplicate(true),
		CradleMode.persist, CradleMode.path_override, GameState.to_dict()]
	# Migration: a pre-profile folder (one slot and a profile) moves into p1 unchanged.
	DirAccess.make_dir_recursive_absolute(root)
	var legacy_save: Dictionary = GameState.to_dict()
	SaveManager.write_dict(root.path_join("slot_0.save"), legacy_save)
	var lp: Dictionary = CradleMode.default_profile()
	lp["starseeds"] = 21.0
	SaveManager.write_dict(root.path_join("profile.save"), lp)
	check.call("profiles_migrated", 2, SaveManager.migrate_to_profiles(root))
	var back: Dictionary = SaveManager.read_dict(root.path_join("p1/slot_0.save"))
	check.call("profiles_migrated_save", JSON.stringify(JSON.parse_string(JSON.stringify(legacy_save.get("currencies")))), JSON.stringify(back.get("currencies")))
	check.call("profiles_migrated_profile", 21.0, float(CradleMode.from_dict(SaveManager.read_dict(root.path_join("p1/profile.save")))["starseeds"]))
	# Isolation through the real SaveManager / CradleMode paths, in a scratch save dir.
	SaveManager.dev_dir = "roundtrip_profiles_live"
	CradleMode.path_override = ""
	CradleMode.persist = true
	SaveManager.slot = 0
	SaveManager.set_profile(1)
	CradleMode.profile = CradleMode.default_profile()
	CradleMode.profile["starseeds"] = 11.0
	CradleMode._add_world()
	CradleMode.save_profile()
	GameState.flags["profile_marker"] = "one"
	SaveManager.save_game(false)
	SaveManager.set_profile(2)
	CradleMode.reload_for_profile()
	check.call("profiles_p2_fresh_worlds", 1, CradleMode.worlds().size())
	check.call("profiles_p2_no_save", false, SaveManager.has_save(0))
	CradleMode.profile["starseeds"] = 22.0
	CradleMode.profile["name"] = "Second"
	CradleMode.save_profile()
	GameState.flags["profile_marker"] = "two"
	SaveManager.save_game(false)
	SaveManager.set_profile(1)
	CradleMode.reload_for_profile()
	SaveManager.load_game()
	check.call("profiles_p1_back", "one|11|2", "%s|%d|%d" % [GameState.flags.get("profile_marker"), int(CradleMode.starseeds()), CradleMode.worlds().size()])
	SaveManager.set_profile(2)
	CradleMode.reload_for_profile()
	SaveManager.load_game()
	check.call("profiles_p2_back", "two|22|Second", "%s|%d|%s" % [GameState.flags.get("profile_marker"), int(CradleMode.starseeds()), ProfileSlots.summary(2)["name"]])
	# Clean up both scratch roots.
	for n: int in range(1, SaveManager.PROFILES + 1):
		SaveManager.delete_profile(n)
	for f: String in ["p1/slot_0.save", "p1/profile.save"]:
		DirAccess.remove_absolute(root.path_join(f))
	SaveManager.dev_dir = keep[0]
	SaveManager.profile_slot = keep[1]
	SaveManager.slot = keep[2]
	CradleMode.profile = keep[3]
	CradleMode.persist = keep[4]
	CradleMode.path_override = keep[5]
	GameState.from_dict(keep[6])
