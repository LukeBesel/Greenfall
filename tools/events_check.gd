extends Node
## [events] Plays every world event to its end in a real slice (headless) and checks the outcome:
##   godot --headless --path . res://tools/events_check.tscn -- --fresh
## Prints PASS/FAIL per check and exits 1 on any failure.

var _fails: int = 0
var s: Node


func _check(name: String, ok: bool, detail: String = "") -> void:
	print("[events-check] %s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		_fails += 1


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _ready() -> void:
	await get_tree().process_frame
	SaveManager.enabled = false
	s = (load("res://scenes/slice.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(s)
	await _frames(5)
	var ev: WorldEvents = s.events
	GameState.flags["seeds_unlocked"] = true
	GameState.flags["intro_done"] = true
	# --- Supply drop: clearing the junk around the crate opens it.
	var bolts0: float = GameState.get_currency("bolts").to_float()
	_check("supply_start", ev.start("supply_drop", true))
	ev.active["left"] = 999.0
	ev._supply_landed()
	for pid: int in ev.active["zone"]:
		if s.field.piece_alive[pid] == 1:
			s.collect_piece(pid)
	await _frames(3)
	_check("supply_opened", ev.active.is_empty(), "bolts %.0f -> %.0f" % [bolts0, GameState.get_currency("bolts").to_float()])
	_check("supply_paid", GameState.get_currency("bolts").to_float() > bolts0)
	# --- Salvage surge: surge junk triples a bale; streak adds its bonus.
	_check("surge_start", ev.start("salvage_surge", true))
	var h: int = int(ev.active["hex"])
	var pid0: int = -1
	for pid: int in s.field.hex_pieces[h]:
		if s.field.piece_alive[pid] == 1:
			pid0 = pid
			break
	ev.streak = Streak.new(WorldEvents.cfg()["streak"])
	ev._bale_vol = 0.0
	ev._bale_surge = 0.0
	ev.on_patch_take(pid0, 2.0)
	var info: Dictionary = ev.apply_bale_bonus({"value": BigNum.from_float(100.0)})
	_check("surge_triples_bale", absf((info["value"] as BigNum).to_float() - 300.0) < 0.01, str((info["value"] as BigNum).to_float()))
	ev.streak.add_scoop(65.0)  # tier 2
	var info2: Dictionary = ev.apply_bale_bonus({"value": BigNum.from_float(100.0)})
	_check("streak_bonus_on_bale", absf((info2["value"] as BigNum).to_float() - 106.0) < 0.01, str((info2["value"] as BigNum).to_float()))
	ev.active["left"] = 0.0
	await _frames(2)
	_check("surge_ends", ev.active.is_empty())
	# --- Rain: dry plants get watered.
	var g: Garden = s.garden
	var slot: int = -1
	for k: int in g.slot_species.size():
		if g.slot_species[k] < 0:
			slot = k
			break
	GameState.add_currency("seeds", BigNum.from_float(5))
	g.slot_species[slot] = 0
	g.slot_water[slot] = 0.0
	_check("rain_start", ev.start("rain_shower", true))
	ev._tick_t = 2.0
	await _frames(3)
	_check("rain_waters", g.slot_water[slot] > 20.0, str(g.slot_water[slot]))
	ev.active["left"] = 0.0
	await _frames(2)
	_check("rain_ends", ev.active.is_empty())
	# --- Robot hiccup: the robot freezes, E fixes it.
	var r: Robot = s.fleet.spawn("scoopie", 0, Vector3(3, 0.2, 3), 0.0, "Hic")
	await _frames(2)
	_check("hiccup_start", ev.start("robot_hiccup", true))
	var bot: Robot = ev.active["robot"]
	_check("hiccup_frozen", not bot.is_physics_processing())
	ev._fix_hiccup()
	_check("hiccup_fixed", bot.is_physics_processing() and ev.active.is_empty())
	r.queue_free()
	# --- Wildlife: a photo goes into the Collection.
	_check("wildlife_start", ev.start("wildlife_visit", true))
	var aid: String = str(ev.active["animal_id"])
	ev._photo()
	_check("wildlife_photo", Collection.has("photo_" + aid) and ev.active.is_empty(), aid)
	# --- Rare part signal: digging the part pays a bonus rare part.
	var parts0: int = GameState.parts.size()
	if ev.start("rare_part_signal", true):
		s.field.part_found[int(ev.active["part"])] = 1
		await _frames(2)
		_check("signal_paid", ev.active.is_empty() and GameState.parts.size() > parts0 and int(GameState.parts[-1]["rarity"]) >= 3)
	else:
		print("[events-check] SKIP signal (no buried parts left)")
	# --- Ledger audit: the drone scoops, Patch beats it.
	_check("audit_start", ev.start("ledger_audit", true))
	ev.active["working"] = true
	for i: int in 3:
		ev._tick_t = 5.0
		await _frames(1)
	_check("audit_drone_scoops", int(ev.active.get("drone_n", 0)) >= 1, str(ev.active.get("drone_n", 0)))
	var tok0: int = Contracts.tokens()
	for pid: int in ev.active["zone"]:
		if s.field.piece_alive[pid] == 1:
			ev.on_patch_take(pid, 1.0)
			s.collect_piece(pid)
	await _frames(2)
	_check("audit_won", ev.active.is_empty() and Contracts.tokens() >= tok0 + 2, "tokens %d -> %d" % [tok0, Contracts.tokens()])
	# --- Scheduler: with the gate met, a random event starts by itself.
	GameState.stats["hexes_cleaned"] = 10
	WorldEvents.persist_state()["next_in"] = 0.05
	await _frames(10)
	_check("scheduler_starts_event", not ev.active.is_empty(), str(ev.active.get("id", "")))
	ev.cancel()
	_check("next_delay_set", float(WorldEvents.persist_state()["next_in"]) >= 200.0)
	print("[events-check] %s (%d failures)" % ["OK" if _fails == 0 else "FAILED", _fails])
	get_tree().quit(1 if _fails > 0 else 0)
