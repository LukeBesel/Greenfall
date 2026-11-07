class_name FrontierDistrict
extends Node
## The live side of a frontier district (planet/frontiers.gd has the rules, data/frontiers.json
## the numbers, planet/frontier_view.gd the visuals). Built by the slice only on frontier hubs.
##   Dust Flats    sandstorms every few minutes re-dust clean, bare hexes that no Sustained hex
##                 shelters; the base well is dry, so Drips refill at Water Tanks.
##   Frozen Port   junk is locked in ice. Lumi's beam thaws slowly, heaters (E, cubes) thaw a hex
##                 fast and warm the hexes around it. Plants need a greenhouse (E with the seed
##                 tool) or Cold-Hardy Seeds.
##   Sunken City   mostly water. When 80% of the next ring's water is skimmed the old pumps run,
##                 the water drops a stage and that ring becomes streets (with stranded debris).
##   Cradle Returns the landing pad must be clean and Sustained and 70% of the district Growing;
##                 then EventBus.cradle_district_complete fires once (the ark finale hook).
## Two phases: prepare() right after the field is restored (before views, garden and hex levels
## are built: ice locks, drained streets, base start level), setup() once the scene is built.
## State: GameState.world["frontier"] (see persist_save).

const TICK_S: float = 0.25

var world: Node
var kind: Dictionary = {}
var kid: String = ""
var view: FrontierView
## Frozen Port: ice per hex (1 solid .. 0 thawed), heater and greenhouse hex ids.
var ice := PackedFloat32Array()
var heaters: Array = []
var greenhouses: Array = []
## Sunken City: stages drained so far and the hexes they revealed, in order.
var drained: int = 0
var drain_order: Array = []
## Dust Flats: seconds to the next storm, storm phase (0 calm, 1 warning, 2 blowing).
var storm_t: float = 0.0
var storm_phase: int = 0
var storm_left: float = 0.0
var storms: int = 0
## Cradle Returns: the finale hook has fired.
var done: bool = false
var growing_frac: float = 0.0
var cradle: Dictionary = {}

var _rng := RandomNumberGenerator.new()
var _tick: float = 0.0
var _slow: float = 0.0
var _act: Node3D
var _hint_t: float = 0.0
var _card: Label
var _card_box: PanelContainer
var _storm_amt: float = 0.0


# --- Phase 1: before views ---------------------------------------------------------------------

func prepare(p_world: Node) -> void:
	world = p_world
	var field: HexField = world.field
	kind = Frontiers.def_for_biome(field.biome)
	kid = str(kind.get("id", ""))
	_rng.seed = field.seed_value + 6060 + int(Time.get_ticks_usec() % 100000)
	var st: Dictionary = GameState.world.get("frontier", {})
	storms = int(st.get("storms", 0))
	storm_t = float(st.get("storm_t", kind.get("storm", {}).get("first_s", 150.0)))
	heaters = _ints(st.get("heaters", []))
	greenhouses = _ints(st.get("greenhouses", []))
	done = bool(st.get("done", false))
	growing_frac = float(st.get("growing_frac", 0.0))
	if not GameState.world.has("hub_level") and kind.has("start_hub_level"):
		GameState.world["hub_level"] = int(kind["start_hub_level"])
	match kid:
		"frozen_port":
			var raw: PackedFloat32Array = Marshalls.base64_to_raw(str(st.get("ice", ""))).to_float32_array() if st.has("ice") else PackedFloat32Array()
			ice = raw if raw.size() == field.hex_count() else Frontiers.initial_ice(field, kind.get("ice", {}))
			if DevHooks.has("thaw-all"):
				ice.fill(0.0)
			_update_locks()
		"sunken_city":
			drain_order = _ints(st.get("drain_order", []))
			drained = int(st.get("drained", 0))
			for h: Variant in drain_order:
				if int(h) >= 0 and int(h) < field.hex_count():
					Frontiers.drain_hex(field, int(h))


## Saved id lists come back from JSON as floats.
static func _ints(a: Variant) -> Array:
	var out: Array = []
	if a is Array:
		for v: Variant in a:
			out.append(int(v))
	return out


func _update_locks() -> void:
	var field: HexField = world.field
	field.locked.clear()
	for id: int in ice.size():
		if ice[id] > 0.0:
			field.locked[id] = true


# --- Phase 2: the scene is built ---------------------------------------------------------------

func setup() -> void:
	add_to_group("persist")
	var field: HexField = world.field
	for h: Variant in greenhouses:
		world.garden.hex_grow_bonus[int(h)] = float(kind.get("ice", {}).get("greenhouse_grow", 0.25))
	view = FrontierView.new()
	view.name = "FrontierView"
	view.district = self
	world.add_child(view)
	view.build()
	var sd: SkyDirector = world.get("sky_director")
	if sd:
		sd.grade = kind.get("grade", {})
	_act = Node3D.new()
	_act.name = "FrontierAction"
	world.add_child(_act)
	world.interactables.register(_act, 1.2, _prompt, _use, _act_enabled)
	_build_card()
	Codex.unlock("frontiers:" + kid)
	if kid == "cradle_returns":
		Codex.unlock("frontiers:ark_pad")
	if not GameState.flags.get("frontier_seen_" + kid, false):
		GameState.flags["frontier_seen_" + kid] = true
		var seen: Array = GameState.flags.get("frontiers_visited", [])
		if not (kid in seen):
			seen.append(kid)
		GameState.flags["frontiers_visited"] = seen
		get_tree().create_timer(5.0, false).timeout.connect(func() -> void:
			EventBus.toast.emit("%s: %s" % [Frontiers.kind_name(kid), tr(str(kind.get("tagline", "")))], "story")
			if world.get("wren") != null:
				world.wren.say("frontier_" + kid, 1.0, true))
	_dev_hooks()
	_refresh_summary()
	print("[frontier] %s ready: radius=%d pieces=%d junk_hexes=%d locked=%d drained=%d" % [kid, field.radius, field.piece_count(), field.junk_hex_count, field.locked.size(), drained])


func _dev_hooks() -> void:
	if DevHooks.has("frontier-nohud"):  # clean landscape screenshots: hide every overlay (see _process)
		set_meta("nohud", true)
	if DevHooks.has("frontier-done"):  # Cradle: fire the completion hook now (screenshots / story tests)
		get_tree().create_timer(DevHooks.get_f("frontier-done", 3.0)).timeout.connect(complete)
	if DevHooks.has("frontier-cam"):  # --frontier-cam=dist,pitch,yaw[,fov] (landscape screenshots)
		var c: PackedStringArray = DevHooks.get_s("frontier-cam", "30,-0.3,0").split(",")
		var cam: CameraRig = world.cam
		cam.max_distance = maxf(cam.max_distance, float(c[0]))
		cam.distance = float(c[0])
		cam.pitch = float(c[1]) if c.size() > 1 else -0.3
		cam.yaw = float(c[2]) if c.size() > 2 else cam.yaw
		(cam.get("_arm") as SpringArm3D).collision_mask = 0  # [vqa] the yard sign/fence pulled the arm in
		if c.size() > 3:  # [vqa] 4th value: field of view (a narrow lens keeps the towers upright)
			Settings.fov = float(c[3])
			cam.camera.fov = Settings.fov
		cam.snap()
	if DevHooks.has("storm"):  # --storm[=S]: a sandstorm S seconds after start (warning skipped)
		storm_t = DevHooks.get_f("storm", 3.0)
		if storm_t < 0.5:
			storm_t = 0.5
	if DevHooks.has("storm-hold"):  # keep the storm blowing (screenshots)
		storm_phase = 2
		storm_left = 9999.0
		_storm_amt = 1.0
	if DevHooks.has("frontier-heaters"):  # --frontier-heaters=N: N heaters on the nearest iced hexes
		var iced: Array = range(ice.size()).filter(func(h: int) -> bool: return ice[h] > 0.0)
		iced.sort_custom(func(a: int, b: int) -> bool: return world.field.hex_center(a).length() < world.field.hex_center(b).length())
		for h: int in iced.slice(0, int(DevHooks.get_f("frontier-heaters", 3.0))):
			_place_heater(h, false)
	if DevHooks.has("frontier-greenhouses"):
		var ok: Array = range(world.field.hex_count()).filter(func(h: int) -> bool: return world.field.hex_hub[h] == 0 and not world.field.is_water(h) and (ice.is_empty() or ice[h] <= 0.0))
		for h: int in ok.slice(0, int(DevHooks.get_f("frontier-greenhouses", 2.0))):
			_build_greenhouse(h, false)
	if DevHooks.has("drain"):  # --drain=N: run the pumps N times now (skims the rings first)
		for k: int in int(DevHooks.get_f("drain", 1.0)):
			for h: int in Frontiers.drain_hexes(world.field, drained + 1, kind.get("flood", {})):
				_clear_hex(h)
			drain_next(false)


## Dev (--future=N previews): thaw every hex and run every pump stage before the preview cleans
## and plants the district.
func dev_pre_preview() -> void:
	if kid == "frozen_port":
		ice.fill(0.0)
		world.field.locked.clear()
	if kid == "sunken_city":
		var st: int = int(kind.get("flood", {}).get("stages", 3))
		while drained < st:
			for h: int in Frontiers.drain_hexes(world.field, drained + 1, kind.get("flood", {})):
				_clear_hex(h)
			drain_next(false)


## Removes every piece of a hex through the slice (dev/screenshots).
func _clear_hex(h: int) -> void:
	var was: Variant = world.field.locked.get(h)
	world.field.locked.erase(h)
	for pid: int in world.field.hex_pieces[h]:
		if world.field.piece_alive[pid] == 1:
			world.collect_piece(pid)
	if was != null and ice.size() > h and ice[h] > 0.0:
		world.field.locked[h] = true


func _process(delta: float) -> void:
	if world == null or view == null:
		return
	_tick += delta
	_hint_t = maxf(0.0, _hint_t - delta)
	if has_meta("nohud"):
		for c: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
			(c as CanvasLayer).visible = false
	_update_act()
	var paused: bool = bool(world.get("launching")) or world.any_modal_open()
	match kid:
		"dust_flats":
			if not paused:
				_storm_step(delta)
			_storm_amt = move_toward(_storm_amt, 1.0 if storm_phase == 2 else 0.0, delta * 0.35)
			view.set_storm(_storm_amt)
			var sd: SkyDirector = world.get("sky_director")
			if sd:
				sd.storm = _storm_amt
	if _tick < TICK_S:
		return
	var dt: float = _tick
	_tick = 0.0
	_slow += dt
	match kid:
		"frozen_port":
			_thaw_step(dt)
		"sunken_city":
			if Frontiers.drain_ready(world.field, drained, kind.get("flood", {})):
				drain_next(true)
	if _slow >= 2.0:
		_slow = 0.0
		_refresh_summary()
		if kid == "cradle_returns":
			_cradle_step()
		_update_card()


func _refresh_summary() -> void:
	var hl: HexLevels = world.get("hex_levels")
	if hl == null:
		return
	var land: int = 0
	var good: int = 0
	var sum_lv: float = 0.0
	for h: Variant in hl.levels:
		land += 1
		sum_lv += float(hl.levels[h])
		if int(hl.levels[h]) >= 3:
			good += 1
	if kid == "sunken_city":
		# [beat] Streets still under water count too: otherwise the six dry hexes alone made the
		# Sunken City "50% Growing" minutes after landing (the Cradle unlock).
		var fl: Dictionary = kind.get("flood", {})
		for id: int in world.field.hex_count():
			if world.field.is_water(id) and Frontiers.flood_stage_of(world.field, id, fl) > drained:
				land += 1
	growing_frac = float(good) / maxf(land, 1.0)
	var restore: float = sum_lv / maxf(land * 5.0, 1.0)
	var sd: SkyDirector = world.get("sky_director")
	if sd:
		sd.grade_amt = 1.0 - 0.6 * restore
	if view:
		view.set_restore(restore)


# --- Dust Flats: sandstorms --------------------------------------------------------------------

func _storm_step(dt: float) -> void:
	var s: Dictionary = kind.get("storm", {})
	match storm_phase:
		0:
			storm_t -= dt
			if storm_t <= float(s.get("warn_s", 18.0)) and not DevHooks.has("storm"):
				storm_phase = 1
				EventBus.toast.emit(tr("Sandstorm on the horizon. Bare clean ground will get buried; planted and sheltered hexes hold."), "story")
				if world.get("wren") != null:
					world.wren.say("sandstorm_warn", 1.0, true)
				Audio.play("whoosh", 0.5, -6.0)
			elif storm_t <= 0.0:
				_start_storm()
		1:
			storm_t -= dt
			if storm_t <= 0.0:
				_start_storm()
		2:
			storm_left -= dt
			if storm_left <= float(s.get("len_s", 24.0)) * 0.45 and not bool(get_meta("hit", false)):
				set_meta("hit", true)
				storm_hit()
			if storm_left <= 0.0:
				storm_phase = 0
				set_meta("hit", false)
				var ev: Array = s.get("every_s", [300, 480])
				storm_t = _rng.randf_range(float(ev[0]), float(ev[1]))


func _start_storm() -> void:
	storm_phase = 2
	storm_left = float(kind.get("storm", {}).get("len_s", 24.0))
	set_meta("hit", false)
	Audio.play("whoosh", 0.35, -2.0)
	EventBus.shake_requested.emit(0.12)


## The storm drops junk back on unsheltered clean, bare hexes. Returns the hexes it hit.
func storm_hit() -> Array[int]:
	var field: HexField = world.field
	var s: Dictionary = kind.get("storm", {})
	var fences: bool = Research.has("dune_fences")
	var ring: int = int(s.get("fences_ring", 2)) if fences else int(s.get("shelter_ring", 1))
	var hl: HexLevels = world.get("hex_levels")
	var cands: Array[int] = Frontiers.storm_candidates(field, hl.levels if hl else {}, _is_planted, int(s.get("shelter_level", 4)), ring)
	for k: int in range(cands.size() - 1, 0, -1):
		var j: int = _rng.randi() % (k + 1)
		var t: int = cands[k]
		cands[k] = cands[j]
		cands[j] = t
	var n: int = Frontiers.storm_count(s, field.cleaned_count, fences)
	var hit: Array[int] = []
	for h: int in cands:
		if hit.size() >= n:
			break
		var pids: PackedInt32Array = Frontiers.storm_pieces(field, h, _rng, float(s.get("frac", 0.07)), int(s.get("min_pieces", 8)), int(s.get("max_pieces", 40)))
		if pids.is_empty():
			continue
		field.revive_pieces(pids)
		if world.get("planet") != null:
			world.planet.set_junk(world.slice_cells[h], 1.0 - field.removed_fraction(h))
		world.view.refresh_hex(h)
		if view:
			view.dust_hex(h)
		hit.append(h)
	storms += 1
	GameState.inc_stat("sandstorms")
	Codex.unlock("frontiers:sandstorm")
	EventBus.field_progress_changed.emit(field.cleaned_count, field.junk_hex_count)
	if not hit.is_empty() and world.get("wren") != null:
		world.wren.say("sandstorm_over", 1.0, true, {"n": hit.size()})
	EventBus.toast.emit(tr_n("The sandstorm buried %d hex again. Sustained hexes shelter their neighbours.", "The sandstorm buried %d hexes again. Sustained hexes shelter their neighbours.", hit.size()) % hit.size() if not hit.is_empty() else tr("The storm blew over. Everything held."), "info")
	print("[frontier] storm %d hit %s" % [storms, str(hit)])
	return hit


func _is_planted(hid: int) -> bool:
	var g: Garden = world.get("garden")
	if g == null:
		return false
	for s: int in g.hex_slots.get(hid, PackedInt32Array()):
		if g.slot_species[s] >= 0:
			return true
	return false


# --- Frozen Port: ice, heaters, greenhouses ---------------------------------------------------

func _beam_hex() -> int:
	var p: Patch = world.get("patch") as Patch
	if p == null or p.tool != Patch.Tool.SCOOP or p.input == null or not p.input.scoop_held():
		return -1
	var h: int = world.field.hex_at(p.global_position + p.forward() * 2.0)
	return h if h >= 0 and h < ice.size() and ice[h] > 0.0 else -1


func _thaw_step(dt: float) -> void:
	var bh: int = _beam_hex()
	var rates: Dictionary = Frontiers.thaw_rates(world.field, kind.get("ice", {}), heaters, bh, Research.has("heat_pumps"), Research.has("thermal_lance"))
	if bh >= 0 and randf() < 0.5:
		var p: Patch = world.patch
		Vfx.burst("steam", p.global_position + p.forward() * 2.0 + Vector3(0, 0.3, 0), Color(0.9, 0.95, 1.0, 0.6), 0.4)
	var freed: Array[int] = Frontiers.thaw_step(ice, rates, dt)
	for h: int in rates:
		if view and (ice[h] > 0.0 or h in freed):
			view.set_ice(h, ice[h])
	for h: int in freed:
		_on_thawed(h)


func _on_thawed(h: int) -> void:
	world.field.locked.erase(h)
	if view:
		view.set_ice(h, 0.0)
	Vfx.burst("steam", world.field.hex_center(h) + Vector3(0, 0.4, 0), Color(0.92, 0.96, 1.0, 0.7), 2.0)
	Audio.play("steam", 0.8, -6.0)
	GameState.inc_stat("hexes_thawed")
	Codex.unlock("frontiers:thaw")
	if int(GameState.stats.get("hexes_thawed", 0)) <= 1:
		EventBus.toast.emit(tr("The ice let go. The junk underneath is just junk again."), "info")
		if world.get("wren") != null:
			world.wren.say("thaw_first", 1.0, true)


func heater_cost() -> BigNum:
	return BigNum.from_float(Frontiers.heater_cost(kind.get("ice", {}), heaters.size()))


func greenhouse_cost() -> BigNum:
	return BigNum.from_float(Frontiers.greenhouse_cost(kind.get("ice", {}), greenhouses.size()))


func _place_heater(h: int, pay: bool) -> bool:
	if h < 0 or h in heaters or heaters.size() >= int(kind.get("ice", {}).get("heater_max", 16)):
		return false
	if pay and not GameState.spend("cubes", heater_cost()):
		return false
	heaters.append(h)
	if view:
		view.add_heater(h, pay)
	GameState.inc_stat("heaters_placed")
	return true


func _build_greenhouse(h: int, pay: bool) -> bool:
	if h < 0 or h in greenhouses:
		return false
	if pay and not GameState.spend("cubes", greenhouse_cost()):
		return false
	greenhouses.append(h)
	world.garden.hex_grow_bonus[h] = float(kind.get("ice", {}).get("greenhouse_grow", 0.25))
	if view:
		view.add_greenhouse(h, pay)
	GameState.inc_stat("greenhouses_built")
	Codex.unlock("frontiers:greenhouse")
	if pay and world.get("wren") != null:
		world.wren.say("greenhouse_built", 1.0, true)
	return true


## Garden hook: can an empty slot on this hex take a seed? (Frozen Port cold rules)
func slot_plantable(hid: int) -> bool:
	if kid != "frozen_port":
		return true
	if hid >= 0 and hid < ice.size() and ice[hid] > 0.0:
		return false
	return hid in greenhouses or Research.has("cold_hardy_seeds")


# --- The E action (heater / greenhouse) ------------------------------------------------------

func _target_hex() -> int:
	var p: Patch = world.get("patch") as Patch
	if p == null:
		return -1
	var h: int = world.field.hex_at(p.global_position)
	var f: int = world.field.hex_at(p.global_position + p.forward() * 3.0)
	if kid == "frozen_port":
		for c: int in [h, f]:
			if c >= 0 and c < ice.size() and ice[c] > 0.0 and not (c in heaters):
				return c
	return h


func _action() -> String:
	if kid != "frozen_port":
		return ""
	var h: int = _target_hex()
	if h < 0 or world.field.hex_hub[h] != 0:
		return ""
	if ice[h] > 0.0 and not (h in heaters):
		return "heater"
	var p: Patch = world.patch
	if p.tool == Patch.Tool.PLANT and ice[h] <= 0.0 and world.field.is_clean(h) and not world.field.is_water(h) and not (h in greenhouses):
		return "greenhouse"
	return ""


func _update_act() -> void:
	if _act and world.get("patch") != null:
		_act.global_position = world.patch.global_position


func _act_enabled() -> bool:
	return _action() != ""


func _prompt() -> String:
	match _action():
		"heater":
			return tr("E   Light a heater on this ice · %s cubes") % Settings.fmt(heater_cost())
		"greenhouse":
			return tr("E   Build a greenhouse on this hex · %s cubes") % Settings.fmt(greenhouse_cost())
	return ""


func _use() -> void:
	var h: int = _target_hex()
	match _action():
		"heater":
			if not _place_heater(h, true):
				Audio.play("buzz", 1.0, -8.0)
				EventBus.toast.emit(tr("Not enough cubes for a heater.") if heaters.size() < int(kind.get("ice", {}).get("heater_max", 16)) else tr("Heater limit reached. Move on to the next ice once these have done their work."), "info")
		"greenhouse":
			if not _build_greenhouse(h, true):
				Audio.play("buzz", 1.0, -8.0)
				EventBus.toast.emit(tr("Not enough cubes for a greenhouse."), "info")


# --- Sunken City: pumps ------------------------------------------------------------------------

## Runs the pumps once: the next ring of water hexes becomes streets. Clean ones get stranded silt
## debris back (a share of their pieces); dirty ones keep what is left of theirs.
func drain_next(animate: bool) -> Array[int]:
	var field: HexField = world.field
	var flood: Dictionary = kind.get("flood", {})
	if drained >= int(flood.get("stages", 3)):
		return []
	var hs: Array[int] = Frontiers.drain_hexes(field, drained + 1, flood)
	drained += 1
	for h: int in hs:
		Frontiers.drain_hex(field, h)
		drain_order.append(h)
		if field.is_clean(h):
			var pids: PackedInt32Array = Frontiers.storm_pieces(field, h, _rng, float(flood.get("silt_frac", 0.3)), 6, 60)
			field.revive_pieces(pids)
		world.planet.set_junk(world.slice_cells[h], 1.0 - field.removed_fraction(h))
		world.garden.add_hex(h)
		var hl: HexLevels = world.get("hex_levels")
		if hl and not hl.levels.has(h):
			hl.levels[h] = 0
		world.view.refresh_hex(h)
	EventBus.field_progress_changed.emit(field.cleaned_count, field.junk_hex_count)
	if view:
		view.on_drained(hs, animate)
	GameState.inc_stat("drain_stages")
	Codex.unlock("frontiers:pumps")
	if animate:
		EventBus.toast.emit(tr("The old pumps are running. The water drops and a ring of streets comes back up, with a lot of stranded junk."), "story")
		if world.get("wren") != null:
			world.wren.say("drain_stage", 1.0, true)
		EventBus.shake_requested.emit(0.3)
		Audio.play("hydraulic", 0.6, -2.0)
	print("[frontier] drained stage %d: %d hexes" % [drained, hs.size()])
	return hs


# --- Cradle Returns -------------------------------------------------------------------------

func _cradle_step() -> void:
	var hl: HexLevels = world.get("hex_levels")
	if hl == null:
		return
	var before: float = float(cradle.get("pad_clean", 0.0))
	cradle = Frontiers.cradle_progress(world.field, hl.levels, kind)
	if view:
		view.set_cradle(cradle)
	if before < 1.0 and float(cradle["pad_clean"]) >= 1.0 and not GameState.flags.get("cradle_pad_clean", false):
		GameState.flags["cradle_pad_clean"] = true
		EventBus.toast.emit(tr("The landing pad is clean. Now plant it and keep it Sustained."), "story")
		if world.get("wren") != null:
			world.wren.say("cradle_pad", 1.0, true)
	if bool(cradle["done"]) and not done:
		complete()


## The ark-finale hook: fires EventBus.cradle_district_complete once per save (see docs/DECISIONS.md).
func complete() -> void:
	if done:
		return
	done = true
	GameState.flags["cradle_returned"] = true
	GameState.inc_stat("cradle_called")
	if view:
		view.celebrate()
	EventBus.toast.emit(tr("The landing pad is alive and the beacon is lit. The Cradle has answered. It is coming home."), "story")
	if world.get("wren") != null:
		world.wren.say("cradle_complete", 1.0, true)
	Audio.play("fanfare", 0.8, -2.0)
	persist_save()
	EventBus.cradle_district_complete.emit(int(world.hub_index))
	print("[frontier] cradle district complete (hub %d)" % int(world.hub_index))


# --- HUD card ---------------------------------------------------------------------------------

func _build_card() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var cl := CanvasLayer.new()
	cl.layer = 5
	add_child(cl)
	_card_box = PanelContainer.new()
	_card_box.add_theme_stylebox_override("panel", UITheme.box(Color(0.06, 0.08, 0.1, 0.72), Color(0.5, 0.85, 1.0, 0.35), 1, 6, 10))
	_card_box.anchor_top = 0.5
	_card_box.anchor_bottom = 0.5
	_card_box.offset_left = 16
	_card_box.offset_top = 40
	_card_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(_card_box)
	_card = UITheme.label("", 13, UITheme.CREAM)
	_card_box.add_child(_card)
	_update_card()


func card_text() -> String:
	var lines: Array[String] = [Frontiers.kind_name(kid).to_upper()]
	match kid:
		"dust_flats":
			if storm_phase == 2:
				lines.append(tr("Sandstorm blowing"))
			else:
				lines.append(tr("Next sandstorm  %d:%02d") % [int(storm_t) / 60, int(storm_t) % 60])
			lines.append(tr("Well dry: Drips refill at tanks"))
		"frozen_port":
			var n: int = 0
			for v: float in ice:
				if v > 0.0:
					n += 1
			lines.append(tr("%d hexes iced  ·  %d heaters") % [n, heaters.size()])
			lines.append(tr("Greenhouses %d%s") % [greenhouses.size(), tr("  ·  cold-hardy seeds") if Research.has("cold_hardy_seeds") else ""])
		"sunken_city":
			var fl: Dictionary = kind.get("flood", {})
			if drained >= int(fl.get("stages", 3)):
				lines.append(tr("Water down: all streets above water"))
			else:
				lines.append(tr("Pumps: ring %d skimmed %d%% / %d%%") % [drained + 2, int(Frontiers.drain_progress(world.field, drained + 1, fl) * 100.0), int(float(fl.get("drain_at", 0.8)) * 100.0)])
			lines.append(tr("Water level %d / %d") % [int(fl.get("stages", 3)) - drained, int(fl.get("stages", 3))])
		"cradle_returns":
			if done:
				lines.append(tr("The Cradle is coming home"))
			else:
				lines.append(tr("Pad clean %d%%  ·  Sustained %d%%") % [int(float(cradle.get("pad_clean", 0.0)) * 100.0), int(float(cradle.get("pad_level", 0.0)) * 100.0)])
				lines.append(tr("District Growing %d%% / %d%%") % [int(float(cradle.get("district", 0.0)) * 100.0), int(float(kind.get("complete", {}).get("frac", 0.7)) * 100.0)])
	return "\n".join(lines)


func _update_card() -> void:
	if _card:
		_card.text = card_text()


# --- Save -------------------------------------------------------------------------------------

func persist_save() -> void:
	var d: Dictionary = {"kind": kid, "storms": storms, "storm_t": storm_t, "heaters": heaters.duplicate(),
		"greenhouses": greenhouses.duplicate(), "drained": drained, "drain_order": drain_order.duplicate(),
		"done": done, "growing_frac": growing_frac}
	if not ice.is_empty():
		d["ice"] = Marshalls.raw_to_base64(ice.to_byte_array())
	GameState.world["frontier"] = d
