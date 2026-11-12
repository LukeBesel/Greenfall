# Snippets cut from tools/events_check.gd in task M3-13 with the cut world events (Supply Drop,
# Robot Hiccup, Wildlife Visit).

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
