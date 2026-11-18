class_name WalkRadio
extends RefCounted
## [v10snd] Owner, 2026-11-15 (item 108): "the first song should play when you find a cd in the
## rubble close by at the start. It should play sun baked and tell you when you find cds you can
## play at will ... first song is after CD and player can play sun baked whenever they want."
## A new game played with real keys and mouse clicks (the reloads are tools/walk_home.gd's: the
## pause key, Quit and the title's Continue; then the autosave, a kill and Continue):
##   1. no song before the CD, even with the shuffle's wait run out; the radio key opens nothing;
##      the CD lies by the bin, in the start area, on ground Lumi can reach;
##   2. quit and Continue: still no song, the CD still lies where it lay;
##   3. Lumi drives into it (move key, scoop held): Sunbaked is the playing song at once, it is in
##      the collection, and the message names the radio key;
##   4. the radio key opens the radio; Stop stops the song; picking Sunbaked plays it again;
##   5. kill and Continue: the CD stays found, the radio is still on Sunbaked and it plays;
##   6. "Random songs": a song comes up by itself once the wait is over, never the one just heard.
## --walk-radio-clean: instead of 2-6, the CD's hex comes clean without Lumi (a robot, the 95%
## sweep): the CD is given all the same.
## --walk-radio-shots=/abs/dir (rendered) saves frames: the CD lying, the card, the radio open.
## --walk-radio[=S] (after S s, default 8): prints [walk-radio] lines, exit 1 on a failure.
## tools/check_exit.sh runs it.

static var _fails: Array[String] = []
static var _toasts: Array[String] = []
static var _live: bool = false


static func run_dev(p_so: SliceOrbit) -> void:
	if _live:  # a reload built a new world: the running walk picks it up (WalkHome._reload)
		WalkHome._reborn = p_so
		return
	_live = true
	WalkHome._bind(p_so)
	var tree: SceneTree = WalkHome.tree
	await tree.create_timer(DevHooks.get_f("walk-radio", 8.0)).timeout
	if not await WalkHome._wait_world():
		print("[walk-radio] FAIL: no objectives / Lumi")
		tree.quit(1)
		return
	EventBus.toast.connect(func(t: String, _k: String) -> void: _toasts.append(t))
	for k: int in 1200:  # WREN's brief reveals the card (the reload compares the card)
		if WalkHome.ob.revealed:
			break
		await tree.create_timer(0.25).timeout
	await tree.create_timer(1.0).timeout
	var song: String = Tunes.first_cd_id()
	_check(song == "sunbaked", "the first CD is Sunbaked and its file is there (%s)" % song)

	# 1. Before the CD.
	var spot: Vector3 = await _disc()
	_check(spot.is_finite(), "a CD lies in the junk at the start")
	if not spot.is_finite():
		return _done()
	var bin_at: Vector3 = (WalkHome.w.depot as Node3D).global_position
	_check(spot.distance_to(bin_at) <= float(Economy.read_json("res://data/start_area.json").get("radius_m", 50.0)),
		"the CD is in the start area (%.0f m from the bin)" % spot.distance_to(bin_at))
	var reach: TargetReach = TargetReach.for_world(WalkHome.w, true)
	_check(reach != null and reach.escapes(spot.normalized()), "the CD stands on ground Lumi can reach")
	await _no_song("before the CD")
	await WalkHome._tap(TunesPicker.ACTION)
	_check(not _picker().is_open, "before the CD the radio key opens nothing")

	if DevHooks.has("walk-radio-clean"):  # the CD's hex comes clean without Lumi (a robot, the 95% sweep): given all the same
		var cdf0: CdFinds = WalkHome.w.find_child("CdFinds", true, false) as CdFinds
		var hid: int = -1
		for id: Variant in CdFinds.pending():
			if str(id).begins_with(CdFinds.FIRST_KEY):
				hid = int((CdFinds.pending()[id] as Dictionary).get("hex", -1))
		_check(hid >= 0, "the CD's hex is saved (%d)" % hid)
		var far: float = WalkHome.p.global_position.distance_to(spot)
		EventBus.hex_cleaned.emit(hid, WalkHome.w.field.hex_center(hid), BigNum.new(0.0))
		await tree.create_timer(2.0).timeout
		_check(Tunes.first_cd_found() and Tunes.now_playing() == song, "its hex comes clean with Lumi %.0f m away: the CD flies to him and Sunbaked plays ('%s')" % [far, Tunes.now_playing()])
		_check(cdf0.get_node_or_null("FirstCdCard") != null and "Glim" in cdf0.first_card_text, "and the card shows")
		_check(not (await _disc(1)).is_finite() and not CdFinds.pending().keys().any(func(k: Variant) -> bool: return str(k).begins_with(CdFinds.FIRST_KEY)), "no CD is left behind")
		return _done()

	# 2. Quit and Continue.
	if not await WalkHome._reload("radio before the CD", func() -> Dictionary: return _state()):
		return
	var spot2: Vector3 = await _disc()
	_check(spot2.is_finite() and spot2.distance_to(spot) < 1.0, "after Continue the CD lies where it lay (%.1f m off)" % (spot2.distance_to(spot) if spot2.is_finite() else -1.0))
	await _no_song("after Continue, before the CD")
	if not spot2.is_finite():
		return _done()

	# 3. Drive into it.
	if DevHooks.has("walk-radio-shots") and DisplayServer.get_name() != "headless":  # a frame with the CD in view
		var cam0: Camera3D = WalkHome.w.get_viewport().get_camera_3d()
		var up0: Vector3 = spot2.normalized()
		var cf: Vector3 = -cam0.global_transform.basis.z if cam0 else bin_at - spot2
		cf = (cf - up0 * cf.dot(up0)).normalized()
		WalkHome._stand(spot2 - cf * 3.0 + up0.cross(cf).normalized() * 2.0, spot2)  # the camera behind Lumi, the CD 3 m ahead and to one side
		await _shot("cd_in_view", 3.0)
		var cam1: Camera3D = WalkHome.w.get_viewport().get_camera_3d()
		var cdn: Node3D = null
		var cdf1: Node = WalkHome.w.find_child("CdFinds", true, false)
		for c: Node in cdf1.get_children():
			if c is Node3D:
				cdn = c
		print("[walk-radio] cd_in_view: CD at screen %s (behind %s), %.1f m from the camera, %.1f m from Lumi, visible %s, scale %s, node %s" % [str(cam1.unproject_position(spot2)), str(cam1.is_position_behind(spot2)), cam1.global_position.distance_to(spot2), WalkHome.p.global_position.distance_to(spot2), str(cdn.is_visible_in_tree()) if cdn else "-", str(cdn.scale) if cdn else "-", str(cdn.get_path()) if cdn else "-"])
	_toasts.clear()
	var up: Vector3 = spot2.normalized()
	var away: Vector3 = spot2 - bin_at
	away = (away - up * away.dot(up)).normalized()
	var side: Vector3 = up.cross(away).normalized()
	var tries: Array[Vector3] = [away, side, -side, -away]
	for k: int in tries.size():  # a player who is blocked comes at it from another side
		WalkHome._stand(spot2 + tries[k] * 5.0, spot2)  # 5 m out, facing the CD
		await WalkHome._frames(6)
		if k == 0:
			_check(not Tunes.first_cd_found(), "standing 5 m away does not pick it up")
			await _shot("cd_lies", 3.0)  # the camera swings round behind him first
		var d0: float = WalkHome.p.global_position.distance_to(spot2)
		await _drive_to(spot2, 25.0)  # scooping what is in the way; the CD flies to him (0.8 s)
		if Tunes.first_cd_found():
			break
		print("[walk-radio] note: try %d: from %.1f m he got to %.1f m of the CD (paused %s)" % [k, d0, WalkHome.p.global_position.distance_to(spot2), str(tree.paused)])
	_check(Tunes.first_cd_found(), "driving into the CD picks it up")
	await _shot("cd_flying")
	await _shot("cd_card")
	_check(Tunes.now_playing() == song, "Sunbaked is the playing song at once (playing: '%s')" % Tunes.now_playing())
	_check(Tunes.is_found(song) and song in Tunes.found(), "Sunbaked is in the collection")
	var key: String = Settings.glyph(TunesPicker.ACTION)
	var cdf: Node = WalkHome.w.find_child("CdFinds", true, false)
	var said: String = str(cdf.get("first_card_text"))
	var card: Node = cdf.get_node_or_null("FirstCdCard")
	_check(card != null and said != "" and key in said and TranslationServer.translate(Tunes.title(song)) in said and "Glim" in said,
		"a card with a CD picture names the song, the radio key %s and Glim: \"%s\"" % [key, said])
	_check(not (await _disc(1)).is_finite(), "the CD is gone from the ground")

	# 4. The radio: stop, play again.
	await _radio_pick(Tunes.OFF)
	await tree.create_timer(2.5).timeout
	_check(Tunes.radio_mode() == Tunes.OFF and Tunes.now_playing() == "", "the radio's Stop stops the song (mode %s, playing '%s')" % [Tunes.radio_mode(), Tunes.now_playing()])
	var d: Node = Tunes.director()
	d.set("gap_left", 0.0)
	await tree.create_timer(2.0).timeout
	_check(Tunes.now_playing() == "", "stopped stays stopped: no song comes by itself")
	await _radio_pick(song)
	await tree.create_timer(0.5).timeout
	_check(Tunes.radio_mode() == song and Tunes.now_playing() == song, "picking Sunbaked on the radio plays it (mode %s, playing '%s')" % [Tunes.radio_mode(), Tunes.now_playing()])

	# 5. Kill and Continue.
	if not await WalkHome._reload("radio on Sunbaked", func() -> Dictionary: return _state()):
		return
	await tree.create_timer(2.0).timeout
	_check(Tunes.first_cd_found() and Tunes.is_found(song), "after Continue the CD stays found")
	_check(Radio.playing() == song and Tunes.now_playing() == song, "after Continue the radio is still on Sunbaked and it plays (radio %s, playing '%s')" % [Radio.playing(), Tunes.now_playing()])
	_check(not (await _disc(1)).is_finite(), "after Continue no second CD lies there")

	# 6. Back to random songs.
	await _radio_pick("")
	await tree.create_timer(2.5).timeout
	_check(Tunes.radio_mode() == "" and Tunes.now_playing() == "", "\"Random songs\" hands the music back: quiet first (mode '%s', playing '%s')" % [Tunes.radio_mode(), Tunes.now_playing()])
	d = Tunes.director()
	d.set("gap_left", 0.0)
	var got: String = ""
	for k: int in 80:
		got = Tunes.now_playing()
		if got != "":
			break
		await tree.create_timer(0.25).timeout
	_check(got != "" and got != song and Tunes.has_file(got), "when the wait is over a song comes by itself, not the one just heard ('%s')" % got)
	var gap: Array = Tunes.rule("gap_s", SolarSystem.current_id(), [0, 0])
	_check(float(gap[0]) >= 120.0 and float(gap[1]) <= 480.0, "the quiet between songs is 2-8 min (%s s)" % str(gap))
	_done()


static func _done() -> void:
	_fails.append_array(WalkHome._fails)
	print("[walk-radio] %s" % ("PASS" if _fails.is_empty() else "FAIL: " + "; ".join(_fails)))
	WalkHome.tree.quit(0 if _fails.is_empty() else 1)


## What must be the same after a reload.
static func _state() -> Dictionary:
	return {"first_cd": Tunes.first_cd_found(), "radio": Radio.playing(), "found": ",".join(Tunes.found())}


static func _picker() -> TunesPicker:
	return WalkHome.w.find_child("TunesPicker", true, false) as TunesPicker


## Where the first CD lies (waits up to `secs` for it to be put out); Vector3.INF when it is not out.
static func _disc(secs: int = 30) -> Vector3:
	for k: int in secs * 4:
		var cdf: Node = WalkHome.w.find_child("CdFinds", true, false)
		if cdf != null:
			var at: Vector3 = cdf.call("first_spot")
			if at.is_finite():
				return at - at.normalized() * 0.55  # its ground point
		await WalkHome.tree.create_timer(0.25).timeout
	return Vector3.INF


## No song now, and none starts when the shuffle's wait has run out.
static func _no_song(tag: String) -> void:
	var d: Node = Tunes.director()
	_check(not Tunes.first_cd_found() and Tunes.now_playing() == "", "%s: no song plays" % tag)
	d.set("gap_left", 0.0)
	await WalkHome.tree.create_timer(3.0).timeout
	_check(Tunes.now_playing() == "" and str(d.call("current")) == "", "%s: still no song when the shuffle's wait is over" % tag)
	_check(Audio.is_tunes_hushed(), "%s: the built-in score stays quiet too" % tag)


## Drives Lumi toward a spot with the move keys (as the camera sees it) and the scoop held, until
## the first CD is found or `secs` are up.
static func _drive_to(to: Vector3, secs: float) -> void:
	var tree: SceneTree = WalkHome.tree
	var held: Dictionary = {}
	var set_key: Callable = func(action: String, on: bool) -> void:
		if bool(held.get(action, false)) != on:
			held[action] = on
			WalkHome._send(action, on)
	set_key.call("scoop", true)
	for j: int in int(secs * 10.0):
		if Tunes.first_cd_found():
			break
		var cam: Camera3D = WalkHome.w.get_viewport().get_camera_3d()
		var up: Vector3 = WalkHome.p.global_position.normalized()
		var d: Vector3 = to - WalkHome.p.global_position
		d = (d - up * d.dot(up)).normalized()
		var fwd: Vector3 = -cam.global_transform.basis.z if cam else d
		fwd = (fwd - up * fwd.dot(up)).normalized()
		var right: Vector3 = fwd.cross(up).normalized()
		var z: float = d.dot(fwd)
		var x: float = d.dot(right)
		set_key.call("move_forward", z > 0.35)
		set_key.call("move_back", z < -0.35)
		set_key.call("move_right", x > 0.35)
		set_key.call("move_left", x < -0.35)
		await tree.create_timer(0.1).timeout
	for a: String in held:
		if bool(held[a]):
			WalkHome._send(a, false)
	await WalkHome._frames(4)


## The radio key, then a click on a row: "" (Random songs), Tunes.OFF (Stop) or a song id.
static func _radio_pick(id: String) -> void:
	var pk: TunesPicker = _picker()
	await WalkHome._tap(TunesPicker.ACTION)
	await WalkHome._pframes(4)
	_check(pk != null and pk.is_open, "the radio key opens the radio")
	if pk == null or not pk.is_open:
		return
	await _shot("radio_" + (id if id != "" else "random"))
	var b: Button = pk.row(id)
	_check(b != null, "the radio lists %s" % (id if id != "" else "Random songs"))
	if b == null:
		return
	await WalkHome._click(b)
	await WalkHome._pframes(4)
	_check(not pk.is_open, "a pick closes the radio")


## --walk-radio-shots=/abs/dir (rendered runs): a frame of what the player sees now.
static var _shot_n: int = 0
static func _shot(name: String, wait_s: float = 0.6) -> void:
	var dir: String = DevHooks.get_s("walk-radio-shots", "")
	if dir == "" or DisplayServer.get_name() == "headless":
		return
	await WalkHome.tree.create_timer(wait_s, true).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(dir)
	var path: String = "%s/%02d_%s.png" % [dir, _shot_n, name]
	_shot_n += 1
	WalkHome.tree.root.get_texture().get_image().save_png(path)
	print("[walk-radio] shot %s" % path)


static func _check(ok: bool, what: String) -> void:
	print("[walk-radio] %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails.append(what)
