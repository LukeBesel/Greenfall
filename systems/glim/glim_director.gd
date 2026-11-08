class_name GlimDirector
extends Node
## [buddy] Wires Glim into a district (one call from scenes/slice.gd): finds him in the junk
## (Glim.ready_to_find, or at the first dusk), keeps his body (GlimBot) beside Lumi, runs the hex
## scanner (GlimScan: tap glim_scan = F / LT; auto-pulse from the Auto-Scan track), the Tidy Tug
## magnet for tiny pieces, and opens the Glim panel (hold glim_scan; ui/glim_panel.gd).
## Dev hooks:
##   --glim                 Glim is already found
##   --glim-tiers=light:2,scan:3,auto:1,magnet:1   set upgrade tiers (implies --glim)
##   --glim-look=shells:sunset,glows:ember,tops:beanie   wear a look (implies --glim, unlocks it)
##   --glim-scan[=S]        pulse the scanner S game seconds after start (default 3), then every 6 s
##   --glim-open[=S]        open the Glim panel after S wall-clock seconds
##   --glim-cam[=dist]      close-up camera on Glim (screenshots)

const HOLD_OPEN_S: float = 0.45

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
	world.add_child(scan)
	panel = GlimPanel.new()
	panel.name = "GlimPanel"
	panel.world = world
	panel.director = self
	world.add_child(panel)
	EventBus.junk_scooped.connect(_on_scooped)
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


## [style] The Locker's bot selector (systems/cosmetic_targets.gd, if that branch is merged):
## Glim registers his looks editor. Looked up by name so this file works without it.
func _register_cosmetics() -> void:
	for c: Dictionary in ProjectSettings.get_global_class_list():
		if str(c.get("class", "")) == "CosmeticTargets":
			var ct: Script = load(str(c["path"]))
			if ct:
				ct.call("register", "glim", {
					"name": "Glim",
					"order": 20,
					"editor": func(_w: Node) -> Control:
						var ed := GlimPanel.GlimLooksEditor.new()
						ed.director = self
						return ed,
					"unlocked": func() -> bool: return Glim.is_found(),
					"hint": "Find the little lantern bot in the junk",
				})
			return


func _spawn(reveal: bool) -> void:
	if bot:
		return
	var patch: Node3D = world.get("patch") as Node3D
	bot = GlimBot.new()
	bot.name = "Glim"
	world.add_child(bot)
	bot.target = patch
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


func find_now(reason: String = "junk") -> void:
	if Glim.is_found():
		return
	Glim.set_found(true)
	_spawn(true)
	var key: String = Settings.glyph("glim_scan")
	if reason == "dusk":
		EventBus.toast.emit(tr("A little lantern bot flickers awake in the junk beside you: Glim! He'll light the way at night."), "story")
	else:
		EventBus.toast.emit(tr("Something in the junk blinks back at you: Glim, a little lantern bot! He'll light the way at night."), "story")
	get_tree().create_timer(4.0).timeout.connect(func() -> void:
		EventBus.toast.emit(tr("Tap %s: Glim scans your hex for junk you missed. Hold %s for his upgrades.") % [key, key], "tip"))
	GameState.inc_stat("glim_found")


func _on_scooped(_type_id: String, _pos: Vector3) -> void:
	_pieces += 1
	if Glim.is_found():
		return
	var scooped: int = _pieces + int(GameState.stats.get("glim_pieces", 0.0))
	GameState.stats["glim_pieces"] = float(scooped)
	_pieces = 0
	if Glim.ready_to_find(float(GameState.stats.get("time_played", 0.0)), scooped):
		find_now("junk")


func _blocked() -> bool:
	if world.has_method("any_modal_open") and bool(world.call("any_modal_open")):
		return true
	if panel and panel.is_open:
		return true
	var intro: Node = world.get("intro")
	if intro and intro.has_method("busy") and bool(intro.call("busy")):
		return true
	return bool(world.get("launching")) if world.get("launching") != null else false


## Pulse the scanner over Lumi's hex (and the rings around it at higher tiers).
func do_scan(manual: bool = true) -> int:
	if bot == null or scan == null or scan.field == null:
		return -1
	var patch: Node3D = world.get("patch") as Node3D
	if patch == null:
		return -1
	var f: HexField = scan.field
	var ring: int = int(Glim.value("scan", "ring", 0.0))
	var hexes: Array[int] = f.hexes_near(patch.global_position, ring) if ring > 0 else [f.hex_at(patch.global_position)] as Array[int]
	var n: int = scan.pulse(patch.global_position, hexes)
	bot.scanning = 1.0
	_cooldown = Glim.value("scan", "cooldown", 8.0)
	Audio.play("whoosh", 1.9, -14.0 if manual else -20.0)
	if DevHooks.has("glim-scan"):
		print("[glim] scan: %d hexes, %d pieces marked (%d too big), ring %d" % [hexes.size(), n, scan.last_big, ring])
	if manual:
		GameState.inc_stat("glim_scans")
		if n == 0:
			Vfx.float_text(bot.global_position + Vector3(0, 0.45, 0), tr("All clear here!"), Color(0.6, 0.95, 1.0), 0.8, 0.8)
		elif scan.last_big > 0 and scan.last_big == n:
			Vfx.float_text(bot.global_position + Vector3(0, 0.45, 0), tr("Only big pieces left"), Color(1.0, 0.7, 0.35), 0.8, 0.8)
	return n


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if not Glim.is_found():
		_check_dusk()
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
		_hold = -1.0


## Before he's found, the first dusk finds him anyway (no one plays the night in the dark).
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
		if f.piece_vol[pid] > max_vol:
			continue
		var to_me: Vector3 = me - f.piece_pos[pid]
		to_me.y = 0.0
		var d: float = to_me.length()
		if d > 1.1:
			view.call("move_piece", pid, f.piece_pos[pid] + to_me / d * minf(1.2 * dt, d - 1.1))


func _cam() -> void:
	var cam: Node = world.get("cam")
	if bot == null or cam == null:
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
