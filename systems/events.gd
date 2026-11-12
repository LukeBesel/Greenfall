class_name WorldEvents
extends Node3D
## World events director (the planet's events table). Every few minutes of play (only while
## playing: no menus, cinematics or rocket flights) one small event starts somewhere near Patch,
## announced by a toast, a WREN line, the EventHUD banner + marker and a pin in Command view.
## Each points at cleaning, pressing or tending:
##   salvage_surge     a hex glows: Patch's bales get 3x value for junk scooped there (2 min)
##   rain_shower       rain keeps every plant watered (2 min), puddles shimmer
##   rare_part_signal  a violet beam marks a buried part; dig it up for a bonus rare part
##   ledger_audit      (after the Ledger arc) a friendly drone races you to clear a ring of junk
## Nothing is ever lost: an event that times out just ends. Rewards scale with progress (see
## progress_cubes) so they stay a spike, never a flood: never above reward.max_income_s of income. Also owns the cleaning streak (Streak)
## and the per-bale bonus (streak tier + surge share), applied by Patch when a bale is pressed.
## Persistent bits live in GameState.flags["events"]: {next_in, recent, done{id: n}}.

signal event_started(id: String)
signal event_ended(id: String, handled: bool)
signal streak_tier_up(tier: int)

const TABLE: String = "events"

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
		_cfg = Economy.planet_table(TABLE)
		Economy.drop_on_planet_change(_drop_planet_cache)
	return _cfg


static func _drop_planet_cache() -> void:
	_cfg = {}


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
		if str(req.get("flag", "")) != "" and not bool((ctx.get("flags", GameState.flags) as Dictionary).get(str(req["flag"]), false)):
			ok = false  # [pace] needs an unlock (has_baler, has_signal_finder, ...: Pace.sync_flags)
		if id in ["salvage_surge", "ledger_audit"] and int(ctx.get("junk_hexes", 0)) <= 0:
			ok = false
		if id == "rare_part_signal" and int(ctx.get("parts_left", 0)) <= 0:
			ok = false
		if not bool(e.get("enabled", true)):
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
	var rate: float = GameState.income_rate()
	var min_c: float = float(rw.get("min_cubes", 40))
	var c: float = scaled_cubes(rate, earned, secs, float(rw.get("earned_frac", 0.004)) * secs / 90.0, min_c)
	return round(capped_cubes(c, rate, float(rw.get("max_income_s", 0.0)), min_c))


## The rule's ceiling: no reward above max_income_s of current income (0 = no ceiling), and never
## below the floor (an early or idle moment, when the rate is about nothing).
static func capped_cubes(cubes: float, rate: float, max_income_s: float, min_cubes: float) -> float:
	if max_income_s <= 0.0:
		return cubes
	return minf(cubes, maxf(min_cubes, rate * max_income_s))


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
	_dev_hooks.call_deferred()


func _dev_hooks() -> void:
	if DevHooks.has("streak"):
		streak.add_scoop(DevHooks.get_f("streak", 90.0))
		streak.grace_s = 1.0e9  # held for screenshots
	if DevHooks.has("livery"):
		var lid: String = DevHooks.get_s("livery", "livery_neon")
		Looks.grant(CrewLooks.piece(CrewLooks.CREW, CrewLooks.LIVERY, lid), "", true)
		GameState.flags["livery"] = lid
	if DevHooks.has("event"):
		_dev_event_t = DevHooks.get_f("event-at", 3.0)
	if DevHooks.has("event-every"):
		persist_state()["next_in"] = DevHooks.get_f("event-every", 20.0)


## --event-look[=M]: screenshot helper, puts Patch M metres from the event, facing it.
func _dev_look(at: Vector3, dist: float) -> void:
	var p: Patch = world.patch
	# Stand between Lumi (at the base) and the event, looking outward (the sheds stay behind the camera).
	var up: Vector3 = at.normalized()
	var d: Vector3 = at - p.global_position
	d -= up * d.dot(up)
	d = d.normalized() if d.length() > 0.1 else SphereGrid.frame(up).z
	p.place_on_sphere(_gp(at - d * dist) + up * 0.2, d)


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
		var id: String = DevHooks.get_s("event", "salvage_surge")
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
	for h: int in OrbitUp.hexes(f, world.patch.global_position):  # [orbB]
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
	return {"junk_hexes": junk, "planted": planted, "robots": fleet.robot_total() if fleet else 0, "max_hex_level": lvl,
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
	active = {"id": id, "name": tr(str(d.get("name", id))), "color": Color.html(str(d.get("color", "#ffffff"))),
		"left": float(d.get("duration_s", 120)), "dur": float(d.get("duration_s", 120)), "hint": tr(str(d.get("hud", ""))),
		"progress": "", "pos": null}
	var ok: bool = false
	var arg: String = ""
	match id:
		"salvage_surge": ok = _start_surge(d, force)
		"rain_shower": ok = _start_rain(d, force)
		"rare_part_signal": ok = _start_signal(d, force)
		"ledger_audit": ok = _start_audit(d, force)
	if not ok:
		_clear_props()
		active = {}
		return false
	if active.get("pos") is Vector3:
		arg = LedgerArc.compass_label((active["pos"] as Vector3) - world.patch.global_position)
	var toast: String = tr(str(d.get("toast", d.get("name", id))))
	EventBus.toast.emit(toast % arg if "%s" in toast else toast, "story")
	Audio.play("blip", 1.25, -4.0)
	Audio.play("chime", 1.5, -8.0)
	if world.get("wren") != null:
		world.wren.say("event_" + id, 1.0, true)
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
		EventBus.toast.emit(text, "reward")  # [v4calm] item 49: no payout summaries
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
	if hud:
		hud.set_rain(false)


func _keep(n: Node) -> Node:
	_props.append(n)
	return n


## The ground under p.
func _gp(p: Vector3) -> Vector3:
	return (world.field as SphereField).terrain.ground(p.normalized())


## Stand a placed prop upright on the local ground (keeps its yaw).
func _upright(n: Node3D) -> void:
	var sc: Vector3 = n.scale
	n.global_basis = SphereGrid.frame(n.global_position.normalized()) * Basis(Vector3.UP, n.rotation.y)
	n.scale = sc


func _update_active(delta: float) -> void:
	_tick_t += delta
	match str(active["id"]):
		"salvage_surge": _update_surge(delta)
		"rain_shower": _update_rain(delta)
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
					Vfx.float_text(world.field.piece_pos[pid] + OrbitUp.up(world.field.piece_pos[pid]) * 1.0, "x3", Color(1.0, 0.82, 0.3), 0.5, 0.9)
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


func _on_streak_up(tier: int) -> void:
	streak_tier_up.emit(tier)
	var p: Patch = world.patch
	var col: Color = Color(0.45, 0.9, 1.0).lerp(Color(1.0, 0.75, 0.25), float(tier) / maxf(streak.max_tier, 1))
	Audio.play_scale("chime", tier + 2, -8.0)
	Vfx.ring(p.global_position + OrbitUp.up(p.global_position) * 0.1, 1.2 + tier * 0.25, col, 0.5)
	Vfx.float_text(p.global_position + OrbitUp.up(p.global_position) * 2.2, tr("STREAK x%d  +%d%%") % [tier, int(round(streak.bonus() * 100.0))], col, 0.55, 0.9)
	var best: float = float(GameState.stats.get("best_streak_tier", 0))
	if tier > best:
		GameState.stats["best_streak_tier"] = tier
	if tier >= streak.max_tier:
		Vfx.burst("sparkle", p.global_position + OrbitUp.up(p.global_position) * 1.2, col, 1.0)
		GameState.inc_stat("max_streaks")
		if int(GameState.stats["max_streaks"]) == 1 or rng.randf() < 0.3:  # always the first time
			if world.get("wren") != null:
				world.wren.say("streak_max", 1.0)


# --- Rewards -----------------------------------------------------------------------------------

func _range_i(v: Variant) -> int:
	if v is Array:
		return rng.randi_range(int(v[0]), int(v[1]))
	return int(v)


## Grants an event reward and shows it at `at`. Returns a summary ("+120 cubes  +8 bolts ...").
func _pay(rw: Dictionary, at: Vector3) -> String:
	var bits: Array[String] = []
	if rw.has("income_s"):
		var c: float = progress_cubes(float(rw["income_s"]))
		GameState.add_currency("cubes", BigNum.from_float(c))
		bits.append(tr("+%s cubes") % Settings.fmt(BigNum.from_float(c)))
	if rw.has("parts"):  # [money] bolts/materials are Parts now
		var b: int = _range_i(rw["parts"])
		GameState.add_currency("parts", BigNum.from_float(b))
		bits.append(L10nFmt.reward("parts", b))
	if rw.has("seeds") and GameState.flags.get("seeds_unlocked", false):
		var s: int = _range_i(rw["seeds"])
		GameState.add_currency("seeds", BigNum.from_float(s))
		bits.append(tr("+%d seeds") % s)
	if rw.has("part_rarity"):  # one robot part of one of two rarities (3 in 4 the first)
		var pr: Array = rw["part_rarity"]
		var r: int = int(pr[0]) if rng.randf() < 0.75 else int(pr[1])
		var t: int = rng.randi() % maxi(Economy.parts.get("types", [1]).size(), 1)
		RobotParts.salvage(t, r)  # [ui2] a found robot part pays Parts
		bits.append(RobotParts.gain_text(r))
	var text: String = "  ".join(bits)
	if text != "":
		Vfx.float_text(at + OrbitUp.up(at) * 1.6, text, Color(0.75, 1.0, 0.85), 0.55, 1.6)
	Audio.play("coin", 1.1, -4.0)
	return text


# --- Spot pickers ------------------------------------------------------------------------------

## Junk hexes with at least `min_alive` pieces, sorted by distance to Patch (within max_d if possible).
func _junk_hexes(min_alive: int, min_d: float, max_d: float) -> Array[int]:
	var f: HexField = world.field
	var pp: Vector3 = world.patch.global_position
	var out: Array[int] = []
	for h: int in OrbitUp.hexes(f, world.patch.global_position):  # [orbB]
		if f.hex_hub[h] != 0 or f.is_water(h) or f.is_clean(h):
			continue
		var alive: int = 0
		for pid: int in f.hex_pieces[h]:
			alive += f.piece_alive[pid]
		if alive < min_alive:
			continue
		var d: float = OrbitUp.ground_dist(pp, f.hex_center(h))  # [orbB]
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
			var d: float = OrbitUp.ground_dist(pp, p)  # [orbB]
			if (d < min_d or d > max_d) and not force:
				continue
			var zone: PackedInt32Array = f.pieces_within(p, radius)
			if zone.size() >= min_n or (force and zone.size() > 0):
				return {"pos": _gp(p), "zone": zone, "hex": h}
	return {}


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
	_upright(glow)  # [orbB]
	active["glow"] = glow
	var beacon: Node3D = EventProps.beacon(col, 18.0, 0.5)
	add_child(beacon)
	_keep(beacon)
	beacon.global_position = c
	_upright(beacon)  # [orbB]
	Vfx.ring(c + OrbitUp.up(c) * 0.2, world.field.hex_size, col, 1.2)
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
		for k: int in (3 if not pids.is_empty() else 0):  # [v3qa] a globe cell out of the near ring has no pieces
			var pid: int = pids[rng.randi() % pids.size()]
			if world.field.piece_alive[pid] == 1:
				Vfx.burst("sparkle", world.field.piece_pos[pid] + OrbitUp.up(world.field.piece_pos[pid]) * 0.2, Color(1.0, 0.85, 0.35), 0.25)
	active["progress"] = tr("%d pieces grabbed at 3x") % int(active.get("took", 0))
	if float(active["left"]) <= 0.0 or world.field.is_clean(h):
		var took: int = int(active.get("took", 0))
		_finish(took > 0, (tr("The surge faded. You grabbed %d pieces at triple value; they pay out when you bale.") % took) if took > 0 else tr("The surge faded. Next time!"))


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
		pd.global_position = _gp(p) + OrbitUp.up(p) * 0.03
		pd.rotation.y = rng.randf() * TAU
		_upright(pd)  # [orbB]
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
	active["progress"] = tr("Every plant is drinking")
	if float(active["left"]) <= 0.0:
		# Puddles linger and dry slowly after the rain.
		for pd: Variant in active.get("puddles", []):
			if is_instance_valid(pd):
				var tw := (pd as Node3D).create_tween()
				tw.tween_interval(10.0)
				tw.tween_property(pd, "scale", Vector3(0.01, 1, 0.01), 12.0)
				tw.tween_callback((pd as Node).queue_free)
		var got: String = _pay(def("rain_shower").get("reward", {}), world.patch.global_position)
		_finish(true, tr("The rain moves on. The ground soaked it up: %s") % got)


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
	_upright(root)  # [orbB]
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
	active["progress"] = tr("Signal %d%%") % int(clampf(1.0 - d / 40.0, 0.0, 1.0) * 100.0)
	if world.field.part_found[idx] == 1:
		var got: String = _pay(def("rare_part_signal").get("reward", {}), world.field.part_pos[idx])
		Audio.play("fanfare", 1.0, -6.0)
		_finish(true, tr("That was the signal: a stash with a rare part inside. %s") % got)
	elif float(active["left"]) <= 0.0:
		_finish(false, tr("The signal faded. The part is still down there; the detector will find it."))


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
	_upright(root)  # [orbB]
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
	add_child(drone)
	_keep(drone)
	var dir := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
	dir = (dir - OrbitUp.up(pos) * dir.dot(OrbitUp.up(pos))).normalized()  # a ground direction
	drone.global_position = pos + dir * 50.0 + OrbitUp.up(pos) * 18.0
	active["drone"] = drone
	var tw := drone.create_tween()
	tw.tween_property(drone, "global_position", pos + OrbitUp.up(pos) * 4.5, 5.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
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
		board.text = tr("AUDIT   YOU %d  :  %d DRONE") % [int(active["player"]), int(active["drone_n"])]
	active["progress"] = tr("You %d  :  %d Drone   ·   %d left") % [int(active["player"]), int(active["drone_n"]), alive.size()]
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
		Vfx.burst("sparkle", pp + OrbitUp.up(pp) * 0.2, Color(0.4, 1.0, 0.6), 0.3)
		world.collect_piece(best)
		active["drone_n"] = int(active["drone_n"]) + 1
		var old: Variant = active.get("dtw")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
		var tw := drone.create_tween()
		tw.tween_property(drone, "global_position", _gp(pp) + OrbitUp.up(pp) * 4.0, float(active["pace"]) * 0.9)
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
			dir = (dir - OrbitUp.up(drone.global_position) * dir.dot(OrbitUp.up(drone.global_position))).normalized()
			var tw := drone.create_tween()
			tw.tween_property(drone, "global_position", drone.global_position + dir * 60.0 + OrbitUp.up(drone.global_position) * 22.0, 6.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			tw.tween_callback(drone.queue_free)
		if won:
			var got: String = _pay(def("ledger_audit").get("reward", {}), active["pos"])
			Audio.play("fanfare", 1.2, -6.0)
			_finish(true, tr("Audit won, %d to %d! The Ledger stamps it APPROVED. %s") % [you, dn, got])
		else:
			var c: float = progress_cubes(20.0)
			GameState.add_currency("cubes", BigNum.from_float(c))
			_finish(false, tr("The drone won the audit, %d to %d. It left a tip anyway: +%s cubes.") % [dn, you, Settings.fmt(BigNum.from_float(c))])


# --- Queries for the HUD and Command view --------------------------------------------------------

func marker_pos() -> Variant:
	if active.is_empty():
		return null
	return active.get("pos")


func time_left() -> float:
	return float(active.get("left", 0.0))
