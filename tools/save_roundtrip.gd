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
		"intro_done": GameState.flags.get("intro_done", false),
	}


func _built(s: Node) -> Array:
	var out: Array = []
	var st: Node = Stations.of(s)
	if st:
		for id: String in ["conveyor", "baler", "recycler"]:
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
		for id: String in ["conveyor", "baler"]:
			st.build(id)
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
	if s1.fleet.get("water_net") != null:
		s1.fleet.water_net.place_tank(s1.field.hex_center(1) + Vector3(2, 0, 0))
	GameState.flags["research"] = {"done": ["scoop_beam", "salvage_logic"], "queue": [], "active": {}}
	for i: int in 30:
		await get_tree().process_frame
	var before: Dictionary = _snapshot(s1)
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
