extends Node
## Save/load round-trip check for every system that persists.
## Run: godot --headless --path . res://tools/save_roundtrip.tscn -- --fresh --stations=all --unlock-seeds --clean-hexes=3
## Builds a mid-game state in one slice, saves to a temp slot, loads it into a second slice and
## compares. Prints PASS/FAIL lines and exits with code 1 on any failure.

var _fails: int = 0


func _check(name: String, a: Variant, b: Variant) -> void:
	var ok: bool = str(a) == str(b)
	print("[roundtrip] %s %s: %s -> %s" % ["PASS" if ok else "FAIL", name, str(a), str(b)])
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
	}


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
	SaveManager.delete_save()
	print("[roundtrip] %s (%d failures)" % ["OK" if _fails == 0 else "FAILED", _fails])
	get_tree().quit(1 if _fails > 0 else 0)
