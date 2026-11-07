extends Node
## Save/load round-trip check for every system that persists.
## Run: godot --headless --path . res://tools/save_roundtrip.tscn -- --fresh --stations=all --unlock-seeds --clean-hexes=3
## Builds a mid-game state in one slice, saves to a temp slot, loads it into a second slice and
## compares. Prints PASS/FAIL lines and exits with code 1 on any failure.

var _fails: int = 0


func _check(name_: String, a: Variant, b: Variant) -> void:
	var ok: bool = str(a) == str(b)
	print("[roundtrip] %s %s: %s -> %s" % ["PASS" if ok else "FAIL", name_, str(a), str(b)])
	if not ok:
		_fails += 1


func _snapshot(s: Node) -> Dictionary:
	var f: Fleet = s.fleet
	var types: Array = []
	for r: Robot in f.robots():
		types.append("%s@%d" % [r.type_id, r.tier])
	types.sort()
	var planted: int = 0
	for sp: int in s.garden.slot_species:
		if sp >= 0:
			planted += 1
	var lv: Array = []
	if s.get("hex_levels") != null:
		for h: int in s.field.hex_count():
			lv.append(s.hex_levels.level_of(h))
	return {
		"cubes": snappedf(GameState.get_currency("cubes").to_float(), 0.01),
		"seeds": snappedf(GameState.get_currency("seeds").to_float(), 0.01),
		"compost": snappedf(GameState.get_currency("compost").to_float(), 0.01),
		"robots": types,
		"orders": JSON.stringify(GameState.world.get("orders", {})),
		"cleaned": s.field.cleaned_count,
		"alive": s.field.piece_alive.count(1),
		"planted": planted,
		"hex_levels": lv,
		"composter": s.composter.level,
		"stations": JSON.stringify(_built(s)),
		"tanks": s.fleet.water_net.tanks.size() if s.fleet.get("water_net") != null else -1,
		"research": JSON.stringify(Research.done_list()),
		"goals": JSON.stringify(GameState.flags.get("goals_done", [])),
		"hub_level": s.hub.level,
		"rocket_tier": RocketTiers.tier(),
		"intro_done": GameState.flags.get("intro_done", false),
		"bloom": JSON.stringify([Bloom.done_list(), GameState.flags.get("bloom_finale_seen", false), GameState.flags.get("credits_seen", false), Bloom.ark_state()]),  # [beat]
		"core_charge": "%.3f %s" % [float(GameState.flags.get("core_charge", 0.0)), str(CoreCharge.beats_done())],
		"tagged_cubes": _tagged_cubes(s),
		"outposts": _outposts(s),
		# [events] contracts board (timers excluded: they tick), tokens, collection, livery, shop.
		"tokens": Contracts.tokens(),
		"contracts": JSON.stringify(Contracts.slots().map(func(c: Dictionary) -> String: return "%s:%s:%d:%d" % [c.get("state", ""), c.get("tpl", ""), int(c.get("n", 0)), int(c.get("base", 0))])),
		"contracts_done": int(Contracts.state().get("done_total", 0)),
		"trinkets": JSON.stringify(Collection.found_list()),
		"livery": Liveries.equipped(),
		"shop_owned": JSON.stringify(Contracts.owned()),
		"events_recent": JSON.stringify(WorldEvents.persist_state().get("recent", [])),
		# [hud] Lumi Level (level, XP into it, lifetime XP).
		"lumi": "L%d xp%d total%d" % [int(LumiLevel.state()["level"]), int(LumiLevel.state()["xp"]), int(LumiLevel.state()["total"])],
		# [drones] robot builder: parts bin, fragments, presets, per-robot builds, traits and names.
		"builder_inv": JSON.stringify(_sorted(RobotBuilder.inv())),
		"builder_fragments": RobotBuilder.fragments(),
		"builder_presets": JSON.stringify(RobotBuilder.st().get("presets", {})),
		"builds": _builds(f),
		"fauna": _fauna(s),  # [wild]
		# [skins] Lumi's designs: worn, unlocked, looks-only, and the model actually built with it.
		"design": "%s %s looks_only=%s model=%s" % [Designs.current(), JSON.stringify(Designs.unlocked()), str(Designs.looks_only()), (s.patch.model as PatchModel).variant],
		# [late] Garden Mode decorations and their charm; Cradle Mode world tag.
		"decor": JSON.stringify(GameState.world.get("decor", {})),
		"decor_charm": snappedf(float(GameState.world.get("decor_charm", 0.0)), 0.01),
		"world_index": int(GameState.flags.get("world_index", 0)),
		"extras": JSON.stringify(ExtrasRoundtrip.snap(s)),  # [extras] radio, album, nursery
	}


## [wild] Persisted animal state, plus whether the adopted cat is back in the live district.
func _fauna(s: Node) -> String:
	var named: String = "-"
	if s.get("fauna") != null:
		s.fauna.replan()
		for a: Fauna.Animal in s.fauna.animals:
			if a.named:
				named = a.cat_name
	return "%s %s %s %s live=%s" % [str(GameState.flags.get("fauna_seen", [])), str(GameState.flags.get("fauna_photos", [])),
		str(GameState.flags.get("fauna_cat", {}).get("name", "")), str(int(GameState.flags.get("fauna_cat", {}).get("coat", -1))), named]


## [drones] "name:trait:slot=part,..." per robot, sorted.
func _builds(f: Fleet) -> Array:
	var out: Array = []
	for r: Robot in f.robots():
		var bits: Array = []
		for k: String in RobotBuilder.SLOTS:
			if r.build.has(k):
				bits.append("%s=%s" % [k, r.build[k]])
		out.append("%s:%s:%s:%.3f" % [r.robot_name, r.trait_id, ",".join(bits), r.stat("speed")])
	out.sort()
	return out


func _sorted(d: Dictionary) -> Dictionary:
	var keys: Array = d.keys()
	keys.sort()
	var out: Dictionary = {}
	for k: Variant in keys:
		out[k] = int(d[k])
	return out


## [outposts] Live outpost levels (and whether each repaired one has a working scale).
func _outposts(s: Node) -> Array:
	var out: Array = []
	if s.get("outposts") == null:
		return out
	for o: Outpost in s.outposts.items:
		out.append("%d%s" % [o.level, "+scale" if o.scale_depot != null else ""])
	return out


## Values of the marker cubes (a Haul Bug's bale, a cube dropped with Q) found in the saved cube list.
func _tagged_cubes(s: Node) -> Array:
	s.persist_save()
	var out: Array = []
	for cd: Dictionary in GameState.world.get("cubes", []):
		var v: float = snappedf(BigNum.from_serialized(cd.get("value", [0.0, 0])).to_float(), 0.01)
		if v in [41.25, 37.75]:
			out.append(v)
	out.sort()
	return out


## [biomes] Snapshot of a frontier district's persisted state.
func _frontier_snap(s: Node) -> Dictionary:
	var fd: FrontierDistrict = s.frontier
	var ice_sum: float = 0.0
	for v: float in fd.ice:
		ice_sum += v
	var planted: int = 0
	for sp: int in s.garden.slot_species:
		if sp >= 0:
			planted += 1
	return {"kind": fd.kid, "heaters": JSON.stringify(fd.heaters), "greenhouses": JSON.stringify(fd.greenhouses),
		"ice": snappedf(ice_sum, 0.01), "locked": s.field.locked.size(), "drained": fd.drained,
		"drain_order": JSON.stringify(fd.drain_order), "storms": fd.storms, "cleaned": s.field.cleaned_count,
		"alive": s.field.piece_alive.count(1), "slots": s.garden.slot_pos.size(), "planted": planted,
		"water": s.field.hex_water.count(1), "hub_level": s.hub.level,
		"cradle_done": fd.done, "cradle_returned": GameState.flags.get("cradle_returned", false)}  # [beat]


func _frontier_roundtrip(packed: PackedScene, kid: String, hub_i: int) -> void:
	GameState.switch_hub(hub_i)
	GameState.reload_in_memory = true
	var s1: Node = packed.instantiate()
	get_tree().root.add_child(s1)
	for i: int in 5:
		await get_tree().process_frame
	var fd: FrontierDistrict = s1.frontier
	if fd == null:
		_check("frontier_%s_built" % kid, true, false)
		s1.queue_free()
		return
	GameState.add_currency("cubes", BigNum.from_float(500000))
	GameState.add_currency("seeds", BigNum.from_float(30))
	match kid:
		"frozen_port":
			var iced: Array = range(fd.ice.size()).filter(func(h_: int) -> bool: return fd.ice[h_] > 0.0)
			fd._place_heater(int(iced[0]), true)
			fd._place_heater(int(iced[1]), true)
			fd._thaw_step(30.0)
			var h: int = int(iced[2])
			fd.ice[h] = 0.0
			fd._update_locks()
			fd._clear_hex(h)
			fd._build_greenhouse(h, true)
			Research.grant("cold_hardy_seeds")
		"sunken_city":
			for h: int in Frontiers.drain_hexes(s1.field, 1, fd.kind["flood"]):
				fd._clear_hex(h)
			fd.drain_next(false)
			var street: int = int(fd.drain_order[0])
			fd._clear_hex(street)
		"cradle_returns":  # [beat] the ark finale hook fires, and we save mid-cinematic
			fd.complete()
		"dust_flats":
			for h: int in s1.field.hex_count():
				if s1.field.hex_hub[h] == 0 and Frontiers.ring_of(s1.field, h) <= 2:
					fd._clear_hex(h)
			fd.storm_hit()
	for k: int in s1.garden.slot_species.size():
		if s1.garden.slot_species[k] < 0 and s1.field.is_clean(s1.garden.slot_hex[k]) and s1.garden.plantable(k):
			s1.garden.plant(k)
			break
	s1.hub.upgrade()
	for i: int in 5:
		await get_tree().process_frame
	var before: Dictionary = _frontier_snap(s1)
	if not SaveManager.save_game():
		_check("frontier_%s_saved" % kid, true, false)
	s1.queue_free()
	await get_tree().process_frame
	GameState.from_dict(SaveManager.read_dict(SaveManager.slot_path()))
	GameState.reload_in_memory = true
	var s2: Node = packed.instantiate()
	get_tree().root.add_child(s2)
	for i: int in 5:
		await get_tree().process_frame
	var after: Dictionary = _frontier_snap(s2)
	for k: String in before:
		_check("frontier_%s_%s" % [kid, k], before[k], after[k])
	if kid == "cradle_returns":  # [beat] quit mid-finale: it plays again after loading, and the Seed Ark opens
		await get_tree().create_timer(4.0).timeout
		_check("cradle_finale_replays_after_load", true, BloomFinale.playing or bool(GameState.flags.get("bloom_finale_seen", false)))
		_check("cradle_opens_seed_ark", true, Bloom.ark_unlocked())
	s2.queue_free()
	await get_tree().process_frame


func _built(s: Node) -> Array:
	var out: Array = []
	var st: Node = Stations.of(s)
	if st:
		for id: String in ["conveyor", "auto_baler", "recycler"]:
			if st.built(id):
				out.append(id)
	return out


func _ready() -> void:
	await get_tree().process_frame
	SaveManager.slot = 7
	SaveManager.enabled = true
	var packed: PackedScene = load("res://scenes/slice.tscn")
	var s1: Node = packed.instantiate()
	get_tree().root.add_child(s1)
	for i: int in 3:
		await get_tree().process_frame
	# Build up some mid-game state.
	GameState.add_currency("cubes", BigNum.from_float(5000))
	GameState.add_currency("compost", BigNum.from_float(12))
	GameState.flags["seeds_unlocked"] = true
	GameState.flags["rocket_tier"] = 3
	GameState.add_currency("seeds", BigNum.from_float(20))
	GameState.add_currency("sheet_metal", BigNum.from_float(200))
	GameState.add_currency("plastic_stock", BigNum.from_float(200))
	# Clean three hexes by hand.
	var cleaned: int = 0
	for h: int in s1.field.hex_count():
		if cleaned >= 3:
			break
		if s1.field.hex_hub[h] != 0 or s1.field.is_water(h) or s1.field.is_clean(h):
			continue
		for pid: int in s1.field.hex_pieces[h]:
			if s1.field.piece_alive[pid] == 1:
				s1.collect_piece(pid)
		cleaned += 1
	var st: Node = Stations.of(s1)
	if st:
		for id: String in ["conveyor", "auto_baler"]:
			Research.grant(id)
			if not st.build(id):
				print("[roundtrip] FAIL could not build %s: %s" % [id, st.block_reason(id)])
				_fails += 1
	for t: String in ["scoopie", "haulbug", "drip", "skimmer"]:
		var r: Robot = s1.fleet.spawn(t, 1, Vector3(randf_range(-3, 3), 0.2, randf_range(2, 4)), 0.05, "RT-" + t)
		r.tier = 1
	s1.fleet.toggle_zone_hex("clean", false, 5, true)
	s1.fleet.set_mode("clean", false, "stay")
	s1.fleet.set_mode("RT-drip", true, "recall")
	for slot: int in 6:
		var free: int = -1
		for k: int in s1.garden.slot_species.size():
			if s1.garden.slot_species[k] < 0 and s1.field.is_clean(s1.garden.slot_hex[k]):
				free = k
				break
		if free >= 0:
			s1.garden.plant(free)
	s1.composter.level = 3
	CoreCharge.store(0.31)  # Bloom Core charge + its 25% milestone
	Bloom.done_list().append("first_meadow")  # [beat] a Verdance Bloom milestone, post-credits flag
	GameState.flags["credits_seen"] = true
	# [outposts] Repair outpost 0 and take it to Big Skip; repair the last one too.
	if s1.get("outposts") != null and s1.outposts.items.size() >= 2:
		s1.outposts.repair(0, false, true)
		s1.outposts.upgrade(0, false, true)
		s1.outposts.repair(s1.outposts.items.size() - 1, false, true)
	if s1.fleet.get("water_net") != null:
		s1.fleet.water_net.place_tank(s1.field.hex_center(1) + Vector3(2, 0, 0))
	GameState.flags["research"] = {"done": ["scoop_beam", "salvage_logic"], "queue": [], "active": {}}
	# A Haul Bug with a bale on its fork, and a cube Patch set down with Q (both must persist).
	for r: Robot in s1.fleet.robots():
		if r.type_id == "haulbug":
			var bale: JunkCube = JunkCube.create(BigNum.from_float(41.25), {"fill": 1.0})
			s1.add_cube(bale)
			bale.set_carried(true)
			bale.reparent(r, true)
			r.carried.append(bale)
	# [events] Tokens, an accepted contract, a finished one, collectibles and a livery.
	GameState.add_currency(Contracts.CURRENCY, BigNum.from_float(17))
	var cst: Dictionary = Contracts.state()
	cst["slots"] = [Contracts.make_offer(Contracts.template("perfect_bales"), 1), Contracts.make_offer(Contracts.template("scoop"), 0), Contracts.wait_slot(500.0)]
	Contracts.accept_slot(cst["slots"][0], 3.0)
	cst["slots"][1]["state"] = "done"
	cst["done_total"] = 4
	Collection.grant("golden_bolt", true)
	Collection.grant("photo_moss_deer", true)
	Contracts.owned().append("livery_halo")
	GameState.flags["livery"] = "livery_halo"
	WorldEvents.persist_state()["recent"] = ["supply_drop", "rain_shower"]
	# [hud] Some Lumi XP across a couple of levels.
	if s1.get("lumi_level") != null:
		s1.lumi_level.add("dev", LumiLevel.need(1) + LumiLevel.need(2) + 37)
	# [wild] Animals: sightings, a photo and an adopted cat (she should be back at the base).
	if s1.get("fauna") != null:
		s1.fauna.mark_seen("deer")
		s1.fauna.record_photo("pigeon")
		var stray := Fauna.Animal.new()
		stray.sp = "cat"
		stray.kind = "cat"
		stray.key = "cat|5|0"
		stray.coat = 1
		s1.fauna.adopt(stray)
	# [drones] Builder: parts in the bin, fragments, builds on two robots (one renamed), a preset.
	for id: String in ["treads", "big_eye", "rotor", "long_forks", "top_hat", "mist_sprayer"]:
		RobotBuilder.add_part(id, 2)
	RobotBuilder.add_fragments(3)
	for r: Robot in s1.fleet.robots():
		if r.type_id == "scoopie":
			RobotBuilder.equip(r, "mobility", "treads")
			RobotBuilder.equip(r, "head", "big_eye")
			RobotBuilder.equip(r, "topper", "top_hat")
			RobotBuilder.save_preset("clean", r.build)
			RobotBuilder.rename(s1.fleet, r, "Bobbin-42")
		elif r.type_id == "haulbug":
			RobotBuilder.equip(r, "tool", "long_forks")
			RobotBuilder.equip(r, "mobility", "rotor")
		elif r.type_id == "drip":
			r.trait_id = "sleepy"
			RobotBuilder.equip(r, "tool", "mist_sprayer")
	# [skins] Unlock two designs, wear Nova, turn bonuses off.
	Designs.unlocked().append_array(["bolt", "nova"])
	Designs.select("nova")
	Designs.set_looks_only(true)
	(s1.patch.model as PatchModel).set_variant("nova")
	_late_decorate(s1, 4)  # [late] a few Garden Mode decorations
	ExtrasRoundtrip.setup(s1)  # [extras] radio song, album records, a retired caretaker
	s1.patch.global_position = Vector3(3.0, 0.2, 5.0)
	var dropped: JunkCube = JunkCube.create(BigNum.from_float(37.75), {"fill": 1.0})
	s1.add_cube(dropped)
	s1.patch.pick_up(dropped)
	await get_tree().physics_frame
	s1.patch.place_top_cube()
	for i: int in 30:
		await get_tree().process_frame
	var before: Dictionary = _snapshot(s1)
	_check("tagged_cubes_saved", [37.75, 41.25], before["tagged_cubes"])
	if not SaveManager.save_game():
		print("[roundtrip] FAIL save_game returned false")
		get_tree().quit(1)
		return
	s1.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	# Load from disk into a fresh slice.
	GameState.from_dict(SaveManager.read_dict(SaveManager.slot_path()))
	GameState.reload_in_memory = true
	var s2: Node = packed.instantiate()
	get_tree().root.add_child(s2)
	for i: int in 30:
		await get_tree().process_frame
	var after: Dictionary = _snapshot(s2)
	for k: String in before:
		_check(k, before[k], after[k])
	# [biomes] Frontier districts: ice/heaters/greenhouses, pump stages, storm count.
	var fhubs: Dictionary = (s2.planet as PlanetData).frontier_hubs.duplicate()
	s2.queue_free()
	await get_tree().process_frame
	for kid: String in ["frozen_port", "sunken_city", "dust_flats", "cradle_returns"]:
		await _frontier_roundtrip(packed, kid, int(fhubs[kid]))
	await ExtrasRoundtrip.weekly(self, packed)  # [extras] Seed of the Week in its own slot
	await _late_multi_world(packed)  # [late] Cradle Mode: a second world, the profile, travel both ways
	SaveManager.delete_save()
	print("[roundtrip] %s (%d failures)" % ["OK" if _fails == 0 else "FAILED", _fails])
	get_tree().quit(1 if _fails > 0 else 0)


# --- [late] Garden Mode and Cradle Mode ---------------------------------------------------

## Places `n` decorations (free) on cells that accept them; returns how many went down.
func _late_decorate(s: Node, n: int) -> int:
	var d: LateDirector = LateDirector.of(s)
	if d == null:
		_check("late_director_built", true, false)
		return 0
	var types: Array[String] = ["bench", "fountain", "lamp", "flower_bed", "planter"]
	var placed: int = 0
	var f: HexField = s.field
	for h: int in f.hex_count():
		if placed >= n:
			break
		if not f.is_clean(h) or f.is_water(h):
			continue
		var c: Vector2i = Decor.cell_at(f.hex_center(h))
		for k: int in 6:
			var t: String = types[placed % types.size()]
			if d.decor.place(t, c + Vector2i(k * 2 - 6, 1), placed % 4, false):
				placed += 1
				break
	_check("late_decor_placed", true, placed > 0)
	return placed


func _late_snap(s: Node) -> Dictionary:
	var types: Array = []
	for r: Robot in (s.fleet as Fleet).robots():
		types.append(r.type_id)
	types.sort()
	return {"world": CradleMode.world_name(), "seed": (s.planet as PlanetData).seed_value, "district": s.district_name,
		"town0": str((s.planet as PlanetData).cities[0]["name"]), "cubes": snappedf(GameState.get_currency("cubes").to_float(), 0.01),
		"robots": types, "decor": JSON.stringify(GameState.world.get("decor", {})), "world_index": int(GameState.flags.get("world_index", 0)),
		"research": Research.done_list().size(), "slot": SaveManager.slot}


func _late_multi_world(packed: PackedScene) -> void:
	var keep_profile: Dictionary = CradleMode.profile.duplicate(true)
	var keep_persist: bool = CradleMode.persist
	CradleMode.path_override = SaveManager.save_dir().path_join("roundtrip_profile.save")
	CradleMode.persist = true
	CradleMode.profile = CradleMode.default_profile()
	(CradleMode.worlds()[0] as Dictionary)["slot"] = 7  # Verdance lives in the round trip's slot
	CradleMode.apply_current()
	GameState.flags["bloom_finale_seen"] = true
	GameState.stats["ark_waves"] = 3.0
	SaveManager.save_game(false)  # Verdance as it is now (launch_new_world only saves with a live tree)
	var verdance_cubes: float = GameState.get_currency("cubes").to_float()
	var verdance_hub: int = GameState.current_hub
	CradleMode.profile["starseeds"] = 200.0
	for id: String in ["old_crew", "head_start", "archivist", "green_thumb"]:
		CradleMode.buy(id)
	var w: Dictionary = CradleMode.launch_new_world(null, 8)
	_check("late_new_world_slot", 8, SaveManager.slot)
	var s3: Node = packed.instantiate()
	get_tree().root.add_child(s3)
	for i: int in 20:
		await get_tree().process_frame
	_check("late_new_world_name", str(w["name"]), CradleMode.world_name())
	_check("late_new_world_seed", int(w["seed"]), (s3.planet as PlanetData).seed_value)
	_check("late_new_world_new_towns", true, str((s3.planet as PlanetData).cities[0]["name"]) != "Old Town")
	_check("late_new_world_kit_robots", true, (s3.fleet as Fleet).robots().size() >= 1)
	_check("late_new_world_kit_research", true, Research.done_list().size() >= 5)
	var f3: HexField = s3.field
	var n_clean: int = 0
	for h: int in f3.hex_count():
		if n_clean >= 3:
			break
		if f3.hex_hub[h] != 0 or f3.is_water(h) or f3.is_clean(h) or f3.hex_center(h).length() < 14.0:
			continue
		for pid: int in f3.hex_pieces[h]:
			if f3.piece_alive[pid] == 1:
				s3.collect_piece(pid)
		n_clean += 1
	_late_decorate(s3, 2)
	var before: Dictionary = _late_snap(s3)
	if not SaveManager.save_game():
		_check("late_new_world_saved", true, false)
	s3.queue_free()
	await get_tree().process_frame
	# The profile on disk comes back as it was.
	var prof: String = JSON.stringify(CradleMode.to_dict())
	CradleMode.profile = {}
	CradleMode.load_profile()
	_check("late_profile_roundtrip", str(JSON.parse_string(prof)), str(JSON.parse_string(JSON.stringify(CradleMode.to_dict()))))
	_check("late_profile_worlds", 2, CradleMode.worlds().size())
	_check("late_profile_heirlooms", 4, CradleMode.heirloom_total())
	# Back to Verdance: its save (slot 7) loads as it was left.
	_check("late_switch_home", true, CradleMode.switch_world(0))
	_check("late_home_slot", 7, SaveManager.slot)
	_check("late_home_name", "Verdance", str(Economy.planet["name"]))
	_check("late_home_cubes", snappedf(verdance_cubes, 0.01), snappedf(GameState.get_currency("cubes").to_float(), 0.01))
	_check("late_home_hub", verdance_hub, GameState.current_hub)
	_check("late_home_district0_decor", true, JSON.stringify((GameState.districts.get(0, {}) as Dictionary).get("decor", {})).contains("bench"))
	var s4: Node = packed.instantiate()
	get_tree().root.add_child(s4)
	for i: int in 10:
		await get_tree().process_frame
	_check("late_home_seed", 4471, (s4.planet as PlanetData).seed_value)
	SaveManager.save_game()
	s4.queue_free()
	await get_tree().process_frame
	# And out to the new world again: everything it had.
	_check("late_switch_away", true, CradleMode.switch_world(1))
	var s5: Node = packed.instantiate()
	get_tree().root.add_child(s5)
	for i: int in 20:
		await get_tree().process_frame
	var after: Dictionary = _late_snap(s5)
	for k: String in before:
		_check("late_world2_" + k, before[k], after[k])
	s5.queue_free()
	await get_tree().process_frame
	SaveManager.delete_save(8)
	DirAccess.remove_absolute(CradleMode.profile_path())
	CradleMode.path_override = ""
	CradleMode.persist = keep_persist
	CradleMode.profile = keep_profile
	SaveManager.slot = 7
	Economy.planet["name"] = "Verdance"
