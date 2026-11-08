class_name SoakWatch
extends Node
## [orbD] Dev QA soak for the slice on the globe (--soak). Every game minute: Lumi's position,
## distance moved, altitude over the terrain (falls through the ground / flies off), NaN checks,
## and every robot body's state; flags a stuck Lumi (pushing, under ~3 m in 3 game minutes while
## the autoplay bot drives) and robots that haven't moved in 10 minutes or sit far off the ground.
## Prints a state digest at start (after a load) and at exit, so a save -> reload mismatch shows as
## two digests that differ. Lines: "[soak] ...", "[soak] WARN ...", "[soak] digest ...".
## Also --soak-hops: once --soak-play=S game seconds have passed, hops to every hub and back to 0;
## --soak-planet=K: then the interplanet rocket to planet K.

var so: SliceOrbit
var _t: float = 0.0
var _min: int = 0
var _last_pos := Vector3.ZERO
var _hist: Array[Vector3] = []  # Lumi's position each minute
var _robot_last: Dictionary = {}  # instance id -> [pos, minutes unmoved]
var _warns: int = 0
var _phase: String = "play"


static func attach(p_so: SliceOrbit) -> SoakWatch:
	var s := SoakWatch.new()
	s.name = "SoakWatch"
	s.so = p_so
	s.process_mode = Node.PROCESS_MODE_ALWAYS
	p_so.w.add_child(s)
	return s


func _ready() -> void:
	(func() -> void: print("[soak] digest start " + digest())).call_deferred()
	so.w.tree_exiting.connect(func() -> void: print("[soak] digest exit %s (warnings %d)" % [digest(), _warns]))


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	_t += delta
	if int(_t / 60.0) > _min:
		_min = int(_t / 60.0)
		_check()
	if _phase == "play" and DevHooks.has("soak-hops") and _t >= DevHooks.get_f("soak-play", 7200.0):
		_phase = "hops"
		_hops()


## Totals that must survive a save and a reload.
func digest() -> String:
	var g: OrbitPlanet = so.globe
	var p: Patch = so.w.get("patch")
	var lp: Vector3 = p.global_position if p and p.is_inside_tree() else (_hist[_hist.size() - 1] if not _hist.is_empty() else Vector3.ZERO)
	var cubes: String = Settings.fmt(GameState.get_currency("cubes"))
	var parts: String = Settings.fmt(GameState.get_currency("parts"))
	var seeds: String = Settings.fmt(GameState.get_currency("seeds")) if GameState.has_method("get_currency") else "?"
	var f: SphereField = g.field
	var dirty: int = 0
	for c: int in g.cells.n:
		if g.cells.is_dirty(c):
			dirty += 1
	var sm: SiteManager = g.site_manager
	return "planet=%s cubes=%s parts=%s seeds=%s cleaned=%d/%d dirty_cells=%d planet%%=%.2f hub_lv=%s upgrades=%d lumi=%s" % [
		g.planet_id, cubes, parts, seeds, f.cleaned_count, f.junk_hex_count, dirty, (sm.planet_fraction() * 100.0) if sm else -1.0,
		str(Array(sm.levels)) if sm else "-", GameState.upgrades.size(), _fmt(g.to_dirh(lp)) if lp != Vector3.ZERO else "-"]


static func _fmt(a: Array) -> String:
	return "[" + ",".join(a.map(func(v: Variant) -> String: return "%.4f" % float(v))) + "]"


func _warn(msg: String) -> void:
	_warns += 1
	print("[soak] WARN t=%.0fs %s" % [_t, msg])


func _check() -> void:
	var g: OrbitPlanet = so.globe
	var p: Patch = so.w.get("patch")
	if p == null:
		return
	var pos: Vector3 = p.global_position
	if not (is_finite(pos.x) and is_finite(pos.y) and is_finite(pos.z)):
		_warn("Lumi position is NaN/inf")
		return
	var alt: float = g.terrain.altitude(pos)
	var moved: float = pos.distance_to(_last_pos) if _last_pos != Vector3.ZERO else 0.0
	_last_pos = pos
	_hist.append(pos)
	if alt < -1.5:
		_warn("Lumi %.1f m UNDER the terrain at cell %d" % [-alt, g.grid.cell_at(pos)])
	elif alt > 60.0 and not p.visible == false:
		_warn("Lumi %.1f m above the terrain" % alt)
	var bot_driving: bool = so.w.get("bot") != null and p.process_mode != Node.PROCESS_MODE_DISABLED
	if bot_driving and _hist.size() >= 4:
		var span: float = _hist[_hist.size() - 1].distance_to(_hist[_hist.size() - 4])
		if span < 3.0:
			_warn("Lumi stuck: %.1f m in 3 min at cell %d (local %s)" % [span, g.grid.cell_at(pos), _site_local(pos)])
	# Robots: every CharacterBody3D under the slice but Lumi.
	var n_bots: int = 0
	for b: Node in so.w.find_children("*", "CharacterBody3D", true, false):
		if b == p:
			continue
		n_bots += 1
		var bp: Vector3 = (b as Node3D).global_position
		if not (is_finite(bp.x) and is_finite(bp.y) and is_finite(bp.z)):
			_warn("robot %s position NaN" % b.name)
			continue
		var ba: float = g.terrain.altitude(bp)
		if ba < -1.5 or ba > 30.0:
			_warn("robot %s %.1f m %s the terrain" % [b.name, absf(ba), "under" if ba < 0 else "above"])
		var id: int = b.get_instance_id()
		var rec: Array = _robot_last.get(id, [bp, 0])
		if (rec[0] as Vector3).distance_to(bp) < 0.5:
			rec[1] = int(rec[1]) + 1
			if int(rec[1]) == 10:
				_warn("robot %s hasn't moved in 10 min (cell %d)" % [b.name, g.grid.cell_at(bp)])
		else:
			rec = [bp, 0]
		_robot_last[id] = rec
	if DevHooks.has("soak-debug"):
		var comp: Compartment = p.compartment
		var dep: Variant = so.w.get("depot")
		print("[soak] dbg fill=%.2f pending=%.2f cubing=%.2f carried=%d dump_allowed=%s baler=%s depot_patch_ok=%s depot_bare=%s d_depot=%.1f task=%s" % [
			comp.fill, comp.pending, float(p.get("_cubing")), p.carried.size(), Pace.dump_allowed(), Pace.baler_unlocked(),
			dep != null and (dep as Object).get("patch") == p, (dep as Object).get("bare") if dep else "-", (dep as Node3D).global_position.distance_to(p.global_position) if dep else -1.0,
			str((so.w.get("bot") as Object).get("_task")) if so.w.get("bot") else "-"])
	if DevHooks.has("soak-debug"):
		var hits: PackedStringArray = []
		for k: int in p.get_slide_collision_count():
			var co: Object = p.get_slide_collision(k).get_collider()
			if co is Node:
				hits.append(String((co as Node).get_path()).get_slice("/Slice/", 1))
		var ab: Variant = so.w.get("bot")
		var mo: SphereMotor = p.sphere_motor
		print("[soak] dbg hits=%s task=%s move=%s grounded=%s vv=%.2f alt=%.2f hv=%.2f vel=%.2f" % [",".join(hits), str((ab as Object).get("_task")) if ab else "-",
			str((ab as Object).get("_move")) if ab else "-", mo.grounded, mo.vv, mo.altitude, mo.hv.length(), p.velocity.length()])
	print("[soak] t=%dmin lumi moved %.0f m alt %.2f cell %d bots %d cubes %s cleaned %d" % [_min, moved, alt, g.grid.cell_at(pos), n_bots,
		Settings.fmt(GameState.get_currency("cubes")), g.field.cleaned_count])


func _site_local(pos: Vector3) -> String:
	var sm: SiteManager = so.globe.site_manager
	if sm == null or sm.nearest < 0:
		return "-"
	var l: Vector3 = (sm.sites[sm.nearest]["transform"] as Transform3D).affine_inverse() * pos
	return "hub %d (%.1f, %.1f)" % [sm.nearest, l.x, l.z]


func _hops() -> void:
	var os: OrbitSites = so.sites
	var sm: SiteManager = so.globe.site_manager
	var bot: Variant = so.w.get("bot")
	print("[soak] hops: %d hubs" % sm.sites.size())
	for i: int in range(1, sm.sites.size()) + [0]:
		var t0: int = Time.get_ticks_msec()
		var ok: bool = await os.hop_to(i)
		var d: float = (so.w.get("patch") as Node3D).global_position.distance_to(sm.pad_xf(i).origin)
		print("[soak] hop -> hub %d %s in %d ms, %.1f m from its pad" % [i, "ok" if ok else "FAIL", Time.get_ticks_msec() - t0, d])
		if not ok or d > 12.0:
			_warn("hop to hub %d: %s, %.1f m from the pad" % [i, "refused" if not ok else "landed off the pad", d])
		await get_tree().create_timer(3.0).timeout
	_phase = "after_hops"
	if DevHooks.has("soak-planet"):
		var k: int = int(DevHooks.get_f("soak-planet", 1.0))
		print("[soak] rocket to planet %d" % k)
		os.launch_planet(Homeward.PLANET_BASE - k)
