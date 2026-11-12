# Snippets cut from systems/events.gd (WorldEvents) in task M3-13: the three world events that
# were cut (docs/reviews/M3-13_TRIM.md). Supply Drop (off since the owner's playtest: no reward
# crates from the sky), Robot Hiccup (pointed at robots, not at cleaning, pressing or tending, and
# paid cubes and Parts for robot upkeep) and Wildlife Visit (its reward was a photo for the parked
# Collection, plus cubes and seeds for a photo). Their start/update cases in start() and
# _update_active(), the robot/animal parts of _clear_props(), the "robot"/"animal" WREN vars and
# their entries in the planet's events table (parked/side/events/events_cut.json) went with them.

# --- Supply drop -------------------------------------------------------------------------------

func _start_supply(d: Dictionary, force: bool) -> bool:
	var r: float = float(d.get("zone_radius", 4.0))
	var spot: Dictionary = _junk_spot(r, 10, 10.0, 45.0, force)
	if spot.is_empty():
		return false
	var pos: Vector3 = spot["pos"]
	active["pos"] = pos
	active["zone"] = spot["zone"]
	active["n0"] = (spot["zone"] as PackedInt32Array).size()
	active["landed"] = false
	var col: Color = active["color"]
	var root := Node3D.new()
	root.name = "SupplyDrop"
	add_child(root)
	_keep(root)
	root.global_position = pos
	_upright(root)  # [orbB]
	var ring: MeshInstance3D = EventProps.zone_ring(r, col)
	root.add_child(ring)
	var beacon: Node3D = EventProps.beacon(col, 30.0, 0.3)
	root.add_child(beacon)
	var crate: Node3D = EventProps.crate()
	crate.scale = Vector3.ONE * 1.4
	root.add_child(crate)
	var chute: Node3D = EventProps.parachute()
	chute.position = Vector3(0, 0.62, 0)
	crate.add_child(chute)
	# --event-land (screenshots): start just above the junk and drift down slowly.
	var low: bool = DevHooks.has("event-land")
	crate.position = Vector3(0, 1.3 if low else 30.0, 0)
	crate.rotation.y = rng.randf() * TAU
	active["crate"] = crate
	active["chute"] = chute
	var tw := crate.create_tween()
	tw.tween_property(crate, "position:y", 0.12, 90.0 if low else 8.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_supply_landed)
	return true


func _supply_landed() -> void:
	if active.get("id", "") != "supply_drop":
		return
	active["landed"] = true
	var pos: Vector3 = active["pos"]
	Vfx.burst("dust", pos + OrbitUp.up(pos) * 0.2, Color(0.7, 0.66, 0.6, 0.7), 1.6)
	Audio.play("thud", 0.8, -2.0)
	EventBus.shake_requested.emit(0.08)
	var chute: Node3D = active.get("chute")
	if is_instance_valid(chute):
		var tw := chute.create_tween()
		tw.set_parallel(true)
		tw.tween_property(chute, "scale", Vector3(1.3, 0.05, 1.3), 1.2).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(chute, "position", Vector3(1.4, 0.1, 0.4), 1.2)
		tw.chain().tween_interval(3.0)
		tw.chain().tween_property(chute, "scale", Vector3(0.01, 0.01, 0.01), 0.8)


func _update_supply() -> void:
	var crate: Node3D = active.get("crate")
	var chute: Node3D = active.get("chute")
	if is_instance_valid(chute) and not bool(active["landed"]):
		chute.rotation.z = sin(_anim_t * 1.3) * 0.12
		chute.rotation.x = cos(_anim_t * 1.1) * 0.08
	var zone: PackedInt32Array = active["zone"]
	var alive: int = 0
	for pid: int in zone:
		alive += world.field.piece_alive[pid]
	var need: int = maxi(1, int(ceil(int(active["n0"]) * 0.08)))
	active["progress"] = tr("%d pieces of junk left around the crate") % maxi(alive - need, 0)
	if bool(active["landed"]) and alive <= need:
		var pos: Vector3 = active["pos"]
		if is_instance_valid(crate):
			var lid: Node3D = crate.get_node_or_null("Lid")
			if lid:
				var tw := lid.create_tween()
				tw.tween_property(lid, "rotation_degrees:x", -115.0, 0.35).set_trans(Tween.TRANS_BACK)
			# The crate stays a moment after the event ends, then sinks away.
			_props.erase(crate.get_parent())
			var root: Node3D = crate.get_parent()
			var tw2 := root.create_tween()
			tw2.tween_interval(6.0)
			tw2.tween_property(root, "scale", Vector3(0.01, 0.01, 0.01), 0.6)
			tw2.tween_callback(root.queue_free)
			var beacon: Node = root.get_node_or_null("Beacon")
			if beacon:
				beacon.queue_free()
			var ring: Node = root.get_node_or_null("ZoneRing")
			if ring:
				ring.queue_free()
		Vfx.burst("big_sparkle", pos + OrbitUp.up(pos) * 0.8, Color(0.5, 0.95, 1.0))
		Vfx.burst("confetti", pos + OrbitUp.up(pos) * 1.0, Color.WHITE, 0.6)
		Audio.play("fanfare", 1.15, -6.0)
		var got: String = _pay(def("supply_drop").get("reward", {}), pos, "supply_drop")
		_finish(true, tr("Supply crate opened: %s") % got)
	elif float(active["left"]) <= 0.0:
		_finish(false, tr("The supply crate's beacon timed out and a drone hauled it back up. Another will come."))


# --- Robot hiccup ------------------------------------------------------------------------------

func _start_hiccup(_d: Dictionary, _force: bool) -> bool:
	var fleet: Fleet = world.get("fleet") as Fleet
	if fleet == null or fleet.robots().is_empty():
		return false
	var pp: Vector3 = world.patch.global_position
	var bots: Array[Robot] = fleet.robots()
	bots.sort_custom(func(a: Robot, b: Robot) -> bool: return a.global_position.distance_to(pp) < b.global_position.distance_to(pp))
	var r: Robot = bots[rng.randi() % mini(3, bots.size())]
	r.set_physics_process(false)
	active["robot"] = r
	active["robot_name"] = r.robot_name
	active["pos"] = r.global_position
	var marker: Node3D = EventProps.hiccup_marker(active["color"])
	marker.position = Vector3(0, 2.2, 0)
	r.add_child(marker)
	active["marker"] = marker
	world.interactables.register(r, 2.8, tr("E   fix %s's hiccup") % r.robot_name, _fix_hiccup)
	return true


func _update_hiccup(delta: float) -> void:
	var r: Variant = active.get("robot")
	if not is_instance_valid(r) or not (r is Robot):
		_finish(false)
		return
	var bot: Robot = r
	active["pos"] = bot.global_position
	var m: Node3D = active.get("marker")
	if is_instance_valid(m):
		m.position.y = 2.2 + sin(_anim_t * 3.0) * 0.12
		var ring: Node3D = m.get_node_or_null("Ring")
		if ring:
			ring.rotate_y(delta * 2.0)
	# Hic! A little hop, a puff and a squeak every so often.
	if _tick_t > 1.6:
		_tick_t = 0.0
		Vfx.burst("steam", bot.global_position + OrbitUp.up(bot.global_position) * 1.0, Color(0.9, 0.9, 0.9, 0.5), 0.5)
		Audio.play("squeak", rng.randf_range(1.3, 1.6), -10.0)
		if bot.visual:
			var tw := bot.visual.create_tween()
			tw.tween_property(bot.visual, "position:y", 0.18, 0.08)
			tw.tween_property(bot.visual, "position:y", 0.0, 0.18).set_trans(Tween.TRANS_BOUNCE)
	var d: float = bot.global_position.distance_to(world.patch.global_position)
	active["progress"] = tr("%s is %d m away") % [bot.robot_name, int(d)]
	if float(active["left"]) <= 0.0:
		_finish(false, tr("%s shook off its hiccups on its own. It looks embarrassed.") % bot.robot_name)


func _fix_hiccup() -> void:
	var r: Variant = active.get("robot")
	if active.get("id", "") != "robot_hiccup" or not is_instance_valid(r) or not (r is Robot):
		return
	var bot: Robot = r
	world.interactables.unregister(bot)
	bot.set_physics_process(true)
	Vfx.burst("sparkle", bot.global_position + OrbitUp.up(bot.global_position) * 1.0, Color(1.0, 0.75, 0.35), 0.9)
	Audio.play("servo", 1.0, -4.0)
	Audio.play("ding", 1.2, -6.0)
	var got: String = _pay(def("robot_hiccup").get("reward", {}), bot.global_position, "robot_hiccup")
	_finish(true, tr("%s is fixed and back to work. %s") % [bot.robot_name, got])


# --- Wildlife visit ----------------------------------------------------------------------------

func _start_wildlife(d: Dictionary, force: bool) -> bool:
	var hl: HexLevels = world.get("hex_levels") as HexLevels
	var need: int = int(d.get("requires", {}).get("hex_level", 4))
	var best: int = -1
	var best_l: int = -1
	var pp: Vector3 = world.patch.global_position
	if hl:
		for h: Variant in hl.levels:
			var l: int = int(hl.levels[h])
			if l >= need and (best < 0 or l > best_l or (l == best_l and world.field.hex_center(int(h)).distance_to(pp) < world.field.hex_center(best).distance_to(pp))):
				best = int(h)
				best_l = l
	if best < 0 and force:
		var f: HexField = world.field
		var near: float = INF
		for h: int in OrbitUp.hexes(f, world.patch.global_position):  # [orbB]
			if f.is_water(h) or f.hex_hub[h] != 0:
				continue
			var dd: float = f.hex_center(h).distance_to(pp)
			if dd > 8.0 and dd < near and (f.is_clean(h) or near == INF):
				near = dd
				best = h
	if best < 0:
		return false
	var animals: Array = cfg().get("animals", [])
	var pick: Dictionary = {}
	for a: Dictionary in animals:
		if not Collection.has("photo_" + str(a["id"])):
			pick = a
			break
	if pick.is_empty():
		pick = animals[rng.randi() % animals.size()]
	var c: Vector3 = world.field.hex_center(best)
	var at: Vector3 = _gp(c + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * world.field.hex_size * 0.35)
	var an: Node3D = EventProps.animal(str(pick.get("body", "fox")), Color.html(str(pick["color"])), Color.html(str(pick["glow"])))
	add_child(an)
	_keep(an)
	an.global_position = at
	_upright(an)  # [orbB]
	an.scale = Vector3.ONE * 0.01
	an.create_tween().tween_property(an, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_BACK)
	Vfx.burst("sparkle", at + OrbitUp.up(at) * 0.6, Color.html(str(pick["glow"])), 0.6)
	active["animal"] = an
	active["animal_id"] = str(pick["id"])
	active["animal_name"] = tr(str(pick["name"]))
	active["animal_body"] = str(pick.get("body", "fox"))
	active["hex"] = best
	active["pos"] = at
	active["goal"] = at
	active["name"] = tr("Wildlife Visit: %s") % tr(str(pick["name"]))
	world.interactables.register(an, 3.4, tr("E   take a photo of the %s") % tr(str(pick["name"])), _photo)
	return true


func _update_wildlife(delta: float) -> void:
	var an: Node3D = active.get("animal")
	if not is_instance_valid(an):
		_finish(false)
		return
	var goal: Vector3 = active["goal"]
	var to: Vector3 = goal - an.global_position
	var u: Vector3 = an.global_position.normalized()
	to -= u * to.dot(u)  # along the ground
	var body: Node3D = an.get_node("Body")
	var hop: bool = str(active["animal_body"]) in ["hare", "hedgehog"]
	if to.length() > 0.25:
		var spd: float = 1.3 if hop else 0.8
		an.global_position += to.normalized() * minf(spd * delta, to.length())
		an.global_position = _gp(an.global_position)  # on the ground, facing where it walks
		var sc: Vector3 = an.scale
		an.global_basis = an.global_basis.orthonormalized().slerp(Basis.looking_at(-to.normalized(), an.global_position.normalized()), minf(delta * 4.0, 1.0)).orthonormalized()
		an.scale = sc
		body.position.y = absf(sin(_anim_t * (9.0 if hop else 6.0))) * (0.12 if hop else 0.03)
	else:
		body.position.y = lerpf(body.position.y, 0.0, minf(delta * 6.0, 1.0))
		body.rotation.x = sin(_anim_t * 0.9) * 0.05  # grazing / sniffing
	var tail: Node3D = body.get_node_or_null("Tail")
	if tail:
		tail.rotation.y = sin(_anim_t * 3.0) * 0.4
	if _tick_t > rng.randf_range(3.0, 6.0):
		_tick_t = 0.0
		var c: Vector3 = world.field.hex_center(int(active["hex"]))
		active["goal"] = _gp(c + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * world.field.hex_size * 0.45)
	active["pos"] = an.global_position
	active["progress"] = tr("%s, %d m away") % [str(active["animal_name"]), int(an.global_position.distance_to(world.patch.global_position))]
	if float(active["left"]) <= 0.0:
		_animal_leave(an)
		_finish(false, tr("The %s wandered off. It'll be back somewhere green.") % str(active["animal_name"]))


func _animal_leave(an: Node3D) -> void:
	_props.erase(an)
	if world.get("interactables") != null:
		world.interactables.unregister(an)
	var away: Vector3 = an.global_position + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * 6.0
	var tw := an.create_tween()
	tw.tween_property(an, "global_position", away, 2.5)
	tw.parallel().tween_property(an, "scale", Vector3.ONE * 0.01, 2.5).set_ease(Tween.EASE_IN)
	tw.tween_callback(an.queue_free)


func _photo() -> void:
	if active.get("id", "") != "wildlife_visit":
		return
	var an: Node3D = active.get("animal")
	if not is_instance_valid(an):
		return
	hud.flash()
	Audio.play("click", 0.7, 0.0)
	Audio.play("ding", 1.5, -6.0)
	var aid: String = str(active["animal_id"])
	var first: bool = Collection.grant("photo_" + aid)
	GameState.inc_stat("photos_taken")
	var rw: Dictionary = (def("wildlife_visit").get("reward", {}) as Dictionary).duplicate()
	rw.erase("trinket_chance")
	var got: String = _pay(rw, an.global_position, "wildlife_visit")
	_animal_leave(an)
	_finish(true, (tr("Snap! The %s is in your Collection. %s") if first else tr("Snap! Another lovely shot of the %s. %s")) % [str(active.get("animal_name", "visitor")), got])
