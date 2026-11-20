class_name RewatchCheck
extends RefCounted
## [v11film] Owner: "add rewatch option to cut scene for a little bit after it happens". Watching
## the opening film again must never change the save or the world. This plays it again in the real
## game and compares everything before and after:
##   --fresh --orbit --no-intro --rewatch-check     (headless; tools/check_rewatch.sh, check_exit)
## Cases: watched to the end; skipped in space, in the fall, just after the crash and at the hatch;
## paused with Space, resumed and skipped; started twice in a row. For each: the save (every
## system's persist_save plus GameState, as the file would be written), Lumi, the game camera, the
## real pod, the HUD, the guide marks, the sky, the music context, and what is paused, are the same
## the moment the game goes on as the moment the film started; while the film plays the game is
## stopped and Lumi is not moved; nothing of the film is left in the tree afterwards.
## Then the pause menu: the entry is there for a new game near the pod, gone after
## Intro.REWATCH_S of play and when Lumi is far from the pod, and pressing it starts the film.
## Prints [rewatch] lines, exit 1 on any failure.

const TAG: String = "[rewatch]"

static var _fails: Array[String] = []
static var _tree: SceneTree
static var _w: Node
static var _intro: Intro


static func run_dev(so: SliceOrbit) -> void:
	_tree = so.get_tree()
	_w = so.w
	_run.call_deferred()


## Dev (--rewatch-at=S): starts a rewatch S seconds after the world is up, as the Codex would.
static func run_at(so: SliceOrbit) -> void:
	_tree = so.get_tree()
	_w = so.w
	_start_at.call_deferred(DevHooks.get_f("rewatch-at", 20.0))


static func _start_at(secs: float) -> void:
	var ld: LoadingScreen = _tree.root.get_node_or_null("Loader") as LoadingScreen
	await _wait(func() -> bool: return (ld == null or not ld.busy()) and _w.has_meta("orbit_pod") and _w.get("intro") is Intro, 100000)
	await _tree.create_timer(secs, false).timeout
	_intro = _w.get("intro") as Intro
	print("%s rewatch starts %.0f s in (can_replay=%s)" % [TAG, secs, str(_intro.can_replay())])
	_intro.replay()


static func _check(ok: bool, what: String) -> void:
	print("%s %s %s" % [TAG, "ok  " if ok else "FAIL", what])
	if not ok:
		_fails.append(what)


static func _frames(n: int) -> void:
	for k: int in n:
		await _tree.process_frame


static func _wait(cond: Callable, frames: int) -> void:
	var n: int = 0
	while not bool(cond.call()) and n < frames:
		await _tree.process_frame
		n += 1


## Everything a rewatch could disturb, as text (so two can be compared and the difference shown).
static func fingerprint() -> Dictionary:
	_tree.call_group("persist", "persist_save")
	var save: Dictionary = GameState.to_dict()
	save.erase("saved_unix")
	var patch: Node3D = _w.get("patch")
	var cam: Camera3D = _tree.root.get_camera_3d()
	var site: Node3D = _w.get_meta("orbit_pod", null) if _w.has_meta("orbit_pod") else null
	var hatch: Node3D = site.get("pod").get_node_or_null("Hatch") as Node3D if site else null
	var sd: Variant = _w.get("sky_director")
	var env: Environment = (sd as SkyDirector).env if sd is SkyDirector else null
	var shown: Dictionary = {}
	for g: String in ["guide_3d", "robot", "crash_site"]:
		var vis: Array = []
		for n: Node in _tree.get_nodes_in_group(g):
			vis.append(bool(n.get("visible")))
		shown[g] = vis
	var layers: Array = []
	for n: Node in _tree.root.find_children("*", "CanvasLayer", true, false):
		if _intro == null or not (n == _intro or _intro.is_ancestor_of(n)):
			layers.append("%s:%s" % [n.name, str((n as CanvasLayer).visible)])
	return {
		"save": JSON.stringify(save, "", true),
		"lumi": var_to_str(patch.global_transform),
		"lumi_visible": patch.visible,
		"camera": var_to_str(cam.global_transform) if cam else "none",
		"camera_node": str(cam.get_path()) if cam else "none",
		"pod": var_to_str(site.global_transform) if site else "none",
		"pod_visible": site.visible if site else false,
		"hatch": snappedf(hatch.rotation.x, 0.001) if hatch else 0.0,
		"hud": bool(_w.get("hud").visible) if _w.get("hud") != null else false,
		"shown": str(shown),
		"layers": str(layers),
		"paused": _tree.paused,
		"time_scale": Engine.time_scale,
		"tunes": Tunes.context(),
		"film_dust": (sd as SkyDirector).film_dust if sd is SkyDirector else 0.0,
		"exposure": snappedf(env.tonemap_exposure, 0.0001) if env else 0.0,
		"contrast": snappedf(env.adjustment_contrast, 0.0001) if env else 0.0,
		"vfx_mode": Vfx.process_mode,
		"film_plays": Audio.film_plays,
		"world_sound_held": Audio.is_world_paused(),
		"subtitles": str(Subtitles.current.get_path()) if Subtitles.current else "none",
		"intro_mode": _intro.process_mode,
		"intro_children": _intro.get_child_count(),
		"time_played": float(GameState.stats.get("time_played", 0.0)),
	}


static func _diff(a: Dictionary, b: Dictionary) -> String:
	var out: Array[String] = []
	for k: String in a:
		if str(a[k]) != str(b.get(k)):
			var x: String = str(a[k])
			var y: String = str(b.get(k))
			if x.length() > 160:  # the save: show where it first differs
				var i: int = 0
				while i < mini(x.length(), y.length()) and x[i] == y[i]:
					i += 1
				x = "…" + x.substr(maxi(0, i - 60), 140)
				y = "…" + y.substr(maxi(0, i - 60), 140)
			out.append("%s: %s -> %s" % [k, x, y])
	return "; ".join(out)


## One rewatch: start it, do `during` (skip, pause...) and compare the world before and after.
static func _case(label: String, skip_at: float, pause_first: bool = false) -> void:
	await _frames(3)
	var before: Dictionary = fingerprint()
	var restored: Array = [{}]
	var on_restored := func() -> void: restored[0] = fingerprint()
	_intro.replay_restored.connect(on_restored, CONNECT_ONE_SHOT)
	_intro.replay()
	_check(_intro.running, "%s: the film starts" % label)
	if not _intro.running:
		if _intro.replay_restored.is_connected(on_restored):
			_intro.replay_restored.disconnect(on_restored)
		return
	var patch: Node3D = _w.get("patch")
	var at0: Transform3D = patch.global_transform
	var stopped: bool = true
	var moved: bool = false
	var shown: bool = false
	var paused_ok: bool = true
	var did_pause: bool = false
	var n: int = 0
	while _intro.busy() and n < 4000:
		await _tree.process_frame
		n += 1
		if not _intro.running:
			continue
		stopped = stopped and _tree.paused
		moved = moved or not patch.global_transform.is_equal_approx(at0)
		shown = shown or patch.visible
		var t: float = float(_intro.get("_t"))
		if pause_first and not did_pause and t > 2.0:
			did_pause = true
			var pz: StoryPause = _intro.get("_pauser")
			pz.set_paused(true)
			await _tree.process_frame  # the frame in flight still carries its own time step
			await _tree.process_frame
			var t_hold: float = float(_intro.get("_t"))
			for k: int in 12:
				await _tree.process_frame
			paused_ok = absf(float(_intro.get("_t")) - t_hold) < 0.001 and _tree.paused
			if not paused_ok:
				print("%s note: film time %.3f -> %.3f over 12 frames, time scale %.2f, pauser paused=%s, tree paused=%s" % [TAG, t_hold, float(_intro.get("_t")), Engine.time_scale, str(pz.paused), str(_tree.paused)])
			pz.set_paused(false)
		if skip_at >= 0.0 and t >= skip_at:
			_intro.skip()
	_check(not _intro.busy(), "%s: the film ends" % label)
	_check(stopped, "%s: the game is stopped the whole time the film plays" % label)
	_check(not moved and not shown, "%s: the real Lumi is not moved and not shown during the film" % label)
	if pause_first:
		_check(paused_ok, "%s: Space holds the film still (and the game stays stopped)" % label)
	var after: Dictionary = restored[0]
	_check(not after.is_empty(), "%s: the film says when the world is back" % label)
	if after.is_empty():
		return
	# The film's own nodes are freed on the next frames: those are compared a moment later.
	var kids_before: int = int(before["intro_children"])
	before.erase("intro_children")
	after.erase("intro_children")
	var d: String = _diff(before, after)
	_check(d == "", "%s: the save and the world are the same as before%s" % [label, "" if d == "" else " (" + d + ")"])
	await _frames(90)
	_check(_intro.get_child_count() == kids_before, "%s: nothing of the film is left behind (%d nodes under the film, %d before)" % [label, _intro.get_child_count(), kids_before])
	_check(not _tree.paused and Engine.time_scale > 0.0, "%s: the game goes on afterwards" % label)


static func _press(action: String) -> void:
	for down: bool in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = down
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		await _frames(4)


static func _menu() -> void:
	var pm: PauseMenu = _w.get("pause_menu")
	var patch: Node3D = _w.get("patch")
	_check(pm != null, "menu: the pause menu is there")
	if pm == null:
		return
	GameState.stats["time_played"] = 120.0
	await _press("pause")
	await _wait(func() -> bool: return pm.is_open, 60)
	_check(pm.is_open, "menu: the pause key opens the menu")
	var fb: Button = pm.find_child("FilmBtn", true, false) as Button
	_check(fb != null and fb.visible and fb.text == TranslationServer.translate("Watch the opening again"), "menu: two minutes in, by the pod, it offers \"Watch the opening again\"")
	if fb and fb.visible:
		var first: Button = pm.find_child("PhotoBtn", true, false) as Button
		var up: Node = fb.get_node_or_null(fb.focus_neighbor_top)
		var down: Node = fb.get_node_or_null(fb.focus_neighbor_bottom)
		_check(up is Button and (up as Button).visible and down is Button and (down as Button).visible and (first == null or first.visible or (up != first and down != first)), "menu: a controller can reach it (up and down lead to shown buttons)")
	pm.close_menu()
	await _frames(4)
	# After the window: gone from the pause menu (the Codex keeps it).
	GameState.stats["time_played"] = Intro.REWATCH_S + 60.0
	pm.open_menu()
	await _frames(4)
	_check(fb != null and not fb.visible, "menu: after %d minutes of play the entry is gone" % int(Intro.REWATCH_S / 60.0))
	pm.close_menu()
	await _frames(4)
	_check(_intro.can_replay(), "menu: the Codex can still start it then")
	# Far from the pod: not offered (the film is shot round the pod).
	GameState.stats["time_played"] = 120.0
	var home: Transform3D = patch.global_transform
	patch.global_position = home.origin + home.basis.z * (Intro.REWATCH_NEAR_M + 40.0)
	pm.open_menu()
	await _frames(4)
	_check(fb != null and not fb.visible and not _intro.can_replay(), "menu: far from the pod it is not offered")
	pm.close_menu()
	patch.global_transform = home
	await _frames(4)
	# Pressing it plays the film; Esc skips; the game goes on.
	pm.open_menu()
	await _frames(4)
	if fb and fb.visible:
		fb.pressed.emit()
		await _wait(func() -> bool: return _intro.running, 240)
		_check(_intro.running and _tree.paused and not pm.is_open, "menu: pressing it closes the menu and starts the film with the game stopped")
		await _frames(30)
		await _press("ui_cancel")
		await _wait(func() -> bool: return not _intro.busy(), 600)
		_check(not _intro.busy() and not _tree.paused, "menu: Esc skips it and the game goes on")
		await _frames(30)
		_check(not pm.is_open, "menu: the Esc that skipped did not also open the pause menu")
	else:
		_check(false, "menu: the entry is back two minutes in, by the pod")


static func _run() -> void:
	# The world is up when the loader is done and the pod stands.
	var ld: LoadingScreen = _tree.root.get_node_or_null("Loader") as LoadingScreen
	await _wait(func() -> bool: return (ld == null or not ld.busy()) and _w.has_meta("orbit_pod") and _w.get("intro") is Intro, 6000)
	_intro = _w.get("intro") as Intro
	_check(_intro != null and _intro.can_replay(), "the world is up and the film can be watched again")
	if _intro == null or not _intro.can_replay():
		_finish()
		return
	await _frames(60)
	var tl: Array = Intro.timeline(Intro.load_table())
	var at: Dictionary = {}
	for s: Dictionary in tl:
		at[str(s["id"])] = float(s["t0"])
	if DevHooks.get_s("rewatch-check", "") == "pause":  # dev: this case alone
		await _case("paused, resumed, skipped", 6.0, true)
		_finish()
		return
	await _case("skipped in space", 3.0)
	await _case("skipped in the fall", float(at.get("reentry", 66.0)) + 1.5)
	await _case("skipped just after the crash", float(at.get("dust", 80.0)) + 0.5)
	await _case("skipped at the hatch", float(at.get("hatch", 85.0)) + 2.5)
	await _case("paused, resumed, skipped", 6.0, true)
	await _case("watched to the end", -1.0)
	await _case("watched again at once, skipped", 20.0)
	await _menu()
	_finish()


static func _finish() -> void:
	print("%s %s: %d failure(s)" % [TAG, "PASS" if _fails.is_empty() else "FAIL", _fails.size()])
	for f: String in _fails:
		print("%s   failed: %s" % [TAG, f])
	_tree.quit(0 if _fails.is_empty() else 1)
