class_name WorldEvents
extends Node3D
## World events director (data/events.json). Every few minutes of play (only while playing: no
## menus, cinematics or rocket flights) one small event starts somewhere near Patch, announced by
## a toast, a WREN line, the EventHUD banner + marker and a pin in Command view:
##   supply_drop       a crate parachutes onto junk; clear the junk around it to open it
##   salvage_surge     a hex glows: Patch's bales get 3x value for junk scooped there (2 min)
##   rain_shower       rain keeps every plant watered (2 min), puddles shimmer
##   robot_hiccup      a helper robot freezes; walk over and press E to fix it
##   wildlife_visit    a rare animal visits a Sustained/Thriving hex; press E for a photo
##   rare_part_signal  a violet beam marks a buried part; dig it up for a bonus rare part
##   ledger_audit      (after the Ledger arc) a friendly drone races you to clear a ring of junk
## Nothing is ever lost: an event that times out just ends. Rewards scale with progress (see
## progress_cubes) so they stay a spike, never a flood. Also owns the cleaning streak (Streak)
## and the per-bale bonus (streak tier + surge share), applied by Patch when a bale is pressed.
## Persistent bits live in GameState.flags["events"]: {next_in, recent, done{id: n}}.

signal event_started(id: String)
signal event_ended(id: String, handled: bool)
signal streak_tier_up(tier: int)

const PATH: String = "res://data/events.json"

static var _cfg: Dictionary = {}

var world: Node
var rng := RandomNumberGenerator.new()
var streak: Streak
var hud: EventHUD
## The running event ({} when none): id, name, color, left, dur, hint, progress, pos, plus per-event data.
var active: Dictionary = {}
var _props: Array[Node] = []
var _anim_t: float = 0.0
var _sync_t: float = 0.0
var _tick_t: float = 0.0
var _bale_vol: float = 0.0
var _bale_surge: float = 0.0
var _dev_event_t: float = -1.0


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = Economy.read_json(PATH)
	return _cfg


static func defs() -> Array:
	return cfg().get("events", [])


static func def(id: String) -> Dictionary:
	for e: Dictionary in defs():
		if str(e["id"]) == id:
			return e
	return {}


static func sched() -> Dictionary:
	return cfg().get("schedule", {})


## Gap before the next event (r in 0..1).
static func next_delay(r: float, s: Dictionary) -> float:
	var ev: Array = s.get("every_s", [240, 480])
	return lerpf(float(ev[0]), float(ev[1]), clampf(r, 0.0, 1.0))


## Weighted pick among eligible ids, skipping the last `no_repeat` events when possible.
static func pick_event(event_defs: Array, eligible: Dictionary, recent: Array, r: float, no_repeat: int = 2) -> String:
	var tail: Array = recent.slice(maxi(0, recent.size() - no_repeat))
	for pass_i: int in 2:
		var pool: Array = []
		var total: float = 0.0
		for e: Dictionary in event_defs:
			var id: String = str(e["id"])
			if not eligible.get(id, false) or (pass_i == 0 and id in tail):
				continue
			pool.append(e)
			total += float(e.get("weight", 1.0))
		if pool.is_empty():
			continue
		var x: float = clampf(r, 0.0, 0.999999) * total
		for e: Dictionary in pool:
			x -= float(e.get("weight", 1.0))
			if x < 0.0:
				return str(e["id"])
		return str(pool[-1]["id"])
	return ""


## Which events can run given a snapshot of the game: {junk_hexes, planted, robots,
## max_hex_level, ledger_resolved, parts_left}.
static func eligible_ids(ctx: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for e: Dictionary in defs():
		var id: String = str(e["id"])
		var req: Dictionary = e.get("requires", {})
		var ok: bool = true
		if int(req.get("planted", 0)) > int(ctx.get("planted", 0)):
			ok = false
		if int(req.get("robots", 0)) > int(ctx.get("robots", 0)):
			ok = false
		if int(req.get("hex_level", 0)) > int(ctx.get("max_hex_level", 0)):
			ok = false
		if bool(req.get("ledger_resolved", false)) and not bool(ctx.get("ledger_resolved", false)):
			ok = false
		if id in ["supply_drop", "salvage_surge", "ledger_audit"] and int(ctx.get("junk_hexes", 0)) <= 0:
			ok = false
		if id == "rare_part_signal" and int(ctx.get("parts_left", 0)) <= 0:
			ok = false
		out[id] = ok
	return out


## Cube reward that tracks progress: about `secs` of current income, never below a floor that
## grows with lifetime earnings.
static func scaled_cubes(rate: float, earned: float, secs: float, frac: float, min_cubes: float) -> float:
	return maxf(min_cubes, maxf(rate * secs, earned * frac))


static func progress_cubes(secs: float) -> float:
	var rw: Dictionary = cfg().get("reward", {})
	var earned: float = BigNum.from_serialized(GameState.stats.get("cubes_earned_total", [0.0, 0])).to_float()
	return round(scaled_cubes(GameState.income_rate(), earned, secs, float(rw.get("earned_frac", 0.004)) * secs / 90.0, float(rw.get("min_cubes", 40))))


static func persist_state() -> Dictionary:
	var v: Variant = GameState.flags.get("events")
	if not (v is Dictionary):
		v = {"next_in": float(sched().get("first_after_s", 210)), "recent": [], "done": {}}
		GameState.flags["events"] = v
	return v


# --- Node ---------------------------------------------------------------------------------------

func _ready() -> void:
	rng.randomize()
	streak = Streak.new(cfg().get("streak", {}))
	persist_state()
	hud = EventHUD.new()
	hud.events = self
	add_child(hud)
	if world and world.get("wren") != null:
		var wl: Dictionary = cfg().get("wren", {})
		for k: String in wl:
			world.wren.lines[k] = wl[k]
	EventBus.cube_made.connect(_on_cube_made)
	_dev_hooks.call_deferred()


func _dev_hooks() -> void:
	if DevHooks.has("tokens"):
		GameState.add_currency(Contracts.CURRENCY, BigNum.from_float(DevHooks.get_f("tokens", 50.0)))
	if DevHooks.has("streak"):
		streak.add_scoop(DevHooks.get_f("streak", 90.0))
		streak.grace_s = 1.0e9  # held for screenshots
	if DevHooks.has("trinkets"):
		var n: int = int(DevHooks.get_f("trinkets", 8.0))
		var i: int = 0
		for t: Dictionary in Collection.defs():
			if i % 2 == 0 and Collection.count() < n:
				Collection.grant(str(t["id"]), true)
			i += 1
	if DevHooks.has("livery"):
		var lid: String = DevHooks.get_s("livery", "livery_neon")
		if not (lid in Contracts.owned()):
			Contracts.owned().append(lid)
		GameState.flags["livery"] = lid
	if DevHooks.has("event"):
		_dev_event_t = DevHooks.get_f("event-at", 3.0)
	if DevHooks.has("event-every"):
		persist_state()["next_in"] = DevHooks.get_f("event-every", 20.0)


## --event-look[=M]: screenshot helper, puts Patch M metres from the event, facing it.
func _dev_look(at: Vector3, dist: float) -> void:
	var p: Patch = world.patch
	# Stand between the base and the event, looking outward (the base's sheds stay behind the camera).
	var d: Vector3 = at
	d.y = 0.0
	d = d.normalized() if d.length() > 0.1 else Vector3.FORWARD
	var spot: Vector3 = at - d * dist
	p.global_position = Vector3(spot.x, _ground(spot.x, spot.z) + 0.2, spot.z)
	p.rotation.y = atan2(-d.x, -d.z)
	if world.get("cam") != null:
		world.cam.yaw = p.rotation.y
		world.cam.snap()


func _paused() -> bool:
	if world == null:
		return true
	if bool(world.get("launching")):
		return true
	if world.has_method("any_modal_open") and bool(world.call("any_modal_open")):
		return true
	var intro: Variant = world.get("intro")
	return intro != null and (intro as Node).has_method("busy") and bool(intro.call("busy"))


func _process(delta: float) -> void:
	_anim_t += delta
	var fleet: Fleet = world.get("fleet") as Fleet if world else null
	Liveries.animate(fleet, _anim_t)
	_sync_t += delta
	if _sync_t > 1.0:
		_sync_t = 0.0
		Liveries.sync(fleet)
	# Wall clock (DevHooks._elapsed): on software rendering game time crawls.
	if _dev_event_t >= 0.0 and DevHooks._elapsed >= _dev_event_t:
		_dev_event_t = -1.0
		var id: String = DevHooks.get_s("event", "supply_drop")
		print("[events] dev start %s -> %s" % [id, str(start(id, true))])
		if DevHooks.has("event-look") and active.get("pos") is Vector3:
			_dev_look(active["pos"], DevHooks.get_f("event-look", 9.0))
	if _paused():
		return
	streak.tick(delta)
	if not active.is_empty():
		active["left"] = float(active["left"]) - delta
		_update_active(delta)
		return
	if float(GameState.stats.get("hexes_cleaned", 0)) < float(sched().get("min_hexes", 2)) and not DevHooks.has("event-every"):
		return
	var st: Dictionary = persist_state()
	st["next_in"] = float(st.get("next_in", 0.0)) - delta
	if float(st["next_in"]) <= 0.0:
		if not start_random():
			st["next_in"] = float(sched().get("retry_s", 40))


func context() -> Dictionary:
	var f: HexField = world.field
	var junk: int = 0
	for h: int in f.hex_count():
		if f.hex_hub[h] == 0 and not f.is_water(h) and not f.is_clean(h):
			junk += 1
	var planted: int = 0
	var g: Garden = world.get("garden") as Garden
	if g:
		for sp: int in g.slot_species:
			if sp >= 0:
				planted += 1
	var lvl: int = 0
	var hl: HexLevels = world.get("hex_levels") as HexLevels
	if hl:
		for h: Variant in hl.levels:
			lvl = maxi(lvl, int(hl.levels[h]))
	var parts_left: int = f.part_found.count(0)
	var fleet: Fleet = world.get("fleet") as Fleet
	return {"junk_hexes": junk, "planted": planted, "robots": fleet.robots().size() if fleet else 0, "max_hex_level": lvl,
		"ledger_resolved": LedgerArc.resolved(), "parts_left": parts_left}


func start_random() -> bool:
	var st: Dictionary = persist_state()
	var elig: Dictionary = eligible_ids(context())
	# Try the weighted pick first, then anything eligible (a pick can fail if no spot fits).
	var first: String = pick_event(defs(), elig, st.get("recent", []), rng.randf(), int(sched().get("no_repeat", 2)))
	if first != "" and start(first):
		return true
	for e: Dictionary in defs():
		var id: String = str(e["id"])
		if id != first and elig.get(id, false) and start(id):
			return true
	return false


## Starts an event now. force skips the requirements (dev hooks, tests).
func start(id: String, force: bool = false) -> bool:
	if not active.is_empty() or world == null:
		return false
	var d: Dictionary = def(id)
	if d.is_empty():
		return false
	active = {"id": id, "name": str(d.get("name", id)), "color": Color.html(str(d.get("color", "#ffffff"))),
		"left": float(d.get("duration_s", 120)), "dur": float(d.get("duration_s", 120)), "hint": str(d.get("hud", "")),
		"progress": "", "pos": null}
	var ok: bool = false
	var arg: String = ""
	match id:
		"supply_drop": ok = _start_supply(d, force)
		"salvage_surge": ok = _start_surge(d, force)
		"rain_shower": ok = _start_rain(d, force)
		"robot_hiccup": ok = _start_hiccup(d, force)
		"wildlife_visit": ok = _start_wildlife(d, force)
		"rare_part_signal": ok = _start_signal(d, force)
		"ledger_audit": ok = _start_audit(d, force)
	if not ok:
		_clear_props()
		active = {}
		return false
	if active.get("pos") is Vector3:
		arg = LedgerArc.compass((active["pos"] as Vector3) - world.patch.global_position)
	if id == "robot_hiccup":
		arg = str(active.get("robot_name", "A robot"))
	var toast: String = str(d.get("toast", d.get("name", id)))
	EventBus.toast.emit(toast % arg if "%s" in toast else toast, "story")
	Audio.play("blip", 1.25, -4.0)
	Audio.play("chime", 1.5, -8.0)
	if world.get("wren") != null:
		world.wren.say("event_" + id, 1.0, true, {"robot": str(active.get("robot_name", "")), "animal": str(active.get("animal_name", ""))})
	GameState.inc_stat("ev_events_started")
	print("[events] started %s" % id)
	event_started.emit(id)
	return true


func _finish(handled: bool, text: String = "") -> void:
	if active.is_empty():
		return
	var id: String = str(active["id"])
	_clear_props()
	active = {}
	var st: Dictionary = persist_state()
	st["next_in"] = next_delay(rng.randf(), sched())
	var recent: Array = st.get("recent", [])
	recent.append(id)
	st["recent"] = recent.slice(maxi(0, recent.size() - 4))
	if handled:
		var done: Dictionary = st.get("done", {})
		done[id] = int(done.get(id, 0)) + 1
		st["done"] = done
		GameState.inc_stat("ev_events_done")
		if world.get("wren") != null:
			world.wren.say("event_won", 0.4)
	if text != "":
		EventBus.toast.emit(text, "story" if handled else "info")
	print("[events] ended %s handled=%s  %s" % [id, str(handled), text])
	event_ended.emit(id, handled)


## Ends the running event without a reward (dev / tests / district change).
func cancel() -> void:
	_finish(false, "")


func _clear_props() -> void:
	for n: Node in _props:
		if is_instance_valid(n):
			n.queue_free()
	_props.clear()
	if world and world.get("interactables") != null:
		for k: String in ["animal", "robot"]:
			var v: Variant = active.get(k)
			if is_instance_valid(v) and v is Node3D:
				world.interactables.unregister(v)
	var r: Variant = active.get("robot")
	if is_instance_valid(r) and r is Robot:
		(r as Robot).set_physics_process(true)
		var m: Node = (r as Robot).get_node_or_null("Hiccup")
		if m:
			m.queue_free()
	if hud:
		hud.set_rain(false)


func _keep(n: Node) -> Node:
	_props.append(n)
	return n


func _ground(x: float, z: float) -> float:
	var layout: CityLayout = world.field.layout
	return clampf(layout.height_at(x, z), 0.0, 0.3) if layout else 0.0


func _gp(p: Vector3) -> Vector3:
	return Vector3(p.x, _ground(p.x, p.z), p.z)


func _update_active(delta: float) -> void:
	_tick_t += delta
	match str(active["id"]):
		"supply_drop": _update_supply()
		"salvage_surge": _update_surge(delta)
		"rain_shower": _update_rain(delta)
		"robot_hiccup": _update_hiccup(delta)
		"wildlife_visit": _update_wildlife(delta)
		"rare_part_signal": _update_signal()
		"ledger_audit": _update_audit(delta)


# --- Patch hooks -------------------------------------------------------------------------------

## Patch is pulling in a piece (called before the field forgets it).
func on_patch_take(pid: int, vol: float) -> void:
	_bale_vol += vol
	var up: int = streak.add_scoop()
	if up > 0:
		_on_streak_up(up)
	if active.is_empty():
		return
	match str(active["id"]):
		"salvage_surge":
			if world.field.piece_hex[pid] == int(active["hex"]):
				_bale_surge += vol
				active["took"] = int(active.get("took", 0)) + 1
				if int(active["took"]) % 6 == 1:
					Vfx.float_text(world.field.piece_pos[pid] + Vector3(0, 1.0, 0), "x3", Color(1.0, 0.82, 0.3), 0.5, 0.9)
		"ledger_audit":
			if (active.get("zone_set", {}) as Dictionary).has(pid):
				active["player"] = int(active.get("player", 0)) + 1


## Bale bonus: best streak tier while filling + the share of surge junk. Returns the new info.
func apply_bale_bonus(info: Dictionary) -> Dictionary:
	var sb: float = streak.take_bale_peak()
	var surge_frac: float = clampf(_bale_surge / maxf(_bale_vol, 0.0001), 0.0, 1.0)
	_bale_vol = 0.0
	_bale_surge = 0.0
	var m: float = float(def("salvage_surge").get("mult", 3.0))
	var mult: float = (1.0 + sb) * (1.0 + (m - 1.0) * surge_frac)
	if mult <= 1.0001:
		return info
	var out: Dictionary = info.duplicate()
	out["value"] = (info["value"] as BigNum).mul_f(mult)
	out["streak_bonus"] = sb
	out["surge_frac"] = surge_frac
	return out


func _on_cube_made(info: Dictionary) -> void:
	if str(info.get("dominant", "")) == "metal":
		GameState.inc_stat("ev_metal_bales")


func _on_streak_up(tier: int) -> void:
	Contracts.note_peak("streak", tier)
	streak_tier_up.emit(tier)
	var p: Patch = world.patch
	var col: Color = Color(0.45, 0.9, 1.0).lerp(Color(1.0, 0.75, 0.25), float(tier) / maxf(streak.max_tier, 1))
	Audio.play_scale("chime", tier + 2, -8.0)
	Vfx.ring(p.global_position + Vector3(0, 0.1, 0), 1.2 + tier * 0.25, col, 0.5)
	Vfx.float_text(p.global_position + Vector3(0, 2.2, 0), "STREAK x%d  +%d%%" % [tier, int(round(streak.bonus() * 100.0))], col, 0.55, 0.9)
	var best: float = float(GameState.stats.get("best_streak_tier", 0))
	if tier > best:
		GameState.stats["best_streak_tier"] = tier
	if tier >= streak.max_tier:
		Vfx.burst("sparkle", p.global_position + Vector3(0, 1.2, 0), col, 1.0)
		GameState.inc_stat("max_streaks")
		if Collection.grant("streak_medal") or rng.randf() < 0.3:
			if world.get("wren") != null:
				world.wren.say("streak_max", 1.0)


# --- Rewards -----------------------------------------------------------------------------------

func _range_i(v: Variant) -> int:
	if v is Array:
		return rng.randi_range(int(v[0]), int(v[1]))
	return int(v)


func _roll_rarity(lo: int, hi: int) -> int:
	var rar: Array = Economy.parts.get("rarities", [])
	hi = mini(hi, rar.size() - 1)
	var total: float = 0.0
	for i: int in range(lo, hi + 1):
		total += float(rar[i].get("weight", 1.0))
	var x: float = rng.randf() * total
	for i: int in range(lo, hi + 1):
		x -= float(rar[i].get("weight", 1.0))
		if x <= 0.0:
			return i
	return hi


## Grants an event reward and shows it at `at`. Returns a summary ("+120 cubes  +8 bolts ...").
func _pay(rw: Dictionary, at: Vector3, source: String) -> String:
	var bits: Array[String] = []
	if rw.has("income_s"):
		var c: float = progress_cubes(float(rw["income_s"]))
		GameState.add_currency("cubes", BigNum.from_float(c))
		bits.append("+%s cubes" % Settings.fmt(BigNum.from_float(c)))
	if rw.has("bolts"):
		var b: int = _range_i(rw["bolts"])
		GameState.add_currency("bolts", BigNum.from_float(b))
		bits.append("+%d bolts" % b)
	if rw.has("seeds") and GameState.flags.get("seeds_unlocked", false):
		var s: int = _range_i(rw["seeds"])
		GameState.add_currency("seeds", BigNum.from_float(s))
		bits.append("+%d seeds" % s)
	if rw.has("data"):
		var dv: int = _range_i(rw["data"])
		GameState.add_currency(Research.CURRENCY, BigNum.from_float(dv))
		bits.append("+%d data" % dv)
	var n_parts: int = int(rw.get("parts", 0))
	if rw.has("part_rarity"):
		n_parts = maxi(n_parts, 1)
	for k: int in n_parts:
		var r: int = _roll_rarity(int(rw.get("part_min_rarity", 0)), 4)
		if rw.has("part_rarity"):
			var pr: Array = rw["part_rarity"]
			r = int(pr[0]) if rng.randf() < 0.75 else int(pr[1])
		var t: int = rng.randi() % maxi(Economy.parts.get("types", [1]).size(), 1)
		GameState.parts.append({"type": t, "rarity": r})
		EventBus.part_found.emit(t, r)
		bits.append("+%s %s" % [Economy.rarity(r).get("name", ""), Economy.part_type(t).get("name", "part")])
	var tok: int = int(rw.get("tokens", 0))
	if rng.randf() < float(rw.get("tokens_chance", 0.0)):
		tok += 1
	if tok > 0:
		GameState.add_currency(Contracts.CURRENCY, BigNum.from_float(tok))
		bits.append("+%d token%s" % [tok, "" if tok == 1 else "s"])
	if rng.randf() < float(rw.get("trinket_chance", 0.0)):
		var tid: String = Collection.roll(source, rng.randf())
		if tid != "" and Collection.grant(tid):
			bits.append(str(Collection.def(tid).get("name", tid)))
	var text: String = "  ".join(bits)
	if text != "":
		Vfx.float_text(at + Vector3(0, 1.6, 0), text, Color(0.75, 1.0, 0.85), 0.55, 1.6)
	Audio.play("coin", 1.1, -4.0)
	return text


# --- Spot pickers ------------------------------------------------------------------------------

## Junk hexes with at least `min_alive` pieces, sorted by distance to Patch (within max_d if possible).
func _junk_hexes(min_alive: int, min_d: float, max_d: float) -> Array[int]:
	var f: HexField = world.field
	var pp: Vector3 = world.patch.global_position
	var out: Array[int] = []
	for h: int in f.hex_count():
		if f.hex_hub[h] != 0 or f.is_water(h) or f.is_clean(h):
			continue
		var alive: int = 0
		for pid: int in f.hex_pieces[h]:
			alive += f.piece_alive[pid]
		if alive < min_alive:
			continue
		var d: float = Vector2(f.hex_center(h).x - pp.x, f.hex_center(h).z - pp.z).length()
		if d >= min_d and d <= max_d:
			out.append(h)
	out.sort_custom(func(a: int, b: int) -> bool: return f.hex_center(a).distance_to(pp) < f.hex_center(b).distance_to(pp))
	return out


## A spot on junk (a live piece) with at least min_n pieces within radius, not too close to Patch.
func _junk_spot(radius: float, min_n: int, min_d: float, max_d: float, force: bool) -> Dictionary:
	var f: HexField = world.field
	var pp: Vector3 = world.patch.global_position
	var hexes: Array[int] = _junk_hexes(min_n, 0.0, max_d + f.hex_size)
	if hexes.is_empty() and force:
		hexes = _junk_hexes(1, 0.0, 9999.0)
	for h: int in hexes.slice(0, 6):
		var pids: PackedInt32Array = f.hex_pieces[h]
		for k: int in 10:
			var pid: int = pids[rng.randi() % pids.size()]
			if f.piece_alive[pid] == 0:
				continue
			var p: Vector3 = f.piece_pos[pid]
			var d: float = Vector2(p.x - pp.x, p.z - pp.z).length()
			if (d < min_d or d > max_d) and not force:
				continue
			var zone: PackedInt32Array = f.pieces_within(p, radius)
			if zone.size() >= min_n or (force and zone.size() > 0):
				return {"pos": _gp(p), "zone": zone, "hex": h}
	return {}


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
	Vfx.burst("dust", pos + Vector3(0, 0.2, 0), Color(0.7, 0.66, 0.6, 0.7), 1.6)
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
	active["progress"] = "%d pieces of junk left around the crate" % maxi(alive - need, 0)
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
		Vfx.burst("big_sparkle", pos + Vector3(0, 0.8, 0), Color(0.5, 0.95, 1.0))
		Vfx.burst("confetti", pos + Vector3(0, 1.0, 0), Color.WHITE, 0.6)
		Audio.play("fanfare", 1.15, -6.0)
		var got: String = _pay(def("supply_drop").get("reward", {}), pos, "supply_drop")
		_finish(true, "Supply crate opened: %s" % got)
	elif float(active["left"]) <= 0.0:
		_finish(false, "The supply crate's beacon timed out and a drone hauled it back up. Another will come.")


# --- Salvage surge -----------------------------------------------------------------------------

func _start_surge(_d: Dictionary, force: bool) -> bool:
	var hexes: Array[int] = _junk_hexes(30, 0.0, 40.0)
	if hexes.is_empty() and force:
		hexes = _junk_hexes(1, 0.0, 9999.0)
	if hexes.is_empty():
		return false
	var h: int = hexes[rng.randi() % mini(3, hexes.size())]
	var c: Vector3 = _gp(world.field.hex_center(h))
	active["hex"] = h
	active["pos"] = c
	active["took"] = 0
	var col: Color = active["color"]
	var glow: Node3D = EventProps.hex_glow(world.field.hex_size, col, 1.8)
	add_child(glow)
	_keep(glow)
	glow.global_position = c
	active["glow"] = glow
	var beacon: Node3D = EventProps.beacon(col, 18.0, 0.5)
	add_child(beacon)
	_keep(beacon)
	beacon.global_position = c
	Vfx.ring(c + Vector3(0, 0.2, 0), world.field.hex_size, col, 1.2)
	return true


func _update_surge(_delta: float) -> void:
	var h: int = int(active["hex"])
	var glow: Node3D = active.get("glow")
	if is_instance_valid(glow):
		var mi: MeshInstance3D = glow.get_node("Glow")
		var a: float = 0.75 + 0.25 * sin(_anim_t * 4.0)
		if float(active["left"]) < 15.0:
			a *= 0.5 + 0.5 * absf(sin(_anim_t * 9.0))  # flickers as it runs out
		(mi.material_override as StandardMaterial3D).albedo_color.a = a
	# Junk in the surge glints now and then.
	if _tick_t > 0.35:
		_tick_t = 0.0
		var pids: PackedInt32Array = world.field.hex_pieces[h]
		for k: int in 3:
			var pid: int = pids[rng.randi() % pids.size()]
			if world.field.piece_alive[pid] == 1:
				Vfx.burst("sparkle", world.field.piece_pos[pid] + Vector3(0, 0.2, 0), Color(1.0, 0.85, 0.35), 0.25)
	active["progress"] = "%d pieces grabbed at 3x" % int(active.get("took", 0))
	if float(active["left"]) <= 0.0 or world.field.is_clean(h):
		var took: int = int(active.get("took", 0))
		if took >= 20:
			_pay({"trinket_chance": float(def("salvage_surge").get("reward", {}).get("trinket_chance", 0.15))}, world.patch.global_position, "salvage_surge")
		_finish(took > 0, ("The surge faded. You grabbed %d pieces at triple value; they pay out when you bale." % took) if took > 0 else "The surge faded. Next time!")


# --- Rain shower -------------------------------------------------------------------------------

func _start_rain(_d: Dictionary, _force: bool) -> bool:
	var rain: Node3D = EventProps.rain()
	add_child(rain)
	_keep(rain)
	rain.global_position = world.patch.global_position
	active["rain"] = rain
	active["pos"] = null
	active["watered"] = 0
	# Puddles on open ground around Patch.
	var pp: Vector3 = world.patch.global_position
	var puddles: Array = []
	for k: int in 9:
		var p: Vector3 = pp + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * rng.randf_range(2.5, 14.0)
		if world.field.layout and world.field.layout.surface_at(p.x, p.z) == CityLayout.Surface.BUILDING:
			continue
		var pd: MeshInstance3D = EventProps.puddle(rng.randf_range(0.5, 1.3))
		add_child(pd)
		pd.global_position = _gp(p) + Vector3(0, 0.03, 0)
		pd.rotation.y = rng.randf() * TAU
		pd.scale = Vector3(0.01, 1, 0.01)
		pd.create_tween().tween_property(pd, "scale", Vector3(1, 1, randf_range(0.55, 0.9)), 6.0)
		puddles.append(pd)
	active["puddles"] = puddles
	hud.set_rain(true)
	return true


func _update_rain(_delta: float) -> void:
	var rain: Node3D = active.get("rain")
	if is_instance_valid(rain):
		rain.global_position = world.patch.global_position
	for pd: Variant in active.get("puddles", []):
		if is_instance_valid(pd):
			var m: StandardMaterial3D = (pd as MeshInstance3D).material_override
			m.emission_energy_multiplier = 0.22 + 0.14 * sin(_anim_t * 2.3 + (pd as Node3D).position.x)
	if _tick_t > 1.0:
		_tick_t = 0.0
		var g: Garden = world.get("garden") as Garden
		if g:
			for s: int in g.slot_species.size():
				if g.slot_species[s] >= 0 and g.slot_water[s] < 30.0:
					g.water(s, 30.0 - g.slot_water[s])
					active["watered"] = int(active["watered"]) + 1
	active["progress"] = "Every plant is drinking"
	if float(active["left"]) <= 0.0:
		# Puddles linger and dry slowly after the rain.
		for pd: Variant in active.get("puddles", []):
			if is_instance_valid(pd):
				var tw := (pd as Node3D).create_tween()
				tw.tween_interval(10.0)
				tw.tween_property(pd, "scale", Vector3(0.01, 1, 0.01), 12.0)
				tw.tween_callback((pd as Node).queue_free)
		var got: String = _pay(def("rain_shower").get("reward", {}), world.patch.global_position, "rain_shower")
		_finish(true, "The rain moves on. The ground soaked it up: %s" % got)


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
	world.interactables.register(r, 2.8, "E   fix %s's hiccup" % r.robot_name, _fix_hiccup)
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
		Vfx.burst("steam", bot.global_position + Vector3(0, 1.0, 0), Color(0.9, 0.9, 0.9, 0.5), 0.5)
		Audio.play("squeak", rng.randf_range(1.3, 1.6), -10.0)
		if bot.visual:
			var tw := bot.visual.create_tween()
			tw.tween_property(bot.visual, "position:y", 0.18, 0.08)
			tw.tween_property(bot.visual, "position:y", 0.0, 0.18).set_trans(Tween.TRANS_BOUNCE)
	var d: float = bot.global_position.distance_to(world.patch.global_position)
	active["progress"] = "%s is %d m away" % [bot.robot_name, int(d)]
	if float(active["left"]) <= 0.0:
		_finish(false, "%s shook off its hiccups on its own. It looks embarrassed." % bot.robot_name)


func _fix_hiccup() -> void:
	var r: Variant = active.get("robot")
	if active.get("id", "") != "robot_hiccup" or not is_instance_valid(r) or not (r is Robot):
		return
	var bot: Robot = r
	world.interactables.unregister(bot)
	bot.set_physics_process(true)
	Vfx.burst("sparkle", bot.global_position + Vector3(0, 1.0, 0), Color(1.0, 0.75, 0.35), 0.9)
	Audio.play("servo", 1.0, -4.0)
	Audio.play("ding", 1.2, -6.0)
	var got: String = _pay(def("robot_hiccup").get("reward", {}), bot.global_position, "robot_hiccup")
	_finish(true, "%s is fixed and back to work. %s" % [bot.robot_name, got])


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
		for h: int in f.hex_count():
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
	an.scale = Vector3.ONE * 0.01
	an.create_tween().tween_property(an, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_BACK)
	Vfx.burst("sparkle", at + Vector3(0, 0.6, 0), Color.html(str(pick["glow"])), 0.6)
	active["animal"] = an
	active["animal_id"] = str(pick["id"])
	active["animal_name"] = str(pick["name"])
	active["animal_body"] = str(pick.get("body", "fox"))
	active["hex"] = best
	active["pos"] = at
	active["goal"] = at
	active["name"] = "Wildlife Visit: %s" % str(pick["name"])
	world.interactables.register(an, 3.4, "E   take a photo of the %s" % str(pick["name"]), _photo)
	return true


func _update_wildlife(delta: float) -> void:
	var an: Node3D = active.get("animal")
	if not is_instance_valid(an):
		_finish(false)
		return
	var goal: Vector3 = active["goal"]
	var to: Vector3 = goal - an.global_position
	to.y = 0.0
	var body: Node3D = an.get_node("Body")
	var hop: bool = str(active["animal_body"]) in ["hare", "hedgehog"]
	if to.length() > 0.25:
		var spd: float = 1.3 if hop else 0.8
		an.global_position += to.normalized() * minf(spd * delta, to.length())
		an.global_position.y = _ground(an.global_position.x, an.global_position.z)
		an.rotation.y = lerp_angle(an.rotation.y, atan2(-to.x, -to.z), minf(delta * 4.0, 1.0))
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
	active["progress"] = "%s, %d m away" % [str(active["animal_name"]), int(an.global_position.distance_to(world.patch.global_position))]
	if float(active["left"]) <= 0.0:
		_animal_leave(an)
		_finish(false, "The %s wandered off. It'll be back somewhere green." % str(active["animal_name"]))


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
	_finish(true, ("Snap! The %s is in your Collection. %s" if first else "Snap! Another lovely shot of the %s. %s") % [str(active.get("animal_name", "visitor")), got])


# --- Rare part signal --------------------------------------------------------------------------

func _start_signal(_d: Dictionary, force: bool) -> bool:
	var f: HexField = world.field
	var pp: Vector3 = world.patch.global_position
	var best: int = -1
	var best_d: float = INF
	for i: int in f.part_pos.size():
		if f.part_found[i] == 1:
			continue
		var dd: float = Vector2(f.part_pos[i].x - pp.x, f.part_pos[i].z - pp.z).length()
		var score: float = absf(dd - 25.0)  # not on top of Patch, not across the map
		if (dd >= 8.0 or force) and score < best_d:
			best_d = score
			best = i
	if best < 0:
		return false
	var fuzzy: Vector3 = f.part_pos[best] + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.8, 2.6)
	var pos: Vector3 = _gp(fuzzy)
	active["part"] = best
	active["pos"] = pos
	var col: Color = active["color"]
	var root := Node3D.new()
	root.name = "Signal"
	add_child(root)
	_keep(root)
	root.global_position = pos
	root.add_child(EventProps.beacon(col, 34.0, 0.4))
	var ring: MeshInstance3D = EventProps.zone_ring(4.0, col)
	root.add_child(ring)
	active["ring"] = ring
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 1.5
	light.omni_range = 6.0
	light.position = Vector3(0, 1.5, 0)
	root.add_child(light)
	return true


func _update_signal() -> void:
	var ring: MeshInstance3D = active.get("ring")
	if is_instance_valid(ring):
		var s: float = 1.0 + 0.06 * sin(_anim_t * 5.0)
		ring.scale = Vector3(s, 1, s)
	var idx: int = int(active["part"])
	var d: float = Vector2(world.field.part_pos[idx].x - world.patch.global_position.x, world.field.part_pos[idx].z - world.patch.global_position.z).length()
	active["progress"] = "Signal %d%%" % int(clampf(1.0 - d / 40.0, 0.0, 1.0) * 100.0)
	if world.field.part_found[idx] == 1:
		var got: String = _pay(def("rare_part_signal").get("reward", {}), world.field.part_pos[idx], "rare_part_signal")
		Audio.play("fanfare", 1.0, -6.0)
		_finish(true, "That was the signal: a stash with a rare part inside. %s" % got)
	elif float(active["left"]) <= 0.0:
		_finish(false, "The signal faded. The part is still down there; the detector will find it.")


# --- Ledger audit ------------------------------------------------------------------------------

func _start_audit(d: Dictionary, force: bool) -> bool:
	var r: float = float(d.get("zone_radius", 5.0))
	var spot: Dictionary = _junk_spot(r, 25, 8.0, 35.0, force)
	if spot.is_empty():
		return false
	var pos: Vector3 = spot["pos"]
	var zone: PackedInt32Array = spot["zone"]
	var zs: Dictionary = {}
	for pid: int in zone:
		zs[pid] = true
	active["pos"] = pos
	active["zone"] = zone
	active["zone_set"] = zs
	active["player"] = 0
	active["drone_n"] = 0
	active["working"] = false
	active["pace"] = clampf(1.0 / maxf(Economy.stat("scoop_rate") * float(d.get("drone_rate_frac", 0.25)), 0.01), 0.2, 1.2)
	var col: Color = active["color"]
	var root := Node3D.new()
	root.name = "Audit"
	add_child(root)
	_keep(root)
	root.global_position = pos
	root.add_child(EventProps.zone_ring(r, col))
	var board := Label3D.new()
	board.name = "Score"
	board.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	board.no_depth_test = true
	board.font_size = 64
	board.outline_size = 14
	board.pixel_size = 0.012
	board.modulate = col
	board.position = Vector3(0, 4.2, 0)
	root.add_child(board)
	active["board"] = board
	var drone := LedgerDrone.new()
	drone.friendly = true
	drone.ground_y = _ground
	add_child(drone)
	_keep(drone)
	var dir := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
	drone.global_position = pos + dir * 50.0 + Vector3(0, 18, 0)
	active["drone"] = drone
	var tw := drone.create_tween()
	tw.tween_property(drone, "global_position", pos + Vector3(0, 4.5, 0), 5.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void:
		if active.get("id", "") == "ledger_audit":
			active["working"] = true
			drone.set_beam(2.0))
	return true


func _update_audit(_delta: float) -> void:
	var drone: LedgerDrone = active.get("drone")
	var zone: PackedInt32Array = active["zone"]
	var alive: Array[int] = []
	for pid: int in zone:
		if world.field.piece_alive[pid] == 1:
			alive.append(pid)
	var board: Label3D = active.get("board")
	if is_instance_valid(board):
		board.text = "AUDIT   YOU %d  :  %d DRONE" % [int(active["player"]), int(active["drone_n"])]
	active["progress"] = "You %d  :  %d Drone   ·   %d left" % [int(active["player"]), int(active["drone_n"]), alive.size()]
	if bool(active["working"]) and is_instance_valid(drone) and _tick_t >= float(active["pace"]) and not alive.is_empty():
		_tick_t = 0.0
		var best: int = alive[0]
		var bd: float = INF
		for pid: int in alive:
			var dd: float = Vector2(world.field.piece_pos[pid].x - drone.global_position.x, world.field.piece_pos[pid].z - drone.global_position.z).length_squared()
			if dd < bd:
				bd = dd
				best = pid
		var pp: Vector3 = world.field.piece_pos[best]
		Vfx.burst("sparkle", pp + Vector3(0, 0.2, 0), Color(0.4, 1.0, 0.6), 0.3)
		world.collect_piece(best)
		active["drone_n"] = int(active["drone_n"]) + 1
		var old: Variant = active.get("dtw")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
		var tw := drone.create_tween()
		tw.tween_property(drone, "global_position", Vector3(pp.x, _ground(pp.x, pp.z) + 4.0, pp.z), float(active["pace"]) * 0.9)
		active["dtw"] = tw
	if alive.size() <= 2 or float(active["left"]) <= 0.0:
		var you: int = int(active["player"])
		var dn: int = int(active["drone_n"])
		var won: bool = you >= dn and you > 0
		var old2: Variant = active.get("dtw")
		if old2 is Tween and (old2 as Tween).is_valid():
			(old2 as Tween).kill()
		if is_instance_valid(drone):
			_props.erase(drone)
			drone.set_beam(0.0)
			var dir := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
			var tw := drone.create_tween()
			tw.tween_property(drone, "global_position", drone.global_position + dir * 60.0 + Vector3(0, 22, 0), 6.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			tw.tween_callback(drone.queue_free)
		if won:
			var got: String = _pay(def("ledger_audit").get("reward", {}), active["pos"], "ledger_audit")
			Audio.play("fanfare", 1.2, -6.0)
			_finish(true, "Audit won, %d to %d! The Ledger stamps it APPROVED. %s" % [you, dn, got])
		else:
			var c: float = progress_cubes(20.0)
			GameState.add_currency("cubes", BigNum.from_float(c))
			_finish(false, "The drone won the audit, %d to %d. It left a tip anyway: +%s cubes." % [dn, you, Settings.fmt(BigNum.from_float(c))])


# --- Queries for the HUD and Command view --------------------------------------------------------

func marker_pos() -> Variant:
	if active.is_empty():
		return null
	return active.get("pos")


func time_left() -> float:
	return float(active.get("left", 0.0))
