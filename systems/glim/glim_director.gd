class_name GlimDirector
extends Node
## [buddy] Wires Glim into a district (one call from scenes/slice.gd): keeps his body (GlimBot)
## beside Lumi once he's repaired, runs the hex
## scanner (GlimScan: tap glim_scan = F / LT; auto-pulse from the Auto-Scan track), the Tidy Tug
## magnet for tiny pieces, and opens the Glim panel (hold glim_scan; ui/glim_panel.gd).
## Dev hooks:
##   --glim                 Glim is already found
##   --glim-tiers=light:2,scan:3,auto:1,magnet:1   set upgrade tiers (implies --glim)
##   --glim-look=shells:sunset,glows:ember,tops:beanie   wear a look (implies --glim, unlocks it)
##   --glim-scan[=S]        pulse the scanner S game seconds after start (default 3), then every 6 s
##   --glim-scan-hold       keep the pulse parked mid-sweep (screenshots on slow renderers)
##   --glim-open[=S]        open the Glim panel after S wall-clock seconds
##   --glim-cam[=dist]      close-up camera on Glim (screenshots)
##   --glim-groove[=BPM]    Glim bobs to an imaginary song (music visuals without a song)
##   --glim-repair[=S]      [v4calm] the Repair Glim build is bought S game seconds in (default 4)
##   (--glim-cam frames the broken Glim on the pod while he isn't repaired)

const HOLD_OPEN_S: float = 0.45
## [v4calm] Owner item 43: Glim is a little helper bot who followed Lumi and clung to the pod in the
## fall. Until he's repaired (the workbench Build entry "Repair Glim", data/camp.json builds.glim)
## he hangs on the crashed pod, dark (STUCK_NAME, a broken GlimBot on the pod). Buying the repair
## sets flags.glim_repaired (the objective) and flags.glim_repair_pending; the moment itself plays
## once no menu is open: sparks, he flickers awake, a happy chirp, WREN's line, and he floats over
## to Lumi and follows from then on. He is no longer found in the junk or at dusk.
const STUCK_NAME: String = "GlimStuck"
const STUCK_GROUP: String = "glim_stuck"
## Pod-local: on the shell just right of the door (the door faces -Z), at chest height.
const STUCK_POS := Vector3(0.80, 1.22, -0.47)
const BUILD_ID: String = "glim"

var world: Node
var bot: GlimBot
var scan: GlimScan
var panel: GlimPanel
var _cooldown: float = 0.0
var _auto_t: float = 0.0
var _hold: float = -1.0
var _mag_t: float = 0.0
var _dusk_checked: bool = false
var _dev_scan_t: float = -1.0
var _pieces: int = 0
var _music_t: float = 0.0
var _moment: bool = false  # [v4calm] the repair moment is playing
var _dev_repair_at: float = -1.0  # [v4calm] --glim-repair


static func attach(slice: Node) -> GlimDirector:
	var d := GlimDirector.new()
	d.name = "GlimDirector"
	d.world = slice
	slice.add_child(d)
	d._setup()
	return d


static func of(slice: Node) -> GlimDirector:
	return slice.get_node_or_null("GlimDirector") as GlimDirector if slice else null


func _setup() -> void:
	Glim.st()  # normalise the saved state
	_dev_hooks()
	scan = GlimScan.new()
	scan.name = "GlimScan"
	scan.field = world.get("field") as HexField
	scan.world = world
	scan.hold_for_shot = DevHooks.has("glim-scan-hold")
	world.add_child(scan)
	panel = GlimPanel.new()
	panel.name = "GlimPanel"
	panel.world = world
	panel.director = self
	world.add_child(panel)
	EventBus.junk_scooped.connect(_on_scooped)
	YardBuilds.events.built.connect(_on_yard_built)  # [v4calm]
	if Glim.is_found():  # [v4calm] saves from before the repair build: he's already with Lumi
		GameState.flags["glim_repaired"] = true
		GameState.flags["glim_ready"] = true
		if not YardBuilds.built(BUILD_ID):
			YardBuilds.mark_built(BUILD_ID)
	EventBus.upgrade_bought.connect(func(id: String, _lv: int) -> void:
		if id.begins_with("glim_"):
			refresh())
	_register_cosmetics()
	if Glim.is_found():
		_spawn(false)
	if DevHooks.has("glim-scan"):
		_dev_scan_t = DevHooks.get_f("glim-scan", 3.0)
	if DevHooks.has("glim-open"):
		get_tree().create_timer(DevHooks.get_f("glim-open", 2.0), true, false, true).timeout.connect(func() -> void: panel.open_panel())
	if DevHooks.has("glim-cam"):
		_cam.call_deferred()
	if DevHooks.has("glim-repair"):  # [v4calm] wall clock, like --shot-delay
		_dev_repair_at = DevHooks.get_f("glim-repair", 4.0)


func _dev_hooks() -> void:
	if DevHooks.has("glim") or DevHooks.has("glim-tiers") or DevHooks.has("glim-look"):
		Glim.set_found(true)
	if DevHooks.has("glim-tiers"):
		for pair: String in DevHooks.get_s("glim-tiers", "").split(",", false):
			var kv: PackedStringArray = pair.split(":")
			if kv.size() == 2:
				(Glim.st()["tiers"] as Dictionary)[kv[0]] = clampi(int(kv[1]), 0, Glim.max_tier(kv[0]))
	if DevHooks.has("glim-look"):
		for pair: String in DevHooks.get_s("glim-look", "").split(",", false):
			var kv: PackedStringArray = pair.split(":")
			if kv.size() == 2 and not Glim.look(kv[0], kv[1]).is_empty():
				var key: String = Glim.key_of(kv[0], kv[1])
				if not (key in (Glim.st()["owned"] as Array)):
					(Glim.st()["owned"] as Array).append(key)
				Glim.st()[kv[0]] = kv[1]


## The Locker (ui/locker_panel.gd) lists CosmeticTargets: Glim registers his looks editor there.
## The editor finds the live director through the world it is given (the registry is static).
func _register_cosmetics() -> void:
	register_cosmetics()


## Static callables only: the registry is static and outlives this node (a lambda here would
## capture a freed director after a district change).
static func register_cosmetics() -> void:
	CosmeticTargets.register("glim", {
		"name": "Glim",
		"order": 20,
		"editor": GlimDirector.make_looks_editor,
		"unlocked": Glim.is_found,
		"hint": "Repair Glim at the workbench",  # [v4calm]
	})


static func make_looks_editor(w: Node) -> Control:
	var ed := GlimPanel.GlimLooksEditor.new()
	ed.director = GlimDirector.of(w)
	return ed


func _spawn(reveal: bool) -> void:
	if bot:
		return
	var patch: Node3D = world.get("patch") as Node3D
	bot = GlimBot.new()
	bot.name = "Glim"
	world.add_child(bot)
	bot.target = patch
	bot.sky = world.get("sky_director")
	refresh()
	if patch:
		bot.snap_to_target()
	if reveal and patch:
		# Pops out of the junk just ahead of Lumi, then floats up to his shoulder.
		var from: Vector3 = patch.global_position + (patch.global_basis * Vector3(0, 0.3, -1.1))
		bot.global_position = from
		bot.scale = Vector3.ONE * 0.05
		var tw := bot.create_tween()
		tw.tween_property(bot, "scale", Vector3.ONE * 1.15, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(bot, "scale", Vector3.ONE, 0.2)
		Vfx.burst("big_sparkle", from, Color(0.5, 0.95, 1.0))
		Audio.play("chime", 1.4, -4.0)
		bot.scanning = 1.0


## Re-applies light, look and anything that follows the upgrade tiers.
func refresh() -> void:
	if bot:
		bot.set_light(Glim.value("light", "range", 6.0), Glim.value("light", "energy", 1.1))
		bot.apply_look()


## [v4calm] A broken Glim clinging to this pod (Intro.build_pod), unless he's already repaired.
static func cling_to(pod: Node3D) -> GlimBot:
	if pod == null or Glim.is_found():
		return null
	var g := GlimBot.new()
	g.name = STUCK_NAME
	g.broken = true
	g.add_to_group(STUCK_GROUP)
	pod.add_child(g)
	g.position = STUCK_POS
	var out := Vector3(STUCK_POS.x, 0.0, STUCK_POS.z).normalized()
	g.basis = Basis.looking_at(out, Vector3.UP)  # his face (-Z) out from the shell, his back on it
	return g


## The broken Glim on the crashed pod in this world (null if there is none).
func stuck_bot() -> GlimBot:
	for n: Node in get_tree().get_nodes_in_group(STUCK_GROUP):
		if n is GlimBot and is_instance_valid(n) and world.is_ancestor_of(n):
			return n as GlimBot
	return null


func _on_yard_built(id: String) -> void:
	if id != BUILD_ID or Glim.is_found():
		return
	GameState.flags["glim_repaired"] = true
	GameState.flags["glim_repair_pending"] = true
	print("[glim] repair bought at %.1f min played" % (float(GameState.stats.get("time_played", 0.0)) / 60.0))


## [v4calm] The repair moment: short and special. Sparks on the pod, he flickers awake, a happy
## chirp, one WREN line, then he floats over to Lumi's shoulder and the lantern is his.
func play_repair() -> void:
	if _moment or Glim.is_found():
		return
	_moment = true
	GameState.flags.erase("glim_repair_pending")
	GameState.flags["glim_repaired"] = true
	var stuck: GlimBot = stuck_bot()
	var patch: Node3D = world.get("patch") as Node3D
	if stuck == null or patch == null:  # no pod here (tools): he simply appears beside Lumi
		_moment = false
		find_now("repair")
		return
	var at: Vector3 = stuck.global_position
	var up: Vector3 = OrbitUp.up(at)
	Vfx.burst("sparkle", at, Color(1.0, 0.7, 0.3), 0.9)
	Audio.play("buzz", 1.8, -14.0)
	await get_tree().create_timer(0.55).timeout
	if not is_instance_valid(stuck):
		_moment = false
		return
	Vfx.burst("sparkle", at + up * 0.1, Color(0.5, 0.95, 1.0), 1.0)
	Audio.play("charge", 1.5, -12.0)
	stuck.broken = false
	stuck.wake = 0.0
	var tw := stuck.create_tween()
	tw.tween_property(stuck, "wake", 1.0, 1.1)
	await tw.finished
	if not is_instance_valid(stuck):
		_moment = false
		return
	Vfx.burst("big_sparkle", at, Color(0.5, 0.95, 1.0))
	Audio.play("blip", 1.7, -12.0)  # a happy two-note chirp
	get_tree().create_timer(0.13).timeout.connect(func() -> void: Audio.play("blip", 2.15, -12.0))
	at = stuck.global_position
	var rot: Basis = stuck.global_basis
	stuck.queue_free()
	Glim.set_found(true)
	_spawn(false)
	bot.target = null
	bot.global_position = at
	bot.global_basis = rot
	bot.scanning = 1.0
	var w: Variant = world.get("wren")
	var line: String = tr("Glim! He held on to your pod the whole way down, just to stay with you. Welcome back, little light.")
	if w is Wren and (w as Wren).awake():
		(w as Wren).speak(line, (w as Wren).stage())
	else:
		EventBus.toast.emit(tr("Glim blinks awake. He held on to the pod the whole way down, just to stay with Lumi."), "story")
	# He floats up and over to Lumi's shoulder, then follows as usual.
	var glide := bot.create_tween()
	var from: Vector3 = at
	glide.tween_method(func(k: float) -> void:
		if bot and is_instance_valid(patch):
			var dest: Vector3 = patch.global_position + patch.global_basis.orthonormalized() * GlimBot.FOLLOW_OFFSET
			var arc: Vector3 = OrbitUp.up(dest) * sin(k * PI) * 1.2
			bot.global_position = from.lerp(dest, k * k * (3.0 - 2.0 * k)) + arc, 0.0, 1.0, 1.6)
	await glide.finished
	if bot:
		bot.target = patch
	_moment = false
	GameState.inc_stat("glim_found")
	var key: String = Settings.glyph("glim_scan")
	get_tree().create_timer(6.0).timeout.connect(func() -> void:
		EventBus.toast.emit(tr("Tap %s: Glim scans your hex for junk you missed. Hold %s for his upgrades.") % [key, key], "hint"))
	print("[glim] repaired at %.1f min played" % (float(GameState.stats.get("time_played", 0.0)) / 60.0))


func find_now(reason: String = "junk") -> void:
	if Glim.is_found():
		return
	Glim.set_found(true)
	GameState.flags["glim_repaired"] = true  # [v4calm]
	GameState.flags["glim_ready"] = true
	if not YardBuilds.built(BUILD_ID):
		YardBuilds.mark_built(BUILD_ID)
	for n: Node in get_tree().get_nodes_in_group(STUCK_GROUP):
		n.queue_free()
	_spawn(true)
	if reason == "repair":
		print("[glim] repaired (no pod in this world)")
		return
	var key: String = Settings.glyph("glim_scan")
	if reason == "dusk":
		EventBus.toast.emit(tr("A little lantern bot flickers awake in the junk beside you: Glim! He'll light the way at night."), "story")
	else:
		EventBus.toast.emit(tr("Something in the junk blinks back at you: Glim, a little lantern bot! He'll light the way at night."), "story")
	get_tree().create_timer(4.0).timeout.connect(func() -> void:
		EventBus.toast.emit(tr("Tap %s: Glim scans your hex for junk you missed. Hold %s for his upgrades.") % [key, key], "tip"))
	GameState.inc_stat("glim_found")
	print("[glim] found (%s) at %.1f min played" % [reason, float(GameState.stats.get("time_played", 0.0)) / 60.0])


func _on_scooped(_type_id: String, _pos: Vector3) -> void:
	_pieces += 1
	if Glim.is_found():
		return
	var scooped: int = _pieces + int(GameState.stats.get("glim_pieces", 0.0))
	GameState.stats["glim_pieces"] = float(scooped)
	_pieces = 0
	# [v4calm] item 43: no more finding him in the junk; the workbench repair brings him back


func _blocked() -> bool:
	if world.has_method("any_modal_open") and bool(world.call("any_modal_open")):
		return true
	if panel and panel.is_open:
		return true
	var intro: Node = world.get("intro")
	if intro and intro.has_method("busy") and bool(intro.call("busy")):
		return true
	return bool(world.get("launching")) if world.get("launching") != null else false


## The hexes a pulse covers: Lumi's own (ring 0) or the rings around it.
static func scan_hexes(f: HexField, pos: Vector3, ring: int) -> Array[int]:
	var hexes: Array[int] = []
	if ring > 0:
		hexes = f.hexes_near(pos, ring)
	else:
		hexes.append(f.hex_at(pos))
	return hexes


## Pulse the scanner over Lumi's hex (and the rings around it at higher tiers).
func do_scan(manual: bool = true) -> int:
	if bot == null or scan == null or scan.field == null:
		return -1
	var patch: Node3D = world.get("patch") as Node3D
	if patch == null:
		return -1
	var f: HexField = scan.field
	var ring: int = int(Glim.value("scan", "ring", 0.0))
	var hexes: Array[int] = scan_hexes(f, patch.global_position, ring)
	var n: int = scan.pulse(patch.global_position, hexes)
	bot.scanning = 1.0
	_cooldown = Glim.value("scan", "cooldown", 8.0)
	Audio.play("whoosh", 1.9, -14.0 if manual else -20.0)
	if DevHooks.has("glim-scan"):
		print("[glim] scan: %d hexes, %d pieces marked (%d too big), ring %d" % [hexes.size(), n, scan.last_big, ring])
	if manual:
		GameState.inc_stat("glim_scans")
		if n == 0:
			Vfx.float_text(bot.global_position + OrbitUp.up(bot.global_position) * 0.45, tr("All clear here!"), Color(0.6, 0.95, 1.0), 0.8, 0.8)
		elif scan.last_big > 0 and scan.last_big == n:
			Vfx.float_text(bot.global_position + OrbitUp.up(bot.global_position) * 0.45, tr("Only big pieces left"), Color(1.0, 0.7, 0.35), 0.8, 0.8)
	return n


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if not Glim.is_found():
		_tick_repair()  # [v4calm] (was _check_dusk: no more finding him at dusk)
		return
	if bot == null:
		_spawn(false)
	_input_poll(delta)
	# Auto-Scan: pings on his own while there's junk left in Lumi's hex.
	var every: float = Glim.value("auto", "every", 0.0)
	if every > 0.0 and not _blocked():
		_auto_t += delta
		if _auto_t >= every and not scan.active():
			_auto_t = 0.0
			var f: HexField = scan.field
			var patch: Node3D = world.get("patch") as Node3D
			if f and patch:
				var h: int = f.hex_at(patch.global_position)
				if h >= 0 and not f.is_clean(h) and f.hex_hub[h] == 0:
					do_scan(false)
	if _dev_scan_t >= 0.0:
		_dev_scan_t -= delta
		if _dev_scan_t < 0.0:
			do_scan(true)
			_dev_scan_t = 6.0
	_music_t -= delta
	if _music_t <= 0.0:  # [tunes] bob to found songs once Glim has the Music upgrade
		_music_t = 0.25
		bot.music_bpm = Glim.song_bpm() if Glim.has_music() and Glim.song_playing() != "" else 0.0
		if DevHooks.has("glim-groove"):
			bot.music_bpm = DevHooks.get_f("glim-groove", 100.0)
	_mag_t += delta
	if _mag_t >= 0.1:
		_magnet(_mag_t)
		_mag_t = 0.0


func _input_poll(delta: float) -> void:
	if world.get("bot") != null or _blocked():
		_hold = -1.0
		return
	if Input.is_action_pressed("glim_scan"):
		if _hold < 0.0:
			_hold = 0.0
		elif _hold >= 0.0:
			_hold += delta
			if _hold >= HOLD_OPEN_S:
				_hold = -2.0  # consumed until release
				panel.open_panel()
	else:
		if _hold >= 0.0 and _hold < HOLD_OPEN_S and _cooldown <= 0.0:
			do_scan(true)
		elif _hold >= 0.0 and _cooldown > 0.0:
			Audio.play("buzz", 1.6, -16.0)
			Refuse.say(tr("Glim is still scanning. Try again in a moment."))  # [v9d] say why
		_hold = -1.0


## [v4calm] Before the repair: the Build entry opens once the signal tower stands (the objective
## follows it), and a bought repair plays its moment as soon as no menu is open.
func _tick_repair() -> void:
	if _moment:
		return
	if _dev_repair_at >= 0.0 and DevHooks._elapsed >= _dev_repair_at:
		_dev_repair_at = -1.0
		GameState.flags["glim_ready"] = true
		if not YardBuilds.built(BUILD_ID):
			YardBuilds.mark_built(BUILD_ID)
			_on_yard_built(BUILD_ID)
	if not GameState.flags.get("glim_ready", false) and SignalTower.tier() >= 1:
		GameState.flags["glim_ready"] = true
	if GameState.flags.get("glim_repair_pending", false) and not _blocked():
		play_repair()


## Before he's found, the first dusk found him anyway (unused since v4calm: kept for reference).
func _check_dusk() -> void:
	var sd: Node = world.get("sky_director")
	if sd == null:
		return
	var tod: float = float(sd.get("time_of_day"))
	if tod > 0.74 and tod < 0.8 and float(GameState.stats.get("time_played", 0.0)) > 60.0:
		find_now("dusk")


## Tidy Tug: tiny pieces near Lumi scoot gently toward him (never into the hopper by themselves).
func _magnet(dt: float) -> void:
	var r: float = Glim.value("magnet", "radius", 0.0)
	if r <= 0.0:
		return
	var patch: Node3D = world.get("patch") as Node3D
	var f: HexField = scan.field
	var view: Node = world.get("view")
	if patch == null or f == null or view == null:
		return
	var max_vol: float = Glim.value("magnet", "max_vol", 0.4)
	var me: Vector3 = patch.global_position
	for pid: int in f.pieces_within(me, r):
		if f.visual_vol(pid) > max_vol:  # [orbB] by how big it looks (the globe's ledger volume is scaled)
			continue
		var to_me: Vector3 = me - f.piece_pos[pid]
		if OrbitUp.on_globe():  # [orbB] along the ground
			to_me -= OrbitUp.up(me) * to_me.dot(OrbitUp.up(me))
		else:
			to_me.y = 0.0
		var d: float = to_me.length()
		if d > 1.1:
			view.call("move_piece", pid, f.piece_pos[pid] + to_me / d * minf(1.2 * dt, d - 1.1))


func _cam() -> void:
	if bot == null:  # [v4calm] the broken Glim on the pod (and the repair moment)
		_cam_stuck()
		return
	var cam: Node = world.get("cam")
	if cam == null:
		return
	var c3: Camera3D = cam.get_viewport().get_camera_3d()
	if c3 == null:
		return
	var dist: float = DevHooks.get_f("glim-cam", 1.2)
	cam.set("input_enabled", false)
	cam.set_process(false)
	cam.set_physics_process(false)
	var follow := func() -> void:
		if bot and is_instance_valid(c3):
			var p: Vector3 = bot.global_position
			var b: Basis = Basis(Vector3.UP, (world.patch as Node3D).global_rotation.y)
			var eye: Vector3 = p + b * Vector3(-0.55, 0.18, -1.0).normalized() * dist
			c3.global_position = eye
			c3.look_at(p + Vector3(0, -0.02, 0), Vector3.UP)
			c3.fov = 40.0
	get_tree().process_frame.connect(follow)


## [v4calm] Dev: a fixed camera in front of the broken Glim on the pod; it follows him once he's up.
## Re-applied every frame (the loader and the camera rig reset the view while the world settles).
func _cam_stuck() -> void:
	var dist: float = DevHooks.get_f("glim-cam", 2.4)
	var state: Dictionary = {}
	var follow := func() -> void:
		if not state.has("eye"):
			var st: GlimBot = stuck_bot()
			if st == null:
				return
			var p0: Vector3 = st.global_position
			var up: Vector3 = OrbitUp.up(p0)
			var face: Vector3 = (st.global_basis * Vector3(0, 0, -1)).normalized()
			var side: Vector3 = face.cross(up).normalized()
			state["p0"] = p0
			state["up"] = up
			state["eye"] = p0 + (face * 1.0 + up * 0.25 + side * 0.45).normalized() * dist
			print("[glim] glim-cam on the broken Glim at %s" % str(p0))
			var own := Camera3D.new()  # our own camera: the rig keeps driving its own
			own.name = "GlimShotCam"
			world.add_child(own)
			state["cam"] = own
		var c3: Camera3D = state["cam"]
		if not c3.current:
			c3.make_current()
		var p: Vector3 = state["p0"]
		if bot and is_instance_valid(bot):
			p = bot.global_position
		c3.global_position = state["eye"]
		c3.look_at(p, state["up"])
		c3.fov = 50.0
	get_tree().process_frame.connect(follow)
