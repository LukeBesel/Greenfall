class_name HomewardDirector
extends Node
## [home] Wires Homeward (systems/homeward.gd) into a district: measures the current planet's
## restoration every few seconds (stored in the profile), plays the planet beats (arrival memo,
## half-way intercept, restored: relic + Heirloom pick + WREN), dresses a fixed planet (its env
## script and sound theme when those helpers are merged), keeps the interplanetary rocket tier,
## builds the Homeward launch complex and the last-seed bed at Verdance's Cradle Returns, and
## routes the rocket's interplanetary flights (automation/rocket.gd calls start_flight / travel).
## Attached by systems/late_director.gd. Dev hooks:
##   --open=system            open the solar-system map        --planet=N   start on system planet N
##   --planet-restore[=S]     fast-forward: this planet restored S seconds in (default 3)
##   --system-done            every planet restored, all relics, Mk VI drive (the ending is next)
##   --drive=N                set the interplanetary drive tier (5, 6, 7)
##   --cradle-answered        skip "The Cradle Answers" (as if it had played)
##   --cradle-answers[=S]     play "The Cradle Answers" S seconds in
##   --homecoming[=S]         play the Homecoming ending S seconds in (no rocket launch needed)
##   --home-ready             Mk VII built and the last seed planted (launch home from the map)
##   --home-sample            shots: Verdance and Ochre restored, Tidewell half, Mk VI
##   --system-zoom=K          with --open=system: glide in to planet K (--system-zoom-at=S)
##   --home-shots=T1,T2,..    screenshots of the Homeward cinematics at cinematic time T (game seconds),
##                            saved as screenshots/<--home-shot-name>_<i>.png; quits after the last
##   --fly-planet=N[,S]       launch the rocket to system planet N after S seconds (no checks)

const CHECK_S: float = 3.0
const BED_OFFSET := Vector3(10.5, 0.0, 4.5)  # [ship] clear of the Mk VII landing pad (radius ~8.7)

var world: Node
var map: SystemMap
var _t: float = 0.0
var _bed: Node3D
var _complex: Node3D
var _queue: Array[String] = []
var _busy: bool = false


static func attach(slice: Node) -> HomewardDirector:
	var d := HomewardDirector.new()
	d.name = "HomewardDirector"
	d.world = slice
	slice.add_child(d)
	d._setup()
	return d


static func of(slice: Node) -> HomewardDirector:
	return slice.get_node_or_null("HomewardDirector") as HomewardDirector if slice else null


func _setup() -> void:
	map = SystemMap.new()
	map.name = "SystemMap"
	map.world = world
	world.add_child(map)
	var g: Variant = world.get("globe")
	if g is GlobeView:
		(g as GlobeView).open_system = func() -> void: map.open_map(true)
	_dev_hooks()
	# Saves from before Homeward that already reached the Cradle: the answer counts as heard.
	if not Homeward.answered() and Homeward.current_planet() == 0 and GameState.flags.get("cradle_returned", false) \
			and (GameState.flags.get("bloom_finale_seen", false) or GameState.flags.get("cradle_answered", false)):
		Homeward.state()["answered"] = true
		GameState.flags["cradle_answered"] = true
		Homeward.save()
	# The interplanetary rocket travels with Lumi: keep the best in-planet tier on every planet.
	var best: int = maxi(int(GameState.flags.get("rocket_tier", 1)), int(Homeward.state().get("rocket_tier", 1)))
	GameState.flags["rocket_tier"] = best
	Homeward.state()["rocket_tier"] = best
	Homeward.mirror_stats()
	_dress_planet.call_deferred()
	_build_home_site.call_deferred()
	if GameState.flags.has("home_arrived_planet"):
		var k: int = int(GameState.flags["home_arrived_planet"])
		GameState.flags.erase("home_arrived_planet")
		get_tree().create_timer(6.0, false).timeout.connect(func() -> void: _arrival_beat(k))
	elif Homeward.current_planet() > 0 and not Homeward.beat_done("%s_arrive" % _pid()):
		get_tree().create_timer(8.0, false).timeout.connect(func() -> void: _arrival_beat(Homeward.current_planet()))
	if DevHooks.get_s("open", "") == "system":
		(func() -> void:
			map.open_map()
			if DevHooks.has("system-zoom"):  # dev: --system-zoom=K glides in to planet K
				get_tree().create_timer(DevHooks.get_f("system-zoom-at", 2.0), true, false, true).timeout.connect(func() -> void:
					map._select(int(DevHooks.get_f("system-zoom", 1.0)), true))).call_deferred()


func _pid(k: int = -1) -> String:
	return str(Homeward.planet_def(Homeward.current_planet() if k < 0 else k).get("id", ""))


func _dev_hooks() -> void:
	var s: Dictionary = Homeward.state()
	if DevHooks.has("cradle-answered"):
		s["answered"] = true
		GameState.flags["cradle_answered"] = true
	if DevHooks.has("drive"):
		s["drive"] = int(DevHooks.get_f("drive", 5.0))
	if DevHooks.has("system-done"):
		for k: int in Homeward.planets().size():
			(s["pct"] as Dictionary)[str(Homeward.planet_def(k)["id"])] = 1.0
			var rid: String = str(Homeward.planet_def(k).get("relic", ""))
			if rid != "" and not (rid in Homeward.relics()):
				Homeward.relics().append(rid)
		s["answered"] = true
		GameState.flags["cradle_answered"] = true
		s["drive"] = maxi(int(s.get("drive", 0)), 6)
	if DevHooks.has("home-sample"):  # shots: a campaign under way (Verdance and Ochre done, Tidewell half)
		s["answered"] = true
		GameState.flags["cradle_answered"] = true
		s["drive"] = maxi(int(s.get("drive", 0)), 6)
		for kv: Array in [["verdance", 1.0], ["ochre", 1.0], ["tidewell", 0.55], ["rime", 0.12]]:
			(s["pct"] as Dictionary)[kv[0]] = kv[1]
		for rid: String in ["ochre_glass"]:
			if not (rid in Homeward.relics()):
				Homeward.relics().append(rid)
		if Homeward.world_of(3) < 0:
			for k: int in [1, 2, 3]:
				Homeward.make_planet_world(k)
		CradleMode.profile["current"] = 0
		Homeward.mirror_stats()
	if DevHooks.has("home-ready"):
		s["drive"] = 7
		GameState.flags["home_last_seed"] = true
	if DevHooks.has("planet-restore"):
		get_tree().create_timer(DevHooks.get_f("planet-restore", 3.0), false).timeout.connect(func() -> void:
			var k: int = Homeward.current_planet()
			if k >= 0:
				(Homeward.state()["pct"] as Dictionary)[_pid()] = 0.999
				_on_restored(Homeward.store_current(1.0)))
	if DevHooks.has("cradle-answers"):
		get_tree().create_timer(DevHooks.get_f("cradle-answers", 3.0), false).timeout.connect(func() -> void:
			var c := CradleAnswers.new()
			c.world = world
			world.add_child(c)
			c.play())
	if DevHooks.has("fly-planet") and not GameState.flags.get("home_dev_flown", false):  # dev: --fly-planet=N[,S]
		var spec: PackedStringArray = DevHooks.get_s("fly-planet", "1").split(",")
		get_tree().create_timer(float(spec[1]) if spec.size() > 1 else 4.0, false).timeout.connect(func() -> void:
			GameState.flags["home_dev_flown"] = true
			_launch(world, Homeward.PLANET_BASE - int(spec[0])))
	if DevHooks.has("homecoming"):
		get_tree().create_timer(DevHooks.get_f("homecoming", 3.0), false).timeout.connect(func() -> void:
			Homecoming.play_now(world))


# --- Planet look and sound -----------------------------------------------------------------

func _dress_planet() -> void:
	var k: int = Homeward.current_planet()
	if k < 0:
		return
	var id: String = _pid()
	if Audio.has_method("set_planet_theme"):
		Audio.call("set_planet_theme", id)
	if k == 0 or world.get("field") == null:
		return
	var path: String = "res://planet/planets/%s/env.gd" % id
	var reg: Dictionary = registry_entry(id)  # data/planets.json (the planet art helpers), if merged
	if reg.has("env"):
		path = str(reg["env"])
	if ResourceLoader.exists(path):
		var scr: GDScript = load(path) as GDScript
		if scr:
			scr.call("apply", world, world.field, Frontiers.world_kind(world))
			print("[home] planet env %s applied" % path)


## data/planets.json entry for a planet id ({} without the file): a dict keyed by id, or a list of {id: ...}.
static func registry_entry(id: String) -> Dictionary:
	if not FileAccess.file_exists("res://data/planets.json"):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/planets.json"))
	var ps: Variant = (d as Dictionary).get("planets", d) if d is Dictionary else d
	if ps is Dictionary and (ps as Dictionary).get(id) is Dictionary:
		return (ps as Dictionary)[id]
	if ps is Array:
		for e: Variant in ps:
			if e is Dictionary and str((e as Dictionary).get("id", "")) == id:
				return e
	return {}


# --- Restoration -----------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if _t < CHECK_S:
		return
	_t = 0.0
	if Homeward.current_planet() < 0:
		return
	var before: float = Homeward.stored_pct(Homeward.current_planet())
	var got: Array[int] = Homeward.store_current(Homeward.measure_current())
	var now: float = Homeward.stored_pct(Homeward.current_planet())
	if Audio.has_method("set_restoration"):
		Audio.call("set_restoration", now)
	var chart: float = float(Homeward.cfg().get("chart_at", 0.5))
	if Homeward.current_planet() > 0 and before < chart and now >= chart:
		_queue.append("half")
	_on_restored(got)
	_pump()


func _on_restored(got: Array[int]) -> void:
	for k: int in got:
		_queue.append("restored:%d" % k)
	_pump()


func _quiet() -> bool:
	if world.has_method("any_modal_open") and world.any_modal_open():
		return false
	if bool(world.get("launching")) or BloomFinale.playing or CradleAnswers.playing or Homecoming.playing:
		return false
	if map and map.is_open:
		return false
	var ld: LateDirector = LateDirector.of(world)
	return not (ld and ld.story_busy())


func _pump() -> void:
	if _busy or _queue.is_empty() or not _quiet():
		return
	var b: String = _queue.pop_front()
	_busy = true
	if b == "half":
		_doc_beat("%s_half" % _pid(), "home_half")
	elif b.begins_with("restored:"):
		_restored_beat(int(b.get_slice(":", 1)))
	_busy = false


## Shows a planet document (data/homeward.json docs) once per profile.
func _doc_beat(key: String, wren_key: String) -> void:
	if Homeward.beat_done(key):
		return
	Homeward.mark_beat(key)
	var doc: Dictionary = (Homeward.cfg().get("docs", {}) as Dictionary).get(key, {})
	Codex.unlock("homeward:" + key)
	if world.get("wren") != null:
		world.wren.say(wren_key, 1.0, true)
	if not doc.is_empty() and world.get("doc_view") != null and DisplayServer.get_name() != "headless":
		get_tree().create_timer(3.0, false).timeout.connect(func() -> void:
			if _quiet():
				world.doc_view.show_doc(doc))
	if not doc.is_empty():
		EventBus.toast.emit(tr("Intercepted: %s") % tr(str(doc.get("title", ""))), "story")


func _arrival_beat(k: int) -> void:
	if k <= 0:
		return
	var d: Dictionary = Homeward.planet_def(k)
	EventBus.toast.emit(tr("%s: %s") % [Homeward.planet_name(k), tr(str(d.get("twist", "")))], "story")
	_doc_beat("%s_arrive" % str(d["id"]), "home_arrive")
	GameState.inc_stat("planets_landed")


func _restored_beat(k: int) -> void:
	var d: Dictionary = Homeward.planet_def(k)
	Audio.play("fanfare", 0.9, -4.0)
	if world.get("patch") != null:
		Vfx.burst("big_sparkle", (world.patch as Node3D).global_position + Vector3(0, 1.5, 0), Color(0.7, 1.0, 0.6))
	var line: String = tr("%s is restored. System: %d%%.") % [Homeward.planet_name(k), int(floor(Homeward.system_pct() * 100.0 + 0.0001))]
	var rid: String = str(d.get("relic", ""))
	if rid != "":
		line += "  " + tr("Relic: %s. Heirloom pick +1 (Ark Bridge).") % tr(str(Homeward.relic_def(rid).get("name", rid)))
	EventBus.toast.emit(line, "story")
	print("[home] planet %d %s restored (system %.0f%%)" % [k, str(d["id"]), Homeward.system_pct() * 100.0])
	if k > 0:
		_doc_beat("%s_restored" % str(d["id"]), "home_restored")
	if Homeward.system_pct() >= 0.9999:
		get_tree().create_timer(9.0, false).timeout.connect(func() -> void:
			EventBus.toast.emit(tr("Every planet in the system is alive. Go back to Verdance's Cradle Returns and build the Mk VII Homeward rocket."), "story")
			if world.get("wren") != null:
				world.wren.say("home_system_done", 1.0, true))


# --- Travel (automation/rocket.gd hooks) ------------------------------------------------------

## The rocket's flight view: true when Homeward handles it (a planet trip or the home launch).
static func start_flight(w: Node, to_hub: int, dur: float) -> bool:
	if to_hub > Homeward.PLANET_BASE:
		return false
	var d: HomewardDirector = of(w)
	if to_hub == Homeward.HOME:
		var r: Variant = w.get("rocket")
		if r is Rocket:
			(r as Rocket).call("_end_cinematic")
			(r as Rocket).visible = false
		Homecoming.play_now(w)
		return true
	if d and d.map:
		d.map.fly(Homeward.current_planet(), Homeward.PLANET_BASE - to_hub, dur + 1.0)
	return true


## The rocket's hand-off after the flight: true when Homeward travels instead of a district hop.
static func travel(w: Node, to_hub: int) -> bool:
	if to_hub > Homeward.PLANET_BASE:
		return false
	if to_hub == Homeward.HOME:
		return true
	return Homeward.travel_to_planet(Homeward.PLANET_BASE - to_hub, w.get_tree())


static func launch_planet(w: Node, k: int) -> bool:
	if SystemMap.launch_blocker(w, k) != "":
		EventBus.toast.emit(SystemMap.launch_blocker(w, k), "info")
		return false
	return _launch(w, Homeward.PLANET_BASE - k)


static func _launch(w: Node, target: int) -> bool:
	if bool(w.get("launching")):
		return false
	if w.get("rocket") == null and w.has_method("_place_rocket"):
		w.call("_place_rocket", false)
	var r: Variant = w.get("rocket")
	if not (r is Rocket):
		return false
	print("[home] launch to %s" % ("the Cradle" if target == Homeward.HOME else Homeward.planet_name(Homeward.PLANET_BASE - target)))
	(r as Rocket).launch(target)
	return true


## Mk VII built and the last seed planted, at the Homeward complex.
static func home_ready(w: Node) -> bool:
	return Homeward.drive() >= 7 and bool(GameState.flags.get("home_last_seed", false)) and Homeward.at_home_site(w) and not Homeward.done()


static func launch_home(w: Node) -> bool:
	if not home_ready(w):
		return false
	return _launch(w, Homeward.HOME)


static func on_drive_built(w: Node) -> void:
	var d: HomewardDirector = of(w)
	if d:
		d._build_home_site()
	if Homeward.drive() >= 7 and w.get("wren") != null:
		w.wren.say("home_rocket", 1.0, true)


# --- The Homeward complex ----------------------------------------------------------------------

func _build_home_site() -> void:
	if not Homeward.at_home_site(world) or Homeward.drive() < 7 or _complex != null:
		return
	_complex = Node3D.new()
	_complex.name = "HomewardComplex"
	world.add_child(_complex)
	var pad: Vector3 = Rocket.PAD_POS
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.9, 0.9, 0.88)
	white.roughness = 0.3
	var green: StandardMaterial3D = Mats.lamp(Color(0.55, 1.0, 0.6), 2.2)
	# Four tall service towers with green beacons and a ring gantry around the pad.
	for i: int in 4:
		var a: float = PI * 0.25 + i * PI * 0.5
		var p: Vector3 = pad + Vector3(cos(a), 0, sin(a)) * 12.5  # [ship] outside the Mk VII's wings
		var tower := MeshInstance3D.new()
		tower.mesh = ProcMesh.box(Vector3(1.2, 26.0, 1.2))
		tower.material_override = steel
		tower.position = p + Vector3(0, 13.0, 0)
		_complex.add_child(tower)
		for h: float in [8.0, 16.0, 24.0]:
			var band := MeshInstance3D.new()
			band.mesh = ProcMesh.box(Vector3(1.5, 0.35, 1.5))
			band.material_override = white
			band.position = p + Vector3(0, h, 0)
			_complex.add_child(band)
		var lamp := MeshInstance3D.new()
		lamp.mesh = ProcMesh.sphere(0.45, 10, 6)
		lamp.material_override = green
		lamp.position = p + Vector3(0, 26.6, 0)
		_complex.add_child(lamp)
	var ring := MeshInstance3D.new()
	ring.mesh = ProcMesh.torus(12.1, 12.9, 64, 6)  # [ship]
	ring.material_override = white
	ring.position = pad + Vector3(0, 18.0, 0)
	ring.scale = Vector3(1, 0.5, 1)
	_complex.add_child(ring)
	var glow := MeshInstance3D.new()
	glow.mesh = ProcMesh.torus(12.4, 12.6, 64, 4)  # [ship]
	glow.material_override = green
	glow.position = pad + Vector3(0, 18.25, 0)
	glow.scale = Vector3(1, 0.3, 1)
	_complex.add_child(glow)
	_build_bed()
	print("[home] Homeward launch complex built")


## The last-seed bed beside the pad: E plants the last seed, then E launches home.
func _build_bed() -> void:
	if _bed != null or world.get("interactables") == null:
		return
	_bed = Node3D.new()
	_bed.name = "LastSeedBed"
	world.add_child(_bed)
	_bed.global_position = Rocket.PAD_POS + BED_OFFSET
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.95, 0.8, 0.2)  # a yellow fence, like Class 4B's school garden
	var soil := StandardMaterial3D.new()
	soil.albedo_color = Color(0.18, 0.12, 0.08)
	soil.roughness = 1.0
	var bed := MeshInstance3D.new()
	bed.mesh = ProcMesh.box(Vector3(2.0, 0.25, 2.0))
	bed.material_override = soil
	bed.position = Vector3(0, 0.12, 0)
	_bed.add_child(bed)
	for i: int in 4:
		var rail := MeshInstance3D.new()
		rail.mesh = ProcMesh.box(Vector3(2.3 if i < 2 else 0.1, 0.4, 0.1 if i < 2 else 2.3))
		rail.material_override = wood
		rail.position = Vector3(0 if i < 2 else (1.15 if i == 2 else -1.15), 0.35, (1.15 if i == 0 else -1.15) if i < 2 else 0.0)
		_bed.add_child(rail)
	var sprout := MeshInstance3D.new()
	sprout.name = "Sprout"
	sprout.mesh = ProcMesh.sphere(0.18, 10, 6)
	sprout.material_override = Mats.lamp(Color(0.5, 1.0, 0.5), 1.4)
	sprout.position = Vector3(0, 0.4, 0)
	sprout.visible = bool(GameState.flags.get("home_last_seed", false))
	_bed.add_child(sprout)
	world.interactables.register(_bed, 2.4, func() -> String:
		return tr("E   launch home") if GameState.flags.get("home_last_seed", false) else tr("E   plant the last seed"),
		_use_bed, func() -> bool: return not Homeward.done() and Homeward.drive() >= 7)


func _use_bed() -> void:
	if not GameState.flags.get("home_last_seed", false):
		GameState.flags["home_last_seed"] = true
		(_bed.get_node("Sprout") as Node3D).visible = true
		Vfx.burst("big_sparkle", _bed.global_position + Vector3(0, 0.6, 0), Color(0.6, 1.0, 0.6), 0.8)
		Audio.play("chime", 1.0, -4.0)
		GameState.inc_stat("last_seed")
		EventBus.toast.emit(tr("The last seed is in the ground. Everything is ready. Press E again here to launch home."), "story")
		if world.get("wren") != null:
			world.wren.say("home_last_seed", 1.0, true)
		return
	launch_home(world)


# --- Dev: cinematic screenshots -------------------------------------------------------------------

static var _shot_clock: float = 0.0
static var _shot_i: int = 0


## Called each frame by the Homeward cinematics with their frame delta (game time, so slow
## software rendering still frames the same moment).
static func shot_tick(dt: float) -> void:
	if not DevHooks.has("home-shots"):
		return
	_shot_clock += dt
	var times: PackedStringArray = DevHooks.get_s("home-shots", "").split(",", false)
	if _shot_i < times.size() and _shot_clock >= float(times[_shot_i]):
		DevHooks.save_viewport("screenshots/%s_%d.png" % [DevHooks.get_s("home-shot-name", "home_cine"), _shot_i])
		_shot_i += 1
		if _shot_i >= times.size():
			Engine.get_main_loop().quit()
